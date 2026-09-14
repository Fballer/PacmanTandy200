;==============================================================================
; maze_data.asm -- Compact vector maze  (PHASE 1)
;------------------------------------------------------------------------------
; Included from hw_defs.asm.  Do NOT add an ORG -- we share 0D000H.
;
; Why a vector list instead of a 192x128 bitmap
;   A full-screen buffer is 240*128/8 = 3840 bytes.  That is forbidden.
;   Arcade-style solid 8x8 wall BLOCKS also waste memory and look chunky
;   on a 128-pixel-tall LCD.  We store thin 1-pixel STROKED segments:
;       DB  startX, startY, length, direction
;   direction uses DIR_RIGHT (0) or DIR_DOWN (1) only -- a line is always
;   drawn in the +X or +Y direction so we never need DIR_LEFT/DIR_UP here.
;
; Playfield
;   192 x 128 pixels on the left.  HUD is the remaining 48 x 128 on the
;   right (drawn in Phase 2/3).  Tile grid is 24 x 16 of 8-pixel tiles,
;   which gives 7-pixel interiors between 1-pixel walls (8 px center-to-
;   center).  That is the "7 to 8 pixel corridor" rule.
;
; Landmarks encoded below
;   * Outer double-wall (1 px outer + 1 px inset by 2) on top and bottom.
;     Side walls break for the warp tunnels.
;   * Warp tunnels at tile row 7 (pixel Y=56..63).  X=0 wraps to X=191.
;   * Ghost house pixel box X=72..119, Y=56..71 with a SINGLE-LINE gate
;     8 pixels wide at (92,56).
;   * Fruit spawn at (100,84) -- FRUIT_X/FRUIT_Y in hw_defs.asm.
;
; WALK_MAP is a 48-byte bit-board (16 rows x 3 bytes).  Bit=1 means the
; 8x8 TILE is a corridor.  Bit=0 is the interior of a wall island.  The
; renderer (Phase 2) draws only the outlines; the AI (this phase) walks
; the bit-board.  That keeps corridors 8 px wide without storing pixels.
;==============================================================================

;------------------------------------------------------------------------------
; ASCII map  (exactly 24 characters per row, 16 rows)
;   #  wall-island tile (not walkable; outline is stroked)
;   .  corridor
;   =  warp tunnel (walkable, wraps X)
;   H  ghost-house interior (ghosts walk, Pac-Man blocked in AI)
;   G  gate tile (walkable for ghosts leaving / eyes entering)
;
;     012345678901234567890123
;  0  ########################
;  1  #......................#
;  2  #.##.####.####.####.##.#
;  3  #.##.####.####.####.##.#
;  4  #......................#
;  5  #.##.##.##....##.##.##.#
;  6  #....##...####...##....#
;  7  =........GHHHHG........=
;  8  #........HHHHHH........#
;  9  #.##.##.##.##.##.##.##.#
; 10  #......................#     <- fruit at col 12
; 11  #.##.##.##....##.##.##.#
; 12  #....##..........##....#
; 13  #.##.####.####.####.##.#
; 14  #......................#     <- Pac-Man start at col 12
; 15  ########################
;------------------------------------------------------------------------------

;==============================================================================
; WALK_MAP -- 16 rows, 3 bytes each.  MSB of byte 0 = tile column 0.
;==============================================================================
WALK_MAP:
        DB      00H,00H,00H             ; y= 0 ########################
        DB      7FH,FFH,FEH             ; y= 1 #......................#
        DB      48H,42H,12H             ; y= 2 #.##.####.####.####.##.#
        DB      48H,42H,12H             ; y= 3 #.##.####.####.####.##.#
        DB      7FH,FFH,FEH             ; y= 4 #......................#
        DB      49H,3CH,92H             ; y= 5 #.##.##.##....##.##.##.#
        DB      79H,C3H,9EH             ; y= 6 #....##...####...##....#
        DB      0FFH,0FFH,0FFH          ; y= 7 =........GHHHHG........=
        DB      7FH,FFH,FEH             ; y= 8 #........HHHHHH........#
        DB      49H,24H,92H             ; y= 9 #.##.##.##.##.##.##.##.#
        DB      7FH,FFH,FEH             ; y=10 #......................#
        DB      49H,3CH,92H             ; y=11 #.##.##.##....##.##.##.#
        DB      79H,0FFH,9EH            ; y=12 #....##..........##....#
        DB      48H,42H,12H             ; y=13 #.##.####.####.####.##.#
        DB      7FH,FFH,FEH             ; y=14 #......................#
        DB      00H,00H,00H             ; y=15 ########################

