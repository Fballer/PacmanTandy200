;==============================================================================
; sprite_blit.asm -- 7x7 dirty-rectangle blitter  (PHASE 2)
;------------------------------------------------------------------------------
; Included from hw_defs.asm.  Do NOT add an ORG.
;
; Why 7x7: corridors are 8 pixels.  An 8x8 sprite would sit on the 1-pixel
; walls.  7x7 is centered on the actor (center-3, center-3).
;
; Cross-byte: a 7-pixel row at any x can sit in one HD61830 byte or split
; across two.  We always save/restore TWO bytes per row (16-byte slot,
; last 2 unused) so we never have to special-case alignment.
;
; Draw = OR bits onto the LCD.  Erase = write the saved background back.
; That is the dirty rectangle: restore old box, then save+draw at the new
; box.  Phase 3 calls SPRITES_REDRAW every frame; Phase 2 calls
; SPRITES_INIT once after the maze is up.
;
; FRAME_DELAY sits after a blit burst so the slow LCD can catch up
; (smear / ghosting).  Raise DELAY_OUTER if the sprites smear.
;==============================================================================

DELAY_OUTER     EQU     8               ; outer loops of FRAME_DELAY
DELAY_INNER     EQU     0               ; 0 = 256 inner counts
SPR_H           EQU     7
SPR_BACK_SZ     EQU     16              ; 7 rows * 2 bytes, padded
SPR_COUNT       EQU     5               ; Pac + 4 ghosts

;==============================================================================
; FRAME_DELAY -- burn time so the HD61830/LCD can finish the last burst.
; 8085 @ 2.4576 MHz: inner 256 * ~7 cycles ~ 0.7 ms, * DELAY_OUTER ~ 6 ms.
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

;==============================================================================
; SPR_SHIFT_ROW
;   In : A = one 7-pixel bitmap row (pixels in bits 7..1, bit 0 clear)
;        TMP5 = shift 0..7  (pixel x & 7)
;   Out: TMP0 = left byte to OR,  TMP1 = right (spill) byte to OR
;==============================================================================
SPR_SHIFT_ROW:
        MOV     B,A                     ; original row
        LDA     TMP5
        MOV     D,A                     ; D = shift
        ORA     A
        JZ      SSRZ                    ; shift 0: no spill
        MOV     C,A
        MOV     A,B
SSRL:   ORA     A                       ; clear Carry (8085 ORA does)
        RAR                             ; logical >> 1
        DCR     C
        JNZ     SSRL
        STA     TMP0                    ; left
        MVI     A,8
        SUB     D                       ; 8 - shift
        MOV     C,A
        MOV     A,B
SSLL:   ADD     A                       ; << 1
        DCR     C
        JNZ     SSLL
        STA     TMP1                    ; right
        RET
SSRZ:   MOV     A,B
        STA     TMP0
        XRA     A
        STA     TMP1
        RET

;==============================================================================
; SPR_SAVE -- copy 7x2 background bytes at top-left (B,C) into (HL) buffer.
;==============================================================================
SPR_SAVE:
        SHLD    TMP_HL
        MOV     A,B
        STA     TMP3
        MOV     A,C
        STA     TMP4
        XRA     A
        STA     TMP6
SVROW:  LDA     TMP6
        CPI     SPR_H
        JNC     SVDN
        LDA     TMP4
        MOV     C,A
        LDA     TMP6
        ADD     C
        MOV     C,A                     ; y + row
        LDA     TMP3
        MOV     B,A
        CALL    XY_TO_ADDR              ; HL = left-byte address
        PUSH    H
        CALL    LCD_SET_ADDR
        CALL    LCD_RD_BYTE             ; A = left background byte
        LHLD    TMP_HL
        MOV     M,A
        INX     H
        SHLD    TMP_HL
        POP     H
        INX     H                       ; next VRAM byte
        CALL    LCD_SET_ADDR
        CALL    LCD_RD_BYTE
        LHLD    TMP_HL
        MOV     M,A
        INX     H
        SHLD    TMP_HL
        LDA     TMP6
        INR     A
        STA     TMP6
        JMP     SVROW
SVDN:   RET

;==============================================================================
; SPR_RESTORE -- write the 7x2 buffer at (HL) back to top-left (B,C).
;==============================================================================
SPR_RESTORE:
        SHLD    TMP_HL
        MOV     A,B
        STA     TMP3
        MOV     A,C
        STA     TMP4
        XRA     A
        STA     TMP6
RRROW:  LDA     TMP6
        CPI     SPR_H
        JNC     RRDN
        LDA     TMP4
        MOV     C,A
        LDA     TMP6
        ADD     C
        MOV     C,A
        LDA     TMP3
        MOV     B,A
        CALL    XY_TO_ADDR
        PUSH    H
        CALL    LCD_SET_ADDR
        LHLD    TMP_HL
        MOV     A,M
        INX     H
        SHLD    TMP_HL
        CALL    LCD_WR_BYTE
        POP     H
        INX     H
        CALL    LCD_SET_ADDR
        LHLD    TMP_HL
        MOV     A,M
        INX     H
        SHLD    TMP_HL
        CALL    LCD_WR_BYTE
        LDA     TMP6
        INR     A
        STA     TMP6
        JMP     RRROW
