;==============================================================================
; render_maze.asm -- HD61830 1-pixel wall renderer  (PHASE 2)
;------------------------------------------------------------------------------
; Included from hw_defs.asm.  Do NOT add an ORG.
;
; Blits Excel W (wall) pixels as LCD bytes (bit 0 = left, 6 px/byte).
; F / unused pixels stay clear.  RP / PP are drawn on top.
;
; Tandy 200 / VirtualT pixel address (James Yi LCDIO.200):
;     addr = y * 40 + x/6
;     bit  = 01H << (x % 6)     ; LSB is the LEFT pixel, 6 pixels per byte
;
; y*40 is y*32 + y*8  (shifts and add -- no MUL).  x/6 is repeated subtract.
;
; Wrap every blit in DI/EI.  RST 7.5 will tear the image if it fires
; between the read and the write of a byte.
;==============================================================================

; Maze / pellet bitboards are 8 bits, MSB = leftmost TILE.  Unrelated to LCD.
BITMSK:
        DB      80H,40H,20H,10H,08H,04H,02H,01H

; LCD pixel bits inside one 6-pixel byte.  Index = x % 6.  Bit 0 = left.
LCD_BITS:
        DB      01H,02H,04H,08H,10H,20H

;------------------------------------------------------------------------------
; LCD_SET_ADDR -- HL = VRAM address (0 .. 40*128-1)
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
; DIV6 -- A = value 0..239
;   Out: D = A/6,  A = A%6
;   Repeated subtract (max 40 loops).  Destroys only A and D.
;------------------------------------------------------------------------------
DIV6:
        MVI     D,0
D6LP:   CPI     6
        RC                              ; A < 6: CY=1, D = quotient
        SUI     6
        INR     D
        JMP     D6LP

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
        DAD     H                       ; *4
        DAD     H                       ; *8
        PUSH    H                       ; save y*8
        DAD     H                       ; *16
        DAD     H                       ; *32
        POP     D                       ; DE = y*8
        DAD     D                       ; HL = y*40
        POP     B
        PUSH    B
        PUSH    H                       ; y*40
        MOV     A,B                     ; x
        CALL    DIV6                    ; D=x/6, A=x%6
        MOV     C,A                     ; C = remainder (bit 0..5)
        MOV     A,D
        MOV     E,A
        MVI     D,0                     ; DE = x/6
        POP     H
        DAD     D                       ; HL = y*40 + x/6
        MOV     A,C
        MOV     E,A
        MVI     D,0
        PUSH    H
        LXI     H,LCD_BITS
        DAD     D
        MOV     A,M                     ; mask  01H<<bit
        POP     H
        POP     B
        RET

;------------------------------------------------------------------------------
; PLOT_BSET -- set pixel (B,C) via HD61830 Bit Set.  No LCD read.
; VirtualT RAM_BIT_SET: mask = 1 << bit_number, bit 0 = left.
;------------------------------------------------------------------------------
PLOT_BSET:
        MOV     A,B
        CPI     LCD_WIDTH
        RNC
        MOV     A,C
        CPI     LCD_HEIGHT
        RNC
        PUSH    B
        PUSH    D
        CALL    XY_TO_ADDR
        CALL    LCD_SET_ADDR
        POP     D
        POP     B
        PUSH    B
        MOV     A,B
        CALL    DIV6
        MOV     C,A
        MVI     A,LCD_REG_BSET
        CALL    LCD_CMD
        MOV     A,C
        CALL    LCD_DATA
        POP     B
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

