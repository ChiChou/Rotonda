"""Reviewed status must stop being valid when verified wording changes."""
import sys
from pathlib import Path
import unittest
import tempfile
import json
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from translation_review import reviewed_content_hash, validate_review, validate_batch_report

class TranslationReviewTests(unittest.TestCase):
    def reviewed_row(self):
        row=dict(id='test',it='Non è consentito.',en='It is not permitted.',zh='不允许。',review_status='reviewed',
            reviewer='gpt-6.1-terra',reviewer_agent='/root/review_test',reviewed_on='2026-11-14')
        row['reviewed_content_sha256']=reviewed_content_hash(row)
        return row

    def test_changed_english_or_chinese_invalidates_review(self):
        for language in ('en','zh'):
            row=self.reviewed_row()
            self.assertTrue(validate_review(row))
            row[language]='Changed target wording'
            with self.assertRaisesRegex(ValueError,'changed after semantic review'):
                validate_review(row)

    def test_reviewed_marker_requires_evidence(self):
        row=self.reviewed_row();del row['reviewer_agent']
        with self.assertRaisesRegex(ValueError,'lacks reviewer provenance'):
            validate_review(row)
        self.assertFalse(validate_review(dict(id='draft',review_status='draft')))

    def test_sealed_row_without_batch_review_evidence_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);path=root/'batch_000.jsonl';row=self.reviewed_row()
            path.write_text(json.dumps(row)+'\n')
            with patch('translation_review.ROOT',root):
                with self.assertRaisesRegex(ValueError,'require per-batch semantic review evidence'):
                    validate_batch_report(path,[row])

if __name__=='__main__':unittest.main()
