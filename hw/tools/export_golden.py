# export_golden.py
# Write the golden stage dumps for the 16 board images (mem/golden/), used by the testbenches.
"""Export golden stage dumps of the integer model for the 16 board images.

Runs int_model.py on mem/test_images.mem with the weights in mem/ and writes,
in --out (default mem/golden/):

  conv_all.mem        16 x 7,440 conv + ReLU outputs, order (image, c, y, x), 2 hex digits
  pool_all.mem        16 x 1,860 max-pool outputs, order (image, c, y, x), 2 hex digits
  logits_all.mem      16 x 3 logits, 8 hex digits, two's complement
  expected_class.mem  16 classes (golden-model prediction, not the true label), 1 hex digit

tb_conv_pool.v, tb_cnn_core.v and tb_top_basys3_real.v compare the RTL with
these files, and hw/tools/verify_export.py re-checks them independently.
Re-run this script whenever a file in mem/ changes.

Usage (from the repo root):  python hw/tools/export_golden.py
"""
import argparse
from pathlib import Path
import sys

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from int_model import IntModel, IMG_H, IMG_W, read_mem  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]


def write(path, values, digits):
    mask = (1 << (4 * digits)) - 1
    path.write_text(''.join(f'{int(v) & mask:0{digits}X}\n' for v in values), encoding='ascii')


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--mem-dir', type=Path, default=ROOT / 'mem')
    p.add_argument('--out', type=Path, default=None)
    a = p.parse_args()
    out = a.out or a.mem_dir / 'golden'
    out.mkdir(parents=True, exist_ok=True)

    images = read_mem(a.mem_dir / 'test_images.mem', 8, False).reshape(-1, IMG_H, IMG_W)
    r = IntModel(a.mem_dir).run(images)
    write(out / 'conv_all.mem', r['conv'].reshape(-1), 2)
    write(out / 'pool_all.mem', r['pool'].reshape(-1), 2)
    write(out / 'logits_all.mem', r['logits'].reshape(-1), 8)
    write(out / 'expected_class.mem', r['class'], 1)

    labels = read_mem(a.mem_dir / 'test_labels.mem', 2, False)
    print(f'Wrote golden dumps for {len(images)} images to {out}')
    print(f'Golden class: {"".join(str(c) for c in r["class"])}')
    print(f'True label:   {"".join(str(c) for c in labels)}  ({int((r["class"] == labels).sum())}/{len(images)} correct)')


if __name__ == '__main__':
    main()
