"""Corrections extend audited packs only when exact source and independent review agree."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import translation_corrections as corrections
from prepare_bank_translations import text_id


class TranslationCorrectionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.path = self.root / 'translations/corrections/test.json'
        self.path.parent.mkdir(parents=True)
        self.key = text_id('Testo italiano')
        self.draft = dict(rows=[dict(id=self.key, it='Testo italiano', reason='A reviewed meaning correction',
                                    evidence=['Authoritative source'], translations={
                                        'en': dict(current='Old text', proposed='Corrected text')})])
        self.review = dict(status='accepted', issues=[], author='Terra author run', reviewer='Terra reviewer run',
                           draft_sha256=corrections.fingerprint(self.draft), checked_pairs=[[self.key, 'en']])
        self.write()

    def write(self):
        self.path.write_text(json.dumps(dict(draft=self.draft, review=self.review)))

    def test_reviewed_correction_changes_only_target_language(self):
        texts = {'en': {self.key: 'Old text'}, 'zh-Hans': {self.key: '原文'}}
        applied = corrections.apply_corrections(texts, {self.key: 'Testo italiano'}, root=self.root)
        self.assertEqual(applied, [(self.key, 'en', 'Corrected text')])
        self.assertEqual(texts['en'][self.key], 'Corrected text')
        self.assertEqual(texts['zh-Hans'][self.key], '原文')

    def test_changed_baseline_and_missing_italian_are_rejected(self):
        for texts, sources in [({'en': {self.key: 'New source'}}, {self.key: 'Testo italiano'}),
                               ({'en': {self.key: 'Old text'}}, {})]:
            with self.assertRaisesRegex(ValueError, 'Stale translation correction'):
                corrections.apply_corrections(texts, sources, root=self.root)

    def test_self_review_and_edited_draft_are_rejected(self):
        original = copy.deepcopy(self.review)
        self.review['reviewer'] = self.review['author']
        self.write()
        with self.assertRaisesRegex(ValueError, 'independent review'):
            list(corrections.corrections(self.root))
        self.review = original
        self.draft['rows'][0]['translations']['en']['proposed'] = 'Unreviewed text'
        self.write()
        with self.assertRaisesRegex(ValueError, 'exact draft'):
            list(corrections.corrections(self.root))


if __name__ == '__main__':
    unittest.main()
