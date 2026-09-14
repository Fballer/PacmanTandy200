;==============================================================================
; main.asm -- Game loop  (PHASE 3)
;------------------------------------------------------------------------------
; Included from hw_defs.asm.  Do NOT add an ORG.
;
; One pass of GAME_LOOP is one "tick":
;   1. Read the Tandy 200 keyboard (BREAK = quit)
;   2. Buffer Pac-Man's next direction from the arrows
;   3. Move Pac-Man 1 pixel (reverse any time; other turns at tile center)
;   4. AI_TICK -- scatter/chase timer, house release, ghost think+step
;   5. Pellet / energizer / fruit collision
;   6. Ghost touch: eat if blue, else lose a life
;   7. Dirty-rect erase, clear eaten dots on the LCD, redraw sprites
;
; Pac-Man is NOT blocked from reversing (ghosts are).  He cannot enter
; the ghost house.  Warp tunnels wrap X=0 <-> 191 on tile row TUN_TY.
;
; Score is 3-byte packed BCD (ones in SCORE+0).  10 / 50 / 100 / 200...
; added with DAA.  There is no HUD font yet; SCORE is in RAM for Phase 4.
;==============================================================================

FRIGHT_TICKS    EQU     255             ; 8-bit max; ~4s at 60Hz, longer on LCD
FRUIT_TICKS     EQU     90              ; fruit visible time
FRUIT_DOT1      EQU     50              ; first fruit after this many pellets
FRUIT_DOT2      EQU     100             ; second fruit
CLR_PELLET      EQU     1
CLR_ENERG       EQU     2
CLR_FRUIT       EQU     3

GST_PLAY        EQU     0
GST_OVER        EQU     1

;==============================================================================
; GAME_LOOP -- does not return until BREAK.  START JMPs here, then EXIT.
;==============================================================================
GAME_LOOP:
        XRA     A
        STA     GAME_STATE
        STA     CLR_KIND

GLTICK: CALL    KEYSCAN
        LDA     KEY_FLAGS
        ANI     KEY_EXIT
        RNZ                             ; BREAK -> return to START's EXIT

        LDA     GAME_STATE
        CPI     GST_OVER
        JZ      GLTICK                  ; freeze until BREAK

        CALL    PAC_INPUT
        CALL    PAC_MOVE
        CALL    AI_TICK
        CALL    EYES_REVIVE
        CALL    PELLET_TRY
        CALL    ENERG_TRY
        CALL    FRUIT_LOGIC
        CALL    GHOST_HIT
        LDA     GAME_STATE
        CPI     GST_OVER
        JZ      GLTICK
        LDA     GAME_STATE
        CPI     0FFH                    ; 0FFH = just died, actors already reset
        JNZ     GLDRAW
        XRA     A
        STA     GAME_STATE
        CALL    SPRITES_INIT
        JMP     GLTICK

GLDRAW: CALL    CHECK_LEVEL
        DI
        CALL    SPRITES_ERASE
        CALL    FLUSH_CLR
        CALL    SPRITES_PAINT
        EI
        CALL    FRAME_DELAY
        JMP     GLTICK

;==============================================================================
; PAC_INPUT -- arrows set PAC_NDIR.  Last matching key in this order wins
; (Right, so a Right+Up chord goes right).  No key = keep previous NDIR.
;==============================================================================
PAC_INPUT:
        LDA     KEY_FLAGS
        MOV     B,A
        ANI     KEY_UP
        JZ      PI_DN
        MVI     A,DIR_UP
        STA     PAC_NDIR
PI_DN:  MOV     A,B
        ANI     KEY_DOWN
        JZ      PI_LF
        MVI     A,DIR_DOWN
        STA     PAC_NDIR
PI_LF:  MOV     A,B
        ANI     KEY_LEFT
        JZ      PI_RT
        MVI     A,DIR_LEFT
        STA     PAC_NDIR
PI_RT:  MOV     A,B
        ANI     KEY_RIGHT
        RZ
        MVI     A,DIR_RIGHT
        STA     PAC_NDIR
        RET

