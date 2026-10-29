# Project Report: Dual-Core Pipelined MIPS with MESI Coherence

## 1. Implementation assumptions

| Item | Choice |
|---|---|
| Addressing | 32-bit byte-addressed |
| Datapath | 32 bits |
| Registers | 32 general-purpose registers; register 0 hardwired to zero |
| Data access | Aligned 32-bit words only |
| Endianness/block order | Word offset 0 in bits `[31:0]`; offset 4 in `[63:32]`; offset 8 in `[95:64]`; offset 12 in `[127:96]` |
| L1 capacity | 64 bytes per core |
| L1 organization | Four direct-mapped lines, 16 bytes per line |
| Address split | tag `[31:6]`, index `[5:4]`, block offset `[3:0]`, word select `[3:2]` |
| Write policy | Write-back, write-allocate |
| Coherence | MESI, one state per line; I replaces a valid bit |
| Main memory | 256 × 128-bit blocks = 4 KiB |
| Memory latency | Three cycles per accepted block operation |
| Reset | Synchronous active-high |
| Branch/jump resolution | EX stage |
| Hazards | EX/MEM and MEM/WB forwarding; one-cycle load-use bubble |
| Instruction memory | Separate file-backed memory per core |
| Cache transfer | Direct cache-to-cache for clean data; modified owner supplies data and memory is updated before completion |
| Arbitration | Single-owner bus transaction; fair alternating priority for simultaneous competitions |
| Victim cache | Enabled bonus: four fully-associative 16-byte entries per core, FIFO replacement |

## 2. Overall architecture

```text
                 +--------------------+
                 |  Instruction Mem 0 |
                 +----------+---------+
                            |
+---------+ CPU word req +--v-------+      bus request
| MIPS 0  |<------------->| L1 D$ 0 |------------------+
| 5 stage |               | 64 B    |<-- snoop ---------|
+---------+               +---------+                   |
                                                        v
                                                  +-----------+
                                                  | Shared Bus|
                                                  | Arbiter   |
                                                  +-----+-----+
                                                        |
                                                  128-bit block
                                                        |
                                                  +-----v-----+
                                                  | Main Mem  |
                                                  | 4 KiB     |
                                                  +-----------+
                                                        ^
+---------+ CPU word req +---------+                    |
| MIPS 1  |<------------->| L1 D$ 1 |------------------+
| 5 stage |               | 64 B    |<-- snoop ---------|
+---------+               +----+----+
                            |
                 +----------v---------+
                 |  Instruction Mem 1 |
                 +--------------------+
```

### Module hierarchy

```text
dual_core_mips_top
├── core0 : mips_core
│   ├── imem : instruction_memory
│   ├── control : control_unit
│   ├── alu_decode : alu_control
│   ├── execute_alu : alu
│   ├── rf : register_file
│   ├── hazard : hazard_unit
│   └── forwarding : forwarding_unit
├── core1 : mips_core
├── cache0 : l1_data_cache
│   └── victim : victim_cache
├── cache1 : l1_data_cache
│   └── victim : victim_cache
├── arbiter : bus_arbiter
└── memory : shared_main_memory
```

## 3. Processor pipeline

### IF

- Reads the core's private instruction memory using `PC[31:2]`.
- Forms `PC + 4`.
- IF/ID is frozen during a cache stall or load-use stall.

### ID

- Decodes opcode and function fields.
- Reads `rs` and `rt` asynchronously.
- Sign-extends normal immediates and zero-extends `ori` immediates.
- A same-cycle register-file write/read bypass prevents a WB-to-ID timing hazard.

### EX

- Selects forwarded operands.
- Computes ALU result or effective address.
- Carries forwarded `rt` as store data.
- Resolves `beq`, `bne`, and `j`.
- A taken branch or jump clears IF/ID and ID/EX and redirects the PC.

### MEM

- EX/MEM presents a stable request to the private L1.
- If the cache is not ready, the core freezes PC and all pipeline registers.
- WB write enable is suppressed during the freeze, avoiding repeated commits.

### WB

- Selects ALU result or cache load data.
- Writes only when MEM is not stalled.

## 4. Hazard handling

### Forwarding

- EX/MEM ALU result to EX operand A or B.
- MEM/WB write-back value to EX operand A or B.
- EX/MEM forwarding is suppressed for a load because load data is not available there.
- The forwarded B-register value is also captured as `sw` data.

### Load-use hazard

When ID/EX is a load and its destination `rt` is needed by the instruction in IF/ID, PC and IF/ID are held and ID/EX is cleared for one cycle. The detector understands which source fields are actually used by R type, `addi`, `ori`, `lw`, `sw`, `beq`, and `bne`.

### Control hazard

Branches and jumps resolve in EX, so the two younger instructions are invalidated when a control transfer is taken.

## 5. L1 cache organization

Each line contains:

```text
MESI state: 2 bits
Tag:        26 bits
Data:       128 bits (four 32-bit words)
```

No separate valid bit is needed because state I means invalid.

### CPU interface

```text
cpu_req, cpu_we, cpu_addr, cpu_wdata
cpu_rdata, cpu_ready, cpu_stall
```

The request remains stable until the response. `C_RESP` makes `cpu_ready` high for a complete cycle and prevents a held request from being accepted twice.

## 6. MESI state-transition table

### Local processor events

| Current | Local event | Bus action | Next | Data action |
|---|---|---|---|---|
| M | Read hit | None | M | Return word |
| E | Read hit | None | E | Return word |
| S | Read hit | None | S | Return word |
| I/tag miss | Read | BusRd | E if no peer; S if peer | Install returned block |
| M | Write hit | None | M | Update word |
| E | Write hit | None | M | Update word |
| S | Write hit | BusUpgr | M | Invalidate peer, then update word |
| I/tag miss | Write | BusRdX | M | Obtain block, update word |
| M victim | Replacement | BusWB | I, then miss flow | Write full victim block to memory |

### Snoop events

| Current | Snoop BusRd | Snoop BusRdX | Snoop BusUpgr |
|---|---|---|---|
| M | Supply block, write memory, M→S | Supply block, write memory, M→I | Protocol-error case; implementation invalidates if observed |
| E | Supply clean block, E→S | Supply block, E→I | E→I if observed |
| S | Supply clean block, remain S | Supply block, S→I | S→I |
| I | No hit, remain I | No hit, remain I | No hit, remain I |

### Coherence invariants

- A requesting write completes only after the other copy is invalid.
- A read of a peer's M line uses the peer block, never stale memory.
- A modified line is written to memory before eviction or intervention completes.
- Bus ownership is exclusive until the FSM reaches response.

## 7. Cache FSM

| State | Purpose |
|---|---|
| `C_IDLE` | Snoop or accept one CPU request; serve local M/E/S hits |
| `C_WB` | Write a modified victim block through the bus |
| `C_MISS` | Issue BusRd or BusRdX and install returned block |
| `C_UPGR` | Issue BusUpgr for an S write hit |
| `C_RESP` | Present one completed CPU response and prevent duplicate acceptance |

### Read miss

1. Latch address, tag, index, and word offset.
2. If the victim is M, perform `C_WB` first.
3. Issue BusRd.
4. Arbiter snoops peer.
5. Install S if peer hit, otherwise E.
6. Enter `C_RESP`.

### Write miss

1. Write back an M victim if necessary.
2. Issue BusRdX.
3. Peer invalidates and supplies its block if present.
4. Apply the CPU word to the returned block.
5. Install M and respond.

## 8. Shared-bus transaction definitions

| Code | Name | Meaning |
|---|---|---|
| `00` | BusRd | Read miss; requester obtains E or S |
| `01` | BusRdX | Read for ownership/write miss; requester obtains M |
| `10` | BusUpgr | Invalidate peer for an S write hit; no data transfer required |
| `11` | BusWB | Write an evicted modified block to memory |

The requester supplies a block-aligned address. BusWB also supplies 128-bit write data. The response contains 128-bit block data and a `shared` indication.

## 9. Arbiter FSM and sequences

| State | Action |
|---|---|
| `A_IDLE` | Choose one requester; alternate priority on simultaneous requests |
| `A_SNOOP` | Broadcast to the nonowner and sample hit/modified/data |
| `A_MEM_READ` | Read a block when no peer has it |
| `A_MEM_WRITE` | Perform BusWB or modified intervention write-back |
| `A_RESP` | Assert done to the owner for one cycle |

### Transaction sequences

1. **Read miss, no peer copy:** IDLE → SNOOP(no hit) → MEM_READ → RESP; requester gets E.
2. **Read miss, peer S:** IDLE → SNOOP(hit clean) → RESP; both remain/become S.
3. **Read miss, peer E:** peer E→S; clean cache-to-cache response; requester gets S.
4. **Read miss, peer M:** peer supplies newest block and M→S; arbiter writes it to memory; requester gets S.
5. **Write miss, no peer copy:** SNOOP(no hit) → MEM_READ → RESP; requester writes word and gets M.
6. **Write miss, peer S:** peer S→I; clean block transfers; requester gets M.
7. **Write miss, peer E:** peer E→I; clean block transfers; requester gets M.
8. **Write miss, peer M:** peer supplies newest block and M→I; memory receives that block; requester applies its store and gets M.
9. **Shared upgrade:** BusUpgr snoop invalidates peer S; requester changes S→M and applies store.
10. **Modified eviction:** cache issues BusWB; memory writes full 128-bit block; cache then begins its original miss.

## 10. Round-robin policy

