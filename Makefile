IVERILOG ?= iverilog
VVP      ?= vvp
VFLAGS   ?= -g2001 -Wall -Irtl
RTL      := $(wildcard rtl/*.v)
BUILD    := build

.PHONY: all test cache-test core-test static assemble clean waves

all: test

$(BUILD):
	mkdir -p $(BUILD)

assemble:
	./tools/assemble_subset.py asm/core0_program.asm mem/core0_program.mem
	./tools/assemble_subset.py asm/core1_program.asm mem/core1_program.mem

static:
	./tools/static_consistency_check.py
	./tools/verilog2001_lint.py

$(BUILD)/cache_test.out: $(RTL) tb/tb_cache_mesi.v | $(BUILD)
	$(IVERILOG) $(VFLAGS) -s tb_cache_mesi -o $@ $(RTL) tb/tb_cache_mesi.v

$(BUILD)/core_test.out: $(RTL) tb/tb_dual_core_mesi.v | $(BUILD)
	$(IVERILOG) $(VFLAGS) -s tb_dual_core_mesi -o $@ $(RTL) tb/tb_dual_core_mesi.v

cache-test: assemble static $(BUILD)/cache_test.out
	$(VVP) $(BUILD)/cache_test.out

core-test: assemble static $(BUILD)/core_test.out
	$(VVP) $(BUILD)/core_test.out

test: cache-test core-test

waves:
	@echo "Open build/cache_mesi.vcd or build/dual_core_mesi.vcd with GTKWave."
	@echo "Example: gtkwave build/dual_core_mesi.vcd"

clean:
	rm -f $(BUILD)/*.out $(BUILD)/*.vcd
