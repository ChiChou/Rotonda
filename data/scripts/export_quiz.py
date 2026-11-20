#!/usr/bin/env python3
"""Export questions with bank IDs, source references and translations."""
import csv
import json
from pathlib import Path
import sqlite3

ROOT=Path(__file__).resolve().parents[1]

def main():
    with sqlite3.connect(f'file:{ROOT / "database/quiz.db"}?mode=ro',uri=True) as db:
        db.row_factory=sqlite3.Row
        rows=[]
        for row in db.execute('''SELECT q.*,c.id AS chapter_id,c.title_it AS chapter_it,
                en.text AS chapter_en,zh.text AS chapter_zh,es.text AS chapter_es
                FROM localized_questions q
                JOIN question_groups g ON g.id=q.group_id
                JOIN chapters c ON c.id=g.chapter_id
                LEFT JOIN translations en ON en.text_id=c.text_id AND en.language='en'
                LEFT JOIN translations zh ON zh.text_id=c.text_id AND zh.language='zh-Hans'
                LEFT JOIN translations es ON es.text_id=c.text_id AND es.language='es-419'
                ORDER BY q.bank_id,q.official_number'''):
            item=dict(row)
            item['answer']=bool(item['answer'])
            item['answer_text']='VERO' if item['answer'] else 'FALSO'
            item['images']=[dict(img) for img in db.execute('''SELECT a.path,qa.source_page,qa.x0,qa.top,qa.x1,qa.bottom
                FROM question_assets qa JOIN assets a ON a.id=qa.asset_id
                WHERE qa.question_id=? ORDER BY qa.source_page,qa.top''',(item['id'],))]
            rows.append(item)
        banks=[dict(r) for r in db.execute('SELECT * FROM exam_banks ORDER BY id')]
    folder=ROOT/'exports';folder.mkdir(parents=True,exist_ok=True)
    (folder/'questions.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
    (folder/'banks.json').write_text(json.dumps(banks,ensure_ascii=False,indent=2)+'\n')
    with (folder/'questions.csv').open('w',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=list(rows[0]),lineterminator='\n');writer.writeheader()
        for row in rows:
            writer.writerow({**row,'images':json.dumps(row['images'],ensure_ascii=False)})
    print(f'Exported {len(rows)} questions across {len(banks)} banks')

if __name__=='__main__':main()
