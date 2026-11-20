import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import content_workflow as wf
import staged_explanations as staged

class StagedTests(unittest.TestCase):
    def test_planning_keeps_each_banks_actual_italian_version(self):
        banks=[dict(id='ab'),dict(id='other')]
        def pack(bank,language):
            return {1:dict(number=1,text=bank+' Italian version')} if language=='it' else {}
        with patch.object(wf,'selected_banks',return_value=banks), \
             patch.object(wf,'question_sources',side_effect=lambda b:[dict(number=1,text_it='Same question',answer=1,figures=[],bank=b['id'])]), \
             patch.object(wf,'explanations',side_effect=pack):
            tasks=list(staged.tasks('localize','en',25))
            self.assertEqual(len(tasks),2)
            for task in tasks:
                self.assertEqual(task['records'][0]['italian'],task['bank']+' Italian version')

    def test_bad_evidence_does_not_discard_other_completed_rows(self):
        with tempfile.TemporaryDirectory() as tmp:
            task=dict(bank='a',language='it',records=[dict(source=dict(number=n)) for n in (1,2,3)])
            rows=[dict(number=1,text='Supported',evidence=['Rule']),dict(number=2,text='Unsupported',evidence=[])]
            with patch.object(wf,'explanations',return_value={}),patch.object(staged,'accept',return_value=1) as accept:
                self.assertEqual(staged.save_completed(task,rows,{'run_id':'actual'},Path(tmp)),1)
                self.assertEqual(accept.call_args.args[1],[rows[0]])
                issues=json.loads((Path(tmp)/'incomplete-rows.json').read_text())['issues']
                self.assertEqual({r['number'] for r in issues},{2,3})

    def test_italian_saved_without_review_and_existing_text_protected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);source=dict(number=1,text_it='Italian',answer=1,figures=[])
            task=dict(stage='italian',bank='a',language='it',records=[dict(source=source,source_sha256=wf.fingerprint(source))]);task['task_sha256']=wf.fingerprint(task)
            with patch.object(wf,'ROOT',root),patch.object(wf,'selected_banks',return_value=[dict(id='a')]),patch.object(wf,'question_sources',return_value=[source]):
                rows=[dict(number=1,text='Reason',evidence=['Primary source'])]
                self.assertEqual(staged.accept(task,rows,{'run_id':'actual','model':'gpt-6.1-terra'}),1)
                row=wf.explanations('a','it')[1]
                self.assertNotIn('review',row)
                staged.validate_generated('a','it',row,source,{('a','it'):{1:row}})
                with self.assertRaisesRegex(ValueError,'overwrite'):staged.accept(task,rows,{'run_id':'other'})
                changed=copy.deepcopy(source);changed['answer']=0
                with self.assertRaisesRegex(ValueError,'Stale'):staged.validate_generated('a','it',row,changed,{('a','it'):{1:row}})

    def test_localization_requires_exact_italian_baseline(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);source=dict(number=1,text_it='Italian',answer=1,figures=[])
            folder=root/'explanations/a';folder.mkdir(parents=True);(folder/'it.jsonl').write_text(json.dumps(dict(number=1,text='Original reason'))+'\n')
            record=dict(source=source,source_sha256=wf.fingerprint(source),italian='Original reason',italian_sha256=wf.fingerprint('Original reason'))
            task=dict(stage='localize',bank='a',language='en',records=[record]);task['task_sha256']=wf.fingerprint(task)
            with patch.object(wf,'ROOT',root),patch.object(wf,'selected_banks',return_value=[dict(id='a')]),patch.object(wf,'question_sources',return_value=[source]):
                staged.accept(task,[dict(number=1,text='Translated reason')],{'run_id':'translation'})
                row=wf.explanations('a','en')[1]
                packs={('a','it'):wf.explanations('a','it')}
                staged.validate_generated('a','en',row,source,packs)
                packs[('a','it')][1]['text']='Changed reason'
                with self.assertRaisesRegex(ValueError,'Italian changed'):staged.validate_generated('a','en',row,source,packs)

if __name__=='__main__':unittest.main()
