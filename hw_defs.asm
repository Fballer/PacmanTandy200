;==============================================================================
; hw_defs.asm -- Pac-Man for Tandy 200  (PHASE 1)
;------------------------------------------------------------------------------
; Pure Intel 8085.  NO Z80 instructions (no LDIR, DJNZ, IX, IY, JR).
; NO multiply opcode -- the 8085 does not have MUL.
;
; How this file fits the project
;   1. ORG 0D000H  -- load into the Tandy 200 high RAM bank (A000-FFFF).
;   2. On entry we snapshot BASIC's Stack Pointer so we can RET later.
;   3. All runtime RAM (DS) lives at the BOTTOM of this file.  Count it.
;      Budget: under 300 bytes.  We use 224 bytes.  No 3.8KB screen buffer.
;   4. maze_data.asm and ai_logic.asm are INCLUDEd before the DS block
;      so code/tables sit in ROM-image space and variables sit last.
;
; Assemble later with:  hw_defs.asm  (this file pulls the other two in).
;==============================================================================

        ORG     0D000H

;==============================================================================
; 1. Tandy 200 / HD61830 ports
;------------------------------------------------------------------------------
; Club 100 rcmap0.200 and James Yi's LCDIO.200 document the T200 LCD as:
;     OUT 255, register_number     then    OUT 254, data_byte
; which means:
;     port 0FFh = Instruction / Status   (HD61830 RS=1)
;     port 0FEh = Data                   (HD61830 RS=0)
; Busy flag = bit 7 of a READ from the instruction port.
;
; (Some secondary write-ups swap FE/FF.  The pair below is the measured
;  Tandy 200 mapping.  Using the swapped pair would never talk to the chip.)
;==============================================================================
LCD_IR          EQU     0FFH            ; command write, busy-flag read
LCD_DR          EQU     0FEH            ; data write / data read

PIO_CMD         EQU     0B0H            ; 8155 command/status
PIO_PA          EQU     0B1H            ; Port A: kbd columns 0-7, LCD, RTC
PIO_PB          EQU     0B2H            ; Port B: kbd column 9, LCD CS, beep
PIO_PC          EQU     0B3H            ; Port C: inputs
KBD_ROWS        EQU     0E0H            ; keyboard row return (E0-EF same)

BANK_PORT       EQU     0D8H            ; T200 ROM/RAM bank select (do not touch)

