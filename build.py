#!/usr/bin/env python3
"""
build.py -- tiny Intel 8085 assembler for Pac-Man on the Tandy 200.

What this script does (beginner overview)
-----------------------------------------
1. Reads hw_defs.asm and follows every INCLUDE.
2. Assembles pure 8085 Intel-syntax source (two passes).
3. Writes PAC200.CO with the 6-byte Tandy/Kyocera header:

      bytes 0-1  load address      (little-endian), we use 0xC800
      bytes 2-3  payload length    (not counting the 6-byte header)
      bytes 4-5  execution address (little-endian), also 0xC800
      bytes 6+   the machine code, including DS zeros

Run it from this folder:

      python3 build.py

No extra packages.  No Z80.  No MUL.
"""

from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(ROOT, "hw_defs.asm")
OUTPUT = os.path.join(ROOT, "PAC200.CO")
LISTING = os.path.join(ROOT, "PAC200.LST")

LOAD_ADDR = 0xC800
EXEC_ADDR = 0xC800

# ---------------------------------------------------------------------------
# 8085 opcode tables (Intel mnemonics, 8080-compatible encoding)
# ---------------------------------------------------------------------------
REG8 = {"B": 0, "C": 1, "D": 2, "E": 3, "H": 4, "L": 5, "M": 6, "A": 7}
RP = {"B": 0, "D": 1, "H": 2, "SP": 3}          # LXI/INX/DCX/DAD
RP_PUSH = {"B": 0, "D": 1, "H": 2, "PSW": 3}    # PUSH/POP

IMPLIED = {
    "NOP": 0x00, "RLC": 0x07, "RRC": 0x0F, "RAL": 0x17, "RAR": 0x1F,
    "DAA": 0x27, "CMA": 0x2F, "STC": 0x37, "CMC": 0x3F,
    "HLT": 0x76, "RET": 0xC9, "RNZ": 0xC0, "RZ": 0xC8,
    "RNC": 0xD0, "RC": 0xD8, "RPO": 0xE0, "RPE": 0xE8,
    "RP": 0xF0, "RM": 0xF8, "XTHL": 0xE3, "PCHL": 0xE9,
    "XCHG": 0xEB, "SPHL": 0xF9, "DI": 0xF3, "EI": 0xFB,
    "RIM": 0x20, "SIM": 0x30,
}

# jumps / calls: opcode, then 16-bit address
JUMP16 = {
    "JMP": 0xC3, "JNZ": 0xC2, "JZ": 0xCA, "JNC": 0xD2, "JC": 0xDA,
    "JPO": 0xE2, "JPE": 0xEA, "JP": 0xF2, "JM": 0xFA,
    "CALL": 0xCD, "CNZ": 0xC4, "CZ": 0xCC, "CNC": 0xD4, "CC": 0xDC,
    "CPO": 0xE4, "CPE": 0xEC, "CP": 0xF4, "CM": 0xFC,
}

IMM8 = {
    "ADI": 0xC6, "ACI": 0xCE, "SUI": 0xD6, "SBI": 0xDE,
    "ANI": 0xE6, "XRI": 0xEE, "ORI": 0xF6, "CPI": 0xFE,
}

ALU_R = {
    "ADD": 0x80, "ADC": 0x88, "SUB": 0x90, "SBB": 0x98,
    "ANA": 0xA0, "XRA": 0xA8, "ORA": 0xB0, "CMP": 0xB8,
}


class AsmError(Exception):
    def __init__(self, path: str, lineno: int, msg: str):
        super().__init__(f"{path}:{lineno}: {msg}")
        self.path = path
        self.lineno = lineno


# ---------------------------------------------------------------------------
# Numbers and expressions
# ---------------------------------------------------------------------------
def parse_number(tok: str) -> int | None:
    """Return int or None if `tok` is not a literal."""
    t = tok.strip().upper()
    if not t:
        return None
    if t.endswith("B") and len(t) > 1 and all(c in "01" for c in t[:-1]):
        return int(t[:-1], 2) & 0xFFFF
    if t.endswith("H"):
        h = t[:-1]
        if h.startswith("0") and len(h) > 1:
            h = h  # 0D000 is valid hex
        try:
            return int(h, 16) & 0xFFFF
        except ValueError:
            return None
    if t.startswith("0X"):
        try:
            return int(t, 16) & 0xFFFF
        except ValueError:
            return None
    if t.isdigit() or (t.startswith("-") and t[1:].isdigit()):
        return int(t, 10) & 0xFFFF
    return None


