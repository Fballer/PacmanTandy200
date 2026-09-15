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
;      Budget: under 300 bytes.  Pellet map is 63 bytes.  No 3.8KB screen buffer.
;   4. maze_data, ai_logic, render_maze, sprite_blit, and main are INCLUDEd
;      before the DS block so code/tables sit in the image and variables last.
;
; Assemble with:  python3 build.py  (reads this file; writes PACMAN.CO).
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

; Tandy 200 LCD (James Yi LCDIO.200 + VirtualT T200_Disp):
;   40 bytes per scanline, 6 pixels per byte, bit 0 = LEFT pixel.
;   40 * 6 = 240.  Visible VRAM = 40 * 128 = 5120 bytes.
; r0=63 screen on, r1=0 6-pixel pitch, r2=38 normal, r3=63 ROM duty.
LCD_WIDTH       EQU     240
LCD_HEIGHT      EQU     128
LCD_HBBYTES     EQU     40              ; bytes per scanline
LCD_HCHARS      EQU     38              ; James Yi "normal display"
LCD_PITCH_T200  EQU     00H             ; r1=0 -> 6 pixels/byte
LCD_MODE_T200   EQU     63              ; r0=63 -> screen on (includes gfx bit)
LCD_DUTY        EQU     63              ; James Yi ROM value
LCD_VRAM        EQU     5120            ; 40 * 128  (assembler has no MUL)

;==============================================================================
; 3. Playfield geometry  (narrower Excel 6x6 maze, on LCD bytes)
;------------------------------------------------------------------------------
; Tandy 200 packs 6 pixels per VRAM byte.  Tile (0,0) is at X=6 so every
; 6x6 wall/sprite ROW is exactly one LCD byte -- no split writes.
; Excel: blue=wall, black=pellet, green=HUD.  19x21 tiles + 1px border.
; Left green margin x=0..4, border x=5, maze x=6..119, border x=120,
; green HUD x=121..239.  Divider at x=126 (byte 21).
;------------------------------------------------------------------------------
PF_W            EQU     118             ; maze pixels (2px border + 19*6)
PF_H            EQU     128
HUD_W           EQU     114             ; 240-126
HUD_X           EQU     126             ; first HUD pixel (21*6, byte aligned)

TILE            EQU     6               ; 6x6 tiles = one LCD byte wide
MAP_W           EQU     19              ; Excel interior (two tiles narrower)
MAP_H           EQU     21
MAZE_X0         EQU     6               ; tile (0,0) pixel X  (6 % 6 == 0)
MAZE_Y0         EQU     1               ; tile (0,0) pixel Y
BORDER_X0       EQU     4               ; extra 2-pixel wall on the left
BORDER_X1       EQU     121             ; extra 2-pixel wall on the right
PEL_OX          EQU     2               ; 2x2 pellet offset inside a tile
PEL_OY          EQU     2

; Warp tunnels: tile row 9, pixel Y=55..60, wrap sprite X=6 <-> 114
TUN_TY          EQU     9
TUN_Y0          EQU     55
TUN_Y1          EQU     60
PF_XMAX         EQU     114             ; last tile's top-left X (tile 18)
PF_XWRAP        EQU     115             ; one pixel past last tile -> wrap to 6

; Ghost house tiles (gate is (9,8), interior (7..11, 9..10))
HOUSE_TX0       EQU     7
HOUSE_TX1       EQU     11
HOUSE_TY0       EQU     8
HOUSE_TY1       EQU     10
GATE_TX         EQU     9
GATE_TY         EQU     8
GATE_X          EQU     60              ; MAZE_X0 + 9*6
GATE_Y          EQU     49              ; MAZE_Y0 + 8*6
GATE_W          EQU     6

; Forbidden UP-turns: the two corridors of the T above the house.
FORBID_TY       EQU     7
FORBID_TX0      EQU     8
FORBID_TX1      EQU     10

; Fruit: tile (9,12) open slot under the house.  Plus at origin+(2,2).
FRUIT_TX        EQU     9
FRUIT_TY        EQU     12
FRUIT_X         EQU     62
FRUIT_Y         EQU     75