; Tandy 200 ROM helpers (T200 addresses, NOT Model 100's 12CBH/13DBH)
T200_CLS        EQU     4F4DH           ; clear character display via ROM
T200_BEEP       EQU     8FABH           ; beep
T200_HOME       EQU     4F49H           ; cursor home

;==============================================================================
; 2. HD61830 register / mode values
;------------------------------------------------------------------------------
; Instruction codes (write these to LCD_IR, then the data byte to LCD_DR).
;------------------------------------------------------------------------------
LCD_REG_MODE    EQU     00H             ; Mode Control
LCD_REG_PITCH   EQU     01H             ; Character Pitch (Hp in graphics)
LCD_REG_HCHARS  EQU     02H             ; Horizontal byte count minus 1
LCD_REG_DUTY    EQU     03H             ; Time divisions minus 1
LCD_REG_CPOS    EQU     04H             ; Cursor position (char mode)
LCD_REG_SAD_L   EQU     08H             ; Display start address low
LCD_REG_SAD_H   EQU     09H             ; Display start address high
LCD_REG_CAD_L   EQU     0AH             ; Cursor / write address low
LCD_REG_CAD_H   EQU     0BH             ; Cursor / write address high
LCD_REG_WRITE   EQU     0CH             ; Write display data (auto-inc)
LCD_REG_READ    EQU     0DH             ; Read display data (dummy+data)
LCD_REG_BCLR    EQU     0EH             ; Bit clear
LCD_REG_BSET    EQU     0FH             ; Bit set

; Mode Control data bits (instruction 00H):
;   bit0 CG ROM (0=internal)  bit1 1=graphics  bit2 1=display ON
;   bit3 1=master             bit4-5 cursor/blink
LCD_MODE_GFX    EQU     32H             ; graphics + display on (typical)
LCD_MODE_GFX2   EQU     0EH             ; alt: master+display+graphics, no cursor
LCD_MODE_CHAR   EQU     0CH             ; character + display on + master
LCD_MODE_OFF    EQU     00H             ; display off

LCD_PITCH_8     EQU     07H             ; Hp=8  (one byte = 8 pixels)
LCD_PITCH_6     EQU     05H             ; Hp=6  (T200 character pitch)

; Visible LCD is 240 x 128.  240/8 = 30 bytes/row.
; James Yi measured the controller walking 40 bytes/row (value 38 on r2).
; We program 30 so our 192+48 layout maps 1:1 onto the visible 240 pixels.
; If Phase 2 drawing looks shifted, change LCD_HBBYTES to 40 and HCHARS to 39.
LCD_WIDTH       EQU     240
LCD_HEIGHT      EQU     128
LCD_HBBYTES     EQU     30              ; visible bytes per scanline
LCD_HCHARS      EQU     29              ; HN-1  (30-1)
LCD_DUTY        EQU     127             ; NX-1  (128-1)  -> 1/128 duty

;==============================================================================
; 3. Playfield geometry  (Atari Lynx-style: whole maze on screen, no scroll)
;------------------------------------------------------------------------------
PF_W            EQU     192             ; playfield pixels (left)
PF_H            EQU     128             ; playfield pixels
HUD_W           EQU     48              ; HUD column (right)  192+48=240
HUD_X           EQU     192             ; first HUD pixel column

TILE            EQU     8               ; 8x8 tiles, corridors 7-8 px wide
TILE_MASK       EQU     07H
TILE_CENTER     EQU     04H             ; sprite center inside a tile
MAP_W           EQU     24              ; 192/8
MAP_H           EQU     16              ; 128/8

; Warp tunnels: one tile-row tall, wrap pixel X=0 <-> X=191
TUN_TY          EQU     7               ; tile row
TUN_Y0          EQU     56              ; pixel Y of tunnel (inclusive)
TUN_Y1          EQU     63              ; pixel Y of tunnel (inclusive)
PF_XMAX         EQU     191

; Ghost house (pixel box).  Gate is a SINGLE 8-pixel line on the roof.
HOUSE_X0        EQU     72
HOUSE_X1        EQU     119             ; inclusive
HOUSE_Y0        EQU     56
HOUSE_Y1        EQU     71              ; inclusive  (Y=56..72 as specified)
HOUSE_TX0       EQU     9
HOUSE_TX1       EQU     14
HOUSE_TY0       EQU     7
HOUSE_TY1       EQU     8
GATE_X          EQU     92              ; single-line door, 8 px wide
GATE_W          EQU     8
GATE_Y          EQU     56
GATE_TX         EQU     11
GATE_TY         EQU     7

; Forbidden UP-turns (Dossier "red zones"): corridor just above the house.
; Enforced in scatter+chase, ignored in frightened.
FORBID_TY       EQU     6
FORBID_TX0      EQU     8
FORBID_TX1      EQU     15

; Static fruit spawn (pixel center of tile 12,10 -- under the house)
FRUIT_X         EQU     100
FRUIT_Y         EQU     84
FRUIT_TX        EQU     12
FRUIT_TY        EQU     10

; Actor start positions (pixel centers)
PAC_START_X     EQU     100
PAC_START_Y     EQU     116
PAC_START_TX    EQU     12
PAC_START_TY    EQU     14

BLINKY_X0       EQU     100             ; just above the house, outside
BLINKY_Y0       EQU     52
PINKY_X0        EQU     100             ; house center
PINKY_Y0        EQU     68
INKY_X0         EQU     92              ; house left
INKY_Y0         EQU     68
CLYDE_X0        EQU     108             ; house right
CLYDE_Y0        EQU     68

;==============================================================================
; 4. Directions  (must stay 0-3 so "reverse" is XOR 2)
;------------------------------------------------------------------------------
DIR_RIGHT       EQU     0               ; +X
DIR_DOWN        EQU     1               ; +Y
DIR_LEFT        EQU     2               ; -X
DIR_UP          EQU     3               ; -Y

;==============================================================================
; 5. Ghost / global mode bytes
;------------------------------------------------------------------------------
MODE_SCATTER    EQU     0
MODE_CHASE      EQU     1
MODE_FRIGHT     EQU     2
MODE_EATEN      EQU     3               ; eyes, heading home
MODE_HOUSE      EQU     4               ; waiting inside the pen

GID_BLINKY      EQU     0
GID_PINKY       EQU     1
GID_INKY        EQU     2
GID_CLYDE       EQU     3
GHOST_COUNT     EQU     4
GHOST_SIZE      EQU     12              ; bytes per ghost (see DS block)

; Per-ghost byte offsets into a GHOST_SIZE record
GH_X            EQU     0
GH_Y            EQU     1
GH_DIR          EQU     2
GH_MODE         EQU     3
GH_TX           EQU     4
GH_TY           EQU     5
GH_TARGX        EQU     6
GH_TARGY        EQU     7
GH_FLAGS        EQU     8
GH_ANIM         EQU     9
GH_DOTCTR       EQU     10
GH_HOME         EQU     11              ; 1 = currently inside house

; GH_FLAGS bits
GF_SKIP         EQU     00000001B       ; frightened half-speed toggle
GF_REV          EQU     00000010B       ; reverse at next tile (mode change)
GF_ELROY        EQU     00000100B       ; Blinky Cruise Elroy (Phase 3)

; House-exit dot limits (Dossier, level 1).  Pinky=0 so he leaves at once.
DOTLIM_PINKY    EQU     0
DOTLIM_INKY     EQU     30
DOTLIM_CLYDE    EQU     60
; After a death the GLOBAL counter is used: Pinky=7, Inky=17, Clyde=32
GDOT_PINKY      EQU     7
GDOT_INKY       EQU     17
GDOT_CLYDE      EQU     32

; Scatter targets (tile coords, 8-bit wrap: 0FFH = -1, just outside the maze)
SCAT_BLINKY_X   EQU     24
SCAT_BLINKY_Y   EQU     0FFH            ; top-right
SCAT_PINKY_X    EQU     0FFH
SCAT_PINKY_Y    EQU     0FFH            ; top-left
SCAT_INKY_X     EQU     24
SCAT_INKY_Y     EQU     16              ; bottom-right
SCAT_CLYDE_X    EQU     0FFH
SCAT_CLYDE_Y    EQU     16              ; bottom-left

CLYDE_SHY       EQU     8               ; tiles; below this, Clyde scatters

; Scatter/chase durations in 60Hz ticks (Dossier, level 1)
; 7s=420, 20s=1200, 7s=420, 20s=1200, 5s=300, 20s=1200, 5s=300, chase forever
TICKS_7S        EQU     420
TICKS_20S       EQU     1200
TICKS_5S        EQU     300

PELLET_BYTES    EQU     24              ; 8 pellet-rows x 3 bytes = 192 bits
PELLET_ROWS     EQU     8
ENERG_COUNT     EQU     4

; Keyboard flag bits in KEY_FLAGS
KEY_RIGHT       EQU     00000001B
KEY_DOWN        EQU     00000010B
KEY_LEFT        EQU     00000100B
KEY_UP          EQU     00001000B
KEY_FIRE        EQU     00010000B       ; spacebar
KEY_EXIT        EQU     00100000B       ; BREAK

;==============================================================================
; ENTRY -- save BASIC's SP immediately, never return without restoring it.
;------------------------------------------------------------------------------
; Phase 3 will replace the idle wait with the real game loop.
; For Phase 1 we:  save SP, take a local stack, put the LCD in graphics
; mode, reset AI state, then sit in a tiny key-wait so BREAK returns to BASIC.
;==============================================================================
START:  DI
        LXI     H,0
        DAD     SP                      ; HL = BASIC's SP
        SHLD    SAVED_SP
        LXI     SP,LOCAL_STK_TOP        ; our private stack (grows down)

        CALL    LCD_INIT_GFX            ; graphics mode, known registers
        CALL    AI_RESET                ; ghosts, timers, pellet RAM copy
        CALL    RENDER_MAZE             ; Phase 2: stroke walls + pellets
        CALL    SPRITES_INIT            ; Phase 2: 7x7 dirty-rect first paint
        EI

P2WAIT: CALL    KEYSCAN
        LDA     KEY_FLAGS
        ANI     KEY_EXIT
        JZ      P2WAIT
        JMP     EXIT

;------------------------------------------------------------------------------
; Clean return to BASIC.
; Tandy 200 ROM draws characters IN GRAPHICS MODE (the chip is not sitting
; in HD61830 "character mode" while BASIC runs).  Switching the controller
; to true character mode on exit would scramble the MENU.  We restore the
; ROM-friendly graphics setup, ask ROM to CLS, put SP back, EI, RET.
;------------------------------------------------------------------------------
EXIT:   CALL    LCD_RESTORE             ; ROM-friendly HD61830 state
        CALL    T200_CLS                ; 4F4DH -- safe ROM clear
        LHLD    SAVED_SP
        SPHL
        EI
        RET

;==============================================================================
; LCD helpers  (used by init now; reused by the Phase 2 blitter)
;------------------------------------------------------------------------------
; ALWAYS poll busy (bit 7 of LCD_IR) before the next command/data byte.
; The HD61830 is slow.  A timeout is included so VirtualT cannot hang us
; if its busy flag is stuck.
;
; Blit routines in Phase 2 MUST wrap calls with DI / EI -- the T200 RST 7.5
; hardware timer will otherwise tear the LCD image mid-write.
;==============================================================================

; Wait until busy=0.  Preserves A via stack.  Timeout ~256 polls.
LCD_WAIT:
        PUSH    PSW
        PUSH    B
        MVI     B,00H
LWLOOP: IN      LCD_IR
        RLC                             ; bit 7 -> Carry
        JNC     LWOK                    ; CY=0 => not busy
        DCR     B
        JNZ     LWLOOP                  ; timeout: continue anyway
LWOK:   POP     B
        POP     PSW
        RET

; Write A = instruction/register number to the command port.
LCD_CMD:
        CALL    LCD_WAIT
        OUT     LCD_IR
        RET

; Write A = data byte to the data port.
LCD_DATA:
        CALL    LCD_WAIT
        OUT     LCD_DR
        RET

; HL = pointer to (reg, data) pairs, B = pair count.
LCD_SEQ:
        MOV     A,M
        INX     H
        CALL    LCD_CMD
        MOV     A,M
        INX     H
        CALL    LCD_DATA
        DCR     B
        JNZ     LCD_SEQ
        RET

; Switch HD61830 to graphics mode with our 240x128 layout.
; Wrapped in DI/EI so RST 7.5 cannot interrupt a register write.
LCD_INIT_GFX:
        DI
        LXI     H,GFX_INIT_TAB
        MVI     B,GFX_INIT_LEN
        CALL    LCD_SEQ
        EI
        RET

; Restore the T200 ROM's working HD61830 configuration (graphics, 8px pitch).
LCD_RESTORE:
        DI
        LXI     H,GFX_REST_TAB
        MVI     B,GFX_REST_LEN
        CALL    LCD_SEQ
        EI
        RET

; Optional: true HD61830 character mode (NOT used on EXIT -- see comment).
LCD_SET_CHAR:
        DI
        LXI     H,CHAR_INIT_TAB
        MVI     B,CHAR_INIT_LEN
        CALL    LCD_SEQ
        EI
        RET

; (register, data) pairs
GFX_INIT_TAB:
        DB      LCD_REG_MODE,  LCD_MODE_GFX
        DB      LCD_REG_PITCH, LCD_PITCH_8
        DB      LCD_REG_HCHARS,LCD_HCHARS
        DB      LCD_REG_DUTY,  LCD_DUTY
        DB      LCD_REG_CPOS,  00H
        DB      LCD_REG_SAD_L, 00H
        DB      LCD_REG_SAD_H, 00H
        DB      LCD_REG_CAD_L, 00H
        DB      LCD_REG_CAD_H, 00H
GFX_INIT_LEN    EQU     9

GFX_REST_TAB:
        DB      LCD_REG_MODE,  LCD_MODE_GFX
        DB      LCD_REG_PITCH, LCD_PITCH_8
        DB      LCD_REG_HCHARS,LCD_HCHARS
        DB      LCD_REG_DUTY,  LCD_DUTY
        DB      LCD_REG_SAD_L, 00H
        DB      LCD_REG_SAD_H, 00H
GFX_REST_LEN    EQU     6

CHAR_INIT_TAB:
        DB      LCD_REG_MODE,  LCD_MODE_CHAR
        DB      LCD_REG_PITCH, LCD_PITCH_6
CHAR_INIT_LEN   EQU     2

;==============================================================================
; Tandy 200 keyboard matrix scan
;------------------------------------------------------------------------------
; Hardware is the 8155 (same chip as Model 100) but the T200 key WELL and
; dedicated cursor cluster are NOT laid out like the M100 Technical Manual
; table.  We strobe columns ourselves rather than CALL the M100 addresses
; 12CBH / 13DBH (those entry points are in a different ROM on the T200).
;
; CRITICAL: Port B1/B2 also drive the LCD chip-selects and the RTC.  We
; snapshot them and write them back unchanged except for the column bit
; we are testing.  Never leave a column permanently selected.
;
; Active-low strobe: 0 on the column bit, 1s elsewhere.  A 0 in the row
; byte at E0H means that key is down.  We invert so KEY_FLAGS bits are 1
; when pressed.
;
; M100-compatible arrow column is bit 5 of B1:
;   row7=Right  row6=Left  row5=Up  row4=Down
; Space is column bit 6 of B1, row 0.
; BREAK is column 9 (B2 bit 0), row 7.
; If arrows feel swapped on real silicon, this is the one table to edit.
;==============================================================================
KEYSCAN:
        PUSH    B
        PUSH    D
        PUSH    H

        IN      PIO_PA
        STA     SAV_B1
        IN      PIO_PB
        STA     SAV_B2

        XRA     A
        STA     KEY_FLAGS

        ; --- arrows: column bit 5 of Port A ---
        LDA     SAV_B1
        ANI     11011111B               ; clear bit 5 (strobe col 5)
        OUT     PIO_PA
        IN      KBD_ROWS
        CMA                             ; 1 = pressed
        MOV     B,A
        ANI     10000000B               ; row 7 = Right
        JZ      KSNO_R
        LDA     KEY_FLAGS
        ORI     KEY_RIGHT
        STA     KEY_FLAGS
KSNO_R: MOV     A,B
        ANI     01000000B               ; row 6 = Left
        JZ      KSNO_L
        LDA     KEY_FLAGS
        ORI     KEY_LEFT
        STA     KEY_FLAGS
KSNO_L: MOV     A,B
        ANI     00100000B               ; row 5 = Up
        JZ      KSNO_U
        LDA     KEY_FLAGS
        ORI     KEY_UP
        STA     KEY_FLAGS
KSNO_U: MOV     A,B
        ANI     00010000B               ; row 4 = Down
        JZ      KSNO_D
        LDA     KEY_FLAGS
        ORI     KEY_DOWN
        STA     KEY_FLAGS
KSNO_D:
        ; restore Port A before the next strobe
        LDA     SAV_B1
        OUT     PIO_PA

        ; --- spacebar: column bit 6 of Port A, row 0 ---
        LDA     SAV_B1
        ANI     10111111B
        OUT     PIO_PA
        IN      KBD_ROWS
        CMA
        ANI     00000001B
        JZ      KSNO_SP
        LDA     KEY_FLAGS
        ORI     KEY_FIRE
        STA     KEY_FLAGS
KSNO_SP:
        LDA     SAV_B1
        OUT     PIO_PA

        ; --- BREAK: column 9 = Port B bit 0, row 7 ---
        LDA     SAV_B2
        ANI     11111110B
        OUT     PIO_PB
        IN      KBD_ROWS
        CMA
        ANI     10000000B
        JZ      KSNO_BR
        LDA     KEY_FLAGS
        ORI     KEY_EXIT
        STA     KEY_FLAGS
KSNO_BR:
        ; always put the 8155 back the way we found it
        LDA     SAV_B1
        OUT     PIO_PA
        LDA     SAV_B2
        OUT     PIO_PB

        POP     H
        POP     D
        POP     B
        RET

;==============================================================================
; Tiny 8085 math used by AI  (no MUL anywhere)
;------------------------------------------------------------------------------
; PIX_TO_TILE:  A = pixel 0..191  ->  A = tile 0..23   (unsigned / 8)
PIX_TO_TILE:
        RRC
        RRC
        RRC
        ANI     1FH
        RET

; TILE_TO_PIX:  A = tile  ->  A = pixel center (tile*8 + 4)
TILE_TO_PIX:
        ADD     A                       ; *2
        ADD     A                       ; *4
        ADD     A                       ; *8
        ADI     TILE_CENTER
        RET

; ABS_DIFF:  A = |A - C|   (8-bit, works for 0FFH used as -1)
ABS_DIFF:
        SUB     C
        RNC                             ; no borrow => A was >= C
        CMA
        INR     A                       ; two's complement
        RET

; MANHATTAN:  |DX| + |DY|
;   In : B=x1  C=x2  D=y1  E=y2
;   Out: A = distance (saturates at 255)
MANHATTAN:
        MOV     A,B
        CALL    ABS_DIFF                ; |x1-x2|, C is still x2
        MOV     B,A                     ; save |dx|
        MOV     A,D
        MOV     C,E
        CALL    ABS_DIFF                ; |y1-y2|
        ADD     B                       ; may overflow; we ignore CY
        RET

;==============================================================================
; Concatenate the other Phase 1 files here (tables, then AI code).
; Variables MUST come last so DS does not sit in the middle of the image.
;==============================================================================
        INCLUDE maze_data.asm
        INCLUDE ai_logic.asm
        INCLUDE render_maze.asm
        INCLUDE sprite_blit.asm

;==============================================================================
; RUNTIME RAM  -- every DS byte is counted.  Do not add a screen buffer.
;------------------------------------------------------------------------------
;   SAVED_SP .. KEY_RAW / temps / sprite backups / local stack
;   Total = RAM_END - RAM_START  (must stay < 300)
;==============================================================================
RAM_START:

SAVED_SP:       DS      2               ; BASIC stack pointer
SAV_B1:         DS      1               ; 8155 Port A snapshot
SAV_B2:         DS      1               ; 8155 Port B snapshot

PAC_X:          DS      1
PAC_Y:          DS      1
PAC_DIR:        DS      1
PAC_NDIR:       DS      1               ; buffered turn
PAC_ANIM:       DS      1
PAC_TX:         DS      1
PAC_TY:         DS      1
PAC_FLAGS:      DS      1

; 4 ghosts x 12 bytes = 48.  Layout matches GH_* offsets above.
GHOSTS:         DS      48
GHOST_BLINKY    EQU     GHOSTS
GHOST_PINKY     EQU     GHOSTS+12
GHOST_INKY      EQU     GHOSTS+24
GHOST_CLYDE     EQU     GHOSTS+36

MODE_CUR:       DS      1               ; 0=scatter 1=chase  (global)
MODE_IDX:       DS      1               ; index into MODE_TABLE
MODE_TMR:       DS      2               ; 16-bit tick countdown
FRIGHT_TMR:     DS      2               ; 0 = not frightened
FRAME_CNT:      DS      2
FRUIT_TMR:      DS      1
FRUIT_ON:       DS      1
FRUIT_IDX:      DS      1

SCORE:          DS      3               ; packed BCD, 6 digits
LIVES:          DS      1
LEVEL:          DS      1
PELLET_LEFT:    DS      1
ENERG_LEFT:     DS      1
GAME_STATE:     DS      1
GHOST_PTS:      DS      1               ; 0..3 -> 200/400/800/1600

PELLET_BITS:    DS      PELLET_BYTES    ; 24-byte live eaten/not-eaten mask

PRNG:           DS      2               ; 16-bit LFSR
KEY_FLAGS:      DS      1
KEY_RAW:        DS      1
DOT_GLOBAL:     DS      1               ; post-death house-release counter
DOT_GUSE:       DS      1               ; 0=personal limits, 1=global
ELROY:          DS      1

TMP0:           DS      1
TMP1:           DS      1
TMP2:           DS      1
TMP3:           DS      1
TMP4:           DS      1
TMP5:           DS      1
TMP6:           DS      1
TMP7:           DS      1
TMP_HL:         DS      2
BEST_DIR:       DS      1
BEST_DIST:      DS      1
CUR_GID:        DS      1

; Dirty-rectangle previous positions (Pac + 4 ghosts) for Phase 2 blitter
OLD_XY:         DS      10

; 5 sprites x 16 bytes (7 rows * 2 LCD bytes, padded).  7x7 can straddle
; a byte boundary, so each row saves TWO VRAM bytes.
SPR_BACK:       DS      80

; Private call stack (grows toward LOCAL_STK).  48 bytes = 24 nested words.
LOCAL_STK:      DS      48
LOCAL_STK_TOP   EQU     LOCAL_STK+48

RAM_END:
RAM_USED        EQU     RAM_END-RAM_START
; RAM_USED = 262 decimal.  Hard cap is 300.  Do not add a framebuffer.

        END
