<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## What it does

`tt_um_multi_stage_processor` is a mixed-signal processing pipeline that combines four independent datapath units — a 16-bit free-running counter, a 16-bit maximal-length LFSR, a 16-bit LFSR-fed shift register, and an 8-bit analog sampler — and routes their outputs through a configurable 5-stage combinational core. The stage sequence is: source selection → ALU operation → barrel shift → analog XOR injection → registered output. An 8-channel debug multiplexer exposes every internal signal simultaneously.

## How it works

**Datapath units** run continuously from reset release:

- `counter_16b` increments every clock.
- `lfsr_16b` advances a 16-bit Galois LFSR (polynomial x¹⁶+x¹⁴+x¹³+x¹¹+1, seed `0xACE1`).
- `shift_reg_16b` shifts in `lfsr_val[0]` each cycle.
- `analog_sampler_8b` shifts in the digital level of `ua[0]` each cycle, producing an 8-bit running sample.

**Analog path**: An external signal on `ua[1]` passes through the `yen_top` analog blackbox to `ua[0]`. This output is sampled digitally and becomes a first-class pipeline operand.

**5-stage combinational pipeline**:

1. **Source MUX** — `mode_sel` (ui_in[2:0]) selects one of 8 operand combinations from the four datapath units.
2. **ALU** — A 3-bit autonomous FSM (cycles 0→7 each clock unless `hold` is asserted) applies one of 8 operations: ADD, SUB, XOR, AND, OR-constant, counter-extended ADD/SUB, or pass-through. The `config` nibble (`uio_in[3:0]`) is the secondary operand.
3. **Barrel Shift** — A fully unrolled left-shifter shifts the ALU result 0–7 bits based on `config[2:0]`.
4. **Analog Injection** — The shifted result is XOR'd with `analog_sample`, coupling the analog domain into every output.
5. **Output Register** — The final value is registered on the rising clock edge, producing a glitch-free `uo_out`.

**Test mode** (`ui_in[7]` = 1) bypasses the pipeline and forces `uo_out = cnt[7:0]` for deterministic verification.

**Debug multiplexer** (`ui_in[6:4]`) selects which internal value is reflected on `uio_out[7:0]`: counter bytes, LFSR bytes, shift register, analog sample, pre-ALU source, or the packed FSM state and mode word.

## How to test

1. Apply reset: hold `rst_n` low for at least 2 clock cycles, then release.
2. Assert `ena = 1`.
3. **Test mode check**: set `ui_in = 8'b1000_0000`. Observe `uo_out` incrementing as a binary counter. This confirms the counter, clock, and output path are functional.
4. **Normal operation**: clear `ui_in[7]` (test_mode off). Set `mode_sel` via `ui_in[2:0]` to choose a source. Set `config` via `uio_in[3:0]` to control the ALU secondary operand and shift amount.
5. **Analog path**: drive a signal onto `ua[1]`. After several clock cycles, `debug_sel = 3'd5` (`ui_in[6:4] = 3'b101`) will show `analog_sample` on `uio_out`, confirming the sampler is active. Changing `ua[1]` will, over time, alter `uo_out`.
6. **FSM hold**: assert `ui_in[3] = 1`. Observe that `uo_out` stops changing between FSM-induced transitions (the ALU operation is frozen). Release to resume.
7. **Debug sweep**: cycle `ui_in[6:4]` through 0–7 and read `uio_out` to verify each internal signal independently.

## External hardware

An optional analog signal source (function generator or DAC, 0–VDD range) may be connected to `ua[1]` to exercise the analog sampling and injection path. Without it, the digital logic functions normally; `analog_sample` will hold a constant low value (matched to the testbench `pulldown` on `ua[0]`).

## Inputs/Outputs

| Port | Bits | Direction | Description |
|------|------|-----------|-------------|
| `ui_in` | [2:0] | Input | `mode_sel` — source operand selection |
| `ui_in` | [3] | Input | `hold` — freeze FSM when high |
| `ui_in` | [6:4] | Input | `debug_sel` — debug channel selection |
| `ui_in` | [7] | Input | `test_mode` — force deterministic counter output |
| `uo_out` | [7:0] | Output | Registered 5-stage pipeline output |
| `uio_in` | [3:0] | Input | `config` — ALU operand and shift amount |
| `uio_out` | [7:0] | Output | 8-bit debug word (upper nibble driven externally) |
| `uio_oe` | [7:0] | Output | `8'b1111_0000` — upper nibble output, lower nibble input |
| `ua[1]` | — | Analog In | Input to `yen_top` analog block |
| `ua[0]` | — | Analog Out | Output from `yen_top`; sampled into digital pipeline |
