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
; the ghost house.  Warp tunnels wrap X=6 <-> 114 on tile row TUN_TY.
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
;==============================================================================
; WAIT_START -- maze is already on screen.  Do NOT start the game yet.
; Draw PRESS SPACE on the HUD, poll spacebar without touching Port B
; (LCD chip-select lives there), then draw GO so we know input + LCD work.
;==============================================================================
T200_KSCAN      EQU     0FD0EH          ; VirtualT T200 ROM keyscan mirror

WAIT_START:
        LXI     H,MSG_PRESS
        MVI     B,126                   ; HUD, byte-aligned
        MVI     C,8
        CALL    DRAW_STR
WSIDL:  CALL    POLL_KEYS               ; wait until no false/stuck keys
        LDA     KEY_FLAGS
        ANI     01FH
        JNZ     WSIDL
WSLP:   CALL    POLL_KEYS
        LDA     KEY_FLAGS
        ANI     01FH                    ; space or any direction
        JZ      WSLP
WSOK:   LXI     H,MSG_GO
        MVI     B,126
        MVI     C,24
        CALL    DRAW_STR
        MVI     B,8                     ; brief hold so GO is visible
WSDLY:  PUSH    B
        CALL    FRAME_DELAY
        POP     B
        DCR     B
        JNZ     WSDLY
        RET

; 8155 PA/PB as outputs.  PB bit0=1 so column 9 is NOT selected (otherwise
; IN E0 ignores every Port A strobe).  PB bit4 must stay 0 (power-off).
; Seed T200 keyscan RAM with 0 so VirtualT's first key event is accepted
; instead of waiting for ~10 ignored presses.
KBD_INIT:
        MVI     A,03H                   ; PA out, PB out, PC in, timer untouched
        OUT     PIO_CMD
        MVI     A,01H                   ; col9 off, no power-down, no beep bit
        OUT     PIO_PB
        MVI     A,0FFH
        OUT     PIO_PA
        LXI     H,T200_KSCAN
        MVI     B,9
        XRA     A
KSEED:  MOV     M,A
        INX     H
        DCR     B
        JNZ     KSEED
        RET

; Hold the column strobe so VirtualT has time to sample the matrix.
KBD_HOLD:
        PUSH    B
        MVI     B,2
KH1:    DCR     B
        JNZ     KH1
        POP     B
        RET

; A = Port A column mask (one bit low).  Returns row byte in A.  PA idle 0FFH.
KBD_STROBE:
        OUT     PIO_PA
        CALL    KBD_HOLD
        IN      KBD_ROWS
        PUSH    PSW
        MVI     A,0FFH
        OUT     PIO_PA
        POP     PSW
        RET

; Strobe columns 0-7 and write ~row to ROM keyscan RAM (0FD0EH).
; VirtualT will not apply a host key until those 9 bytes equal ~keyscan,
; otherwise it waits for ~10 auto-repeat events (~0.5s).
KSTROB:
        DB      0FEH,0FDH,0FBH,0F7H,0EFH,0DFH,0BFH,07FH
KBD_MIRROR:
        MVI     A,01H                   ; col9 off (LCD CS lives on PB)
        OUT     PIO_PB
        LXI     H,T200_KSCAN
        LXI     D,KSTROB
        MVI     B,8
KM1:    LDAX    D
        PUSH    D
        PUSH    B
        PUSH    H
        CALL    KBD_STROBE
        POP     H
        POP     B
        POP     D
        ORA     A
        JZ      KMST                    ; 00 = no sample, not all-keys-down
        CMA                             ; 1 = pressed
KMST:   MOV     M,A
        INX     H
        INX     D
        DCR     B
        JNZ     KM1
        XRA     A                       ; col9 unused (never drop PB bit0)
        MOV     M,A
        RET

; Fill KEY_FLAGS from WASD (active-low letters) plus SPACE/ARROWS with
; both VirtualT active-high special-key encoding and real active-low.
POLL_PLAY:
        XRA     A
        STA     KEY_FLAGS
        CALL    KBD_MIRROR
        JMP     PK_WASD                 ; WASD only (faster in the play loop)

POLL_KEYS:
        XRA     A
        STA     KEY_FLAGS
        CALL    KBD_MIRROR
        CALL    PK_WASD
        JMP     PK_ARR

        ; --- WASD from mirrored col1/col2 (already 1 = pressed) ---
