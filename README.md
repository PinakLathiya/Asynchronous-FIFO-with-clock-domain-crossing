# Asynchronous-FIFO-with-clock-domain-crossing

Parameterized dual-clock FIFO in Verilog-2005. Gray-coded pointers and 2-FF synchronizers carry the read and write pointers between two independent clock domains. A self-checking randomized testbench verifies it across four clock ratios.

## Architecture

```
 wclk domain                                    rclk domain
 +--------------+  wptr (gray) --> [2FF] -->  +---------------+
 |  wptr_full   |                              |  rptr_empty   |
 |  (wfull)     | <-- [2FF] <-- rptr (gray)   |  (rempty)     |
 +------+-------+                              +-------+-------+
        | waddr, wen                                   | raddr
        +----------------> [ fifo_mem ] <--------------+
                                |
                              rdata
```


- Pointers are `ADDR_WIDTH+1` bits. The extra MSB tells full apart from empty.
- **Full:** the next gray write pointer equals the synchronized read pointer with its top two bits inverted.
- **Empty:** the next gray read pointer equals the synchronized write pointer.
- Both flags are registered and conservative: they deassert a few cycles late but never assert early, so the FIFO cannot overflow or underflow.
- Only gray-coded pointers cross between domains, so at most one bit changes per sample.
- Read data is combinational from the memory (first-word fall-through): `rdata` is valid whenever `rempty == 0`.

## Schematic
<img width="1883" height="931" alt="image" src="https://github.com/user-attachments/assets/dbd1c095-dd25-4631-a488-4a0f1d37998e" />



### Parameters

| Parameter | Default | Meaning |
|---|---|---|
| `DATA_WIDTH` | 8 | Width of each word |
| `ADDR_WIDTH` | 4 | Depth = 2^ADDR_WIDTH (16 words) |

### Ports

| Port | Dir | Domain | Description |
|---|---|---|---|
| `wclk`, `wrst_n` | in | write | Write clock, active-low async reset |
| `winc`, `wdata` | in | write | Write request and data |
| `wfull` | out | write | FIFO full |
| `rclk`, `rrst_n` | in | read | Read clock, active-low async reset |
| `rinc` | in | read | Read request |
| `rdata`, `rempty` | out | read | Read data and FIFO empty |

## Files

| File | Purpose |
|---|---|
| `async_fifo.v` | RTL: top, `sync_2ff`, `fifo_mem`, `wptr_full`, `rptr_empty` |
| `tb_async_fifo.v` | Self-checking randomized testbench (scoreboard, overflow and underflow checks) |
| `async_fifo_sva.sv` | SystemVerilog assertions and cover points (bound onto the DUT) |
| `Makefile` | Runs the four clock ratios with Icarus Verilog |

## Verification

The testbench drives random write and read traffic in six phases per run, each phase lasting `CYCLES` write-clock cycles (default 20000):

| Phase | Write probability | Read probability |
|---|---|---|
| balanced | 50% | 50% |
| write-heavy | 90% | 20% |
| read-heavy | 20% | 90% |
| back-to-back | 100% | 100% |
| bursty-fill | 100% | 5% |
| bursty-drain | 5% | 100% |

After the last phase the testbench drains the FIFO and runs the final checks.

**Checks**
- Every word read matches the scoreboard in order (data integrity and ordering).
- A write is never accepted while the FIFO is truly full (no overflow).
- A read is never accepted while the FIFO is truly empty (no underflow).
- Total reads equal total writes after the drain, `rempty` is high and `wfull` is low.
- Full and empty are both actually hit during the run.

The read clock starts 3 ns after the write clock, so the edges are never aligned.

### Results (Vivado behavioral simulation)

| wclk half-period | rclk half-period | Writes | Reads | Full events | Empty events | Errors |
|---|---|---|---|---|---|---|
| 5 ns | 7 ns | 30093 | 30093 | 11147 | 3598 | 0 |
| 7 ns | 5 ns | 41918 | 41918 | 5014 | 15632 | 0 |
| 11 ns | 3 ns | 53275 | 53275 | 4869 | 33940 | 0 |
| 3 ns | 11 ns | 14500 | 14500 | 9235 | 1342 | 0 |

**Total: 139,786 words written and read with 0 errors.** Every run printed `PASS`. Icarus Verilog gives the same results to within one count.

### Clock domain crossing analysis

Vivado `report_cdc` on the implemented design (xc7a12ticsg325-1L):

| Direction | Endpoints | Safe | Unsafe | Unknown | No ASYNC_REG |
|---|---|---|---|---|---|
| wclk to rclk | 5 | 5 | 0 | 0 | 0 |
| rclk to wclk | 5 | 5 | 0 | 0 | 0 |

All ten pointer-bit crossings are recognized as 2-FF synchronizers. The Warning severity in the report appears because the crossings are covered by the `set_clock_groups -asynchronous` constraint, which is expected. FIFO data crossing the domains is protected by the pointer protocol: the write side only overwrites locations the read side has released, and the read side only reads locations the write side has published.

### SystemVerilog assertions

`async_fifo_sva.sv` checks that:
- the gray pointers change by at most one bit per clock,
- pointers hold still when a write is blocked by full or a read is blocked by empty,
- reset state is correct (pointers zero, `wfull` low, `rempty` high),

and it covers the first full and first empty. It needs a SystemVerilog simulator (Vivado xsim, Questa, or Verilator). Results: pending.

## How to run

**Icarus Verilog**

```
make          # four clock ratios, prints PASS or FAIL for each
make wave     # short run that writes wave.vcd for GTKWave
```

**Vivado**

1. Create an RTL project and add `async_fifo.v` under Design Sources.
2. Add `tb_async_fifo.v` under Simulation Sources and set it as top.
3. Run Behavioral Simulation, then `run all` in the Tcl console.
4. To change the clock ratio, edit `WH` (write half-period) and `RH` (read half-period) in the testbench.

**Verilator (with assertions)**

```
verilator --binary --assert --timing -Wno-fatal async_fifo.v async_fifo_sva.sv tb_async_fifo.v --top-module tb_async_fifo
```

## Possible extensions

- Registered read output (block RAM friendly) and almost-full / almost-empty flags
- Formal proof of pointer and flag invariants with SymbiYosys
- Randomized clock ratios and reset-during-traffic tests
