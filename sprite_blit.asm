;==============================================================================
; sprite_blit.asm -- 6x6 dirty-rectangle blitter
;------------------------------------------------------------------------------
; Corridors are 6 pixels.  A 6x6 sprite fills a tile when aligned.
; Tile X is a multiple of 6 so a sprite ROW is one LCD byte on-grid
; (and two bytes when the actor is mid-tile).
;==============================================================================

DELAY_OUTER     EQU     1               ; LCD settle after maze / GO
DELAY_INNER     EQU     0
PACE_OUTER      EQU     4               ; ~3 ms; keep 1px even without a long stall
SPR_H           EQU     6
SPR_COUNT       EQU     5               ; Pac + 4 ghosts

;==============================================================================
; FRAME_DELAY -- burn time so the HD61830/LCD can finish the last burst.
; 8085 @ 2.4576 MHz: inner 256 * ~7 cycles ~ 0.7 ms, * DELAY_OUTER ~ 0.7 ms.
;==============================================================================
FRAME_DELAY:
        PUSH    B
        MVI     B,DELAY_OUTER
FD1:    MVI     C,DELAY_INNER
FD2:    DCR     C
        JNZ     FD2
        DCR     B
        JNZ     FD1
        POP     B
        RET

; Pac step clock.  Also polls WASD so a tap during the wait is latched
; into PAC_NDIR before the next pixel (no need to hold the key).
PAC_PACE:
        PUSH    B
        MVI     B,PACE_OUTER
PP1:    PUSH    B
        CALL    POLL_PLAY
        CALL    PAC_INPUT
        POP     B
        MVI     C,80H
PP2:    DCR     C
        JNZ     PP2
        DCR     B
        JNZ     PP1
        POP     B
        RET

;==============================================================================
; SPR_TO_LCD -- A = sprite row (bit7=left) -> A = LCD bits (bit0=left).
;==============================================================================
SPR_TO_LCD:
        MOV     D,A
        MVI     C,0
        LXI     H,LCD_BITS
        MVI     B,6
STL1:   MOV     A,D
        RLC
        MOV     D,A
        JNC     STL0
        MOV     A,C
        ORA     M
        MOV     C,A
STL0:   INX     H
        DCR     B
        JNZ     STL1
        MOV     A,C
        RET

; A << B  (B=0 leaves A).  Destroys B,C.
SHL_N:
        MOV     C,A
        MOV     A,B
        ORA     A
        MOV     A,C
        RZ
SHL1:   ADD     A
        DCR     B
        JNZ     SHL1
        RET

; logical A >> B.  Destroys B,C.
SHR_N:
        MOV     C,A
        MOV     A,B
        ORA     A
        MOV     A,C
        RZ
SHR1:   ORA     A
        RAR
        DCR     B
        JNZ     SHR1
        RET

;==============================================================================
; SPR_DRAW -- write maze|sprite as LCD bytes at top-left (B,C).
; Always two bytes per row so vertical (x%6==0) costs the same as a
; mid-tile horizontal step.  Second byte is neighbor maze when aligned.
;==============================================================================
SPR_DRAW:
        SHLD    TMP_HL
        MOV     A,B
        STA     TMP3
        MOV     A,C
        STA     TMP4
        XRA     A
        STA     TMP6
