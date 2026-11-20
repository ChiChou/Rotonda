"""Spanish review must bind source wording, final CSV and correction history."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from source_files import read_rows, write_rows
from spanish_review import file_hash, record_review, validate_batch


class SpanishReviewTests(unittest.TestCase):
    def test_sealed_review_rejects_changed_spanish_source_and_history(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            baseline = root / 'baseline'
            path = root / 'translations/es-419/000.csv'
            row = dict(id='source', text='Puede estacionar.', origin='gpt-6.1-terra', review_status='draft')
            write_rows(path, [row])
            write_rows(baseline / path.name, [row])
            report_path = root / 'reviews/spanish-review/000.json'
            report_path.parent.mkdir(parents=True)
            (report_path.parent / 'baseline.json').write_text(json.dumps(dict(files={path.name: file_hash(path)})))
            needed = {'source': dict(id='source', it='Non può sostare.')}
            row['text'] = 'No puede estacionar.'
            write_rows(path, [row])
            with patch('spanish_review.ROOT', root), patch('spanish_review.BASELINE', baseline), patch('spanish_translations.sources', return_value=needed):
                record_review(0, '/root/test_reviewer', {'source': 'Restore the negation omitted from the draft.'})
                rows = read_rows(path)
                self.assertIsNotNone(validate_batch(path, rows, needed))
                changed_source = {'source': dict(id='source', it='Può sostare.')}
                with self.assertRaisesRegex(ValueError, 'Italian source changed'):
                    validate_batch(path, rows, changed_source)
                report = json.loads(report_path.read_text())
                report['corrections'][0]['before'] = 'Fabricated earlier wording.'
                report_path.write_text(json.dumps(report))
                with self.assertRaisesRegex(ValueError, 'does not reconstruct'):
                    validate_batch(path, rows, needed)
                rows[0]['text'] = 'Changed after review.'
                write_rows(path, rows)
                with self.assertRaisesRegex(ValueError, 'Spanish wording changed'):
                    validate_batch(path, rows, needed)

    def test_reviewed_status_without_evidence_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / '000.csv'
            rows = [dict(id='source', text='Texto', origin='gpt-6.1-terra', review_status='reviewed')]
            write_rows(path, rows)
            with patch('spanish_review.ROOT', root):
                with self.assertRaisesRegex(ValueError, 'requires batch review evidence'):
                    validate_batch(path, rows, {'source': dict(it='Testo')} )


if __name__ == '__main__':
    unittest.main()
