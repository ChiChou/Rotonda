"""Regression checks for PDF parsing and the bank-scoped storage contract."""
import sqlite3
import sys
from pathlib import Path
import unittest
import tempfile
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from extract_pdf_questions import extract
from build_multibank_database import SCHEMA, content_hash
from source_files import read_rows, write_rows, store_image, restore_image


class SourceFileTests(unittest.TestCase):
    def test_csv_preserves_punctuation_unicode_and_optional_figure_links(self):
        rows=[dict(page=0,top=12.25,text='È vietato, anche "qui"\nseconda riga',question_number=31001),
              dict(page=1,top=4.5,text='Logo')]
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'occurrences.csv'
            write_rows(path,rows)
            self.assertEqual(read_rows(path),rows)

    def test_image_round_trip_and_corruption_rejection(self):
        with tempfile.TemporaryDirectory() as folder, patch('source_files.ROOT',Path(folder)):
            data=b'raw image bytes\x00\xff'
            digest=store_image(data,'.png')
            target=Path(folder)/'decoded.png'
            restore_image(target,digest)
            self.assertEqual(target.read_bytes(),data)
            (Path(folder)/'source/images'/f'{digest}.png').write_bytes(b'bad')
            with self.assertRaises(ValueError):
                restore_image(target,digest)

    def test_jpeg_extension_aliases_share_one_source_blob(self):
        with tempfile.TemporaryDirectory() as folder, patch('source_files.ROOT',Path(folder)):
            digest=store_image(b'jpeg bytes','.jpeg')
            store_image(b'jpeg bytes','.jpg')
            self.assertEqual(len(list((Path(folder)/'source/images').iterdir())),1)
            target=Path(folder)/'application.jpeg'
            restore_image(target,digest)
            self.assertEqual(target.read_bytes(),b'jpeg bytes')

class ExtractionTests(unittest.TestCase):
    def test_source_order_survives_nonsequential_group_numbers(self):
        groups,questions,warnings=extract('''Quesito n° 9 - Prima categoria
Numero Testo domanda Risposta Corretta Immagine
31001 Prima domanda VERO
Quesito n° 2 - Seconda categoria
Numero Testo domanda Risposta Corretta Immagine
31002 Seconda domanda FALSO
''')
        ordered=sorted(groups,key=lambda row:row['source_order'])
        self.assertEqual([row['id'] for row in ordered],[9,2])
        self.assertFalse(warnings)

    def test_numeric_continuation_is_prompt_not_id(self):
        groups,questions,warnings=extract('''Quesito n° 1 - Motori
Numero Testo domanda Risposta Corretta Immagine
29284 In un motore Diesel, la marmitta deve essere sostituita ogni due anni o ogni FALSO
               25000 chilometri, perché il nerofumo tende a intasarla
29285 Altro testo VERO
''')
        self.assertFalse(warnings)
        self.assertEqual([q['number'] for q in questions],[29284,29285])
        self.assertTrue(questions[0]['text_it'].endswith('25000 chilometri, perché il nerofumo tende a intasarla'))
        self.assertEqual(questions[0]['answer'],0)

    def test_heading_wraps_across_page_and_answers_wrap(self):
        groups,questions,warnings=extract('''Quesito n° 7 - Prima parte
seconda parte
\fultima parte
Numero Testo domanda Risposta Corretta Immagine
31065 Testo su più
       righe VERO
''')
        self.assertEqual(groups[0]['category'],'Prima parte seconda parte ultima parte')
        self.assertEqual(questions[0]['text_it'],'Testo su più righe')
        self.assertEqual(questions[0]['page'],1)
        self.assertEqual(questions[0]['answer'],1)
        self.assertFalse(warnings)

class SchemaTests(unittest.TestCase):
    def test_content_version_ignores_insertion_order_and_detects_changes(self):
        databases=[]
        for order in [('am','ab'),('ab','am')]:
            db=sqlite3.connect(':memory:');db.executescript(SCHEMA)
            db.executemany('INSERT INTO exam_banks VALUES(?,?,?,?,?)',[(b,b,'conseguimento','it',0) for b in order])
            databases.append(db)
        self.assertEqual(content_hash(databases[0]),content_hash(databases[1]))
        databases[1].execute("UPDATE exam_banks SET title_it='Titolo aggiornato' WHERE id='am'")
        self.assertNotEqual(content_hash(databases[0]),content_hash(databases[1]))
        for db in databases:db.close()

    def test_cross_bank_group_references_are_rejected(self):
        db=sqlite3.connect(':memory:');db.executescript(SCHEMA)
        for bank in ('am','ab'):
            db.execute('INSERT INTO exam_banks VALUES(?,?,?,?,?)',(bank,bank,'conseguimento','it',0))
        db.execute("INSERT INTO content_texts VALUES('text','Testo')")
        db.execute("INSERT INTO chapters VALUES('ab:chapter','ab',1,'Titolo','text')")
        db.execute("INSERT INTO question_groups VALUES('ab:group:1','ab',1,'ab:chapter',1)")
        with self.assertRaises(sqlite3.IntegrityError):
            db.execute("INSERT INTO questions VALUES('am:1','am',1,'ab:group:1','Testo','text',1,1)")
        db.execute("INSERT INTO questions VALUES('ab:1','ab',1,'ab:group:1','Testo','text',1,1)")
        with self.assertRaises(sqlite3.IntegrityError):
            db.execute("INSERT INTO questions VALUES('am:2','ab',2,'ab:group:1','Testo','text',1,1)")
        self.assertEqual(db.execute('SELECT text_en,text_zh FROM localized_questions').fetchone(),(None,None))
        db.execute("INSERT INTO translations VALUES('text','es-419','Texto','gpt-6.1-terra','draft')")
        self.assertEqual(db.execute('SELECT text_es,es_review_status FROM localized_questions').fetchone(),('Texto','draft'))
        self.assertEqual(db.execute("SELECT spanish_count FROM translation_coverage WHERE bank_id='ab'").fetchone(),(1,))
        db.close()

if __name__=='__main__':unittest.main()
