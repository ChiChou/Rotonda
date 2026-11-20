#!/usr/bin/env python3
"""Extract the pinned official PDFs into versioned CSV, text, and image sources."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

from extract_pdf_questions import convert, extract
from source_files import ROOT, read_rows, write_rows
from verify_official_pdfs import selected_banks, verify
import tempfile


def poppler(name):
    executable = shutil.which(name)
    candidate = Path.home() / '.cache/codex-runtimes/codex-primary-runtime/dependencies/native/poppler/poppler/bin' / name
    if not executable and candidate.is_file():
        executable = str(candidate)
    if not executable:
        raise FileNotFoundError(f'Install Poppler: {name} was not found')
    return executable


def validate_text(bank, text):
    groups, questions, warnings = extract(text)
    rows = re.findall(r'^\d{4,6}\s+', text.replace('\f', '\n'), re.M)
    answers = re.findall(r'\b(?:VERO|FALSO)\s*$', text, re.M)
    if warnings or len(questions) != bank['expected_questions'] or len(groups) != bank['expected_groups']:
        raise ValueError(f"{bank['id']}: extraction warnings/count mismatch: {warnings}")
    if len(rows) != len(questions) or len(answers) != len(questions):
        raise ValueError(f"{bank['id']}: question/answer row counts differ")
    return sorted(groups, key=lambda r: r['id']), sorted(questions, key=lambda r: r['number'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--refresh-images', action='store_true')
    parser.add_argument('--bank', action='append', help='Extract only this bank; repeatable')
    args = parser.parse_args()
    banks = selected_banks(args.bank)
    # Fail before writing any sources if a selected original is missing or changed.
    for bank in banks:
        verify(bank)
    for bank in banks:
        extract_bank(bank, args.refresh_images)


def extract_bank(bank, refresh_images=False):
    pdf = verify(bank)
    target = ROOT / 'source/banks' / bank['id']
    target.mkdir(parents=True, exist_ok=True)
    previous = target / 'extraction.json'
    same_pdf = previous.is_file() and json.loads(previous.read_text())['pdf_sha256'] == bank['sha256']
    # Stage records so parser/image errors cannot overwrite an accepted extraction.
    with tempfile.TemporaryDirectory(prefix='patente-extract-') as temporary:
        folder = Path(temporary)
        text = convert(pdf, poppler('pdftotext'))
        groups, questions = validate_text(bank, text)
        (folder / 'raw.txt').write_text(text, encoding='utf-8')
        write_rows(folder / 'groups.csv', groups)
        write_rows(folder / 'questions.csv', questions)
        if refresh_images or not same_pdf or not all((target / name).is_file() for name in ('images.csv', 'figures.csv')):
            from pdf_bank_images import extract_bank_images
            embedded = []
            figures = extract_bank_images(pdf, bank['id'], ROOT / 'assets/official', all_images=embedded)
            for image in embedded:
                image['path'] = str(Path(image['path']).resolve().relative_to(ROOT))
            write_rows(folder / 'figures.csv', figures)
            write_rows(folder / 'images.csv', embedded)
        else:
            for name in ('images.csv', 'figures.csv'):
                shutil.copyfile(target / name, folder / name)
        provenance = dict(pdf_sha256=bank['sha256'], files={
            name: hashlib.sha256((folder / name).read_bytes()).hexdigest()
            for name in ('raw.txt', 'groups.csv', 'questions.csv', 'figures.csv', 'images.csv')})
        (folder / 'extraction.json').write_text(json.dumps(provenance, indent=2) + '\n', encoding='utf-8')
        for path in folder.iterdir():
            shutil.copyfile(path, target / path.name)
        print(f"{bank['id']}: {len(questions)} questions, {len(groups)} groups", flush=True)


if __name__ == '__main__':
    main()
