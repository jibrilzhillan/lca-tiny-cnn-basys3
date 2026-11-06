# int_model.py
# Vectorised integer golden model with the same arithmetic as the RTL.
"""Integer CNN model that matches the RTL bit for bit.

Arithmetic (decisions D24/D25, mem/quant_params.txt):
  conv   acc = bias + sum(pixel_u8 * w_s8)         (int24)
  requant y = clamp((acc + 2^(S1-1)) >> S1, 0, 127) (round half up)
  pool   2x2 max, stride 2 (the 30x62 map loses no row or column: 15x31)
  fc     logit = bias + sum(pool_u7 * w_s8)          (int32)
  argmax lowest index wins a tie
Reads weights from the .mem files, so it checks exactly what the FPGA loads.
"""
from pathlib import Path
import re
import numpy as np

IMG_H, IMG_W = 32, 64
CH, CW = 30, 62
PH, PW = 15, 31
POOL = 4 * PH * PW  # 1860
CLASS_NAMES = ('LEFT', 'STRAIGHT', 'RIGHT')


def read_mem(path, bits, signed):
    v = np.array([int(x, 16) for x in Path(path).read_text().split()], dtype=np.int64)
    if signed:
        v = np.where(v >= 1 << (bits - 1), v - (1 << bits), v)
    return v


def read_s1(mem_dir):
    text = (Path(mem_dir) / 'quant_params.txt').read_text(encoding='utf-8-sig')
    return int(re.search(r'^\s*S1\s*=\s*(\d+)', text, re.M).group(1))


class IntModel:
    def __init__(self, mem_dir):
        mem_dir = Path(mem_dir)
        self.conv_w = read_mem(mem_dir / 'conv_weight.mem', 8, True).reshape(4, 3, 3)
        self.conv_b = read_mem(mem_dir / 'conv_bias.mem', 32, True)
        self.fc_w = read_mem(mem_dir / 'fc_weight.mem', 8, True).reshape(3, POOL)
        self.fc_b = read_mem(mem_dir / 'fc_bias.mem', 32, True)
        self.s1 = read_s1(mem_dir)

    def run(self, images):
        """images: uint8 array (N, 32, 64). Returns dict of int arrays."""
        x = images.astype(np.int64)
        n = x.shape[0]
        acc = np.zeros((n, 4, CH, CW), dtype=np.int64)
        for ky in range(3):
            for kx in range(3):
                patch = x[:, ky:ky + CH, kx:kx + CW]
                acc += patch[:, None] * self.conv_w[None, :, ky, kx, None, None]
        acc += self.conv_b[None, :, None, None]
        assert np.all((acc >= -(1 << 23)) & (acc < (1 << 23))), 'conv int24 overflow'
        conv = np.clip((acc + (1 << (self.s1 - 1))) >> self.s1, 0, 127)
        pool = conv.reshape(n, 4, PH, 2, PW, 2).max(axis=(3, 5))
        flat = pool.reshape(n, POOL)  # C, Y, X order
        logits = flat @ self.fc_w.T + self.fc_b[None, :]
        assert np.all((logits >= -(1 << 31)) & (logits < (1 << 31))), 'fc int32 overflow'
        cls = np.argmax(logits, axis=1)  # numpy picks the lowest index on ties
        return {'conv': conv, 'pool': flat, 'logits': logits, 'class': cls}
