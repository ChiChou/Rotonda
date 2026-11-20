#!/usr/bin/env python3
"""Build the archived A/B application content bundle.

This normalizes the PDF extraction, merges every translation JSONL batch,
adds the per-language explanations from explanations/ab, imports curated
teaching facts, validates all references, and copies only referenced images. User data is deliberately not part of this database.

Usage:
    python3 scripts/build_ab_database.py
    python3 scripts/build_ab_database.py --output /path/to/app/Resources
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sqlite3
import sys
from datetime import UTC, datetime
from pathlib import Path
import unicodedata

ROOT = Path(__file__).resolve().parent.parent

# Remove closed-class grammar words, but retain exam-critical logic such as
# non, mai, sempre, solo, senza, ogni, tutti and qualsiasi.
DICTIONARY_STOP_WORDS = frozenset(
    {
        "a", "ad", "ai", "al", "all", "alla", "alle", "allo", "con", "da", "dai",
        "dal", "dall", "dalla", "dalle", "dallo", "dei", "del", "dell", "della", "delle",
        "dello", "di", "e", "ed", "gli", "i", "il", "in", "la", "le",
        "lo", "nei", "nel", "nell", "nella", "nelle", "nello", "o", "od", "per",
        "quest", "su", "sui", "sul", "sull", "sulla", "sulle", "sullo", "tra", "fra",
        "un", "una", "uno",
    }
)
WORD_PATTERN = re.compile(r"[^\W\d_]+", re.UNICODE)


def dictionary_sort_key(word: str) -> str:
    return "".join(
        character
        for character in unicodedata.normalize("NFKD", word)
        if not unicodedata.combining(character)
    ).casefold()


def dictionary_first_letter(word: str) -> str:
    initial = dictionary_sort_key(word)[:1].upper()
    return initial if "A" <= initial <= "Z" else "#"


def build_dictionary_index(connection: sqlite3.Connection) -> int:
    connection.row_factory = sqlite3.Row
    entries: dict[str, tuple[str, str, str, int]] = {}
    for row in connection.execute("SELECT id, text_it FROM questions ORDER BY id"):
        for match in WORD_PATTERN.finditer(str(row["text_it"])):
            word = match.group(0).lower()
            if len(word) <= 1 or word in DICTIONARY_STOP_WORDS or word in entries:
                continue
            entries[word] = (
                word,
                dictionary_first_letter(word),
                dictionary_sort_key(word),
                int(row["id"]),
            )

    connection.executemany(
        "INSERT INTO dictionary_entries VALUES (?, ?, ?, ?)",
        sorted(entries.values(), key=lambda entry: (entry[1], entry[2], entry[0])),
    )
    return len(entries)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, help='Optional generated compatibility input')
    parser.add_argument("--translations", type=Path, help='Optional translation import override')
    parser.add_argument("--facts", type=Path, default=ROOT / "facts" / "ab")
    parser.add_argument("--explanations", type=Path, default=ROOT / "explanations" / "ab")
    parser.add_argument("--images", type=Path, default=ROOT / "assets" / "ab")
    parser.add_argument(
        "--output", type=Path, default=ROOT / "database" / "ab"
    )
    parser.add_argument("--version", default=datetime.now(UTC).strftime("%Y.%m.%d"))
    return parser.parse_args()


# File name in explanations/ab -> column suffix in the questions table.
EXPLANATION_LANGUAGES = {"it": "it", "en": "en", "zh-Hans": "zh", "es-419": "es"}


def load_explanations(directory: Path, question_ids: set[int]) -> dict[str, dict[int, str]]:
    """One JSON Lines file per language, one {"number", "text"} record per question."""
    explanations: dict[str, dict[int, str]] = {}
    for language in EXPLANATION_LANGUAGES:
        path = directory / f"{language}.jsonl"
        texts: dict[int, str] = {}
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            record = json.loads(line)
            number, text = int(record["number"]), record["text"].strip()
            if number in texts:
                raise ValueError(f"{path.name}:{line_number}: duplicate question {number}")
            if not text:
                raise ValueError(f"{path.name}:{line_number}: empty explanation for {number}")
            texts[number] = text
        missing, unknown = sorted(question_ids - texts.keys()), sorted(texts.keys() - question_ids)
        if missing or unknown:
            raise ValueError(f"{path.name}: missing={missing[:10]}, unknown={unknown[:10]}")
        explanations[language] = texts
    return explanations


def load_translations(directory: Path | None) -> tuple[dict[int, tuple[str, str]], dict[int, tuple[str, str]]]:
    if directory is None:
        from content_workflow import translations, text_id
        from source_files import read_rows
        texts = translations()
        compatibility = json.loads((ROOT / 'app/ab_compatibility.json').read_text())
        def localized(rows, key, field, overrides):
            return {r[key]: tuple(overrides.get(str(r[key]),
                [texts[lang][text_id(r[field])] for lang in ('en','zh-Hans')])) for r in rows}
        folder = ROOT / 'source/banks/ab'
        return (localized(read_rows(folder/'groups.csv'),'id','category',compatibility['category_text_overrides']),
                localized(read_rows(folder/'questions.csv'),'number','text_it',compatibility['question_text_overrides']))
    categories: dict[int, tuple[str, str]] = {}
    questions: dict[int, tuple[str, str]] = {}
    duplicate_keys: list[str] = []

    files = sorted(directory.glob("*.jsonl"))
    if not files:
        raise ValueError(f"No translation JSONL files found in {directory}")

    for path in files:
        for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if not raw.strip():
                continue
            try:
                row = json.loads(raw)
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path.name}:{line_number}: {exc}") from exc

            english = str(row.get("en", "")).strip()
            chinese = str(row.get("zh", "")).strip()
            if not english or not chinese:
                raise ValueError(f"{path.name}:{line_number}: empty en/zh translation")

            row_type = row.get("type")
            if row_type == "question":
                key = int(row["number"])
                target = questions
            elif row_type == "category":
                key = int(row["id"])
                target = categories
            else:
                raise ValueError(f"{path.name}:{line_number}: unknown type {row_type!r}")

            value = (english, chinese)
            if key in target and target[key] != value:
                duplicate_keys.append(f"{row_type}:{key}")
            target[key] = value

    if duplicate_keys:
        raise ValueError(f"Conflicting duplicate translations: {duplicate_keys[:10]}")
    return categories, questions


def create_schema(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        PRAGMA foreign_keys = ON;
        PRAGMA journal_mode = DELETE;
        CREATE TABLE chapters (
            id INTEGER PRIMARY KEY,
            position INTEGER NOT NULL UNIQUE,
            title_it TEXT NOT NULL,
            title_en TEXT NOT NULL,
            title_zh TEXT NOT NULL
        );
        CREATE TABLE question_groups (
            id INTEGER PRIMARY KEY,
            chapter_id INTEGER NOT NULL REFERENCES chapters(id),
            image TEXT
        );
        CREATE TABLE questions (
            id INTEGER PRIMARY KEY,
            group_id INTEGER NOT NULL REFERENCES question_groups(id),
            text_it TEXT NOT NULL,
            text_en TEXT NOT NULL,
            text_zh TEXT NOT NULL,
            answer INTEGER NOT NULL CHECK (answer IN (0, 1)),
            image TEXT,
            explanation_it TEXT NOT NULL,
            explanation_en TEXT NOT NULL,
            explanation_zh TEXT NOT NULL,
            explanation_es TEXT NOT NULL
        );
        CREATE TABLE dictionary_entries (
            word TEXT PRIMARY KEY,
            first_letter TEXT NOT NULL CHECK (length(first_letter) = 1),
            sort_key TEXT NOT NULL,
            sample_question_id INTEGER NOT NULL REFERENCES questions(id)
        );
        CREATE TABLE study_facts (
            id TEXT PRIMARY KEY,
            deck TEXT NOT NULL,
            position INTEGER NOT NULL,
            topic TEXT NOT NULL,
            fact_en TEXT NOT NULL,
            fact_zh TEXT NOT NULL,
            fact_it TEXT NOT NULL,
            value TEXT NOT NULL DEFAULT '',
            note TEXT
        );
        CREATE TABLE study_fact_sources (
            fact_id TEXT NOT NULL REFERENCES study_facts(id),
            question_id INTEGER NOT NULL REFERENCES questions(id),
            PRIMARY KEY (fact_id, question_id)
        );
        CREATE TABLE content_manifest (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        CREATE INDEX idx_groups_chapter ON question_groups(chapter_id);
        CREATE INDEX idx_questions_group ON questions(group_id);
        CREATE INDEX idx_dictionary_letter_sort
            ON dictionary_entries(first_letter, sort_key, word);
        CREATE INDEX idx_fact_question ON study_fact_sources(question_id);
        """
    )