; Actor positions are sprite TOP-LEFT (6x6 fills the tile when aligned).
PAC_START_TX    EQU     9
PAC_START_TY    EQU     16              ; under the T on the energizer row
PAC_START_X     EQU     60
PAC_START_Y     EQU     97

BLINKY_X0       EQU     60              ; tile (9,7) above the gate
BLINKY_Y0       EQU     43
PINKY_X0        EQU     60              ; tile (9,10) house center
PINKY_Y0        EQU     61
INKY_X0         EQU     54              ; tile (8,10)
INKY_Y0         EQU     61
CLYDE_X0        EQU     66              ; tile (10,10)
CLYDE_Y0        EQU     61

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

; Scatter targets (tile coords).  Unsigned Manhattan cannot use 0FFH as
; -1: |ty-255| gets *smaller* going down, so Blinky circled the house.
SCAT_BLINKY_X   EQU     18
SCAT_BLINKY_Y   EQU     0               ; top-right
SCAT_PINKY_X    EQU     0
SCAT_PINKY_Y    EQU     0               ; top-left
SCAT_INKY_X     EQU     18
SCAT_INKY_Y     EQU     20              ; bottom-right
SCAT_CLYDE_X    EQU     0
SCAT_CLYDE_Y    EQU     20              ; bottom-left

CLYDE_SHY       EQU     8               ; tiles; below this, Clyde scatters

; Scatter/chase durations in 60Hz ticks (Dossier, level 1)
; 7s=420, 20s=1200, 7s=420, 20s=1200, 5s=300, 20s=1200, 5s=300, chase forever
TICKS_7S        EQU     420
TICKS_20S       EQU     1200
TICKS_5S        EQU     300

PELLET_BYTES    EQU     63              ; 21 rows x 3 bytes
PELLET_ROWS     EQU     21
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
; Phase 3 runs GAME_LOOP until BREAK, then EXIT returns to BASIC.
;==============================================================================
START:  DI
        MVI     A,1CH                   ; SIM: MSE + mask RST 7.5 + clear pending
        SIM
        LXI     H,0
        DAD     SP                      ; HL = BASIC's SP
        SHLD    SAVED_SP
        LXI     SP,LOCAL_STK_TOP        ; our private stack (grows down)

        CALL    KBD_INIT                ; PA/PB directions, col9 off, VT keyscan
        CALL    LCD_INIT_GFX            ; graphics mode, known registers
        CALL    AI_RESET                ; ghosts, timers, pellet RAM copy
        CALL    RENDER_MAZE             ; Phase 2: stroke walls + pellets
        CALL    SPRITES_INIT            ; Phase 2: 6x6 dirty-rect first paint
        CALL    WAIT_START              ; SPACE, then draw GO, then run
        CALL    GAME_LOOP               ; Phase 3: until reset
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

; Wait until busy=0.  Preserves A.  Timeout: VirtualT often leaves bit 7 stuck.
LCD_WAIT:
        PUSH    PSW
        PUSH    B
        MVI     B,08H
LWLOOP: IN      LCD_IR
        RLC
        JNC     LWOK
        DCR     B
        JNZ     LWLOOP
LWOK:   MVI     B,10H
LWDLY:  DCR     B
        JNZ     LWDLY
        POP     B
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
        RET

; Restore the T200 ROM's working HD61830 configuration (graphics, 8px pitch).
LCD_RESTORE:
        DI
        LXI     H,GFX_REST_TAB
        MVI     B,GFX_REST_LEN
        CALL    LCD_SEQ
        EI
        RET

; Character-mode init is unused: T200 BASIC already runs the HD61830 in
; graphics.  Switching modes on EXIT scrambles the MENU.

; (register, data) pairs
GFX_INIT_TAB:
        DB      LCD_REG_MODE,  LCD_MODE_T200
        DB      LCD_REG_PITCH, LCD_PITCH_T200
        DB      LCD_REG_HCHARS,LCD_HCHARS
        DB      LCD_REG_DUTY,  LCD_DUTY
        DB      LCD_REG_CPOS,  00H
        DB      LCD_REG_SAD_L, 00H
        DB      LCD_REG_SAD_H, 00H
        DB      LCD_REG_CAD_L, 00H
        DB      LCD_REG_CAD_H, 00H