;==============================================================================
; MAZE_SEGS -- 1-pixel vector list
; Format:  startX, startY, length (pixels plotted), direction (0=+X, 1=+Y)
; Terminator: length = 0
; First 10 entries are the double-wall / house / gate landmarks so Phase 2
; can draw them even if it only consumes the head of the list while testing.
;==============================================================================
MAZE_SEGS:
        ; --- landmarks ---
        DB        2,  2,188, DIR_RIGHT  ; inner top of double-wall
        DB        2,125,188, DIR_RIGHT  ; inner bottom of double-wall
        DB        2,  2, 54, DIR_DOWN   ; inner left, above tunnel
        DB        2, 64, 61, DIR_DOWN   ; inner left, below tunnel
        DB      189,  2, 54, DIR_DOWN   ; inner right, above tunnel
        DB      189, 64, 61, DIR_DOWN   ; inner right, below tunnel
        DB       72, 56, 20, DIR_RIGHT  ; house roof left of gate
        DB       92, 56,  8, DIR_RIGHT  ; SINGLE-LINE GATE
        DB      100, 56, 20, DIR_RIGHT  ; house roof right of gate
        DB       72, 56, 16, DIR_DOWN   ; house left wall
        DB      120, 56, 16, DIR_DOWN   ; house right wall
        DB       72, 72, 48, DIR_RIGHT  ; house floor

        ; --- outer shell (1 px) with tunnel gaps at Y=56..63 ---
        DB        0,  0,192, DIR_RIGHT  ; outer top
        DB        0,127,192, DIR_RIGHT  ; outer bottom
        DB        0,  0, 56, DIR_DOWN   ; outer left above tunnel
        DB        0, 64, 64, DIR_DOWN   ; outer left below tunnel
        DB      191,  0, 56, DIR_DOWN   ; outer right above tunnel
        DB      191, 64, 64, DIR_DOWN   ; outer right below tunnel

        ; --- island outlines, horizontal runs (merged collinear edges) ---
        DB        8,  8,176, DIR_RIGHT
        DB       16, 16, 16, DIR_RIGHT
        DB       40, 16, 32, DIR_RIGHT
        DB       80, 16, 32, DIR_RIGHT
        DB      120, 16, 32, DIR_RIGHT
        DB      160, 16, 16, DIR_RIGHT
        DB       16, 32, 16, DIR_RIGHT
        DB       40, 32, 32, DIR_RIGHT
        DB       80, 32, 32, DIR_RIGHT
        DB      120, 32, 32, DIR_RIGHT
        DB      160, 32, 16, DIR_RIGHT
        DB       16, 40, 16, DIR_RIGHT
        DB       40, 40, 16, DIR_RIGHT
        DB       64, 40, 16, DIR_RIGHT
        DB      112, 40, 16, DIR_RIGHT
        DB      136, 40, 16, DIR_RIGHT
        DB      160, 40, 16, DIR_RIGHT
        DB       16, 48, 16, DIR_RIGHT
        DB       64, 48, 64, DIR_RIGHT
        DB      160, 48, 16, DIR_RIGHT
        DB        0, 56,  8, DIR_RIGHT  ; tunnel ceiling lip, left
        DB       40, 56, 16, DIR_RIGHT
        DB      136, 56, 16, DIR_RIGHT
        DB      184, 56,  8, DIR_RIGHT  ; tunnel ceiling lip, right
        DB        0, 64,  8, DIR_RIGHT  ; tunnel floor lip, left
        DB      184, 64,  8, DIR_RIGHT  ; tunnel floor lip, right
        DB       16, 72, 16, DIR_RIGHT
        DB       40, 72, 16, DIR_RIGHT
        DB       64, 72, 16, DIR_RIGHT
        DB       88, 72, 16, DIR_RIGHT
        DB      112, 72, 16, DIR_RIGHT
        DB      136, 72, 16, DIR_RIGHT
        DB      160, 72, 16, DIR_RIGHT
        DB       16, 80, 16, DIR_RIGHT
        DB       40, 80, 16, DIR_RIGHT
        DB       64, 80, 16, DIR_RIGHT
        DB       88, 80, 16, DIR_RIGHT
        DB      112, 80, 16, DIR_RIGHT
        DB      136, 80, 16, DIR_RIGHT
        DB      160, 80, 16, DIR_RIGHT
        DB       16, 88, 16, DIR_RIGHT
        DB       40, 88, 16, DIR_RIGHT
        DB       64, 88, 16, DIR_RIGHT
        DB      112, 88, 16, DIR_RIGHT
        DB      136, 88, 16, DIR_RIGHT
        DB      160, 88, 16, DIR_RIGHT
        DB       16, 96, 16, DIR_RIGHT
        DB       64, 96, 16, DIR_RIGHT
        DB      112, 96, 16, DIR_RIGHT
        DB      160, 96, 16, DIR_RIGHT
        DB       16,104, 16, DIR_RIGHT
        DB       56,104, 16, DIR_RIGHT
        DB       80,104, 32, DIR_RIGHT
        DB      120,104, 16, DIR_RIGHT
        DB      160,104, 16, DIR_RIGHT
        DB       16,112, 16, DIR_RIGHT
        DB       40,112, 32, DIR_RIGHT
        DB       80,112, 32, DIR_RIGHT
        DB      120,112, 32, DIR_RIGHT
        DB      160,112, 16, DIR_RIGHT
        DB        8,120,176, DIR_RIGHT

        ; --- island outlines, vertical runs ---
        DB        8,  8, 48, DIR_DOWN
        DB        8, 64, 56, DIR_DOWN
        DB       16, 16, 16, DIR_DOWN
        DB       16, 40,  8, DIR_DOWN
        DB       16, 72,  8, DIR_DOWN
        DB       16, 88,  8, DIR_DOWN
        DB       16,104,  8, DIR_DOWN
        DB       32, 16, 16, DIR_DOWN
        DB       32, 40,  8, DIR_DOWN
        DB       32, 72,  8, DIR_DOWN
        DB       32, 88,  8, DIR_DOWN
        DB       32,104,  8, DIR_DOWN
        DB       40, 16, 16, DIR_DOWN
        DB       40, 40, 16, DIR_DOWN
        DB       40, 72,  8, DIR_DOWN
        DB       40, 88, 24, DIR_DOWN
        DB       56, 40, 16, DIR_DOWN
        DB       56, 72,  8, DIR_DOWN
        DB       56, 88, 16, DIR_DOWN
        DB       64, 40,  8, DIR_DOWN
        DB       64, 72,  8, DIR_DOWN
        DB       64, 88,  8, DIR_DOWN
        DB       72, 16, 16, DIR_DOWN
        DB       72,104,  8, DIR_DOWN
        DB       80, 16, 16, DIR_DOWN
        DB       80, 40, 16, DIR_DOWN
        DB       80, 72,  8, DIR_DOWN
        DB       80, 88,  8, DIR_DOWN
        DB       80,104,  8, DIR_DOWN
        DB       88, 72,  8, DIR_DOWN
        DB      104, 72,  8, DIR_DOWN
        DB      112, 16, 16, DIR_DOWN
        DB      112, 40, 16, DIR_DOWN
        DB      112, 72,  8, DIR_DOWN
        DB      112, 88,  8, DIR_DOWN
        DB      112,104,  8, DIR_DOWN
        DB      120, 16, 16, DIR_DOWN
        DB      120,104,  8, DIR_DOWN
        DB      128, 40,  8, DIR_DOWN
        DB      128, 72,  8, DIR_DOWN
        DB      128, 88,  8, DIR_DOWN
        DB      136, 40, 16, DIR_DOWN
        DB      136, 72,  8, DIR_DOWN
        DB      136, 88, 16, DIR_DOWN
        DB      152, 16, 16, DIR_DOWN
        DB      152, 40, 16, DIR_DOWN
        DB      152, 72,  8, DIR_DOWN
        DB      152, 88, 24, DIR_DOWN
        DB      160, 16, 16, DIR_DOWN
        DB      160, 40,  8, DIR_DOWN
        DB      160, 72,  8, DIR_DOWN
        DB      160, 88,  8, DIR_DOWN
        DB      160,104,  8, DIR_DOWN
        DB      176, 16, 16, DIR_DOWN
        DB      176, 40,  8, DIR_DOWN
        DB      176, 72,  8, DIR_DOWN
        DB      176, 88,  8, DIR_DOWN
        DB      176,104,  8, DIR_DOWN
        DB      184,  8, 48, DIR_DOWN
        DB      184, 64, 56, DIR_DOWN

        DB        0,  0,  0,  0         ; end of list (length=0)

