;==============================================================================
; render_maze.asm -- HD61830 1-pixel wall renderer  (PHASE 2)
;------------------------------------------------------------------------------
; Included from hw_defs.asm.  Do NOT add an ORG.
;
; Draws MAZE_SEGS directly to the LCD.  There is NO framebuffer -- every
; pixel is a read-modify-write of one HD61830 byte.
;
; Address of pixel (x,y):
;     addr = y * LCD_HBBYTES + x/8
;     bit  = 80H >> (x & 7)     ; MSB is the LEFT pixel on the HD61830
;
; y*30 is done as y*32 - y*2  (shifts and a subtract -- no MUL).
;
; Wrap every blit in DI/EI.  RST 7.5 will tear the image if it fires
; between the read and the write of a byte.
;
; If the maze looks too narrow/wide on real silicon, James Yi measured
; 40 bytes/row.  Change LCD_HBBYTES in hw_defs.asm from 30 to 40.
;==============================================================================

BITMSK:
        DB      80H,40H,20H,10H,08H,04H,02H,01H

;------------------------------------------------------------------------------
; LCD_SET_ADDR -- HL = VRAM address (0 .. 30*128-1)
;------------------------------------------------------------------------------
LCD_SET_ADDR:
        MVI     A,LCD_REG_CAD_L
        CALL    LCD_CMD
        MOV     A,L
        CALL    LCD_DATA
        MVI     A,LCD_REG_CAD_H
        CALL    LCD_CMD
        MOV     A,H
        CALL    LCD_DATA
        RET

; Write A to VRAM at the current cursor (issues WRITE command).
LCD_WR_BYTE:
        PUSH    PSW
        MVI     A,LCD_REG_WRITE
        CALL    LCD_CMD
        POP     PSW
        CALL    LCD_DATA
        RET

; Read VRAM at the current cursor.  Dummy byte first (HD61830 rule).
; Cursor then points at the NEXT byte.
LCD_RD_BYTE:
        MVI     A,LCD_REG_READ
        CALL    LCD_CMD
        CALL    LCD_WAIT
        IN      LCD_DR                  ; dummy
        CALL    LCD_WAIT
        IN      LCD_DR                  ; real
        RET

;------------------------------------------------------------------------------
; XY_TO_ADDR
;   In : B = x (0..239),  C = y (0..127)
;   Out: HL = VRAM address,  A = bit mask for that pixel
;   Destroys DE.
;------------------------------------------------------------------------------
XY_TO_ADDR:
        PUSH    B
        MOV     A,C                     ; y
        MOV     L,A
        MVI     H,0
        DAD     H                       ; *2
        PUSH    H                       ; save y*2
        DAD     H                       ; *4
        DAD     H                       ; *8
        DAD     H                       ; *16
        DAD     H                       ; *32
        POP     D                       ; DE = y*2
        MOV     A,L
        SUB     E
        MOV     L,A
        MOV     A,H
        SBB     D
        MOV     H,A                     ; HL = y*30
        POP     B
        PUSH    B
        MOV     A,B                     ; x/8
        RRC
        RRC
        RRC
        ANI     1FH
        MOV     E,A
        MVI     D,0
        DAD     D                       ; HL = y*30 + x/8
        POP     B
        MOV     A,B
        ANI     07H
        MOV     E,A
        MVI     D,0
        PUSH    H
        LXI     H,BITMSK
        DAD     D
        MOV     A,M                     ; mask
        POP     H
        RET

;------------------------------------------------------------------------------
; PLOT_OR -- set pixel (B,C) to black.  Clips to 240x128.
;------------------------------------------------------------------------------
PLOT_OR:
        MOV     A,B
        CPI     LCD_WIDTH
        RNC
        MOV     A,C
        CPI     LCD_HEIGHT
        RNC
        PUSH    D
        CALL    XY_TO_ADDR              ; HL=addr, A=mask
        MOV     D,A
        PUSH    H
        CALL    LCD_SET_ADDR
        CALL    LCD_RD_BYTE             ; A = screen byte, addr+1
        ORA     D
        MOV     D,A
        POP     H
        CALL    LCD_SET_ADDR            ; rewind
        MOV     A,D
        CALL    LCD_WR_BYTE
        POP     D
        RET

