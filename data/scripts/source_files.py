"""Deterministic CSV records and content-addressed original image blobs."""
import csv
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def image_suffix(suffix):
    return '.jpg' if suffix.lower() == '.jpeg' else suffix.lower()


def read_rows(path):
    path = Path(path)
    with path.open(encoding='utf-8', newline='') as stream:
        rows = list(csv.DictReader(stream))
    for row in rows:
        if 'category' in row:
            row['id'] = int(row['id'])
        for key in ('source_order', 'page', 'number', 'quesito_id', 'answer', 'question_number'):
            if key in row:
                if row[key] == '':
                    del row[key]
                else:
                    row[key] = int(row[key])
        for key in ('top', 'bottom', 'x0', 'x1'):
            if key in row:
                row[key] = float(row[key])
    return rows


def write_rows(path, rows):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = list(rows)
    fields = list(dict.fromkeys(key for row in rows for key in row))
    with path.open('w', encoding='utf-8', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)


def store_image(data, suffix):
    """One original blob per unique image, keyed by its bytes."""
    digest = hashlib.sha256(data).hexdigest()
    path = ROOT / 'source/images' / (digest + image_suffix(suffix))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return digest


def restore_image(path, digest):
    path = Path(path)
    source = ROOT / 'source/images' / (digest + image_suffix(path.suffix))
    data = source.read_bytes()
    if hashlib.sha256(data).hexdigest() != digest:
        raise ValueError(f'Image checksum mismatch: {source}')
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists() or path.read_bytes() != data:
        path.write_bytes(data)
    return data


def restore_ab(target):
    """Generate the application adapter from canonical official A/B text sources."""
    import json
    import sqlite3
    import tempfile
    folder = ROOT / 'source/banks/ab'
    compatibility = json.loads((ROOT / 'app/ab_compatibility.json').read_text())
    for row in compatibility['assets']:
        restore_image(ROOT / row['path'], row['sha256'])
    target = Path(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='ab-source-', dir=target.parent) as temporary:
        staged = Path(temporary) / 'input.db'
        with sqlite3.connect(staged) as db:
            db.executescript("""
                CREATE TABLE quesiti (id INTEGER PRIMARY KEY, category TEXT NOT NULL,
                    image TEXT, page INTEGER NOT NULL);
                CREATE TABLE questions (number INTEGER PRIMARY KEY,
                    quesito_id INTEGER NOT NULL REFERENCES quesiti(id), text_it TEXT NOT NULL,
                    answer INTEGER NOT NULL CHECK (answer IN (0, 1)), image TEXT,
                    page INTEGER NOT NULL);
            """)
            for row in read_rows(folder / 'groups.csv'):
                db.execute('INSERT INTO quesiti VALUES (?, ?, ?, ?)',
                    (row['id'], compatibility.get('category_it_overrides',{}).get(str(row['id']),row['category']),
                     compatibility['group_images'].get(str(row['id'])), row['page']))
            for row in read_rows(folder / 'questions.csv'):
                db.execute('INSERT INTO questions VALUES (?, ?, ?, ?, ?, ?)',
                    (row['number'], row['quesito_id'], row['text_it'], row['answer'],
                     compatibility['question_images'].get(str(row['number'])), row['page']))
        staged.replace(target)