;==============================================================================
; Pellet ROM image  -- 8 rows x 24 columns = 192 bits = 24 bytes
; Runtime copy lives in PELLET_BITS (DS 24).  Bit=1 means a pellet is still
; there.  Mapping: PELLET_Y[row] + column 0..23.  Energizers are NOT in
; this mask (they have their own 4-byte table).  House tiles have no pellets.
;
; PELLET_Y rows: 1,2,4,5,10,11,12,14   (skips house band 7-8 and box rows)
;==============================================================================
PELLET_Y:
        DB      1,2,4,5,10,11,12,14

PELLET_INIT:
        DB      3FH,0FFH,0FCH           ; ty=1  (energizers at col 1 and 22 off)
        DB      48H,42H,12H             ; ty=2
        DB      7FH,0FFH,0FEH           ; ty=4
        DB      49H,3CH,92H             ; ty=5
        DB      7FH,0FFH,0FEH           ; ty=10
        DB      49H,3CH,92H             ; ty=11
        DB      79H,0FFH,9EH            ; ty=12
        DB      3FH,0FFH,0FCH           ; ty=14 (energizers at col 1 and 22 off)

PELLET_COUNT0   EQU     128             ; bits set in PELLET_INIT

; Four energizers, pixel centers of the corner corridor tiles
ENERG_XY:
        DB      12, 12                  ; tile (1,1)
        DB     180, 12                  ; tile (22,1)
        DB      12,116                  ; tile (1,14)
        DB     180,116                  ; tile (22,14)