; OR all 6 pixels of the byte that contains (B,C).  Caller aligns x % 6 == 0.
PLOT_BYTE_OR:
        PUSH    D
        CALL    XY_TO_ADDR
        PUSH    H
        CALL    LCD_SET_ADDR
        CALL    LCD_RD_BYTE
        ORI     3FH                     ; bits 0-5 only
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
DHLOOP: MOV     A,E
        ORA     A
        RZ                              ; fast-path may land on 0
        MOV     A,B
        CALL    DIV6                    ; A = x % 6
        ORA     A
        JNZ     DHPIX                   ; not aligned: one pixel
        MOV     A,E
        CPI     6
        JC      DHPIX                   ; tail shorter than a 6-pixel byte
        PUSH    B
        PUSH    D
        CALL    PLOT_BYTE_OR
        POP     D
        POP     B
        MOV     A,B
        ADI     6
        MOV     B,A
        MOV     A,E
        SUI     6
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
; LCD_CLEAR -- write 0 to every visible VRAM byte (40*128 = 5120).
; Caller should already have DI set for a long transfer.
;------------------------------------------------------------------------------
LCD_CLEAR:
        LXI     H,0
        CALL    LCD_SET_ADDR
        MVI     A,LCD_REG_WRITE
        CALL    LCD_CMD
        LXI     D,LCD_VRAM              ; 40 * 128 = 5120
LC1:    CALL    LCD_WAIT
        XRA     A
        OUT     LCD_DR
        DCX     D
        MOV     A,D
        ORA     E
        JNZ     LC1
        RET

;------------------------------------------------------------------------------
; RENDER_MAZE -- clear LCD, blit Excel W pixels, then RP/PP dots.
;------------------------------------------------------------------------------
RENDER_MAZE:
        DI
        CALL    LCD_CLEAR
        CALL    DRAW_WALLS              ; Excel W outlines + RP/PP in one pass
        CALL    FRAME_DELAY
        RET

; A = pattern id 0..32  ->  HL = WALL_PAT + A*21  (16-bit; 32*21 = 672)
WALL_PAT_PTR:
        MOV     L,A
        MVI     H,0
        DAD     H                       ; *2
        DAD     H                       ; *4
        MOV     E,L
        MOV     D,H                     ; DE = *4
        DAD     H                       ; *8
        DAD     H                       ; *16
        DAD     D                       ; *20
        MOV     E,A
        MVI     D,0
        DAD     D                       ; *21
        LXI     D,WALL_PAT
        DAD     D
        RET

; B = LCD byte index 0..20, C = y.  A = wall bits + live 6x6 pellet sprites.
; RP: bits 2-3 on oy 2-3 (2x2).  PP (super-narrow Excel, 24-pixel diamond):
;   oy 0,5 = 00CH  oy 1,4 = 01EH  oy 2,3 = 03FH
COMPOSE_BYTE:
        PUSH    B
        MOV     A,C
        MOV     E,A
        MVI     D,0
        LXI     H,WALL_IDX
        DAD     D
        MOV     A,M
        CALL    WALL_PAT_PTR
        POP     B
        PUSH    B
        MOV     A,B
        MOV     E,A
        MVI     D,0
        DAD     D
        MOV     A,M
        STA     TMP1
        POP     B
        MOV     A,B
        ORA     A
        JZ      CB_DONE                 ; x=0..5 border, no pellets
        CPI     20
        JZ      CB_DONE                 ; x=120..125 border
        DCR     A
        STA     TMP7                    ; tx
        MOV     A,C
        CPI     1
        JC      CB_DONE
        CPI     127
        JZ      CB_DONE
        PUSH    B
        SUI     1
        CALL    DIV6                    ; D=ty  A=oy
        STA     TMP2
        MOV     A,D
        CPI     MAP_H
        JNC     CB_POP
        STA     TMP5
        LDA     TMP2
        CPI     2
        JC      CB_EN
        CPI     4
        JNC     CB_EN
        CALL    PEL_ON
        JNC     CB_EN
        LDA     TMP1
        ORI     00CH
        STA     TMP1
CB_EN:  CALL    EN_ON
        JNC     CB_POP
        LDA     TMP2                    ; oy 0..5
        CPI     6
        JNC     CB_POP
        MOV     E,A
        MVI     D,0
        LXI     H,PP_OY
        DAD     D
        MOV     A,M
        MOV     B,A
        LDA     TMP1
        ORA     B
        STA     TMP1
CB_POP: POP     B
CB_DONE:
        LDA     TMP1
        RET

