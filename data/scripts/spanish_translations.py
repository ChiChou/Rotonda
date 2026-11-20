"""Validate/import Latin American Spanish source translations (es-419)."""
import argparse
import json

from prepare_bank_translations import text_id
from source_files import ROOT, read_rows, write_rows
from worker_models import is_worker


def sources():
    needed = {}
    for folder in sorted((ROOT / 'source/banks').iterdir()):
        if not folder.is_dir():
            continue
        for kind, column in (('questions', 'text_it'), ('groups', 'category')):
            for row in read_rows(folder / (kind + '.csv')):
                it = row[column]
                needed.setdefault(text_id(it), dict(id=text_id(it), it=it))
    return needed


def check():
    needed = sources()
    seen = {}
    for path in sorted((ROOT / 'translations/es-419').glob('*.csv')):
        rows = read_rows(path)
        for row in rows:
            key = row['id']
            if key not in needed or key in seen:
                raise ValueError(f'{path}: duplicate or unknown source ID {key}')
            if not row['text'].strip() or not is_worker(row['origin']):
                raise ValueError(f'{path}: missing translation/model provenance for {key}')
            if row['review_status'] not in ('draft', 'reviewed'):
                raise ValueError(f'{path}: invalid Spanish review status')
            seen[key] = row
        from spanish_review import validate_batch
        validate_batch(path, rows, needed)
    return needed, seen


def load_spanish(db):
    _, translated = check()
    for key, row in translated.items():
        db.execute('INSERT INTO translations VALUES(?,?,?,?,?)',
                   (key, 'es-419', row['text'], row['origin'], row['review_status']))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare', action='store_true', help='Write deterministic 100-string source task CSV files')
    parser.add_argument('--require-complete', action='store_true')
    parser.add_argument('--require-reviewed', action='store_true')
    args = parser.parse_args()
    needed, translated = check()
    if args.prepare:
        rows = sorted(needed.values(), key=lambda row: row['id'])
        for n in range(0, len(rows), 100):
            write_rows(ROOT / 'translations/tasks/es-419' / f'{n//100:03}.csv', rows[n:n+100])
    print(json.dumps(dict(language='es-419', total=len(needed), translated=len(translated),
                          missing=len(needed)-len(translated),
                          reviewed=sum(row['review_status']=='reviewed' for row in translated.values()))))
    if args.require_complete and needed.keys() != translated.keys():
        raise SystemExit(1)
    if args.require_reviewed and (needed.keys() != translated.keys() or any(row['review_status']!='reviewed' for row in translated.values())):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
