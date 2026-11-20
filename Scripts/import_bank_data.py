#!/usr/bin/env python3
"""Import the official multi-licence question banks from data into data/app/banks.db.

The monorepo's data directory builds `database/quiz.db` from the
ministry PDFs for every licence: AM, A/B, Superiori, CQC and the revisione re-examinations.
This script keeps only what the app needs, in a compact build input:

  banks           the selectable question pools, in display order
  languages       translation languages, as BCP 47 codes (en, zh-Hans, es-419…)
  chapters        each bank's own chapter list (Italian), with chapter_texts per language
  groups          each bank's official question groups, by chapter
  questions       one row per official question number (Italian), with question_texts
                  per language
  bank_questions  which questions each bank contains, in which group

Translations are rows, not columns, so a language data adds arrives without a schema
change. Every question and chapter must have every language the source declares.

Official question numbers are the ministry's own and are global: the same number has the
same Italian wording and the same answer in every bank that contains it. The import checks
this before writing, so the app can store progress once per question across licences.

Figures that the existing A/B bundle does not already carry are converted to JPEG into
Rotonda/Resources/StudyImages, named by the first 12 hex digits of their SHA-256.

Run after updating data, then rebuild the app database:

  python3 Scripts/prepare_content.py
  python3 Scripts/build_content_db.py
"""
import argparse
import json
import sqlite3
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Display order. cqc_vecchio (the superseded CQC list) is left out on purpose.
BANKS = [
    "ab", "am", "superiori", "cqc_nuovo",
    "revisione_ab", "revisione_am", "revisione_superiori", "revisione_cqc_merci", "revisione_cqc_persone",
]

SCHEMA = """
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE banks (
    id TEXT PRIMARY KEY, position INTEGER NOT NULL UNIQUE, title_it TEXT NOT NULL,
    exam_kind TEXT NOT NULL CHECK (exam_kind IN ('conseguimento', 'revisione'))
);
CREATE TABLE languages (code TEXT PRIMARY KEY, position INTEGER NOT NULL UNIQUE);
CREATE TABLE chapters (
    bank TEXT NOT NULL REFERENCES banks(id), position INTEGER NOT NULL, title_it TEXT NOT NULL,
    PRIMARY KEY (bank, position)
);
CREATE TABLE chapter_texts (
    bank TEXT NOT NULL, position INTEGER NOT NULL, language TEXT NOT NULL REFERENCES languages(code),
    title TEXT NOT NULL CHECK (length(trim(title)) > 0),
    PRIMARY KEY (bank, position, language), FOREIGN KEY (bank, position) REFERENCES chapters(bank, position)
);
CREATE TABLE groups (
    bank TEXT NOT NULL REFERENCES banks(id), id INTEGER NOT NULL, chapter INTEGER NOT NULL,
    PRIMARY KEY (bank, id), FOREIGN KEY (bank, chapter) REFERENCES chapters(bank, position)
);
CREATE TABLE questions (
    id INTEGER PRIMARY KEY, text_it TEXT NOT NULL,
    answer INTEGER NOT NULL CHECK (answer IN (0, 1)), image TEXT
);
CREATE TABLE question_texts (
    question_id INTEGER NOT NULL REFERENCES questions(id), language TEXT NOT NULL REFERENCES languages(code),
    text TEXT NOT NULL CHECK (length(trim(text)) > 0), review_status TEXT NOT NULL,
    PRIMARY KEY (question_id, language)
);
CREATE TABLE bank_questions (
    bank TEXT NOT NULL REFERENCES banks(id), question_id INTEGER NOT NULL REFERENCES questions(id),
    group_id INTEGER NOT NULL, PRIMARY KEY (bank, question_id),
    FOREIGN KEY (bank, group_id) REFERENCES groups(bank, id)
);
CREATE TABLE question_explanations (
    question_id INTEGER NOT NULL REFERENCES questions(id), language TEXT NOT NULL,
    text TEXT NOT NULL CHECK (length(trim(text)) > 0),
    PRIMARY KEY (question_id, language)
);
"""