; LCD bits for one PP row (bit 0 = left).  Diamond: ..##.. / .####. / ######
PP_OY:
        DB      00CH, 01EH, 03FH, 03FH, 01EH, 00CH

; CY=1 if PELLET_BITS still has (TMP7,TMP5).
PEL_ON:
        LDA     TMP5
        ADD     A
        MOV     C,A
        LDA     TMP5
        ADD     C
        MOV     C,A
        MVI     B,0
        LXI     H,PELLET_BITS
        DAD     B
        LDA     TMP7
        RRC
        RRC
        RRC
        ANI     03H
        MOV     C,A
        MVI     B,0
        DAD     B
        LDA     TMP7
        ANI     07H
        MOV     B,A
        INR     B
        MOV     A,M
POROT:  RLC
        DCR     B
        JNZ     POROT
        RET

; CY=1 if (TMP7,TMP5) is a live energizer.
EN_ON:
        LXI     H,ENERG_XY
        MVI     B,0
ENE1:   LDA     TMP7
        CMP     M
        INX     H
        JNZ     ENE2
        LDA     TMP5
        CMP     M
        JNZ     ENE2
        LDA     ENERG_MASK
        MOV     C,B
        INR     C
ENER:   RRC
        DCR     C
        JNZ     ENER
        RET
ENE2:   INX     H
        INR     B
        MOV     A,B
        CPI     ENERG_COUNT
        JNZ     ENE1
        XRA     A
        RET

; Blit Excel W pixels + live RP/PP into LCD bytes 0..20 of every row.
DRAW_WALLS:
        XRA     A
        STA     TMP0
DWY:    LDA     TMP0
        CPI     LCD_HEIGHT
        RNC
        MOV     C,A
        MVI     B,0
        CALL    XY_TO_ADDR
        CALL    LCD_SET_ADDR
        MVI     A,LCD_REG_WRITE
        CALL    LCD_CMD
        XRA     A
        STA     TMP6
DWB:    LDA     TMP6
        CPI     WALL_BYTES
        JZ      DWBN
        MOV     B,A
        LDA     TMP0
        MOV     C,A
        CALL    COMPOSE_BYTE
        CALL    LCD_DATA
        LDA     TMP6
        INR     A
        STA     TMP6
        JMP     DWB
DWBN:   LDA     TMP0
        INR     A
        STA     TMP0
        JMP     DWY

; One maze LCD byte at pixel (B,C).  Used when a sprite leaves a byte.
WALL_RESTORE_BYTE:
        MOV     A,C
        CPI     LCD_HEIGHT
        RNC
        PUSH    B
        CALL    XY_TO_ADDR
        CALL    LCD_SET_ADDR
        MVI     A,LCD_REG_WRITE
        CALL    LCD_CMD
        POP     B
        MOV     A,B
        CALL    DIV6
        MOV     A,D
        CPI     WALL_BYTES
        RNC
        MOV     B,A
        CALL    COMPOSE_BYTE
        JMP     LCD_DATA

; Maze byte(s) covering 6 pixels at (B,C).  Aligned = one byte.
WALL_RESTORE_ROW:
        MOV     A,C
        CPI     LCD_HEIGHT
        RNC
        PUSH    B
        CALL    XY_TO_ADDR
        CALL    LCD_SET_ADDR
        MVI     A,LCD_REG_WRITE
        CALL    LCD_CMD
        POP     B
        MOV     A,B
        CALL    DIV6                    ; D=x/6  A=x%6  C=y still
        PUSH    PSW
        MOV     A,D
        CPI     WALL_BYTES
        JNC     WRR_HUD
        PUSH    D
        MOV     B,A
        CALL    COMPOSE_BYTE
        CALL    LCD_DATA
        POP     D
        POP     PSW
        ORA     A
        RZ                              ; aligned: sprite lived in this byte
        MOV     A,D
        INR     A
        CPI     WALL_BYTES
        RNC
        MOV     B,A
        CALL    COMPOSE_BYTE
        JMP     LCD_DATA
