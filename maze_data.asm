;==============================================================================
; maze_data.asm -- Excel 6x6 Tandy 200 maze  (240x128 pixel grid)
;------------------------------------------------------------------------------
; Included from hw_defs.asm.  Do NOT add an ORG.
;
; Source: "Last super narrow walls pacman.xlsx"
;   Cell labels (pixel-accurate):
;     F  = free / unused.  Do not draw.
;     w  = wall pixel (1px outlines, rounded corners).
;     RP = regular pellet (2x2 in the middle of a 6x6 tile).
;     PP = power pellet (24-pixel diamond filling the 6x6 tile).
;     (blank) = corridor / house / tunnel.
;   19 x 21 tiles of 6x6.  Tile (0,0) = pixel (6,1).  Outer wall ~x=5 and x=120.
;   HUD/unused (F) starts at x=122.
;
; WALK_MAP is collision/AI (19 bits per row, packed 3 bytes, MSB = col 0).
; WALL_PAT/WALL_IDX are the Excel W pixels packed as LCD bytes (bit 0 = left).
; Pellets 2x2 at origin+(2,2).  Energizers 24-pixel diamond in the 6x6.
;==============================================================================

;------------------------------------------------------------------------------
; ASCII  19 columns, 21 rows
;   # wall  . pellet  o energizer  (space) open / house / tunnel
;
;     0123456789012345678
;  0  .........#.........
;  1  o###.###.#.###.###o
;  2  .###.###.#.###.###.
;  3  ...................
;  4  .###.#.#####.#.###.
;  5  .....#...#...#.....
;  6  ####.###.#.###.####
;  7  ####.#       #.####
;  8  ####.# ## ## #.####
;  9  ...... #   # ......
; 10  ####.# #   # #.####
; 11  ####.# ##### #.####
; 12  ####.#       #.####
; 13  ####.#.#####.#.####
; 14  .........#.........
; 15  .###.###.#.###.###.
; 16  o..#...........#..o
; 17  ##.#.#.#####.#.#.##
; 18  .....#...#...#.....
; 19  .#######.#.#######.
; 20  ...................
;------------------------------------------------------------------------------

WALK_MAP:
        DB      0FFH, 0BFH, 0E0H ; y= 0  .........#.........
        DB       88H, 0A2H,  20H ; y= 1  o###.###.#.###.###o
        DB       88H, 0A2H,  20H ; y= 2  .###.###.#.###.###.
        DB      0FFH, 0FFH, 0E0H ; y= 3  ...................
        DB       8AH,  0AH,  20H ; y= 4  .###.#.#####.#.###.
        DB      0FBH, 0BBH, 0E0H ; y= 5  .....#...#...#.....
        DB       08H, 0A2H,  00H ; y= 6  ####.###.#.###.####
        DB       0BH, 0FAH,  00H ; y= 7  ####.#       #.####
        DB       0AH,  4AH,  00H ; y= 8  ####.# ## ## #.####
        DB      0FEH, 0EFH, 0E0H ; y= 9  ...... #   # ......
        DB       0AH, 0EAH,  00H ; y=10  ####.# #   # #.####
        DB       0AH,  0AH,  00H ; y=11  ####.# ##### #.####
        DB       0BH, 0FAH,  00H ; y=12  ####.#       #.####
        DB       0AH,  0AH,  00H ; y=13  ####.#.#####.#.####
        DB      0FFH, 0BFH, 0E0H ; y=14  .........#.........
        DB       88H, 0A2H,  20H ; y=15  .###.###.#.###.###.
        DB      0EFH, 0FEH, 0E0H ; y=16  o..#...........#..o
        DB       2AH,  0AH,  80H ; y=17  ##.#.#.#####.#.#.##
        DB      0FBH, 0BBH, 0E0H ; y=18  .....#...#...#.....
        DB       80H, 0A0H,  20H ; y=19  .#######.#.#######.
        DB      0FFH, 0FFH, 0E0H ; y=20  ...................