;==============================================================================
; PAC_MOVE -- 1 pixel.  Reverse is allowed mid-tile.  Other turns only when
; the sprite center sits on a tile center (x&7==4, y&7==4).
;==============================================================================
PAC_MOVE:
        ; reverse requested?
        LDA     PAC_DIR
        XRI     02H
        MOV     B,A
        LDA     PAC_NDIR
        CMP     B
        JNZ     PM_CTR
        STA     PAC_DIR
        JMP     PM_STEP

PM_CTR: CALL    PAC_AT_CENTER
        JNZ     PM_STEP                 ; mid-tile: keep current dir
        LDA     PAC_NDIR
        CALL    PAC_CAN_GO
        JNZ     PM_FWD                  ; NDIR blocked
        LDA     PAC_NDIR
        STA     PAC_DIR
        JMP     PM_STEP
PM_FWD: LDA     PAC_DIR
        CALL    PAC_CAN_GO
        RNZ                             ; both blocked: sit still

PM_STEP:
        LDA     PAC_DIR
        MOV     C,A
        MVI     B,0
        LXI     H,DIR_DX
        DAD     B
        LDA     PAC_X
        ADD     M
        STA     PAC_X
        LXI     H,DIR_DY
        DAD     B
        LDA     PAC_Y
        ADD     M
        STA     PAC_Y
        ; tunnel wrap (pixel)
        LDA     PAC_Y
        CPI     TUN_Y0
        JC      PM_ANIM
        CPI     TUN_Y1+1
        JNC     PM_ANIM
        LDA     PAC_X
        CPI     0FFH
        JNZ     PM_W1
        MVI     A,PF_XMAX
        STA     PAC_X
        JMP     PM_ANIM
PM_W1:  CPI     192
        JNZ     PM_ANIM
        XRA     A
        STA     PAC_X
PM_ANIM:
        LDA     PAC_ANIM
        INR     A
        STA     PAC_ANIM
        JMP     PAC_TILES               ; keep TX/TY in sync

; Z=1 if Pac is on a decision pixel.
PAC_AT_CENTER:
        LDA     PAC_X
        ANI     TILE_MASK
        CPI     TILE_CENTER
        JNZ     PACNO
        LDA     PAC_Y
        ANI     TILE_MASK
        CPI     TILE_CENTER
        JNZ     PACNO
        XRA     A
        RET
PACNO:  MVI     A,1
        ORA     A
        RET

; PAC_CAN_GO: A = dir.  Z=1 if the NEXT tile is a corridor and not the house.
PAC_CAN_GO:
        STA     TMP3
        LDA     PAC_TX
        STA     TMP4
        LDA     PAC_TY
        STA     TMP5
        LDA     TMP3
        MOV     C,A
        MVI     B,0
        LXI     H,DIR_DX
        DAD     B
        LDA     TMP4
        ADD     M
        STA     TMP4
        LXI     H,DIR_DY
        DAD     B
        LDA     TMP5
        ADD     M
        STA     TMP5
        LDA     TMP5
        CPI     TUN_TY
        JNZ     PCGW
        LDA     TMP4
        CPI     0FFH
        JNZ     PCGW1
        MVI     A,MAP_W-1
        STA     TMP4
        JMP     PCGW
PCGW1:  CPI     MAP_W
        JNZ     PCGW
        XRA     A
        STA     TMP4
PCGW:   LDA     TMP4
        MOV     D,A
        LDA     TMP5
        MOV     E,A
        CALL    TILE_WALKABLE
        RNZ                             ; NZ = wall
        CALL    IN_HOUSE_TE
        JZ      PCGNO                   ; house: Pac may not enter
        XRA     A                       ; Z = ok
        RET
PCGNO:  MVI     A,1
        ORA     A
        RET

;==============================================================================
; PELLET_TRY -- if we are centered on a still-present pellet, eat it.
;==============================================================================
PELLET_TRY:
        CALL    PAC_AT_CENTER
        RNZ
        LDA     PAC_TY
        MOV     D,A
        LXI     H,PELLET_Y
        MVI     C,0
