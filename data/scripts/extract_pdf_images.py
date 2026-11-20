#!/usr/bin/env python3
"""Extract every embedded image placement from an official quiz PDF.

Requires Poppler's ``pdfimages``. The JSON index records one entry per image
placement (including repeated placements of the same PDF object) and points to
the correspondingly numbered extracted asset.

Example:
  python3 scripts/extract_pdf_images.py downloads/2026-11-14/conseguimento-ab-it.pdf
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sqlite3
import shutil
import subprocess
import sys
from pathlib import Path


def pdfimages_path() -> str:
    candidates = [
        shutil.which("pdfimages"),
        "/opt/homebrew/bin/pdfimages",
        "/usr/bin/pdfimages",
        str(Path.home() / ".cache/codex-runtimes/codex-primary-runtime/dependencies/native/poppler/poppler/bin/pdfimages"),
    ]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return candidate
    raise SystemExit("pdfimages not found; install Poppler and put pdfimages on PATH")


def image_rows(pdfimages: str, pdf: Path) -> list[dict]:
    result = subprocess.run(
        [pdfimages, "-list", str(pdf)], check=True, text=True, capture_output=True
    )
    rows = []
    for line in result.stdout.splitlines():
        match = re.match(
            r"\s*(\d+)\s+(\d+)\s+(image|mask|smask)\s+(\d+)\s+(\d+)\s+"
            r"(\S+)\s+(\d+)\s+(\d+)\s+(\S+)\s+(\S+)\s+"
            r"(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\S+)\s+(\S+)",
            line,
        )
        if not match:
            continue
        page, number, kind, width, height, color, components, bpc, encoding, interp, obj, gen, xppi, yppi, size, ratio = match.groups()
        rows.append({
            "placement": len(rows),
            "page_1_based": int(page),
            "page_0_based": int(page) - 1,
            "image_number_on_page": int(number),
            "type": kind,
            "width": int(width),
            "height": int(height),
            "color_space": color,
            "components": int(components),
            "bits_per_component": int(bpc),
            "encoding": encoding,
            "interpolate": interp,
            "pdf_object": int(obj),
            "pdf_generation": int(gen),
            "x_ppi": int(xppi),
            "y_ppi": int(yppi),
            "encoded_size": size,
            "ratio": ratio,
        })
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", type=Path, help="Source PDF")
    parser.add_argument("--output", type=Path, help="Output directory (default: data/pdf_images)")
    args = parser.parse_args()
    pdf = args.pdf.expanduser().resolve()
    if not pdf.is_file():
        parser.error(f"PDF not found: {pdf}")
    output = (args.output or Path(__file__).resolve().parents[1] / "pdf_images").resolve()
    assets = output / "assets"
    assets.mkdir(parents=True, exist_ok=True)

    pdfimages = pdfimages_path()
    rows = image_rows(pdfimages, pdf)
    prefix = assets / "pdf-image"
    subprocess.run([pdfimages, "-all", str(pdf), str(prefix)], check=True)
    extracted = sorted(assets.glob("pdf-image-*"), key=lambda path: int(path.stem.rsplit("-", 1)[1]))
    if len(extracted) != len(rows):
        raise SystemExit(f"Expected {len(rows)} extracted images, found {len(extracted)}")

    canonical_db = Path(__file__).resolve().parents[1] / "database/ab/quiz.db"
    canonical_hashes = {}
    for candidate in (Path(__file__).resolve().parents[1] / "assets/ab").glob("*"):
        if candidate.is_file():
            canonical_hashes.setdefault(hashlib.sha256(candidate.read_bytes()).hexdigest(), []).append(candidate.name)
    db = sqlite3.connect(canonical_db)
    direct_questions = {}
    for question_id, image in db.execute("SELECT id, image FROM questions WHERE image IS NOT NULL"):
        direct_questions.setdefault(image, []).append(question_id)
    groups = {}
    for group_id, image in db.execute("SELECT id, image FROM question_groups WHERE image IS NOT NULL"):
        groups.setdefault(image, []).append(group_id)
    group_questions = {}
    for question_id, group_id in db.execute("SELECT id, group_id FROM questions"):
        group_questions.setdefault(group_id, []).append(question_id)
    db.close()

    for row, image_file in zip(rows, extracted):
        data = image_file.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        row["asset"] = image_file.relative_to(output).as_posix()
        row["format"] = image_file.suffix.lstrip(".").lower()
        row["bytes"] = len(data)
        row["sha256"] = digest
        row["canonical_assets"] = canonical_hashes.get(digest, [])
        row["direct_question_ids"] = sorted({qid for name in row["canonical_assets"] for qid in direct_questions.get(name, [])})
        row["group_question_ids"] = sorted({qid for name in row["canonical_assets"] for gid in groups.get(name, []) for qid in group_questions.get(gid, [])})

    pdfinfo = shutil.which("pdfinfo") or str(Path(pdfimages).with_name("pdfinfo"))
    info = subprocess.run(
        [pdfinfo, str(pdf)], check=True, text=True, capture_output=True
    ).stdout
    page_count = int(re.search(r"^Pages:\s+(\d+)", info, re.MULTILINE).group(1))
    index = {
        "source_pdf": pdf.name,
        "source_pdf_sha256": hashlib.sha256(pdf.read_bytes()).hexdigest(),
        "source_page_count": page_count,
        "extraction_tool": f"{Path(pdfimages).name} -all",
        "placement_count": len(rows),
        "mapping_note": "canonical_assets and question IDs are exact SHA-256 joins against data/assets/ab and database/ab/quiz.db. Direct question attachments are separate from group-level attachments.",
        "assets": rows,
    }
    (output / "image_index.json").write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n")
    print(f"Extracted {len(rows)} image placements to {assets}")
    print(f"Wrote {output / 'image_index.json'}")


if __name__ == "__main__":
    main()