SDROW:  LDA     TMP6
        CPI     SPR_H
        RNC
        LHLD    TMP_HL
        MOV     A,M
        INX     H
        SHLD    TMP_HL
        CALL    SPR_TO_LCD
        STA     TMP0
        LDA     TMP4
        MOV     C,A
        LDA     TMP6
        ADD     C
        MOV     C,A
        CPI     LCD_HEIGHT
        JNC     SDRN
        LDA     TMP3
        MOV     B,A
        PUSH    B
        CALL    XY_TO_ADDR
        CALL    LCD_SET_ADDR
        MVI     A,LCD_REG_WRITE
        CALL    LCD_CMD
        POP     B
        MOV     A,B
        CALL    DIV6
        PUSH    PSW                     ; remain
        MOV     B,D
        PUSH    B                       ; B=byte, C=y
        CALL    COMPOSE_BYTE
        MOV     D,A
        POP     B
        POP     PSW
        PUSH    B
        PUSH    PSW
        MOV     E,A
        LDA     TMP0
        MOV     B,E
        CALL    SHL_N                   ; remain 0: identity
        ANI     03FH
        ORA     D
        CALL    LCD_DATA
        POP     PSW
        POP     B
        PUSH    PSW
        INR     B
        MOV     A,B
        CPI     WALL_BYTES
        JNC     SDX
        PUSH    B
        LDA     TMP4
        MOV     C,A
        LDA     TMP6
        ADD     C
        MOV     C,A
        CALL    COMPOSE_BYTE
        MOV     D,A
        POP     B
        POP     PSW
        MOV     C,A
        MVI     A,6
        SUB     C
        MOV     B,A
        LDA     TMP0
        CALL    SHR_N                   ; remain 0: sprite >> 6 = 0
        ORA     D
        CALL    LCD_DATA
        JMP     SDRN
SDX:    POP     PSW
SDRN:   LDA     TMP6
        INR     A
        STA     TMP6
        JMP     SDROW

; Restore old square if Pac moved (byte write overwrites the new square).
PAC_REDRAW:
        XRA     A
        CALL    SPR_SLOT_OLD
        LDAX    D
        MOV     B,A
        INX     D
        LDAX    D
        MOV     C,A
        LDA     PAC_X
        CMP     B
        JNZ     PR_ER
        LDA     PAC_Y
        CMP     C
        JZ      PR_IDLE
PR_ER:  CALL    WALL_RESTORE_BOX
        JMP     PR_DR
PR_IDLE:
        CALL    PAC_PACE                ; no restore: pad so chew matches move
PR_DR:  LDA     PAC_X
        MOV     B,A
        LDA     PAC_Y
        MOV     C,A
        PUSH    B
        XRA     A
        CALL    SPR_SLOT_OLD
        POP     B
        MOV     A,B
        STAX    D
        INX     D
        MOV     A,C
        STAX    D
        PUSH    B
        CALL    PAC_BITMAP
        POP     B
        JMP     SPR_DRAW

; OLD_XY pair for slot A -> DE (pointer).  Must not touch BC: callers
; hold the sprite top-left in B,C and Pac was being drawn at (0,0).
SPR_SLOT_OLD:
        PUSH    B
        ADD     A                       ; *2
        MOV     C,A
        MVI     B,0
        LXI     H,OLD_XY
        DAD     B
        XCHG
        POP     B
        RET

;==============================================================================
; PAC_BITMAP -- HL -> 6-byte frame.  4 dirs * 3 mouths * 6 bytes.
; PAC_ANIM 0..15 holds each mouth 4 ticks: open, half, closed, half.
PAC_BITMAP:
        LDA     PAC_DIR
        MOV     B,A
        ADD     A
        ADD     B                       ; dir * 3
        MOV     B,A
        LDA     PAC_ANIM
        ORA     A
        RAR
        ORA     A
        RAR                             ; /4 -> phase 0..3
        ANI     03H
        CPI     03H
        JNZ     PBM1
        MVI     A,01H                   ; phase 3 = half
PBM1:   ADD     B                       ; dir*3 + mouth (0 open, 1 half, 2 closed)
        MOV     C,A                     ; *6 = *2 + *4
        ADD     A
        MOV     B,A
        ADD     A
        ADD     B
        MOV     C,A
        MVI     B,0
        LXI     H,SPR_PAC
        DAD     B
        RET

; Ghost: frightened, else facing GH_DIR; odd anim uses skirt frame 2.
GHOST_BITMAP:
        LDA     FRIGHT_TMR
        MOV     B,A
        LDA     FRIGHT_TMR+1
        ORA     B
        JNZ     GB_FR
        CALL    GHOST_BASE
        LXI     B,GH_ANIM
        DAD     B
        MOV     A,M
        ANI     01H
        JZ      GB_DIR
        LXI     H,SPR_GHOST_FEET2
        RET
