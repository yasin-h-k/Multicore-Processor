# Validation

The project was checked in this environment with the included project-specific
Verilog-2001 structural checker and lint pass:

```text
STATIC CONSISTENCY CHECK PASS: 15 modules, 15 files
VERILOG-2001 LINT PASS: 15 files
```

The additional module is `victim_cache.v`. All named ports are connected, all
instantiated modules are defined, and the source contains no project-forbidden
SystemVerilog constructs.

The direct self-checking testbench now includes checks for victim-cache lookup,
atomic swap, MESI state preservation, snoop response from an M victim entry, FIFO
replacement, and dirty victim write-back. The end-to-end testbench checks that the
Core 0 dirty conflict block resides in its victim cache rather than being written
back immediately.

Icarus Verilog is not installed in the artifact-generation environment, so dynamic
`vvp` execution could not be performed here. Run `make clean && make test` on the
target Ubuntu system. A successful dynamic run must end with:

```text
CACHE/MESI TESTS PASS
DUAL-CORE PIPELINE TESTS PASS
```