PK_WASD:
        LXI     H,T200_KSCAN+1
        MOV     A,M
        MOV     B,A
        ANI     01H                     ; A
        JZ      PK_S
        LDA     KEY_FLAGS
        ORI     KEY_LEFT
        STA     KEY_FLAGS
PK_S:   MOV     A,B
        ANI     02H                     ; S
        JZ      PK_D
        LDA     KEY_FLAGS
        ORI     KEY_DOWN
        STA     KEY_FLAGS
PK_D:   MOV     A,B
        ANI     04H                     ; D
        JZ      PK_W
        LDA     KEY_FLAGS
        ORI     KEY_RIGHT
        STA     KEY_FLAGS
PK_W:   LXI     H,T200_KSCAN+2
        MOV     A,M
        ANI     02H                     ; W
        JZ      PK_WDN
        LDA     KEY_FLAGS
        ORI     KEY_UP
        STA     KEY_FLAGS
PK_WDN: RET

        ; --- arrows, column 5 ---
PK_ARR: MVI     A,0DFH
        CALL    KBD_STROBE
        MOV     B,A
        ANI     0FH
        JZ      PK_VT                   ; low nibble 0: VirtualT special keys
        MOV     A,B                     ; real silicon: 0 = pressed
        CMA
        MOV     B,A
        ANI     80H                     ; row7 Right
        JZ      PK_RL
        LDA     KEY_FLAGS
        ORI     KEY_RIGHT
        STA     KEY_FLAGS
PK_RL:  MOV     A,B
        ANI     40H                     ; row6 Left
        JZ      PK_RU
        LDA     KEY_FLAGS
        ORI     KEY_LEFT
        STA     KEY_FLAGS
PK_RU:  MOV     A,B
        ANI     20H                     ; row5 Up
        JZ      PK_RD
        LDA     KEY_FLAGS
        ORI     KEY_UP
        STA     KEY_FLAGS
PK_RD:  MOV     A,B
        ANI     10H                     ; row4 Down
        JZ      PK_SP
        LDA     KEY_FLAGS
        ORI     KEY_DOWN
        STA     KEY_FLAGS
        JMP     PK_SP
PK_VT:  MOV     A,B                     ; VT: 1 = pressed
        ANI     10H                     ; bit4 Left
        JZ      PK_VR
        LDA     KEY_FLAGS
        ORI     KEY_LEFT
        STA     KEY_FLAGS
PK_VR:  MOV     A,B
        ANI     20H                     ; bit5 Right
        JZ      PK_VU
        LDA     KEY_FLAGS
        ORI     KEY_RIGHT
        STA     KEY_FLAGS
PK_VU:  MOV     A,B
        ANI     40H                     ; bit6 Up
        JZ      PK_VD
        LDA     KEY_FLAGS
        ORI     KEY_UP
        STA     KEY_FLAGS
PK_VD:  MOV     A,B
        ANI     80H                     ; bit7 Down
        JZ      PK_SP
        LDA     KEY_FLAGS
        ORI     KEY_DOWN
        STA     KEY_FLAGS

        ; --- space, column 6 ---
        ; VT idle 00h / space 01h (bit0=1).  Real idle FFh / space FEh (bit0=0).
PK_SP:  MVI     A,0BFH
        CALL    KBD_STROBE
        MOV     B,A
        ANI     01H
        JNZ     PK_S1                   ; bit0 set: VT space or real idle
        MOV     A,B
        ORA     A
        RZ                              ; 00h = VirtualT idle
        JMP     PK_SY                   ; real space (FEh etc.)
PK_S1:  MOV     A,B
        CPI     0FFH
        RZ                              ; real idle
PK_SY:  LDA     KEY_FLAGS
        ORI     KEY_FIRE
        STA     KEY_FLAGS
        RET

; HL -> indices 0..8, 0FFH-terminated.  B=x C=y.  5x7 glyphs, 6 px step.
DRAW_STR:
        MOV     A,M
        CPI     0FFH
        RZ
        INX     H
        PUSH    H
        PUSH    B
        CALL    DRAW_GLYPH
        POP     B
        MOV     A,B
        ADI     6
        MOV     B,A
        POP     H
        JMP     DRAW_STR