def build_database(args: argparse.Namespace, database_path: Path) -> tuple[set[str], dict[str, int]]:
    category_translations, question_translations = load_translations(args.translations)
    source = sqlite3.connect(f"file:{args.base}?mode=ro", uri=True)
    source.row_factory = sqlite3.Row

    source_groups = list(source.execute(
        "SELECT id, category, image FROM quesiti ORDER BY id"
    ))
    source_questions = list(source.execute(
        "SELECT number, quesito_id, text_it, answer, image FROM questions ORDER BY number"
    ))
    if not source_groups or not source_questions:
        raise ValueError("Base extraction database is empty")

    group_ids = {int(row["id"]) for row in source_groups}
    question_ids = {int(row["number"]) for row in source_questions}
    missing_group_translations = sorted(group_ids - category_translations.keys())
    missing_question_translations = sorted(question_ids - question_translations.keys())
    extra_questions = sorted(question_translations.keys() - question_ids)
    if missing_group_translations or missing_question_translations or extra_questions:
        raise ValueError(
            "Translation coverage mismatch: "
            f"missing categories={missing_group_translations[:10]}, "
            f"missing questions={missing_question_translations[:10]}, "
            f"unknown questions={extra_questions[:10]}"
        )

    explanations = load_explanations(args.explanations, question_ids)

    if database_path.exists():
        database_path.unlink()
    destination = sqlite3.connect(database_path)
    create_schema(destination)

    category_order: dict[str, int] = {}
    category_first_group: dict[str, int] = {}
    for row in source_groups:
        category = row["category"]
        if category not in category_order:
            category_order[category] = len(category_order) + 1
            category_first_group[category] = int(row["id"])

    for category, position in category_order.items():
        representative_id = category_first_group[category]
        english, chinese = category_translations[representative_id]
        destination.execute(
            "INSERT INTO chapters VALUES (?, ?, ?, ?, ?)",
            (position, position, category, english, chinese),
        )

    referenced_images: set[str] = set()
    for row in source_groups:
        image = row["image"]
        if image:
            referenced_images.add(image)
        destination.execute(
            "INSERT INTO question_groups VALUES (?, ?, ?)",
            (int(row["id"]), category_order[row["category"]], image),
        )

    content_hasher = hashlib.sha256()
    for row in source_questions:
        number = int(row["number"])
        english, chinese = question_translations[number]
        image = row["image"]
        if image:
            referenced_images.add(image)
        values = (
            number, int(row["quesito_id"]), row["text_it"], english,
            chinese, int(row["answer"]), image,
            *(explanations[language][number] for language in EXPLANATION_LANGUAGES),
        )
        destination.execute("INSERT INTO questions VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", values)
        content_hasher.update(json.dumps(values, ensure_ascii=False).encode("utf-8"))

    dictionary_count = build_dictionary_index(destination)

    fact_count = 0
    for fact_path in sorted(args.facts.glob("*.json")):
        deck = fact_path.stem
        cards = json.loads(fact_path.read_text(encoding="utf-8"))
        for position, card in enumerate(cards):
            fact_id = f"{deck}:{position}"
            destination.execute(
                "INSERT INTO study_facts VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    fact_id, deck, position, card["topic"], card["fact_en"],
                    card["fact_zh"], card["fact_it"], card.get("value", ""),
                    card.get("note"),
                ),
            )
            for question_id in card.get("src", []):
                if question_id not in question_ids:
                    raise ValueError(f"{fact_path.name}: unknown source question {question_id}")
                destination.execute(
                    "INSERT INTO study_fact_sources VALUES (?, ?)", (fact_id, question_id)
                )
            fact_count += 1

    manifest = {
        "content_version": args.version,
        "schema_version": "3",
        "content_hash": content_hasher.hexdigest()[:16],
        "question_count": str(len(source_questions)),
        "group_count": str(len(source_groups)),
        "chapter_count": str(len(category_order)),
        "fact_count": str(fact_count),
        "dictionary_count": str(dictionary_count),
        "image_count": str(len(referenced_images)),
        "languages": "it,en,zh-Hans,es-419",
        "source": args.base.name,
    }
    destination.executemany("INSERT INTO content_manifest VALUES (?, ?)", manifest.items())
    destination.execute("PRAGMA user_version = 3")
    destination.commit()
    destination.execute("VACUUM")

    checks = {
        "chapters": destination.execute("SELECT COUNT(*) FROM chapters").fetchone()[0],
        "groups": destination.execute("SELECT COUNT(*) FROM question_groups").fetchone()[0],
        "questions": destination.execute("SELECT COUNT(*) FROM questions").fetchone()[0],
        "dictionary": destination.execute("SELECT COUNT(*) FROM dictionary_entries").fetchone()[0],
        "facts": destination.execute("SELECT COUNT(*) FROM study_facts").fetchone()[0],
    }
    destination.close()
    source.close()
    return referenced_images, checks


