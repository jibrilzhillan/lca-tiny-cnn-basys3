# Design decisions

The decisions behind the design, with the reason for each. Code comments and reports refer to them by number (for example "D25"). Numbers that are missing were replaced by later decisions; they are listed at the end.

## Task and data

| ID | Decision | Reason |
|---|---|---|
| D1 | **Task: classify the car's position in its lane** (LEFT of centre / STRAIGHT = centred / RIGHT of centre) from one dash-camera image. The output is a position, not a steering command (see D27) | Directly useful for Lane Centering, Lane Keeping and Lane Departure Warning; lane markings survive heavy downscaling, so the model can be very small. Alternatives considered: speed-limit signs (fine-grained digits), colour traffic signs, driver drowsiness (eye open/closed) |
| D2 | **3 classes** | Clear class boundaries and enough samples per class. 5 classes was a stretch goal, not done |
| D16 | **Input: 64×32 grayscale uint8.** Crop rows 320–719 and columns 240–1039 of the 1280×720 frame, convert to gray, resize with OpenCV `INTER_AREA` (D27) | With the same network, 64×32 reached 86.3% test accuracy in the training study against 73.8% at 32×16. Cost: 2,048 bytes per image, 32 KB of image ROM for 16 images. Pillow and OpenCV resizing differ by up to 8 gray levels at this size, so one tool (OpenCV) is used for training, `.mem` export and golden data |
| D27 | **Labels from the car's offset from the lane centre** at image row 670: `offset = (640 − lane_centre) / (lane_width / 2)`; LEFT if offset < −0.15, RIGHT if > +0.15, else STRAIGHT. Frames where no pair of lane lines brackets x = 640 are discarded (`generate_labels()` in `sw/preprocess_tusimple.py`) | Describes where the car is now, using one row just ahead of the car. Result: train + validation 3,141 frames (920 / 2,010 / 211), test 2,216 (661 / 1,352 / 203). The middle class keeps the name STRAIGHT (`St` on the board); the Python code calls it CENTER |
| D21 | **The model is trained offline in PyTorch**, rebuilt from an earlier training study (100 float epochs, then 50 epochs of quantization-aware training; class-weighted loss; no flips). The training code is not in this repository; the trained model is in `sw/lane_model/` | Scales come from training, so the RTL reads `S1` from the exported `mem/quant_params.txt`. `sw/lane_model/lane_model_quantized_weights.npz` holds exactly the int8 weights in `mem/` |

## Network and number formats