GB_DIR: CALL    GHOST_BASE
        LXI     B,GH_DIR
        DAD     B
        MOV     A,M                     ; 0..3  *6
        ADD     A
        MOV     B,A
        ADD     A
        ADD     B
        MOV     C,A
        MVI     B,0
        LXI     H,SPR_GHOST
        DAD     B
        RET
GB_FR:  LXI     H,SPR_FRIGHT
        RET

;==============================================================================
; SPRITES_INIT -- first draw after the maze.  Saves background and ORs
; each actor on.  Records top-left in OLD_XY so REDRAW can erase later.
;==============================================================================
SPRITES_INIT:
        DI
        CALL    SPRITES_PAINT
        CALL    FRAME_DELAY
        RET

;==============================================================================
; SPRITES_REDRAW -- erase at OLD_XY, draw at current actor pixels.
; Phase 3 calls this once per frame after AI_TICK / Pac move.
;==============================================================================
SPRITES_REDRAW:
        DI
        CALL    SPRITES_ERASE
        CALL    SPRITES_PAINT
        CALL    FRAME_DELAY
        RET

; Restore maze under every sprite.  Do NOT write saved LCD bytes -- VirtualT
; reads often return 0, which punched holes and turned ghosts into blobs.
; Clear the 6x6 box, then restroke walls/pellets in the dirty tiles.
; Restore maze under every sprite from the Excel W bitmap (not a pixel
; clear -- that punched holes when PIX_TO_TX hit the 1px border).
SPRITES_ERASE:
        XRA     A
        CALL    SPR_SLOT_OLD
        LDAX    D
        MOV     B,A
        INX     D
        LDAX    D
        MOV     C,A
        CALL    WALL_RESTORE_BOX
        XRA     A
        STA     CUR_GID
SRE_G:  LDA     CUR_GID
        INR     A
        CALL    SPR_SLOT_OLD
        LDAX    D
        MOV     B,A
        INX     D
        LDAX    D
        MOV     C,A
        CALL    WALL_RESTORE_BOX
        LDA     CUR_GID
        INR     A
        STA     CUR_GID
        CPI     GHOST_COUNT
        JNZ     SRE_G
        LDA     FRUIT_ON
        ORA     A
        JZ      SRE_X
        CALL    DRAW_FRUIT
SRE_X:  RET

; Paint ghosts first, Pac last.  After DRAW_WALLS the LCD is still catching
; up; later pixel writes are the ones that stick, and Pac must be visible.
SPRITES_PAINT:
        XRA     A
        STA     CUR_GID
SPP_G:  CALL    GHOST_BASE
        MOV     A,M
        MOV     B,A
        INX     H
        MOV     A,M
        MOV     C,A
        LDA     CUR_GID
        INR     A
        PUSH    B
        CALL    SPR_SLOT_OLD
        POP     B
        MOV     A,B
        STAX    D
        INX     D
        MOV     A,C
        STAX    D
        PUSH    B
        CALL    GHOST_BITMAP
        POP     B
        CALL    SPR_DRAW
        LDA     CUR_GID
        INR     A
        STA     CUR_GID
        CPI     GHOST_COUNT
        JNZ     SPP_G

        LDA     PAC_X
        MOV     B,A
        LDA     PAC_Y
        MOV     C,A
        PUSH    B
        XRA     A
        CALL    SPR_SLOT_OLD
        POP     B
        MOV     A,B
        STAX    D
        INX     D
        MOV     A,C
        STAX    D
        PUSH    B
        CALL    PAC_BITMAP
        POP     B
        CALL    SPR_DRAW
        RET

; Clear a 6x6 pixel box at top-left (B,C).
SPR_CLEAR_BOX:
        MOV     A,B
        STA     TMP3
        MOV     A,C
        STA     TMP4
        XRA     A
        STA     TMP6
