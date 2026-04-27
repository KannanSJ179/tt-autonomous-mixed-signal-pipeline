# Simulation Guide — `tt_um_multi_stage_processor`

This directory contains the complete testbench for the mixed-signal processor.  
The testbench runs entirely in simulation using Icarus Verilog; no analogue tools are required.

---

## Files

| File | Purpose |
|------|---------|
| `tb_tt_um_multi_stage_processor.v` | Self-contained testbench; drives all stimulus and prints results |
| `tb.vcd` | Waveform dump (generated on each run) |

The design under test (`src/project.v`) is in the parent directory.

---

## Requirements

| Tool | Version | Install |
|------|---------|---------|
| Icarus Verilog (`iverilog` / `vvp`) | ≥ 10.x | `sudo apt install iverilog` or `brew install icarus-verilog` |
| GTKWave (optional, waveform viewer) | any | `sudo apt install gtkwave` or `brew install gtkwave` |

---

## Running the Simulation

```bash
# From the repository root
cd test/

# Compile
iverilog -o sim.out \
         tb_tt_um_multi_stage_processor.v \
         ../src/project.v

# Run — prints to stdout and writes tb.vcd
vvp sim.out

# View waveforms (optional)
gtkwave tb.vcd &
```

---

## Testbench Structure

The testbench exercises six distinct scenarios in sequence.

### Phase 1 — Reset and Enable

```
clk=0, ena=0, rst_n=0  →  after 30 ns: rst_n=1  →  after 10 ns: ena=1
```

All registers clear to 0. The counter, LFSR, and FSM begin advancing from the first enabled clock.

---

### Phase 2 — Test Mode (`ui_in[7] = 1`)

```verilog
ui_in = 8'b1_000_0_000;  // test_mode=1, debug_sel=0, hold=0, mode_sel=0
```

**Expected**: `uo_out` equals `cnt[7:0]` (low byte of the 16-bit free-running counter). This is a deterministic sanity check — independent of analog, LFSR, or FSM state.

**Verify**: `uo_out` increments by 1 each clock.

---

### Phase 3 — Analog Source with Dynamic Config

```verilog
ui_in    = 8'b0_001_0_011;   // test_mode=0, debug_sel=1 (cnt[15:8]), mode_sel=3 (analog_sample)
uio_in   = 8'bXXXX_0011;    // config = 3
```

**Expected**:
- `src_data = analog_sample` (shifted digital representation of `ua[0]`)
- ALU applies FSM-controlled operations with secondary operand `config=3`
- Barrel shift: `config[2:0]=3` → 3-bit left shift
- `uo_out` reflects the processed analog value XOR'd with `analog_sample` again at Stage 4
- `uio_out[7:4]` shows `cnt[15:8]` (debug channel 1)

**In simulation**: `ua[0]` is pulled low by the testbench `pulldown`, so `analog_sample` accumulates to `8'h00`. The output is therefore dominated by the pipeline arithmetic on `8'h00`, and will be close to `8'h00` XOR `8'h00 = 8'h00` unless counter or LFSR values dominate (mode 3 selects pure analog sample).

---

### Phase 4 — XOR Source with config = 7

```verilog
ui_in    = 8'b0_110_0_100;   // debug_sel=6 (src_data pre-ALU), mode_sel=4 (cnt^lfsr)
uio_in   = 8'bXXXX_0111;    // config = 7
```

**Expected**:
- `src_data = cnt[7:0] ^ lfsr_val[7:0]`
- `debug_sel=6` exposes `src_data` directly on `uio_out` — this allows visual comparison of the pre-ALU value vs the post-pipeline `uo_out`
- Barrel shift = 7 bits left → `alu_out` is heavily shifted; only the LSB of `alu_out` survives in `uo_out[7]`

**Verify**: `uio_out` and `uo_out` should differ by the ALU and shift transformations.

---

### Phase 5 — FSM Hold

```verilog
ui_in[3] = 1;  // hold asserted
```

**Expected**: `state` freezes; the ALU operation is fixed; `uo_out` changes only as fast as the source data changes (counter/LFSR still increment, LFSR still shifts). `uo_out` should be visibly more stable — not frozen, but the ALU mode is locked.

**Verify**: Before and after hold, the rate of change of `uo_out` differs.

---

### Phase 6 — Debug Multiplexer Sweep

```verilog
for (i = 0; i < 8; i++) begin
    ui_in[6:4] = i;
    #60;
    $display("debug_sel=%d -> uio_out[7:4] = %h", i, uio_out[7:4]);
end
```

| `debug_sel` | Expected `uio_out` source |
|------------|--------------------------|
| 0 | `cnt[7:0]` — increments each cycle |
| 1 | `cnt[15:8]` — increments slowly |
| 2 | `lfsr_val[7:0]` — pseudo-random |
| 3 | `lfsr_val[15:8]` — pseudo-random |
| 4 | `shift_val[7:0]` — LFSR-fed shift register |
| 5 | `analog_sample` — 8-bit digital analog snapshot (0x00 with pulldown) |
| 6 | `src_data` — pre-ALU value; matches mode_sel operand |
| 7 | `{1'b0, state[2:0], mode_sel[2:0]}` — packed FSM + mode |

**Verify**: Each channel reads a meaningfully different value. Channel 7 should show bits [5:3] cycling 0→7 (FSM state) and bits [2:0] fixed at the current mode.

---

### Phase 7 — Analog Toggle

```verilog
force ua[1] = 1'b1;  #200;
force ua[1] = 1'b0;  #200;
release ua[1];
```

**Expected**: With `ua[1]` forced high, `yen_top` passes `analog_in → analog_out`, so `ua[0]` goes high. The `analog_sampler_8b` begins shifting in `1` bits. After 8 clocks, `analog_sample` approaches `8'hFF`. This propagates through Stage 4 (XOR injection) and changes `uo_out`. Returning `ua[1]` low reverses the effect.

**Verify**: `uo_out` after the toggle sequence differs from `uo_out` before it.

---

## Interpreting Results

| Symptom | Likely cause |
|---------|-------------|
| `uo_out` constant at `0` | `ena` not asserted or `rst_n` never released |
| `uo_out` equals `cnt[7:0]` always | `test_mode` (`ui_in[7]`) stuck high |
| `uo_out` never changes | `hold` stuck high and source data is `analog_sample` which is constant |
| `uio_out` all zeros | `uio_oe` not properly observed by testbench; upper nibble should be driven |
| Analog phases have no effect | Normal in simulation with stub — `ua[0]` requires `force` to change |

---

## Waveform Signals (GTKWave)

Recommended signals to add to GTKWave in order:

```
clk
rst_n
ena
ui_in[7:0]
uio_in[3:0]
uo_out[7:0]
uio_out[7:0]
dut.core.cnt[15:0]
dut.core.lfsr_val[15:0]
dut.core.shift_val[15:0]
dut.core.analog_sample[7:0]
dut.core.state[2:0]
dut.core.src_data[7:0]
dut.core.alu_out[7:0]
dut.core.shifted[7:0]
dut.core.s4[7:0]
```

This ordering traces the full pipeline from inputs to registered output, making timing relationships immediately visible.