; A = glyph index, B = x, C = y.  Bit 7 of each font byte = leftmost.
DRAW_GLYPH:
        STA     TMP0
        MOV     A,B
        STA     TMP3
        MOV     A,C
        STA     TMP4
        LDA     TMP0
        ADD     A                       ; *2
        ADD     A                       ; *4
        MOV     B,A
        LDA     TMP0
        ADD     A                       ; *2
        ADD     B                       ; *6
        MOV     B,A
        LDA     TMP0
        ADD     B                       ; *7
        MOV     E,A
        MVI     D,0
        LXI     H,FONT5
        DAD     D
        XRA     A
        STA     TMP6
DGROW:  LDA     TMP6
        CPI     7
        RNC
        MOV     A,M
        INX     H
        MOV     D,A
        XRA     A
        STA     TMP7
DGCOL:  LDA     TMP7
        CPI     5
        JZ      DGRN
        MOV     A,D
        RLC
        MOV     D,A
        JNC     DGNXT
        LDA     TMP3
        MOV     B,A
        LDA     TMP7
        ADD     B
        MOV     B,A
        LDA     TMP4
        MOV     C,A
        LDA     TMP6
        ADD     C
        MOV     C,A
        PUSH    H
        PUSH    D
        CALL    PLOT_OR
        POP     D
        POP     H
DGNXT:  LDA     TMP7
        INR     A
        STA     TMP7
        JMP     DGCOL
DGRN:   LDA     TMP6
        INR     A
        STA     TMP6
        JMP     DGROW

; 0=sp 1=A 2=C 3=E 4=G 5=O 6=P 7=R 8=S   (5x7, bit7=left)
FONT5:
        DB      000H,000H,000H,000H,000H,000H,000H   ; space
        DB      070H,088H,088H,0F8H,088H,088H,088H   ; A
        DB      070H,088H,080H,080H,080H,088H,070H   ; C
        DB      0F8H,080H,080H,0F0H,080H,080H,0F8H   ; E
        DB      070H,088H,080H,0B8H,088H,088H,070H   ; G
        DB      070H,088H,088H,088H,088H,088H,070H   ; O
        DB      0F0H,088H,088H,0F0H,080H,080H,080H   ; P
        DB      0F0H,088H,088H,0F0H,0A0H,090H,088H   ; R
        DB      078H,080H,080H,070H,008H,008H,0F0H   ; S

MSG_PRESS:
        DB      6,7,3,8,8,0,8,6,1,2,3,0FFH   ; PRESS SPACE
MSG_GO:
        DB      4,5,0FFH                     ; GO

; After GO: steer + Pac + eat pellets (COMPOSE omits eaten bits).
GAME_LOOP:
        XRA     A
        STA     GAME_STATE
        STA     CLR_KIND

GLTICK: CALL    POLL_PLAY
        CALL    PAC_INPUT
        CALL    PAC_MOVE
        CALL    PELLET_TRY
        CALL    ENERG_TRY
        CALL    AI_TICK                 ; Blinky think+step
        XRA     A
        STA     CUR_GID
        CALL    GHOST_REDRAW
        CALL    PAC_REDRAW              ; Pac last (complete chew)
        CALL    PAC_PACE
        JMP     GLTICK

;==============================================================================
; PAC_INPUT -- buffer PAC_NDIR from WASD.  A tap is kept until a new
; 90-degree or reverse key; holding A/D must not clear a W/S tap.
;==============================================================================
PAC_INPUT:
        LDA     KEY_FLAGS
        ANI     00FH                    ; direction bits only
        RZ
        MOV     B,A
        LDA     PAC_DIR
        MOV     C,A
        ; Pass 1: perpendicular, UP / LEFT / DOWN / RIGHT
        MOV     A,B
        ANI     KEY_UP
        JZ      PI1L
        MVI     A,DIR_UP
        XRA     C
        ANI     01H
        JNZ     PI_UP
PI1L:   MOV     A,B
        ANI     KEY_LEFT
        JZ      PI1D
        MVI     A,DIR_LEFT
        XRA     C
        ANI     01H
        JNZ     PI_LF
PI1D:   MOV     A,B
        ANI     KEY_DOWN
        JZ      PI1R
        MVI     A,DIR_DOWN
        XRA     C
        ANI     01H
        JNZ     PI_DN
PI1R:   MOV     A,B
        ANI     KEY_RIGHT
        JZ      PI_REV
        MVI     A,DIR_RIGHT
        XRA     C
        ANI     01H
        JNZ     PI_RT
