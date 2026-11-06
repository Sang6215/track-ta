import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from trackta_core import normalize, merge_snapshots, guard_history, Workspace, export_csv, progress_values, change_summary
from trackta_core import debloat_plan, apply_debloat, entry_complete, can_debloat
from usb_client import UsbClient, UsbError


def fixture():
    seed = json.loads((Path(__file__).resolve().parents[2] / 'assets/seed.json').read_text(encoding='utf-8'))
    return normalize({'app':'trackta','version':1,'weeks':seed['weeks'],'entries':seed['entries']})


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.doc = fixture()

    def test_v1_import_keeps_original_pairs_and_empty_weeks(self):
        self.assertEqual(108, len(self.doc['entries']))
        self.assertEqual('2x12.5kg', self.doc['entries']['1:d1e1:2']['weight'])
        self.assertEqual(self.doc, normalize(self.doc))
        self.assertIsNone(progress_values(self.doc, 'd1e1')[3])

    def test_unrelated_phone_logs_and_desktop_schedule_merge(self):
        local, remote = copy.deepcopy(self.doc), copy.deepcopy(self.doc)
        local['days'][0]['exercises'][0]['name'] = 'Bench edited'
        remote['entries']['4:d1e1:1'] = {'weight':'30', 'reps':'8','note':'phone','source':'app'}
        merged, conflicts = merge_snapshots(self.doc, local, remote)
        self.assertFalse(conflicts)
        self.assertEqual('Bench edited', merged['days'][0]['exercises'][0]['name'])
        self.assertEqual('phone', merged['entries']['4:d1e1:1']['note'])

    def test_same_set_conflicts_require_explicit_choice(self):
        local, remote = copy.deepcopy(self.doc), copy.deepcopy(self.doc)
        local['entries']['1:d1e1:1']['weight'] = '50'
        remote['entries']['1:d1e1:1']['weight'] = '45'
        _, conflicts = merge_snapshots(self.doc,local,remote)
        self.assertEqual(['1:d1e1:1'],[c['key'] for c in conflicts])
        merged, conflicts = merge_snapshots(self.doc,local,remote,{'1:d1e1:1':'local'})
        self.assertFalse(conflicts)
        self.assertEqual('50',merged['entries']['1:d1e1:1']['weight'])

    def test_deletion_and_no_baseline_do_not_lose_phone_entries(self):
        local = copy.deepcopy(self.doc)
        del local['entries']['1:d1e1:1']
        merged, conflicts = merge_snapshots(self.doc, local, self.doc)
        self.assertNotIn('1:d1e1:1',merged['entries'])
        merged, conflicts = merge_snapshots(None,local,self.doc)
        self.assertIn('1:d1e1:1',merged['entries'])

    def test_archive_keeps_history_and_mode_changes_are_guarded(self):
        new = copy.deepcopy(self.doc)
        new['days'][0]['exercises'][0]['archived'] = True
        guard_history(self.doc, normalize(new))
        self.assertEqual(108,len(new['entries']))
        new['days'][0]['exercises'][0]['timed'] = True
        with self.assertRaises(ValueError):
            guard_history(self.doc,normalize(new))

    def test_invalid_document_rejected_before_local_write(self):
        with tempfile.TemporaryDirectory() as folder:
            ws = Workspace(folder,'phone')
            ws.accept_remote(self.doc)
            invalid = copy.deepcopy(self.doc)
            invalid['days'][0]['exercises'][0]['sets'] = 1
            with self.assertRaises(ValueError):
                ws.edit(invalid)
            self.assertEqual(self.doc,Workspace(folder,'phone').doc)

    def test_failed_remote_save_keeps_unsent_working_copy_and_baseline(self):
        with tempfile.TemporaryDirectory() as folder:
            ws = Workspace(folder, 'phone')
            ws.accept_remote(self.doc)
            local = copy.deepcopy(self.doc)
            local['entries']['1:d1e1:1']['weight'] = '50kg'
            ws.edit(local)
            remote = copy.deepcopy(self.doc)
            remote['entries']['1:d1e1:1']['weight'] = '45kg'
            with patch.object(ws, 'save', side_effect=OSError('Disk full')):
                with self.assertRaises(OSError):
                    ws.accept_remote(remote)
            self.assertEqual(local, ws.doc)
            self.assertEqual(self.doc, ws.baseline)
            self.assertTrue(ws.dirty)
            self.assertEqual(local, Workspace(folder, 'phone').doc)

    def test_backups_and_photo_history_survive_replacements(self):
        with tempfile.TemporaryDirectory() as folder:
            ws = Workspace(folder,'phone')
            ws.accept_remote(self.doc)
            path = ws.backup(self.doc,'before-sync')
            self.assertEqual(self.doc,normalize(json.loads(path.read_text(encoding='utf-8'))))
            one = ws.save_photo('2026-10',b'first')
            two = ws.save_photo('2026-10',b'second')
            self.assertTrue(one.exists() and two.exists())
            self.assertNotEqual(one,two)

    def test_changes_and_csv_preserve_data_and_escape_formulas(self):
        new = copy.deepcopy(self.doc)
        new['days'][0]['exercises'][0]['name']='Bench'
        self.assertEqual(1,len(change_summary(self.doc,new)))
        new['entries']['1:d1e1:1']['note']='=SUM(1,2)'
        self.assertIn("'=SUM(1,2)",export_csv(new))
        self.assertIn('2x12.5kg',export_csv(new))


