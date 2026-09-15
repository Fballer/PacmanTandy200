# Pac-Man for the Tandy 200

Authentic Pac-Man in **pure Intel 8085 assembly** for the Tandy 200 portable (Hitachi HD61830 LCD, 240×128).

No Z80 instructions. No multiply. No full-screen framebuffer. Maze walls are thin vector strokes; sprites are dirty-rectangle blits straight to the LCD.

## Status

| Phase | What | State |
|-------|------|--------|
| 1 | Hardware defs, vector maze, Dossier ghost AI | Done |
| 2 | LCD wall renderer + sprite blitter | Done |
| 3 | Game loop (input, pellets, timers) | Done |
| 4 | `build.py` → `PACMAN.CO` + VirtualT guide | Done |

Load address / entry: `0xD000` (decimal **53248**). Runtime `DS` budget: 267 bytes (cap 300). Assembled image: 5638 bytes of machine code plus the 6-byte `.CO` header.

## Build the `.CO` file

You only need Python 3. No extra assembler, no pip packages.

```
python3 build.py
```

That reads `hw_defs.asm` (which `INCLUDE`s the other `.asm` files) and writes:

- `PACMAN.CO` — what the Tandy 200 / VirtualT loads
- `PACMAN.LST` — a human-readable listing (address + hex + source), for debugging

The `.CO` header is the standard Kyocera/Tandy 6-byte prefix, little-endian:

| Bytes | Meaning | This project |
|-------|---------|--------------|
| 0–1 | Load address | `D000H` |
| 2–3 | Payload length (not counting the header) | size of the machine code |
| 4–5 | Execution address | `D000H` (`START`) |

## Files

- `build.py` — tiny two-pass 8085 assembler (Phase 4)
- `PACMAN.CO` — load this in VirtualT
- `hw_defs.asm` — ports, `ORG 0D000H`, entry/exit, LCD helpers, RAM
- `maze_data.asm` — 192×128 playfield vector segments + walk map
- `ai_logic.asm` — Blinky / Pinky / Inky / Clyde targeting (Pac-Man Dossier)
- `render_maze.asm` — 1-pixel wall renderer (Phase 2)
- `sprite_blit.asm` — 7×7 dirty-rect blitter (Phase 2)
- `main.asm` — keyboard, Pac-Man motion, pellets, deaths, level loop (Phase 3)

## Play in VirtualT (beginner walkthrough)

[VirtualT](https://sourceforge.net/projects/virtualt/) is a Model 100 / Tandy 200 emulator for Windows, Linux, and macOS.

### 1. Switch the emulator to a Tandy 200

1. Start VirtualT.
2. Menu **Emulation → Model → T200**.
3. Power on / reset if it still looks like a Model 100.

You should see the Tandy 200 MENU (date, BASIC, TEXT, TELCOM, …).

### 2. Put `PACMAN.CO` in the laptop’s RAM disk

1. Menu **File → Load file from HD**.
2. Choose `PACMAN.CO` from this folder.

The name **PACMAN.CO** fits the Tandy 6.2 filename limit. It should appear as `PACMAN.CO` on the MENU.

That copy lives in the RAM *file* area. BASIC still has to `LOADM` it into high memory before it can run.

### 3. Reserve high RAM, then load

Arrow to **BASIC** on the MENU and press Enter. Type these lines, pressing Enter after each:

```
CLEAR 256,53248
LOADM "PACMAN"
```

What that means, in plain language:

- `CLEAR 256,53248` tells BASIC: keep 256 bytes for strings, and **do not use RAM from address 53248 (`0xD000`) upward**. That attic is where our program lives.
- `LOADM "PACMAN"` copies the machine code from the RAM-disk file to `0xD000` using the header. Use the name **without** `.CO`.

You must `CLEAR` **before** `LOADM`. If you skip it, BASIC can sit on top of `0xD000` and the load will crash the machine.

Tandy 200 `MAXRAM` is 61104 (`0xEE90`). `LOADM` returns to BASIC if the `.CO` END is at or past that. The file stores code only; `DS` runtime RAM is not in the payload.

### 4. Run it

Still in BASIC:

```
CALL 53248
```

Or, instead of `LOADM` then `CALL`, you can use one line that loads *and* jumps to the execution address:

```
RUNM "PACMAN"
```

(You still need the `CLEAR 256,53248` first.)

### 5. Controls

| Key | Action |
|-----|--------|
| Arrow keys | Steer Pac-Man (Right wins if two arrows are held) |
| BREAK | Quit: restore BASIC’s stack, clear the LCD, `RET` to BASIC |

In VirtualT, Tandy **BREAK** is usually the PC **Pause/Break** key (the emulator’s special-key name is `pause`). On a Mac keyboard that has no Pause key, open VirtualT’s software keyboard if the host mapping does nothing.

After BREAK you are back in BASIC. Type `MENU` and Enter to see the file list again. `CALL 53248` restarts without reloading, as long as you did not `CLEAR` away high memory.

### If something goes wrong

| Symptom | Likely cause |
|---------|----------------|
| `OM` (Out of Memory) or BASIC error on `LOADM` | Forgot `CLEAR 256,53248`, or HIMEM is not `53248` |
| `LOADM` drops back to BASIC / Ok | `.CO` END was past T200 `MAXRAM` (61104). Rebuild so the file is code-only (no `DS` zeros). |
| Instant crash / garbage | `CLEAR` was issued *after* `LOADM`, or the model is still Model 100 |
| MENU text scrambled after quit | Should not happen — we leave the LCD in graphics mode and call ROM CLS at `4F4DH` |
| Arrows do nothing | Model is not T200 (keyboard matrix differs from the Model 100) |

## Hardware notes

- CPU: 80C85 @ ~2.4576 MHz
- LCD: HD61830 command `0FFh`, data `0FEh`, busy = status bit 7
- Wrap LCD blits in `DI` / `EI` (RST 7.5 tears the screen)
- Save `SP` on entry; restore and `RET` to BASIC on BREAK
