#!/usr/bin/env python3
"""Small project-specific Verilog-2001 lint pass.

This is intentionally conservative. It checks language-token compatibility,
block balancing, continuous/procedural driver types, and common accidental
constructs before an external HDL compiler is invoked.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = sorted((ROOT / "rtl").glob("*.v")) + sorted((ROOT / "tb").glob("*.v"))

FORBIDDEN = {
    r"\blogic\b": "logic",
    r"\balways_ff\b": "always_ff",
    r"\balways_comb\b": "always_comb",
    r"\balways_latch\b": "always_latch",
    r"\btypedef\b": "typedef",
    r"\benum\b": "enum",
    r"\binterface\b": "interface",
    r"\bmodport\b": "modport",
    r"\bpackage\b": "package",
    r"\bclass\b": "class",
    r"\bstring\b": "string",
    r"\bunique\s+case\b": "unique case",
    r"\bpriority\s+case\b": "priority case",
    r"\$sformatf\b": "$sformatf",
    r"\$fatal\b": "$fatal",
    r"\$clog2\b": "$clog2",
}


def clean(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//.*", "", text)
    text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
    return text


def declared_types(text: str):
    types = {}
    # ANSI ports and regular declarations. Declarations in task/function scope
    # may shadow module names, but this checker only reports module-level wire
    # assignments and therefore treats duplicate names conservatively.
    pat = re.compile(
        r"\b(?:(input|output|inout)\s+)?(wire|reg)\s*"
        r"(?:signed\s*)?(?:\[[^\]]+\]\s*)?([^;\)]+)[;\)]"
    )
    for m in pat.finditer(text):
        kind = m.group(2)
        names = m.group(3)
        for item in names.split(','):
            name = re.sub(r"\[[^\]]+\]", "", item).strip()
            name = name.split('=')[0].strip()
            if re.match(r"^[A-Za-z_]\w*$", name):
                types.setdefault(name, kind)
    return types


def block_balance(text: str, path: Path):
    errors = []
    # Token stack for constructs with unique closing tokens.
    pairs = {
        'endmodule': 'module',
        'endcase': 'case',
        'endfunction': 'function',
        'endtask': 'task',
        'join': 'fork',
    }
    stack = []
    tokens = re.finditer(r"\b(module|endmodule|case|endcase|function|endfunction|task|endtask|fork|join)\b", text)
    for m in tokens:
        tok = m.group(1)
        line = text.count('\n', 0, m.start()) + 1
        if tok in pairs:
            if not stack or stack[-1][0] != pairs[tok]:
                errors.append(f"{path}: unmatched {tok} at line {line}")
            else:
                stack.pop()
        else:
            stack.append((tok, line))
    for tok, line in stack:
        errors.append(f"{path}: unclosed {tok} from line {line}")

    # begin/end balance is independent because begin occurs within all blocks.
    depth = 0
    for m in re.finditer(r"\b(begin|end)\b", text):
        tok = m.group(1)
        line = text.count('\n', 0, m.start()) + 1
        if tok == 'begin':
            depth += 1
        else:
            depth -= 1
            if depth < 0:
                errors.append(f"{path}: unmatched end at line {line}")
                depth = 0
    if depth:
        errors.append(f"{path}: {depth} more begin than end tokens")
    return errors


def driver_checks(text: str, path: Path):
    errors = []
    types = declared_types(text)
    for m in re.finditer(r"\bassign\s+([A-Za-z_]\w*)\s*(?:\[[^\]]+\])?\s*=", text):
        name = m.group(1)
        if types.get(name) == 'reg':
            line = text.count('\n', 0, m.start()) + 1
            errors.append(f"{path}: continuous assignment drives reg {name} at line {line}")

    # Scan procedural regions line-wise. This is not a full parser, but catches
    # accidental writes to module-level wires in this project's coding style.
    procedural_depth = 0
    for lineno, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if re.match(r"^(always\b|initial\b|task\b|function\b)", stripped):
            procedural_depth += 1
        if procedural_depth:
            m = re.match(r"(?:if\s*\([^)]*\)\s*)?([A-Za-z_]\w*)\s*(?:\[[^\]]+\])?\s*(<=|=)", stripped)
            if m and types.get(m.group(1)) == 'wire':
                errors.append(f"{path}: procedural assignment drives wire {m.group(1)} at line {lineno}")
        if re.match(r"^(endtask|endfunction)\b", stripped):
            procedural_depth = max(0, procedural_depth - 1)
        # An always/initial region ends at its final end. Precise nesting is
        # checked separately; this simple scan may stay active longer, which is
        # conservative and safe for reporting writes to wires.
    return errors


def main() -> int:
    errors = []
    for path in FILES:
        raw = path.read_text()
        text = clean(raw)
        for pattern, label in FORBIDDEN.items():
            if re.search(pattern, text):
                errors.append(f"{path}: contains SystemVerilog-only token {label}")
        if path.suffix != '.v':
            errors.append(f"{path}: HDL file must use .v extension")
        errors.extend(block_balance(text, path))
        errors.extend(driver_checks(text, path))

    if errors:
        print("VERILOG-2001 LINT FAILED")
        for error in errors:
            print(" -", error)
        return 1
    print(f"VERILOG-2001 LINT PASS: {len(FILES)} files")
    return 0


if __name__ == '__main__':
    sys.exit(main())
