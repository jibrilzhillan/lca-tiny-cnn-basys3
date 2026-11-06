# generate_core_fixtures.py
# Generate synthetic wiring and memory fixtures; never training exports.
"""Generate independent synthetic references for cnn_core wiring tests.

These are transport-test vectors, NOT training data or CNN golden dumps.
Only Python's standard library is required.
"""

import argparse
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"common"))
from cnn_test_config import architecture, pixels as make_pixels


def write_hex(path, values, digits):
    mask = (1 << (digits * 4)) - 1
    path.write_text(
        "".join(f"{value & mask:0{digits}X}\n" for value in values),
        encoding="ascii",
    )


def generate(output_dir):
    output_dir.mkdir(parents=True, exist_ok=True)
    a=architecture()
    images, features, pools, logits, classes = [], [], [], [], []
    for image_id in range(a["NUM_IMAGES"]):
        pixels = make_pixels(image_id,a)
        feature_map = [(pixels[index % a["PIXELS"]] ^ index) & 127 for index in range(a["FMAP"])]
        pooled = [max(feature_map[index:index + 4]) for index in range(0, a["FMAP"], 4)]
        checksum = sum(pooled)
        center=a["POOL"]*600//7
        margin=a["POOL"]//2
        scores = [checksum-center, center-checksum, margin]
        images.extend(pixels)
        features.extend(feature_map)
        pools.extend(pooled)
        logits.extend(scores)
        classes.append(max(range(3), key=lambda index: scores[index]))

    assert len(images) == a["NUM_IMAGES"]*a["PIXELS"] and len(features) == a["NUM_IMAGES"]*a["FMAP"]
    assert len(pools) == a["NUM_IMAGES"]*a["POOL"] and len(logits) == a["NUM_IMAGES"]*3
    assert set(classes)=={0,1,2}, "Synthetic vectors must cover all classes"
    write_hex(output_dir / "core_test_images.mem", images, 2)
    write_hex(output_dir / "core_expected_fmap.mem", features, 2)
    write_hex(output_dir / "core_expected_pool.mem", pools, 2)
    write_hex(output_dir / "core_expected_logits.mem", logits, 8)
    write_hex(output_dir / "core_expected_classes.mem", classes, 1)
    write_hex(output_dir / "memory_test_u8.mem", [(i * 73 + 19) & 255 for i in range(16)], 2)
    write_hex(output_dir / "memory_test_s32.mem", [-1, 0, -(1 << 31)], 8)
    print("Generated architecture-sized synthetic wiring vectors and all three classes.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    generate(parser.parse_args().output_dir)
