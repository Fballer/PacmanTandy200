;==============================================================================
; ai_logic.asm -- Ghost brains  (PHASE 1)
;------------------------------------------------------------------------------
; Included from hw_defs.asm.  Do NOT add an ORG.
;
; Pure 8085.  Targeting rules are Jamey Pittman's Pac-Man Dossier:
;   Blinky (red)   : target = Pac-Man's tile
;   Pinky  (pink)  : target = 4 tiles ahead of Pac-Man
;                    (UP also subtracts 4 from X -- the 8088 overflow bug)
;   Inky   (cyan)  : pivot = 2 tiles ahead of Pac-Man (same UP bug)
;                    target = pivot + (pivot - Blinky)  i.e. 2*pivot - Blinky
;   Clyde  (orange): target = Pac-Man, but if Manhattan < 8 tiles then
;                    his bottom-left scatter corner instead
;
; Global timer alternates SCATTER and CHASE.  FRIGHTENED is a side-state:
; it REVERSES everyone, halves speed, and uses a PRNG at intersections.
; Fright PAUSES the scatter/chase timer; when it expires ghosts resume
; the mode they were in.  They do NOT reverse when leaving frightened.
;
; Intersection law
;   * Never reverse (dir XOR 2) unless the GF_REV flag was set by a mode
;     change (chase<->scatter, or either -> frightened).
;   * Upward turns forbidden in the red zone above the ghost house,
;     except while frightened.
;   * Choose the neighbor tile with the smallest Manhattan distance to
;     the target.  Ties break in order UP, LEFT, DOWN, RIGHT.
;
; Distance is |dx|+|dy| -- no multiply, no square-root, no hypot.
;==============================================================================

;==============================================================================
; AI_RESET -- call once at START and at the beginning of every new life.
; Copies pellet ROM -> RAM, parks every actor on ACTOR_INIT, loads the
; first scatter period, seeds the PRNG.
;==============================================================================
AI_RESET:
        PUSH    B
        PUSH    D
        PUSH    H

        ; pellet bitmask
        LXI     H,PELLET_INIT
        LXI     D,PELLET_BITS
        MVI     B,PELLET_BYTES
ARPEL:  MOV     A,M
        STAX    D
        INX     H
        INX     D
        DCR     B
        JNZ     ARPEL
        MVI     A,PELLET_COUNT0
        STA     PELLET_LEFT
        MVI     A,ENERG_COUNT
        STA     ENERG_LEFT
        MVI     A,0FH
        STA     ENERG_MASK
        XRA     A
        STA     SCORE
        STA     SCORE+1
        STA     SCORE+2
        STA     DOT_EATEN
        STA     CLR_KIND
        STA     DOT_GUSE
        MVI     A,3
        STA     LIVES
        MVI     A,1
        STA     LEVEL
        CALL    AI_RESET_ACTORS
        POP     H
        POP     D
        POP     B
        RET

; After a death: actors home, pellets/score/lives stay.  Dossier: the
; personal 0/30/60 clocks are abandoned.  One GLOBAL counter starts at 0
; this life (Pinky 7, Inky 17, Clyde 32).  Do not copy DOT_EATEN into
; GH_DOTCTR -- that credited Clyde with Inky's pellets and dumped all
; three out of the house after a couple of deaths.
AI_RESET_LIFE:
        PUSH    B
        PUSH    D
        PUSH    H
        MVI     A,1
        STA     DOT_GUSE
        XRA     A
        STA     DOT_GLOBAL
        STA     GHOST_PTS
        STA     CLR_KIND
        CALL    AI_RESET_ACTORS
        POP     H
        POP     D
        POP     B
        RET

AI_RESET_ACTORS:
        ; Pac-Man from ACTOR_INIT record 0
        LXI     H,ACTOR_INIT
        MOV     A,M
        STA     PAC_X
        INX     H
        MOV     A,M
        STA     PAC_Y
        INX     H
        MOV     A,M
        STA     PAC_DIR
        STA     PAC_NDIR
        INX     H                       ; skip MODE byte (Pac unused)
        INX     H
        MOV     A,M
        STA     PAC_TX
        INX     H
        MOV     A,M
        STA     PAC_TY
        INX     H
        XRA     A
        STA     PAC_ANIM
        STA     PAC_FLAGS

        ; four ghosts, 12-byte records
        XRA     A
        STA     CUR_GID
ARGH:   CALL    GHOST_BASE              ; HL -> ghost[CUR_GID]
        PUSH    H
        LDA     CUR_GID
        MOV     C,A
        CALL    ACTOR_GHOST_SRC         ; DE -> ACTOR_INIT record for this ghost
        POP     H
        LDAX    D                       ; X
        MOV     M,A
        INX     H
        INX     D
        LDAX    D                       ; Y
        MOV     M,A
        INX     H
        INX     D
        LDAX    D                       ; DIR
        MOV     M,A
        INX     H
        INX     D
        LDAX    D                       ; MODE
        MOV     M,A
        INX     H
        INX     D
        LDAX    D                       ; TX
        MOV     M,A
        INX     H
        INX     D
        LDAX    D                       ; TY
        MOV     M,A
        INX     H
        XRA     A
        MOV     M,A                     ; TARGX
        INX     H
        MOV     M,A                     ; TARGY
        INX     H
        MOV     M,A                     ; FLAGS
        INX     H
        MOV     M,A                     ; ANIM
        INX     H
        MOV     M,A                     ; DOTCTR
        INX     H
        LDA     CUR_GID
        CPI     GID_BLINKY
        MVI     A,0                     ; Blinky starts outside
        JZ      ARHOME
        MVI     A,1                     ; others start in the house