PTF:    MOV     A,M
        CMP     D
        JZ      PTGOT
        INX     H
        INR     C
        MOV     A,C
        CPI     PELLET_ROWS
        JNZ     PTF
        RET                             ; not a pellet row
PTGOT:  MOV     A,C
        ADD     A
        ADD     C                       ; row * 3
        MOV     C,A
        MVI     B,0
        LXI     H,PELLET_BITS
        DAD     B
        LDA     PAC_TX
        RRC
        RRC
        RRC
        ANI     03H
        MOV     C,A
        MVI     B,0
        DAD     B                       ; HL -> byte
        LDA     PAC_TX
        ANI     07H
        MOV     E,A
        MVI     D,0
        PUSH    H
        LXI     H,BITMSK
        DAD     D
        MOV     A,M                     ; mask
        POP     H
        MOV     B,A
        MOV     A,M
        ANA     B
        RZ                              ; already 0
        MOV     A,B
        CMA
        ANA     M
        MOV     M,A                     ; clear bit
        LDA     PELLET_LEFT
        DCR     A
        STA     PELLET_LEFT
        LDA     DOT_EATEN
        INR     A
        STA     DOT_EATEN
        MVI     A,10H                   ; BCD 10 points
        CALL    ADD_BCD_LO
        CALL    AI_DOT_EATEN
        LDA     PAC_TX
        CALL    TILE_TO_PIX
        STA     CLR_X
        LDA     PAC_TY
        CALL    TILE_TO_PIX
        STA     CLR_Y
        MVI     A,CLR_PELLET
        STA     CLR_KIND
        RET

;==============================================================================
; ENERG_TRY -- corner power pellets.
;==============================================================================
ENERG_TRY:
        CALL    PAC_AT_CENTER
        RNZ
        LXI     H,ENERG_XY
        MVI     C,0                     ; index 0..3
ET1:    MOV     A,C
        CPI     ENERG_COUNT
        RZ
        MOV     A,M
        INX     H
        CALL    PIX_TO_TILE
        MOV     B,A                     ; tx
        MOV     A,M
        INX     H
        CALL    PIX_TO_TILE             ; ty
        MOV     D,A
        LDA     PAC_TX
        CMP     B
        JNZ     ETN
        LDA     PAC_TY
        CMP     D
        JNZ     ETN
        ; matching tile -- still present?
        LDA     ENERG_MASK
        MOV     B,A
        MOV     A,C
        INR     A
        MOV     E,A                     ; E = index+1
        MVI     A,01H
ETSH:   DCR     E
        JZ      ETBIT
        ADD     A                       ; shift bit
        JMP     ETSH
ETBIT:  MOV     E,A                     ; bit
        ANA     B
        RZ                              ; already eaten
        MOV     A,E
        CMA
        ANA     B
        STA     ENERG_MASK
        LDA     ENERG_LEFT
        DCR     A
        STA     ENERG_LEFT
        MVI     A,50H                   ; BCD 50
        CALL    ADD_BCD_LO
        XRA     A
        STA     GHOST_PTS
        MVI     A,FRIGHT_TICKS
        CALL    AI_FRIGHTEN
        DCX     H
        DCX     H
        MOV     A,M
        STA     CLR_X
        INX     H
        MOV     A,M
        STA     CLR_Y
        MVI     A,CLR_ENERG
        STA     CLR_KIND
        RET
ETN:    INR     C
        JMP     ET1

;==============================================================================
; FRUIT_LOGIC -- spawn at 50 and 100 pellets, timeout, or eat for 100 pts.
;==============================================================================
FRUIT_LOGIC:
        LDA     FRUIT_ON
        ORA     A
        JNZ     FR_ON
        LDA     DOT_EATEN
        CPI     FRUIT_DOT1
        JZ      FR_SP
        CPI     FRUIT_DOT2
        JZ      FR_SP
        RET