SCY:    LDA     TMP6
        CPI     SPR_H
        RNC
        XRA     A
        STA     TMP7
SCX:    LDA     TMP7
        CPI     SPR_H
        JZ      SCYN
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
        CALL    PLOT_CLR
        LDA     TMP7
        INR     A
        STA     TMP7
        JMP     SCX
SCYN:   LDA     TMP6
        INR     A
        STA     TMP6
        JMP     SCY

; Restroke pellets under the 6x6 at (B,C).  Walls already restored.
SPR_REPAIR_BOX:
        PUSH    B
        CALL    SPR_FIX_PIX
        POP     B
        PUSH    B
        MOV     A,B
        ADI     5
        MOV     B,A
        CALL    SPR_FIX_PIX
        POP     B
        PUSH    B
        MOV     A,C
        ADI     5
        MOV     C,A
        CALL    SPR_FIX_PIX
        POP     B
        MOV     A,B
        ADI     5
        MOV     B,A
        MOV     A,C
        ADI     5
        MOV     C,A
SPR_FIX_PIX:
        MOV     A,B
        CALL    PIX_TO_TX
        STA     TMP4
        MOV     A,C
        CALL    PIX_TO_TY
        STA     TMP5
        MOV     D,A
        LDA     TMP4
        MOV     D,A
        LDA     TMP5
        MOV     E,A
        JMP     PELLET_DOT

;==============================================================================
; 6x6 bitmaps.  Bit 7 = leftmost pixel, bits 1..0 unused.
; Pac frames: dir (R,D,L,U) * 3 (open, half, closed).
; Ghost frames: dir (R,D,L,U), plus feet2 and frightened.
;==============================================================================
SPR_PAC:
        DB      078H,0F0H,0C0H,0C0H,0F0H,078H   ; RIGHT open
        DB      078H,0F8H,0E0H,0E0H,0F8H,078H   ; RIGHT half
        DB      078H,0FCH,0FCH,0FCH,0FCH,078H   ; RIGHT closed
        DB      078H,0FCH,0FCH,0CCH,048H,000H   ; DOWN open
        DB      078H,0FCH,0FCH,0FCH,06CH,030H   ; DOWN half
        DB      078H,0FCH,0FCH,0FCH,0FCH,078H   ; DOWN closed
        DB      078H,03CH,00CH,00CH,03CH,078H   ; LEFT open
        DB      078H,07CH,01CH,01CH,07CH,078H   ; LEFT half
        DB      078H,0FCH,0FCH,0FCH,0FCH,078H   ; LEFT closed
        DB      000H,048H,0CCH,0FCH,0FCH,078H   ; UP open
        DB      030H,06CH,0FCH,0FCH,0FCH,078H   ; UP half
        DB      078H,0FCH,0FCH,0FCH,0FCH,078H   ; UP closed

SPR_GHOST:
        DB      078H,0FCH,0E8H,0FCH,0FCH,0B4H   ; RIGHT
        DB      078H,0FCH,0B4H,0FCH,0FCH,0B4H   ; DOWN
        DB      078H,0FCH,05CH,0FCH,0FCH,0B4H   ; LEFT
        DB      078H,0B4H,0FCH,0FCH,0FCH,0B4H   ; UP
SPR_GHOST_FEET2:
        DB      078H,0FCH,0B4H,0FCH,0FCH,048H
SPR_FRIGHT:
        DB      078H,0FCH,0B4H,0FCH,0A8H,0B4H

; 6x6 pellet sprites.  Bit 7 = leftmost.  Only the middle pixels are lit.
; Regular: 2x2 at (2,2).  Power: rounded 12 px.  Rest of the tile is empty.
SPR_PELLET:
        DB      000H,000H,030H,030H,000H,000H
SPR_POWER:
        DB      030H,078H,0FCH,0FCH,078H,030H   ; 24-pixel diamond


