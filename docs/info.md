---
title: Autonomous Mixed-Signal Pipeline Core
---

## What it does

`tt_um_multi_stage_processor` is a mixed-signal processing pipeline that combines four independent datapath units — a 16-bit free-running counter, a 16-bit maximal-length LFSR, a 16-bit LFSR-fed shift register, and an 8-bit analog sampler — and routes their outputs through a configurable 5-stage combinational core. The stage sequence is: source selection → ALU operation → barrel shift → analog XOR injection → registered output. An 8-channel debug multiplexer exposes every internal signal simultaneously.

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