| ID | Decision | Reason |
|---|---|---|
| D17 | **Network: Conv 3×3 ×4 → ReLU → MaxPool 2×2 → FC 1,860→3 → argmax** (1×32×64 → 4×30×62 → 4×15×31 → 1,860 → 3) | 5,616 weights and 72,540 MACs per image. 8 filters scored 88.1% but needs about 212,000 cycles and 16 BRAM36, so 4 filters was chosen |
| D5 | **Power-of-two quantization:** int8 weights, uint8 input, activations clamped to 0–127, int32 biases and logits, round half up | Every rescale is a bit shift, so no multipliers are needed for requantization, and bit-exact agreement with Python is easy to reach |
| D25 | **Scales: `Fw1 = 8`, `Fa = 7`, `Fw2 = 8`, `S1 = 9`** (`mem/quant_params.txt`). Conv biases are at scale 2⁻¹⁶, logits at 2⁻¹⁵ | With `Fw2 = 8` no FC weight is clipped at the int8 limits (range −81..79; D24's `Fw2 = 12` clipped 55%). `S1 = 8 + Fw1 − Fa` = 9 is the only scale the RTL uses; argmax works on raw logits. Validation accuracy 83.8% (balanced 86.9%), test accuracy 83.0% ([report/test_accuracy.md](report/test_accuracy.md)) |
| D10 | **Argmax ties go to the lowest class index** | Must be identical in Python and RTL |
| D11 | **Flatten order is channel-major (c, y, x)**; FC weight address `j*1860 + i` | Must be identical in Python and RTL |

## Hardware

| ID | Decision | Reason |
|---|---|---|
| D6 | **Layer-by-layer architecture with memory buffers between stages, 1 MAC per engine** | Each stage can be built and verified on its own, and its output memory can be compared directly with the Python dump. Parallel MACs or streaming would be faster but were not needed to meet D19 |
| D12 | **One 100 MHz clock domain**, synchronous active-high reset | Simplest timing closure |
| D7 | **Verilog-2001**, Vivado 2026.1, XSim | One language and one tool for design and simulation |
| D14 | **Generic `rom.v` / `ram.v`** in `hw/rtl/lib/`; every memory (image ROM, weight and bias ROMs, feature-map and pool RAMs, label ROM) is an instance of one of them | Two modules to write and verify instead of eight; width, depth, init file and ROM style are parameters |
| D22 | **Every size and width is a parameter in `hw/rtl/include/cnn_params.vh`** | The input size changed once (32×16 to 64×32); with all sizes in one header, the RTL followed by changing parameters and `.mem` files |
| D20 | **20-bit cycle counter.** With `SW[14] = 1`, `SW[13]` selects bits [15:0] or [19:16] on the display | About 117,000 cycles does not fit in 16 bits; 20 bits holds about 1 million |
| D8 | **Board I/O:** `SW[3:0]` selects one of 16 stored images, `BTNC` starts, `BTNU` resets, LED position bar, seven-segment `LF` / `St` / `rt`, PASS/FAIL LEDs, `SW[14]` latency view | Switches select stored test images rather than entering pixels; latency can be measured on the board |
| D15 | **`top_basys3` has a `USE_STUB` parameter:** 1 swaps in `cnn_core_stub`, 0 (default) uses the real `cnn_core` | Let the board side be simulated, built and tested before the CNN core existed |

## Targets

| ID | Decision | Reason |
|---|---|---|
| D19 | **Targets:** test accuracy ≥ 80% (integer model, full test set), latency ≤ 120,000 cycles, BRAM ≤ 30%, 100 MHz | With 1 MAC per engine, 64×32 cannot reach the original 30,000-cycle and 20%-BRAM targets. All targets are met (see the README) |

## Repository and build flow

| ID | Decision | Reason |
|---|---|---|
| D13 | **FPGA files under `hw/`** (`rtl/`, `tb/`, `constr/`, `vivado/`, `tools/`); `mem/` at the root | `mem/` is written by Python and read by the golden model, the testbenches and the bitstream, so it sits between `sw/` and `hw/`. The Tcl scripts add the `.mem` files from `mem/`, so `$readmemh` needs no relative paths |
| D23 | **Weight files are `conv_weight.mem`, `conv_bias.mem`, `fc_weight.mem`, `fc_bias.mem`, and `mem/` holds the only copy** | A second copy elsewhere could silently go stale |
| D26 | **`create_project.tcl` defaults to `top_basys3`; `build_bitstream.tcl` archives each build's reports in `report/builds/Bnn_<commit>/`**, logged in `report/implementation_log.md` | A project created for another top silently built the wrong design. The archive ties every timing and utilization number to one commit |
| D28 | **Golden stage dumps in `mem/golden/` are generated by `hw/tools/export_golden.py`** from the integer model (`hw/tools/int_model.py`) and checked independently by `hw/tools/verify_export.py` | The testbenches compare every conv, pool, logit and class value with these files. Generating them from the same model that defines the arithmetic keeps one source of truth; re-run the script whenever `mem/` changes |

## Replaced decisions

| ID | Was | Replaced by |
|---|---|---|
| D3 | Input 32×16 | D16 |
| D4 | FC 420→3 (for the 32×16 input) | D17 |
| D9 | Provisional label threshold T = 0.15 on a look-ahead steering score | D18 |
| D18 | T = 0.05 on a look-ahead score at row 500 (behaved like a steering hint on curves) | D27 |
| D24 | Scales with `Fw2 = 12` (55% of FC weights clipped) | D25 |
