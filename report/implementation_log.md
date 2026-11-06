# Implementation log

One row per bitstream build of `top_basys3`, from the first real-core build to timing closure. Each build's reports are in `builds/Bnn_<commit>/`.

Commit hashes in this log and in the `builds/` folder names refer to the original development repository; this public copy starts with a fresh history.

## How to add a build

1. Commit the RTL change first. Use a message that names the build, for example `fc: map MAC to DSP48 for timing (B02)`.
2. Run `run_tests.tcl` and confirm it passes before building.
3. Run `create_project.tcl` (default top `top_basys3`; only needed if files were added or removed), then `build_bitstream.tcl`. Don't change the top in the GUI: the project then lacks the quant config, and `build_bitstream.tcl` now refuses to build it. The script archives the reports in `builds/Bnn_<commit>/` and prints a row for the table below. A build from uncommitted `hw/` or `mem/` changes gets a `_dirty` suffix and can't be reproduced from git.
4. Paste the row into the table, fill in the change, and add a short section under "Build notes".
5. If the change is a design choice, add it to `DESIGN_DECISIONS.md`.
6. If the build is programmed on the board, record the result in `board_test_log.md`.

## Builds

All builds target 100 MHz (10 ns). Fmax = 1 / (10 ns − WNS) when WNS < 0.

| Build | Commit | Change | WNS (ns) | TNS (ns) | LUT | FF | BRAM | DSP | Board |
|---|---|---|---|---|---|---|---|---|---|
| B01 | 2583f6a | Baseline: first real-core build (`USE_STUB = 0`) | −0.259 | −2.059 | 652 | 405 | 12.5 | 0 | programmed, not tested (bitstream overwritten) |
| B02 | 2583f6a (dirty) | `bringup_top` (H0 test), not the CNN. See note | +7.332 | 0 | 14 | 26 | 0 | 0 | — |
| B03 | 2583f6a (dirty) | Rebuild of B01 from a correctly created project (quant config present) | −0.259 | −2.059 | 652 | 405 | 12.5 | 0 | **16/16 as expected, 117,192 cycles** |
| B04 | a98620d | Conv MAC mapped to a DSP48 (`conv_engine.v`, `mac.v`) | −0.246 | −1.055 | 546 | 364 | 12.5 | 1 | not programmed |
| B05 | e1fc44c | FC multiply mapped to a DSP48 (`use_dsp` in `fc_engine.v`) on top of B04 | **+0.651** | **0** | 429 | 364 | 12.5 | 2 | **16/16 as expected, 117,192 cycles** |

Available resources: 20,800 LUT, 41,600 FF, 50 BRAM tiles, 90 DSP.

## Build notes

### B01: baseline (2026-11-04)

- **Design:** first integrated core (conv, classifier, controller and memories) with the board top. The fw2fix weights (Fw1 = 8, Fw2 = 8, Fa = 7, S1 = 9) and the 16 test images in `mem/`.
- **Timing fails:** WNS −0.259 ns, so Fmax ≈ 97.5 MHz. 16 setup endpoints fail. Hold passes (WHS +0.096 ns).
- **Critical path:** `u_fc/fc_w_rom` (BRAM output) → 9×8 multiply → 32-bit `accum` add → `accum_reg[31]`, all in one cycle. The data path is 10.19 ns (60.9% logic, 39.1% routing) with 14 logic levels (9 CARRY4, 5 LUT). The multiply is built from LUTs and carry chains rather than a DSP48, which is why DSP use is 0.
- **Resources:** 3.1% LUT, 1.0% FF, 25% BRAM (12 RAMB36 + 1 RAMB18; the D19 target is ≤ 30%), 0 DSP (the plan expected 2).
- **Archive gaps:** this build was archived by hand after a later `bringup_top` build overwrote the project, so the synthesis warnings, DRC report and hierarchical utilization are missing. Builds from B02 on are archived automatically.
- **Next step:** try mapping the FC multiply-accumulate to a DSP48 (`use_dsp` attribute), which keeps the cycle count. If that's not enough, pipeline the product, which adds a cycle per MAC and needs FSM and testbench changes.

### B02: bringup_top (2026-11-04)

- Not a CNN build. `create_project.tcl` still defaulted to `bringup_top` and was run without `-tclargs`. Kept in the table only so build numbers stay continuous.
- That project was then switched to `top_basys3` **in the GUI** and built (not archived). It had no quant config, so `conv_engine` synthesized with `S1 = -1`: conv outputs were zero, the logits were just the FC biases, and the board showed `rt` for almost every image. Fixed by making `top_basys3` the default top (D26) and adding a check to `build_bitstream.tcl` that refuses to build the real core without the quant config.

### B03: first board-verified build (2026-11-04)

- Same design and same numbers as B01, built from a project created by `create_project.tcl` with `top_basys3` (synthesis log: `Parameter S1 bound to: 9`).
- **Board:** all 16 images as expected (14 PASS, images A and D FAIL as the golden model predicts), latency `0001C9C8` = 117,192 cycles. See `board_test_log.md`.
- **Timing still fails** (WNS −0.259 ns, same FC path as B01). The board works at room temperature, but the design isn't guaranteed at 100 MHz until WNS ≥ 0. Fixing it is the next build.
- Built in the GUI, so archived by hand (see `build_info.txt`).