ARHOME: MOV     M,A                     ; GH_HOME
        LDA     CUR_GID
        INR     A
        STA     CUR_GID
        CPI     GHOST_COUNT
        JNZ     ARGH

        ; scatter/chase timer = first table record
        XRA     A
        STA     MODE_IDX
        CALL    MODE_LOAD

        LXI     H,0
        SHLD    FRIGHT_TMR
        SHLD    FRAME_CNT
        XRA     A
        STA     FRUIT_ON
        STA     FRUIT_TMR
        STA     ELROY
        STA     GHOST_PTS

        LXI     H,1
        SHLD    PRNG
        RET

; DE <- pointer to ACTOR_INIT + 6 + CUR_GID*6  (ghost records start at +6)
ACTOR_GHOST_SRC:
        LXI     D,ACTOR_INIT+6
        LDA     CUR_GID
        ADD     A                       ; *2
        MOV     C,A
        ADD     A                       ; *4
        ADD     C                       ; *6
        MOV     C,A
        MVI     B,0
        XCHG                            ; HL = ACTOR_INIT+6
        DAD     B
        XCHG                            ; DE = result
        RET

;==============================================================================
; MODE_LOAD -- MODE_IDX -> MODE_CUR and MODE_TMR from MODE_TABLE
; Each record is 3 bytes (mode, ticks-lo, ticks-hi).
;==============================================================================
MODE_LOAD:
        LDA     MODE_IDX
        MOV     C,A
        ADD     A                       ; *2
        ADD     C                       ; *3
        MOV     C,A
        MVI     B,0
        LXI     H,MODE_TABLE
        DAD     B
        MOV     A,M
        STA     MODE_CUR
        INX     H
        MOV     A,M
        STA     MODE_TMR
        INX     H
        MOV     A,M
        STA     MODE_TMR+1
        CALL    GHOSTS_APPLY_MODE
        RET

; Write MODE_CUR into GH_MODE for every ghost that is currently
; scattering or chasing (leave house / eyes / frightened alone).
GHOSTS_APPLY_MODE:
        XRA     A
        STA     CUR_GID
GAM1:   CALL    GHOST_BASE
        LXI     B,GH_MODE
        DAD     B
        MOV     A,M
        CPI     MODE_SCATTER
        JZ      GAMSET
        CPI     MODE_CHASE
        JNZ     GAMN
GAMSET: LDA     MODE_CUR
        MOV     M,A
GAMN:   LDA     CUR_GID
        INR     A
        STA     CUR_GID
        CPI     GHOST_COUNT
        JNZ     GAM1
        RET

;==============================================================================
; AI_TICK -- one game tick.  Phase 3 calls this every frame after input.
; Order:  maybe tick scatter/chase, release house, think, step pixels.
;==============================================================================
AI_TICK:
        PUSH    B
        PUSH    D
        PUSH    H

        LHLD    FRAME_CNT
        INX     H
        SHLD    FRAME_CNT

        CALL    MODE_TICK
        CALL    HOUSE_RELEASE
        CALL    PAC_TILES

        XRA     A
        STA     CUR_GID
AITG:   CALL    GHOST_THINK
        CALL    GHOST_STEP
        CALL    GHOST_BASE
        LXI     B,GH_MODE
        DAD     B
        MOV     A,M
        CPI     MODE_EATEN
        JNZ     AITN
        CALL    GHOST_THINK             ; eyes: second pixel this tick
        CALL    GHOST_STEP
AITN:   LDA     CUR_GID
        INR     A
        STA     CUR_GID
        CPI     GHOST_COUNT
        JNZ     AITG

        CALL    EYES_REVIVE

        POP     H
        POP     D
        POP     B
        RET

; Refresh Pac tile coords from pixels (divide by 6).
PAC_TILES:
        LDA     PAC_X
        CALL    PIX_TO_TX
        STA     PAC_TX
        LDA     PAC_Y
        CALL    PIX_TO_TY
        STA     PAC_TY
        RET

;==============================================================================
; MODE_TICK -- count down scatter/chase unless frightened (timer paused).
; On expire: advance table, SET GF_REV on every ghost that is not frightened
; and not eaten.  Dossier: reverse on chase<->scatter and *->frightened.
;==============================================================================
MODE_TICK:
        LHLD    FRIGHT_TMR
        MOV     A,H
        ORA     L
        JNZ     FRIGHT_TICK             ; frightened: pause scatter/chase

        LHLD    MODE_TMR
        MOV     A,H
        ORA     L
        RZ                              ; 0000 = already stopped
        MOV     A,H                     ; FFFF = chase forever, do not tick
        ANA     L
        INR     A
        RZ

        LHLD    MODE_TMR
        DCX     H
        SHLD    MODE_TMR
        MOV     A,H
        ORA     L
        RNZ                             ; still counting

        ; period ended -- next table slot and reverse everyone
        LDA     MODE_IDX
        INR     A
        CPI     MODE_TAB_LEN
        JC      MTADV
        MVI     A,MODE_TAB_LEN-1        ; clamp at last (chase forever)
MTADV:  STA     MODE_IDX
        CALL    MODE_LOAD               ; also applies MODE_CUR to chasing ghosts
        MVI     A,GF_REV
        CALL    GHOSTS_ORFLAG
        RET

; Count frightened time.  At zero, ghosts that were frightened go back
; to MODE_CUR (scatter or chase).  NO reverse on the way out.
FRIGHT_TICK:
        DCX     H
        SHLD    FRIGHT_TMR
        MOV     A,H
        ORA     L
        RNZ
        ; expired
        XRA     A
        STA     CUR_GID