def copy_images(referenced: set[str], source: Path, destination: Path) -> None:
    missing = sorted(name for name in referenced if not (source / name).is_file())
    if missing:
        raise ValueError(f"Missing referenced images: {missing[:10]}")
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    for name in sorted(referenced):
        shutil.copy2(source / name, destination / name)


def main() -> int:
    args = parse_args()
    from source_files import restore_ab
    args.output.mkdir(parents=True, exist_ok=True)
    if args.base is None:
        args.base = args.output / 'ab-input.db'
        restore_ab(args.base)
    for required in (args.base, args.facts, args.images):
        if not required.exists():
            raise FileNotFoundError(required)

    args.output.mkdir(parents=True, exist_ok=True)
    final_database = args.output / "quiz.db"
    temporary_database = args.output / "quiz.db.building"
    if temporary_database.exists():
        temporary_database.unlink()

    try:
        referenced, checks = build_database(args, temporary_database)
        copy_images(referenced, args.images, args.output / "StudyImages")
        temporary_database.replace(final_database)
    except Exception:
        if temporary_database.exists():
            temporary_database.unlink()
        raise

    size_mb = final_database.stat().st_size / 1_000_000
    print(f"Built {final_database} ({size_mb:.2f} MB)")
    print(
        f"Validated {checks['chapters']} chapters, {checks['groups']} groups, "
        f"{checks['questions']} questions, {checks['dictionary']} useful dictionary words, "
        f"{checks['facts']} facts, "
        f"{len(referenced)} referenced images"
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
