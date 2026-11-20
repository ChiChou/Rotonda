#!/usr/bin/env python3
"""Verify manually supplied official PDFs. Never downloads or changes the manifest."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def verify(bank, root=ROOT):
    path = root / bank['pdf']
    if not path.is_file():
        raise ValueError(f"{bank['id']}: manually place the original PDF at {path}; source: {bank['url']}")
    data = path.read_bytes()
    if not data.startswith(b'%PDF-'):
        raise ValueError(f"{bank['id']}: not a PDF: {path}")
    if len(data) != bank['bytes'] or hashlib.sha256(data).hexdigest() != bank['sha256']:
        raise ValueError(f"{bank['id']}: PDF differs from the pinned edition; review the source and manifest explicitly")
    return path


def selected_banks(bank_ids=None):
    manifest = json.loads((ROOT / 'source/official/manifest.json').read_text())
    banks = {bank['id']: bank for bank in manifest['banks']}
    unknown = set(bank_ids or []) - banks.keys()
    if unknown:
        raise ValueError(f'Unknown banks: {sorted(unknown)}')
    return [bank for key, bank in banks.items() if not bank_ids or key in bank_ids]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bank', action='append', help='Verify only this bank; repeatable')
    args = parser.parse_args()
    errors = []
    for bank in selected_banks(args.bank):
        try:
            verify(bank)
            print(f"{bank['id']}: verified")
        except ValueError as error:
            errors.append(str(error))
    if errors:
        parser.exit(1, '\n'.join(errors) + '\n')


if __name__ == '__main__':
    main()