FTG:    CALL    GHOST_BASE
        PUSH    H
        LXI     B,GH_MODE
        DAD     B
        MOV     A,M
        CPI     MODE_FRIGHT
        JNZ     FTG2
        LDA     MODE_CUR
        MOV     M,A
FTG2:   POP     H
        LDA     CUR_GID
        INR     A
        STA     CUR_GID
        CPI     GHOST_COUNT
        JNZ     FTG
        RET

; OR A into GH_FLAGS of every ghost (used to plant GF_REV).
GHOSTS_ORFLAG:
        MOV     C,A
        XRA     A
        STA     CUR_GID
GOF1:   CALL    GHOST_BASE
        PUSH    B
        LXI     B,GH_FLAGS
        DAD     B
        POP     B
        MOV     A,M
        ORA     C
        MOV     M,A
        LDA     CUR_GID
        INR     A
        STA     CUR_GID
        CPI     GHOST_COUNT
        JNZ     GOF1
        RET

;==============================================================================
; AI_FRIGHTEN -- Phase 3 calls this when Pac-Man eats an energizer.
; Reverse, enter frightened, reset ghost-points chain.  Scatter/chase pauses
; because FRIGHT_TMR becomes non-zero.
; A = frightened ticks (level-dependent; Phase 3 supplies it).
;==============================================================================
AI_FRIGHTEN:
        MOV     L,A
        MVI     H,0
        SHLD    FRIGHT_TMR
        XRA     A
        STA     GHOST_PTS
        MVI     A,GF_REV
        CALL    GHOSTS_ORFLAG
        XRA     A
        STA     CUR_GID
AFF1:   CALL    GHOST_BASE
        LXI     B,GH_MODE
        DAD     B
        MOV     A,M
        CPI     MODE_EATEN
        JZ      AFF2                    ; eyes ignore fright
        CPI     MODE_HOUSE
        JZ      AFF2                    ; still in pen: no fright yet
        MVI     M,MODE_FRIGHT
AFF2:   LDA     CUR_GID
        INR     A
        STA     CUR_GID
        CPI     GHOST_COUNT
        JNZ     AFF1
        RET

;==============================================================================
; HOUSE_RELEASE -- Dossier personal / global dot counters.
; Only one personal counter is live: Pinky, then Inky, then Clyde.
; Blinky is never in the house at level start.
;==============================================================================
HOUSE_RELEASE:
        LDA     DOT_GUSE
        ORA     A
        JNZ     HR_GLOBAL

        ; personal: first house-bound ghost in Pinky, Inky, Clyde order
        MVI     A,GID_PINKY
        CALL    HR_TRY
        RNZ
        MVI     A,GID_INKY
        CALL    HR_TRY
        RNZ
        MVI     A,GID_CLYDE
        CALL    HR_TRY
        RET

HR_GLOBAL:
        MVI     A,GID_PINKY
        MVI     C,GDOT_PINKY
        CALL    HR_GCHK
        MVI     A,GID_INKY
        MVI     C,GDOT_INKY
        CALL    HR_GCHK
        MVI     A,GID_CLYDE
        MVI     C,GDOT_CLYDE
        CALL    HR_GCHK
        RET

; A=ghost id.  If that ghost is in MODE_HOUSE and his counter >= limit,
; release him.  Returns NZ if we released (so the caller stops -- only one
; personal counter is active).
HR_TRY: STA     CUR_GID
        CALL    GHOST_BASE
        PUSH    H
        LXI     B,GH_MODE
        DAD     B
        MOV     A,M
        POP     H
        CPI     MODE_HOUSE
        JNZ     HRNO                    ; not in the pen
        ; compare DOTCTR to limit
        PUSH    H
        LXI     B,GH_DOTCTR
        DAD     B
        MOV     A,M                     ; counter
        POP     H
        MOV     B,A
        LDA     CUR_GID
        CPI     GID_PINKY
        MVI     A,DOTLIM_PINKY
        JZ      HRCMP
        LDA     CUR_GID
        CPI     GID_INKY
        MVI     A,DOTLIM_INKY
        JZ      HRCMP
        MVI     A,DOTLIM_CLYDE
HRCMP:  CMP     B                       ; A=limit, B=counter.  CY if B>A? CMP B is A-B
        ; we want release if counter >= limit  i.e. B >= A  i.e. A-B has CY or Z
        ; CMP B: A - B.  CY if A < B (counter > limit).  Z if equal.
        JZ      HRGO
        JNC     HRNO                    ; limit > counter
HRGO:   CALL    GHOST_LEAVE
        MVI     A,1
        ORA     A                       ; NZ
        RET
HRNO:   XRA     A
        RET

HR_GCHK:
        STA     CUR_GID
        LDA     DOT_GLOBAL              ; GHOST_BASE zeros B; do not keep the
        CMP     C                       ; count there across Pinky -> Inky
        RC                              ; not yet
        CALL    GHOST_BASE
        LXI     D,GH_MODE
        DAD     D
        MOV     A,M
        CPI     MODE_HOUSE
        RNZ
        CALL    GHOST_LEAVE
        RET

; Face UP (the gate).  Drop queued GF_REV.  GH_HOME=1 until they walk
; out of the box (eyes just dropped in need that too).
GHOST_LEAVE:
        CALL    GHOST_BASE
        LXI     B,GH_FLAGS
        DAD     B
        MOV     A,M
        ANI     0FDH                    ; clear GF_REV
        MOV     M,A
        CALL    GHOST_BASE
        LXI     B,GH_DIR
        DAD     B
        MVI     M,DIR_UP
        CALL    GHOST_BASE
        LXI     B,GH_HOME
        DAD     B
        MVI     M,1
        CALL    GHOST_BASE
        LXI     B,GH_MODE
        DAD     B
        LDA     MODE_CUR
        MOV     M,A
        RET