The arbiter stores the winner of the previous simultaneous competition. On the next cycle in which both requests are present in `A_IDLE`, the other core wins. A transaction keeps ownership until `A_RESP`, so no multi-cycle operation is preempted. A single uncontested request does not consume the alternating tie priority.

## 11. Main memory

- Storage is an unpacked array of 256 128-bit blocks.
- An accepted request is latched in `M_IDLE`.
- `M_BUSY` counts three cycles.
- The block read/write occurs at completion.
- `M_RESP` holds `mem_ready` until the arbiter deasserts `mem_req`.
- Sparse `$readmemh` initialization is provided.

## 12. Test programs

### Core 0

The program verifies:

- ALU-result forwarding.
- Two-source forwarding.
- Store-data forwarding.
- A write-allocate miss.
- A local load from M.
- A load-use dependency.
- Taken-branch flushing.
- Jump flushing.
- Modified conflict eviction between addresses `0x300` and `0x340`.

Expected key registers are `$t0=5`, `$t1=8`, `$t2=13`, `$t3=13`, `$t4=18`, `$t5=7`, `$t6=9`, and `$t7=18`.

### Core 1

The program verifies concurrent execution, `ori` zero extension, store/load, `sub`, non-taken `bne`, and jump flushing.

## 13. Self-checking tests

### `tb_cache_mesi`

- First reader gets E; second reader makes both S.
- S→M upgrade invalidates the peer.
- Peer read of M receives updated data and causes M→S.
- Modified direct-mapped victim is written back.
- Two simultaneous competitions alternate first grant.
- Write ownership is checked against peer E, S, and M cases.
- Internal MESI arrays, tags, data blocks, and main memory are checked.

### `tb_dual_core_mesi`

- Waits for both completion registers.
- Checks final architectural registers.
- Checks that both cores experienced cache stalls.
- Checks that core 0 observed a load-use bubble.
- Checks control flushes.
- Checks PC stability during persistent stalls.
- Counts the load write-back and requires exactly one commit.
- Checks dirty eviction data in main memory and the final cache tag/data.

## 14. Implementation decisions and challenges

### Avoiding duplicate memory operations

A common error is returning a one-cycle ready pulse while the cache has already returned to IDLE. Because a stalled pipeline still presents the old EX/MEM request at the response edge, the cache may accept the same store twice. This design uses `C_RESP`, so the response handshake occurs while the cache is not able to accept a request.

### Avoiding repeated WB commits during a cache stall

Freezing MEM/WB without gating register-file write enable can repeatedly write the same register. This design gates WB with `!mem_stall`; the held instruction commits once when the memory stage resumes.

### Modified intervention

The arbiter always chooses peer M data over memory. It writes that data to memory before completing the transaction, so both the requester and memory observe the latest pretransaction block.

## 15. Implemented victim-cache bonus

### Organization

Each L1 contains one separate `victim_cache` module. It has four fully-associative
entries. Every entry stores a 28-bit block address (`address[31:4]`), 128-bit data,
and a two-bit MESI state. A separate valid bit is unnecessary because I denotes
invalid. The replacement policy is FIFO, represented by a two-bit pointer.

### L1 miss sequence

1. The direct-mapped L1 lookup is performed.
2. On an L1 miss, all four victim entries are searched in parallel.
3. A victim hit causes an atomic swap: the requested victim block enters the
   indexed L1 line, while the displaced valid L1 block enters the same victim slot.
4. Read hits complete without using the bus. Writes to M/E become or remain M.
5. A write to a recovered S entry issues BusUpgr before changing the word.
6. On a victim miss, a valid displaced L1 line is inserted at the FIFO pointer.
7. If the selected FIFO entry is M, BusWB completes before the slot is overwritten.
8. The original BusRd or BusRdX miss is then issued normally.

### Coherence and snooping

The arbiter sees a merged snoop response from L1 and victim storage. The victim
cache compares every snoop block address against all four entries. BusRd causes M
or E to become S and supplies the block. BusRdX and BusUpgr invalidate matching
S/E/M entries. Thus a modified block remains discoverable and cannot be lost merely
because it was displaced from direct-mapped L1.

### Correctness properties

- The same block is never intentionally stored in both L1 and its victim cache;
  the hit operation is a swap.
- M state and dirty data are preserved across L1 displacement.
- A normal victim hit avoids both shared-bus and main-memory traffic.
- A replaced M victim entry is written back before reuse.
- Peer reads and writes snoop victim entries exactly as they snoop L1 lines.
- Setting `ENABLE_VICTIM_CACHE=0` selects the original direct L1-to-bus behavior.

### Bonus tests

`tb_cache_mesi.v` verifies an M L1 line moving into victim storage, a victim-hit
swap, an M victim supplying the peer on BusRd and downgrading to S, FIFO pointer
wraparound, and write-back before replacing an M victim entry. The end-to-end test
checks that the processor conflict block is retained in victim storage with its M
state and dirty word.
