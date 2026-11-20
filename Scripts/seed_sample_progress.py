#!/usr/bin/env python3
"""Fill an empty Rotonda progress store with realistic sample study history.

For demos, screenshots and trying the progress screens without studying for weeks. It writes
straight into the SwiftData store (Progress.store, a Core Data SQLite file) using the
`ProgressSchemaV1` models, with real question, word and fact ids from the bundled content.

What it adds:
  - 15 study days ending today, the last 12 in a row (a 12-day streak), with ~1,000 logged answers
  - 1,000 answered statements across chapters 1-5 in book order, about 70 open mistakes
  - 150 word cards and 30 fact cards, mostly learned, about 10% due now
  - four mock exams improving from 6 to 1 errors (the last two pass), with their answers
  - 6 saved questions, 5 saved words, and Learn & quiz positions matching the answers

Usage:
  1. Launch the app once so it creates an empty store, then quit it.
  2. Copy the store off, seed it, and copy it back (the app must not be running):

     Simulator:
       C=$(xcrun simctl get_app_container <simulator> me.chichou.rotonda data)
       python3 Scripts/seed_sample_progress.py "$C/Library/Application Support/Rotonda/Progress.store"
       (remove Progress.store-wal and Progress.store-shm next to it if present)

     Device (Xcode's devicectl):
       xcrun devicectl device copy from --device <device> --domain-type appDataContainer \\
         --domain-identifier me.chichou.rotonda \\
         --source "Library/Application Support/Rotonda/Progress.store" --destination /tmp/seed/Rotonda/Progress.store
       python3 Scripts/seed_sample_progress.py /tmp/seed/Rotonda/Progress.store
       xcrun devicectl device copy to --device <device> --domain-type appDataContainer \\
         --domain-identifier me.chichou.rotonda --source /tmp/seed/Rotonda \\
         --destination "Library/Application Support/Rotonda" --remove-existing-content true

     Copying the whole folder with --remove-existing-content also clears stale -wal/-shm files.

"Reset all progress" in the app's settings removes the sample data again.
"""