def tokenize_expr(expr: str) -> list[str]:
    """Split A+B-1 into ['A', '+', 'B', '-', '1'] (no spaces)."""
    s = expr.replace(" ", "")
    out: list[str] = []
    buf = ""
    for ch in s:
        if ch in "+-":
            if buf:
                out.append(buf)
                buf = ""
            # unary minus: start or after another operator
            if ch == "-" and (not out or out[-1] in "+-"):
                buf = "-"
            else:
                out.append(ch)
        else:
            buf += ch
    if buf:
        out.append(buf)
    return out


def eval_expr(expr: str, symbols: dict[str, int], where: tuple[str, int]) -> int:
    expr = expr.strip()
    if not expr:
        raise AsmError(where[0], where[1], "empty expression")
    tokens = tokenize_expr(expr)
    if not tokens:
        raise AsmError(where[0], where[1], f"bad expression '{expr}'")

    def value(tok: str) -> int:
        n = parse_number(tok)
        if n is not None:
            return n
        name = tok.upper()
        if name not in symbols:
            raise AsmError(where[0], where[1], f"undefined symbol '{tok}'")
        return symbols[name] & 0xFFFF

    total = value(tokens[0])
    i = 1
    while i < len(tokens):
        op = tokens[i]
        if i + 1 >= len(tokens):
            raise AsmError(where[0], where[1], f"truncated expression '{expr}'")
        rhs = value(tokens[i + 1])
        if op == "+":
            total = (total + rhs) & 0xFFFF
        elif op == "-":
            total = (total - rhs) & 0xFFFF
        else:
            raise AsmError(where[0], where[1], f"bad operator '{op}'")
        i += 2
    return total


# ---------------------------------------------------------------------------
# Source loading
# ---------------------------------------------------------------------------
def strip_comment(line: str) -> str:
    cut = line.find(";")
    if cut >= 0:
        line = line[:cut]
    return line.rstrip()


def load_source(path: str, seen: set[str] | None = None) -> list[tuple[str, int, str]]:
    """Expand INCLUDE into a flat list of (path, lineno, original_line)."""
    seen = seen or set()
    ap = os.path.abspath(path)
    if ap in seen:
        raise AsmError(path, 0, "circular INCLUDE")
    seen.add(ap)
    rows: list[tuple[str, int, str]] = []
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except OSError as e:
        raise AsmError(path, 0, f"cannot read file: {e}") from e
    base = os.path.dirname(ap)
    for i, raw in enumerate(lines, 1):
        body = strip_comment(raw).strip()
        up = body.upper()
        if up.startswith("INCLUDE"):
            rest = body.split(None, 1)
            if len(rest) < 2:
                raise AsmError(path, i, "INCLUDE needs a filename")
            inc = rest[1].strip().strip('"').strip("'")
            rows.extend(load_source(os.path.join(base, inc), seen))
        else:
            rows.append((path, i, raw.rstrip("\n")))
    return rows


def split_label_and_rest(raw: str) -> tuple[str | None, str]:
    s = strip_comment(raw)
    if not s.strip():
        return None, ""
    if s[0].isspace():
        return None, s.strip()
    # label at column 0, with or without colon
    m = re.match(r"^([A-Za-z_@?][A-Za-z0-9_@?]*)(:?)(\s+|$)(.*)$", s)
    if not m:
        return None, s.strip()
    name, colon, sp, rest = m.group(1), m.group(2), m.group(3), m.group(4)
    rest = rest.strip()
    # "MOV A,M" at column 0 would look like a label.  Our files indent ops.
    # EQU/DS/DB/DW/ORG/END may sit next to a label without a colon.
    if not colon and rest:
        first = rest.split(None, 1)[0].upper()
        if first not in {
            "EQU", "DB", "DW", "DS", "ORG", "END", "SET",
        } and first in IMPLIED | JUMP16 | IMM8 | ALU_R | {
            "MOV", "MVI", "LXI", "LDA", "STA", "LHLD", "SHLD",
            "INX", "DCX", "INR", "DCR", "DAD", "PUSH", "POP",
            "LDAX", "STAX", "IN", "OUT", "RST", "PCHL", "SPHL",
            "INCLUDE",
        }:
            # "START  DI" without colon -- treat START as label anyway
            return name, rest
    return name, rest