PI_REV: MOV     A,C
        XRI     02H
        MOV     E,A
        MVI     D,0
        LXI     H,DIRKMSK
        DAD     D
        MOV     A,M
        ANA     B
        JZ      PI_KEEP                 ; continue key: do NOT eat a 90-degree tap
        MOV     A,E
        STA     PAC_NDIR
        RET
PI_KEEP:
        RET
PI_UP:  MVI     A,DIR_UP
        STA     PAC_NDIR
        RET
PI_DN:  MVI     A,DIR_DOWN
        STA     PAC_NDIR
        RET
PI_LF:  MVI     A,DIR_LEFT
        STA     PAC_NDIR
        RET
PI_RT:  MVI     A,DIR_RIGHT
        STA     PAC_NDIR
        RET

DIRKMSK:
        DB      KEY_RIGHT, KEY_DOWN, KEY_LEFT, KEY_UP

;==============================================================================
; PAC_MOVE -- 1 pixel.  Reverse any time.  90-degree turns only on the
; tile origin (x%6==0, y%6==1).  PAC_NDIR is buffered, so a tap during
; the approach still turns at that pixel -- do not snap from mid-tile.
;==============================================================================
PAC_MOVE:
        CALL    PAC_TILES               ; TX/TY from current pixels before the turn test
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
        JNZ     PM_ANIM                 ; blocked: do not step, still chew

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
        CPI     BORDER_X0
        JNZ     PM_W1
        MVI     A,PF_XMAX
        STA     PAC_X
        JMP     PM_ANIM
PM_W1:  CPI     PF_XWRAP
        JNZ     PM_ANIM
        MVI     A,MAZE_X0
        STA     PAC_X
PM_ANIM:
        LDA     PAC_ANIM
        INR     A
        ANI     0FH                     ; 16 ticks = open, half, closed, half
        STA     PAC_ANIM
        JMP     PAC_TILES               ; keep TX/TY in sync

; Z=1 if Pac is on a decision pixel.
PAC_AT_CENTER:
        LDA     PAC_X
        CALL    DIV6
        ORA     A
        JNZ     PACNO
        LDA     PAC_Y
        CALL    DIV6
        CPI     1
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
        ADD     A
        MOV     C,A
        LDA     PAC_TY
        ADD     C                       ; ty * 3
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
        CALL    TILE_TO_PX
        ADI     PEL_OX
        STA     CLR_X
        LDA     PAC_TY
        CALL    TILE_TO_PY
        ADI     PEL_OY
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
        MOV     B,A                     ; tx
        MOV     A,M
        INX     H
        MOV     D,A                     ; ty
        LDA     PAC_TX
        CMP     B
        JNZ     ETN
        LDA     PAC_TY
        CMP     D
        JNZ     ETN
        LDA     ENERG_MASK
        MOV     B,A
        MOV     A,C
        INR     A
        MOV     E,A                     ; E = index+1
        MVI     A,01H
ETSH:   DCR     E
        JZ      ETBIT
        ADD     A
        JMP     ETSH
ETBIT:  MOV     E,A
        ANA     B
        RZ
        MOV     A,E
        CMA
        ANA     B
        STA     ENERG_MASK
        LDA     ENERG_LEFT
        DCR     A
        STA     ENERG_LEFT
        MVI     A,50H
        CALL    ADD_BCD_LO
        XRA     A
        STA     GHOST_PTS
        MVI     A,FRIGHT_TICKS
        CALL    AI_FRIGHTEN
        DCX     H
        DCX     H
        MOV     A,M                     ; tx
        CALL    TILE_TO_PX
        ADI     1
        STA     CLR_X
        INX     H
        MOV     A,M                     ; ty
        CALL    TILE_TO_PY
        ADI     1
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
        JZ      FC_2
        CPI     CLR_ENERG
        JZ      FC_4
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
FC_2:   MVI     E,2
        JMP     FC_BOX
FC_4:   MVI     E,4
FC_BOX: LDA     CLR_X
        MOV     B,A
        LDA     CLR_Y
        MOV     C,A
FCY:    PUSH    B
        PUSH    D
        MOV     D,E
FCX:    PUSH    B
        PUSH    D
        CALL    PLOT_CLR
        POP     D
        POP     B
        INR     B
        DCR     D
        JNZ     FCX
        POP     D
        POP     B
        INR     C
        DCR     E
        JNZ     FCY
        JMP     FC_DN

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