; OR an entire byte at pixel (B,C) which MUST be byte-aligned (x & 7 == 0).
PLOT_BYTE_OR:
        PUSH    D
        CALL    XY_TO_ADDR
        PUSH    H
        CALL    LCD_SET_ADDR
        CALL    LCD_RD_BYTE
        ORI     0FFH
        MOV     D,A
        POP     H
        CALL    LCD_SET_ADDR
        MOV     A,D
        CALL    LCD_WR_BYTE
        POP     D
        RET

;------------------------------------------------------------------------------
; DRAW_H -- horizontal 1-pixel stroke
;   B = start x, C = y, E = length in pixels
; Fast path: once x is byte-aligned and >=8 pixels remain, OR a whole byte.
;------------------------------------------------------------------------------
DRAW_H:
        MOV     A,E
        ORA     A
        RZ
DHLOOP: MOV     A,B
        ANI     07H
        JNZ     DHPIX                   ; not aligned: one pixel
        MOV     A,E
        CPI     8
        JC      DHPIX                   ; tail shorter than a byte
        PUSH    B
        PUSH    D
        CALL    PLOT_BYTE_OR
        POP     D
        POP     B
        MOV     A,B
        ADI     8
        MOV     B,A
        MOV     A,E
        SUI     8
        MOV     E,A
        JMP     DHLOOP
DHPIX:  PUSH    B
        PUSH    D
        CALL    PLOT_OR
        POP     D
        POP     B
        INR     B
        DCR     E
        JNZ     DHLOOP
        RET

;------------------------------------------------------------------------------
; DRAW_V -- vertical 1-pixel stroke
;   B = x, C = start y, E = length
; Reuses the same bit mask; address steps by LCD_HBBYTES each row.
;------------------------------------------------------------------------------
DRAW_V:
        MOV     A,E
        ORA     A
        RZ
        MOV     A,C
        CPI     LCD_HEIGHT
        RNC
        PUSH    D
        CALL    XY_TO_ADDR              ; HL=addr, A=mask
        POP     D
        MOV     D,A                     ; D = mask for this column
DVLOOP: MOV     A,E
        ORA     A
        RZ
        MOV     A,C
        CPI     LCD_HEIGHT
        RNC
        PUSH    H
        PUSH    D
        PUSH    B
        CALL    LCD_SET_ADDR
        CALL    LCD_RD_BYTE
        POP     B
        POP     D
        ORA     D
        MOV     B,A                     ; B = new byte (x is not needed now)
        POP     H
        PUSH    H
        PUSH    D
        PUSH    B
        CALL    LCD_SET_ADDR
        POP     B
        MOV     A,B
        CALL    LCD_WR_BYTE
        POP     D
        POP     H
        PUSH    D
        MVI     E,LCD_HBBYTES
        MVI     D,0
        DAD     D                       ; next row
        POP     D
        INR     C
        DCR     E
        JNZ     DVLOOP
        RET

;------------------------------------------------------------------------------
; DRAW_SEG -- A = direction (0 = +X, 1 = +Y), B=x, C=y, E=length
;------------------------------------------------------------------------------
DRAW_SEG:
        ORA     A
        JZ      DRAW_H
        JMP     DRAW_V

;------------------------------------------------------------------------------
; LCD_CLEAR -- write 0 to every visible VRAM byte (30*128 = 3840).
; Caller should already have DI set for a long transfer.
;------------------------------------------------------------------------------
LCD_CLEAR:
        LXI     H,0
        CALL    LCD_SET_ADDR
        MVI     A,LCD_REG_WRITE
        CALL    LCD_CMD
        LXI     D,3840                  ; LCD_HBBYTES * LCD_HEIGHT
LC1:    CALL    LCD_WAIT
        XRA     A
        OUT     LCD_DR
        DCX     D
        MOV     A,D
        ORA     E
        JNZ     LC1
        RET

;------------------------------------------------------------------------------
; RENDER_MAZE -- clear LCD, stroke every wall segment, HUD divider, fruit,
;                energizers, and remaining pellets.
;------------------------------------------------------------------------------
RENDER_MAZE:
        DI
        CALL    LCD_CLEAR
        LXI     H,MAZE_SEGS
