# Pac-Man for the Tandy 200

Authentic Pac-Man in **pure Intel 8085 assembly** for the Tandy 200 portable (Hitachi HD61830 LCD, 240×128).

No Z80 instructions. No multiply. No full-screen framebuffer. Maze walls are thin vector strokes; sprites are dirty-rectangle blits straight to the LCD.

## Status

| Phase | What | State |
|-------|------|--------|
| 1 | Hardware defs, vector maze, Dossier ghost AI | Done |
| 2 | LCD wall renderer + sprite blitter | Done |
| 3 | Game loop (input, pellets, timers) | Not started |
| 4 | `build.py` → `.co` file + VirtualT guide | Not started |

Load address / entry: `0xD000`. Runtime `DS` budget: under 300 bytes.

## Files

- `hw_defs.asm` — ports, `ORG 0D000H`, entry/exit, LCD helpers, RAM
- `maze_data.asm` — 192×128 playfield vector segments + walk map
- `ai_logic.asm` — Blinky / Pinky / Inky / Clyde targeting (Pac-Man Dossier)
- `render_maze.asm` — 1-pixel wall renderer (Phase 2)
- `sprite_blit.asm` — 7×7 dirty-rect blitter (Phase 2)

## Hardware notes

- CPU: 80C85 @ ~2.4576 MHz
- LCD: HD61830 command `0FFh`, data `0FEh`, busy = status bit 7
- Wrap LCD blits in `DI` / `EI` (RST 7.5 tears the screen)
- Save `SP` on entry; restore and `RET` to BASIC on BREAK
