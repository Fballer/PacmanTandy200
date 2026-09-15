;==============================================================================
; sprite_blit.asm -- 6x6 dirty-rectangle blitter
;------------------------------------------------------------------------------
; Corridors are 6 pixels.  A 6x6 sprite fills a tile when aligned.
; Tile X is a multiple of 6 so a sprite ROW is one LCD byte on-grid
; (and two bytes when the actor is mid-tile).
;==============================================================================

DELAY_OUTER     EQU     1               ; LCD settle after maze / GO
DELAY_INNER     EQU     0
PACE_OUTER      EQU     4               ; 4 ghosts already pad the frame; keep a short WASD poll
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
; SPR_DRAW -- maze|sprite at top-left (B,C).
; One LCD byte per row when x%6==0 (the 6px sprite is that byte).
; Two bytes only when the sprite splits a byte.  Paint MUST finish; do
; not full-box erase first -- that burst is what clipped both actors.
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
        ORA     A
        JZ      SDRN                    ; aligned: do not write neighbor
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
        CALL    SHR_N
        ORA     D
        CALL    LCD_DATA
        JMP     SDRN
SDX:    POP     PSW
SDRN:   LDA     TMP6
        INR     A
        STA     TMP6
        JMP     SDROW

; Paint current frame first, then maze-only the 1px strip we left.
PAC_REDRAW:
        XRA     A
        CALL    SPR_SLOT_OLD
        LDAX    D
        MOV     B,A
        INX     D
        LDAX    D
        MOV     C,A
        PUSH    B                       ; old xy
        LDA     PAC_X
        MOV     B,A
        LDA     PAC_Y
        MOV     C,A
        PUSH    B                       ; new xy
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
        POP     B                       ; old xy
        LDA     TMP3
        CMP     B
        JNZ     PR_VAC
        LDA     TMP4
        CMP     C
        RZ
PR_VAC: JMP     SPR_VACATE

; Same as PAC_REDRAW for CUR_GID.  Hollow fright / eyes are sparse, so the
; 1px strip vacate leaves pupils behind.  Those modes restroke the old 6x6
; first, then paint (overlap is maze then sprite -- no hole, no trail).
GHOST_REDRAW:
        LDA     CUR_GID
        INR     A
        CALL    SPR_SLOT_OLD
        LDAX    D
        MOV     B,A
        INX     D
        LDAX    D
        MOV     C,A
        PUSH    B                       ; old xy
        CALL    GHOST_BASE
        MOV     A,M
        MOV     B,A
        INX     H
        MOV     A,M
        MOV     C,A
        PUSH    B                       ; new xy
        LDA     CUR_GID
        INR     A
        CALL    SPR_SLOT_OLD
        POP     B
        MOV     A,B
        STAX    D
        INX     D
        MOV     A,C
        STAX    D
        PUSH    B                       ; new xy
        CALL    GHOST_BASE
        LXI     D,GH_MODE
        DAD     D
        MOV     A,M
        CPI     MODE_EATEN
        JZ      GR_SPARSE
        CPI     MODE_FRIGHT
        JZ      GR_SPARSE
        ; Eyes revive teleports to the floor.  1px vacate then leaves
        ; pupils on the door; restroke the old 6x6 when we jumped.
        POP     D                       ; D=newX E=newY
        POP     B                       ; B=oldX C=oldY
        PUSH    B
        PUSH    D
        MOV     A,D
        PUSH    B
        MOV     C,B                     ; C=oldX
        CALL    ABS_DIFF
        POP     B
        CPI     2
        JNC     GR_SPARSE
        MOV     A,E
        CALL    ABS_DIFF                ; C still oldY
        CPI     2
        JNC     GR_SPARSE
        CALL    GHOST_BITMAP
        POP     B
        CALL    SPR_DRAW
        POP     B                       ; old xy
        LDA     TMP3
        CMP     B
        JNZ     GR_VAC
        LDA     TMP4
        CMP     C
        RZ
GR_VAC: JMP     SPR_VACATE

GR_SPARSE:
        POP     D                       ; new xy in DE
        POP     B                       ; old
        PUSH    D
        CALL    WALL_RESTORE_BOX
        CALL    GHOST_BITMAP
        POP     B
        JMP     SPR_DRAW

; Maze-only pixels the sprite vacated.  BC = old top-left; TMP3/TMP4 = new.
; Vertical: one row.  Horizontal: only LCD bytes no longer covered.
SPR_VACATE:
        LDA     TMP4
        CMP     C
        JZ      SV_H
        JC      SV_UP                   ; new y < old y
        JMP     WALL_RESTORE_ROW        ; vacated top row
SV_UP:  MOV     A,C
        ADI     SPR_H-1
        MOV     C,A
        JMP     WALL_RESTORE_ROW
SV_H:   LDA     TMP3
        CMP     B
        RZ
        MOV     A,C
        STA     TMP6                    ; old y
        MOV     A,B
        CALL    DIV6
        MOV     A,D
        STA     TMP0                    ; old_lo
        MOV     A,B
        ADI     SPR_H-1
        CALL    DIV6
        MOV     A,D
        STA     TMP1                    ; old_hi
        LDA     TMP3
        CALL    DIV6
        MOV     A,D
        STA     TMP2                    ; new_lo
        LDA     TMP3
        ADI     SPR_H-1
        CALL    DIV6
        MOV     A,D
        STA     TMP5                    ; new_hi
        LDA     TMP0
        MOV     B,A
        CALL    SV_INNEW
        JNZ     SV_K0
        MVI     A,0FFH
        STA     TMP0
SV_K0:  LDA     TMP1
        MOV     B,A
        CALL    SV_INNEW
        JNZ     SV_K1
        MVI     A,0FFH
        STA     TMP1
