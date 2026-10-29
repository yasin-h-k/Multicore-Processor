# Dual-Core 5-Stage MIPS with Private MESI L1 Caches

> **Important fix:** This package includes the zero-time snoop-loop correction
> described in `HANG_FIX.md`. Run `make clean` before rebuilding an older copy.


## Overview

This project is an educational dual-core MIPS system written in IEEE Verilog-2001. It contains two independent five-stage pipelines, one private 64-byte direct-mapped write-back L1 data cache per core, a snooping shared bus with fair round-robin arbitration, and a deterministic-latency shared main memory, and one four-entry fully-associative MESI-aware victim cache per core.

The source intentionally avoids SystemVerilog-only constructs such as `logic`, `always_ff`, `always_comb`, typed strings, `unique case`, interfaces, packages, and classes.

The supported instruction subset is:

- R type: `add`, `sub`, `and`, `or`, `slt`
- I type: `addi`, `ori`, `lw`, `sw`
- Control: `beq`, `bne`, `j`

Two self-checking testbenches are included:

- `tb/tb_cache_mesi.v`: direct cache/bus/memory verification for MESI and arbitration.
- `tb/tb_dual_core_mesi.v`: end-to-end dual-core pipeline, hazard, stall, control-flow, cache-miss, and dirty-eviction verification.

## Important assumptions

- 32-bit byte-addressed address space.
- 32-bit words and aligned `lw`/`sw` accesses only.
- Little-endian word placement inside a 16-byte block: offset `0` is `block[31:0]`, offset `4` is `block[63:32]`, offset `8` is `block[95:64]`, and offset `12` is `block[127:96]`.
- Each L1 has four 16-byte direct-mapped lines: offset bits `[3:0]`, index bits `[5:4]`, tag bits `[31:6]`.
- MESI `I` is the validity indication; no separate valid bit is stored.
- Main data memory is 4 KiB, represented as 256 blocks of 128 bits.
- Main-memory block read/write latency is three clock cycles after request acceptance.
- Reset is synchronous, active high.
- Branches and jumps are resolved in EX. Taken control transfers flush IF/ID and ID/EX.
- EX/MEM and MEM/WB forwarding is implemented. A load-use dependency inserts one bubble.
- Store data uses the same forwarded `rt` path as an ALU source.
- A memory operation in EX/MEM freezes the affected core until `cpu_ready` is asserted.
- Clean E/S data is transferred directly cache-to-cache. Modified data is supplied by the owner and written to main memory before completion.
- The bonus victim cache is enabled by default. Set `ENABLE_VICTIM_CACHE=0` on `dual_core_mips_top` or `l1_data_cache` to run the original base path.

## Directory structure

```text
.
├── asm/
│   ├── core0_program.asm
│   └── core1_program.asm
├── mem/
│   ├── core0_program.mem
│   ├── core1_program.mem
│   └── data_memory.mem
├── rtl/
│   ├── alu.v
│   ├── alu_control.v
│   ├── bus_arbiter.v
│   ├── control_unit.v
│   ├── dual_core_mips_top.v
│   ├── forwarding_unit.v
│   ├── hazard_unit.v
│   ├── instruction_memory.v
│   ├── l1_data_cache.v
│   ├── mips_core.v
│   ├── register_file.v
│   └── shared_main_memory.v
├── tb/
│   ├── tb_cache_mesi.v
│   └── tb_dual_core_mesi.v
├── tools/
│   ├── assemble_subset.py
│   ├── static_consistency_check.py
│   └── verilog2001_lint.py
├── Makefile
├── README.md
├── REPORT.md
├── VALIDATION.md
└── run_sim.sh
```

## Module summary

- `mips_core`: five-stage processor pipeline and CPU-cache handshake.
- `control_unit`: opcode/function decoding and main control signals.
- `alu_control`: maps ALU operation class and R-type function to ALU control.
- `alu`: 32-bit arithmetic/logic unit.
- `register_file`: 32 registers, synchronous write, asynchronous read, `$zero` protection, same-cycle write/read bypass.
- `hazard_unit`: detects immediate load-use hazards.
- `forwarding_unit`: EX/MEM and MEM/WB forwarding selection.
- `instruction_memory`: separate combinational instruction memory for each core.
- `l1_data_cache`: four-line direct-mapped write-back MESI cache, victim lookup/swap controller, and merged L1/victim snoop logic.
- `victim_cache`: four-entry fully-associative storage with FIFO replacement, MESI state per entry, and independent snoop participation.
- `bus_arbiter`: single-owner transaction FSM, snoop broadcast, memory access, modified intervention, and round-robin tie breaking.
- `shared_main_memory`: 128-bit block memory with fixed latency.
- `dual_core_mips_top`: connects both cores, caches, arbiter, and memory.

## Requirements

Ubuntu/Debian example:

```bash
sudo apt update
sudo apt install iverilog gtkwave python3 make
```

The complete project uses Verilog-2001 source files (`.v`) and is compiled with `iverilog -g2001`. RTL uses `wire`, `reg`, `always @*`, and `always @(posedge clk)` rather than SystemVerilog constructs. Cache lines, register files, instruction memory, and main memory use Verilog memory arrays. Testbench tasks use classic Verilog task declarations and fixed-width character vectors for messages.

## Build and run

From the project root:

```bash
make test
```

Equivalent explicit commands:

```bash
python3 tools/assemble_subset.py asm/core0_program.asm mem/core0_program.mem
python3 tools/assemble_subset.py asm/core1_program.asm mem/core1_program.mem
python3 tools/static_consistency_check.py
python3 tools/verilog2001_lint.py

iverilog -g2001 -Wall -Irtl \
  -s tb_cache_mesi \
  -o build/cache_test.out \
  rtl/*.v tb/tb_cache_mesi.v
vvp build/cache_test.out

iverilog -g2001 -Wall -Irtl \
  -s tb_dual_core_mesi \
  -o build/core_test.out \
  rtl/*.v tb/tb_dual_core_mesi.v
vvp build/core_test.out
```

Or run:

```bash
./run_sim.sh
```

Expected final messages are:

```text
CACHE/MESI TESTS PASS
DUAL-CORE PIPELINE TESTS PASS
```

## Waveforms

The testbenches generate:

- `build/cache_mesi.vcd`
- `build/dual_core_mesi.vcd`

Open either with GTKWave:

```bash
gtkwave build/dual_core_mesi.vcd
```

Useful hierarchy paths include:

- `dut.core0.pc`, `dut.core1.pc`
- `dut.core0.mem_stall`, `dut.core0.load_use_stall`
- `dut.cache0.mesi_state[0:3]`, `dut.cache1.mesi_state[0:3]`
- `dut.cache0.tags[0:3]`, `dut.cache0.data_lines[0:3]`
- `dut.cache0.victim.block_addr[0:3]`, `data_block[0:3]`, `mesi_state[0:3]`
- `dut.cache0.victim.fifo_pointer` and the equivalent Core 1 paths
- `dut.arbiter.state`, `dut.arbiter.owner`, `dut.arbiter.current_cmd`
- `dut.memory.mem_req`, `dut.memory.mem_we`, `dut.memory.mem_ready`
- `dut.core0.rf.regs[0:31]`, `dut.core1.rf.regs[0:31]`

## Program initialization

Each core has a separate instruction memory file:

- Core 0: `mem/core0_program.mem`
- Core 1: `mem/core1_program.mem`

The corresponding assembly is in `asm/`. Rebuild the machine-code files with `make assemble`.

The data memory is initialized by `mem/data_memory.mem`. The file uses standard `$readmemh` `@address` directives, where the address is a 128-bit block index.

## CPU-cache handshake

The core holds `cpu_req`, `cpu_we`, `cpu_addr`, and `cpu_wdata` stable while waiting. The cache raises `cpu_ready` for a response cycle. The core freezes PC and all pipeline registers while an EX/MEM memory instruction is waiting. Register-file write enable is gated during that freeze so an older WB instruction cannot commit repeatedly.

The cache uses a response state, rather than pulsing ready while already idle, so the same level-held processor request cannot be accepted twice.

## Victim cache bonus

The bonus is fully implemented and enabled by default through the integer parameter
`ENABLE_VICTIM_CACHE=1`. Each private L1 owns one `victim_cache` instance with:

- four 16-byte entries;
- fully-associative block-address comparison;
- 128-bit data and a full MESI state per entry;
- FIFO replacement using a two-bit pointer;
- L1/victim swapping on a victim hit;
- no bus or main-memory access for a normal victim hit;
- snoop lookup for `BusRd`, `BusRdX`, and `BusUpgr`;
- M-to-S downgrade and data supply on a snooped `BusRd`;
- invalidation on snooped `BusRdX` or `BusUpgr`;
- write-back of an M victim entry before FIFO replacement.

On an L1 miss, the hierarchy first searches all victim entries. On a hit, the
requested entry is installed in L1 and the displaced L1 line is written into the
same victim slot. MESI state and the complete block address are preserved. If the
hit entry is S and the CPU operation is a write, the block is restored to L1 and a
`BusUpgr` is completed before the store is acknowledged.

On a victim miss, a valid displaced L1 line is inserted at the FIFO pointer. If
that victim slot currently contains M, the cache first issues `BusWB`, waits for
completion, and only then reuses the slot. Clean S/E entries may be replaced
without a memory write.

The direct MESI testbench additionally verifies victim hits, swaps, snooping an M
victim entry, FIFO pointer wraparound, and dirty victim replacement.
