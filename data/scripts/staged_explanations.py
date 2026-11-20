#!/usr/bin/env python3
"""Generate Italian explanations, then translate frozen Italian text, without review.

Workers run on a lower-cost model chosen with --model (see worker_models.py).

Existing reviewed rows are retained. New rows record generation provenance, never
invented review approval. Model executions are bounded and all run state is external.
"""
import argparse
import concurrent.futures
import json
from pathlib import Path

import content_workflow as wf
import worker_models
import run_explanation_batches as runtime


def issue_numbers(issue, all_numbers):
    if not isinstance(issue,dict):return set(all_numbers)
    numbers=issue.get('numbers',[])
    number=issue.get('number')
    return set(numbers) | set(number if isinstance(number,list) else [number])


def save_completed(task, rows, author, folder):
    """Save structurally valid rows and retain incomplete rows as explicit gaps."""
    expected={r['source']['number'] for r in task['records']}
    existing=wf.explanations(task['bank'],task['language'])
    italian=wf.explanations(task['bank'],'it') if task['language']!='it' else {}
    records={r['source']['number']:r for r in task['records']}
    valid=[]; issues=[]; seen=set()
    for row in rows:
        number=row.get('number')
        if number in existing:continue
        reason=None
        if number not in expected or number in seen:reason='Unexpected or duplicate ID'
        elif not isinstance(row.get('text'),str) or not row['text'].strip():reason='Missing text'
        elif task['language']=='it' and (not isinstance(row.get('evidence'),list)
                or not row['evidence'] or any(not isinstance(e,str) or not e.strip() for e in row['evidence'])):
            reason='Missing Italian evidence'
        elif task['language']!='it' and wf.fingerprint(italian.get(number,{}).get('text'))!=records[number]['italian_sha256']:
            reason='Italian baseline changed'
        seen.add(number)
        if reason:issues.append(dict(number=number,reason=reason))
        else:valid.append(row)
    issues.extend(dict(number=n,reason='Missing draft row') for n in sorted(expected-seen-existing.keys()))
    runtime.write_json(folder/'incomplete-rows.json',dict(issues=issues))
    return accept(task,valid,author)


def recover_staged(base):
    count=0
    for folder in base.iterdir() if base.exists() else []:
        if not folder.is_dir() or not (folder/'task.json').exists() or not (folder/'draft.jsonl').exists():continue
        logs=sorted(folder.glob('author-*.jsonl'),key=lambda p:p.stat().st_mtime_ns)
        if not logs:continue
        try:
            events=[json.loads(line) for line in logs[-1].read_text().splitlines() if line.strip()]
            run_id=runtime.completed_run_id(events)
            if not run_id:continue
            inputs=logs[-1].with_name(logs[-1].stem+'-input.json')
            model=json.loads(inputs.read_text())['model'] if inputs.exists() else runtime.MODEL
            count+=save_completed(json.loads((folder/'task.json').read_text()),wf.jsonl(folder/'draft.jsonl'),
                                  dict(model=model,run_id=run_id),folder)
        except (ValueError,KeyError,TypeError) as exc:
            runtime.write_json(folder/'recovery-error.json',dict(error=str(exc)))
    return count


def validate_generated(bank, language, row, source, packs):
    path = (wf.ROOT / row['generation']).resolve()
    if not path.is_relative_to((wf.ROOT / 'provenance/explanations').resolve()):
        raise ValueError('Generation provenance outside expected directory')
    bundle = json.loads(path.read_text())
    if bundle['status'] != 'generated_unreviewed' or not bundle.get('author'):
        raise ValueError('Invalid generation provenance')
    if bundle['output_sha256'] != wf.fingerprint(bundle['rows']):
        raise ValueError('Changed generation output')
    task = bundle['task']
    if task['task_sha256'] != wf.fingerprint({k:v for k,v in task.items() if k != 'task_sha256'}):
        raise ValueError('Changed generation task')
    records = {r['source']['number']:r for r in task['records']}
    outputs = {r['number']:r for r in bundle['rows']}
    record = records[row['number']]
    if (task['bank'] != bank or task['language'] != language
            or record['source_sha256'] != wf.fingerprint(source)
            or row['source_sha256'] != wf.fingerprint(source)
            or outputs[row['number']]['text'] != row['text']):
        raise ValueError('Stale generation source or text')
    if language != 'it':
        italian = packs[(bank, 'it')].get(row['number'])
        if not italian or wf.fingerprint(italian['text']) != record['italian_sha256']:
            raise ValueError('Stale explanation translation; Italian changed')