RMNEXT: MOV     A,M                     ; x
        INX     H
        MOV     B,A
        MOV     A,M                     ; y
        INX     H
        MOV     C,A
        MOV     A,M                     ; length
        INX     H
        MOV     E,A
        MOV     A,M                     ; direction
        INX     H
        MOV     D,A
        MOV     A,E
        ORA     A
        JZ      RMDONE                  ; length 0 = end of list
        PUSH    H
        MOV     A,D
        CALL    DRAW_SEG
        POP     H
        JMP     RMNEXT

RMDONE: ; playfield | HUD divider at x = 192
        MVI     B,HUD_X
        MVI     C,0
        MVI     E,LCD_HEIGHT
        MVI     A,DIR_DOWN
        CALL    DRAW_SEG

        CALL    DRAW_FRUIT
        CALL    DRAW_ENERG
        CALL    DRAW_PELLETS
        EI
        CALL    FRAME_DELAY
        RET

; Tiny plus at the fruit spawn point.
DRAW_FRUIT:
        MVI     B,FRUIT_X
        MVI     C,FRUIT_Y
        CALL    PLOT_OR
        MVI     B,FRUIT_X
        MVI     C,FRUIT_Y-1
        CALL    PLOT_OR
        MVI     B,FRUIT_X
        MVI     C,FRUIT_Y+1
        CALL    PLOT_OR
        MVI     B,FRUIT_X-1
        MVI     C,FRUIT_Y
        CALL    PLOT_OR
        MVI     B,FRUIT_X+1
        MVI     C,FRUIT_Y
        JMP     PLOT_OR

; 3x3 blocks at the four energizer pixels.
DRAW_ENERG:
        LXI     H,ENERG_XY
        MVI     D,ENERG_COUNT
DE1:    MOV     A,M
        INX     H
        MOV     B,A                     ; cx
        MOV     A,M
        INX     H
        MOV     C,A                     ; cy
        PUSH    H
        PUSH    D
        DCR     B
        DCR     C
        MVI     E,3                     ; 3 rows
DEY:    PUSH    B
        PUSH    D
        MVI     E,3                     ; 3 cols
        CALL    DRAW_H
        POP     D
        POP     B
        INR     C
        DCR     E
        JNZ     DEY
        POP     D
        POP     H
        DCR     D
        JNZ     DE1
        RET

; One pixel at the center of every still-present pellet bit.
DRAW_PELLETS:
        XRA     A
        STA     TMP0                    ; row 0..7
DPR:    LDA     TMP0
        MOV     C,A
        MVI     B,0
        LXI     H,PELLET_Y
        DAD     B
        MOV     A,M                     ; tile Y
        CALL    TILE_TO_PIX
        STA     TMP1                    ; pixel Y
        LDA     TMP0
        ADD     A
        ADD     A                       ; *2? need *3 for 3-byte rows
        MOV     C,A                     ; *2
        LDA     TMP0
        ADD     C                       ; *3
        MOV     C,A
        MVI     B,0
        LXI     H,PELLET_INIT
        DAD     B                       ; HL -> 3-byte mask for this row
        XRA     A
        STA     TMP2                    ; tile X 0..23
DPC:    LDA     TMP2
        CPI     MAP_W
        JZ      DPRN
        ; test bit TMP2 of (HL..)
        MOV     A,M                     ; we need the right byte
        ; byte = TMP2 / 8, bit = TMP2 & 7 (MSB first)
        PUSH    H
        LDA     TMP2
        RRC
        RRC
        RRC
        ANI     03H
        MOV     C,A
        MVI     B,0
        DAD     B
        LDA     TMP2
        ANI     07H
        MOV     B,A
        INR     B
        MOV     A,M
DPROT:  RLC
        DCR     B
        JNZ     DPROT
        POP     H
        JNC     DPSK                    ; bit was 0
        LDA     TMP2
        CALL    TILE_TO_PIX
        MOV     B,A                     ; pixel X
        LDA     TMP1
        MOV     C,A
        CALL    PLOT_OR
DPSK:   LDA     TMP2
        INR     A
        STA     TMP2
        JMP     DPC
DPRN:   LDA     TMP0
        INR     A
        STA     TMP0
        CPI     PELLET_ROWS
        JNZ     DPR
        RET
