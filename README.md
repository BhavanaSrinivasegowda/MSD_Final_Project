# Last-Level Cache (LLC) Simulator

**ECE 485/585 Final Project — Group 7**
Deven Bishnu · Bhavana Manikyanahalli Srinivasegowda · Lokarjun Ramesh · Xiang Li

A cycle-behavioral model of a last-level cache (LLC) written in SystemVerilog. The cache sits between a higher-level L1 cache and a shared system bus, handling processor-side requests and bus-side snoops while maintaining coherence with the **MESI** protocol.

---

## Table of Contents

- [Overview](#overview)
- [Cache Specification](#cache-specification)
- [Address Breakdown](#address-breakdown)
- [Supported Requests](#supported-requests)
- [MESI State Transitions](#mesi-state-transitions)
- [Repository Layout](#repository-layout)
- [Data Structures](#data-structures)
- [How to Run](#how-to-run)
- [Trace File Format](#trace-file-format)
- [Operating Modes](#operating-modes)
- [Example Output](#example-output)
- [Test Suite](#test-suite)
- [Assumptions](#assumptions)
- [Authors](#authors)

---

## Overview

This project implements a last-level cache that interfaces with one higher-level cache (L1) and a shared bus shared with other caches. The LLC accepts nine request types from either the L1 cache or another cache on the bus, models the resulting bus operations and snoop results, and reports the messages it would send back to L1. All design and verification work is done in SystemVerilog and simulated in ModelSim/QuestaSim (`vsim`).

The cache reports three categories of communication to the terminal: **bus operations**, **snoop results**, and **L1 messages** — each annotated with the operation type, the targeted address, and any other relevant detail.

---

## Cache Specification

| Attribute | Value |
| --- | --- |
| Total capacity | 16 MB |
| Line size | 64 bytes |
| Associativity | 16-way set associative |
| Number of sets | 16,384 |
| Write policy | Write-allocate / write-back |
| Coherence protocol | MESI |
| Replacement policy | Pseudo-LRU |

---

## Address Breakdown

Each 32-bit physical address is decoded into the following fields:

| Field | Bits | Purpose |
| --- | --- | --- |
| Tag | 12 | Uniquely identifies the memory block |
| Index | 14 | Selects the cache set (1 of 16,384) |
| Byte Offset | 6 | Identifies the byte within a 64-byte line |

In addition, each line carries a **2-bit MESI state** and each set carries **15 pseudo-LRU bits** to track replacement order across its 16 ways.

```
 31                    20 19                      6 5            0
+------------------------+-------------------------+--------------+
|        Tag (12)        |       Index (14)        |  Offset (6)  |
+------------------------+-------------------------+--------------+
```

---

## Supported Requests

Requests are issued as `n address`, where `n` is the request code and `address` is the target (up to 4 bytes).

| Code | Request | Direct Function |
| --- | --- | --- |
| `0` | Read request (L1 data cache) | `process_read_request_L1_DataCache()` |
| `1` | Write request (L1 data cache) | `process_write_request_data_cache()` |
| `2` | Read request (L1 instruction cache) | `read_request_from_L1_Instruction_cache()` |
| `3` | Snooped read request | `Snooped_read_request()` |
| `4` | Snooped write request | `Snooped_write_request()` |
| `5` | Snooped read with intent to modify (RWIM) | `Snooped_RWIM_request()` |
| `6` | Snooped invalidate command | `Snooped_invalidate_request()` |
| `8` | Clear the cache and reset all state | `clear_cache()` |
| `9` | Print cache contents and state | `print_cache_contents()` |

> Code `2` (instruction read) behaves identically to code `0`. The LLC is a **unified cache** and does not distinguish instruction from data accesses.
>
> All functions except `clear_cache()` and `print_cache_contents()` take the address as an argument.

The bus operations, snoop results, and L1 messages use the following encodings:

| Bus Op | Snoop Result | L1 Message |
| --- | --- | --- |
| `1` READ | `0` NOHIT | `1` GETLINE |
| `2` WRITE | `1` HIT | `2` SENDLINE |
| `3` INVALIDATE | `2` HITM | `3` INVALIDATELINE |
| `4` RWIM | | `4` EVICTLINE |

---

## MESI State Transitions

The table below summarizes how each line transitions based on the current state and the incoming event. *No state changes occur on a NOHIT.*

| Current State | Event | Bus Op | Snoop Result | Next State |
| --- | --- | --- | --- | --- |
| **M** (Modified) | Local eviction | FlushWB (Write) | — | I |
| | PrRd | — | — | M |
| | PrWr | — | — | M |
| | Snooped Read | FlushWB (Write) | HITM | S |
| | Snooped ReadX | FlushWB (Write) | HITM | I |
| **E** (Exclusive) | Local eviction | — | — | I |
| | PrRd | — | — | E |
| | PrWr | — | — | M |
| | Snooped Read | Flush (Write) | HIT | S |
| | Snooped ReadX | Flush (Write) | HIT | I |
| **S** (Shared) | Local eviction | — | — | I |
| | PrRd | — | — | S |
| | PrWr | Upgr/Inv | — | M |
| | Snooped Upgr/Inv | — | — | I |
| | Snooped Read | — | HIT | S |
| | Snooped ReadX | — | — | I |
| **I** (Invalid) | PrRd | Read | NOHIT | E |
| | PrRd | Read | HIT/HITM | S |
| | PrWr | ReadX (RWIM) | — | M |
| | Snooped Read | — | NOHIT | I |

---

## Repository Layout

| Path | Description |
| --- | --- |
| `LLC_FINAL_MOD.sv` | The cache itself — module `cache_simulator1`. Contains all request-handling functions plus internal helpers for initialization, address decode, MESI/LRU management, and terminal I/O. |
| `trace_file_reader.sv` | Testbench. Reads a trace file and calls the appropriate function in `cache_simulator1`. |
| `Test Cases/` | The nine trace files (`testcase_0` … `testcase_9`) and a `README.md` describing expected results. |
| `Documentation/` | Design report, test plan, data-structure tables, and the algorithm/MESI reference. |
| `default.din` | Default trace file. |
| `miscellaneous.txt` | Supplementary notes. |

---

## Data Structures

The cache is modeled as a hierarchy of three structures plus a statistics counter block:

**`CacheLine_t`** — a single cache line
- `valid` — valid bit (1 bit)
- `tag` — tag bits (12 bits)
- `mesi_state` — MESI state (2 bits: I, S, E, M)

**`CacheSet_t`** — a set of 16 lines
- `lines[16]` — array of 16 `CacheLine_t`
- `lru_state` — pseudo-LRU bits for replacement (15 bits)

**`Cache_t`** — the full cache
- `sets[16384]` — array of 16,384 `CacheSet_t`

**`CacheStats_t`** — usage counters
- `read_count`, `write_count`, `hit_count`, `miss_count`

**Bus / messaging interface**
- `BusOperation()` — simulate bus operations
- `GetSnoopResult()` / `PutSnoopResult()` — receive / report snoop results
- `MessageToCache()` — communicate with the higher-level (L1) cache

---

## How to Run

The design is simulated with ModelSim/QuestaSim. Compile both source files, then run the testbench.

**Compile (with full visibility for debugging):**

```sh
vsim -voptargs=+acc work.trace_file_reader
```

**Run a specific trace file from the command line:**

```sh
vsim -c -do "run -all" work.trace_file_reader +filename=path/to/trace.din
```

Replace `path/to/trace.din` with any of the files in the `Test Cases/` directory (for example `rwims.din` or `t9.din`). If no `+filename` is supplied, the simulator falls back to `default.din`.

---

## Trace File Format

Each line of a trace file is a single request of the form:

```
n address
```

- `n` — request code (`0`–`9`, see [Supported Requests](#supported-requests))
- `address` — target address, `00000000`–`FFFFFFFF` (up to 4 bytes)

Addresses are **case-insensitive** and may be shorter than 4 bytes (leading bits are assumed to be `0`). One request per line.

Example:

```
0 0BADBAD0
1 00000002
6 2BADBAD0
9 BAD0BAD0
```

---

## Operating Modes

The simulation runs in one of two modes:

| Mode | Name | Output |
| --- | --- | --- |
| `0` | **Silent** | Usage-statistics summary plus the response to any `9` (print) requests in the trace. |
| `1` | **Normal** | Everything in Silent mode **plus** bus operations, reported snoop results, and L2→L1 messages. |

---

## Example Output

### Snoop / RWIM / invalidate sequence (`rwims.din`, Normal mode)

This run exercises read requests, an RWIM, and a series of snooped invalidate commands across lines in the Shared, Exclusive, and Modified states. Note the `HITM` snoop result and `FlushWB` behavior when a Modified line is invalidated.

![Simulation output for the rwims trace](docs/images/sim_rwims.png)

### Print contents and state (`t9.din`, Normal mode)

This run shows an Exclusive→Modified transition on a write, then prints the valid cache lines along with their set, way, tag, and MESI state, followed by the usage statistics and hit ratio.

![Simulation output for the print/t9 trace](docs/images/sim_print.png)

---

## Test Suite

Testing used a suite of nine trace files, one per request type. Expected results are documented in `Test Cases/README.md`. Each case targets boundary addresses (`00000000` and `FFFFFFFF`), sub-4-byte and case-insensitive addresses, hits/misses/evictions, and MESI transitions where relevant.

| Test Case | Focus | Expected (R / W / Hits / Misses / Ratio) |
| --- | --- | --- |
| `testcase_0_read` | Read hit / miss / evict, boundary addresses | 29 / 0 / 10 / 19 / 0.345 |
| `testcase_1_write` | Write hit / miss / evict, MESI transitions | 2 / 31 / 13 / 20 / 0.394 |
| `testcase_2_instruction` | Instruction read (identical to read) | same as `testcase_0` |
| `testcase_3_snoopread` | Snooped read, MESI transitions | 2 / 1 / 0 / 3 / 0.000 |
| `testcase_4_snoopwrite` | Snooped write (should have no effect) | 0 / 0 / 0 / 0 / 0.000 |
| `testcase_5_snoopmodify` | Snooped RWIM, flush-write-back | 2 / 1 / 0 / 3 / 0.000 |
| `testcase_6_snoopinvalidate` | Snooped invalidate, MESI transitions | 2 / 1 / 0 / 3 / 0.000 |
| `testcase_8_clear` | Clear cache → all ways invalid | — |
| `testcase_9_print` | Fill a set, print contents in M/E/S | 19 / 1 / 0 / 20 / 0.000 |

A few notable expectations:

- **`testcase_5_snoopmodify`** should produce one bus write (FlushWB) for `00200002` and three INVALIDATELINE messages to L1 for `00000002`, `00100000`, and `00200002`; afterward all ways are invalid.
- **`testcase_6_snoopinvalidate`** and **`testcase_8_clear`** should both leave every way in the Invalid state.
- **`testcase_9_print`** fills all ways of set `3FFE` and places lines in the E (`00000042`), S (`00000080`), and M (`00FFF82`) states.

---

## Assumptions

- **Processor:** requests stay within the cache's 4-byte address range.
- **Memory subsystem:** requests are handled in arrival order; a request is not handled until the previous one completes. A 6-bit byte offset is sufficient for a 64-byte line. A write-back policy is used.
- **Interfaces:** addresses are no more than 4 bytes; for shorter addresses the leading bits are `0`.
- **L1 cache:** uses the MESI protocol.

---

## Authors

ECE 485/585 — Group 7

- Deven Bishnu
- Bhavana Manikyanahalli Srinivasegowda
- Lokarjun Ramesh
- Xiang Li