def accept(task, rows, author):
    """Structural validation only; no semantic review is claimed."""
    if not rows:
        return 0
    bank, language = task['bank'], task['language']
    current = {r['number']:r for r in wf.question_sources(wf.selected_banks([bank])[0])}
    expected = {r['source']['number']:r for r in task['records']}
    numbers = [r['number'] for r in rows]
    if len(set(numbers)) != len(numbers) or not set(numbers) <= expected.keys():
        raise ValueError('Duplicate or unexpected IDs')
    merged = wf.explanations(bank, language)
    italian = wf.explanations(bank, 'it')
    for row in rows:
        number = row['number']; record = expected[number]
        if number in merged:
            raise ValueError('Refusing to overwrite existing explanation')
        if wf.fingerprint(current[number]) != record['source_sha256']:
            raise ValueError('Changed official source')
        if not isinstance(row.get('text'), str) or not row['text'].strip():
            raise ValueError('Empty explanation')
        if language == 'it' and not row.get('evidence'):
            raise ValueError('Italian reasoning requires evidence')
        if language != 'it' and (number not in italian or
                wf.fingerprint(italian[number]['text']) != record['italian_sha256']):
            raise ValueError('Italian baseline changed')
    relative = Path('provenance/explanations') / bank / language / (wf.fingerprint([task,rows,author])+'.json')
    path = wf.ROOT / relative; path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(dict(status='generated_unreviewed', author=author,
        task=task, rows=rows, output_sha256=wf.fingerprint(rows)),ensure_ascii=False,indent=2)+'\n')
    for row in rows:
        merged[row['number']] = dict(number=row['number'],text=row['text'],
            source_sha256=expected[row['number']]['source_sha256'],generation=str(relative))
    path = wf.ROOT / 'explanations' / bank / (language+'.jsonl')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(''.join(json.dumps(r,ensure_ascii=False)+'\n' for _,r in sorted(merged.items())))
    return len(rows)


def tasks(stage, language, size):
    seen = set()
    banks = sorted(wf.selected_banks(), key=lambda b:bool(b.get('legacy')))
    known = {}
    sources = {b['id']:wf.question_sources(b) for b in banks}
    for bank in banks:
        for lang in wf.EXPLANATION_LANGUAGES:
            for number,row in wf.explanations(bank['id'],lang).items():
                source = next(r for r in sources[bank['id']] if r['number']==number)
                known[(wf.source_identity(source),lang)] = row['text']
    for bank in banks:
        pending=[]
        local=wf.explanations(bank['id'],language)
        local_it=wf.explanations(bank['id'],'it')
        for source in sources[bank['id']]:
            key = wf.source_identity(source)
            if language!='it' and source['number'] not in local_it:continue
            selection_key=(key,wf.fingerprint(local_it[source['number']]['text'])) if language!='it' else key
            if (source['number'] in local or (language=='it' and (key,language) in known)
                    or selection_key in seen):
                continue
            if language != 'it' and (key,'it') not in known:
                continue
            seen.add(selection_key)
            record=dict(source=source,source_sha256=wf.fingerprint(source))
            if language != 'it':
                text=local_it[source['number']]['text']
                record.update(italian=text,italian_sha256=wf.fingerprint(text))
            pending.append(record)
        for start in range(0,len(pending),size):
            task=dict(stage=stage,bank=bank['id'],language=language,records=pending[start:start+size])
            task['task_sha256']=wf.fingerprint(task)
            yield task