RRDN:   RET

;==============================================================================
; SPR_DRAW -- OR a 7-byte bitmap (HL) onto the LCD at top-left (B,C).
; Background MUST already be saved; this only sets bits.
;==============================================================================
SPR_DRAW:
        SHLD    TMP_HL                  ; bitmap pointer
        MOV     A,B
        STA     TMP3
        ANI     07H
        STA     TMP5                    ; shift
        MOV     A,C
        STA     TMP4
        XRA     A
        STA     TMP6
SDROW:  LDA     TMP6
        CPI     SPR_H
        JNC     SDDN
        LHLD    TMP_HL
        MOV     A,M
        INX     H
        SHLD    TMP_HL
        CALL    SPR_SHIFT_ROW           ; TMP0/TMP1
        LDA     TMP4
        MOV     C,A
        LDA     TMP6
        ADD     C
        MOV     C,A
        LDA     TMP3
        MOV     B,A
        CALL    XY_TO_ADDR              ; HL = dest
        PUSH    H
        CALL    LCD_SET_ADDR
        CALL    LCD_RD_BYTE
        MOV     B,A
        LDA     TMP0
        ORA     B
        MOV     B,A                     ; left merged (B)
        POP     H
        PUSH    H
        CALL    LCD_SET_ADDR
        MOV     A,B
        CALL    LCD_WR_BYTE
        POP     H
        INX     H
        PUSH    H
        CALL    LCD_SET_ADDR
        CALL    LCD_RD_BYTE
        MOV     B,A
        LDA     TMP1
        ORA     B
        MOV     B,A
        POP     H
        CALL    LCD_SET_ADDR
        MOV     A,B
        CALL    LCD_WR_BYTE
        LDA     TMP6
        INR     A
        STA     TMP6
        JMP     SDROW
SDDN:   RET

;==============================================================================
; Center (B,C) -> top-left (B,C), clipped to >=0.
;==============================================================================
SPR_CENTER_TL:
        MOV     A,B
        CPI     3
        JNC     SCTLX
        XRA     A
        JMP     SCTLX2
SCTLX:  SUI     3
SCTLX2: MOV     B,A
        MOV     A,C
        CPI     3
        JNC     SCTLY
        XRA     A
        JMP     SCTLY2
SCTLY:  SUI     3
SCTLY2: MOV     C,A
        RET

; Buffer address for sprite slot A (0..4) -> HL
SPR_SLOT_BUF:
        MOV     C,A
        ADD     A                       ; *2
        ADD     A                       ; *4
        ADD     A                       ; *8
        ADD     A                       ; *16
        MOV     C,A
        MVI     B,0
        LXI     H,SPR_BACK
        DAD     B
        RET

; OLD_XY pair for slot A -> DE (pointer)
SPR_SLOT_OLD:
        ADD     A                       ; *2
        MOV     C,A
        MVI     B,0
        LXI     H,OLD_XY
        DAD     B
        XCHG
        RET

;==============================================================================
; PAC_BITMAP -- HL -> 7-byte frame for current PAC_DIR / PAC_ANIM
; 8 frames (4 dirs * 2 mouths) * 7 bytes.
;==============================================================================
PAC_BITMAP:
        LDA     PAC_DIR
        ADD     A                       ; *2 frames per dir
        MOV     B,A
        LDA     PAC_ANIM
        ANI     01H
        ADD     B                       ; frame 0..7
        MOV     C,A                     ; save index
        ADD     A                       ; *2
        ADD     A                       ; *4
        ADD     A                       ; *8
        SUB     C                       ; *7
        MOV     C,A
        MVI     B,0
        LXI     H,SPR_PAC
        DAD     B
        RET

; Ghost bitmap for CUR_GID 0..3
GHOST_BITMAP:
        LDA     CUR_GID
        MOV     C,A
        ADD     A
        ADD     A
        ADD     A                       ; *8
        SUB     C                       ; *7
        MOV     C,A
        MVI     B,0
        LXI     H,SPR_GHOST
        DAD     B
        LDA     FRIGHT_TMR
        MOV     B,A
        LDA     FRIGHT_TMR+1
        ORA     B
        RZ                              ; HL already ghost body
        LXI     H,SPR_FRIGHT            ; all four share frightened shape
        RET

;==============================================================================
; SPRITES_INIT -- first draw after the maze.  Saves background and ORs
; each actor on.  Records top-left in OLD_XY so REDRAW can erase later.
;==============================================================================
SPRITES_INIT:
        DI
        CALL    SPRITES_PAINT
        EI
        CALL    FRAME_DELAY
        RET

