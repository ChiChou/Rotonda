import sys
import tempfile
import json
import types
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import run_explanation_batches as runner


class BatchTests(unittest.TestCase):
    def test_model_call_limit_is_shared_across_workers(self):
        with tempfile.TemporaryDirectory() as tmp:
            control = runner.RunControl(Path(tmp), 3)
            def attempt(_):
                try:
                    control.reserve()
                    return True
                except runner.DispatchLimit:
                    return False
            with runner.concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                self.assertEqual(sum(pool.map(attempt, range(20))), 3)
            self.assertEqual(json.loads((Path(tmp) / 'dispatch-budget.json').read_text())['started_model_runs'], 3)
            with patch.object(runner, 'RUN_CONTROL', control), patch.object(runner.subprocess, 'run') as model:
                with self.assertRaises(runner.DispatchLimit):
                    runner.run_codex('prompt', Path(tmp), 'author-0', 1)
                model.assert_not_called()

    def test_pause_prevents_planning_and_model_dispatch(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            (base / 'PAUSED').write_text('User requested pause')
            control = runner.RunControl(base, 2)
            with self.assertRaises(runner.DispatchLimit):
                control.reserve()
            self.assertEqual(control.started, 0)
            with patch.object(sys, 'argv', ['runner', '--state-dir', tmp, '--execute']), \
                 patch.object(runner, 'plan_batches') as plan, \
                 patch.object(runner.subprocess, 'run') as model:
                with self.assertRaises(SystemExit) as stopped:
                    runner.main()
                self.assertEqual(stopped.exception.code, 2)
                plan.assert_not_called()
                model.assert_not_called()

    def test_usage_summary_excludes_drafts_and_incomplete_events(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            folder = base / 'batch'
            folder.mkdir()
            event = {'type': 'turn.completed', 'usage': {
                'input_tokens': 100, 'cached_input_tokens': 80, 'output_tokens': 7}}
            (folder / 'author-0.jsonl').write_text(json.dumps(event) + '\n' + '{"type":"turn.completed"')
            (folder / 'reviewer-0.jsonl').write_text(json.dumps(event) + '\n')
            (folder / 'draft-it.jsonl').write_text(json.dumps(event) + '\n')
            report = runner.usage_summary(base)
            self.assertEqual(report['completed_runs'], {'author': 1, 'reviewer': 1})
            self.assertEqual(report['uncached_input_tokens'], 40)
            self.assertEqual(report['reported_usage']['output_tokens'], 14)

    def test_resume_keeps_original_boundary_and_excludes_replanned_duplicates(self):
        bank = dict(id='a', pdf='a.pdf', sha256='pdf')
        rows = [dict(number=n, text_it=str(n), answer='0', figures=[], bank='a') for n in range(1, 7)]
        accepted = set()
        localized = {lang: {runner.text_id(str(n)): str(n) for n in range(1, 7)} for lang in runner.wf.LANGUAGES}
        def existing(bank_id, language):
            return {n: {'text': f'{language}-{n}'} for n in accepted}
        with tempfile.TemporaryDirectory() as tmp, \
             patch.object(runner.wf, 'selected_banks', return_value=[bank]), \
             patch.object(runner.wf, 'question_sources', side_effect=lambda b: rows), \
             patch.object(runner.wf, 'translations', return_value=localized), \
             patch.object(runner.wf, 'reusable_ab', return_value={}), \
             patch.object(runner.wf, 'explanations', side_effect=existing):
            base = Path(tmp)
            original = list(runner.make_batches(2, None))
            self.write_manifest(base, original[1])
            accepted.update((1, 2))
            planned = runner.plan_batches(base, None, 2, 3)
            self.assertEqual(planned[0], original[1])
            numbers = [[r['source']['number'] for r in b['tasks'][0]['records']] for b in planned]
            self.assertEqual(numbers, [[3, 4], [5, 6]])
            self.assertEqual(runner.plan_batches(base, None, 2, 1), [original[1]])

    def test_manual_acceptance_and_stale_source_force_replanning(self):
        bank = dict(id='a', pdf='a.pdf', sha256='pdf')
        rows = [dict(number=n, text_it=str(n), answer='0', figures=[], bank='a') for n in (1, 2)]
        accepted = set()
        localized = {lang: {runner.text_id(str(n)): str(n) for n in (1, 2)} for lang in runner.wf.LANGUAGES}
        def existing(bank_id, language):
            return {n: {'text': f'{language}-{n}'} for n in accepted}
        with tempfile.TemporaryDirectory() as tmp, \
             patch.object(runner.wf, 'selected_banks', return_value=[bank]), \
             patch.object(runner.wf, 'question_sources', side_effect=lambda b: rows), \
             patch.object(runner.wf, 'translations', return_value=localized), \
             patch.object(runner.wf, 'reusable_ab', return_value={}), \
             patch.object(runner.wf, 'explanations', side_effect=existing):
            base = Path(tmp)
            original = list(runner.make_batches(2, None))[0]
            self.write_manifest(base, original)
            accepted.add(1)
            replanned = runner.plan_batches(base, None, 2, 1)
            self.assertNotEqual(replanned[0], original)
            self.assertEqual([r['source']['number'] for r in replanned[0]['tasks'][0]['records']], [2])
            accepted.clear()
            rows[1] = dict(rows[1], answer='1')
            replanned = runner.plan_batches(base, None, 2, 1)
            self.assertNotEqual(replanned[0], original)
            self.assertEqual(replanned[0]['tasks'][0]['records'][1]['source']['answer'], '1')

    def test_translation_change_and_size_limit_reject_old_manifest(self):
        bank = dict(id='a', pdf='a.pdf', sha256='pdf')
        rows = [dict(number=n, text_it=str(n), answer='0', figures=[], bank='a') for n in (1, 2)]
        localized = {lang: {runner.text_id(str(n)): str(n) for n in (1, 2)} for lang in runner.wf.LANGUAGES}
        with tempfile.TemporaryDirectory() as tmp, \
             patch.object(runner.wf, 'selected_banks', return_value=[bank]), \
             patch.object(runner.wf, 'question_sources', return_value=rows), \
             patch.object(runner.wf, 'translations', return_value=localized), \
             patch.object(runner.wf, 'reusable_ab', return_value={}), \
             patch.object(runner.wf, 'explanations', return_value={}):
            base = Path(tmp)
            original = list(runner.make_batches(2, None))[0]
            self.write_manifest(base, original)
            self.assertEqual(runner.resume_batches(base, None, 1), [])
            localized['en'][runner.text_id('1')] = 'new translation'
            self.assertEqual(runner.resume_batches(base, None, 2), [])
            new = runner.plan_batches(base, None, 2, 1)[0]
            self.assertNotEqual(new, original)
            self.assertEqual(next(t for t in new['tasks'] if t['language'] == 'en')['records'][0]['localized_text'], 'new translation')

    @staticmethod
    def write_manifest(base, batch):
        batch_hash = runner.wf.fingerprint(batch)
        folder = base / batch_hash
        folder.mkdir()
        items = []
        for task in batch['tasks']:
            path = folder / ('task-' + task['task_sha256'] + '.json')
            path.write_text(json.dumps(task))
            items.append({'task': str(path), 'draft': str(folder / ('draft-' + task['task_sha256'] + '.jsonl')),
                          'review': str(folder / ('review-' + task['task_sha256'] + '.json'))})
        (folder / 'manifest.json').write_text(json.dumps({'batch_sha256': batch_hash,
            'identities': batch['identities'], 'tasks': items}))

    def test_identity_requires_number_answer_and_figure_bytes(self):
        row = {'number': '1', 'text_it': 'Test', 'answer': '0', 'figures': [{'sha256': 'a'}]}
        key = runner.identity(row)
        for field, value in [('number', '2'), ('answer', '1'), ('text_it', 'Other'),
                             ('figures', [{'sha256': 'b'}])]:
            self.assertNotEqual(key, runner.identity(dict(row, **{field: value})))
        self.assertEqual(key, runner.identity(dict(row, figures=[{'sha256': 'a'}, {'sha256': 'a'}])))

    def test_process_guard_blocks_model_until_explicit_retry(self):
        row = {'number': 1, 'text_it': 'A', 'answer': '0', 'figures': []}
        record = dict(source=row, source_sha256=runner.wf.fingerprint(row), localized_text='A')
        task = dict(schema_version=1, stage='explain', bank='a', language='it', pdf='a.pdf',
                    pdf_sha256='pdf', model=runner.MODEL, records=[record])
        task['task_sha256'] = runner.wf.fingerprint(task)
        batch = dict(identities={runner.identity(row): {}}, tasks=[task])
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            self.write_manifest(base, batch)
            folder = base / runner.wf.fingerprint(batch)
            (folder / 'status.json').write_text(json.dumps({'status':'source_adjudication',
                'report':{'kind':'source_ambiguity','issues':[{'number':1,'reason':'ambiguous',
                                                               'checked_sources':['source']}]}}))
            with patch.object(runner, 'author_complete', side_effect=RuntimeError('author launched')) as author, \
                 patch.object(runner, 'run_codex') as model:
                _, result = runner.process(batch, base, 0, 1)
                self.assertIn('blocked: source adjudication', result)
                author.assert_not_called()
                model.assert_not_called()
                with self.assertRaisesRegex(RuntimeError, 'author launched'):
                    runner.process(batch, base, 0, 1, retry_source_blocked=True)
                author.assert_called_once()

    def test_rebatch_preserves_block_until_source_or_translation_changes(self):
        rows = [dict(number=n, text_it=str(n), answer='0', figures=[]) for n in (1, 2)]
        def batch_for(sources, translation='translated'):
            records = [dict(source=r, source_sha256=runner.wf.fingerprint(r), localized_text=translation) for r in sources]
            task = dict(schema_version=1, stage='explain', bank='a', language='en', pdf='a',
                        pdf_sha256='p', model=runner.MODEL, records=records)
            task['task_sha256'] = runner.wf.fingerprint(task)
            return dict(identities={runner.identity(r): {} for r in sources}, tasks=[task])
        original = batch_for(rows)
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            self.write_manifest(base, original)
            folder = base / runner.wf.fingerprint(original)
            (folder / 'status.json').write_text(json.dumps({'status':'source_adjudication',
                'report':{'issues':[{'number':2,'reason':'ambiguous','checked_sources':['source']}]}}))
            rebatch = batch_for([rows[1]])
            with patch.object(runner, 'author_complete') as author:
                self.assertIn('source adjudication', runner.process(rebatch, base, 0, 1)[1])
                author.assert_not_called()
            self.assertIsNone(runner.blocked_source_match(batch_for([rows[0]]), base))
            self.assertIsNone(runner.blocked_source_match(batch_for([dict(rows[1], answer='1')]), base))
            self.assertIsNone(runner.blocked_source_match(batch_for([rows[1]], 'changed'), base))

    def test_valid_source_blocker_stops_without_continuations_and_keeps_provenance(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            task, draft = folder / 'task.json', folder / 'draft.jsonl'
            task.write_text(json.dumps({'records': [{'source': {'number': 1}}, {'source': {'number': 2}}]}))
            manifest = {'tasks': [{'task': str(task), 'draft': str(draft)}]}
            def fake_run(prompt, folder, label, timeout, figures):
                (folder / f'{label}-input.json').write_text('{"model":"gpt-6.1-terra"}')
                draft.write_text(json.dumps({'number': 1, 'text': 'one', 'evidence': ['source']}) + '\n')
                (folder / f'{label}-blocker.json').write_text(json.dumps({'kind':'source_ambiguity','issues':[
                    {'number':2,'reason':'Printed answer conflicts with source wording','checked_sources':['PDF p. 1 and law art. 2']}]}))
                return 'real-run-id'
            with patch.object(runner, 'run_codex', side_effect=fake_run) as run:
                with self.assertRaises(runner.SourceBlocker):
                    runner.author_complete(manifest, folder, 'prompt', [], 1, 0)
            self.assertEqual(run.call_count, 1)
            self.assertEqual(json.loads((folder / 'status.json').read_text())['status'], 'source_adjudication')
            record = json.loads((folder / 'author-0-0-source-blocker-record.json').read_text())
            self.assertEqual(record['run_id'], 'real-run-id')
            self.assertEqual(record['report']['issues'][0]['number'], 2)
            self.assertEqual(runner.source_blocker_history(folder), [record])
            self.assertEqual(len((folder / 'author-0-0-drafts' / draft.name).read_text().splitlines()), 1)

    def test_invalid_or_unassigned_blocker_does_not_skip_retries(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            task, draft = folder / 'task.json', folder / 'draft.jsonl'
            task.write_text(json.dumps({'records':[{'source':{'number':1}}]}))
            manifest = {'tasks':[{'task':str(task),'draft':str(draft)}]}
            def fake_run(prompt, folder, label, timeout, figures):
                (folder / f'{label}-input.json').write_text('{}')
                (folder / f'{label}-blocker.json').write_text(json.dumps({'kind':'source_ambiguity','issues':[
                    {'number':999,'reason':'not assigned','checked_sources':['source']}]}))
                return label
            with patch.object(runner, 'run_codex', side_effect=fake_run) as run:
                with self.assertRaisesRegex(ValueError, 'bounded author continuations'):
                    runner.author_complete(manifest, folder, 'prompt', [], 1, 0, max_resumptions=2)
            self.assertEqual(run.call_count, 3)
            self.assertEqual(json.loads((folder / 'status.json').read_text())['status'], 'incomplete')
            self.assertEqual(len(list(folder.glob('*-blocker-stale-*.json'))), 3)

    def test_stale_blocker_cannot_block_later_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            task, draft = folder / 'task.json', folder / 'draft.jsonl'
            task.write_text(json.dumps({'records':[{'source':{'number':1}}]}))
            manifest = {'tasks':[{'task':str(task),'draft':str(draft)}]}
            stale = folder / 'author-0-0-blocker.json'
            stale.write_text(json.dumps({'kind':'source_ambiguity','issues':[{'number':1,'reason':'stale',
                                                                            'checked_sources':['old']}]}))
            def fake_run(prompt, folder, label, timeout, figures):
                self.assertFalse(stale.exists())
                (folder / f'{label}-input.json').write_text('{}')
                draft.write_text(json.dumps({'number':1,'text':'complete','evidence':['source']})+'\n')
                return 'fresh'
            with patch.object(runner, 'run_codex', side_effect=fake_run):
                self.assertEqual(runner.author_complete(manifest, folder, 'prompt', [], 1, 0)[-1]['run_id'], 'fresh')
            self.assertTrue((folder / 'author-0-0-blocker-stale-0.json').exists())
            self.assertFalse((folder / 'author-0-0-source-blocker-record.json').exists())

    def test_author_continues_partial_draft_and_preserves_attempts(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            task, draft = folder / 'task.json', folder / 'draft.jsonl'
            task.write_text(json.dumps({'records': [{'source': {'number': 1}}, {'source': {'number': 2}}]}))
            manifest = {'tasks': [{'task': str(task), 'draft': str(draft)}]}
            prompts = []
            def fake_run(prompt, folder, label, timeout, figures):
                prompts.append(prompt)
                (folder / f'{label}-input.json').write_text('{}')
                rows = [{'number': 1, 'text': 'one', 'evidence': ['source']}]
                if len(prompts) > 1:
                    rows.append({'number': 2, 'text': 'two', 'evidence': ['source']})
                draft.write_text(''.join(json.dumps(row) + '\n' for row in rows))
                return f'run-{len(prompts)}'
            with patch.object(runner, 'run_codex', side_effect=fake_run):
                history = runner.author_complete(manifest, folder, 'initial', [], 1, 0)
            self.assertEqual([row['run_id'] for row in history], ['run-1', 'run-2'])
            self.assertIn('"missing_numbers": [2]', prompts[1])
            self.assertEqual(len((folder / 'author-0-0-drafts' / draft.name).read_text().splitlines()), 1)
            self.assertEqual(len((folder / 'author-0-1-drafts' / draft.name).read_text().splitlines()), 2)

    def test_malformed_draft_stops_after_bounded_continuations(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            task, draft = folder / 'task.json', folder / 'draft.jsonl'
            task.write_text(json.dumps({'records': [{'source': {'number': 1}}]}))
            manifest = {'tasks': [{'task': str(task), 'draft': str(draft)}]}
            def fake_run(prompt, folder, label, timeout, figures):
                (folder / f'{label}-input.json').write_text('{}')
                draft.write_text('{bad json')
                return label
            with patch.object(runner, 'run_codex', side_effect=fake_run) as run:
                with self.assertRaisesRegex(ValueError, 'bounded author continuations'):
                    runner.author_complete(manifest, folder, 'initial', [], 1, 0, max_resumptions=3)
            self.assertEqual(run.call_count, 4)
            self.assertEqual(json.loads((folder / 'status.json').read_text())['status'], 'incomplete')

    def test_author_prompt_confirms_launcher_model_and_full_scope(self):
        prompt = runner.author_prompt(Path('/tmp/manifest'))
        self.assertIn('already selected and verified -m gpt-6.1-terra', prompt)
        self.assertIn('Do not attempt', prompt)
        self.assertIn('Complete EVERY assigned ID', prompt)
        self.assertIn('not a sample', prompt)

    def test_run_supplies_images_and_records_actual_input(self):
        figure = runner.REPO / 'data' / 'docs' / 'workflow.md'
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            def fake_run(command, **kwargs):
                self.assertEqual(command[command.index('--image') + 1], str(figure))
                kwargs['stdout'].write(json.dumps({'type': 'thread.started', 'thread_id': 'run1'}) + '\n')
                kwargs['stdout'].write(json.dumps({'type': 'turn.completed'}) + '\n')
                return types.SimpleNamespace(returncode=0)
            with patch.object(runner.subprocess, 'run', side_effect=fake_run):
                self.assertEqual(runner.run_codex('prompt', folder, 'author-0', 1, [figure]), 'run1')
            metadata = json.loads((folder / 'author-0-input.json').read_text())
            self.assertEqual(metadata['attached_image_paths'], ['docs/workflow.md'])
            self.assertEqual(len(metadata['attached_image_sha256'][0]), 64)
            self.assertEqual(len(metadata['prompt_sha256']), 64)

    def test_claude_worker_reads_figures_and_reports_its_session(self):
        figure = runner.REPO / 'data' / 'docs' / 'workflow.md'
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            def fake_run(command, **kwargs):
                self.assertEqual(command[:4], ['claude', '-p', '--model', 'claude-sonnet-5-5'])
                self.assertNotIn('Bash', command[command.index('--tools') + 1])
                self.assertIn(str(figure), kwargs['input'])
                kwargs['stdout'].write(json.dumps({'type': 'system', 'subtype': 'init', 'session_id': 's1'}) + '\n')
                kwargs['stdout'].write(json.dumps({'type': 'result', 'subtype': 'success', 'is_error': False,
                    'session_id': 's1', 'usage': {'input_tokens': 5, 'cache_read_input_tokens': 10,
                                                  'output_tokens': 7}}) + '\n')
                return types.SimpleNamespace(returncode=0)
            with patch.object(runner, 'MODEL', 'claude-sonnet-5-5'), \
                 patch.object(runner.subprocess, 'run', side_effect=fake_run):
                self.assertEqual(runner.run_codex('prompt', folder, 'author-0', 1, [figure]), 's1')
            self.assertEqual(json.loads((folder / 'author-0-input.json').read_text())['model'], 'claude-sonnet-5-5')
            usage = runner.usage_summary(folder.parent)
            self.assertEqual(usage['completed_runs']['author'], 1)
            self.assertEqual(usage['reported_usage'], dict(input_tokens=15, cached_input_tokens=10, output_tokens=7))

    def test_failed_claude_run_has_no_run_identifier(self):
        failed = [{'type': 'result', 'subtype': 'error_max_turns', 'is_error': True, 'session_id': 's1'}]
        self.assertIsNone(runner.completed_run_id(failed))
        self.assertIsNone(runner.completed_run_id([{'type': 'thread.started', 'thread_id': 't'}]))

    def test_worker_registry_accepts_listed_models_only(self):
        import worker_models
        self.assertTrue(worker_models.is_worker('claude-sonnet-5-5'))
        self.assertFalse(worker_models.is_worker('claude-opus-5-5'))
        self.assertTrue(worker_models.is_correction('gpt-6.1-terra:correction'))
        self.assertFalse(worker_models.is_correction('gpt-6.1-terra'))

    def test_provenance_binds_distinct_real_runs_without_changing_decision(self):
        review = {'reviewer': 'RUN_ID_TO_BE_RECORDED', 'status': 'needs_changes', 'issues': ['unsafe']}
        bound = runner.bind_run_provenance(review, 'author-id', 'review-id')
        self.assertEqual(bound['author'], 'gpt-6.1-terra / author-id')
        self.assertEqual(bound['reviewer'], 'gpt-6.1-terra / review-id')
        self.assertEqual(bound['status'], 'needs_changes')
        self.assertEqual(bound['issues'], ['unsafe'])
        with self.assertRaises(ValueError):
            runner.bind_run_provenance(review, 'same', 'same')
        with self.assertRaises(ValueError):
            runner.bind_run_provenance({'reviewer': 'untrusted'}, 'author-id', 'review-id')

    def test_current_bank_and_source_order_precede_legacy(self):
        banks = [dict(id='legacy', pdf='l', sha256='l', legacy=True),
                 dict(id='current', pdf='c', sha256='c', legacy=False)]
        def sources(bank):
            numbers = ['2', '1'] if bank['id'] == 'current' else ['0']
            return [dict(number=n, text_it=n, answer='0', figures=[], bank=bank['id']) for n in numbers]
        localized = {lang: {runner.text_id(n): n for n in ('0', '1', '2')} for lang in runner.wf.LANGUAGES}
        with patch.object(runner.wf, 'selected_banks', return_value=banks), \
             patch.object(runner.wf, 'question_sources', side_effect=sources), \
             patch.object(runner.wf, 'translations', return_value=localized), \
             patch.object(runner.wf, 'reusable_ab', return_value={}), \
             patch.object(runner.wf, 'explanations', return_value={}):
            batches = list(runner.make_batches(1, None))
        self.assertEqual([batch['tasks'][0]['bank'] for batch in batches], ['current', 'current', 'legacy'])
        self.assertEqual([batch['tasks'][0]['records'][0]['source']['number'] for batch in batches], ['2', '1', '0'])

    def test_fully_covered_donor_skips_duplicate(self):
        banks = [dict(id='a', pdf='a', sha256='a'), dict(id='b', pdf='b', sha256='b')]
        row = dict(number='1', text_it='Test', answer='0', figures=[])
        translations = {lang: {runner.text_id('Test'): 'translated'} for lang in runner.wf.LANGUAGES}
        def existing(bank, language):
            return {'1': {'text': language + ' explanation'}} if bank == 'a' else {}
        with patch.object(runner.wf, 'selected_banks', side_effect=lambda ids=None: banks if ids is None else [banks[1]]), \
             patch.object(runner.wf, 'question_sources', side_effect=lambda bank: [dict(row, bank=bank['id'])]), \
             patch.object(runner.wf, 'translations', return_value=translations), \
             patch.object(runner.wf, 'reusable_ab', return_value={}), \
             patch.object(runner.wf, 'explanations', side_effect=existing):
            self.assertEqual(list(runner.make_batches(5, ['b'])), [])

    def test_duplicate_banks_have_one_owner_and_four_tasks(self):
        banks = [dict(id='a', pdf='a.pdf', sha256='a'), dict(id='b', pdf='b.pdf', sha256='b')]
        row = dict(number='1', text_it='Test', answer='0', figures=[])
        sources = lambda bank: [dict(row, bank=bank['id'])]
        translations = {lang: {runner.text_id('Test'): 'Translated'} for lang in runner.wf.LANGUAGES}
        with patch.object(runner.wf, 'selected_banks', return_value=banks), \
             patch.object(runner.wf, 'question_sources', side_effect=sources), \
             patch.object(runner.wf, 'translations', return_value=translations), \
             patch.object(runner.wf, 'reusable_ab', return_value={}), \
             patch.object(runner.wf, 'explanations', return_value={}):
            batches = list(runner.make_batches(5, None))
        self.assertEqual(len(batches), 1)
        self.assertEqual(len(batches[0]['identities']), 1)
        self.assertEqual(len(batches[0]['tasks']), 4)
        self.assertEqual({t['bank'] for t in batches[0]['tasks']}, {'a'})
        self.assertEqual({t['language'] for t in batches[0]['tasks']}, set(runner.LANGUAGES))


if __name__ == '__main__':
    unittest.main()