def recover(base):
    """Reuse source-bound existing Italian drafts; leave flagged rows for authoring."""
    count=0
    for manifest_path in sorted(base.glob('*/manifest.json')):
        manifest=json.loads(manifest_path.read_text())
        for item in manifest.get('tasks',[]):
            old=json.loads(Path(item['task']).read_text())
            if old.get('language') != 'it' or not Path(item['draft']).exists():continue
            flagged=set()
            review_path=Path(item['review'])
            if review_path.exists():
                review=json.loads(review_path.read_text())
                for issue in review.get('issues',[]):
                    flagged.update(issue_numbers(issue,[r['source']['number'] for r in old['records']]))
            for findings_path in manifest_path.parent.glob('review-findings-*.json'):
                for finding in json.loads(findings_path.read_text()):
                    for issue in finding.get('issues',[]):
                        flagged.update(issue_numbers(issue,[r['source']['number'] for r in old['records']]))
            merged=wf.explanations(old['bank'],'it')
            rows=[r for r in wf.jsonl(Path(item['draft'])) if r['number'] not in merged and r['number'] not in flagged]
            if not rows:continue
            ids={r['number'] for r in rows}
            task=dict(stage='italian',bank=old['bank'],language='it',records=[r for r in old['records'] if r['source']['number'] in ids])
            task['task_sha256']=wf.fingerprint(task)
            history=manifest_path.parent/'author-runs.json'
            if not history.exists():continue
            author_runs=json.loads(history.read_text())
            if not author_runs:continue
            try:count+=accept(task,rows,dict(model=runtime.MODEL,recovered_from=str(manifest_path),runs=author_runs))
            except (ValueError,KeyError):continue
    return count


def generate(task, base):
    """Workers write disjoint external drafts; the coordinator owns repository writes."""
    folder=base/task['task_sha256']
    folder.mkdir(parents=True,exist_ok=True)
    runtime.write_json(folder/'task.json',task)
    draft=folder/'draft.jsonl'
    prompt_name='explain-italian.md' if task['language']=='it' else 'translate-explanations.md'
    prompt=(wf.ROOT/'docs/prompts'/prompt_name).read_text()+f'\nTask: {folder / "task.json"}\nOutput: {draft}\n'
    figures=sorted({wf.ROOT/f['path'] for r in task['records'] for f in r['source']['figures']})
    label='author-'+str(len(list(folder.glob('author-*.jsonl'))))
    run=runtime.run_codex(prompt,folder,label,1800,figures)
    return folder,run,wf.jsonl(draft) if draft.exists() else []


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--state-dir',type=Path,required=True)
    p.add_argument('--stage',choices=('italian','localize'),default='italian')
    p.add_argument('--language',choices=wf.LANGUAGES)
    p.add_argument('--recover-from',type=Path)
    p.add_argument('--size',type=int,default=25)
    p.add_argument('--max-model-runs',type=int,default=2)
    p.add_argument('--concurrency',type=int,default=1,choices=(1,2,3))
    p.add_argument('--model',choices=sorted(worker_models.BACKENDS),default=worker_models.DEFAULT,
                   help='Lower-cost worker model (default: PATENTE_WORKER_MODEL or %(default)s)')
    p.add_argument('--execute',action='store_true')
    args=p.parse_args();base=args.state_dir.resolve()
    runtime.MODEL=args.model
    if base==wf.ROOT or wf.ROOT in base.parents or not 1<=args.size<=50 or args.max_model_runs<1:p.error('Invalid bounds/state directory')
    if args.stage=='localize' and not args.language:p.error('Localization requires one --language')
    if (base/'PAUSED').exists() and args.execute:p.error('Paused')
    if args.recover_from and args.execute:print('Recovered Italian drafts:',recover(args.recover_from),flush=True)
    if args.execute:
        print('Recovered staged rows:',recover_staged(base),flush=True)
        wf.materialize_reuse()
    runtime.RUN_CONTROL=runtime.RunControl(base,args.max_model_runs)
    language='it' if args.stage=='italian' else args.language
    selected=list(tasks(args.stage,language,args.size))[:args.max_model_runs]
    print(f'{len(selected)} {args.stage}/{language} tasks selected; no review runs',flush=True)
    if not args.execute:
        for task in selected:print(task['task_sha256'],len(task['records']))
    else:
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.concurrency) as pool:
            futures={pool.submit(generate,task,base):task for task in selected}
            for future in concurrent.futures.as_completed(futures):
                task=futures[future];folder=base/task['task_sha256']
                try:
                    folder,run,rows=future.result()
                    print('Saved',save_completed(task,rows,dict(model=runtime.MODEL,run_id=run),folder),language,'explanations',flush=True)
                except runtime.DispatchLimit:
                    raise
                except Exception as exc:
                    runtime.write_json(folder/'generation-error.json',dict(error=str(exc)))
                    print('Batch left incomplete:',str(exc),flush=True)
    if args.execute:wf.materialize_reuse()
    print(json.dumps(runtime.usage_summary(base),indent=2))


if __name__=='__main__':main()
