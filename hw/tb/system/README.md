# System tests

Testbenches that run more than one module together. All are self-checking and run from [`hw/vivado/run_tests.tcl`](../../vivado/run_tests.tcl), except the many-image regression, which has its own script.

| Testbench | What it checks | Expected values from |
|---|---|---|
| `tb_conv_pool.v` (I2) | conv_engine → maxpool_engine for all 16 board images | `mem/golden/conv_all.mem`, `pool_all.mem` |
| `tb_cnn_core.v` (I3, I4, I5) | the full `cnn_core` on all 16 images back to back: every conv, pool, logit and class value; the cycle count; reset during a run | `mem/golden/` |
| `tb_top_basys3_real.v` | the board top with the real core: buttons with bounce, all 16 images, the latency display, a press while busy, reset during a run | `mem/golden/expected_class.mem`, `mem/test_labels.mem` |
| `tb_top_basys3.v` | the same board-level checks with `cnn_core_stub` | the stub's fixed answers |
| `tb_classifier_core.v` | real max-pool, FC and argmax inside the core, with a fake conv engine | vectors from `tb/classifier/generate_classifier_fixtures.py` |
| `tb_cnn_core_wiring.v` | memories, controller and timing only, with fake engines from `tb/common/mocks/` (not the CNN arithmetic) | vectors from `generate_core_fixtures.py` |
| `tb_cnn_regression.v` (R1) | many TuSimple test images through the real core | `hw/tools/int_model.py` |

`mem/golden/` is written by `hw/tools/export_golden.py` from the integer model (D28). Re-run it whenever a file in `mem/` changes.

The fake engines in `tb/common/mocks/` and the two tests that use them are guarded by `CNN_CORE_WIRING_TEST`, which is off by default. The project script adds `hw/tb/` recursively, so a normal project must never pick up the fake engines. Only `run_tests.tcl` defines the flag, for those two tests.

## Many-image regression (R1)

`tb_cnn_regression.v` runs the real `cnn_core` on N images from the TuSimple **test** set (default 128) and compares the three logits, the class and the cycle count of every image with the Python integer model. The image ROM holds 16 images, so the testbench loads the next 16 into `dut.image_rom.mem` between batches. This is simulation only; the board build is unchanged.

It needs the preprocessed test set (`sw/tusimple_preprocessed_test.npz`, not in the repository; see the main README). One command from the repo root generates the vectors, runs the simulation and writes `summary.md` and per-image CSVs to `hw/vivado/build/regression/`:

```
python hw/tools/run_regression.py                        # XSim if Vivado is found, else Icarus
python hw/tools/run_regression.py --sim icarus --count 256
python hw/tools/run_regression.py --report report/regression   # also copy results for the report
```

Needs NumPy. About 1.4 s per image with Icarus Verilog. The last results are in [`report/regression/summary.md`](../../../report/regression/summary.md).
