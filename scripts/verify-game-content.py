#!/usr/bin/env python3
"""Check the content shipped by both desktop exports, without a game engine."""
import argparse
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def compare_visual_baseline(exported_baseline, root=ROOT):
    """Compare parsed geometry so formatting never changes the contract."""
    checked_in = json.loads((root / "apps/game/data/visual-baseline.json").read_text())
    generated = json.loads(Path(exported_baseline).read_text())
    if checked_in != generated:
        raise RuntimeError("Shared visual baseline differs from the original Swift projection; regenerate with apps/game/tools/export-visual-baseline.swift")


def verify_font_assets(root=ROOT):
    directory = root / "apps/game/assets/fonts"
    provenance_path = directory / "provenance.json"
    provenance = json.loads(provenance_path.read_text())
    if provenance.get("family") != "Inter" or provenance.get("license") != "SIL Open Font License 1.1":
        raise RuntimeError("Missing Inter font identity or OFL license provenance")
    files = provenance.get("files", [])
    if len(files) != 2 or {entry.get("file") for entry in files} != {"Inter.ttf", "OFL.txt"}:
        raise RuntimeError("Inter provenance must identify exactly the original font and OFL license")
    for entry in files:
        path = directory / entry["file"]
        if hashlib.sha256(path.read_bytes()).hexdigest() != entry.get("sha256"):
            raise RuntimeError(f"Inter font/license differs from pinned provenance: {path.name}")
    if not (directory / "README.md").read_text().strip():
        raise RuntimeError("Missing portable font attribution notes")
    return hashlib.sha256(provenance_path.read_bytes()).hexdigest()


def verify(exported_course=None, exported_baseline=None):
    course_path = ROOT / "apps/game/data/course.json"
    course = json.loads(course_path.read_text())
    assert course["version"] == 1, "Unsupported course format"
    chapters = course["chapters"]
    assert chapters and all(isinstance(title, str) and title.strip() for title in chapters)
    assert len(set(chapters)) == len(chapters), "Duplicate chapter title"
    lessons = course["lessons"]
    assert lessons, "Empty course"
    assert len({item["id"] for item in lessons}) == len(lessons), "Duplicate lesson ID"
    assert len({item["version"] for item in lessons}) == len(lessons), "Duplicate lesson version"
    event_count = 0
    for index, lesson in enumerate(lessons):
        assert type(lesson["chapter"]) is int and 0 <= lesson["chapter"] < len(chapters), "Invalid chapter"
        if index > 0:
            assert lessons[index - 1]["chapter"] <= lesson["chapter"], "Chapters must stay in order"
        for key in ("id", "version", "title", "subtitle", "objective", "explanation",
                    "counts", "practice_minutes", "technique_tip", "reading_question"):
            assert isinstance(lesson[key], str) and lesson[key].strip(), f"Missing {key}"
        assert 48 <= lesson["bpm"] <= 144
        choices = lesson["reading_choices"]
        assert len(choices) == 3 and all(isinstance(c, str) and c.strip() for c in choices)
        assert type(lesson["reading_answer"]) is int and 0 <= lesson["reading_answer"] < len(choices)
        assert lesson["events"], "Empty lesson"
        targets = set()
        for event in lesson["events"]:
            beat, pad = event["beat"], event["pad"]
            assert isinstance(beat, (float, int)) and math.isfinite(beat) and 0 <= beat < 4
            assert beat * 2 == round(beat * 2), "Current notation supports quarter/eighth attacks"
            assert type(pad) is int and 0 <= pad < 3
            assert type(event["velocity"]) is int and 1 <= event["velocity"] <= 127
            assert event["hand"] in ("", "R", "L")
            assert (pad, beat) not in targets, "Duplicate target"
            targets.add((pad, beat))
            event_count += 1

    assert {lesson["chapter"] for lesson in lessons} == set(range(len(chapters))), "Empty chapter"

    if exported_course:
        assert course == json.loads(Path(exported_course).read_text()), "Shared course differs from authored native lessons; regenerate with apps/game/tools/export-course.swift"

    if exported_baseline:
        compare_visual_baseline(exported_baseline)
        print("Visual baseline matches geometry regenerated from the original Swift projection.")

    verify_font_assets()

    source = ROOT / "native/assets/BigRusty"
    destination = ROOT / "apps/game/assets/BigRusty"
    # Includes source/license text as well as recordings and their provenance.
    originals = {p.relative_to(source) for p in source.rglob("*") if p.is_file()}
    copies = {p.relative_to(destination) for p in destination.rglob("*") if p.is_file() and p.suffix != ".import"}
    assert originals == copies, "The exported sample bank has missing or extra files"
    for relative in sorted(originals):
        assert (source / relative).read_bytes() == (destination / relative).read_bytes(), f"Sample bank drift: {relative}"
    assert len(list(source.rglob("*.flac"))) == 80
    print(f"Shared content: {len(lessons)} lessons in {len(chapters)} chapters, {event_count} authored targets, 80 identical FLAC recordings, pinned Inter font/license, and complete provenance.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-course", help="JSON freshly emitted by the Swift course exporter")
    parser.add_argument("--native-visual-baseline", help="JSON freshly emitted by the Swift visual baseline exporter")
    args = parser.parse_args()
    verify(args.native_course, args.native_visual_baseline)
