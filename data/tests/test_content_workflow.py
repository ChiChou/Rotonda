"""Regression checks for manual intake and source-bound explanation review."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import content_workflow as workflow
from verify_official_pdfs import verify


class ManualInputTests(unittest.TestCase):
    def test_missing_wrong_and_changed_originals_fail_without_mutation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            data = b'%PDF-1.7\noriginal test fixture'
            bank = dict(id='am', pdf='original.pdf', url='https://example.test/original',
                        bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
            with self.assertRaisesRegex(ValueError, 'manually place'):
                verify(bank, root)
            self.assertFalse(list(root.iterdir()))
            path = root / bank['pdf']
            path.write_bytes(data)
            self.assertEqual(verify(bank, root), path)
            path.write_bytes(data.replace(b'original', b'altered!'))
            with self.assertRaisesRegex(ValueError, 'pinned edition'):
                verify(bank, root)
            self.assertNotEqual(path.read_bytes(), data)
            path.write_bytes(b'not a pdf')
            with self.assertRaisesRegex(ValueError, 'not a PDF'):
                verify(bank, root)


class ExplanationReviewTests(unittest.TestCase):
    def setUp(self):
        self.source = dict(number=12345, text_it='Testo italiano', answer=0, page=0,
                           bank='am', pdf_sha256='pdf', figures=[])
        self.task = dict(stage='explain', bank='am', language='en', records=[dict(
            source=copy.deepcopy(self.source), source_sha256=workflow.fingerprint(self.source),
            localized_text='English statement')])
        self.task['task_sha256'] = workflow.fingerprint(self.task)
        self.rows = [dict(number=12345, text='A specific explanation.', evidence=['Source, section 1: supporting rule'])]
        self.review = dict(task_sha256=self.task['task_sha256'], output_sha256=workflow.fingerprint(self.rows),
                           author='test author', reviewer='independent test reviewer', status='accepted', checked_numbers=[12345], issues=[])
        self.patches = [patch.object(workflow, 'selected_banks', return_value=[dict(id='am')]),
                        patch.object(workflow, 'question_sources', side_effect=lambda _: [self.source]),
                        patch.object(workflow, 'translations', return_value={
                            'en': {workflow.text_id(self.source['text_it']): 'English statement'}})]
        for mocked in self.patches:
            mocked.start()
            self.addCleanup(mocked.stop)

    def check(self):
        return workflow.validate_explanations(self.task, self.rows, self.review)

    def test_complete_matching_review_is_accepted(self):
        self.assertEqual(set(self.check()), {12345})

    def test_author_cannot_accept_own_output(self):
        self.review['reviewer'] = self.review['author']
        with self.assertRaisesRegex(ValueError, 'Review must'):
            self.check()

    def test_source_answer_and_figure_changes_invalidate_review(self):
        original = copy.deepcopy(self.source)
        for field, value in [('text_it', 'Changed'), ('answer', 1), ('figures', [{'sha256': 'changed'}])]:
            with self.subTest(field=field):
                self.source.clear()
                self.source.update(original)
                self.source[field] = value
                with self.assertRaisesRegex(ValueError, 'Stale'):
                    self.check()

    def test_translation_change_invalidates_review(self):
        with patch.object(workflow, 'translations', return_value={'en': {workflow.text_id(self.source['text_it']): 'Changed'}}):
            with self.assertRaisesRegex(ValueError, 'Stale localized'):
                self.check()

    def test_edited_draft_and_partial_review_fail(self):
        self.rows[0]['text'] = 'Unreviewed edit'
        with self.assertRaisesRegex(ValueError, 'Review must'):
            self.check()
        self.review['output_sha256'] = workflow.fingerprint(self.rows)
        self.review['checked_numbers'] = []
        with self.assertRaisesRegex(ValueError, 'Review must'):
            self.check()

    def test_duplicates_missing_ids_and_missing_evidence_fail(self):
        for rows in [[], self.rows * 2, [dict(number=99999, text='x', evidence=['x'])],
                     [dict(number=12345, text='x', evidence=[])]]:
            with self.subTest(rows=rows):
                with self.assertRaises(ValueError):
                    workflow.validate_explanations(self.task, rows, self.review)

    def test_accept_retains_evidence_and_build_revalidates_text(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(workflow, 'ROOT', Path(temporary)):
            root = Path(temporary)
            paths = [root / name for name in ('task.json', 'draft.jsonl', 'review.json')]
            for path, data in zip(paths, [self.task, self.rows[0], self.review]):
                path.write_text(json.dumps(data) + '\n')
            workflow.accept(*paths)
            self.assertEqual(workflow.load_explanation_rows(), [('am:12345', 'en', self.rows[0]['text'])])
            accepted = root / 'explanations/am/en.jsonl'
            row = json.loads(accepted.read_text())
            row['text'] = 'Tampered explanation'
            accepted.write_text(json.dumps(row) + '\n')
            with self.assertRaisesRegex(ValueError, 'no longer matches'):
                workflow.load_explanation_rows()

    def test_changed_statement_only_invalidates_its_own_row(self):
        other = dict(self.source, number=67890, text_it='Altro testo')
        sources = [self.source, other]
        self.task['records'].append(dict(source=copy.deepcopy(other), source_sha256=workflow.fingerprint(other),
                                         localized_text='Other statement'))
        self.task['task_sha256'] = workflow.fingerprint({k: v for k, v in self.task.items() if k != 'task_sha256'})
        self.rows.append(dict(number=67890, text='Another explanation.', evidence=['Source, section 2: rule']))
        self.review.update(task_sha256=self.task['task_sha256'], output_sha256=workflow.fingerprint(self.rows),
                           checked_numbers=[12345, 67890])
        current = {workflow.text_id(self.source['text_it']): 'English statement',
                   workflow.text_id(other['text_it']): 'Revised other statement'}
        with tempfile.TemporaryDirectory() as temporary, patch.object(workflow, 'ROOT', Path(temporary)), \
             patch.object(workflow, 'question_sources', side_effect=lambda _: sources), \
             patch.object(workflow, 'translations', return_value={'en': current}):
            root = Path(temporary)
            evidence = root / 'reviews/explanations/am/en/batch.json'
            evidence.parent.mkdir(parents=True)
            evidence.write_text(json.dumps(dict(task=self.task, rows=self.rows, review=self.review)))
            pack = root / 'explanations/am/en.jsonl'
            pack.parent.mkdir(parents=True)
            def write(numbers):
                pack.write_text(''.join(json.dumps(dict(number=r['number'], text=r['text'],
                    source_sha256=workflow.fingerprint(s), review='reviews/explanations/am/en/batch.json')) + '\n'
                    for r, s in zip(self.rows, sources) if r['number'] in numbers))
            write({12345, 67890})
            with self.assertRaisesRegex(ValueError, 'Stale localized source: 67890'):
                workflow.load_explanation_rows()
            write({12345})
            self.assertEqual(workflow.load_explanation_rows(), [('am:12345', 'en', self.rows[0]['text'])])


class ReuseTests(unittest.TestCase):
    def test_same_question_can_retain_translations_of_distinct_italian_versions(self):
        banks=[dict(id='ab'),dict(id='old')]
        source=dict(number=1,text_it='Same assertion',answer=1,figures=[])
        def pack(bank,language):
            if language not in ('it','en'):return {}
            row=dict(number=1,text=bank+' '+language)
            if bank=='old' and language=='it':row['reuse']=dict(bank='ab',number=2)
            return {1:row}
        with tempfile.TemporaryDirectory() as temporary, patch.object(workflow,'ROOT',Path(temporary)), \
             patch.object(workflow,'selected_banks',return_value=banks), \
             patch.object(workflow,'question_sources',return_value=[source]), \
             patch.object(workflow,'explanations',side_effect=pack), \
             patch.object(workflow,'load_explanation_rows',return_value=[]):
            self.assertEqual(workflow.materialize_reuse(),0)

    def test_helper_reuse_cannot_translate_a_different_italian_baseline(self):
        sources=[dict(number=n,text_it='Same assertion',answer=1,figures=[]) for n in (1,2)]
        with tempfile.TemporaryDirectory() as temporary, patch.object(workflow,'ROOT',Path(temporary)), \
             patch.object(workflow,'selected_banks',return_value=[dict(id='ab')]), \
             patch.object(workflow,'question_sources',return_value=sources):
            folder=Path(temporary)/'explanations/ab';folder.mkdir(parents=True)
            (folder/'it.jsonl').write_text('\n'.join(json.dumps(dict(number=n,text=text)) for n,text in [(1,'First Italian version'),(2,'Different Italian version')])+'\n')
            (folder/'en.jsonl').write_text(json.dumps(dict(number=1,text='Translation of first version'))+'\n')
            self.assertEqual(workflow.reuse_identical_content(),0)
            self.assertEqual(set(workflow.explanations('ab','en')),{1})

    def test_typography_normalization_preserves_negation_and_quantities(self):
        row=dict(number=1,text_it='L’auto  non supera 30 km/h',answer=1,figures=[])
        equivalent=dict(row,number=2,text_it="L'auto non supera 30 km/h")
        self.assertEqual(workflow.content_identity(row,True),workflow.content_identity(equivalent,True))
        self.assertNotEqual(workflow.content_identity(row,True),workflow.content_identity(dict(equivalent,text_it="L'auto supera 30 km/h"),True))
        self.assertNotEqual(workflow.content_identity(row,True),workflow.content_identity(dict(equivalent,text_it="L'auto non supera 50 km/h"),True))

    def test_renumbered_reuse_requires_exact_text_answer_and_figures(self):
        banks=[dict(id='ab'),dict(id='target')]
        original=dict(number=1,text_it='Same assertion',answer=1,figures=[])
        sources={'ab':[original],'target':[dict(original,number=2),dict(original,number=3,answer=0)]}
        with tempfile.TemporaryDirectory() as temporary, patch.object(workflow,'ROOT',Path(temporary)), \
             patch.object(workflow,'selected_banks',return_value=banks), \
             patch.object(workflow,'question_sources',side_effect=lambda b:sources[b['id']]):
            donor=Path(temporary)/'explanations/ab/it.jsonl'
            donor.parent.mkdir(parents=True)
            donor.write_text(json.dumps(dict(number=1,text='Existing reasoning'))+'\n')
            self.assertEqual(workflow.reuse_identical_content(),1)
            rows=workflow.explanations('target','it')
            self.assertEqual(set(rows),{2})
            self.assertEqual(rows[2]['reuse'],dict(bank='ab',number=1,match='exact-content'))
            sources['target'][0]['figures']=[dict(sha256='changed')]
            with self.assertRaisesRegex(ValueError,'Stale or nonidentical'):
                workflow.load_explanation_rows()

    def test_reuse_retains_provenance_and_rejects_changed_answer_or_text(self):
        banks = [dict(id='ab'), dict(id='revisione_ab')]
        base = dict(number=12345, text_it='Testo', answer=1, figures=[], page=0)
        sources = {b['id']: [dict(base, bank=b['id'], pdf_sha256=b['id'])] for b in banks}
        with tempfile.TemporaryDirectory() as temporary, patch.object(workflow, 'ROOT', Path(temporary)), \
                patch.object(workflow, 'selected_banks', return_value=banks), \
                patch.object(workflow, 'question_sources', side_effect=lambda b: sources[b['id']]):
            root = Path(temporary)
            donor = root / 'explanations/ab/en.jsonl'
            donor.parent.mkdir(parents=True)
            donor.write_text(json.dumps(dict(number=12345, text='Accepted legacy explanation')) + '\n')
            (donor.parent/'it.jsonl').write_text(json.dumps(dict(number=12345,text='Italian baseline'))+'\n')
            target_it=root/'explanations/revisione_ab/it.jsonl'
            target_it.parent.mkdir(parents=True)
            target_it.write_text(json.dumps(dict(number=12345,text='Italian baseline',
                source_sha256=workflow.fingerprint(sources['revisione_ab'][0]),reuse=dict(bank='ab',number=12345)))+'\n')
            self.assertEqual(workflow.materialize_reuse(), 1)
            target = root / 'explanations/revisione_ab/en.jsonl'
            row = json.loads(target.read_text())
            self.assertEqual(row['reuse'], dict(bank='ab', number=12345,italian_sha256=workflow.fingerprint('Italian baseline')))
            self.assertEqual(len(workflow.load_explanation_rows()), 4)
            sources['revisione_ab'][0]['answer'] = 0
            with self.assertRaisesRegex(ValueError, 'Stale or nonidentical'):
                workflow.load_explanation_rows()
            sources['revisione_ab'][0]['answer'] = 1
            row['text'] = 'Unreviewed modification'
            target.write_text(json.dumps(row) + '\n')
            with self.assertRaisesRegex(ValueError, 'Stale or nonidentical'):
                workflow.load_explanation_rows()

    def test_cyclic_reuse_is_rejected(self):
        banks = [dict(id='ab'), dict(id='revisione_ab')]
        source = dict(number=12345, text_it='Testo', answer=1, figures=[])
        with tempfile.TemporaryDirectory() as temporary, patch.object(workflow, 'ROOT', Path(temporary)), \
                patch.object(workflow, 'selected_banks', return_value=banks), \
                patch.object(workflow, 'question_sources', return_value=[source]):
            for bank, donor in [('ab', 'revisione_ab'), ('revisione_ab', 'ab')]:
                path = Path(temporary) / 'explanations' / bank / 'en.jsonl'
                path.parent.mkdir(parents=True)
                path.write_text(json.dumps(dict(number=12345, text='x', source_sha256=workflow.fingerprint(source),
                                                reuse=dict(bank=donor, number=12345))) + '\n')
            with self.assertRaisesRegex(ValueError, 'Cyclic'):
                workflow.load_explanation_rows()


if __name__ == '__main__':
    unittest.main()