PELLET_INIT:
        DB      0FFH, 0BFH, 0E0H ; y= 0
        DB       08H, 0A2H,  00H ; y= 1
        DB       88H, 0A2H,  20H ; y= 2
        DB      0FFH, 0FFH, 0E0H ; y= 3
        DB       8AH,  0AH,  20H ; y= 4
        DB      0FBH, 0BBH, 0E0H ; y= 5
        DB       08H, 0A2H,  00H ; y= 6
        DB       08H,  02H,  00H ; y= 7
        DB       08H,  02H,  00H ; y= 8
        DB      0FCH,  07H, 0E0H ; y= 9
        DB       08H,  02H,  00H ; y=10
        DB       08H,  02H,  00H ; y=11
        DB       08H,  02H,  00H ; y=12
        DB       0AH,  0AH,  00H ; y=13
        DB      0FFH, 0BFH, 0E0H ; y=14
        DB       88H, 0A2H,  20H ; y=15
        DB       6FH, 0FEH, 0C0H ; y=16
        DB       2AH,  0AH,  80H ; y=17
        DB      0FBH, 0BBH, 0E0H ; y=18
        DB       80H, 0A0H,  20H ; y=19
        DB      0FFH, 0FFH, 0E0H ; y=20

PELLET_COUNT0   EQU     183

; Energizers as TILE coordinates (tx, ty).  Drawn rounded (Excel 6).
ENERG_XY:
        DB      0, 1
        DB     18, 1
        DB      0,16
        DB     18,16

ACTOR_INIT:
        DB      PAC_START_X, PAC_START_Y, DIR_LEFT,  0,           PAC_START_TX, PAC_START_TY
        DB      BLINKY_X0,   BLINKY_Y0,   DIR_LEFT,  MODE_SCATTER,  9, 7
        DB      PINKY_X0,    PINKY_Y0,    DIR_UP,    MODE_HOUSE,    9,10
        DB      INKY_X0,     INKY_Y0,     DIR_UP,    MODE_HOUSE,    8,10
        DB      CLYDE_X0,    CLYDE_Y0,    DIR_UP,    MODE_HOUSE,   10,10

SCATTER_XY:
        DB      SCAT_BLINKY_X, SCAT_BLINKY_Y
        DB      SCAT_PINKY_X,  SCAT_PINKY_Y
        DB      SCAT_INKY_X,   SCAT_INKY_Y
        DB      SCAT_CLYDE_X,   SCAT_CLYDE_Y

EXIT_TILE_X     EQU     9
EXIT_TILE_Y     EQU     7

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
MODE_TAB_LEN    EQU     8

DIR_PRI:
        DB      DIR_UP, DIR_LEFT, DIR_DOWN, DIR_RIGHT

DIR_DX:
        DB      1, 0, 0FFH, 0
DIR_DY:
        DB      0, 1, 0,    0FFH

; Shortest-path home direction for eyes.  21 rows x 5 bytes, 2 bits per
; tile (tx 0 in bits 1-0).  BFS from house floor (9,10).  0=R 1=D 2=L 3=U.
HOME_DIR:
        DB      000H, 029H, 091H, 092H, 02AH  ; y= 0
        DB      001H, 001H, 011H, 010H, 010H  ; y= 1
        DB      001H, 001H, 011H, 010H, 010H  ; y= 2
        DB      000H, 090H, 00AH, 0A9H, 02AH  ; y= 3
        DB      003H, 013H, 000H, 031H, 030H  ; y= 4
        DB      003H, 003H, 091H, 0B2H, 02AH  ; y= 5
        DB      000H, 001H, 011H, 010H, 000H  ; y= 6
        DB      000H, 001H, 0A4H, 012H, 000H  ; y= 7
        DB      000H, 031H, 004H, 013H, 000H  ; y= 8
        DB      000H, 030H, 024H, 0ABH, 02AH  ; y= 9
        DB      000H, 033H, 02CH, 033H, 000H  ; y=10
        DB      000H, 033H, 000H, 033H, 000H  ; y=11
        DB      000H, 0B3H, 00AH, 033H, 000H  ; y=12
        DB      000H, 033H, 000H, 033H, 000H  ; y=13
        DB      000H, 0B3H, 002H, 0ABH, 02AH  ; y=14
        DB      003H, 003H, 033H, 030H, 030H  ; y=15
        DB      02BH, 02BH, 0BBH, 032H, 031H  ; y=16
        DB      010H, 033H, 000H, 033H, 001H  ; y=17
        DB      000H, 0B3H, 002H, 0B3H, 02AH  ; y=18
        DB      003H, 000H, 033H, 000H, 030H  ; y=19
        DB      0ABH, 002H, 0BBH, 02AH, 030H  ; y=20