def split_mnemonic(rest: str) -> tuple[str, str]:
    if not rest:
        return "", ""
    parts = rest.split(None, 1)
    mnem = parts[0].upper()
    ops = parts[1].strip() if len(parts) > 1 else ""
    return mnem, ops


def split_operands(ops: str) -> list[str]:
    if not ops:
        return []
    return [p.strip() for p in ops.split(",") if p.strip()]


# ---------------------------------------------------------------------------
# Instruction sizing / encoding
# ---------------------------------------------------------------------------
def instr_size(mnem: str, ops: list[str]) -> int:
    if mnem in ("EQU", "ORG", "END", "SET", ""):
        return 0
    if mnem == "DS":
        return -1  # caller evaluates
    if mnem in ("DB",):
        return -1
    if mnem == "DW":
        return 2 * max(1, len(ops)) if ops else 2
    if mnem in IMPLIED:
        return 1
    if mnem in JUMP16:
        return 3
    if mnem in IMM8 or mnem in ("IN", "OUT"):
        return 2
    if mnem in ALU_R:
        return 1
    if mnem == "MOV":
        return 1
    if mnem == "MVI":
        return 2
    if mnem in ("INR", "DCR"):
        return 1
    if mnem in ("INX", "DCX", "DAD"):
        return 1
    if mnem in ("PUSH", "POP"):
        return 1
    if mnem in ("LDAX", "STAX"):
        return 1
    if mnem in ("LXI",):
        return 3
    if mnem in ("LDA", "STA", "LHLD", "SHLD"):
        return 3
    if mnem == "RST":
        return 1
    raise ValueError(f"unknown mnemonic {mnem}")


