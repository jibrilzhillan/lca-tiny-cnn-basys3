
from pathlib import Path
import json
import cv2
import numpy as np

# Change these paths to match your Kaggle download.
DATA_ROOT = Path("test_set")
OUTPUT_FILE = Path("tusimple_preprocessed_test.npz")

# Common annotation files in the TuSimple dataset.
ANNOTATION_FILES = [
    DATA_ROOT / "test_label.json",
]

# One hex value per line (see hw/README.md, memories table): copy both files to mem/.
OUTPUT_IMAGE_MEM = Path("test_images.mem")
OUTPUT_LABEL_MEM = Path("test_labels.mem")
MAX_IMAGES = 16

CROP_TOP = 320
CROP_BOTTOM = 720       # Python excludes 720, so rows 320..719


CROP_LEFT = 240
CROP_RIGHT = 1040

OUT_W = 64
OUT_H = 32

IMAGE_CENTER_X = 640.0
CENTER_THRESHOLD = 0.15

PIXEL_BITS = 8
WORD_BITS = 16

def select_balanced_sample(images, classes, offsets, paths, max_images=16):
    """
    Select up to max_images samples with a mix of LEFT, CENTER, RIGHT.

    Uses round-robin selection to balance the classes.
    """

    class_indices = {
        class_id: [
            i for i, label in enumerate(classes)
            if label == class_id
        ]
        for class_id in range(3)
    }

    # Shuffle each class independently for variety.
    rng = np.random.default_rng(42)

    for indices in class_indices.values():
        rng.shuffle(indices)

    selected_indices = []

    # Round-robin selection: LEFT -> CENTER -> RIGHT.
    while len(selected_indices) < max_images:
        added = False

        for class_id in range(3):
            if class_indices[class_id]:
                selected_indices.append(
                    class_indices[class_id].pop()
                )
                added = True

                if len(selected_indices) >= max_images:
                    break

        if not added:
            break

    selected_indices = np.asarray(selected_indices, dtype=np.int64)

    return (
        images[selected_indices],
        offsets[selected_indices],
        classes[selected_indices],
        [paths[i] for i in selected_indices],
    )

def export_image_mem(images, output_file):
    """
    Export images as 8-bit hexadecimal values, one pixel per line.

    Each image is 32x64 grayscale.
    Pixels are stored in row-major order, image 0 first.
    This matches image_rom in the RTL (32,768 x 8, address {img, y, x}).

    Each image contains:
        32 rows x 64 pixels = 2048 lines

    16 images = 32768 lines.
    """

    output_file.parent.mkdir(parents=True, exist_ok=True)

    with output_file.open("w") as f:
        for image in images:
            # Flatten in row-major order.
            pixels = image.flatten(order="C")

            # One 8-bit pixel per line.
            for pixel in pixels:
                f.write(f"{int(pixel):02X}\n")

    print(f"Saved image memory: {output_file}")


def export_label_mem(classes, output_file):
    """
    Export labels as 2-bit hexadecimal values.

    LEFT   = 00
    CENTER = 01
    RIGHT  = 10
    """

    output_file.parent.mkdir(parents=True, exist_ok=True)

    with output_file.open("w") as f:
        for class_id in classes:
            f.write(f"{int(class_id):02X}\n")

    print(f"Saved label memory: {output_file}")

def inspect_lane_geometry(record, target_y=670):
    lanes = record["lanes"]
    h_samples = record["h_samples"]

    lane_xs = []

    for lane in lanes:
        x = interpolate_lane_x(lane, h_samples, target_y)

        if x is not None:
            lane_xs.append(x)

    lane_xs.sort()

    candidates = [
        (left, right)
        for left, right in zip(lane_xs[:-1], lane_xs[1:])
        if left < IMAGE_CENTER_X < right
    ]

    if len(candidates) != 1:
        return None

    left, right = candidates[0]

    lane_width = right - left

    if lane_width < 50:
        return None

    lane_center = (left + right) / 2.0
    half_width = lane_width / 2.0

    offset = (IMAGE_CENTER_X - lane_center) / half_width

    if offset < -CENTER_THRESHOLD:
        class_id = 0
    elif offset > CENTER_THRESHOLD:
        class_id = 2
    else:
        class_id = 1

    return {
        "left_x": left,
        "right_x": right,
        "lane_width": lane_width,
        "lane_center": lane_center,
        "offset": offset,
        "class_id": class_id
    }

