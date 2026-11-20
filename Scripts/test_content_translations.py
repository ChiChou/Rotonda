#!/usr/bin/env python3
"""Check offline Chinese coverage and ensure rebuilds preserve study identifiers."""
import json
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ChineseContentTests(unittest.TestCase):
    def test_new_bank_explanations_require_every_language_and_reach_app(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            banks = folder / 'banks.db'
            banks.write_bytes((ROOT / 'data/app/banks.db').read_bytes())
            ids = folder / 'ids.json'
            ids.write_bytes((ROOT / 'data/app/word_ids.json').read_bytes())
            output = folder / 'content.db'
            with sqlite3.connect(banks) as db:
                number = db.execute("SELECT question_id FROM bank_questions WHERE bank='am' ORDER BY question_id LIMIT 1").fetchone()[0]
                db.execute('DELETE FROM question_explanations WHERE question_id=?', (number,))
                db.execute('INSERT INTO question_explanations VALUES (?,?,?)', (number, 'it', 'Test italiano'))
            command = [sys.executable, str(ROOT / 'Scripts/build_content_db.py'),
                       '--banks', str(banks), '--output', str(output), '--word-ids', str(ids)]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            with sqlite3.connect(output) as db:
                self.assertEqual('', db.execute('SELECT expl_it FROM questions WHERE id=?', (number,)).fetchone()[0])
            with sqlite3.connect(banks) as db:
                db.executemany('INSERT INTO question_explanations VALUES (?,?,?)',
                               [(number, lang, f'Test {lang}') for lang in ('en', 'zh-Hans', 'es-419')])
                corrected = db.execute("SELECT question_id FROM bank_questions WHERE bank='ab' ORDER BY question_id LIMIT 1").fetchone()[0]
                db.execute("UPDATE question_texts SET text='Reviewed source correction', review_status='corrected' WHERE question_id=? AND language='en'", (corrected,))
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            with sqlite3.connect(output) as db:
                self.assertEqual('Test italiano', db.execute('SELECT expl_it FROM questions WHERE id=?', (number,)).fetchone()[0])
                self.assertEqual({'en': 'Test en', 'zh-Hans': 'Test zh-Hans', 'es-419': 'Test es-419'},
                                 dict(db.execute('SELECT language, explanation FROM question_texts WHERE question_id=?', (number,))))
                self.assertEqual('Reviewed source correction', db.execute(
                    "SELECT text FROM question_texts WHERE question_id=? AND language='en'", (corrected,)).fetchone()[0])

    def test_question_images_follow_question_rows(self):
        with sqlite3.connect(ROOT / 'data/app/quiz.db') as source, sqlite3.connect(ROOT / 'Rotonda/Resources/patente.db') as bundled:
            expected = source.execute('SELECT id, image FROM questions ORDER BY id').fetchall()
            actual = bundled.execute("""SELECT q.id, q.image FROM questions q JOIN licence_questions m
                ON m.question_id = q.id AND m.licence = 'ab' ORDER BY q.id""").fetchall()
            self.assertEqual(expected, actual)
            self.assertIsNone(dict(actual)[22863])
            self.assertIsNotNone(dict(actual)[22261])

    def test_every_bundled_word_has_a_chinese_meaning(self):
        with sqlite3.connect(ROOT / 'Rotonda/Resources/patente.db') as db:
            words = db.execute("SELECT w.lemma, t.gloss FROM words w JOIN word_texts t ON t.word_id = w.id AND t.language = 'zh-Hans'").fetchall()
            self.assertGreater(len(words), 3000)
            self.assertEqual([], [lemma for lemma, zh in words if not re.search(r'[\u3400-\u9fff]', zh)])
            self.assertEqual([], [lemma for lemma, zh in words if '\u00b7' in zh])
            self.assertEqual('ok', db.execute('PRAGMA integrity_check').fetchone()[0])
            self.assertEqual([], db.execute('PRAGMA foreign_key_check').fetchall())
            self.assertIn('操作', dict(words)['manovra'])
            self.assertIn('空挡', dict(words)['folle'])
            self.assertIn('指示灯', dict(words)['spia'])
            # Any question with an Italian explanation must also have its helper-language text.
            self.assertEqual(0, db.execute("""SELECT count(*) FROM questions q LEFT JOIN question_texts t
                ON t.question_id = q.id AND t.language = 'zh-Hans' WHERE q.expl_it <> '' AND trim(coalesce(t.explanation, '')) = ''""").fetchone()[0])
            # English and Chinese are complete for every statement, chapter and fact.
            for table, key, columns in [('questions', 'question_id', ['text']), ('chapters', 'chapter_id', ['title']),
                                        ('facts', 'fact_id', ['topic', 'text'])]:
                texts = table[:-1] + '_texts'
                for language in ('en', 'zh-Hans'):
                    for column in columns:
                        with self.subTest(table=table, language=language, column=column):
                            self.assertEqual(0, db.execute(f"""SELECT count(*) FROM {table} x LEFT JOIN {texts} t
                                ON t.{key} = x.id AND t.language = ? WHERE trim(coalesce(t.{column}, '')) = ''""", (language,)).fetchone()[0])

    def test_every_image_is_bundled(self):
        with sqlite3.connect(ROOT / 'Rotonda/Resources/patente.db') as db:
            images = {row[0] for row in db.execute('SELECT image FROM questions WHERE image IS NOT NULL UNION SELECT image FROM groups WHERE image IS NOT NULL')}
        bundled = {path.name for path in (ROOT / 'Rotonda/Resources/StudyImages').iterdir()}
        self.assertEqual(set(), images - bundled)

    def test_spanish_covers_every_official_statement(self):
        with sqlite3.connect(ROOT / 'Rotonda/Resources/patente.db') as db:
            self.assertEqual(['en', 'zh-Hans', 'es-419'], [r[0] for r in db.execute('SELECT code FROM languages ORDER BY position')])
            # Only the 86 A/B statements the current PDF no longer prints lack Spanish.
            missing = db.execute("""SELECT count(*) FROM questions q WHERE NOT EXISTS
                (SELECT 1 FROM question_texts t WHERE t.question_id = q.id AND t.language = 'es-419')""").fetchone()[0]
            self.assertLessEqual(missing, 86)
            fixed = db.execute("SELECT text FROM question_texts WHERE question_id = 20640 AND language = 'es-419'").fetchone()[0]
            self.assertIn('vía muerta', fixed)
            # Accent-insensitive search: "via muerta" finds "vía muerta".
            self.assertTrue(db.execute("SELECT 1 FROM question_texts WHERE language = 'es-419' AND fold LIKE '%via muerta%'").fetchone())

    def test_licences_are_complete(self):
        with sqlite3.connect(ROOT / 'Rotonda/Resources/patente.db') as db:
            licences = [row[0] for row in db.execute('SELECT id FROM licences ORDER BY position')]
            self.assertEqual(['ab', 'am', 'c', 'd', 'cqc_merci', 'cqc_persone', 'revisione_ab', 'revisione_am',
                              'revisione_superiori', 'revisione_cqc_merci', 'revisione_cqc_persone'], licences)
            for licence in licences:
                with self.subTest(licence=licence):
                    questions, chapters, exam = db.execute(
                        'SELECT question_count, chapter_count, exam_questions FROM licences WHERE id = ?', (licence,)).fetchone()
                    self.assertEqual(questions, db.execute('SELECT count(*) FROM licence_questions WHERE licence = ?', (licence,)).fetchone()[0])
                    self.assertEqual(chapters, db.execute('SELECT count(*) FROM chapters WHERE licence = ?', (licence,)).fetchone()[0])
                    self.assertAlmostEqual(exam, db.execute('SELECT sum(exam_quota) FROM chapters WHERE licence = ?', (licence,)).fetchone()[0], places=2)
                    # Membership stays inside the licence's own chapters and groups.
                    self.assertEqual(0, db.execute("""SELECT count(*) FROM licence_questions m
                        LEFT JOIN chapters c ON c.id = m.chapter_id LEFT JOIN groups g ON g.id = m.group_id
                        WHERE m.licence = ? AND (c.licence IS NOT ? OR g.licence IS NOT ? OR g.chapter_id <> m.chapter_id)""",
                        (licence, licence, licence)).fetchone()[0])
                    self.assertGreater(db.execute('SELECT count(*) FROM licence_words WHERE licence = ?', (licence,)).fetchone()[0], 500)
                    self.assertEqual(0, db.execute("SELECT count(*) FROM chapters WHERE licence = ? AND title_it LIKE '%##%'", (licence,)).fetchone()[0])
                    # Every chapter has a title in every helper language.
                    self.assertEqual(0, db.execute("""SELECT count(*) FROM chapters c CROSS JOIN languages l
                        LEFT JOIN chapter_texts t ON t.chapter_id = c.id AND t.language = l.code
                        WHERE c.licence = ? AND trim(coalesce(t.title, '')) = ''""", (licence,)).fetchone()[0])
            # Superiori splits by the exam codes: the goods chapter is C only.
            self.assertTrue(db.execute("SELECT 1 FROM chapters WHERE licence = 'c' AND title_it LIKE 'Responsabilità del conducente in merito%'").fetchone())
            self.assertFalse(db.execute("SELECT 1 FROM chapters WHERE licence = 'd' AND title_it LIKE 'Responsabilità del conducente in merito%'").fetchone())

    def test_rebuild_matches_bundle_and_preserves_ids(self):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            ids = folder / 'ids.json'
            ids.write_bytes((ROOT / 'data/app/word_ids.json').read_bytes())
            output = folder / 'content.db'
            result = subprocess.run([sys.executable, str(ROOT / 'Scripts/build_content_db.py'),
                                     '--output', str(output), '--word-ids', str(ids)],
                                    capture_output=True, text=True)
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual(json.loads((ROOT / 'data/app/word_ids.json').read_text()), json.loads(ids.read_text()))
            with sqlite3.connect(output) as rebuilt, sqlite3.connect(ROOT / 'Rotonda/Resources/patente.db') as bundled:
                tables = bundled.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
                for (table,) in tables:
                    with self.subTest(table=table):
                        self.assertEqual(sorted(bundled.execute(f'SELECT * FROM {table}').fetchall(), key=repr),
                                         sorted(rebuilt.execute(f'SELECT * FROM {table}').fetchall(), key=repr))

            # A future lexicon addition without Chinese must fail the content build.
            source = json.loads((ROOT / 'data/app/word_meanings_zh.json').read_text())
            del source['meanings']['manovra']
            incomplete = folder / 'incomplete.json'
            incomplete.write_text(json.dumps(source, ensure_ascii=False))
            previous_bundle = output.read_bytes()
            result = subprocess.run([sys.executable, str(ROOT / 'Scripts/build_content_db.py'),
                                     '--output', str(output), '--word-ids', str(ids),
                                     '--meanings-zh', str(incomplete)], capture_output=True, text=True)
            self.assertNotEqual(0, result.returncode)
            self.assertIn('Missing Chinese word meanings', result.stderr)
            self.assertIn('manovra', result.stderr)
            self.assertEqual(previous_bundle, output.read_bytes())


if __name__ == '__main__':
    unittest.main()
