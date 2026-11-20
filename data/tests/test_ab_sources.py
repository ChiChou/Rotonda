import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from source_files import restore_ab


class CanonicalABTests(unittest.TestCase):
    def test_restore_rebuilds_from_current_rows(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = root / 'source/banks/ab'
            folder.mkdir(parents=True)
            (root/'app').mkdir()
            (root/'app/ab_compatibility.json').write_text('{"assets":[],"question_images":{},"group_images":{}}')
            (folder / 'groups.csv').write_text('id,category,image,page\n1,Signals,,0\n')
            questions = folder / 'questions.csv'
            questions.write_text('number,quesito_id,text_it,answer,image,page\n10,1,First,1,,0\n')
            with patch('source_files.ROOT', root):
                restore_ab(root / "input.db")
                questions.write_text('number,quesito_id,text_it,answer,image,page\n10,1,Updated,1,,0\n')
                restore_ab(root / "input.db")
            with sqlite3.connect(root / 'input.db') as db:
                self.assertEqual(('Updated', None), db.execute('SELECT text_it,image FROM questions').fetchone())


if __name__ == '__main__':
    unittest.main()
