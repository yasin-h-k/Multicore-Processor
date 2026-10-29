#!/usr/bin/env python3
"""Lightweight structural consistency checker for this project.

This is not a replacement for a Verilog compiler. It verifies that every
instantiated project module exists, named port connections reference declared
ports, module names are unique, delimiters are balanced after comments/strings
are removed, and every RTL file declares a timescale.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = sorted((ROOT / "rtl").glob("*.v")) + sorted((ROOT / "tb").glob("*.v"))


def strip_comments_and_strings(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//.*", "", text)
    text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
    return text


def balanced(text: str, filename: Path) -> list[str]:
    errors: list[str] = []
    pairs = {')': '(', ']': '[', '}': '{'}
    stack: list[tuple[str, int]] = []
    for lineno, line in enumerate(text.splitlines(), 1):
        for ch in line:
            if ch in "([{":
                stack.append((ch, lineno))
            elif ch in ")]}":
                if not stack or stack[-1][0] != pairs[ch]:
                    errors.append(f"{filename}: unmatched {ch} at line {lineno}")
                else:
                    stack.pop()
    for ch, lineno in stack:
        errors.append(f"{filename}: unmatched {ch} opened at line {lineno}")
    return errors


def extract_balanced(text: str, open_pos: int) -> tuple[str, int]:
    depth = 0
    for i in range(open_pos, len(text)):
        if text[i] == '(':
            depth += 1
        elif text[i] == ')':
            depth -= 1
            if depth == 0:
                return text[open_pos + 1:i], i + 1
    raise ValueError("unbalanced parentheses")


def module_headers(text: str) -> list[tuple[str, set[str], int, int]]:
    out = []
    for match in re.finditer(r"\bmodule\s+([A-Za-z_]\w*)", text):
        name = match.group(1)
        pos = match.end()
        while pos < len(text) and text[pos].isspace():
            pos += 1
        if pos < len(text) and text[pos] == '#':
            pos += 1
            while pos < len(text) and text[pos].isspace():
                pos += 1
            _, pos = extract_balanced(text, pos)
            while pos < len(text) and text[pos].isspace():
                pos += 1
        if pos < len(text) and text[pos] == ';':
            end = pos + 1
            ports = set()
        elif pos < len(text) and text[pos] == '(':
            ports_text, end = extract_balanced(text, pos)
            ports = set(re.findall(r"\b(?:input|output|inout)\b(?:\s+(?:wire|reg))?(?:\s+signed)?(?:\s*\[[^\]]+\])?\s+([A-Za-z_]\w*)", ports_text))
        else:
            continue
        endmodule = text.find("endmodule", end)
        out.append((name, ports, match.start(), endmodule if endmodule >= 0 else len(text)))
    return out


def find_instantiations(body: str, known_modules: set[str]):
    # Locate a known module name followed by optional parameter override, an
    # instance identifier, and a named-port connection list.
    for module in known_modules:
        pattern = re.compile(rf"\b{re.escape(module)}\b\s*(?:#\s*\()?")
        for m in pattern.finditer(body):
            pos = m.end()
            # If parameter override was present, m ended after '#('.
            hash_pos = body.find('#', m.start(), pos)
            if hash_pos >= 0:
                open_pos = body.find('(', hash_pos, pos + 1)
                try:
                    _, pos = extract_balanced(body, open_pos)
                except ValueError:
                    continue
            while pos < len(body) and body[pos].isspace():
                pos += 1
            inst_match = re.match(r"([A-Za-z_]\w*)", body[pos:])
            if not inst_match:
                continue
            inst = inst_match.group(1)
            pos += inst_match.end()
            while pos < len(body) and body[pos].isspace():
                pos += 1
            if pos >= len(body) or body[pos] != '(':
                continue
            try:
                conn_text, _ = extract_balanced(body, pos)
            except ValueError:
                continue
            connected_ports = set(re.findall(r"\.([A-Za-z_]\w*)\s*\(", conn_text))
            if connected_ports:
                yield module, inst, connected_ports


def main() -> int:
    errors: list[str] = []
    texts: dict[Path, str] = {}
    modules: dict[str, tuple[set[str], Path, str]] = {}

    for path in FILES:
        raw = path.read_text()
        forbidden = [
            r"\blogic\b", r"\balways_ff\b", r"\balways_comb\b",
            r"\btypedef\b", r"\benum\b", r"\binterface\b",
            r"\bpackage\b", r"\bclass\b", r"\bstring\b",
            r"\bunique\s+case\b", r"\$sformatf", r"\$fatal",
        ]
        for token in forbidden:
            if re.search(token, strip_comments_and_strings(raw)):
                errors.append(f"{path}: SystemVerilog-only token matches {token}")
        if "`timescale" not in raw:
            errors.append(f"{path}: missing `timescale")
        clean = strip_comments_and_strings(raw)
        texts[path] = clean
        errors.extend(balanced(clean, path))
        for name, ports, start, end in module_headers(clean):
            if name in modules:
                errors.append(f"duplicate module {name}: {modules[name][1]} and {path}")
            modules[name] = (ports, path, clean[start:end])

    known = set(modules)
    for parent, (_, path, body) in modules.items():
        for child, inst, connected in find_instantiations(body, known):
            if child == parent:
                continue
            child_ports = modules[child][0]
            unknown = sorted(connected - child_ports)
            missing_ports = sorted(child_ports - connected)
            if unknown:
                errors.append(
                    f"{path}: instance {inst} of {child} connects unknown ports {unknown}"
                )
            if missing_ports:
                errors.append(
                    f"{path}: instance {inst} of {child} omits ports {missing_ports}"
                )

    required = {
        "alu", "alu_control", "control_unit", "register_file",
        "forwarding_unit", "hazard_unit", "instruction_memory",
        "mips_core", "l1_data_cache", "victim_cache", "bus_arbiter",
        "shared_main_memory", "dual_core_mips_top",
        "tb_cache_mesi", "tb_dual_core_mesi",
    }
    missing = sorted(required - known)
    if missing:
        errors.append(f"missing required modules: {missing}")

    if errors:
        print("STATIC CONSISTENCY CHECK FAILED")
        for error in errors:
            print(" -", error)
        return 1

    print(f"STATIC CONSISTENCY CHECK PASS: {len(modules)} modules, {len(FILES)} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