def load_annotations(files):
    for filename in files:
        if not filename.exists():
            print(f"Skipping missing annotation file: {filename}")
            continue

        with filename.open("r") as f:
            for line in f:
                if line.strip():
                    yield json.loads(line)


def interpolate_lane_x(lane, h_samples, target_y):
    """Interpolate x at target_y using valid annotated lane points."""
    points = [
        (float(y), float(x))
        for x, y in zip(lane, h_samples)
        if x >= 0
    ]
    points.sort()

    if len(points) < 2:
        return None

    ys = np.array([p[0] for p in points])
    xs = np.array([p[1] for p in points])

    # Avoid extrapolating outside the annotated range.
    if target_y < ys[0] or target_y > ys[-1]:
        return None

    return float(np.interp(target_y, ys, xs))


def generate_labels(record, target_y=670):
    """Return normalized offset and class ID, or None if ambiguous."""
    lanes = record["lanes"]
    h_samples = record["h_samples"]

    # Find annotated lanes at the same near-bottom image row.
    lane_xs = []
    for lane in lanes:
        x = interpolate_lane_x(lane, h_samples, target_y)
        if x is not None:
            lane_xs.append(x)

    # TuSimple lanes are commonly ordered left to right, but sort
    # the valid points explicitly to avoid depending on list order.
    lane_xs.sort()

    # Find adjacent boundaries that bracket the image center.
    candidates = [
        (left, right)
        for left, right in zip(lane_xs[:-1], lane_xs[1:])
        if left < IMAGE_CENTER_X < right
        and right - left > 20
    ]

    if not candidates:
        return None

    # Prefer the narrowest plausible bracketing pair.
    # Review this heuristic against rendered annotations.
    left, right = min(candidates, key=lambda p: p[1] - p[0])

    lane_center = (left + right) / 2.0
    half_width = (right - left) / 2.0

    offset = (IMAGE_CENTER_X - lane_center) / half_width
    offset = float(np.clip(offset, -2.0, 2.0))

    if offset < -CENTER_THRESHOLD:
        class_id = 0  # LEFT
    elif offset > CENTER_THRESHOLD:
        class_id = 2  # RIGHT
    else:
        class_id = 1  # CENTER

    return offset, class_id


from collections import Counter

def diagnose_labels(record, target_y=670):
    lanes = record["lanes"]
    h_samples = record["h_samples"]

    valid_xs = []
    for lane in lanes:
        x = interpolate_lane_x(lane, h_samples, target_y)
        if x is not None:
            valid_xs.append(x)

    valid_xs.sort()

    if len(valid_xs) < 2:
        return "fewer_than_two_lanes", valid_xs

    candidates = [
        (left, right)
        for left, right in zip(valid_xs[:-1], valid_xs[1:])
        if left < IMAGE_CENTER_X < right
    ]

    if not candidates:
        return "center_not_bracketed", valid_xs

    wide_candidates = [
        (left, right)
        for left, right in candidates
        if right - left > 20
    ]

    if not wide_candidates:
        return "lane_width_too_small", valid_xs

    return "accepted", valid_xs


def run_label_diagnostics():
    counts = Counter()
    examples = {}

    for record in load_annotations(ANNOTATION_FILES):
        reason, xs = diagnose_labels(record)
        print(inspect_lane_geometry(record))
        counts[reason] += 1

        if reason != "accepted" and reason not in examples:
            examples[reason] = {
                "raw_file": record["raw_file"],
                "valid_lane_xs": xs,
                "h_samples": record["h_samples"],
                "lanes": record["lanes"],
            }

    print("\n===== LABEL DIAGNOSTICS =====")
    for reason, count in counts.most_common():
        print(f"{reason}: {count}")

    for reason, example in examples.items():
        print(f"\nExample: {reason}")
        print("Image:", example["raw_file"])
        print("Valid lane x at target row:", example["valid_lane_xs"])


# if __name__ == "__main__":
#     run_label_diagnostics()


