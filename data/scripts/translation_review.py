#!/usr/bin/env python3
"""Bind completed semantic translation reviews to the exact verified wording.

Review agents call record_review only after reading every Italian/English/Chinese
row in their batch. This helper records evidence; it does not perform a semantic
review or decide whether translations are correct.
"""
import hashlib
import json
from pathlib import Path
from datetime import date

from worker_models import DEFAULT, is_worker

ROOT = Path(__file__).resolve().parents[1]
REVIEW_DATE = '2026-11-14'
BASELINE = Path('/tmp/patentedata-review-baseline')

def reviewed_content_hash(row):
    value={key:row[key] for key in ('id','it','en','zh')}
    return hashlib.sha256(json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode('utf-8')).hexdigest()

def validate_review(row):
    if row.get('review_status') != 'reviewed':
        return False
    if not row.get('reviewer') or not row.get('reviewed_on') or not row.get('reviewer_agent'):
        raise ValueError(f"{row['id']}: reviewed translation lacks reviewer provenance")
    date.fromisoformat(row['reviewed_on'])
    if row.get('reviewed_content_sha256') != reviewed_content_hash(row):
        raise ValueError(f"{row['id']}: translation changed after semantic review")
    return True

def validate_batch_report(path, rows):
    reviewed=[row['id'] for row in rows if validate_review(row)]
    report_path=ROOT/'reviews/translation-review'/f'{path.stem}.json'
    if not reviewed and not report_path.exists():
        return None
    if not report_path.exists():
        raise ValueError(f'{path}: reviewed rows require per-batch semantic review evidence')
    report=json.loads(report_path.read_text(encoding='utf-8'))
    if report['reviewed_file_sha256']!=hashlib.sha256(path.read_bytes()).hexdigest():
        raise ValueError(f'{path}: file changed after recorded review')
    if report['rows']!=len(rows) or set(report['verified_ids'])!=set(reviewed) or len(report['verified_ids'])!=len(reviewed):
        raise ValueError(f'{path}: review evidence does not match verified rows')
    unresolved={row['id'] for row in report['unresolved']}
    if set(reviewed)&unresolved or set(reviewed)|unresolved!={row['id'] for row in rows}:
        raise ValueError(f'{path}: review evidence omits or overlaps rows')
    if not is_worker(report.get('reviewer_model')):
        raise ValueError(f'{path}: unexpected reviewer model')
    for row in rows:
        if row['id'] in reviewed and (row['reviewer_agent']!=report['reviewer_agent'] or row['reviewed_on']!=report['reviewed_on']):
            raise ValueError(f'{path}: row reviewer differs from batch evidence')
    return report

def record_review(batch, reviewer_agent, corrections=None, unresolved=None, reviewer_model=DEFAULT):
    """Seal one fully read batch; supply reasons for every changed/unresolved row."""
    batch=f'{int(batch):03d}'
    path=ROOT/'translations/multibank'/f'batch_{batch}.jsonl'
    baseline=BASELINE/path.name
    before=[json.loads(line) for line in baseline.read_text().splitlines() if line.strip()]
    rows=[json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    old={row['id']:row for row in before}
    if len(rows)!=len(old) or {row['id'] for row in rows}!=old.keys():
        raise ValueError(f'{batch}: review changed row membership')
    corrections=corrections or {};unresolved=unresolved or {}
    unknown=(corrections.keys()|unresolved.keys())-old.keys()
    if unknown:
        raise ValueError(f'{batch}: correction/unresolved IDs are outside the batch: {sorted(unknown)}')
    changed=[];verified=[];blocked=[]
    for row in rows:
        previous=old[row['id']]
        if row['it']!=previous['it'] or row['origin']!=previous['origin']:
            raise ValueError(f'{batch}: source Italian or generation origin changed')
        differences={lang:{'before':previous[lang],'after':row[lang]} for lang in ('en','zh') if row[lang]!=previous[lang]}
        if differences:
            if not corrections.get(row['id']):
                raise ValueError(f"{batch}: correction reason missing for {row['id']}")
            changed.append(dict(id=row['id'],reason=corrections[row['id']],changes=differences))
        if row['id'] in unresolved:
            row['review_status']='draft'
            for key in ('reviewer','reviewer_agent','reviewed_on','reviewed_content_sha256'):
                row.pop(key,None)
            blocked.append(dict(id=row['id'],reason=unresolved[row['id']]))
        else:
            row.update(review_status='reviewed',reviewer=reviewer_model,reviewer_agent=reviewer_agent,reviewed_on=REVIEW_DATE)
            row['reviewed_content_sha256']=reviewed_content_hash(row)
            validate_review(row)
            verified.append(row['id'])
    path.write_text(''.join(json.dumps(row,ensure_ascii=False)+'\n' for row in rows),encoding='utf-8')
    report=dict(batch=batch,reviewer_model=reviewer_model,reviewer_agent=reviewer_agent,reviewed_on=REVIEW_DATE,
        method='Every source row and both target translations read and semantically compared; false assertions retained.',
        baseline_sha256=hashlib.sha256(baseline.read_bytes()).hexdigest(),
        reviewed_file_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        rows=len(rows),verified_ids=verified,unresolved=blocked,corrections=changed)
    folder=ROOT/'reviews/translation-review';folder.mkdir(parents=True,exist_ok=True)
    (folder/f'batch_{batch}.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    return dict(batch=batch,reviewed=len(verified),corrected_rows=len(changed),unresolved=len(blocked))
