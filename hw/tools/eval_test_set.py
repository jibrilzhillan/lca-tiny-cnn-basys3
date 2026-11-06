# eval_test_set.py
# Test-set accuracy of the integer model, using exactly the weights the FPGA loads.
"""Evaluate the integer golden model (int_model.py) on the preprocessed TuSimple test set.

The weights come from mem/ (the same .mem files the bitstream uses), so the
accuracy printed here is the accuracy of the design on the board. The RTL
matches this model bit for bit (see report/regression/summary.md).

The test set is not in the repository (TuSimple licence). Build it with
sw/preprocess_tusimple.py, which writes sw/tusimple_preprocessed_test.npz.

Usage (from the repo root):
  python hw/tools/eval_test_set.py
  python hw/tools/eval_test_set.py --dataset path/to/tusimple_preprocessed_test.npz
"""
import argparse
from pathlib import Path
import sys

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from int_model import IntModel, CLASS_NAMES  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--dataset', type=Path, default=ROOT / 'sw' / 'tusimple_preprocessed_test.npz')
    p.add_argument('--mem-dir', type=Path, default=ROOT / 'mem')
    a = p.parse_args()

    data = np.load(a.dataset)
    images, labels = data['images'], data['classes'].astype(int)
    pred = IntModel(a.mem_dir).run(images)['class']

    n, ok = len(labels), int((pred == labels).sum())
    cm = np.zeros((3, 3), dtype=int)
    for t, q in zip(labels, pred):
        cm[t, q] += 1
    recall = cm.diagonal() / cm.sum(axis=1)

    print(f'Images: {n} ({a.dataset.name}), weights: {a.mem_dir}')
    print(f'Accuracy: {ok}/{n} = {100 * ok / n:.2f}%')
    print(f'Balanced accuracy (mean recall): {100 * recall.mean():.2f}%')
    print(f'Always-STRAIGHT baseline: {100 * (labels == 1).mean():.2f}%')
    print()
    print('Confusion matrix (rows = true label, columns = predicted)')
    print(f'{"":>10}' + ''.join(f'{c:>10}' for c in CLASS_NAMES) + f'{"total":>8}{"recall":>9}')
    for i, c in enumerate(CLASS_NAMES):
        print(f'{c:>10}' + ''.join(f'{v:>10}' for v in cm[i]) + f'{cm[i].sum():>8}{100 * recall[i]:>8.1f}%')


if __name__ == '__main__':
    main()