; Phase 3 calls this once per pellet Pac-Man eats.
AI_DOT_EATEN:
        LDA     DOT_GUSE
        ORA     A
        JNZ     ADE_G
        ; personal: increment the preferred house ghost's counter
        MVI     A,GID_PINKY
        CALL    ADE_INC
        RNZ
        MVI     A,GID_INKY
        CALL    ADE_INC
        RNZ
        MVI     A,GID_CLYDE
        CALL    ADE_INC
        RET
ADE_G:  LDA     DOT_GLOBAL
        INR     A
        STA     DOT_GLOBAL
        RET

; If ghost A is in the house, bump his counter and return NZ.
ADE_INC:
        STA     CUR_GID
        CALL    GHOST_BASE
        LXI     B,GH_MODE
        DAD     B
        MOV     A,M
        CPI     MODE_HOUSE
        JNZ     ADE_NO
        ; back to base, bump DOTCTR
        CALL    GHOST_BASE
        LXI     B,GH_DOTCTR
        DAD     B
        INR     M
        MVI     A,1
        ORA     A
        RET
ADE_NO: XRA     A
        RET

;==============================================================================
; GHOST_THINK -- compute target tile, then if we are on a tile center,
;               pick the next direction.
;==============================================================================
GHOST_THINK:
        CALL    GHOST_BASE
        ; update TX/TY from pixels
        MOV     A,M                     ; X
        CALL    PIX_TO_TX
        PUSH    H
        LXI     B,GH_TX
        DAD     B
        MOV     M,A
        POP     H
        INX     H
        MOV     A,M                     ; Y
        CALL    PIX_TO_TY
        DCX     H
        PUSH    H
        LXI     B,GH_TY
        DAD     B
        MOV     M,A
        POP     H

        CALL    GHOST_TARGET
        CALL    AT_CENTER
        RNZ                             ; not on a decision pixel yet
        ; Pen waiters bob in their seats.  PICKDIR toward the gate stacked
        ; Pinky/Inky/Clyde on one tile so a death looked like a missing ghost.
        CALL    GHOST_BASE
        PUSH    H
        LXI     B,GH_MODE
        DAD     B
        MOV     A,M
        POP     H
        CPI     MODE_HOUSE
        RZ
        ; pending 180 from a mode change?  Not while still in the box --
        ; that turned Pinky into the floor and he never reached a center.
        CALL    GHOST_BASE
        PUSH    H
        LXI     B,GH_HOME
        DAD     B
        MOV     A,M
        POP     H
        ORA     A
        JNZ     GTNR
        CALL    CUR_IN_HOUSE
        JZ      GTNR                    ; still in the box: do not 180
        CALL    GHOST_BASE
        LXI     B,GH_FLAGS
        DAD     B
        MOV     A,M
        ANI     GF_REV
        JZ      GTNR
        MOV     A,M
        ANI     0FDH                    ; clear GF_REV (bit 1)
        MOV     M,A
        CALL    GHOST_BASE
        LXI     B,GH_DIR
        DAD     B
        MOV     A,M
        XRI     02H                     ; reverse
        MOV     M,A
        RET
GTNR:   CALL    GHOST_PICKDIR
        RET

; Z=1 if this ghost's top-left sits on a tile (X%6==0, Y%6==1).
AT_CENTER:
        CALL    GHOST_BASE
        MOV     A,M
        CALL    DIV6
        ORA     A
        JNZ     ATCNO
        INX     H
        MOV     A,M
        CALL    DIV6
        CPI     1
        JNZ     ATCNO
        XRA     A                       ; Z=1
        RET
ATCNO:  MVI     A,1
        ORA     A                       ; Z=0
        RET

;==============================================================================
; GHOST_TARGET -- write GH_TARGX/Y for CUR_GID.
;==============================================================================
GHOST_TARGET:
        CALL    GHOST_BASE
        PUSH    H
        LXI     B,GH_HOME
        DAD     B
        MOV     A,M
        POP     H
        ORA     A
        JZ      GT_MODE
        PUSH    H
        LXI     B,GH_MODE
        DAD     B
        MOV     A,M
        POP     H
        CPI     MODE_EATEN
        JZ      TARG_HOME
        JMP     TARG_EXIT               ; still in the box: climb to the gate
GT_MODE:
        CALL    GHOST_BASE
        PUSH    H
        LXI     B,GH_MODE
        DAD     B
        MOV     A,M
        POP     H
        CPI     MODE_EATEN
        JZ      TARG_HOME
        CPI     MODE_HOUSE
        JZ      TARG_EXIT
        CPI     MODE_FRIGHT
        JZ      TARG_FRIGHT             ; picker uses PRNG; target unused
        CPI     MODE_SCATTER
        JZ      TARG_SCATTER
        ; GH_MODE is chase (or anything else treated as chase)
TARG_CHASE:
        LDA     CUR_GID
        CPI     GID_BLINKY
        JZ      TARG_BLINKY
        CPI     GID_PINKY
        JZ      TARG_PINKY
        CPI     GID_INKY
        JZ      TARG_INKY
        JMP     TARG_CLYDE

TARG_SCATTER:
        LDA     CUR_GID
        ADD     A                       ; *2
        MOV     C,A
        MVI     B,0
        LXI     H,SCATTER_XY
        DAD     B
        MOV     A,M
        STA     TMP0                    ; targ x
        INX     H
        MOV     A,M
        STA     TMP1                    ; targ y
        JMP     TARG_STORE