GFX_INIT_LEN    EQU     9

GFX_REST_TAB:
        DB      LCD_REG_MODE,  LCD_MODE_T200
        DB      LCD_REG_PITCH, LCD_PITCH_T200
        DB      LCD_REG_HCHARS,LCD_HCHARS
        DB      LCD_REG_DUTY,  LCD_DUTY
        DB      LCD_REG_SAD_L, 00H
        DB      LCD_REG_SAD_H, 00H
GFX_REST_LEN    EQU     6

;==============================================================================
; Keyboard: POLL_KEYS in main.asm.  Do not IN 8155 PA/PB on VirtualT.
;------------------------------------------------------------------------------
; Hardware is the 8155.  We strobe columns ourselves (T200 ROM key entry
; points are not the Model 100 12CBH / 13DBH).
;
; Active-low strobe: 0 on the column bit.  A 0 at E0H means that key is
; down.  VirtualT packs SPACE/ARROWS as active-HIGH copies of
; gSpecialKeys (col6 bit0 = SPACE; col5 bit4-7 = L/R/U/D).  Real silicon
; is active-LOW.  POLL_KEYS accepts both, plus WASD.  PB bit0 must stay 1
; or IN E0 always returns column 9.
;==============================================================================

;==============================================================================
; Tiny 8085 math used by AI  (no MUL anywhere)
;------------------------------------------------------------------------------
; TILE_MUL6: A = tile 0..19 -> A = tile*6.  Destroys B.
; *4 + original is *5; add original again.
TILE_MUL6:
        MOV     B,A
        ADD     A                       ; *2
        ADD     A                       ; *4
        ADD     B                       ; *5
        ADD     B                       ; *6
        RET

; PIX_TO_TX / PIX_TO_TY: pixel -> tile.  Uses DIV6 (in render_maze.asm).
PIX_TO_TX:
        SUI     MAZE_X0
        JNC     DIV6Q
        XRA     A
        JMP     DIV6Q
PIX_TO_TY:
        SUI     MAZE_Y0
        JNC     DIV6Q
        XRA     A
DIV6Q:  CALL    DIV6
        MOV     A,D
        RET

; TILE_TO_PX / TILE_TO_PY: tile -> top-left pixel of that 6x6 cell.
TILE_TO_PX:
        CALL    TILE_MUL6
        ADI     MAZE_X0
        RET
TILE_TO_PY:
        CALL    TILE_MUL6
        ADI     MAZE_Y0
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
        INCLUDE main.asm

;==============================================================================
; RUNTIME RAM  -- every DS byte is counted.  Do not add a screen buffer.
;------------------------------------------------------------------------------
;   Not stored in the .CO (LOADM END must stay below T200 MAXRAM 0xEE90).
;   START / AI_RESET write every live field; leftover bytes are scratch.
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
FRIGHT_FLASHW:  DS      1               ; last ticks: flash blue/white
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
ENERG_MASK:     DS      1               ; bits 0-3 = energizer still there
DOT_EATEN:      DS      1               ; pellets eaten this board (fruit)
CLR_KIND:       DS      1               ; 0=none 1=pellet 2=energizer 3=fruit
CLR_X:          DS      1
CLR_Y:          DS      1

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

; 5 sprites x 16 bytes (unused -- we restroke, we do not save LCD bytes)
; SPR_BACK removed to stay under 300 RAM with 63-byte pellet map.

; Private call stack (grows toward LOCAL_STK).  48 bytes = 24 nested words.
LOCAL_STK:      DS      48
LOCAL_STK_TOP   EQU     LOCAL_STK+48

RAM_END:
RAM_USED        EQU     RAM_END-RAM_START
; RAM_USED counted at assemble time.  Hard cap is 300.  Do not add a framebuffer.

        END