FR_SP:  MVI     A,1
        STA     FRUIT_ON
        MVI     A,FRUIT_TICKS
        STA     FRUIT_TMR
        MVI     A,CLR_FRUIT             ; reuse as "draw" by plotting
        ; fruit plus is already on the maze from RENDER; just activate
        RET

FR_ON:  ; eat?
        LDA     PAC_X
        MOV     B,A
        MVI     C,FRUIT_X
        CALL    ABS_DIFF
        CPI     6
        JNC     FR_TMR
        LDA     PAC_Y
        MOV     B,A
        MVI     C,FRUIT_Y
        CALL    ABS_DIFF
        CPI     6
        JNC     FR_TMR
        ; eaten
        MVI     A,01H                   ; BCD 100 -> add 1 to middle digit byte
        CALL    ADD_BCD_MID
        XRA     A
        STA     FRUIT_ON
        MVI     A,FRUIT_X
        STA     CLR_X
        MVI     A,FRUIT_Y
        STA     CLR_Y
        MVI     A,CLR_FRUIT
        STA     CLR_KIND
        RET
FR_TMR: LDA     FRUIT_TMR
        DCR     A
        STA     FRUIT_TMR
        RNZ
        XRA     A
        STA     FRUIT_ON
        MVI     A,FRUIT_X
        STA     CLR_X
        MVI     A,FRUIT_Y
        STA     CLR_Y
        MVI     A,CLR_FRUIT
        STA     CLR_KIND
        RET

;==============================================================================
; GHOST_HIT -- same tile as Pac-Man.
;==============================================================================
GHOST_HIT:
        XRA     A
        STA     CUR_GID
GH1:    CALL    GHOST_BASE
        LXI     B,GH_TX
        DAD     B
        MOV     A,M
        MOV     B,A
        LDA     PAC_TX
        CMP     B
        JNZ     GHN
        INX     H
        MOV     A,M
        MOV     B,A
        LDA     PAC_TY
        CMP     B
        JNZ     GHN
        ; same tile
        CALL    GHOST_BASE
        LXI     B,GH_MODE
        DAD     B
        MOV     A,M
        CPI     MODE_FRIGHT
        JZ      GH_EAT
        CPI     MODE_EATEN
        JZ      GHN
        CPI     MODE_HOUSE
        JZ      GHN
        JMP     LIFE_LOST
GH_EAT: MVI     M,MODE_EATEN
        CALL    GHOST_BASE
        LXI     B,GH_FLAGS
        DAD     B
        MOV     A,M
        ORI     GF_REV
        MOV     M,A
        LDA     GHOST_PTS
        CPI     4
        JNC     GH_SC
        MOV     E,A
        INR     A
        STA     GHOST_PTS
        ; 200/400/800/1600 -> BCD 02/04/08/16 on the middle-high pair
        LXI     H,GHOST_BCD
        MVI     D,0
        DAD     D
        MOV     A,M
        CALL    ADD_BCD_MID
GH_SC:
GHN:    LDA     CUR_GID
        INR     A
        STA     CUR_GID
        CPI     GHOST_COUNT
        JNZ     GH1
        RET

GHOST_BCD:
        DB      02H,04H,08H,16H         ; 200,400,800,1600 in the 00xx00 slots

;==============================================================================
; LIFE_LOST / CHECK_LEVEL / EYES_REVIVE
;==============================================================================
LIFE_LOST:
        LDA     LIVES
        DCR     A
        STA     LIVES
        JZ      LF_OVER
        CALL    AI_RESET_LIFE
        MVI     A,0FFH                  ; tell GAME_LOOP to SPRITES_INIT
        STA     GAME_STATE
        RET
LF_OVER:
        MVI     A,GST_OVER
        STA     GAME_STATE
        RET