;------------------------------------------------------------------------------
; Excel W pixels as LCD bytes for x=0..125 (21 bytes = 126 pixels).
; Bit 0 = leftmost.  Super-narrow outlines from Last super narrow walls pacman.xlsx
; 33 unique row patterns + 128-byte index.
;------------------------------------------------------------------------------
WALL_BYTES      EQU     21

WALL_PAT:
        DB       20H,  3FH,  3FH,  3FH,  3FH,  3FH,  3FH,  3FH,  3FH,  3FH,  21H,  3FH,  3FH,  3FH,  3FH,  3FH,  3FH,  3FH,  3FH,  3FH,  01H
        DB       10H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  12H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  02H
        DB       10H,  00H,  3CH,  3FH,  0FH,  00H,  3CH,  3FH,  0FH,  00H,  12H,  00H,  3CH,  3FH,  0FH,  00H,  3CH,  3FH,  0FH,  00H,  02H
        DB       10H,  00H,  02H,  00H,  10H,  00H,  02H,  00H,  10H,  00H,  12H,  00H,  02H,  00H,  10H,  00H,  02H,  00H,  10H,  00H,  02H
        DB       10H,  00H,  3CH,  3FH,  0FH,  00H,  3CH,  3FH,  0FH,  00H,  0CH,  00H,  3CH,  3FH,  0FH,  00H,  3CH,  3FH,  0FH,  00H,  02H
        DB       10H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  02H
        DB       10H,  00H,  3CH,  3FH,  0FH,  00H,  0CH,  00H,  3CH,  3FH,  3FH,  3FH,  0FH,  00H,  0CH,  00H,  3CH,  3FH,  0FH,  00H,  02H
        DB       10H,  00H,  02H,  00H,  10H,  00H,  12H,  00H,  02H,  00H,  00H,  00H,  10H,  00H,  12H,  00H,  02H,  00H,  10H,  00H,  02H
        DB       10H,  00H,  3CH,  3FH,  0FH,  00H,  12H,  00H,  3CH,  3FH,  21H,  3FH,  0FH,  00H,  12H,  00H,  3CH,  3FH,  0FH,  00H,  02H
        DB       10H,  00H,  00H,  00H,  00H,  00H,  12H,  00H,  00H,  00H,  12H,  00H,  00H,  00H,  12H,  00H,  00H,  00H,  00H,  00H,  02H
        DB       20H,  3FH,  3FH,  3FH,  0FH,  00H,  22H,  3FH,  0FH,  00H,  12H,  00H,  3CH,  3FH,  11H,  00H,  3CH,  3FH,  3FH,  3FH,  01H
        DB       00H,  00H,  00H,  00H,  10H,  00H,  02H,  00H,  10H,  00H,  12H,  00H,  02H,  00H,  10H,  00H,  02H,  00H,  00H,  00H,  00H
        DB       00H,  00H,  00H,  00H,  10H,  00H,  22H,  3FH,  0FH,  00H,  0CH,  00H,  3CH,  3FH,  11H,  00H,  02H,  00H,  00H,  00H,  00H
        DB       00H,  00H,  00H,  00H,  10H,  00H,  12H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  12H,  00H,  02H,  00H,  00H,  00H,  00H
        DB       00H,  00H,  00H,  00H,  10H,  00H,  12H,  00H,  3CH,  0FH,  00H,  3CH,  0FH,  00H,  12H,  00H,  02H,  00H,  00H,  00H,  00H
        DB       00H,  00H,  00H,  00H,  10H,  00H,  12H,  00H,  02H,  10H,  00H,  02H,  10H,  00H,  12H,  00H,  02H,  00H,  00H,  00H,  00H
        DB       30H,  3FH,  3FH,  3FH,  0FH,  00H,  0CH,  00H,  22H,  0FH,  00H,  3CH,  11H,  00H,  0CH,  00H,  3CH,  3FH,  3FH,  3FH,  03H
        DB       00H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  12H,  00H,  00H,  00H,  12H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  00H
        DB       30H,  3FH,  3FH,  3FH,  0FH,  00H,  0CH,  00H,  12H,  00H,  00H,  00H,  12H,  00H,  0CH,  00H,  3CH,  3FH,  3FH,  3FH,  03H
        DB       00H,  00H,  00H,  00H,  10H,  00H,  12H,  00H,  12H,  00H,  00H,  00H,  12H,  00H,  12H,  00H,  02H,  00H,  00H,  00H,  00H
        DB       00H,  00H,  00H,  00H,  10H,  00H,  12H,  00H,  22H,  3FH,  3FH,  3FH,  11H,  00H,  12H,  00H,  02H,  00H,  00H,  00H,  00H
        DB       00H,  00H,  00H,  00H,  10H,  00H,  12H,  00H,  02H,  00H,  00H,  00H,  10H,  00H,  12H,  00H,  02H,  00H,  00H,  00H,  00H
        DB       00H,  00H,  00H,  00H,  10H,  00H,  12H,  00H,  3CH,  3FH,  3FH,  3FH,  0FH,  00H,  12H,  00H,  02H,  00H,  00H,  00H,  00H
        DB       20H,  3FH,  3FH,  3FH,  0FH,  00H,  0CH,  00H,  3CH,  3FH,  21H,  3FH,  0FH,  00H,  0CH,  00H,  3CH,  3FH,  3FH,  3FH,  01H
        DB       10H,  00H,  3CH,  3FH,  11H,  00H,  3CH,  3FH,  0FH,  00H,  0CH,  00H,  3CH,  3FH,  0FH,  00H,  22H,  3FH,  0FH,  00H,  02H
        DB       10H,  00H,  00H,  00H,  12H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  00H,  12H,  00H,  00H,  00H,  02H
        DB       20H,  3FH,  0FH,  00H,  12H,  00H,  0CH,  00H,  3CH,  3FH,  3FH,  3FH,  0FH,  00H,  0CH,  00H,  12H,  00H,  3CH,  3FH,  01H
        DB       00H,  00H,  10H,  00H,  12H,  00H,  12H,  00H,  02H,  00H,  00H,  00H,  10H,  00H,  12H,  00H,  12H,  00H,  02H,  00H,  00H
        DB       20H,  3FH,  0FH,  00H,  0CH,  00H,  12H,  00H,  3CH,  3FH,  21H,  3FH,  0FH,  00H,  12H,  00H,  0CH,  00H,  3CH,  3FH,  01H
        DB       10H,  00H,  3CH,  3FH,  3FH,  3FH,  21H,  3FH,  0FH,  00H,  12H,  00H,  3CH,  3FH,  21H,  3FH,  3FH,  3FH,  0FH,  00H,  02H
        DB       10H,  00H,  02H,  00H,  00H,  00H,  00H,  00H,  10H,  00H,  12H,  00H,  02H,  00H,  00H,  00H,  00H,  00H,  10H,  00H,  02H
        DB       10H,  00H,  3CH,  3FH,  3FH,  3FH,  3FH,  3FH,  0FH,  00H,  0CH,  00H,  3CH,  3FH,  3FH,  3FH,  3FH,  3FH,  1FH,  00H,  02H
        DB       20H,  3FH,  3FH,  3FH,  3FH,  3FH,  3FH,  3FH,  3FH,  3FH,  3FH,  3FH,  3FH,  3FH,  3FH,  3FH,  3FH,  3FH,  3FH,  3FH,  03H
