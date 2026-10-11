"""Checks the InkML traces of written pages with Wacom's universal-ink-library.

Run: uvx --with universal-ink-library==2.1.1 --with 'bitstring<5' python core/tests/inkml_check.py <dir>...
Each <dir> is an expected-output notebook from core/tests/fixtures/documents
(pages/*.svg and samples.json, the engine's samples of every stroke).

For each page, the page's inkml:traceFormat and inkml:trace elements are copied
into one InkML document and parsed with InkMLParser. For every stroke, the point
count and the first and last X and Y must equal the engine's samples.

InkMLParser reads channels from context/inkSource/traceFormat, converts pt to
96-dpi units, and repeats the first and last point of each spline.
"""

import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from uim.codec.parser.inkml import InkMLParser

INKML = "http://www.w3.org/2003/InkML"
SVG = "http://www.w3.org/2000/svg"
XML_ID = "{http://www.w3.org/XML/1998/namespace}id"
PT_PER_UNIT = 72 / 96
TOLERANCE = 0.005  # values are written with 2 decimals


def inkml_document(page: Path) -> tuple[bytes, list[str]]:
    root = ET.parse(page).getroot()
    ink = ET.Element(f"{{{INKML}}}ink")
    definitions = ET.SubElement(ink, f"{{{INKML}}}definitions")
    for trace_format in root.iter(f"{{{INKML}}}traceFormat"):
        format_id = trace_format.get(XML_ID)
        context = ET.SubElement(definitions, f"{{{INKML}}}context", {XML_ID: format_id})
        source = ET.SubElement(context, f"{{{INKML}}}inkSource", {XML_ID: f"src-{format_id}"})
        source.append(trace_format)
    stroke_ids = []
    for path in root.iter(f"{{{SVG}}}path"):
        trace = path.find(f"{{{SVG}}}metadata/{{{INKML}}}trace")
        if trace is None:
            continue
        stroke_ids.append(path.get("id"))
        trace.set(XML_ID, path.get("id"))
        ink.append(trace)
    ET.register_namespace("", INKML)
    return ET.tostring(ink), stroke_ids


def check(notebook: Path) -> list[str]:
    expected = json.loads((notebook / "samples.json").read_text())
    errors = []
    for page in sorted((notebook / "pages").glob("*.svg")):
        file = f"pages/{page.name}"
        document, stroke_ids = inkml_document(page)
        if not stroke_ids:
            continue
        strokes = InkMLParser().parse(document).strokes
        engine = [s for s in expected if s["file"] == file]
        if len(strokes) != len(engine):
            errors.append(f"{file}: {len(strokes)} traces parsed, engine has {len(engine)}")
            continue
        for stroke, sample in zip(strokes, engine):
            xs = [x * PT_PER_UNIT for x in stroke.splines_x[1:-1]]
            ys = [y * PT_PER_UNIT for y in stroke.splines_y[1:-1]]
            where = f"{file} {sample['id']}"
            if len(xs) != sample["count"]:
                errors.append(f"{where}: {len(xs)} points, engine has {sample['count']}")
                continue
            for name, got, want in (("first", (xs[0], ys[0]), sample["first"]),
                                    ("last", (xs[-1], ys[-1]), sample["last"])):
                if any(abs(g - w) > TOLERANCE for g, w in zip(got, want)):
                    errors.append(f"{where}: {name} point {got}, engine has {want}")
        print(f"{file}: {len(strokes)} traces checked")
    return errors


def main() -> int:
    errors = [e for arg in sys.argv[1:] for e in check(Path(arg))]
    for error in errors:
        print(error, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
