#!/usr/bin/env python3
"""Build bank-scoped Italian quiz data, figure references and translations.

Builds use tracked CSV/text/image sources; PDFs are needed only for extraction.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sqlite3

from extract_official_banks import validate_text
from source_files import read_rows, restore_image
from prepare_bank_translations import text_id
from translation_review import validate_review, validate_batch_report

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = (ROOT / 'schema/quiz.sql').read_text(encoding='utf-8')

def load_translations(db):
    used={row[0] for row in db.execute('SELECT id FROM content_texts')}
    seen={}
    for path in sorted((ROOT/'translations/multibank').glob('*.jsonl')):
        rows=[json.loads(line) for line in path.read_text().splitlines() if line.strip()]
        if path.name.startswith('batch_'):
            validate_batch_report(path,rows)
        for n,row in enumerate(rows,1):
            validate_review(row)
            if text_id(row['it'])!=row['id']:
                raise ValueError(f'{path}:{n}: Italian text hash mismatch')
            if row['id'] not in used:
                raise ValueError(f'{path}:{n}: translation has no source text')
            for short,language in [('en','en'),('zh','zh-Hans')]:
                value=row[short].strip()
                if not value:raise ValueError(f'{path}:{n}: empty {short}')
                key=(row['id'],language)
                if key in seen and seen[key]!=value:
                    raise ValueError(f'{path}:{n}: conflicting translation {key}')
                seen[key]=value
                db.execute('INSERT OR IGNORE INTO translations VALUES(?,?,?,?,?)',
                    (row['id'],language,value,row['origin'],row.get('review_status','existing' if row['origin']=='existing_ab' else 'draft')))

def content_hash(db):
    digest=hashlib.sha256()
    for table in ('exam_banks','source_documents','content_texts','translations','chapters','question_groups','questions','question_explanations','assets','question_assets'):
        columns=len(db.execute(f'SELECT * FROM {table} LIMIT 0').description)
        ordering=','.join(str(n) for n in range(1,columns+1))
        digest.update(table.encode('utf-8')+b'\0')
        for row in db.execute(f'SELECT * FROM {table} ORDER BY {ordering}'):
            digest.update(json.dumps(row,ensure_ascii=False,separators=(',',':')).encode('utf-8')+b'\n')
    return digest.hexdigest()

def build(args):
    if args.require_reviewed:
        from check_bank_translations import check
        review_check=check()
        if review_check['pending_batches'] or review_check['unreviewed_unique_strings']:
            raise ValueError('Strict review build requires complete audited semantic reviews for every new bilingual row')
    manifest=json.loads((ROOT/'source/official/manifest.json').read_text())
    db=sqlite3.connect(args.output.with_suffix('.building'))
    try:
        db.executescript(SCHEMA)
        if args.with_indexes:
            db.executescript((ROOT/'schema/indexes.sql').read_text())
        report={'schema_version':5,'banks':[],'unavailable':manifest['unavailable']}
        for bank in manifest['banks']:
            key=bank['id']
            folder=ROOT/'source/banks'/key
            provenance=json.loads((folder/'extraction.json').read_text())
            if provenance['pdf_sha256'] != bank['sha256']:
                raise ValueError(f'{key}: extraction belongs to a different source PDF')
            for name in ('raw.txt','groups.csv','questions.csv','figures.csv','images.csv'):
                if hashlib.sha256((folder/name).read_bytes()).hexdigest() != provenance['files'][name]:
                    raise ValueError(f'{key}: {name} changed since extraction')
            text_path=folder/'raw.txt'
            text=text_path.read_text(encoding='utf-8')
            groups=read_rows(folder/'groups.csv')
            questions=read_rows(folder/'questions.csv')
            expected_groups,expected_questions=validate_text(bank,text)
            if groups != expected_groups or questions != expected_questions:
                raise ValueError(f'{key}: CSV differs from raw source text; re-extract before building')
            import re
            page_count=len(text.rstrip('\f\n').split('\f'))
            db.execute('INSERT INTO exam_banks VALUES(?,?,?,?,?)',(key,bank['title_it'],bank['exam_kind'],'it',int(bank['legacy'])))
            db.execute('INSERT INTO source_documents VALUES(?,?,?,?,?,?,?,?)',(key,bank['url'],bank['pdf'],bank['sha256'],manifest['retrieved_on'],manifest['listing_url'],manifest['listing_updated_on'],page_count))
            chapters={}
            def content(it):
                tid=text_id(it)
                db.execute('INSERT OR IGNORE INTO content_texts VALUES(?,?)',(tid,it))
                return tid
            # Source group numbers are stable; chapter order follows first appearance in the PDF.
            for group in sorted(groups,key=lambda row:row['source_order']):
                category=group['category'];tid=content(category)
                if category not in chapters:
                    chapter_id=f'{key}:chapter:{tid[:16]}'
                    chapters[category]=chapter_id
                    db.execute('INSERT INTO chapters VALUES(?,?,?,?,?)',(chapter_id,key,len(chapters),category,tid))
                db.execute('INSERT INTO question_groups VALUES(?,?,?,?,?)',(f"{key}:group:{group['id']}",key,group['id'],chapters[category],group['page']+1))
            for q in questions:
                db.execute('INSERT INTO questions VALUES(?,?,?,?,?,?,?,?)',(f"{key}:{q['number']}",key,q['number'],f"{key}:group:{q['quesito_id']}",q['text_it'],content(q['text_it']),q['answer'],q['page']+1))
            images=read_rows(folder/'figures.csv')
            embedded=read_rows(folder/'images.csv')
            for image in embedded:
                restore_image(ROOT/image['path'],image['sha256'])
            if [image for image in embedded if 'question_number' in image] != images:
                raise ValueError(f'{key}: figure links differ from embedded image occurrences')
            for image in images:
                path=ROOT/image['path'];digest=hashlib.sha256(path.read_bytes()).hexdigest()
                if digest!=image['sha256']:raise ValueError(f'Asset checksum mismatch: {path}')
                asset_id=digest
                db.execute('INSERT OR IGNORE INTO assets VALUES(?,?,?,?)',(asset_id,image['path'],digest,'image/png' if path.suffix=='.png' else 'image/jpeg'))
                db.execute('INSERT INTO question_assets VALUES(?,?,?,?,?,?,?)',(f"{key}:{image['question_number']}",asset_id,image['page']+1,image['x0'],image['top'],image['x1'],image['bottom']))
            illustrated={image['question_number'] for image in images}
            missing_figures=[q['number'] for q in questions if re.search(r'\braffigurat\w*|\bin figura\b',q['text_it'],re.I) and q['number'] not in illustrated]
            if missing_figures:
                raise ValueError(f'{key}: figure-dependent prompts lack illustrations: {missing_figures}')
            entry=dict(id=key,chapters=len(chapters),groups=len(groups),questions=len(questions),pages=page_count,image_placements=len(images),preserved_embedded_images=len(embedded),extracted_text=str(text_path.relative_to(ROOT)),extracted_text_sha256=hashlib.sha256(text.encode('utf-8')).hexdigest())
            report['banks'].append(entry)
            print(f"{key}: {len(questions)} questions, {len(images)} figure placements",flush=True)
        from content_workflow import load_explanation_rows
        db.executemany('INSERT INTO question_explanations VALUES(?,?,?)', load_explanation_rows())
        load_translations(db)
        from spanish_translations import load_spanish
        load_spanish(db)
        from translation_corrections import apply_to_database
        apply_to_database(db)
        report['translation_coverage']=[dict(zip(['bank_id','questions','english','chinese','spanish'],row)) for row in db.execute('SELECT * FROM translation_coverage ORDER BY bank_id')]
        report['totals']={table:db.execute(f'SELECT count(*) FROM {table}').fetchone()[0] for table in ['exam_banks','chapters','question_groups','questions','content_texts','translations','assets','question_assets']}
        missing=db.execute('SELECT count(*) FROM content_texts c WHERE (SELECT count(*) FROM translations t WHERE t.text_id=c.id)<3').fetchone()[0]
        report['untranslated_unique_strings']=missing
        if args.require_translations and missing:
            raise ValueError(f'{missing} source strings still need English/Chinese/Spanish translations')
        from worker_models import is_worker
        unreviewed=len({text_id for text_id,origin in db.execute("SELECT text_id,origin FROM translations WHERE review_status!='reviewed'")
                        if is_worker(origin.split(':')[0])})
        report['unreviewed_new_unique_strings']=unreviewed
        if args.require_reviewed and (missing or unreviewed):
            raise ValueError(f'{missing} strings untranslated; {unreviewed} new strings still need semantic review')
        report['content_hash']=content_hash(db)
        version=f"{manifest['retrieved_on']}+{report['content_hash'][:12]}"
        db.executemany('INSERT INTO content_manifest VALUES(?,?)',[(k,str(v)) for k,v in dict(schema_version=5,content_version=version,content_hash=report['content_hash'],source_language='it',translation_languages='en,zh-Hans,es-419',retrieved_on=manifest['retrieved_on'],question_count=report['totals']['questions'],untranslated_unique_strings=missing).items()])
        db.execute('INSERT INTO content_manifest VALUES(?,?)',('unreviewed_new_unique_strings',str(unreviewed)))
        report['translation_review_status_counts']=[dict(zip(('origin','language','review_status','count'),row)) for row in db.execute('SELECT origin,language,review_status,count(*) FROM translations GROUP BY origin,language,review_status ORDER BY origin,language,review_status')]
        db.commit()
        if db.execute('PRAGMA foreign_key_check').fetchall():raise ValueError('Foreign key validation failed')
        if db.execute('PRAGMA integrity_check').fetchone()[0]!='ok':raise ValueError('SQLite integrity check failed')
        report['validation']={
            'source_pdf_checksums':'verified during extraction; pinned in source manifest',
            'audited_question_group_counts':'passed',
            'source_row_answer_counts':'passed',
            'figure_asset_checksums':'passed',
            'explicit_figure_references':'passed',
            'translation_hashes_and_conflicts':'passed',
            'english_chinese_review_evidence':'passed',
            'spanish_semantic_review':'passed' if db.execute("SELECT count(*) FROM translations WHERE language='es-419' AND review_status='reviewed'").fetchone()[0] == report['totals']['content_texts'] else 'pending',
            'foreign_keys':'passed',
            'sqlite_integrity':'passed',
            'complete_translations':missing==0,
            'all_new_translations_reviewed':missing==0 and unreviewed==0,
        }
        db.execute('VACUUM')
    finally:db.close()
    args.output.with_suffix('.building').replace(args.output)
    try:report['database_path']=str(args.output.resolve().relative_to(ROOT))
    except ValueError:report['database_path']=str(args.output.resolve())
    report['database_sha256']=hashlib.sha256(args.output.read_bytes()).hexdigest()
    report_path=ROOT/'reviews/multibank-build.json'
    report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report['totals']),flush=True)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'database/quiz.db')
    parser.add_argument('--with-indexes',action='store_true',help='Add optional indexes for bank/group and text lookup queries')
    parser.add_argument('--require-translations',action='store_true')
    parser.add_argument('--require-reviewed',action='store_true')
    args=parser.parse_args();args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.with_suffix('.building').unlink(missing_ok=True)
    try:build(args)
    finally:args.output.with_suffix('.building').unlink(missing_ok=True)

if __name__=='__main__':main()