; Actor reset table: X, Y, DIR, MODE, TX, TY  (6 bytes x 5)
; Index 0 = Pac-Man, then Blinky, Pinky, Inky, Clyde.
ACTOR_INIT:
        DB      PAC_START_X, PAC_START_Y, DIR_LEFT,  0,           PAC_START_TX, PAC_START_TY
        DB      BLINKY_X0,   BLINKY_Y0,   DIR_LEFT,  MODE_SCATTER, 12, 6
        DB      PINKY_X0,    PINKY_Y0,    DIR_UP,    MODE_HOUSE,   12, 8
        DB      INKY_X0,     INKY_Y0,     DIR_UP,    MODE_HOUSE,   11, 8
        DB      CLYDE_X0,    CLYDE_Y0,    DIR_UP,    MODE_HOUSE,   13, 8

; Scatter-target table indexed by ghost id (Blinky, Pinky, Inky, Clyde)
SCATTER_XY:
        DB      SCAT_BLINKY_X, SCAT_BLINKY_Y
        DB      SCAT_PINKY_X,  SCAT_PINKY_Y
        DB      SCAT_INKY_X,   SCAT_INKY_Y
        DB      SCAT_CLYDE_X,   SCAT_CLYDE_Y

; House-exit pixel / tile (just above the gate, outside)
EXIT_TILE_X     EQU     12
EXIT_TILE_Y     EQU     6

; Level-1 scatter/chase schedule (Dossier).  Each record:
;   DB mode, DW ticks
; ticks=0FFFFH means "this mode forever".
; Frightened time is NOT in this table -- it PAUSES this timer.
MODE_TABLE:
        DB      MODE_SCATTER
        DW      TICKS_7S
        DB      MODE_CHASE
        DW      TICKS_20S
        DB      MODE_SCATTER
        DW      TICKS_7S
        DB      MODE_CHASE
        DW      TICKS_20S
        DB      MODE_SCATTER
        DW      TICKS_5S
        DB      MODE_CHASE
        DW      TICKS_20S
        DB      MODE_SCATTER
        DW      TICKS_5S
        DB      MODE_CHASE
        DW      0FFFFH
MODE_TAB_LEN    EQU     8               ; number of records

; Intersection tie-break order (Dossier): UP, LEFT, DOWN, RIGHT
DIR_PRI:
        DB      DIR_UP, DIR_LEFT, DIR_DOWN, DIR_RIGHT

; Pixel step for each direction (X then Y), indexed by DIR_*
DIR_DX:
        DB      1, 0, 0FFH, 0           ; R, D, L, U     (0FFH = -1)
DIR_DY:
        DB      0, 1, 0,    0FFH
