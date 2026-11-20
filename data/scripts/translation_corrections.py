"""Apply independently reviewed source corrections without rewriting historical pack audits."""
import hashlib
import json

from prepare_bank_translations import text_id
from source_files import ROOT

ORIGIN = 'gpt-6.1-terra:correction'


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode()).hexdigest()


def corrections(root=None):
    root = ROOT if root is None else root
    seen = set()
    for path in sorted((root / 'translations/corrections').glob('*.json')):
        bundle = json.loads(path.read_text())
        draft, review = bundle['draft'], bundle['review']
        pairs = sorted([row['id'], lang] for row in draft['rows'] for lang in row['translations'])
        if (review.get('status') != 'accepted' or review.get('issues') != []
                or review.get('draft_sha256') != fingerprint(draft)
                or not review.get('author') or not review.get('reviewer')
                or review['author'] == review['reviewer'] or review.get('checked_pairs') != pairs):
            raise ValueError(f'{path}: correction lacks an independent review of the exact draft')
        for row in draft['rows']:
            if text_id(row['it']) != row['id'] or not row.get('reason') or not row.get('evidence'):
                raise ValueError(f'{path}: correction has invalid source identity or missing evidence')
            for language, change in row['translations'].items():
                key = (row['id'], language)
                before, after = change['current'], change['proposed']
                if key in seen or not isinstance(after, str) or not after.strip() or before == after:
                    raise ValueError(f'{path}: duplicate or empty correction {key}')
                seen.add(key)
                yield row['id'], language, before, after


def apply_corrections(texts, source_texts, *, root=None):
    """Mutate per-language source maps; refuse stale baselines and absent Italian IDs."""
    applied = []
    for key, language, before, after in corrections(root):
        if key not in source_texts or texts.get(language, {}).get(key) != before:
            raise ValueError(f'Stale translation correction {key}/{language}; re-review the changed source')
        texts[language][key] = after
        applied.append((key, language, after))
    return applied


def apply_to_database(db):
    sources = dict(db.execute('SELECT id, text_it FROM content_texts'))
    texts = {}
    for key, language, text in db.execute('SELECT text_id, language, text FROM translations'):
        texts.setdefault(language, {})[key] = text
    for key, language, after in apply_corrections(texts, sources):
        db.execute("UPDATE translations SET text=?, origin=?, review_status='reviewed' WHERE text_id=? AND language=?",
                   (after, ORIGIN, key, language))