def clean(text: str) -> str:
    # The PDFs encode some apostrophes as an inverted question mark ("dell¿ambiente").
    return text.replace("¿", "’").strip()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=ROOT / "data",
                        help="Content source directory (default: bundled data)")
    parser.add_argument("--source-db", type=Path, help="data database built from its tracked sources")
    parser.add_argument("--legacy", type=Path, default=ROOT / "data/app/quiz.db")
    parser.add_argument("--output", type=Path, default=ROOT / "data/app/banks.db")
    parser.add_argument("--images", type=Path, default=ROOT / "Rotonda/Resources/StudyImages")
    parser.add_argument("--fixes", type=Path, default=ROOT / "data/app/translation_fixes.json")
    args = parser.parse_args()
    source_db = args.source_db or args.source / "database/quiz.db"
    src = sqlite3.connect(f"file:{source_db}?mode=ro", uri=True)
    legacy = sqlite3.connect(f"file:{args.legacy}?mode=ro", uri=True)
    marks = ",".join("?" * len(BANKS))

    # Same number, same question, everywhere: required for shared progress.
    conflicts = src.execute(f"""
        SELECT official_number FROM questions WHERE bank_id IN ({marks})
        GROUP BY official_number HAVING COUNT(DISTINCT text_id) > 1 OR COUNT(DISTINCT answer) > 1
    """, BANKS).fetchall()
    if conflicts:
        raise SystemExit(f"Official numbers with different wording or answers: {conflicts[:20]}")

    # Figures: reuse the A/B bundle's image when an A/B question already shows the same asset.
    figure_of = dict(src.execute(f"""
        SELECT q.official_number, a.sha256 FROM question_assets qa
        JOIN questions q ON q.id = qa.question_id JOIN assets a ON a.id = qa.asset_id
        WHERE q.bank_id IN ({marks})
    """, BANKS).fetchall())
    asset_path = dict(src.execute("SELECT sha256, path FROM assets").fetchall())
    legacy_image = dict(legacy.execute("SELECT id, image FROM questions WHERE image IS NOT NULL").fetchall())
    image_for_asset = {}
    for number, sha in figure_of.items():
        if number in legacy_image:
            image_for_asset.setdefault(sha, legacy_image[number])
    converted = 0
    for sha in sorted(set(figure_of.values()) - set(image_for_asset)):
        name = sha[:12] + ".jpeg"
        target = args.images / name
        if not target.exists():
            subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "80",
                            str(args.source / asset_path[sha]), "--out", str(target)],
                           check=True, capture_output=True)
            converted += 1
        image_for_asset[sha] = name

    out_dir = args.output.parent
    with tempfile.TemporaryDirectory(prefix="rotonda-banks-", dir=out_dir) as folder:
        path = Path(folder) / "banks.db"
        out = sqlite3.connect(path)
        out.executescript(SCHEMA)
        titles = dict(src.execute("SELECT id, title_it FROM exam_banks").fetchall())
        kinds = dict(src.execute("SELECT id, exam_kind FROM exam_banks").fetchall())
        for position, bank in enumerate(BANKS, start=1):
            out.execute("INSERT INTO banks VALUES (?,?,?,?)", (bank, position, titles[bank], kinds[bank]))
        manifest = dict(src.execute("SELECT key, value FROM content_manifest").fetchall())
        languages = manifest["translation_languages"].split(",")
        out.executemany("INSERT INTO languages VALUES (?,?)", [(code, i) for i, code in enumerate(languages, start=1)])
        chapter_rows = src.execute(f"""
            SELECT bank_id, position, title_it, text_id FROM chapters WHERE bank_id IN ({marks}) ORDER BY bank_id, position
        """, BANKS).fetchall()
        out.executemany("INSERT INTO chapters VALUES (?,?,?)", [(b, pos, clean(it)) for b, pos, it, _ in chapter_rows])
        texts = {}  # (text_id, language) -> (text, review_status)
        for text_id, language, text, status, origin in src.execute("SELECT text_id, language, text, review_status, origin FROM translations"):
            texts[(text_id, language)] = (text, 'corrected' if origin.endswith(':correction') else status)
        missing = [(b, pos, lang) for b, pos, _, tid in chapter_rows for lang in languages if (tid, lang) not in texts]
        if missing:
            raise SystemExit(f"Chapters without a translation: {missing[:20]}")
        out.executemany("INSERT INTO chapter_texts VALUES (?,?,?,?)", [
            (b, pos, lang, clean(texts[(tid, lang)][0])) for b, pos, _, tid in chapter_rows for lang in languages])
        out.executemany("INSERT INTO groups VALUES (?,?,?)", src.execute(f"""
            SELECT g.bank_id, g.official_id, c.position FROM question_groups g
            JOIN chapters c ON c.id = g.chapter_id WHERE g.bank_id IN ({marks})
        """, BANKS).fetchall())
        rows = src.execute(f"""
            SELECT official_number, text_it, answer, MIN(text_id) FROM questions
            WHERE bank_id IN ({marks}) GROUP BY official_number ORDER BY official_number
        """, BANKS).fetchall()
        missing = [(n, lang) for n, _, _, tid in rows for lang in languages if (tid, lang) not in texts]
        if missing:
            raise SystemExit(f"Questions without a translation: {missing[:20]}")
        out.executemany("INSERT INTO questions VALUES (?,?,?,?)", [
            (n, it, answer, image_for_asset.get(figure_of.get(n))) for n, it, answer, _ in rows])
        explanation_rows = {}
        for number, language, value in src.execute(f"""
            SELECT q.official_number, e.language, e.text FROM question_explanations e
            JOIN questions q ON q.id = e.question_id WHERE q.bank_id IN ({marks})
            ORDER BY q.bank_id
        """, BANKS):
            key = (number, language)
            if key in explanation_rows and explanation_rows[key] != value:
                raise ValueError(f"Conflicting explanations for shared question {key}")
            explanation_rows[key] = value
        out.executemany("INSERT INTO question_explanations VALUES (?,?,?)",
                        [(n, lang, value) for (n, lang), value in sorted(explanation_rows.items())])
        question_texts = {(n, lang): list(texts[(tid, lang)]) for n, _, _, tid in rows for lang in languages}
        # Reviewed corrections not yet upstream (data/app/translation_fixes.json).
        fixes = json.loads(args.fixes.read_text()) if args.fixes.exists() else {}
        for lang, by_question in fixes.items():
            if lang.startswith("_"):
                continue
            for number, fix in by_question.items():
                current = question_texts.get((int(number), lang))
                if current is None or current[0] != fix["from"]:
                    raise SystemExit(f"Translation fix {lang} {number} no longer matches the source; update or remove it")
                current[0], current[1] = fix["to"], "corrected"
        out.executemany("INSERT INTO question_texts VALUES (?,?,?,?)",
                        [(n, lang, text, status) for (n, lang), (text, status) in question_texts.items()])
        out.executemany("INSERT INTO bank_questions VALUES (?,?,?)", src.execute(f"""
            SELECT q.bank_id, q.official_number, g.official_id FROM questions q
            JOIN question_groups g ON g.id = q.group_id WHERE q.bank_id IN ({marks})
        """, BANKS).fetchall())
        out.executemany("INSERT INTO meta VALUES (?,?)", [
            ("content_version", manifest["content_version"]),
            ("content_hash", manifest["content_hash"]),
            ("retrieved_on", manifest["retrieved_on"]),
        ])
        out.commit()
        problems = out.execute("PRAGMA foreign_key_check").fetchall()
        if problems:
            raise SystemExit(f"Foreign key problems: {problems[:10]}")
        out.execute("VACUUM")
        out.close()
        path.replace(args.output)
    print(f"{len(rows)} questions in {len(BANKS)} banks, languages {', '.join(languages)}; {converted} new figures converted")


if __name__ == "__main__":
    main()