def preprocess_image(image_path):
    image = cv2.imread(str(image_path), cv2.IMREAD_COLOR)
    if image is None:
        return None

    if image.shape[0] < CROP_BOTTOM or image.shape[1] != 1280:
        return None

    # Crop original rows 320 through 719.
    crop = image[
        CROP_TOP:CROP_BOTTOM,
        CROP_LEFT:CROP_RIGHT
    ]

    # OpenCV reads BGR, not RGB.
    b, g, r = cv2.split(crop)
    gray = (
        0.299 * r.astype(np.float32)
        + 0.587 * g.astype(np.float32)
        + 0.114 * b.astype(np.float32)
    )

    # INTER_AREA is suitable for downsampling.
    gray = cv2.resize(
        gray, (OUT_W, OUT_H),
        interpolation=cv2.INTER_AREA
    )

    # Keep uint8 pixels for compact storage.
    return np.clip(np.rint(gray), 0, 255).astype(np.uint8)
def inspect_annotation_data(num_samples=5):
    for idx, record in enumerate(load_annotations(ANNOTATION_FILES)):

        if idx >= num_samples:
            break

        h_samples = record["h_samples"]
        lanes = record["lanes"]

        print(f"\n===== SAMPLE {idx + 1} =====")
        print("Image:", record["raw_file"])

        print("h_samples count:", len(h_samples))
        print("h_samples min:", min(h_samples))
        print("h_samples max:", max(h_samples))

        print("Number of lanes:", len(lanes))

        for lane_idx, lane in enumerate(lanes):
            valid_points = [
                (y, x)
                for x, y in zip(lane, h_samples)
                if x >= 0
            ]

            print(f"\nLane {lane_idx}:")
            print("Lane length:", len(lane))
            print("Valid points:", len(valid_points))

            if valid_points:
                print("First valid point:", valid_points[0])
                print("Last valid point:", valid_points[-1])
                print(
                    "Y range:",
                    min(y for y, x in valid_points),
                    "to",
                    max(y for y, x in valid_points)
                )

            print(
                "Interpolated x at 670:",
                interpolate_lane_x(lane, h_samples, 670)
            )

def main():
    images, offsets, classes, paths = [], [], [], []

    stats = {
        "records": 0,
        "labels_missing": 0,
        "images_unreadable": 0,
        "images_wrong_size": 0,
        "accepted": 0,
    }

    for record in load_annotations(ANNOTATION_FILES):
        stats["records"] += 1

        labels = generate_labels(record)

        if labels is None:
            stats["labels_missing"] += 1
            continue

        image_path = DATA_ROOT / record["raw_file"]

        img = cv2.imread(str(image_path), cv2.IMREAD_COLOR)

        if img is None:
            stats["images_unreadable"] += 1
            continue

        if img.shape[0] < CROP_BOTTOM or img.shape[1] != 1280:
            stats["images_wrong_size"] += 1
            continue

        img = preprocess_image(image_path)

        if img is None:
            stats["images_unreadable"] += 1
            continue

        offset, class_id = labels

        images.append(img)
        offsets.append(offset)
        classes.append(class_id)
        paths.append(record["raw_file"])

        stats["accepted"] += 1

    print("\n===== PREPROCESSING REPORT =====")
    inspect_annotation_data(5)
    for key, value in stats.items():
        print(f"{key}: {value}")

    if not images:
        raise RuntimeError("No valid samples found.")

    images = np.stack(images)
    offsets = np.asarray(offsets, dtype=np.float32)
    classes = np.asarray(classes, dtype=np.uint8)

    # Select up to 16 images with balanced labels.
    images, offsets, classes, paths = select_balanced_sample(
        images,
        classes,
        offsets,
        paths,
        max_images=MAX_IMAGES,
    )

    print("\n===== SELECTED SAMPLE =====")
    print("Number of images:", len(images))
    print(
        "Class counts [LEFT, CENTER, RIGHT]:",
        np.bincount(classes, minlength=3),
    )

    # Export the selected images and labels.
    export_image_mem(images, OUTPUT_IMAGE_MEM)
    export_label_mem(classes, OUTPUT_LABEL_MEM)

    print("\n===== MEMORY REPORT =====")
    print("Number of images:", len(images))
    print("Image shape:", images.shape)
    print("Image memory lines:", len(images) * OUT_H * OUT_W)
    print("Label memory words:", len(classes))

    print(
        "Class counts [LEFT, CENTER, RIGHT]:",
        np.bincount(classes, minlength=3),
    )



if __name__ == "__main__":
    main()
