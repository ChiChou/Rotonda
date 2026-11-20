#!/usr/bin/env python3
"""Validate worker batch completeness and report the next uncompleted tasks."""
import argparse
import json
from pathlib import Path
import re

from prepare_bank_translations import text_id
from translation_review import validate_review, validate_batch_report
from worker_models import is_worker

ROOT=Path(__file__).resolve().parents[1]

def check():
    from prepare_bank_translations import prepare
    prepare()
    pending=[];completed=[];count=0;reviewed=0;corrections=0;unreviewed=[]
    for task in sorted((ROOT/'translations/tasks').glob('*.jsonl')):
        source=[json.loads(line) for line in task.read_text().splitlines() if line.strip()]
        output=ROOT/'translations/multibank'/f'batch_{task.stem}.jsonl'
        if not output.exists():pending.append(task.stem);continue
        rows=[json.loads(line) for line in output.read_text().splitlines() if line.strip()]
        expected={r['id']:r for r in source};actual={r['id']:r for r in rows}
        if len(actual)!=len(rows) or actual.keys()!=expected.keys():
            raise ValueError(f'{output}: duplicate, missing or unexpected IDs')
        for key,row in actual.items():
            if row['it']!=expected[key]['it'] or text_id(row['it'])!=key:
                raise ValueError(f'{output}: changed Italian text for {key}')
            if not row.get('en','').strip() or not re.search('[\u3400-\u9fff]',row.get('zh','')):
                raise ValueError(f'{output}: absent English or Chinese translation for {key}')
            if not is_worker(row.get('origin')):
                raise ValueError(f'{output}: unexpected model origin for {key}')
            if validate_review(row):reviewed+=1
            else:unreviewed.append(key)
        report=validate_batch_report(output,rows)
        if report:corrections+=len(report['corrections'])
        count+=len(rows);completed.append(task.stem)
    result=dict(completed_batches=completed,translated_unique_strings=count,pending_batches=pending,pending_unique_strings=sum(sum(1 for line in (ROOT/'translations/tasks'/f'{n}.jsonl').read_text().splitlines() if line.strip()) for n in pending),reviewed_unique_strings=reviewed,unreviewed_unique_strings=len(unreviewed),corrected_review_rows=corrections)
    return result

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--require-complete',action='store_true');parser.add_argument('--require-reviewed',action='store_true');args=parser.parse_args()
    result=check();print(json.dumps(result,indent=2))
    if args.require_complete and result['pending_batches']:raise SystemExit(1)
    if args.require_reviewed and (result['pending_batches'] or result['unreviewed_unique_strings']):raise SystemExit(1)