### B04: DSP48 conv MAC (2026-11-04)

- **Change:** Rewrote `conv_engine.v` and `mac.v` so the conv multiply-accumulate maps to one DSP48E1, removed `signed_mult.v`, and updated `tb_conv_engine.v` and `tb_mac.v`.
- **Function unchanged:** behavioural simulation of `cnn_core` gives the same logits and classes as B03 on all 16 images, still 117,192 cycles.
- **Timing still fails, slightly better:** WNS −0.246 ns (was −0.259), TNS −1.055 ns (was −2.059), 9 failing endpoints (was 16). Every failing path still ends at `u_fc/accum_reg`: `pool_ram` BRAM → 9×8 multiply in LUTs → 32-bit add, 10.15 ns, 14 logic levels (9 CARRY4). The conv was never on the critical path. The small gain comes from ~100 fewer LUTs giving the placer more room, not from a shorter FC path.
- **Resources:** 546 LUT (−106), 364 FF (−41), 1 DSP (in `u_conv`).
- **DRC:** one DPIP-1 warning (conv DSP input A not pipelined). Advisory only.

### B05: DSP48 FC multiply, timing closed (2026-11-04)

- **Change:** Added `(* use_dsp = "yes" *)` to the FC `product` in `fc_engine.v` (commit d4cc1a2), on top of B04's conv change. Vivado now puts the 9×8 multiply and the accumulator add into one DSP48E1 (`u_fc/accum0`).
- **Function unchanged:** behavioural simulation of `cnn_core` at e1fc44c gives the same logits and classes as B03 and B04 on all 16 images, still 117,192 cycles. No FSM or testbench changes were needed.
- **Timing met at 100 MHz:** WNS **+0.651 ns**, TNS **0**, 0 failing setup endpoints out of 1,259; hold met (WHS +0.128 ns). The worst path is now `fc_w_rom` BRAM → DSP48 (`accum0/C[21]`), 8.86 ns with 2 logic levels (DSP48E1 + LUT4), down from 14. Estimated Fmax ≈ 1 / (10 − 0.651) ns ≈ 107 MHz.
- **Resources:** 429 LUT (2.1%), 364 FF, 12.5 BRAM (25%), 2 DSP (1 in `u_conv`, 1 in `u_fc`), which is what the plan expected.
- **DRC:** 5 warnings, 0 errors. DPIP-1 ×3 (DSP inputs not registered), DPOP-1 and DPOP-2 (FC DSP has PREG = 0 and MREG = 0). These are performance suggestions. Timing already passes, so no pipelining is needed.
- **Board:** all 16 images as expected (14 PASS, A and D FAIL as the golden model predicts), latency `0001C9C8` = 117,192 cycles, repeated runs stable. See `board_test_log.md`.

## Synthesis and implementation checks

| Check | Requirement | Status after B05 |
|---|---|---|
| S1 Synthesis warnings | No latches, no multi-driven nets, no unexpected "removed unused" logic | **Pass.** `synth_warnings.txt` has only Synth 8-7129 "port unconnected" for `sw[15], sw[12:4]` (switches not used yet). The B03 warning about `mac.acc_load_data[31:24]` is gone with the new `mac.v`. No latches, multi-driven nets or critical warnings |
| S2 BRAM inference | `image_rom`, `fmap_ram`, `pool_ram`, `fc_w_rom` in block RAM | **Pass.** `utilization_hier.txt`: `fc_w_rom` 2 RAMB36 inside `u_fc`; image ROM, feature-map RAM and pool RAM 10 RAMB36 + 1 RAMB18 in `cnn_core`. 0 LUT-as-memory |
| S3 DSP inference | 2 DSP48E1 for the MACs | **Pass (B05).** 2 DSP: one in `u_conv` (B04), one in `u_fc` (B05) |
| S4 Timing at 100 MHz | WNS ≥ 0, TNS = 0, no unconstrained paths | **Pass on internal paths (B05).** WNS +0.651 ns, TNS 0, WHS +0.128 ns, 0 unconstrained internal endpoints. Still open: 8 inputs have no input delay and 23 outputs have no output delay (switches, buttons, LEDs, seven-segment). Those are slow board I/O; whether to false-path them in the XDC still needs a decision |
| S5 XDC review | Every port has a pin and IOSTANDARD, no DRC errors | **Pass.** `drc.txt` (B05) has no errors, only the 5 DSP pipelining warnings above |

## Latency

The cycle count doesn't depend on timing closure or weight values. Simulation of the integrated core gives **117,192 cycles per inference** (1.17 ms at 100 MHz; the target is ≤ 120,000). The board readout on B03 agrees: `0001C9C8` = 117,192 cycles. B04 and B05 change only how the multipliers are built, not the schedule, so the count is the same.