class DebloatTests(unittest.TestCase):
    def setUp(self):
        self.doc = fixture()
        self.doc['entries'] = {}
        self.bench = self.doc['days'][0]['exercises'][0]

    def history(self, ex, values):
        for w, value in enumerate(values, 1):
            self.doc['entries'][f'{w}:{ex["id"]}:1'] = {
                'weight':'' if ex['timed'] else value,
                'reps':value if ex['timed'] else '8', 'note':'', 'source':'app'}

    def suggestion(self, ex):
        return next(s for s in debloat_plan(self.doc)['suggestions'] if s['exercise']['id']==ex['id'])

    def test_capped_regression_and_paired_rounding(self):
        self.history(self.bench, ['40','42.5','45','47.5'])
        s = self.suggestion(self.bench)
        self.assertEqual((50,47.5,'27.5kg','6'),(s['rawForecast'],s['forecast'],s['weight'],s['reps']))
        self.history(self.bench, ['2x10kg','2x12.5kg','2x12.5kg','2x15kg'])
        self.assertEqual('2x10kg',self.suggestion(self.bench)['weight'])

    def test_assisted_timed_and_bodyweight(self):
        exs = [e for d in self.doc['days'] for e in d['exercises']]
        assisted = next(e for e in exs if e['assisted'])
        self.history(assisted,['40','45','45','50'])
        self.doc['entries'][f'1:{assisted["id"]}:2']={'weight':'55','reps':'8','note':'','source':'app'}
        self.assertEqual('67.5kg',self.suggestion(assisted)['weight'])
        plank = next(e for e in exs if e['timed'])
        self.history(plank,['60']*4)
        self.assertEqual(('','35'),(self.suggestion(plank)['weight'],self.suggestion(plank)['reps']))
        self.history(self.bench,['']*4)
        self.assertEqual('',self.suggestion(self.bench)['weight'])

    def test_unconfirmed_week_counts_as_missing_but_not_excluded(self):
        self.history(self.bench,['40']*4)
        self.doc['entries']['4:d1e1:1']['source']='debloat'
        self.assertFalse(can_debloat(self.doc))
        other=self.doc['days'][0]['exercises'][1]
        self.history(other,['20']*4)
        plan=debloat_plan(self.doc)
        self.assertTrue(plan['eligible'])
        bench=next(s for s in plan['suggestions'] if s['exercise']['id']==self.bench['id'])
        self.assertEqual(3,bench['weeksUsed'])
        self.assertEqual(40,bench['forecast'])
        self.assertFalse(any(s['exercise']['id']==self.bench['id'] for s in plan['skipped']))

    def test_partial_weeks_regress_and_single_week_repeats(self):
        other=self.doc['days'][0]['exercises'][1]
        self.history(other,['20']*4)
        self.doc['entries'][f'1:{self.bench["id"]}:1']={'weight':'40kg','reps':'8','note':'','source':'app'}
        self.doc['entries'][f'3:{self.bench["id"]}:1']={'weight':'44kg','reps':'8','note':'','source':'app'}
        s=self.suggestion(self.bench)
        self.assertEqual(2,s['weeksUsed'])
        self.assertEqual([40,None,44,None],s['weeklyValues'])
        self.assertEqual(48,s['rawForecast'])
        self.assertEqual(44,s['forecast'])
        self.assertEqual('27.5kg',s['weight'])
        self.doc['entries'].pop(f'1:{self.bench["id"]}:1')
        self.doc['entries'].pop(f'3:{self.bench["id"]}:1')
        self.doc['entries'][f'2:{self.bench["id"]}:1']={'weight':'45kg','reps':'8','note':'','source':'app'}
        s=self.suggestion(self.bench)
        self.assertEqual(1,s['weeksUsed'])
        self.assertEqual(45,s['forecast'])
        self.assertEqual('27.5kg',s['weight'])

    def test_assisted_partial_weeks_clamp_to_lowest_available(self):
        self.history(self.bench,['40']*4)
        assisted=next(e for d in self.doc['days'] for e in d['exercises'] if e['assisted'])
        self.doc['entries'][f'1:{assisted["id"]}:1']={'weight':'50','reps':'8','note':'','source':'app'}
        self.doc['entries'][f'2:{assisted["id"]}:1']={'weight':'40','reps':'8','note':'','source':'app'}
        s=self.suggestion(assisted)
        self.assertEqual(2,s['weeksUsed'])
        self.assertEqual(10,s['forecast'])
        self.assertEqual('17.5kg',s['weight'])

    def test_exercise_without_logged_weeks_stays_skipped(self):
        self.history(self.bench,['40']*4)
        plan=debloat_plan(self.doc)
        untouched=self.doc['days'][0]['exercises'][2]
        reason=next(s['reason'] for s in plan['skipped'] if s['exercise']['id']==untouched['id'])
        self.assertEqual('Chưa có hiệp đã tập nào trong tuần 1–4.',reason)

    def test_apply_preserves_edits_idempotent_and_confirmation_counts(self):
        self.history(self.bench,['40']*4)
        self.doc['entries']['5:d1e1:1']={'weight':'','reps':'','note':'keep','source':'app'}
        plan=debloat_plan(self.doc)
        self.assertEqual(3,len(plan['values']))
        # A new real log entered after preview must also survive.
        self.doc['entries']['5:d1e1:2']={'weight':'42.5kg','reps':'8','note':'real','source':'app'}
        result=apply_debloat(self.doc,plan)
        self.assertEqual('keep',result['entries']['5:d1e1:1']['note'])
        self.assertEqual('real',result['entries']['5:d1e1:2']['note'])
        self.assertEqual([5],result['debloatWeeks'])
        self.assertFalse(entry_complete(result['entries']['5:d1e1:3']))
        self.assertEqual(42.5,progress_values(result,'d1e1')[4])
        self.assertEqual(result,apply_debloat(result,plan))
        result['entries']['5:d1e1:3']['source']='windows'
        self.assertTrue(entry_complete(result['entries']['5:d1e1:3']))

    def test_labels_validate_migrate_merge_and_persist(self):
        for bad in [[5,5],[0],[9],['5'],[True],None]:
            with self.subTest(bad=bad):
                value=copy.deepcopy(self.doc)
                value['debloatWeeks']=bad
                with self.assertRaises(ValueError): normalize(value)
        legacy=copy.deepcopy(self.doc)
        legacy.pop('debloatWeeks')
        self.assertEqual([],normalize(legacy)['debloatWeeks'])
        local, remote=copy.deepcopy(self.doc),copy.deepcopy(self.doc)
        local['debloatWeeks']=[5]
        remote['debloatWeeks']=[8]
        merged,conflicts=merge_snapshots(self.doc,local,remote)
        self.assertFalse(conflicts)
        self.assertEqual([5,8],merged['debloatWeeks'])
        self.assertIn('Nhãn tuần debloat',change_summary(self.doc,merged))
        with tempfile.TemporaryDirectory() as folder:
            ws=Workspace(folder,'phone')
            ws.accept_remote(merged)
            self.assertEqual([5,8],Workspace(folder,'phone').doc['debloatWeeks'])

    def test_old_android_cannot_receive_unconfirmed_suggestions(self):
        self.history(self.bench,['40']*4)
        doc=apply_debloat(self.doc,debloat_plan(self.doc))
        client=UsbClient()
        client.remote_version='1.3.0'
        with patch.object(client,'request') as request:
            with self.assertRaises(UsbError): client.send_snapshot(doc,'rev')
            request.assert_not_called()
            client.remote_version='1.4.0'
            client.send_snapshot(doc,'rev')
            request.assert_called_once()


if __name__ == '__main__':
    unittest.main()