; Eyes: house floor.  Reverse is banned so greedy Manhattan cannot walk
; into a closer dead-end and bounce forever (see DIR_LEGAL).
TARG_HOME:
        MVI     A,9                     ; house center tile
        STA     TMP0
        MVI     A,10
        STA     TMP1
        JMP     TARG_STORE

TARG_EXIT:
        MVI     A,EXIT_TILE_X
        STA     TMP0
        MVI     A,EXIT_TILE_Y
        STA     TMP1
        JMP     TARG_STORE

TARG_FRIGHT:
        ; unused, but write Pac's tile so a bug is visible if picker fails
        LDA     PAC_TX
        STA     TMP0
        LDA     PAC_TY
        STA     TMP1
        JMP     TARG_STORE

; Blinky: Pac's tile.  (Cruise Elroy is a speed flag, not a target change.)
TARG_BLINKY:
        LDA     PAC_TX
        STA     TMP0
        LDA     PAC_TY
        STA     TMP1
        JMP     TARG_STORE

; Pinky: 4 tiles ahead.  Facing UP also subtracts 4 from X (Dossier bug).
TARG_PINKY:
        MVI     A,4
        CALL    TILE_AHEAD
        JMP     TARG_STORE

; Inky: 2* (Pac+2ahead) - Blinky
TARG_INKY:
        MVI     A,2
        CALL    TILE_AHEAD              ; TMP0/TMP1 = pivot
        ; Blinky's tile
        LXI     H,GHOST_BLINKY+GH_TX
        MOV     C,M                     ; Blinky TX
        INX     H
        MOV     B,M                     ; Blinky TY  (B=ty, C=tx) wait we wanted C=tx
        ; redo: C = blinky X, B = blinky Y
        LXI     H,GHOST_BLINKY+GH_TX
        MOV     C,M
        LXI     H,GHOST_BLINKY+GH_TY
        MOV     B,M
        ; X = 2*pivotX - blinkyX   (8-bit wrap is correct for "outside maze")
        LDA     TMP0
        ADD     A                       ; *2  (no MUL)
        SUB     C
        STA     TMP0
        LDA     TMP1
        ADD     A
        SUB     B
        STA     TMP1
        JMP     TARG_STORE

; Clyde: Pac unless Manhattan(ghost, Pac) < 8, then scatter corner.
TARG_CLYDE:
        CALL    GHOST_BASE
        LXI     B,GH_TX
        DAD     B
        MOV     B,M                     ; ghost tx
        INX     H
        MOV     D,M                     ; ghost ty
        LDA     PAC_TX
        MOV     C,A
        LDA     PAC_TY
        MOV     E,A
        CALL    MANHATTAN
        CPI     CLYDE_SHY
        JNC     TARG_BLINKY             ; distance >= 8: behave like Blinky
        ; shy: his scatter corner
        LXI     H,SCATTER_XY+6          ; Clyde is index 3, *2 = 6
        MOV     A,M
        STA     TMP0
        INX     H
        MOV     A,M
        STA     TMP1
        JMP     TARG_STORE

; TILE_AHEAD: A = N tiles.  Writes TMP0/TMP1 from Pac's tile + N * facing.
; UP applies the overflow bug: also N tiles LEFT.
TILE_AHEAD:
        STA     TMP2                    ; N
        LDA     PAC_TX
        STA     TMP0
        LDA     PAC_TY
        STA     TMP1
        LDA     PAC_DIR
        CPI     DIR_RIGHT
        JZ      TA_R
        CPI     DIR_DOWN
        JZ      TA_D
        CPI     DIR_LEFT
        JZ      TA_L
        ; UP: Y -= N, X -= N  (the bug)
        LDA     TMP1
        MOV     C,A
        LDA     TMP2
        MOV     B,A
        MOV     A,C
        SUB     B
        STA     TMP1
        LDA     TMP0
        SUB     B
        STA     TMP0
        RET
TA_R:   LDA     TMP0
        MOV     B,A
        LDA     TMP2
        ADD     B
        STA     TMP0
        RET
TA_D:   LDA     TMP1
        MOV     B,A
        LDA     TMP2
        ADD     B
        STA     TMP1
        RET
TA_L:   LDA     TMP0
        MOV     C,A
        LDA     TMP2
        MOV     B,A
        MOV     A,C
        SUB     B
        STA     TMP0
        RET

TARG_STORE:
        CALL    GHOST_BASE
        LXI     B,GH_TARGX
        DAD     B
        LDA     TMP0
        MOV     M,A
        INX     H
        LDA     TMP1
        MOV     M,A
        RET

;==============================================================================
; GHOST_PICKDIR -- choose GH_DIR at an intersection.
;==============================================================================
GHOST_PICKDIR:
        CALL    GHOST_BASE
        LXI     B,GH_MODE
        DAD     B
        MOV     A,M
        CPI     MODE_FRIGHT
        JZ      PICK_FRIGHT
        CPI     MODE_EATEN
        JZ      PICK_HOME

        MVI     A,0FFH
        STA     BEST_DIST
        STA     BEST_DIR

        LXI     H,DIR_PRI
        MVI     B,4                     ; four candidates
