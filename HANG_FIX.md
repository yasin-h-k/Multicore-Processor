# Simulator hang fix

The original Verilog-2001 conversion could enter an infinite zero-time
(delta-cycle) loop during the second core's read of a block already present in
the first cache.

The loop was caused by the combinational snoop path:

`arbiter snoop_valid -> cache snoop_hit -> arbiter`

Both combinational blocks first assigned their outputs to zero and then
overrode them to one.  When a snoop hit occurred, each reevaluation generated
transient `1 -> 0 -> 1` events, retriggering the other block forever, so
simulation time stopped advancing.

The fix is in:

- `rtl/bus_arbiter.v`: snoop broadcast outputs are generated in a separate
  combinational block and assigned exactly once per evaluation.
- `rtl/l1_data_cache.v`: snoop response outputs use a direct `if/else`, so they
  are also assigned exactly once per evaluation.

After extracting this package, rebuild from scratch:

```bash
make clean
./run_sim.sh
```
