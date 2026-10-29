#!/usr/bin/env python3
"""Tiny two-pass assembler for the MIPS subset used by this project."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

REGS = {
    "$zero": 0, "$0": 0,
    "$v0": 2, "$v1": 3,
    "$a0": 4, "$a1": 5, "$a2": 6, "$a3": 7,
    "$t0": 8, "$t1": 9, "$t2": 10, "$t3": 11,
    "$t4": 12, "$t5": 13, "$t6": 14, "$t7": 15,
    "$s0": 16, "$s1": 17, "$s2": 18, "$s3": 19,
    "$s4": 20, "$s5": 21, "$s6": 22, "$s7": 23,
    "$t8": 24, "$t9": 25, "$sp": 29, "$ra": 31,
}

FUNCTS = {"add": 0x20, "sub": 0x22, "and": 0x24, "or": 0x25, "slt": 0x2A}
OPCODES = {"addi": 0x08, "ori": 0x0D, "lw": 0x23, "sw": 0x2B,
           "beq": 0x04, "bne": 0x05, "j": 0x02}


def clean(line: str) -> str:
    return line.split("#", 1)[0].strip()


def reg(token: str) -> int:
    token = token.strip()
    if token not in REGS:
        raise ValueError(f"unknown register {token}")
    return REGS[token]


def number(token: str) -> int:
    return int(token, 0)


def split_args(text: str) -> list[str]:
    return [x.strip() for x in text.split(",")]


def assemble_line(text: str, pc_word: int, labels: dict[str, int]) -> int:
    parts = text.split(None, 1)
    op = parts[0].lower()
    args = split_args(parts[1]) if len(parts) > 1 else []

    if op == "nop":
        return 0

    if op in FUNCTS:
        rd, rs, rt = map(reg, args)
        return (rs << 21) | (rt << 16) | (rd << 11) | FUNCTS[op]

    if op in ("addi", "ori"):
        rt, rs = reg(args[0]), reg(args[1])
        imm = number(args[2]) & 0xFFFF
        return (OPCODES[op] << 26) | (rs << 21) | (rt << 16) | imm

    if op in ("lw", "sw"):
        rt = reg(args[0])
        match = re.fullmatch(r"(.+)\((\$[A-Za-z0-9]+)\)", args[1].replace(" ", ""))
        if not match:
            raise ValueError(f"bad memory operand: {args[1]}")
        imm = number(match.group(1)) & 0xFFFF
        rs = reg(match.group(2))
        return (OPCODES[op] << 26) | (rs << 21) | (rt << 16) | imm

    if op in ("beq", "bne"):
        rs, rt = reg(args[0]), reg(args[1])
        target = labels[args[2]] if args[2] in labels else number(args[2])
        imm = (target - (pc_word + 1)) & 0xFFFF
        return (OPCODES[op] << 26) | (rs << 21) | (rt << 16) | imm

    if op == "j":
        target = labels[args[0]] if args[0] in labels else number(args[0])
        return (OPCODES[op] << 26) | (target & 0x03FF_FFFF)

    raise ValueError(f"unsupported instruction: {text}")


def assemble(src: Path, dst: Path) -> None:
    raw_lines = src.read_text().splitlines()
    labels: dict[str, int] = {}
    instructions: list[str] = []

    for raw in raw_lines:
        line = clean(raw)
        if not line:
            continue
        while ":" in line:
            label, rest = line.split(":", 1)
            labels[label.strip()] = len(instructions)
            line = rest.strip()
            if not line:
                break
        if line:
            instructions.append(line)

    words = [assemble_line(text, pc, labels) for pc, text in enumerate(instructions)]
    dst.write_text("".join(f"{word:08x}\n" for word in words))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    assemble(args.source, args.output)


if __name__ == "__main__":
    main()