;==============================================================================
; SPRITES_REDRAW -- erase at OLD_XY, draw at current actor pixels.
; Phase 3 calls this once per frame after AI_TICK / Pac move.
;==============================================================================
SPRITES_REDRAW:
        DI
        ; erase Pac
        XRA     A
        CALL    SPR_SLOT_OLD
        LDAX    D
        MOV     B,A
        INX     D
        LDAX    D
        MOV     C,A
        XRA     A
        CALL    SPR_SLOT_BUF
        CALL    SPR_RESTORE
        ; erase ghosts
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
        LDA     CUR_GID
        INR     A
        CALL    SPR_SLOT_BUF
        CALL    SPR_RESTORE
        LDA     CUR_GID
        INR     A
        STA     CUR_GID
        CPI     GHOST_COUNT
        JNZ     SRE_G
        ; now INIT-style redraw (save + draw, refresh OLD_XY)
        ; fall into the same body as INIT without the outer DI/EI
        CALL    SPRITES_PAINT
        EI
        CALL    FRAME_DELAY
        RET

; Paint all five at current positions (interrupts already off).
SPRITES_PAINT:
        LDA     PAC_X
        MOV     B,A
        LDA     PAC_Y
        MOV     C,A
        CALL    SPR_CENTER_TL
        XRA     A
        CALL    SPR_SLOT_OLD
        MOV     A,B
        STAX    D
        INX     D
        MOV     A,C
        STAX    D
        XRA     A
        CALL    SPR_SLOT_BUF
        PUSH    B
        CALL    SPR_SAVE
        POP     B
        CALL    PAC_BITMAP
        LDA     TMP3
        MOV     B,A
        LDA     TMP4
        MOV     C,A
        CALL    SPR_DRAW

        XRA     A
        STA     CUR_GID
SPP_G:  CALL    GHOST_BASE
        MOV     A,M
        MOV     B,A
        INX     H
        MOV     A,M
        MOV     C,A
        CALL    SPR_CENTER_TL
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
        LDA     CUR_GID
        INR     A
        PUSH    B
        CALL    SPR_SLOT_BUF
        POP     B
        PUSH    B
        CALL    SPR_SAVE
        POP     B
        CALL    GHOST_BITMAP
        LDA     TMP3
        MOV     B,A
        LDA     TMP4
        MOV     C,A
        CALL    SPR_DRAW
        LDA     CUR_GID
        INR     A
        STA     CUR_GID
        CPI     GHOST_COUNT
        JNZ     SPP_G
        RET

;==============================================================================
; 7x7 bitmaps.  Bit 7 = leftmost pixel, bit 0 unused (always 0).
;==============================================================================

; Pac-Man: dir RIGHT, LEFT, DOWN, UP; each with mouth OPEN then CLOSED.
SPR_PAC:
        ; RIGHT open
        DB      00111000B
        DB      01111100B
        DB      11111110B
        DB      11110000B
        DB      11111110B
        DB      01111100B
        DB      00111000B
        ; RIGHT closed
        DB      00111000B
        DB      01111100B
        DB      11111110B
        DB      11111100B
        DB      11111110B
        DB      01111100B
        DB      00111000B
        ; LEFT open
        DB      00111000B
        DB      01111100B
        DB      11111110B
        DB      00011110B
        DB      11111110B
        DB      01111100B
        DB      00111000B
        ; LEFT closed
        DB      00111000B
        DB      01111100B
        DB      11111110B
        DB      01111110B
        DB      11111110B
        DB      01111100B
        DB      00111000B
        ; DOWN open
        DB      00111000B
        DB      01111100B
        DB      11010110B
        DB      11111110B
        DB      01101100B
        DB      01000100B
        DB      00000000B
        ; DOWN closed
        DB      00111000B
        DB      01111100B
        DB      11010110B
        DB      11111110B
        DB      01111100B
        DB      00111000B
        DB      00000000B
        ; UP open
        DB      00000000B
        DB      01000100B
        DB      01101100B
        DB      11111110B
        DB      11010110B
        DB      01111100B
        DB      00111000B
        ; UP closed
        DB      00000000B
        DB      00111000B
        DB      01111100B
        DB      11111110B
        DB      11010110B
        DB      01111100B
        DB      00111000B

; Ghost bodies (Blinky, Pinky, Inky, Clyde) -- same silhouette, unique fill.
SPR_GHOST:
        ; Blinky: solid, two eyes
        DB      00111000B
        DB      01111100B
        DB      11010110B
        DB      11111110B
        DB      11111110B
        DB      11111110B
        DB      10101010B
        ; Pinky: lighter (every other pixel in the body)
        DB      00111000B
        DB      01010100B
        DB      11010110B
        DB      10101010B
        DB      01010100B
        DB      10101010B
        DB      01010100B
        ; Inky: horizontal bands
        DB      00111000B
        DB      01111100B
        DB      11010110B
        DB      00000000B
        DB      11111110B
        DB      00000000B
        DB      10101010B
        ; Clyde: outline-ish
        DB      00111000B
        DB      01000100B
        DB      11010110B
        DB      10000010B
        DB      10000010B
        DB      11111110B
        DB      10101010B

; Frightened: hollow eyes, wavy skirt (shared)
SPR_FRIGHT:
        DB      00111000B
        DB      01111100B
        DB      10101010B
        DB      11111110B
        DB      01111100B
        DB      11111110B
        DB      01010100B