PKL:    MOV     A,M                     ; candidate dir
        STA     TMP3
        PUSH    H                       ; DIR_PRI cursor
        PUSH    B                       ; remaining count
        CALL    DIR_LEGAL
        JNZ     PKILL                   ; NZ = illegal
        CALL    NEXT_TILE               ; TMP4=nx TMP5=ny from TMP3 dir
        CALL    GHOST_BASE
        LXI     D,GH_TARGX
        DAD     D
        MOV     C,M                     ; targ x
        INX     H
        MOV     E,M                     ; targ y
        LDA     TMP4
        MOV     B,A
        LDA     TMP5
        MOV     D,A
        CALL    MANHATTAN
        MOV     C,A                     ; this dist
        LDA     BEST_DIST
        CMP     C                       ; A=best, C=this.  CY if best < this
        JC      PKILL                   ; this is worse
        JZ      PKILL                   ; tie: keep earlier DIR_PRI entry
        MOV     A,C
        STA     BEST_DIST
        LDA     TMP3
        STA     BEST_DIR
PKILL:  POP     B
        POP     H
        INX     H
        DCR     B
        JNZ     PKL

        LDA     BEST_DIR
        CPI     0FFH
        JNZ     PKUSE
        CALL    GHOST_BASE              ; trapped: reverse rather than walk walls
        LXI     B,GH_DIR
        DAD     B
        MOV     A,M
        XRI     02H
        MOV     M,A
        RET
PKUSE:  CALL    GHOST_BASE
        LXI     B,GH_DIR
        DAD     B
        LDA     BEST_DIR
        MOV     M,A
        RET

; Eyes: one step of the BFS tree toward (9,10).  Reverse is still banned
; in DIR_LEGAL; last-resort reverse covers "we are facing the wrong way."
PICK_HOME:
        CALL    HOME_DIR_AT
        STA     TMP3
        CALL    DIR_LEGAL
        JZ      PFUSE
        CALL    GHOST_BASE
        LXI     B,GH_DIR
        DAD     B
        MOV     A,M
        XRI     02H
        MOV     M,A
        RET

; A = HOME_DIR[ty][tx], 2 bits.  Row is 5 bytes, tx packed little-endian.
HOME_DIR_AT:
        CALL    GHOST_BASE
        LXI     B,GH_TY
        DAD     B
        MOV     A,M
        ADD     A
        ADD     A
        ADD     M                       ; ty*5
        MOV     C,A
        MVI     B,0
        DCX     H
        MOV     A,M                     ; tx
        LXI     H,HOME_DIR
        DAD     B
        MOV     C,A
        RRC
        RRC
        ANI     07H                     ; tx/4 (rows are 5 bytes, tx 0..18)
        MOV     E,A
        MVI     D,0
        DAD     D
        MOV     A,C
        ANI     03H
        INR     A
        MOV     B,A
        MOV     A,M
HDLP:   DCR     B
        JZ      HDGOT
        RRC
        RRC
        JMP     HDLP
HDGOT:  ANI     03H
        RET

; Frightened: PRNG picks a first try, then walk clockwise until legal.
PICK_FRIGHT:
        CALL    PRNG8
        ANI     03H
        STA     TMP3
        MVI     B,4
PFL:    PUSH    B
        CALL    DIR_LEGAL
        POP     B
        JZ      PFUSE
        LDA     TMP3
        INR     A
        ANI     03H                     ; clockwise
        STA     TMP3
        DCR     B
        JNZ     PFL
        RET
PFUSE:  CALL    GHOST_BASE
        LXI     B,GH_DIR
        DAD     B
        LDA     TMP3
        MOV     M,A
        RET

; DIR_LEGAL: TMP3 = candidate.  Z=1 if the ghost MAY take it.
; Rejects: reverse (not while still in the pen), walls,
; house-entry (unless eaten/leaving), forbidden UP, leaving pen early.
; Eyes must NOT reverse: greedy+reverse walks into dead-ends toward the
; house and never leaves.  Last-resort reverse is GHOST_PICKDIR only.
DIR_LEGAL:
        CALL    GHOST_BASE
        PUSH    H
        LXI     B,GH_MODE
        DAD     B
        MOV     A,M
        POP     H
        CPI     MODE_HOUSE
        JZ      DLWALL                  ; reverse is the bounce off the gate
        CALL    CUR_IN_HOUSE
        JZ      DLWALL                  ; still in the box after release
        CALL    GHOST_BASE
        LXI     B,GH_DIR
        DAD     B
        MOV     A,M
        XRI     02H                     ; reverse of current
        MOV     C,A
        LDA     TMP3
        CMP     C
        JNZ     DLWALL
        MVI     A,1
        ORA     A                       ; NZ = illegal (reverse)
        RET

DLWALL: CALL    NEXT_TILE
        LDA     TMP4                    ; nx
        MOV     D,A
        LDA     TMP5
        MOV     E,A
        CALL    TILE_WALKABLE
        RNZ                             ; NZ = wall

        ; House tiles: eyes may enter.  Pen / still-inside may stay.
        ; A ghost already outside may not walk back in (that trapped them).
        CALL    IN_HOUSE_TE             ; Z=1 if next tile is house
        JNZ     DL_OUT
        CALL    GHOST_BASE
        LXI     B,GH_MODE
        DAD     B
        MOV     A,M
        CPI     MODE_EATEN
        JZ      DLRED
        CPI     MODE_HOUSE
        JZ      DLRED
        CALL    CUR_IN_HOUSE            ; still in the box, heading out
        JZ      DLRED
        MVI     A,1
        ORA     A                       ; outside + next is house = re-entry
        RET

DL_OUT: CALL    GHOST_BASE
        LXI     B,GH_MODE
        DAD     B
        MOV     A,M
        CPI     MODE_HOUSE
        JNZ     DLRED                   ; already released: may step onto the gate
        MVI     A,1
        ORA     A                       ; pen: cannot leave until GHOST_LEAVE
        RET