def encode(
    mnem: str,
    ops: list[str],
    symbols: dict[str, int],
    where: tuple[str, int],
) -> bytes:
    def imm8(tok: str) -> int:
        return eval_expr(tok, symbols, where) & 0xFF

    def imm16(tok: str) -> tuple[int, int]:
        v = eval_expr(tok, symbols, where) & 0xFFFF
        return v & 0xFF, (v >> 8) & 0xFF

    def r8(tok: str) -> int:
        t = tok.strip().upper()
        if t not in REG8:
            raise AsmError(where[0], where[1], f"need 8-bit register, got '{tok}'")
        return REG8[t]

    if mnem in IMPLIED:
        if ops:
            raise AsmError(where[0], where[1], f"{mnem} takes no operand")
        return bytes([IMPLIED[mnem]])

    if mnem == "MOV":
        if len(ops) != 2:
            raise AsmError(where[0], where[1], "MOV r,r")
        d, s = r8(ops[0]), r8(ops[1])
        if d == 6 and s == 6:
            raise AsmError(where[0], where[1], "MOV M,M is HLT — not allowed")
        return bytes([0x40 | (d << 3) | s])

    if mnem == "MVI":
        if len(ops) != 2:
            raise AsmError(where[0], where[1], "MVI r,data")
        return bytes([0x06 | (r8(ops[0]) << 3), imm8(ops[1])])

    if mnem in ("INR", "DCR"):
        if len(ops) != 1:
            raise AsmError(where[0], where[1], f"{mnem} r")
        base = 0x04 if mnem == "INR" else 0x05
        return bytes([base | (r8(ops[0]) << 3)])

    if mnem in ALU_R:
        if len(ops) != 1:
            raise AsmError(where[0], where[1], f"{mnem} r")
        return bytes([ALU_R[mnem] | r8(ops[0])])

    if mnem in IMM8:
        if len(ops) != 1:
            raise AsmError(where[0], where[1], f"{mnem} data")
        return bytes([IMM8[mnem], imm8(ops[0])])

    if mnem in ("IN", "OUT"):
        if len(ops) != 1:
            raise AsmError(where[0], where[1], f"{mnem} port")
        op = 0xDB if mnem == "IN" else 0xD3
        return bytes([op, imm8(ops[0])])

    if mnem in ("INX", "DCX", "DAD"):
        if len(ops) != 1:
            raise AsmError(where[0], where[1], f"{mnem} rp")
        rp = ops[0].upper()
        if rp not in RP:
            raise AsmError(where[0], where[1], f"{mnem} needs B, D, H or SP")
        base = {"INX": 0x03, "DCX": 0x0B, "DAD": 0x09}[mnem]
        return bytes([base | (RP[rp] << 4)])

    if mnem in ("PUSH", "POP"):
        if len(ops) != 1:
            raise AsmError(where[0], where[1], f"{mnem} rp")
        rp = ops[0].upper()
        if rp not in RP_PUSH:
            raise AsmError(where[0], where[1], f"{mnem} needs B, D, H or PSW")
        base = 0xC5 if mnem == "PUSH" else 0xC1
        return bytes([base | (RP_PUSH[rp] << 4)])

    if mnem in ("LDAX", "STAX"):
        if len(ops) != 1:
            raise AsmError(where[0], where[1], f"{mnem} B or D")
        rp = ops[0].upper()
        if rp == "B":
            return bytes([0x0A if mnem == "LDAX" else 0x02])
        if rp == "D":
            return bytes([0x1A if mnem == "LDAX" else 0x12])
        raise AsmError(where[0], where[1], f"{mnem} only B or D")

    if mnem == "LXI":
        if len(ops) != 2:
            raise AsmError(where[0], where[1], "LXI rp,data16")
        rp = ops[0].upper()
        if rp not in RP:
            raise AsmError(where[0], where[1], "LXI needs B, D, H or SP")
        lo, hi = imm16(ops[1])
        return bytes([0x01 | (RP[rp] << 4), lo, hi])

    if mnem in ("LDA", "STA", "LHLD", "SHLD"):
        if len(ops) != 1:
            raise AsmError(where[0], where[1], f"{mnem} addr")
        lo, hi = imm16(ops[0])
        op = {"LDA": 0x3A, "STA": 0x32, "LHLD": 0x2A, "SHLD": 0x22}[mnem]
        return bytes([op, lo, hi])

    if mnem in JUMP16:
        if len(ops) != 1:
            raise AsmError(where[0], where[1], f"{mnem} addr")
        lo, hi = imm16(ops[0])
        return bytes([JUMP16[mnem], lo, hi])

    if mnem == "RST":
        if len(ops) != 1:
            raise AsmError(where[0], where[1], "RST n")
        n = imm8(ops[0])
        if n not in range(8):
            raise AsmError(where[0], where[1], "RST 0..7")
        return bytes([0xC7 | (n << 3)])

    raise AsmError(where[0], where[1], f"cannot encode {mnem}")


# ---------------------------------------------------------------------------
# Two-pass assembly
# ---------------------------------------------------------------------------
class Line:
    __slots__ = ("path", "lineno", "raw", "label", "mnem", "ops", "pc", "size")

    def __init__(self, path, lineno, raw, label, mnem, ops):
        self.path = path
        self.lineno = lineno
        self.raw = raw
        self.label = label
        self.mnem = mnem
        self.ops = ops
        self.pc = 0
        self.size = 0


def resolve_equs(parsed: list[Line], symbols: dict[str, int], require: bool) -> None:
    """Evaluate EQU lines.  If require=True, undefined symbols are errors."""
    pending = [ln for ln in parsed if ln.mnem == "EQU"]
    for _ in range(64):
        leftover: list[Line] = []
        progress = False
        for ln in pending:
            if not ln.label:
                raise AsmError(ln.path, ln.lineno, "EQU needs a name")
            if not ln.ops:
                raise AsmError(ln.path, ln.lineno, "EQU needs a value")
            try:
                val = eval_expr(ln.ops[0], symbols, (ln.path, ln.lineno))
            except AsmError:
                leftover.append(ln)
                continue
            symbols[ln.label] = val
            progress = True
        pending = leftover
        if not pending:
            return
        if not progress:
            break
    if require and pending:
        eval_expr(pending[0].ops[0], symbols, (pending[0].path, pending[0].lineno))


