# Board test log

One section per bitstream tested on the Basys3. Build IDs match `implementation_log.md`.

## How to test

1. Program the board: `program_board.tcl`. Check the output says `End of startup status: HIGH` and the DONE LED is on.
2. Press BTNU (reset) once.
3. For each image: set SW[3:0], press BTNC, and write down the seven-segment result (`LF` / `St` / `rt`) and which LED lit (LED11 = PASS, LED10 = FAIL).
4. On any one image, turn on SW14 and read the cycle count: SW13 off shows the low 4 hex digits, SW13 on shows the top digit.
5. Repeat one image several times without reset, and press BTNC while BUSY is lit. The result should stay the same.

## Expected results (all builds with the current `mem/`)

Computed by an integer model with the same arithmetic as the RTL (S1 = 9, round half up, clamp 0–127, 2×2 max-pool, FC plus bias, argmax with the lowest index winning ties). That model matched the training export's golden vectors on 100 of 100 images.

| SW[3:0] | Label | Expected display | Expected LED |
|---|---|---|---|
| 0 | LEFT | LF | PASS |
| 1 | STRAIGHT | St | PASS |
| 2 | RIGHT | rt | PASS |
| 3 | LEFT | LF | PASS |
| 4 | STRAIGHT | St | PASS |
| 5 | RIGHT | rt | PASS |
| 6 | LEFT | LF | PASS |
| 7 | STRAIGHT | St | PASS |
| 8 | RIGHT | rt | PASS |
| 9 | LEFT | LF | PASS |
| A | STRAIGHT | **LF** | **FAIL** (model error) |
| B | RIGHT | rt | PASS |
| C | LEFT | LF | PASS |
| D | STRAIGHT | **LF** | **FAIL** (model error) |
| E | RIGHT | rt | PASS |
| F | LEFT | LF | PASS |

Expected: 14/16 PASS. Expected latency: `C9C8` with SW13 off, `0001` with SW13 on, meaning 0x1C9C8 = 117,192 cycles.

Images A and D are model errors (the logits favour LEFT). If the board matches this table, the hardware behaves the same as the golden model.

## B01 (2583f6a)

Programmed on 2026-11-04 at about 11:05, but not tested before its `.bit` file was overwritten. B03 is the same design.

## Unarchived GUI build (2026-11-04, about 11:59): failed

A `top_basys3` bitstream built in the GUI from a project created for `bringup_top`, so without the quant config (`S1 = -1`). The board showed `rt` on every image except A (`LF`). Cause: the project lacked the generated quantization header. Fix: always create the project with `create_project.tcl` (D26). Not a valid build, so it has no build number.

## B03 (2583f6a): pass

Programmed and tested on 2026-11-04 (about 12:35). Timing fails by 0.259 ns at the slow corner, but the board works at room temperature.

| SW[3:0] | Display | LED | Matches expected? |
|---|---|---|---|
| 0 | LF | PASS | yes |
| 1 | St | PASS | yes |
| 2 | rt | PASS | yes |
| 3 | LF | PASS | yes |
| 4 | St | PASS | yes |
| 5 | rt | PASS | yes |
| 6 | LF | PASS | yes |
| 7 | St | PASS | yes |
| 8 | rt | PASS | yes |
| 9 | LF | PASS | yes |
| A | LF | FAIL | yes (model error, as expected) |
| B | rt | PASS | yes |
| C | LF | PASS | yes |
| D | LF | FAIL | yes (model error, as expected) |
| E | rt | PASS | yes |
| F | LF | PASS | yes |

- Result: **16/16 match the golden model**; 14/16 match the true label.
- Latency (SW14): `0001C9C8` = 117,192 cycles = 1.17 ms at 100 MHz, the same as simulation.
- Repeated runs stable: not recorded
- BTNC while busy ignored: not recorded

## B04 (a98620d)

Not programmed. B05 replaces it.

## B05 (e1fc44c): pass

Programmed and tested on 2026-11-05. The first build that meets timing at 100 MHz (WNS +0.651 ns, TNS 0). Same behaviour on the board as B03.

| SW[3:0] | Display | LED | Matches expected? |
|---|---|---|---|
| 0 | LF | PASS | yes |
| 1 | St | PASS | yes |
| 2 | rt | PASS | yes |
| 3 | LF | PASS | yes |
| 4 | St | PASS | yes |
| 5 | rt | PASS | yes |
| 6 | LF | PASS | yes |
| 7 | St | PASS | yes |
| 8 | rt | PASS | yes |
| 9 | LF | PASS | yes |
| A | LF | FAIL | yes (model error, as expected) |
| B | rt | PASS | yes |
| C | LF | PASS | yes |
| D | LF | FAIL | yes (model error, as expected) |
| E | rt | PASS | yes |
| F | LF | PASS | yes |

- Result: **16/16 match the golden model**; 14/16 match the true label (images A and D are model errors, as for B03).
- Latency (SW14): `0001C9C8` = 117,192 cycles = 1.17 ms at 100 MHz, as expected.
- Repeated runs stable: yes
- BTNC while busy ignored: not testable by hand (a run takes 1.17 ms, too short to press BTNC during it). Covered in simulation by U7 (`hw/tb/cnn/tb_cnn_ctrl.v`), which asserts START during every busy stage and checks it is rejected.