; red-zone: no UP in scatter/chase
DLRED:  LDA     TMP3
        CPI     DIR_UP
        JNZ     DLOK
        CALL    GHOST_BASE
        LXI     B,GH_MODE
        DAD     B
        MOV     A,M
        CPI     MODE_FRIGHT
        JZ      DLOK                    ; frightened may turn up
        CPI     MODE_EATEN
        JZ      DLOK                    ; eyes may take any corridor home
        CALL    GHOST_BASE
        LXI     B,GH_TX
        DAD     B
        MOV     A,M                     ; current tx
        CPI     FORBID_TX0
        JC      DLOK
        CPI     FORBID_TX1+1
        JNC     DLOK
        INX     H
        MOV     A,M                     ; current ty
        CPI     FORBID_TY
        JNZ     DLOK
        MVI     A,1
        ORA     A                       ; illegal up
        RET
DLOK:   XRA     A                       ; Z=1 legal
        RET

; NEXT_TILE: from current GH_TX/TY step TMP3 dir into TMP4/TMP5.
; Applies tunnel wrap on row TUN_TY.
NEXT_TILE:
        CALL    GHOST_BASE
        LXI     B,GH_TX
        DAD     B
        MOV     A,M
        STA     TMP4
        INX     H
        MOV     A,M
        STA     TMP5
        LDA     TMP3
        MOV     C,A
        MVI     B,0
        LXI     H,DIR_DX
        DAD     B
        LDA     TMP4
        ADD     M                       ; 0FFH adds as -1 via 8-bit wrap
        STA     TMP4
        LXI     H,DIR_DY
        DAD     B
        LDA     TMP5
        ADD     M
        STA     TMP5
        ; wrap
        LDA     TMP5
        CPI     TUN_TY
        RNZ
        LDA     TMP4
        CPI     0FFH                    ; walked left from 0
        JNZ     NTW1
        MVI     A,MAP_W-1
        STA     TMP4
        RET
NTW1:   CPI     MAP_W
        RNZ
        XRA     A
        STA     TMP4
        RET

; TILE_WALKABLE: D=tx E=ty.
;   Z=1 (and A=0)  => corridor, legal to step into
;   NZ  (and A=1)  => wall or off the map
; Column 0 is the MSB of each WALK_MAP byte.  ty*3 is done with ADD, not MUL.
TILE_WALKABLE:
        MOV     A,E
        CPI     MAP_H
        JNC     TWNO
        MOV     A,D
        CPI     MAP_W
        JNC     TWNO
        MOV     A,E
        ADD     A                       ; ty*2
        ADD     E                       ; ty*3
        MOV     C,A
        MVI     B,0
        LXI     H,WALK_MAP
        DAD     B                       ; row
        MOV     A,D
        RRC
        RRC
        RRC
        ANI     03H                     ; tx/8 = which byte of the row
        MOV     C,A
        DAD     B
        MOV     A,D
        ANI     07H                     ; 0 = leftmost pixel = bit 7
        MOV     B,A
        INR     B                       ; rotate left (index+1) times
        MOV     A,M
TWROT:  RLC                             ; desired bit -> Carry
        DCR     B
        JNZ     TWROT
        JNC     TWNO                    ; bit was 0 => wall
        XRA     A                       ; Z=1 walkable
        RET
TWNO:   MVI     A,1
        ORA     A                       ; NZ=wall
        RET

; IN_HOUSE_TE: Z=1 if TMP4/TMP5 is inside the house tile box.
IN_HOUSE_TE:
        LDA     TMP4
        CPI     HOUSE_TX0
        JC      IHNO
        CPI     HOUSE_TX1+1
        JNC     IHNO
        LDA     TMP5
        CPI     HOUSE_TY0
        JC      IHNO
        CPI     HOUSE_TY1+1
        JNC     IHNO
        XRA     A                       ; Z=1 yes
        RET
IHNO:   MVI     A,1
        ORA     A
        RET

; Z=1 if this ghost's current PIXEL (not stored TX/TY) is in the house.
; Stored tiles go stale for a step and were letting freed Inky/Clyde walk
; back in.  Preserves TMP4/TMP5 (next-tile for DIR_LEGAL / GHOST_STEP).
CUR_IN_HOUSE:
        LDA     TMP4
        MOV     B,A
        LDA     TMP5
        MOV     C,A
        PUSH    B
        CALL    GHOST_BASE
        MOV     A,M
        PUSH    H
        CALL    PIX_TO_TX
        STA     TMP4
        POP     H
        INX     H
        MOV     A,M
        CALL    PIX_TO_TY
        STA     TMP5
        CALL    IN_HOUSE_TE
        POP     B
        PUSH    PSW
        MOV     A,B
        STA     TMP4
        MOV     A,C
        STA     TMP5
        POP     PSW
        RET

;==============================================================================
; GHOST_STEP -- move 1 pixel, unless frightened half-speed skip.
;==============================================================================
GHOST_STEP:
        CALL    GHOST_BASE
        LXI     B,GH_MODE
        DAD     B
        MOV     A,M
        CPI     MODE_FRIGHT
        JNZ     GSMOVE
        ; half speed: toggle GF_SKIP, skip this frame when it becomes 1
        CALL    GHOST_BASE
        LXI     B,GH_FLAGS
        DAD     B
        MOV     A,M
        XRI     GF_SKIP
        MOV     M,A
        ANI     GF_SKIP
        RNZ                             ; skipped