def assemble(
    rows: list[tuple[str, int, str]],
) -> tuple[bytes, dict[str, int], list[Line], list[str], int, int]:
    parsed: list[Line] = []
    for path, lineno, raw in rows:
        label, rest = split_label_and_rest(raw)
        mnem, ops_s = split_mnemonic(rest)
        ops = split_operands(ops_s) if mnem else []
        if label is None and not mnem:
            continue
        parsed.append(Line(path, lineno, raw, label.upper() if label else None,
                           mnem, ops))

    symbols: dict[str, int] = {}
    pc = LOAD_ADDR
    origin = LOAD_ADDR

    # Pass 1 -- instruction sizes and code labels.  DS sizes wait until EQUs
    # like PELLET_BYTES are known, so they contribute 0 here.
    for ln in parsed:
        ln.pc = pc
        if ln.label:
            if ln.mnem != "EQU":
                if ln.label in symbols:
                    raise AsmError(ln.path, ln.lineno, f"redefined label {ln.label}")
                symbols[ln.label] = pc
        if not ln.mnem:
            ln.size = 0
            continue
        m = ln.mnem
        where = (ln.path, ln.lineno)
        if m == "END":
            ln.size = 0
            break
        if m == "ORG":
            if not ln.ops:
                raise AsmError(*where, "ORG needs an address")
            try:
                pc = eval_expr(ln.ops[0], symbols, where)
            except AsmError:
                pc = LOAD_ADDR
            origin = pc
            ln.size = 0
            continue
        if m == "EQU":
            ln.size = 0
            continue
        if m == "DS":
            if not ln.ops:
                raise AsmError(*where, "DS needs a size")
            ln.size = 0
            continue
        if m == "DB":
            ln.size = max(1, len(ln.ops))
            pc = (pc + ln.size) & 0xFFFF
            continue
        if m == "DW":
            n = max(1, len(ln.ops))
            ln.size = 2 * n
            pc = (pc + ln.size) & 0xFFFF
            continue
        try:
            sz = instr_size(m, ln.ops)
        except ValueError as e:
            raise AsmError(*where, str(e)) from e
        if sz < 0:
            raise AsmError(*where, f"unhandled {m}")
        ln.size = sz
        pc = (pc + sz) & 0xFFFF

    # Numeric EQUs (PELLET_BYTES, TICKS_7S, ...) resolve before DS is sized.
    resolve_equs(parsed, symbols, require=False)

    # Second PC walk: real DS sizes, then every label (including RAM) is final.
    # DS is runtime RAM only -- do NOT put those zeros in the .CO.  Tandy 200
    # LOADM fails / returns to BASIC if END >= 61104 (0xEE90).
    pc = origin
    image_end = origin
    code_end = origin
    started = False
    for ln in parsed:
        if ln.mnem == "END":
            break
        if ln.mnem == "ORG":
            pc = eval_expr(ln.ops[0], symbols, (ln.path, ln.lineno))
            if not started:
                origin = pc
            ln.pc = pc
            continue
        ln.pc = pc
        if ln.label and ln.mnem != "EQU":
            symbols[ln.label] = pc
        if ln.mnem == "DS":
            n = eval_expr(ln.ops[0], symbols, (ln.path, ln.lineno))
            ln.size = n
            pc = (pc + n) & 0xFFFF
            started = True
            image_end = pc
            continue
        if ln.mnem in ("EQU", "", "END"):
            continue
        if ln.mnem == "DB":
            ln.size = max(1, len(ln.ops))
        pc = (pc + ln.size) & 0xFFFF
        started = True
        image_end = pc
        code_end = pc

    # GHOST_PINKY EQU GHOSTS+12 and RAM_USED need the final DS addresses.
    resolve_equs(parsed, symbols, require=True)
    symbols.setdefault("RAM_END", image_end)
    symbols["CODE_END"] = code_end

    # Pass 2 -- emit code only (origin .. code_end).  DS is not stored.
    payload = bytearray(code_end - origin)
    listing: list[str] = []

    def poke(addr: int, data: bytes, ln: Line) -> None:
        off = addr - origin
        if off < 0 or off + len(data) > len(payload):
            raise AsmError(ln.path, ln.lineno,
                           f"write ${addr:04X} outside image")
        payload[off:off + len(data)] = data

    for ln in parsed:
        if ln.mnem == "END":
            break
        where = (ln.path, ln.lineno)
        hexpart = ""
        if ln.mnem == "ORG":
            listing.append(f"            {ln.raw}")
            continue
        if ln.mnem == "EQU":
            listing.append(f"            {ln.raw}")
            continue
        if ln.mnem == "DS":
            hexpart = f"{ln.size} RAM"
        elif ln.mnem == "DB":
            data = bytes(eval_expr(op, symbols, where) & 0xFF for op in ln.ops)
            poke(ln.pc, data, ln)
            hexpart = " ".join(f"{b:02X}" for b in data[:8])
            if len(data) > 8:
                hexpart += " ..."
        elif ln.mnem == "DW":
            buf = bytearray()
            for op in ln.ops:
                v = eval_expr(op, symbols, where) & 0xFFFF
                buf += bytes([v & 0xFF, (v >> 8) & 0xFF])
            poke(ln.pc, bytes(buf), ln)
            hexpart = " ".join(f"{b:02X}" for b in buf)
        elif ln.mnem:
            data = encode(ln.mnem, ln.ops, symbols, where)
            if len(data) != ln.size:
                # DB size is exact; for safety
                pass
            poke(ln.pc, data, ln)
            hexpart = " ".join(f"{b:02X}" for b in data)
        listing.append(f"{ln.pc:04X}  {hexpart:<18} {ln.raw}")

    return bytes(payload), symbols, parsed, listing, origin, image_end


