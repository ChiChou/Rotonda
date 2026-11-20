#!/usr/bin/env python3
"""Report content gaps and prepare small, source-bound tasks for model workers."""
import argparse
import hashlib
import json
from pathlib import Path

from prepare_bank_translations import text_id
from source_files import ROOT, image_suffix, read_rows
from verify_official_pdfs import selected_banks
import worker_models

LANGUAGES = ('en', 'zh-Hans', 'es-419')
EXPLANATION_LANGUAGES = ('it', *LANGUAGES)


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode()).hexdigest()


def jsonl(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def translations():
    result = {language: {} for language in LANGUAGES}
    source_texts = {}
    for path in sorted((ROOT / 'translations/multibank').glob('*.jsonl')):
        for row in jsonl(path):
            source_texts[row['id']] = row['it']
            for field, language in (('en', 'en'), ('zh', 'zh-Hans')):
                result[language][row['id']] = row[field]
    for path in sorted((ROOT / 'translations/es-419').glob('*.csv')):
        for row in read_rows(path):
            result['es-419'][row['id']] = row['text']
    from translation_corrections import apply_corrections
    apply_corrections(result, source_texts, root=ROOT)
    return result


def question_sources(bank):
    folder = ROOT / 'source/banks' / bank['id']
    provenance = json.loads((folder / 'extraction.json').read_text())
    if provenance['pdf_sha256'] != bank['sha256']:
        raise ValueError(f"Stale PDF extraction: {bank['id']}")
    for name in ('raw.txt', 'questions.csv', 'groups.csv', 'images.csv', 'figures.csv'):
        if hashlib.sha256((folder / name).read_bytes()).hexdigest() != provenance['files'][name]:
            raise ValueError(f"Changed extraction source: {bank['id']}/{name}")
    figures = {}
    for figure in read_rows(folder / 'figures.csv'):
        path = f"source/images/{figure['sha256']}{image_suffix(Path(figure['path']).suffix)}"
        if hashlib.sha256((ROOT / path).read_bytes()).hexdigest() != figure['sha256']:
            raise ValueError(f'Corrupt source image: {path}')
        figures.setdefault(figure['question_number'], []).append(dict(
            path=path, sha256=figure['sha256'], page=figure['page'],
            bbox=[figure[k] for k in ('x0', 'top', 'x1', 'bottom')]))
    return [dict(row, bank=bank['id'], pdf_sha256=bank['sha256'],
                 figures=figures.get(row['number'], []))
            for row in read_rows(folder / 'questions.csv')]


def explanations(bank_id, language):
    path = ROOT / 'explanations' / bank_id / f'{language}.jsonl'
    rows = jsonl(path) if path.exists() else []
    result = {row['number']: row for row in rows}
    if len(rows) != len(result):
        raise ValueError(f'Duplicate explanations: {path}')
    return result


def reusable_ab(bank, source, language):
    """Reuse only exact Italian, answer and figure-byte matches, never number alone."""
    ab_bank = next(b for b in selected_banks() if b['id'] == 'ab')
    ab = {r['number']: r for r in question_sources(ab_bank)}
    texts = explanations('ab', language)
    def identity(row):
        return row['text_it'], row['answer'], sorted({f['sha256'] for f in row['figures']})
    return {r['number']: texts[r['number']] for r in source
            if r['number'] in ab and r['number'] in texts and
            identity(r) == identity(ab[r['number']])}


def source_identity(row):
    """Only the same official question, assertion, verdict and figure bytes may share reasoning."""
    return (row['number'], row['text_it'], row['answer'],
            tuple(sorted({f['sha256'] for f in row['figures']})))


def content_identity(row, typography=False):
    text,answer,figures=source_identity(row)[1:]
    if typography:text=' '.join(text.replace('’',"'").replace('‘',"'").split())
    return text,answer,figures


def reuse_identical_content(*, typography=False):
    """Reuse exact assertions/verdicts/figure bytes even when editions renumber IDs."""
    load_explanation_rows()
    banks=sorted(selected_banks(),key=lambda b:bool(b.get('legacy')))
    sources={b['id']:question_sources(b) for b in banks}
    packs={(b['id'],lang):explanations(b['id'],lang) for b in banks for lang in EXPLANATION_LANGUAGES}
    donors={}
    for bank in banks:
        for source in sources[bank['id']]:
            key=content_identity(source,typography)
            for lang in EXPLANATION_LANGUAGES:
                row=packs[(bank['id'],lang)].get(source['number'])
                if row and 'reuse' not in row:
                    donors.setdefault((key,lang),(bank,source,row))
    count=0
    for bank in banks:
        for lang in EXPLANATION_LANGUAGES:
            rows=packs[(bank['id'],lang)];changed=False
            for source in sources[bank['id']]:
                if source['number'] in rows:continue
                donor=donors.get((content_identity(source,typography),lang))
                if donor is None:continue
                donor_bank,donor_source,donor_row=donor
                if donor_bank.get('legacy') and not bank.get('legacy'):continue
                if lang!='it':
                    target_it=packs[(bank['id'],'it')].get(source['number'],{}).get('text')
                    donor_it=packs[(donor_bank['id'],'it')].get(donor_source['number'],{}).get('text')
                    if target_it is None or target_it!=donor_it:continue
                rows[source['number']]=dict(number=source['number'],text=donor_row['text'],
                    source_sha256=fingerprint(source),reuse=dict(bank=donor_bank['id'],
                    number=donor_source['number'],match='typographic-content' if typography else 'exact-content'))
                count+=1;changed=True
            if changed:
                path=ROOT/'explanations'/bank['id']/(lang+'.jsonl')
                path.parent.mkdir(parents=True,exist_ok=True)
                path.write_text(''.join(json.dumps(row,ensure_ascii=False)+'\n' for _,row in sorted(rows.items())))
    load_explanation_rows()
    return count


def materialize_reuse():
    """Copy accepted explanations to exact matching bank memberships with explicit provenance."""
    # Validate donor provenance before making another bank depend on it.
    load_explanation_rows()
    banks = selected_banks()
    sources = {b['id']: question_sources(b) for b in banks}
    donors = {}
    for bank in banks:
        by_number = {row['number']: row for row in sources[bank['id']]}
        italian=explanations(bank['id'],'it')
        for language in EXPLANATION_LANGUAGES:
            for number, row in explanations(bank['id'], language).items():
                if 'reuse' in row:
                    continue  # Always point directly to the authored/legacy source.
                baseline=None if language=='it' else fingerprint(italian.get(number,{}).get('text'))
                key = (source_identity(by_number[number]), language, baseline)
                if key in donors and donors[key][2]['text'] != row['text']:
                    raise ValueError(f'Conflicting accepted explanation donors: {number}/{language}')
                donors.setdefault(key, (bank['id'], number, row))
    count = 0
    for bank in banks:
        for language in EXPLANATION_LANGUAGES:
            rows = explanations(bank['id'], language)
            italian=explanations(bank['id'],'it') if language!='it' else {}
            changed = False
            for source in sources[bank['id']]:
                if source['number'] in rows:
                    continue
                baseline=None if language=='it' else fingerprint(italian.get(source['number'],{}).get('text'))
                donor = donors.get((source_identity(source), language, baseline))
                if donor is None:
                    continue
                donor_bank, number, row = donor
                if language!='it':
                    target_it=explanations(bank['id'],'it').get(source['number'],{}).get('text')
                    donor_it=explanations(donor_bank,'it').get(number,{}).get('text')
                    if target_it is None or target_it!=donor_it:continue
                reuse=dict(bank=donor_bank,number=number)
                if language!='it':reuse['italian_sha256']=baseline
                rows[number] = dict(number=number, text=row['text'], source_sha256=fingerprint(source),reuse=reuse)
                count += 1
                changed = True
            if changed:
                path = ROOT / 'explanations' / bank['id'] / f'{language}.jsonl'
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(''.join(json.dumps(row, ensure_ascii=False) + '\n' for _, row in sorted(rows.items())))
    print(f'Materialized {count} exact cross-bank explanation memberships')
    return count


def coverage():
    localized = translations()
    result = {'languages': list(LANGUAGES), 'banks': [],
              'explanation_note': 'Includes exact A/B reuse; existing A/B explanations predate this workflow.'}
    for bank in selected_banks():
        source = question_sources(bank)
        folder = ROOT / 'source/banks' / bank['id']
        strings = {text_id(r['text_it']) for r in source}
        strings.update(text_id(r['category']) for r in read_rows(folder / 'groups.csv'))
        translated = {lang: len(strings - localized[lang].keys()) for lang in LANGUAGES}
        missing = {}
        for lang in EXPLANATION_LANGUAGES:
            known = reusable_ab(bank, source, lang) | explanations(bank['id'], lang)
            missing[lang] = sum(not known.get(r['number'], {}).get('text', '').strip() for r in source)
        result['banks'].append(dict(bank=bank['id'], legacy=bank['legacy'],
            questions=len(source), missing_translations=translated, missing_explanations=missing))
    result['unavailable_sources'] = json.loads((ROOT / 'source/official/manifest.json').read_text())['unavailable']
    return result


def prepare(bank, stage, language, size, output):
    source = question_sources(bank)
    folder = ROOT / 'source/banks' / bank['id']
    localized = translations()
    if stage == 'extract':
        # Pages remain explicit, including those without numbered question rows.
        pages = (folder / 'raw.txt').read_text().split('\f')
        if not pages[-1].strip():
            pages.pop()
        records = [dict(page=i, raw=text, questions=[r for r in source if r['page'] == i],
                        images=[r for r in read_rows(folder / 'images.csv') if r['page'] == i])
                   for i, text in enumerate(pages)]
    elif stage == 'translate':
        needed = {text_id(r['text_it']): r['text_it'] for r in source}
        needed.update({text_id(r['category']): r['category'] for r in read_rows(folder / 'groups.csv')})
        records = [dict(id=key, it=it) for key, it in sorted(needed.items())
                   if not localized[language].get(key, '').strip()]
    else:
        known = reusable_ab(bank, source, language) | explanations(bank['id'], language)
        records = []
        for row in source:
            if known.get(row['number'], {}).get('text', '').strip():
                continue
            translation = row['text_it'] if language == 'it' else localized[language].get(text_id(row['text_it']))
            if not translation:
                raise ValueError(f"Translate first: {bank['id']}:{row['number']} {language}")
            records.append(dict(source=row, source_sha256=fingerprint(row), localized_text=translation))
    destination = output / stage / bank['id'] / language
    destination.mkdir(parents=True, exist_ok=True)
    if any(destination.glob('*.json')):
        raise ValueError(f'Task folder already has tasks; use a new output directory: {destination}')
    for start in range(0, len(records), size):
        task = dict(schema_version=1, stage=stage, bank=bank['id'], language=language,
                    pdf=bank['pdf'], pdf_sha256=bank['sha256'], model=worker_models.DEFAULT,
                    records=records[start:start + size])
        task['task_sha256'] = fingerprint(task)
        (destination / f'{start // size:04}.json').write_text(json.dumps(task, ensure_ascii=False, indent=2) + '\n')
    print(f"{bank['id']} {language}: {len(records)} {stage} records, {(len(records)+size-1)//size} tasks")


def validate_explanations(task, rows, review, *, source_by_bank=None, localized=None, check_localized=True):
    claimed = task['task_sha256']
    if fingerprint({k: v for k, v in task.items() if k != 'task_sha256'}) != claimed:
        raise ValueError('Task fingerprint mismatch')
    if task['stage'] != 'explain' or task['language'] not in EXPLANATION_LANGUAGES:
        raise ValueError('Expected an explanation task with a supported language')
    bank = selected_banks([task['bank']])[0]
    current = (source_by_bank[bank['id']] if source_by_bank is not None
               else {r['number']: r for r in question_sources(bank)})
    if localized is None:
        localized = translations()
    expected = {r['source']['number']: r for r in task['records']}
    actual = {r['number']: r for r in rows}
    if len(actual) != len(rows) or actual.keys() != expected.keys():
        raise ValueError('Duplicate, missing or unexpected explanation IDs')
    for number, row in actual.items():
        source = current.get(number)
        if source is None or fingerprint(source) != expected[number]['source_sha256']:
            raise ValueError(f'Stale question/answer/figure source: {number}')
        text = source['text_it'] if task['language'] == 'it' else localized[task['language']].get(text_id(source['text_it']))
        if check_localized and text != expected[number]['localized_text']:
            raise ValueError(f'Stale localized source: {number}')
        if not isinstance(row.get('text'), str) or not row['text'].strip():
            raise ValueError(f'Empty explanation: {number}')
        if not isinstance(row.get('evidence'), list) or not row['evidence'] or any(not isinstance(e, str) or not e.strip() for e in row['evidence']):
            raise ValueError(f'Missing explanation evidence: {number}')
    if (review.get('task_sha256') != claimed or review.get('output_sha256') != fingerprint(rows)
            or review.get('status') != 'accepted' or review.get('issues') != []
            or not review.get('reviewer') or not review.get('author')
            or review['reviewer'] == review['author']
            or review.get('checked_numbers') != sorted(expected)):
        raise ValueError('Review must accept and bind every exact source/output row with no unresolved issues')
    return expected


def accept(task_path, draft_path, review_path):
    task, rows, review = json.loads(task_path.read_text()), jsonl(draft_path), json.loads(review_path.read_text())
    expected = validate_explanations(task, rows, review)
    relative = Path('reviews/explanations') / task['bank'] / task['language'] / f"{task['task_sha256']}.json"
    evidence = ROOT / relative
    evidence.parent.mkdir(parents=True, exist_ok=True)
    evidence.write_text(json.dumps(dict(task=task, rows=rows, review=review), ensure_ascii=False, indent=2) + '\n')
    path = ROOT / 'explanations' / task['bank'] / f"{task['language']}.jsonl"
    merged = explanations(task['bank'], task['language'])
    for row in rows:
        merged[row['number']] = dict(number=row['number'], text=row['text'],
            source_sha256=expected[row['number']]['source_sha256'], review=str(relative))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(''.join(json.dumps(row, ensure_ascii=False) + '\n' for _, row in sorted(merged.items())))
    print(f'Accepted {len(rows)} explanations into {path}')


def load_explanation_rows():
    """Validate accepted extensions; retain legacy A/B text without inventing review evidence."""
    checked = {}
    result = []
    banks = selected_banks()
    sources = {b['id']: {r['number']: r for r in question_sources(b)} for b in banks}
    localized = translations()
    packs = {(b['id'], lang): explanations(b['id'], lang) for b in banks for lang in EXPLANATION_LANGUAGES}
    validated = set()

    def validate_row(bank_id, language, number, visiting=frozenset()):
        key = (bank_id, language, number)
        if key in visiting:
            raise ValueError(f'Cyclic explanation reuse: {key}')
        if key in validated:
            return
        source = sources.get(bank_id, {}).get(number)
        row = packs.get((bank_id, language), {}).get(number)
        if source is None or row is None or not row['text'].strip():
            raise ValueError(f'Invalid explanation {key}')
        if 'reuse' in row:
            donor = row['reuse']
            donor_bank, donor_number = donor['bank'], donor['number']
            validate_row(donor_bank, language, donor_number, visiting | {key})
            donor_source = sources[donor_bank][donor_number]
            donor_row = packs[(donor_bank, language)][donor_number]
            source_key,donor_key=source_identity(source),source_identity(donor_source)
            if donor.get('match')=='exact-content':source_key,donor_key=source_key[1:],donor_key[1:]
            elif donor.get('match')=='typographic-content':
                source_key,donor_key=content_identity(source,True),content_identity(donor_source,True)
            if language!='it' and (donor.get('match') in ('exact-content','typographic-content') or 'italian_sha256' in donor):
                target_it=packs[(bank_id,'it')].get(number,{}).get('text')
                donor_it=packs[(donor_bank,'it')].get(donor_number,{}).get('text')
                if target_it is None or target_it!=donor_it:
                    raise ValueError(f'Explanation reuse has a different Italian baseline: {key}')
                if 'italian_sha256' in donor and donor['italian_sha256']!=fingerprint(target_it):
                    raise ValueError(f'Stale Italian baseline for explanation reuse: {key}')
            if (fingerprint(source) != row.get('source_sha256')
                    or source_key != donor_key
                    or row['text'] != donor_row['text']):
                raise ValueError(f'Stale or nonidentical explanation reuse: {key}')
        elif 'generation' in row:
            from staged_explanations import validate_generated
            validate_generated(bank_id, language, row, source, packs)
        elif 'review' not in row:
            if bank_id != 'ab':
                raise ValueError(f'Missing review for {key}')
        else:
            path = (ROOT / row['review']).resolve()
            if not path.is_relative_to((ROOT / 'reviews/explanations').resolve()):
                raise ValueError('Explanation review must be inside reviews/explanations')
            if path not in checked:
                bundle = json.loads(path.read_text())
                # A changed statement elsewhere in the batch does not invalidate this row;
                # each row is checked against its own localized statement below.
                validate_explanations(bundle['task'], bundle['rows'], bundle['review'],
                                      source_by_bank=sources, localized=localized, check_localized=False)
                checked[path] = bundle
            bundle = checked[path]
            accepted = {r['number']: r for r in bundle['rows']}
            records = {r['source']['number']: r for r in bundle['task']['records']}
            if (bundle['task']['bank'] != bank_id or bundle['task']['language'] != language
                    or number not in accepted or accepted[number]['text'] != row['text']
                    or records[number]['source_sha256'] != row.get('source_sha256')):
                raise ValueError(f'Explanation no longer matches review: {number}')
            text = source['text_it'] if language == 'it' else localized[language].get(text_id(source['text_it']))
            if text != records[number]['localized_text']:
                raise ValueError(f'Stale localized source: {number}')
        validated.add(key)

    for bank in banks:
        for language in EXPLANATION_LANGUAGES:
            for number, row in packs[(bank['id'], language)].items():
                validate_row(bank['id'], language, number)
                result.append((f"{bank['id']}:{number}", language, row['text']))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    audit = commands.add_parser('coverage')
    audit.add_argument('--output', type=Path)
    audit.add_argument('--require-translations', action='store_true')
    audit.add_argument('--require-explanations', action='store_true')
    jobs = commands.add_parser('prepare')
    jobs.add_argument('--stage', choices=('extract', 'translate', 'explain'), required=True)
    jobs.add_argument('--bank', action='append')
    jobs.add_argument('--language', choices=EXPLANATION_LANGUAGES, default='it')
    jobs.add_argument('--size', type=int, help='Default: 5 pages, 50 translations, or 25 explanations')
    jobs.add_argument('--output', type=Path, required=True)
    publish = commands.add_parser('accept-explanations')
    commands.add_parser('materialize-reuse')
    for name in ('task', 'draft', 'review'):
        publish.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    if args.command == 'coverage':
        report = coverage()
        text = json.dumps(report, ensure_ascii=False, indent=2) + '\n'
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(text)
        else:
            print(text, end='')
        if args.require_translations and any(any(b['missing_translations'].values()) for b in report['banks']):
            parser.exit(1, 'Missing translations\n')
        if args.require_explanations and any(any(b['missing_explanations'].values()) for b in report['banks']):
            parser.exit(1, 'Missing explanations\n')
    elif args.command == 'prepare':
        if args.stage == 'translate' and args.language == 'it':
            parser.error('Translation tasks require a helper language')
        size = args.size or {'extract': 5, 'translate': 50, 'explain': 25}[args.stage]
        if size < 1 or size > {'extract': 10, 'translate': 100, 'explain': 50}[args.stage]:
            parser.error('Keep batches within 10 pages / 100 translations / 50 explanations')
        for bank in selected_banks(args.bank):
            prepare(bank, args.stage, args.language, size, args.output)
    elif args.command == 'materialize-reuse':
        materialize_reuse()
    else:
        accept(args.task, args.draft, args.review)


if __name__ == '__main__':
    main()
