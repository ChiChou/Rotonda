#!/usr/bin/env python3
"""Build a separate, attributed CEFR/stop-word overlay; never mutate the quiz bank."""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import unicodedata

ROOT = Path(__file__).resolve().parents[1]
LEVELS = ('A1','A2','B1','B2','C1','C2')
DECK_SHA = '357e0e83144493e50dbf01a7cb7b038e2833e840eb271175235da733e22b813d'
def normalize(word):
    return unicodedata.normalize('NFC', word).lower().replace('’', "'")

def build(deck, stops, morphology, output):
    assert hashlib.sha256(deck.read_bytes()).hexdigest() == DECK_SHA, 'Unexpected CEFR source version'
    records = json.loads(deck.read_text())
    direct = collections.defaultdict(set)
    for entry in records:
        if entry['cefr_level'] in LEVELS:
            direct[normalize(entry['word'])].add(entry['cefr_level'])
    # Read the literal data only; never execute downloaded Python source.
    literal = re.search(r'"""(.*?)"""', stops.read_text(), re.S).group(1)
    stopwords = {normalize(w) for w in literal.split()} | {'l', 'd'}
    with sqlite3.connect(f'file:{ROOT / "data/app/quiz.db"}?mode=ro', uri=True) as db:
        words = {normalize(row[0]) for row in db.execute('SELECT word FROM dictionary_entries')}
    curated = json.loads((ROOT / 'data/app/curated_study.json').read_text())
    words.update(normalize(item['it']) for item in curated['examLanguage'] + curated['roadWords'])
    lemmas = collections.defaultdict(set)
    for line in morphology.read_text().splitlines():
        columns = line.split('\t')
        if len(columns) == 3:
            form, lemma, _ = columns
            if normalize(form) in words:
                lemmas[normalize(form)].add(normalize(lemma))
    entries = {}
    for word in sorted(words):
        parts = re.findall(r'[^\W\d_]+', word)
        entry = {'isStopWord': word in stopwords or bool(parts) and all(p in stopwords for p in parts), 'match': 'unclassified'}
        candidates = direct[word]
        if len(candidates) == 1:
            entry.update(level=next(iter(candidates)), match='direct', sourceWords=[word])
        elif not candidates:
            # Only unambiguous morphological analyses with complete source coverage.
            candidates = set().union(*(direct[l] for l in lemmas[word])) if lemmas[word] else set()
            if len(candidates) == 1 and all(len(direct[l]) == 1 for l in lemmas[word]):
                entry.update(level=next(iter(candidates)), match='lemma', sourceWords=sorted(lemmas[word]))
        entries[word] = entry
    referenced = {w for v in entries.values() for w in v.get('sourceWords', [])}
    lexicon = {normalize(r['word']): {'word': r['word'], 'level': r['cefr_level'], 'english': r['english_translation'], 'exampleItalian': r['example_sentence_native'], 'exampleEnglish': r['example_sentence_english'], 'partOfSpeech': r['pos']} for r in records if normalize(r['word']) in referenced}
    result = {'lexicon': lexicon, 'schemaVersion':1, 'sources': {
        'cefr': {'url':'https://github.com/vbvss199/Language-Learning-decks', 'revision':'efd235e692efd47eda026d0a1cbd703ce23d7692','sha256':DECK_SHA},
        'stopwords': {'url':'https://github.com/explosion/spaCy/blob/master/spacy/lang/it/stop_words.py','sha256':hashlib.sha256(stops.read_bytes()).hexdigest()},
        'morphology': {'url':'https://docs.sslmit.unibo.it/doku.php?id=resources:morph-it','sha256':hashlib.sha256(morphology.read_bytes()).hexdigest()}
    },'entries':entries}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True)+'\n')
    print(collections.Counter('stopword' if v['isStopWord'] else v.get('level','unclassified') for v in entries.values()))

if __name__ == '__main__':
    p=argparse.ArgumentParser()
    p.add_argument('--deck',type=Path,required=True)
    p.add_argument('--stopwords',type=Path,required=True)
    p.add_argument('--morphology',type=Path,default=ROOT/'Server/study_pipeline/resources/morph-it_048_utf8.txt')
    p.add_argument('--output',type=Path,default=ROOT/'data/app/word_study_metadata.json')
    args=p.parse_args()
    build(args.deck,args.stopwords,args.morphology,args.output)
