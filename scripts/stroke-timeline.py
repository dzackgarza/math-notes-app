#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Rebuilds each pencil stroke's timeline from a Math Notes log and flags every
stroke that does not end committed.

Reads an idevicesyslog capture (plain or .gz) or the unified-log lines that CI
prints from the app tests. Each stroke runs from "pencil stroke began" to its
end, and collects the engine's decisions, the gesture recognizers that
recognized during it, and UIKit's cancellation.
"""

import gzip
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

# idevicesyslog: "Oct  9 23:27:30.639475 MathNotes[1985] <Info>: pencil stroke began"
DEVICE = re.compile(r"^(\w{3}\s+\d+ \d\d:\d\d:\d\d\.\d+) MathNotes\[\d+\] <\w+>: (.*)$")
# unified log: "2026-10-09 17:44:39.728817+0000 MathNotes[33192:90064] [ink] pencil stroke began"
UNIFIED = re.compile(r"(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)[+-]\d{4} MathNotes\[\d+:\d+\] \[\w+\] (.*)$")


@dataclass
class Stroke:
    began: str
    events: list[tuple[str, str]] = field(default_factory=list)
    recognized: list[str] = field(default_factory=list)
    outcome: str = "open: no end in the log"

    @property
    def committed(self) -> bool:
        return self.outcome.startswith("committed")


def lines(path: Path):
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt", errors="replace") as handle:
        for raw in handle:
            match = DEVICE.match(raw) or UNIFIED.search(raw)
            if match:
                yield match.group(1), match.group(2)


def timeline(path: Path) -> list[Stroke]:
    strokes: list[Stroke] = []
    current: Stroke | None = None
    for time, message in lines(path):
        if message == "pencil stroke began":
            current = Stroke(time)
            strokes.append(current)
            continue
        if current is None:
            continue
        if message.startswith("recognizer ") and "->3 " in message:
            current.recognized.append(message.split("->3 ", 1)[1])
        elif message.startswith(("pen-down", "stroke ", "live stroke", "sample dropped", "UIKit cancelled",
                                 "pencil stroke cancelled", "pencil stroke ended")):
            current.events.append((time, message))
        if message.startswith("stroke committed as"):
            current.outcome = "committed"
        elif message.startswith(("stroke committed nothing", "live stroke discarded", "stroke not started")):
            current.outcome = message
        elif message.startswith("UIKit cancelled touches: pencilStroke=true"):
            current.outcome = "cancelled by UIKit"
        elif message == "pencil stroke ended" and current.outcome.startswith("open"):
            # Logs from builds without the engine trace end here.
            current.outcome = "ended (no engine trace)"
    return strokes


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: stroke-timeline.py <capture.txt[.gz]>")
    strokes = timeline(Path(sys.argv[1]))
    if not strokes:
        sys.exit("no 'pencil stroke began' lines: not a Math Notes capture with app logging")
    outcomes: dict[str, int] = {}
    for stroke in strokes:
        outcomes[stroke.outcome] = outcomes.get(stroke.outcome, 0) + 1
        if stroke.committed:
            continue
        print(f"{stroke.began}  {stroke.outcome}")
        for name in stroke.recognized:
            print(f"    recognized: {name}")
        for time, message in stroke.events:
            print(f"    {time}  {message}")
    print(f"\n{len(strokes)} strokes")
    for outcome, count in sorted(outcomes.items(), key=lambda item: -item[1]):
        print(f"  {count:4}  {outcome}")


if __name__ == "__main__":
    main()