import argparse
import datetime as dt
import random
import sqlite3
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORE_DATA_EPOCH = 978307200  # Core Data dates count seconds from 2001-01-01.
# StudySchedule.intervals: 10 minutes, then 1, 3, 7, 16, 35 and 90 days.
INTERVALS = [600, 86400, 3 * 86400, 7 * 86400, 16 * 86400, 35 * 86400, 90 * 86400]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("store", type=Path, help="path to Progress.store")
    parser.add_argument("--content", type=Path, default=ROOT / "Rotonda/Resources/patente.db")
    parser.add_argument("--seed", type=int, default=7, help="random seed, for repeatable data")
    parser.add_argument("--force", action="store_true", help="seed even if the store already has progress")
    args = parser.parse_args()
    random.seed(args.seed)

    db = sqlite3.connect(args.store)
    content = sqlite3.connect(f"file:{args.content}?mode=ro", uri=True)
    entities = {name: entity for entity, name in db.execute("SELECT Z_ENT, Z_NAME FROM Z_PRIMARYKEY")}
    if "StoredQuestionStat" not in entities:
        sys.exit("Not a Rotonda progress store: launch the app once so it creates one.")
    tables = ["ZSTOREDQUESTIONSTAT", "ZSTOREDCARD", "ZSTOREDACTIVITY", "ZSTOREDEXAM"]
    existing = sum(db.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0] for table in tables)
    if existing and not args.force:
        sys.exit("The store already has progress. Reset it in the app first, or pass --force.")

    keys = {name: db.execute("SELECT Z_MAX FROM Z_PRIMARYKEY WHERE Z_NAME = ?", (name,)).fetchone()[0] for name in entities}
    start = dict(keys)
    now = time.time()
    midnight = dt.datetime.combine(dt.date.today(), dt.time()).timestamp()
    study_days = list(range(0, 12)) + [14, 15, 18]

    def stored(seconds: float) -> float:
        return seconds - CORE_DATA_EPOCH

    def insert(table: str, entity: str, values: dict) -> int:
        keys[entity] += 1
        columns = ["Z_PK", "Z_ENT", "Z_OPT", *values]
        db.execute(f"INSERT INTO {table} ({', '.join(columns)}) VALUES ({', '.join('?' * len(columns))})",
                   [keys[entity], entities[entity], 1, *values.values()])
        return keys[entity]

    def moment(day: int) -> float:
        """A time on a study day `day` days ago, never in the future."""
        return min(midnight - day * 86400 + random.uniform(8, 22) * 3600, now - random.uniform(60, 3600))

    def last_seen(interval: float, due_now: bool) -> float:
        """When an item was last answered so its review falls in the future, or is due now."""
        if due_now:
            return now - interval - random.uniform(600, 6 * 3600)
        return now - random.uniform(0.05, 0.85) * min(interval, 18 * 86400)

    # Statements, in book order: earlier chapters further along.
    answered, reading = [], {}
    for chapter, count in {1: 420, 2: 300, 3: 180, 4: 70, 5: 30}.items():
        rows = content.execute("SELECT id, position FROM questions WHERE chapter_id = ? ORDER BY position LIMIT ?",
                               (chapter, count)).fetchall()
        reading[chapter] = rows[-1][1]
        answered += [(question, chapter) for question, _ in rows]
    for question, chapter in answered:
        wrong = 1 if random.random() < 0.09 else 0
        last_correct = 1 if (not wrong or random.random() < 0.55) else 0
        streak = 0 if not last_correct else (random.choice([1, 2]) if wrong else random.randint(1, 3))
        attempts = max(random.choice([1, 1, 2, 2, 3]), wrong + last_correct)
        box = min(max(streak, 1), len(INTERVALS) - 1) if last_correct else 0
        insert("ZSTOREDQUESTIONSTAT", "StoredQuestionStat", dict(
            ZATTEMPTS=attempts, ZCHAPTERID=chapter, ZCORRECT=attempts - wrong, ZLASTCORRECT=last_correct,
            ZQUESTIONID=question, ZSTREAK=streak, ZWRONG=wrong,
            ZLASTAT=stored(last_seen(INTERVALS[box], random.random() < 0.06))))

    # Word and fact memory cards.
    words = [row[0] for row in content.execute("SELECT id FROM words ORDER BY rank LIMIT 150")]
    facts = [row[0] for row in content.execute("SELECT id FROM facts ORDER BY position LIMIT 30")]
    for card in [f"w:{word}" for word in words] + [f"f:{fact}" for fact in facts]:
        box = random.choices([0, 1, 2, 3, 4], weights=[5, 12, 33, 32, 18])[0]
        last = last_seen(INTERVALS[box], random.random() < 0.1)
        insert("ZSTOREDCARD", "StoredCard", dict(
            ZBOX=box, ZLAPSES=random.choice([0, 0, 0, 1]), ZREPS=box + random.randint(1, 3),
            ZDUE=stored(last + INTERVALS[box]), ZLASTAT=stored(last), ZCARDID=card))

    # The answer log behind the streak and the week chart.
    for day in study_days:
        for _ in range(random.randint(25, 70)):
            insert("ZSTOREDACTIVITY", "StoredActivity", dict(
                ZCORRECT=int(random.random() < 0.86), ZAT=stored(moment(day)),
                ZITEM=str(random.choice(answered)[0]), ZKIND="question"))
        for _ in range(random.randint(8, 30)):
            insert("ZSTOREDACTIVITY", "StoredActivity", dict(
                ZCORRECT=int(random.random() < 0.8), ZAT=stored(moment(day)),
                ZITEM=f"w:{random.choice(words)}", ZKIND="card"))

    # Mock exams, improving over the fortnight.
    pool = content.execute("SELECT id, answer FROM questions WHERE chapter_id <= 10").fetchall()
    for exam_id, (day, errors, seconds) in enumerate([(9, 6, 1140), (6, 4, 1010), (3, 2, 905), (1, 1, 812)], start=1):
        statements = random.sample(pool, 30)
        wrong_positions = set(random.sample(range(30), errors))
        exam = insert("ZSTOREDEXAM", "StoredExam", dict(
            ZCORRECT=30 - errors, ZDURATION=seconds, ZERRORS=errors, ZEXAMID=exam_id, ZAT=stored(moment(day))))
        for position, (question, answer) in enumerate(statements):
            insert("ZSTOREDEXAMANSWER", "StoredExamAnswer", dict(
                ZANSWER=(1 - answer) if position in wrong_positions else answer,
                ZPOSITION=position, ZQUESTIONID=question, ZEXAM=exam))

    for question, _ in random.sample(answered, 6):
        insert("ZSTOREDBOOKMARK", "StoredBookmark", dict(ZQUESTIONID=question, ZAT=stored(moment(random.choice(study_days)))))
    for word in random.sample(words[:60], 5):
        insert("ZSTOREDSAVEDWORD", "StoredSavedWord", dict(ZWORDID=word, ZAT=stored(moment(random.choice(study_days)))))
    for chapter, position in reading.items():
        insert("ZSTOREDREADINGPOSITION", "StoredReadingPosition", dict(
            ZKEY=f"learnquiz-{chapter}", ZPOSITION=position, ZAT=stored(moment(0))))

    # Keep SwiftData's primary key counters ahead of the new rows.
    for name, value in keys.items():
        db.execute("UPDATE Z_PRIMARYKEY SET Z_MAX = ? WHERE Z_NAME = ?", (value, name))
    db.commit()
    added = {name: value - start[name] for name, value in keys.items() if value > start[name]}
    print("Seeded:", ", ".join(f"{name} {count}" for name, count in added.items()))


if __name__ == "__main__":
    main()
