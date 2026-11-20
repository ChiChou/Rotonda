#!/usr/bin/env python3
"""Reuse exact Italian matches and create deduplicated worker translation tasks."""
import hashlib
import json
from pathlib import Path
import re
import unicodedata
from source_files import read_rows

ROOT = Path(__file__).resolve().parents[1]

def normalize(text):
    return re.sub(r'\s+', ' ', unicodedata.normalize('NFKC', text).replace('’', "'").replace('‘', "'")).strip()

def text_id(text):
    return hashlib.sha256(normalize(text).encode()).hexdigest()

def prepare():
    # Reviewed translation outputs are source artifacts; task inputs are derived.
    reused = ROOT / 'translations/multibank/reused_ab.jsonl'
    known = {row['id']: row for row in
             (json.loads(line) for line in reused.read_text().splitlines() if line.strip())}
    needed = {}
    banks=json.loads((ROOT/'source/official/manifest.json').read_text())['banks']
    for bank in sorted(banks,key=lambda row:row['id']):
        file=ROOT/'source/banks'/bank['id']
        data = {kind: read_rows(file / (kind + '.csv')) for kind in ('questions', 'groups')}
        for row in data['questions']:
            it = row['text_it']; key=text_id(it)
            needed.setdefault(key, dict(id=key,it=it,refs=[]))['refs'].append(f"{bank['id']}:{row['number']}")
        for row in data['groups']:
            it=row['category'];key=text_id(it)
            needed.setdefault(key, dict(id=key,it=it,refs=[]))['refs'].append(f"{bank['id']}:group:{row['id']}")
    folder=ROOT/'translations/multibank';folder.mkdir(parents=True,exist_ok=True)
    pending = dict((key, row) for key, row in needed.items() if key not in known)
    jobs=ROOT/'translations/tasks';jobs.mkdir(parents=True,exist_ok=True)
    batch_number = 0
    # Preserve completed batch membership so review evidence remains valid.
    for output in sorted(folder.glob('batch_*.jsonl')):
        rows = [json.loads(line) for line in output.read_text().splitlines() if line.strip()]
        task_rows = []
        for row in rows:
            if row['id'] not in pending:
                raise ValueError(f'{output}: duplicate or unexpected translation source')
            task_rows.append(pending.pop(row['id']))
        batch_number = int(output.stem.split('_')[1])
        (jobs/f'{batch_number:03d}.jsonl').write_text(''.join(json.dumps(row,ensure_ascii=False)+'\n' for row in task_rows))
        batch_number += 1
    remaining=sorted(pending.values(),key=lambda row:row['id'])
    for start in range(0,len(remaining),100):
        (jobs/f'{batch_number+start//100:03d}.jsonl').write_text(''.join(json.dumps(row,ensure_ascii=False)+'\n' for row in remaining[start:start+100]))
    print(f'{len(known)} reused translations; {len(remaining)} strings still need translation')

if __name__=='__main__':
    prepare()