SV_K1:  LDA     TMP1                    ; COMPOSE in SV_COL clobbers TMP1
        PUSH    PSW
        LDA     TMP0
        CPI     0FFH
        CNZ     SV_COL
        POP     PSW
        CPI     0FFH
        RZ
        MOV     B,A
        LDA     TMP0
        CMP     B
        RZ
        MOV     A,B
        JMP     SV_COL

; Z=1 if B is in [TMP2, TMP5].
SV_INNEW:
        LDA     TMP2
        CMP     B
        JZ      SV_INY
        JNC     SV_INN                  ; B < new_lo
        LDA     TMP5
        CMP     B
        JC      SV_INN                  ; B > new_hi
SV_INY: XRA     A
        RET
SV_INN: MVI     A,1
        ORA     A
        RET

; A = LCD byte index.  TMP6 = top y.  Six maze-only rows.
SV_COL: MOV     D,A
        ADD     A
        MOV     B,A
        ADD     A
        ADD     B                       ; *6 -> pixel x
        MOV     B,A
        LDA     TMP6
        MOV     C,A
        MVI     E,SPR_H
SV_CL:  PUSH    B
        PUSH    D
        CALL    WALL_RESTORE_BYTE
        POP     D
        POP     B
        INR     C
        DCR     E
        JNZ     SV_CL
        RET

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
; PAC_BITMAP -- HL -> 6-byte frame.  4 dirs * 2 mouths * 6 bytes.
; PAC_ANIM 0..15, phase = A & 3: open, open, open, closed.
PAC_BITMAP:
        LDA     PAC_DIR
        ADD     A                       ; dir * 2
        MOV     B,A
        LDA     PAC_ANIM
        ANI     03H
        CPI     03H
        JNZ     PBM0                    ; 0,1,2 = open
        MVI     A,01H                   ; 3 = closed
        JMP     PBM1
PBM0:   XRA     A
PBM1:   ADD     B                       ; dir*2 + mouth
        ADD     A                       ; *6 = *2 + *4
        MOV     B,A
        ADD     A
        ADD     B
        MOV     C,A
        MVI     B,0
        LXI     H,SPR_PAC
        DAD     B
        RET

; Ghost: eaten = black pupils.  Frightened = hollow outline + black eyes
; (monochrome stand-in for blue).  Last FRIGHT_FLASHW ticks: blink that
; outline against the solid body (Dossier warning phase).
GHOST_BITMAP:
        CALL    GHOST_BASE
        LXI     B,GH_MODE
        DAD     B
        MOV     A,M
        CPI     MODE_EATEN
        JZ      GB_EYES
        CPI     MODE_FRIGHT
        JZ      GB_FR
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
GB_FR:  LHLD    FRIGHT_TMR
        MOV     A,H
        ORA     A
        JNZ     GB_OUT                  ; remaining >= 256: still blue
        LDA     FRIGHT_FLASHW
        MOV     C,A
        ORA     A
        JZ      GB_OUT                  ; no warning phase this level
        MOV     A,L
        CMP     C
        JNC     GB_OUT                  ; still in the solid-blue window
        LDA     FRAME_CNT
        ANI     08H                     ; ~8 ticks/color (arcade is 14)
        JZ      GB_OUT
        JMP     GB_DIR                  ; flash: solid body
GB_OUT: LXI     H,SPR_FRIGHT
        RET
GB_EYES:
        LXI     H,SPR_EYES
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

;==============================================================================
; 6x6 bitmaps.  Bit 7 = leftmost pixel, bits 1..0 unused.
; Pac frames: dir (R,D,L,U) * 2 (open, closed).
; Ghost frames: dir (R,D,L,U), plus feet2 and frightened.
;==============================================================================
SPR_PAC:
        DB      078H,0F0H,0C0H,0C0H,0F0H,078H   ; RIGHT open
        DB      078H,0FCH,0FCH,0FCH,0FCH,078H   ; RIGHT closed
        DB      078H,0FCH,0FCH,0CCH,048H,000H   ; DOWN open
        DB      078H,0FCH,0FCH,0FCH,0FCH,078H   ; DOWN closed
        DB      078H,03CH,00CH,00CH,03CH,078H   ; LEFT open
        DB      078H,0FCH,0FCH,0FCH,0FCH,078H   ; LEFT closed
        DB      000H,048H,0CCH,0FCH,0FCH,078H   ; UP open
        DB      078H,0FCH,0FCH,0FCH,0FCH,078H   ; UP closed

SPR_GHOST:
        DB      078H,0FCH,0E8H,0FCH,0FCH,0B4H   ; RIGHT
        DB      078H,0FCH,0B4H,0FCH,0FCH,0B4H   ; DOWN
        DB      078H,0FCH,05CH,0FCH,0FCH,0B4H   ; LEFT
        DB      078H,0B4H,0FCH,0FCH,0FCH,0B4H   ; UP
SPR_GHOST_FEET2:
        DB      078H,0FCH,0B4H,0FCH,0FCH,048H
SPR_FRIGHT:
        DB      078H,084H,0ACH,084H,084H,0B4H   ; hollow + two black eyes
SPR_EYES:
        DB      000H,000H,048H,048H,000H,000H   ; pupils inset (x+1, x+4)

; 6x6 pellet sprites.  Bit 7 = leftmost.  Only the middle pixels are lit.
; Regular: 2x2 at (2,2).  Power: rounded 12 px.  Rest of the tile is empty.
SPR_PELLET:
        DB      000H,000H,030H,030H,000H,000H
SPR_POWER:
        DB      030H,078H,0FCH,0FCH,078H,030H   ; 24-pixel diamond