CHECK_LEVEL:
        LDA     PELLET_LEFT
        ORA     A
        RNZ
        LDA     ENERG_LEFT
        ORA     A
        RNZ
        ; board clear
        LDA     LEVEL
        INR     A
        STA     LEVEL
        LDA     LIVES
        STA     TMP7                    ; preserve
        LDA     SCORE
        STA     TMP0
        LDA     SCORE+1
        STA     TMP1
        LDA     SCORE+2
        STA     TMP2
        LDA     LEVEL
        STA     TMP6
        CALL    AI_RESET                ; full maze reset
        LDA     TMP7
        STA     LIVES
        LDA     TMP6
        STA     LEVEL
        LDA     TMP0
        STA     SCORE
        LDA     TMP1
        STA     SCORE+1
        LDA     TMP2
        STA     SCORE+2
        CALL    RENDER_MAZE
        CALL    SPRITES_INIT
        RET

; Eyes that have reached the house become the current scatter/chase mode
; and walk out the gate.
EYES_REVIVE:
        XRA     A
        STA     CUR_GID
EV1:    CALL    GHOST_BASE
        PUSH    H
        LXI     B,GH_MODE
        DAD     B
        MOV     A,M
        POP     H
        CPI     MODE_EATEN
        JNZ     EVN
        CALL    GHOST_BASE
        LXI     B,GH_TX
        DAD     B
        MOV     A,M
        STA     TMP4
        INX     H
        MOV     A,M
        STA     TMP5
        CALL    IN_HOUSE_TE
        JNZ     EVN
        CALL    GHOST_LEAVE
EVN:    LDA     CUR_GID
        INR     A
        STA     CUR_GID
        CPI     GHOST_COUNT
        JNZ     EV1
        RET

;==============================================================================
; FLUSH_CLR -- after SPRITES_ERASE, punch eaten dots out of VRAM.
;==============================================================================
FLUSH_CLR:
        LDA     CLR_KIND
        ORA     A
        RZ
        CPI     CLR_PELLET
        JZ      FC_PIX
        CPI     CLR_ENERG
        JZ      FC_3
        ; fruit plus: center + 4 neighbors
        LDA     CLR_X
        MOV     B,A
        LDA     CLR_Y
        MOV     C,A
        CALL    PLOT_CLR
        LDA     CLR_X
        MOV     B,A
        LDA     CLR_Y
        DCR     A
        MOV     C,A
        CALL    PLOT_CLR
        LDA     CLR_X
        MOV     B,A
        LDA     CLR_Y
        INR     A
        MOV     C,A
        CALL    PLOT_CLR
        LDA     CLR_X
        DCR     A
        MOV     B,A
        LDA     CLR_Y
        MOV     C,A
        CALL    PLOT_CLR
        LDA     CLR_X
        INR     A
        MOV     B,A
        LDA     CLR_Y
        MOV     C,A
        CALL    PLOT_CLR
        JMP     FC_DN
FC_PIX: LDA     CLR_X
        MOV     B,A
        LDA     CLR_Y
        MOV     C,A
        CALL    PLOT_CLR
        JMP     FC_DN
FC_3:   LDA     CLR_X
        DCR     A
        MOV     B,A
        LDA     CLR_Y
        DCR     A
        MOV     C,A
        MVI     E,3
FC3Y:   PUSH    B
        PUSH    D
        MVI     D,3
FC3X:   PUSH    B
        PUSH    D
        CALL    PLOT_CLR
        POP     D
        POP     B
        INR     B
        DCR     D
        JNZ     FC3X
        POP     D
        POP     B
        INR     C
        DCR     E
        JNZ     FC3Y
FC_DN:  XRA     A
        STA     CLR_KIND
        RET

;==============================================================================
; BCD score  (SCORE = 3 bytes, little-endian packed BCD: 00 00 00 .. 99 99 99)
;==============================================================================
ADD_BCD_LO:
        MOV     C,A
        LDA     SCORE
        ADD     C
        DAA
        STA     SCORE
        LDA     SCORE+1
        ACI     0
        DAA
        STA     SCORE+1
        LDA     SCORE+2
        ACI     0
        DAA
        STA     SCORE+2
        RET

ADD_BCD_MID:
        MOV     C,A
        LDA     SCORE+1
        ADD     C
        DAA
        STA     SCORE+1
        LDA     SCORE+2
        ACI     0
        DAA
        STA     SCORE+2
        RET
