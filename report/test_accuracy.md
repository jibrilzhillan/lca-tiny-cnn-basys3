# Test-set accuracy of the FPGA model

The integer golden model ([`hw/tools/int_model.py`](../hw/tools/int_model.py)) run on the full TuSimple test set, using the weights in [`mem/`](../mem/) (decision D25: `Fw1 = 8`, `Fa = 7`, `S1 = 9`, `Fw2 = 8`). These are the same `.mem` files the bitstream loads, and the RTL matches this model bit for bit (16/16 board images, 128/128 in [regression R1](regression/summary.md)), so this is the accuracy of the design running on the board.

| Measure | Result |
|---|---|
| Test images | 2,216 (`tusimple_preprocessed_test.npz`, never used for training) |
| **Accuracy** | **1,840 / 2,216 = 83.0%** (target ≥ 80%, decision D19) |
| Balanced accuracy (mean of the three recalls) | 84.6% |
| Always-STRAIGHT baseline | 61.0% |

## Confusion matrix

Rows are the true label, columns the predicted class.

| True \ Predicted | LEFT | STRAIGHT | RIGHT | Total | Recall |
|---|---|---|---|---|---|
| LEFT | 612 | 48 | 1 | 661 | 92.6% |
| STRAIGHT | 218 | 1,060 | 74 | 1,352 | 78.4% |
| RIGHT | 2 | 33 | 168 | 203 | 82.8% |

The most common error is a centred car classified as LEFT (218 of the 376 errors). LEFT and RIGHT are almost never confused with each other (3 frames).

For comparison, validation accuracy during training was 83.8% (balanced 86.9%) on 628 validation frames.

## Reproduce

The test set is not in this repository (TuSimple licence). Build it with `sw/preprocess_tusimple.py` (see the main README), then from the repo root:

```
python hw/tools/eval_test_set.py --dataset path/to/tusimple_preprocessed_test.npz
```

Run on 2026-11-06 with NumPy 2.4.
