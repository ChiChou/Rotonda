"""Seal Spanish batches only after a reviewer has compared every source/target row.

This records review evidence; it does not translate or perform semantic review.
"""
from datetime import date
import csv
import hashlib
import io
import json
from pathlib import Path

from source_files import ROOT, read_rows, write_rows
from worker_models import DEFAULT, is_worker

BASELINE = Path('/tmp/patentedata-spanish-review-baseline')


def file_hash(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def source_hash(rows, needed):
    data = [[row['id'], needed[row['id']]['it']] for row in rows]
    return hashlib.sha256(json.dumps(data, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()


def baseline_hash(rows, corrections):
    """Reconstruct the draft file so correction history remains verifiable."""
    before = {row['id']: row['before'] for row in corrections}
    restored = [dict(row, text=before.get(row['id'], row['text']), review_status='draft') for row in rows]
    stream = io.StringIO(newline='')
    writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator='\n')
    writer.writeheader()
    writer.writerows(restored)
    return hashlib.sha256(stream.getvalue().encode('utf-8')).hexdigest()


def validate_batch(path, rows, needed):
    reviewed = sum(row['review_status'] == 'reviewed' for row in rows)
    report_path = ROOT / 'reviews/spanish-review' / (path.stem + '.json')
    if not reviewed and not report_path.exists():
        return None
    if not report_path.exists():
        raise ValueError(f'{path}: reviewed Spanish requires batch review evidence')
    report = json.loads(report_path.read_text(encoding='utf-8'))
    if report['reviewed_file_sha256'] != file_hash(path):
        raise ValueError(f'{path}: Spanish wording changed after review')
    if report['source_sha256'] != source_hash(rows, needed):
        raise ValueError(f'{path}: Italian source changed after Spanish review')
    if report['rows'] != len(rows) or reviewed != len(rows):
        raise ValueError(f'{path}: review must cover every row in the batch')
    if not is_worker(report.get('reviewer_model')) or not report['reviewer_agent']:
        raise ValueError(f'{path}: missing reviewer provenance')
    date.fromisoformat(report['reviewed_on'])
    baseline = json.loads((ROOT / 'reviews/spanish-review/baseline.json').read_text(encoding='utf-8'))
    if report['baseline_sha256'] != baseline['files'][path.name]:
        raise ValueError(f'{path}: review baseline differs from recorded manifest')
    if baseline_hash(rows, report['corrections']) != report['baseline_sha256']:
        raise ValueError(f'{path}: correction history does not reconstruct the original draft')
    ids = {row['id'] for row in rows}
    correction_ids = [row['id'] for row in report['corrections']]
    if len(correction_ids) != len(set(correction_ids)):
        raise ValueError(f'{path}: duplicate correction evidence')
    for correction in report['corrections']:
        if correction['id'] not in ids or not correction['reason'].strip():
            raise ValueError(f'{path}: invalid correction evidence')
        if correction['after'] != next(row['text'] for row in rows if row['id'] == correction['id']):
            raise ValueError(f'{path}: correction differs from reviewed wording')
    return report


def record_review(batch, reviewer_agent, corrections=None, reviewer_model=DEFAULT):
    """Call only after reading/comparing every Italian and Spanish row in a batch.

    Edit text in the CSV first; pass {id: reason} for every changed translation.
    Unresolved batches must remain draft and must not be sealed.
    """
    from spanish_translations import sources
    name = f'{int(batch):03d}.csv'
    path = ROOT / 'translations/es-419' / name
    before = read_rows(BASELINE / name)
    rows = read_rows(path)
    if [row['id'] for row in before] != [row['id'] for row in rows]:
        raise ValueError(f'{name}: review changed batch membership/order')
    corrections = corrections or {}
    changed = []
    for old, row in zip(before, rows):
        if row['origin'] != old['origin'] or not is_worker(row['origin']):
            raise ValueError(f'{name}: generation provenance changed')
        if row['text'] != old['text']:
            if not corrections.get(row['id'], '').strip():
                raise ValueError(f"{name}: reason missing for changed text {row['id']}")
            changed.append(dict(id=row['id'], before=old['text'], after=row['text'], reason=corrections[row['id']]))
        row['review_status'] = 'reviewed'
    if set(corrections) != {row['id'] for row in changed}:
        raise ValueError(f'{name}: reasons must match exactly the changed rows')
    baseline = json.loads((ROOT / 'reviews/spanish-review/baseline.json').read_text(encoding='utf-8'))
    if file_hash(BASELINE / name) != baseline['files'][name]:
        raise ValueError(f'{name}: baseline was modified')
    write_rows(path, rows)
    report = dict(batch=path.stem, language='es-419', reviewer_model=reviewer_model,
                  reviewer_agent=reviewer_agent, reviewed_on=date.today().isoformat(),
                  method='Every Italian source and Spanish translation read and semantically compared; false assertions retained.',
                  rows=len(rows), baseline_sha256=baseline['files'][name],
                  reviewed_file_sha256=file_hash(path), source_sha256=source_hash(rows, sources()),
                  corrections=changed)
    report_path = ROOT / 'reviews/spanish-review' / (path.stem + '.json')
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    validate_batch(path, rows, sources())
    return dict(batch=path.stem, reviewed=len(rows), corrected=len(changed))
