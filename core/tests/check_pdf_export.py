#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["Pillow==11.3.0"]
# ///

"""Check PDF exports of the authored notebook fixtures with Poppler and Pillow."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import tempfile
from pathlib import Path
from xml.etree import ElementTree

from PIL import Image, ImageChops, ImageStat


def expected_size(source: Path, page_file: str) -> tuple[float, float]:
    root = ElementTree.parse(source / page_file).getroot()
    _, _, width, height = map(float, root.attrib["viewBox"].split())
    return width, height


def check_fixture(source: Path, output: Path) -> None:
    manifest = json.loads((source / "notebook.json").read_text())
    pages = manifest["pages"]
    pdf = output / f"{source.name}.pdf"
    subprocess.run(["qpdf", "--check", str(pdf)], check=True, capture_output=True)
    info = subprocess.run(
        ["pdfinfo", "-f", "1", "-l", str(len(pages)), "-box", str(pdf)],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    page_count = re.search(r"^Pages:\s+(\d+)$", info, re.MULTILINE)
    if page_count is None or int(page_count.group(1)) != len(pages):
        raise AssertionError(f"{source.name}: PDF page count differs from notebook")
    boxes = {
        int(number): tuple(map(float, (x0, y0, x1, y1)))
        for number, x0, y0, x1, y1 in re.findall(
            r"^Page\s+(\d+) MediaBox:\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)$",
            info,
            re.MULTILINE,
        )
    }
    if len(boxes) != len(pages):
        raise AssertionError(f"{source.name}: missing PDF page dimensions")

    with tempfile.TemporaryDirectory() as temporary:
        for number, page in enumerate(pages, 1):
            width, height = expected_size(source, page["file"])
            x0, y0, x1, y1 = boxes[number]
            if abs((x1 - x0) - width) > 0.02 or abs((y1 - y0) - height) > 0.02:
                raise AssertionError(
                    f"{source.name} page {number}: PDF size "
                    f"{x1 - x0:g} x {y1 - y0:g} pt differs from SVG "
                    f"{width:g} x {height:g} pt"
                )

            engine = Image.open(output / f"{source.name}-{number}.png").convert("RGB")
            prefix = Path(temporary) / f"{source.name}-{number}"
            subprocess.run(
                [
                    "pdftoppm", "-f", str(number), "-l", str(number),
                    "-singlefile", "-scale-to-x", str(engine.width),
                    "-scale-to-y", str(engine.height), "-png", str(pdf), str(prefix),
                ],
                check=True,
                capture_output=True,
            )
            raster = Image.open(prefix.with_suffix(".png")).convert("RGB")
            if raster.size != engine.size:
                raise AssertionError(
                    f"{source.name} page {number}: raster sizes differ "
                    f"({raster.size} versus {engine.size})"
                )
            difference = ImageChops.difference(engine, raster)
            mean = max(ImageStat.Stat(difference).mean)
            channels = difference.split()
            maximum = ImageChops.lighter(
                ImageChops.lighter(channels[0], channels[1]), channels[2]
            )
            over = maximum.point(lambda value: 255 if value > 32 else 0).histogram()[255]
            fraction = over / (engine.width * engine.height)
            if mean > 2 or fraction > 0.01:
                raise AssertionError(
                    f"{source.name} page {number}: PDF raster differs "
                    f"(mean channel {mean:.2f}, {fraction:.3%} over 32)"
                )
            print(f"{source.name} page {number}: {width:g} x {height:g} pt, "
                  f"mean channel {mean:.2f}, {fraction:.3%} over 32")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("documents", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    sources = sorted(path for path in args.documents.iterdir() if (path / "notebook.json").is_file())
    if not sources:
        raise AssertionError("no notebook fixtures found")
    for source in sources:
        check_fixture(source, args.output)


if __name__ == "__main__":
    main()