WRR_HUD:
        POP     PSW
        RET

; Restore Excel walls + remaining pellets under a 6x6 at (B,C).
WALL_RESTORE_BOX:
        PUSH    B
        MOV     A,B
        STA     TMP3
        MOV     A,C
        STA     TMP4
        XRA     A
        STA     TMP6
WRBX:   LDA     TMP6
        CPI     6
        JZ      WRBXD
        LDA     TMP4
        MOV     C,A
        LDA     TMP6
        ADD     C
        MOV     C,A
        LDA     TMP3
        MOV     B,A
        CALL    WALL_RESTORE_ROW
        LDA     TMP6
        INR     A
        STA     TMP6
        JMP     WRBX
WRBXD:  POP     B
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

; 6x6 power-pellet sprite at each live energizer tile (graphic in the middle).
DRAW_ENERG:
        LXI     H,ENERG_XY
        MVI     D,0
DE1:    MOV     A,D
        CPI     ENERG_COUNT
        RZ
        LDA     ENERG_MASK
        MOV     C,D
        INR     C
DEROT:  RRC
        DCR     C
        JNZ     DEROT
        JNC     DE_SK
        MOV     A,M
        INX     H
        CALL    TILE_TO_PX
        MOV     B,A
        MOV     A,M
        INX     H
        CALL    TILE_TO_PY
        MOV     C,A
        PUSH    H
        PUSH    D
        LXI     H,SPR_POWER
        CALL    SPR_DRAW
        POP     D
        POP     H
        JMP     DE_N
DE_SK:  INX     H
        INX     H
DE_N:   INR     D
        JMP     DE1

; 6x6 regular-pellet sprite at every still-present RP tile (graphic in middle).
DRAW_PELLETS:
        XRA     A
        STA     TMP0                    ; tile Y
DPR:    LDA     TMP0
        CPI     MAP_H
        RNC
        CALL    TILE_TO_PY
        STA     TMP1
        LDA     TMP0
        ADD     A
        MOV     C,A
        LDA     TMP0
        ADD     C                       ; *3
        MOV     C,A
        MVI     B,0
        LXI     H,PELLET_BITS
        DAD     B
        XRA     A
        STA     TMP2
DPC:    LDA     TMP2
        CPI     MAP_W
        JZ      DPRN
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
        JNC     DPSK
        LDA     TMP2
        CALL    TILE_TO_PX
        MOV     B,A
        LDA     TMP1
        MOV     C,A
        PUSH    H
        LXI     H,SPR_PELLET
        CALL    SPR_DRAW
        POP     H
DPSK:   LDA     TMP2
        INR     A
        STA     TMP2
        JMP     DPC
DPRN:   LDA     TMP0
        INR     A
        STA     TMP0
        JMP     DPR

; If tile (D=tx, E=ty) still has a pellet, draw its 6x6 sprite.
PELLET_DOT:
        MOV     A,E
        STA     TMP5
        MOV     A,D
        STA     TMP4
        LDA     TMP5
        CPI     MAP_H
        RNC
        ADD     A
        MOV     C,A
        LDA     TMP5
        ADD     C
        MOV     C,A
        MVI     B,0
        LXI     H,PELLET_BITS
        DAD     B
        LDA     TMP4
        RRC
        RRC
        RRC
        ANI     03H
        MOV     C,A
        MVI     B,0
        DAD     B
        LDA     TMP4
        ANI     07H
        MOV     B,A
        INR     B
        MOV     A,M
PDROT:  RLC
        DCR     B
        JNZ     PDROT
        RNC
        LDA     TMP4
        CALL    TILE_TO_PX
        MOV     B,A
        LDA     TMP5
        CALL    TILE_TO_PY
        MOV     C,A
        LXI     H,SPR_PELLET
        JMP     SPR_DRAW

PLOT_2X2:
        CALL    PLOT_OR
        INR     B
        CALL    PLOT_OR
        DCR     B
        INR     C
        CALL    PLOT_OR
        INR     B
        JMP     PLOT_OR