WALL_IDX:
        DB       00H,  01H,  01H,  01H,  01H,  01H,  01H,  01H,  02H,  03H,  03H,  03H,  03H,  03H,  03H,  03H
        DB       03H,  04H,  05H,  05H,  05H,  05H,  05H,  05H,  05H,  05H,  06H,  07H,  07H,  08H,  09H,  09H
        DB       09H,  09H,  09H,  09H,  09H,  09H,  0AH,  0BH,  0BH,  0CH,  0DH,  0DH,  0DH,  0DH,  0DH,  0DH
        DB       0DH,  0DH,  0EH,  0FH,  0FH,  10H,  11H,  11H,  11H,  11H,  11H,  11H,  11H,  11H,  12H,  13H
        DB       13H,  13H,  13H,  13H,  14H,  15H,  15H,  16H,  0DH,  0DH,  0DH,  0DH,  0DH,  0DH,  0DH,  0DH
        DB       16H,  15H,  15H,  17H,  01H,  01H,  01H,  01H,  01H,  01H,  01H,  01H,  02H,  03H,  03H,  18H
        DB       19H,  19H,  19H,  19H,  19H,  19H,  19H,  19H,  1AH,  1BH,  1BH,  1CH,  09H,  09H,  09H,  09H
        DB       09H,  09H,  09H,  09H,  1DH,  1EH,  1EH,  1FH,  05H,  05H,  05H,  05H,  05H,  05H,  05H,  20H
