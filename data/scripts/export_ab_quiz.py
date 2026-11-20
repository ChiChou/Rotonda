#!/usr/bin/env python3
"""Export the legacy A/B quiz database to deterministic JSON and CSV files."""

from __future__ import annotations

import csv
import json
import sqlite3
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DATABASE = ROOT / "database" / "ab" / "quiz.db"
OUTPUT = ROOT / "exports" / "ab"


def fetch_questions(connection: sqlite3.Connection) -> list[dict[str, object]]:
    connection.row_factory = sqlite3.Row
    rows = connection.execute(
        """
        SELECT
            q.id,
            q.group_id,
            c.id AS chapter_id,
            c.position AS chapter_position,
            c.title_it AS chapter_it,
            c.title_en AS chapter_en,
            c.title_zh AS chapter_zh,
            q.text_it,
            q.text_en,
            q.text_zh,
            q.answer,
            q.image AS image
        FROM questions AS q
        JOIN question_groups AS g ON g.id = q.group_id
        JOIN chapters AS c ON c.id = g.chapter_id
        ORDER BY q.id
        """
    ).fetchall()

    questions: list[dict[str, object]] = []
    for row in rows:
        item = dict(row)
        item["answer"] = bool(item["answer"])
        item["answer_text"] = "VERO" if item["answer"] else "FALSO"
        questions.append(item)
    return questions


def write_json(path: Path, rows: list[dict[str, object]]) -> None:
    path.write_text(
        json.dumps(rows, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    if not DATABASE.is_file():
        raise SystemExit(f"Missing legacy A/B database: {DATABASE}")

    OUTPUT.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(f"file:{DATABASE}?mode=ro", uri=True) as connection:
        questions = fetch_questions(connection)

    if len(questions) != 7_106:
        raise SystemExit(f"Unexpected question count: {len(questions)}")

    write_json(OUTPUT / "questions.json", questions)
    write_csv(OUTPUT / "questions.csv", questions)
    print(f"Exported {len(questions)} questions to {OUTPUT}")


if __name__ == "__main__":
    main()
