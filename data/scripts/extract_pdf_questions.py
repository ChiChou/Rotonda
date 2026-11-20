#!/usr/bin/env python3
"""Parse an official Italian PDF to raw text and CSV. SQLite is build output only."""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path



HEADER = re.compile(r"^\s*Quesito\s+n[°º]\s*(\d+)\s*-\s*(.*?)\s*$", re.IGNORECASE)
# Official tables place IDs at the left margin. Indented numeric text belongs
# to the prompt (for example '25000 chilometri' in Superiori question 29284).
QUESTION = re.compile(r"^(\d{4,6})\s+(.*\S)?\s*$")
ANSWER = re.compile(r"\s+(VERO|FALSO)\s*$", re.IGNORECASE)
TABLE_HEADER = re.compile(r"Numero\s+Testo domanda", re.IGNORECASE)


def convert(pdf: Path, pdftotext: str) -> str:
    proc = subprocess.run(
        [pdftotext, "-layout", str(pdf), "-"],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if proc.returncode:
        raise RuntimeError(proc.stderr.strip() or f"pdftotext exited with {proc.returncode}")
    return proc.stdout


def extract(text: str) -> tuple[list[dict], list[dict], list[str]]:
    """Parse grouped questions, preserving wrapped text and PDF page numbers."""
    groups: dict[int, dict] = {}
    questions: list[dict] = []
    warnings: list[str] = []
    active_group: dict | None = None
    current: dict | None = None
    heading_open = False

    def take_answer(line: str) -> tuple[str, int | None]:
        match = ANSWER.search(line)
        if not match:
            return line.strip(), None
        return line[:match.start()].strip(), int(match.group(1).upper() == "VERO")

    def finish_question(page_no: int) -> None:
        nonlocal current
        if current is None:
            return
        body = " ".join(current["parts"])
        if current["answer"] is None:
            warnings.append(f"page {current['page'] + 1}: question {current['number']} has no parsed VERO/FALSO answer")
        else:
            answer = current["answer"]
            question_text = body.strip()
            if not question_text:
                warnings.append(f"page {current['page'] + 1}: question {current['number']} has an empty prompt")
            elif current["group"] is None:
                warnings.append(f"page {current['page'] + 1}: question {current['number']} appears before a Quesito heading")
            else:
                questions.append({
                    "number": current["number"],
                    "quesito_id": current["group"]["id"],
                    "text_it": question_text,
                    "answer": answer,
                    "page": current["page"],
                })
        current = None

    for page_no, page in enumerate(text.split("\f")):
        for line in page.splitlines():
            h = HEADER.match(line)
            if h:
                finish_question(page_no)
                gid, category = int(h.group(1)), h.group(2).strip()
                if gid in groups and groups[gid]["category"] != category:
                    warnings.append(f"page {page_no + 1}: Quesito {gid} category changed; keeping first value")
                active_group = groups.setdefault(gid, {"id": gid, "category": category, "page": page_no, "source_order": len(groups)})
                heading_open = True
                continue
            if TABLE_HEADER.search(line) or re.fullmatch(r"\s*domanda\s*", line, re.IGNORECASE):
                heading_open = False
                continue
            if heading_open and line.strip():
                if 'Ministero delle Infrastrutture' not in line:
                    active_group["category"] += ' ' + line.strip()
                continue
            q = QUESTION.match(line)
            if q:
                # A continuation line should never begin with a bare 4-6 digit token.
                finish_question(page_no)
                current = {"number": int(q.group(1)), "parts": [], "group": active_group, "page": page_no, "answer": None}
                if q.group(2):
                    part, answer = take_answer(q.group(2))
                    if part:
                        current["parts"].append(part)
                    current["answer"] = answer
                continue
            if current is not None and line.strip():
                # Skip repeated table headings or page furniture while retaining wrapped prompts.
                if not TABLE_HEADER.search(line) and not re.fullmatch(r"\s*domanda\s*", line, re.IGNORECASE):
                    part, answer = take_answer(line)
                    if part:
                        current["parts"].append(part)
                    if answer is not None:
                        current["answer"] = answer
        finish_question(page_no)

    if not questions:
        raise ValueError("No question rows were extracted. Check the PDF and pdftotext output format.")
    seen: set[int] = set()
    unique_questions: list[dict] = []
    for row in questions:
        if row["number"] in seen:
            warnings.append(f"duplicate question number {row['number']}; later occurrence omitted")
            continue
        seen.add(row["number"])
        unique_questions.append(row)
    # Keep only groups that have at least one extracted row.
    used = {q["quesito_id"] for q in unique_questions}
    return [groups[g] for g in sorted(used)], unique_questions, warnings


def main() -> int:
    from source_files import write_rows
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", type=Path, help="manually supplied official Italian PDF")
    parser.add_argument("output", type=Path, help="scratch directory for raw.txt, groups.csv, questions.csv")
    parser.add_argument("--pdftotext", help="pdftotext executable")
    args = parser.parse_args()
    exe = args.pdftotext or shutil.which("pdftotext")
    if not exe:
        parser.error("Install Poppler or pass --pdftotext /path/to/pdftotext")
    try:
        text = convert(args.pdf, exe)
        groups, questions, warnings = extract(text)
        if warnings:
            raise ValueError("Unresolved extraction warnings: " + "; ".join(warnings))
        args.output.mkdir(parents=True, exist_ok=True)
        (args.output / "raw.txt").write_text(text, encoding="utf-8")
        write_rows(args.output / "groups.csv", sorted(groups, key=lambda r: r['id']))
        write_rows(args.output / "questions.csv", sorted(questions, key=lambda r: r['number']))
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    print(f"Extracted {len(questions)} questions to {args.output}; use extract_official_banks.py for images and provenance")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
