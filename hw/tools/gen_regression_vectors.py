# gen_regression_vectors.py
# Export N TuSimple test images plus the integer model's expected outputs for tb_cnn_regression.v.
"""Generate the vectors for the many-image RTL regression (tb_cnn_regression.v).

Takes a seeded random sample of the preprocessed TuSimple test set (images the
model never trained on), runs the integer golden model (int_model.py) on it, and
writes, in --out:

  reg_images.mem    N x 2048 pixels, 2 hex digits, row-major, image 0 first
                    (same layout as mem/test_images.mem)
  reg_expected.mem  per image: logit0, logit1, logit2 (8 hex digits, two's
                    complement), class (1 hex digit)  -> 4 lines per image
  reg_labels.mem    true label per image, 1 hex digit
  reg_manifest.csv  index, dataset index, path, label, expected class, logits

N is rounded up to a multiple of 16 because the testbench loads the 16-image
image ROM one batch at a time.
"""
import argparse
import csv
from pathlib import Path
import sys

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from int_model import IntModel, CLASS_NAMES  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--count', type=int, default=128, help='images to test (rounded up to a multiple of 16; default 128)')
    p.add_argument('--all', action='store_true', help='use the whole test set (slow in simulation)')
    p.add_argument('--seed', type=int, default=2026)
    p.add_argument('--dataset', type=Path, default=ROOT / 'sw' / 'tusimple_preprocessed_test.npz')
    p.add_argument('--mem-dir', type=Path, default=ROOT / 'mem')
    p.add_argument('--out', type=Path, required=True)
    a = p.parse_args()

    data = np.load(a.dataset)
    images, labels, paths = data['images'], data['classes'].astype(int), data['paths']
    total = len(labels)
    if a.all:
        idx = np.arange(total)
    else:
        n = min(a.count, total)
        idx = np.sort(np.random.default_rng(a.seed).choice(total, size=n, replace=False))
    pad = (-len(idx)) % 16
    if pad:  # fill the last batch with more random images rather than repeats
        rest = np.setdiff1d(np.arange(total), idx)
        extra = np.random.default_rng(a.seed + 1).choice(rest, size=min(pad, len(rest)), replace=False)
        idx = np.concatenate([idx, np.sort(extra)])
    assert len(idx) % 16 == 0, 'test set too small to fill the last batch'

    model = IntModel(a.mem_dir)
    sel = images[idx]
    r = model.run(sel)
    n = len(idx)

    a.out.mkdir(parents=True, exist_ok=True)
    with open(a.out / 'reg_images.mem', 'w') as f:
        for px in sel.reshape(-1):
            f.write(f'{int(px):02X}\n')
    with open(a.out / 'reg_expected.mem', 'w') as f:
        for k in range(n):
            for v in r['logits'][k]:
                f.write(f'{int(v) & 0xFFFFFFFF:08X}\n')
            f.write(f'{int(r["class"][k]):08X}\n')
    with open(a.out / 'reg_labels.mem', 'w') as f:
        for y in labels[idx]:
            f.write(f'{int(y):X}\n')
    with open(a.out / 'reg_manifest.csv', 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['index', 'dataset_index', 'path', 'label', 'label_name', 'py_class', 'py_class_name',
                    'py_logit0', 'py_logit1', 'py_logit2'])
        for k, d in enumerate(idx):
            w.writerow([k, int(d), str(paths[d]), int(labels[d]), CLASS_NAMES[labels[d]], int(r['class'][k]),
                        CLASS_NAMES[r['class'][k]], *[int(v) for v in r['logits'][k]]])

    acc = float(np.mean(r['class'] == labels[idx]))
    counts = np.bincount(labels[idx], minlength=3)
    print(f'REGRESSION VECTORS: {n} images from {a.dataset.name} (seed {a.seed}), '
          f'labels LEFT/STRAIGHT/RIGHT = {counts.tolist()}, integer-model accuracy {acc:.2%} -> {a.out}')


if __name__ == '__main__':
    main()