GSMOVE: CALL    GHOST_BASE
        LXI     B,GH_DIR
        DAD     B
        MOV     A,M
        MOV     C,A
        MVI     B,0
        LXI     H,DIR_DX
        DAD     B
        MOV     D,M                     ; dx
        LXI     H,DIR_DY
        DAD     B
        MOV     E,M                     ; dy
        CALL    GHOST_BASE
        MOV     A,M
        ADD     D
        STA     TMP0                    ; new X
        INX     H
        MOV     A,M
        ADD     E
        STA     TMP1                    ; new Y
        ; Pen waiters: top-left may stay on floor tile 10 down to Y=66,
        ; so the 6x6 body punches through the house.  Reverse at the seat.
        CALL    GHOST_BASE
        LXI     B,GH_MODE
        DAD     B
        MOV     A,M
        CPI     MODE_HOUSE
        JNZ     GS_WLK
        LDA     TMP1
        CPI     PINKY_Y0+1
        JNC     GSREV
GS_WLK: LDA     TMP0
        CALL    PIX_TO_TX
        STA     TMP4
        LDA     TMP1
        CALL    PIX_TO_TY
        STA     TMP5
        MOV     E,A
        LDA     TMP4                    ; DIV6 in PIX_TO_TY overwrote D
        MOV     D,A
        CALL    TILE_WALKABLE
        JZ      GSWLKO
GSREV:  CALL    GHOST_BASE              ; wall or illegal house: turn around
        LXI     B,GH_DIR
        DAD     B
        MOV     A,M
        XRI     02H
        MOV     M,A
        ; Eyes that slid 5px into a wall are off the decision pixel.
        ; Snap to this tile's origin so the next think can pick a way home.
        CALL    GHOST_BASE
        PUSH    H
        LXI     B,GH_MODE
        DAD     B
        MOV     A,M
        POP     H
        CPI     MODE_EATEN
        JNZ     GSANIM
        ; Top-left is still in this corridor (the step into the wall
        ; was refused).  Centre+2 was already in the wall tile, so snap
        ; was skipped and they bounced off-grid forever.
        MOV     A,M
        CALL    PIX_TO_TX
        CALL    TILE_TO_PX
        STA     TMP0
        CALL    GHOST_BASE
        INX     H
        MOV     A,M
        CALL    PIX_TO_TY
        CALL    TILE_TO_PY
        STA     TMP1
        CALL    GHOST_BASE
        LDA     TMP0
        MOV     M,A
        INX     H
        LDA     TMP1
        MOV     M,A
        JMP     GSANIM
GSWLKO: CALL    IN_HOUSE_TE             ; TMP4/5 = new tile
        JNZ     GSH_OUT
        CALL    GHOST_BASE
        LXI     B,GH_MODE
        DAD     B
        MOV     A,M
        CPI     MODE_EATEN
        JZ      GSOK
        CPI     MODE_HOUSE
        JZ      GSOK
        CALL    CUR_IN_HOUSE
        JZ      GSOK                    ; still inside, may reach the gate
        JMP     GSREV                   ; already free: do not walk back in
GSH_OUT:
        CALL    GHOST_BASE
        LXI     B,GH_MODE
        DAD     B
        MOV     A,M
        CPI     MODE_HOUSE
        JNZ     GSOK
        JMP     GSANIM                  ; pen cannot leave
GSOK:   CALL    GHOST_BASE
        LDA     TMP0
        MOV     M,A
        INX     H
        LDA     TMP1
        MOV     M,A

        ; pixel wrap in the tunnel band
        CALL    GHOST_BASE
        INX     H
        MOV     A,M                     ; Y
        CPI     TUN_Y0
        JC      GSHOME
        CPI     TUN_Y1+1
        JNC     GSHOME
        DCX     H                       ; back to X
        MOV     A,M
        CPI     BORDER_X0               ; walked left from MAZE_X0
        JNZ     GSW1
        MVI     M,PF_XMAX
        JMP     GSHOME
GSW1:   CPI     PF_XWRAP
        JNZ     GSHOME
        MVI     A,MAZE_X0
        MOV     M,A

GSHOME: ; if we have left the house pixel box, clear GH_HOME
        CALL    GHOST_BASE
        MOV     A,M
        CALL    PIX_TO_TX
        STA     TMP4
        INX     H
        MOV     A,M
        CALL    PIX_TO_TY
        STA     TMP5
        MOV     E,A
        LDA     TMP4                    ; D was ty after PIX_TO_TY
        MOV     D,A
        CALL    IN_HOUSE_TE
        JZ      GSANIM                  ; still inside
        CALL    GHOST_BASE
        LXI     B,GH_HOME
        DAD     B
        MVI     M,0
GSANIM: CALL    GHOST_BASE
        LXI     B,GH_ANIM
        DAD     B
        INR     M
        RET

;==============================================================================
; GHOST_BASE -- HL = GHOSTS + CUR_GID * 12
; 12 = 8+4, all shifts/adds.  Preserves CUR_GID.  Destroys A, BC.
;==============================================================================
GHOST_BASE:
        LDA     CUR_GID
        ADD     A                       ; *2
        ADD     A                       ; *4
        MOV     C,A
        ADD     A                       ; *8
        ADD     C                       ; *12
        MOV     C,A
        MVI     B,0
        LXI     H,GHOSTS
        DAD     B
        RET

;==============================================================================
; PRNG8 -- 16-bit Galois LFSR, return A = next byte.
; Polynomial tap 0xB400 on the high side, cheap on 8085.
;==============================================================================
PRNG8:  PUSH    H
        LHLD    PRNG
        MOV     A,L
        RRC
        MOV     L,A
        MOV     A,H
        RAR
        MOV     H,A
        JNC     PRNGS
        MOV     A,L
        XRI     00H
        MOV     L,A
        MOV     A,H
        XRI     0B4H
        MOV     H,A
PRNGS:  SHLD    PRNG
        MOV     A,L
        POP     H
        RET