def write_co(path: str, payload: bytes, load: int, exec_addr: int) -> None:
    if len(payload) > 0xFFFF:
        raise SystemExit("payload too large for a .CO file")
    header = bytes([
        load & 0xFF, (load >> 8) & 0xFF,
        len(payload) & 0xFF, (len(payload) >> 8) & 0xFF,
        exec_addr & 0xFF, (exec_addr >> 8) & 0xFF,
    ])
    with open(path, "wb") as f:
        f.write(header)
        f.write(payload)


def main() -> int:
    print("Pac-Man Tandy 200 assembler")
    print(f"  source : {SOURCE}")
    try:
        rows = load_source(SOURCE)
        payload, symbols, parsed, listing, origin, image_end = assemble(rows)
    except AsmError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    write_co(OUTPUT, payload, origin, EXEC_ADDR)
    with open(LISTING, "w", encoding="utf-8") as f:
        f.write("\n".join(listing))
        f.write("\n")
    ram = symbols.get("RAM_USED")
    code_end = symbols.get("CODE_END", origin + len(payload))
    print(f"  origin : ${origin:04X}")
    print(f"  code   : ${code_end:04X}  ({len(payload)} bytes in .CO + 6 byte header)")
    print(f"  ram    : ${image_end:04X}  (DS not stored in the file)")
    if ram is not None:
        print(f"  DS RAM : {ram} bytes (cap 300)")
        if ram > 300:
            print("ERROR: DS usage exceeds 300 bytes", file=sys.stderr)
            return 1
    # Tandy 200 LOADM / file directory: END must stay below 61104 (0xEE90).
    t200_himem = 0xEE90
    file_end = origin + len(payload)
    if file_end >= t200_himem:
        print(f"ERROR: .CO END ${file_end:04X} >= $EE90 (61104); LOADM returns to BASIC",
              file=sys.stderr)
        return 1
    if image_end > t200_himem:
        print(f"WARNING: runtime RAM ends at ${image_end:04X} > $EE90; stack may hit reserved RAM")
    print(f"  output : {OUTPUT}")
    print(f"  listing: {LISTING}")
    print("Done.  BASIC:  CLEAR 256,51200  then  LOADM \"PAC200\"  then  CALL 51200")
    return 0


if __name__ == "__main__":
    sys.exit(main())
