"""Validated snapshots, conflict-safe merging and local recoverable storage."""
from __future__ import annotations

import copy
import csv
import hashlib
import io
import json
import os
from datetime import datetime, timezone
from pathlib import Path
import re
import sys
import uuid
import math

MUSCLES = {
    'chest': 'Ngực', 'lats': 'Xô', 'upperBack': 'Lưng trên', 'lowerBack': 'Lưng dưới',
    'frontShoulder': 'Vai trước', 'sideShoulder': 'Vai giữa', 'rearShoulder': 'Vai sau',
    'biceps': 'Tay trước', 'triceps': 'Tay sau', 'forearms': 'Cẳng tay', 'abs': 'Bụng',
    'quads': 'Đùi trước', 'hamstrings': 'Đùi sau', 'glutes': 'Mông', 'calves': 'Bắp chân',
}


def resource_path(name: str) -> Path:
    root = Path(getattr(sys, '_MEIPASS', Path(__file__).resolve().parents[1]))
    return root / name


def seed_days() -> list:
    return json.loads(resource_path('assets/seed.json').read_text(encoding='utf-8'))['days']


def parse_weight(text: str) -> float | None:
    value = re.sub(r'\s|kg', '', text.lower().replace(',', '.').replace('×', 'x'))
    match = re.fullmatch(r'(?:(\d+)x)?(\d+(?:\.\d+)?)', value)
    if not match:
        return None
    return int(match[1] or 1) * float(match[2])


def normalize(raw: dict) -> dict:
    raw = copy.deepcopy(raw)
    if not isinstance(raw, dict) or raw.get('app') != 'trackta' or raw.get('version') not in (1, 2):
        raise ValueError('Chọn bản sao lưu JSON của Track Tạ 1.1.0 trở lên.')
    weeks = raw.get('weeks')
    if type(weeks) is not int or not 8 <= weeks <= 10000:
        raise ValueError('Số tuần phải từ 8 đến 10.000.')
    labels = raw.get('debloatWeeks', [])
    if (not isinstance(labels, list) or any(type(w) is not int or not 1 <= w <= weeks for w in labels)
            or len(set(labels)) != len(labels)):
        raise ValueError('Nhãn tuần debloat không hợp lệ.')
    days = raw.get('days') if raw['version'] == 2 else seed_days()
    if not isinstance(days, list) or not 1 <= len(days) <= 14:
        raise ValueError('Lịch tập cần từ 1 đến 14 buổi.')
    day_ids, exercises = set(), {}
    clean_days = []
    def text(value, max_length, label, empty=False):
        if not isinstance(value, str) or len(value) > max_length or (not empty and not value.strip()):
            raise ValueError(f'{label} không hợp lệ (tối đa {max_length} ký tự).')
        return value
    def valid_id(value):
        return isinstance(value, str) and re.fullmatch(r'[A-Za-z0-9_-]{1,64}', value)
    for d in days:
        if not isinstance(d, dict):
            raise ValueError('Buổi tập không hợp lệ.')
        day_id = d.get('id', f"day{d.get('weekday')}")
        if not valid_id(day_id) or day_id in day_ids or type(d.get('weekday')) is not int or not 1 <= d['weekday'] <= 7:
            raise ValueError('Mã buổi hoặc thứ trong tuần không hợp lệ.')
        day_ids.add(day_id)
        items = d.get('exercises')
        if not isinstance(items, list) or not 1 <= len(items) <= 60:
            raise ValueError('Mỗi buổi cần từ 1 đến 60 bài tập.')
        clean_exercises = []
        for e in items:
            if not isinstance(e, dict) or not valid_id(e.get('id')) or e['id'] in exercises:
                raise ValueError('Mã bài tập bị trùng hoặc không hợp lệ.')
            if type(e.get('sets')) is not int or not 1 <= e['sets'] <= 30:
                raise ValueError('Số hiệp của bài tập phải từ 1 đến 30.')
            if any(type(e.get(k)) is not bool for k in ('timed', 'assisted')) or e['timed'] and e['assisted']:
                raise ValueError('Cách đo của bài tập không hợp lệ.')
            archived = e.get('archived', False)
            if type(archived) is not bool:
                raise ValueError('Trạng thái lưu trữ không hợp lệ.')
            groups = []
            for key in ('primaryMuscles', 'secondaryMuscles'):
                value = e.get(key, [])
                if not isinstance(value, list) or any(not isinstance(v, str) or v not in MUSCLES for v in value) or len(set(value)) != len(value):
                    raise ValueError('Nhóm cơ không hợp lệ.')
                groups.append(value)
            if set(groups[0]) & set(groups[1]):
                raise ValueError('Một nhóm cơ không thể vừa chính vừa phụ.')
            clean = {
                'id': e['id'], 'name': text(e.get('name'), 200, 'Tên bài'),
                'target': text(e.get('target'), 40, 'Mục tiêu'), 'sets': e['sets'],
                'timed': e['timed'], 'assisted': e['assisted'], 'archived': archived,
                'primaryMuscles': groups[0], 'secondaryMuscles': groups[1],
            }
            exercises[e['id']] = clean
            clean_exercises.append(clean)
        if all(e['archived'] for e in clean_exercises):
            raise ValueError('Mỗi buổi cần ít nhất một bài đang tập.')
        clean_days.append({'id': day_id, 'name': text(d.get('name'), 100, 'Tên buổi'),
                           'subtitle': text(d.get('subtitle', ''), 300, 'Mô tả buổi', True),
                           'weekday': d['weekday'], 'exercises': clean_exercises})
    entries = raw.get('entries')
    if not isinstance(entries, dict) or len(entries) > 500000:
        raise ValueError('Nhật ký không hợp lệ hoặc quá lớn.')
    clean_entries = {}
    for key, entry in entries.items():
        parts = key.split(':') if isinstance(key, str) else []
        if len(parts) != 3 or not parts[0].isdigit() or not parts[2].isdigit() or parts[1] not in exercises or not 1 <= int(parts[0]) <= weeks or not 1 <= int(parts[2]) <= exercises[parts[1]]['sets'] or not isinstance(entry, dict):
            raise ValueError(f'Hiệp {key!r} không khớp lịch tập. Giữ đủ hiệp đã ghi khi sửa bài.')
        weight = text(entry.get('weight'), 40, 'Tạ', True)
        reps = text(entry.get('reps'), 5, 'Reps / giây', True)
        note = text(entry.get('note', ''), 500, 'Ghi chú', True)
        if weight and (parse_weight(weight) is None or parse_weight(weight) > 10000):
            raise ValueError('Tạ phải có dạng 35kg hoặc 2x12.5kg và không quá 10.000kg.')
        if reps and (not re.fullmatch(r'\d{1,5}', reps) or not 1 <= int(reps) <= 99999):
            raise ValueError('Reps / giây phải là số nguyên lớn hơn 0.')
        clean_entries[key] = {'weight': weight, 'reps': reps, 'note': note,
                              'source': text(entry.get('source', 'app'), 40, 'Nguồn', True)}
    return {'app': 'trackta', 'version': 2, 'weeks': weeks, 'days': clean_days, 'entries': clean_entries, 'debloatWeeks':sorted(labels)}


def all_exercises(doc):
    return {e['id']: (d, e) for d in doc['days'] for e in d['exercises']}


def guard_history(old, new):
    target = all_exercises(new)
    for eid, (_, ex) in all_exercises(old).items():
        if not any(k.split(':')[1] == eid for k in old['entries']):
            continue
        if eid not in target or any(ex[k] != target[eid][1][k] for k in ('timed', 'assisted')):
            raise ValueError('Bài đã có nhật ký cần giữ cách đo. Hãy lưu trữ bài cũ và tạo bài mới.')


def change_summary(old, new):
    if old is None:
        return ['Bản làm việc chưa được đồng bộ với điện thoại này.']
    changes = []
    before, after = all_exercises(old), all_exercises(new)
    for eid in before.keys() | after.keys():
        if ((before[eid][0]['id'], before[eid][1]) if eid in before else None) != ((after[eid][0]['id'], after[eid][1]) if eid in after else None):
            ex = (after.get(eid) or before[eid])[1]
            changes.append(f"Bài tập / buổi: {ex['name']}")
    if [(d['id'], d['name'], d['subtitle'], d['weekday']) for d in old['days']] != [(d['id'], d['name'], d['subtitle'], d['weekday']) for d in new['days']]:
        changes.append('Tên, thứ hoặc thứ tự buổi tập')
    if old['weeks'] != new['weeks']:
        changes.append(f"Số tuần: {old['weeks']} → {new['weeks']}")
    if old.get('debloatWeeks', []) != new.get('debloatWeeks', []):
        changes.append('Nhãn tuần debloat')
    for key in sorted(old['entries'].keys() | new['entries'].keys()):
        if old['entries'].get(key) != new['entries'].get(key):
            w, eid, s = key.split(':')
            name = (after.get(eid) or before.get(eid))[1]['name']
            changes.append(f'Tuần {w} · {name} · Hiệp {s}')
    return changes


def merge_snapshots(base, local, remote, choices=None):
    """Three-way merge. Missing entries mean deletion only with a known baseline."""
    choices = choices or {}
    conflicts = []
    def merge_value(key, b, l, r):
        if l == r:
            return l
        if base is not None and l == b:
            return r
        if base is not None and r == b:
            return l
        if base is None and l is None:
            return r
        if base is None and r is None:
            return l
        if key in choices:
            return l if choices[key] == 'local' else r
        conflicts.append({'key': key, 'local': l, 'remote': r})
        return r
    merged = copy.deepcopy(remote)
    merged['weeks'] = max(local['weeks'], remote['weeks'])
    merged['debloatWeeks'] = sorted(set(local.get('debloatWeeks', [])) | set(remote.get('debloatWeeks', [])))
    merged['days'] = copy.deepcopy(merge_value('days', base['days'] if base else None, local['days'], remote['days']))
    merged['entries'] = {}
    for key in sorted((base['entries'].keys() if base else set()) | local['entries'].keys() | remote['entries'].keys()):
        value = merge_value(key, base['entries'].get(key) if base else None, local['entries'].get(key), remote['entries'].get(key))
        if value is not None:
            merged['entries'][key] = copy.deepcopy(value)
    if not conflicts:
        merged = normalize(merged)
    return merged, conflicts


def export_csv(doc):
    buffer = io.StringIO(newline='')
    writer = csv.writer(buffer)
    writer.writerow(['Tuần', 'Buổi', 'Bài tập', 'Hiệp', 'Mục tiêu', 'Tạ (nguyên bản)', 'Reps / giây', 'Ghi chú'])
    exercises = all_exercises(doc)
    def safe(value):
        return "'" + value if value.startswith(('=', '+', '-', '@', '\t', '\r')) else value
    for key in sorted(doc['entries'], key=lambda k: (int(k.split(':')[0]), k.split(':')[1], int(k.split(':')[2]))):
        w, eid, s = key.split(':')
        day, ex = exercises[eid]
        row = doc['entries'][key]
        writer.writerow([w, safe(day['name']), safe(ex['name']), s, safe(ex['target']), safe(row['weight']), row['reps'], safe(row['note'])])
    return '\ufeff' + buffer.getvalue()


def entry_complete(entry):
    return bool(entry and entry.get('reps') and entry.get('source') != 'debloat')


def progress_values(doc, eid):
    ex = all_exercises(doc)[eid][1]
    values = []
    for w in range(1, doc['weeks'] + 1):
        numbers = []
        for s in range(1, ex['sets'] + 1):
            entry = doc['entries'].get(f'{w}:{eid}:{s}')
            if entry_complete(entry):
                value = int(entry['reps']) if ex['timed'] else parse_weight(entry['weight'])
                if value is not None:
                    numbers.append(value)
        values.append((min(numbers) if ex['assisted'] else max(numbers)) if numbers else None)
    return values


def can_debloat(doc):
    return all(any(k.startswith(f'{w}:') and entry_complete(e) for k, e in doc['entries'].items()) for w in range(1, 5))


def forecast_week_five(values):
    """Least squares over whichever of weeks 1-4 hold a value; one point repeats itself."""
    points = [(i + 1, v) for i, v in enumerate(values) if v is not None]
    if len(points) == 1:
        return points[0][1]
    mean_x = sum(x for x, _ in points) / len(points)
    mean_y = sum(y for _, y in points) / len(points)
    numerator = sum((x - mean_x) * (y - mean_y) for x, y in points)
    denominator = sum((x - mean_x) ** 2 for x, _ in points)
    return mean_y + (numerator / denominator if denominator else 0) * (5 - mean_x)


def round_debloat(value, step, up=False):
    return (math.ceil(value / step - 1e-9) if up else math.floor(value / step + .5 + 1e-9)) * step


def format_suggested_weight(total, paired=False, assisted=False):
    amount = round_debloat(total / (2 if paired else 1), 2.5, up=assisted)
    return f"{'2x' if paired else ''}{amount:g}kg"


def debloat_plan(doc, target=5, factor=.6):
    if target != 5 or not math.isfinite(factor) or not 0 < factor <= 1:
        raise ValueError('Tuần debloat là tuần 5; hệ số trong (0, 1].')
    plan = {'target':target, 'factor':factor, 'eligible':can_debloat(doc), 'suggestions':[], 'skipped':[], 'values':{}, 'preservedSets':0}
    if not plan['eligible']:
        return plan
    for _, ex in all_exercises(doc).values():
        if ex['archived']:
            continue
        completed = [[doc['entries'].get(f'{w}:{ex["id"]}:{s}') for s in range(1, ex['sets'] + 1)] for w in range(1,5)]
        completed = [[e for e in items if entry_complete(e)] for items in completed]
        reason = None
        if all(not items for items in completed):
            reason = 'Chưa có hiệp đã tập nào trong tuần 1–4.'
        logged = [e for items in completed for e in items]
        weeks_used = sum(bool(items) for items in completed)
        bw = not ex['timed'] and not ex['assisted'] and all(not e['weight'] for e in logged)
        weekly = progress_values(doc, ex['id'])[:4]
        available = [v for v in weekly if v is not None]
        if not reason and not bw and not available:
            reason = 'Thiếu tạ hoặc thời gian hợp lệ trong 4 tuần.'
        reps = [int(v) for v in re.findall(r'\d+', ex['target']) if int(v) > 0]
        if not reason and not ex['timed'] and not reps:
            reason = 'Mục tiêu reps chưa có số hợp lệ.'
        if reason:
            plan['skipped'].append({'exercise':ex, 'reason':reason})
            continue
        raw = None if bw else forecast_week_five(weekly)
        forecast = None if bw else max(0, min(raw, min(available) if ex['assisted'] else max(available)))
        paired = not bw and not ex['timed'] and all(re.match(r'^2\s*[x×]', e['weight'].strip(), re.I) for e in logged)
        weight = '' if bw or ex['timed'] else format_suggested_weight(forecast / factor if ex['assisted'] else forecast * factor, paired, ex['assisted'])
        target_reps = str(max(5, int(round_debloat(forecast * factor, 5)))) if ex['timed'] else str(min(reps))
        empty = 0
        for s in range(1, ex['sets'] + 1):
            key = f'{target}:{ex["id"]}:{s}'
            current = doc['entries'].get(key, {})
            if not any(current.get(k) for k in ('weight','reps','note')):
                plan['values'][key] = {'weight':weight, 'reps':target_reps, 'note':'', 'source':'debloat'}
                empty += 1
        plan['preservedSets'] += ex['sets'] - empty
        plan['suggestions'].append({'exercise':ex,'weeklyValues':weekly,'rawForecast':raw,'forecast':forecast,'weight':weight,'reps':target_reps,'emptySets':empty,'preservedSets':ex['sets']-empty,'weeksUsed':weeks_used,'paired':paired})
    return plan


def apply_debloat(doc, plan):
    # Rebuild from the current working copy; never overwrite intervening edits.
    fresh = debloat_plan(doc, plan['target'], plan['factor'])
    if not fresh['eligible']:
        raise ValueError('Cần hiệp đã tập ở cả tuần 1–4.')
    result = copy.deepcopy(doc)
    result['entries'].update(fresh['values'])
    result['debloatWeeks'] = sorted(set(result.get('debloatWeeks', [])) | {fresh['target']})
    return normalize(result)


def new_id(prefix):
    return prefix + uuid.uuid4().hex[:16]


def atomic_json(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.new')
    with temporary.open('w', encoding='utf-8', newline='\n') as stream:
        json.dump(data, stream, ensure_ascii=False, indent=2)
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)


class Workspace:
    def __init__(self, root=None, serial='offline'):
        self.root = Path(root or Path(os.environ.get('LOCALAPPDATA', Path.home())) / 'TrackTaWindows')
        slug = hashlib.sha256(serial.encode()).hexdigest()[:16]
        self.directory = self.root / 'devices' / slug
        self.directory.mkdir(parents=True, exist_ok=True)
        self.serial = serial
        self.baseline = None
        self.doc = None
        self.state_path = self.directory / 'workspace.json'
        if self.state_path.exists():
            data = json.loads(self.state_path.read_text(encoding='utf-8'))
            self.doc = normalize(data['working']) if data.get('working') else None
            self.baseline = normalize(data['baseline']) if data.get('baseline') else None

    def save(self):
        atomic_json(self.state_path, {'serial': self.serial, 'working': self.doc, 'baseline': self.baseline})

    def accept_remote(self, doc):
        parsed = normalize(doc)
        previous_doc, previous_baseline = self.doc, self.baseline
        self.doc = parsed
        self.baseline = copy.deepcopy(self.doc)
        try:
            self.save()
        except Exception:
            self.doc, self.baseline = previous_doc, previous_baseline
            raise

    def edit(self, doc):
        parsed = normalize(doc)
        if self.doc:
            guard_history(self.doc, parsed)
        previous = self.doc
        self.doc = parsed
        try:
            self.save()
        except Exception:
            self.doc = previous
            raise

    def backup(self, doc, label):
        stamp = datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S-%f')
        path = self.directory / 'backups' / f'{stamp}-{label}.json'
        atomic_json(path, normalize(doc))
        return path

    @property
    def dirty(self):
        return self.doc is not None and self.doc != self.baseline

    def photos_index(self):
        path = self.directory / 'photos' / 'index.json'
        return json.loads(path.read_text(encoding='utf-8')) if path.exists() else {}

    def save_photo(self, month, data, expected_hash=None):
        if not re.fullmatch(r'\d{4}-(0[1-9]|1[0-2])', month):
            raise ValueError('Tháng cần có dạng 2026-10.')
        digest = hashlib.sha256(data).hexdigest()
        if expected_hash and digest != expected_hash:
            raise ValueError('Ảnh thay đổi trong lúc tải. Tải lại để sao lưu đầy đủ.')
        extension = 'png' if data[:8] == b'\x89PNG\r\n\x1a\n' else 'jpg'
        folder = self.directory / 'photos'
        folder.mkdir(exist_ok=True)
        path = folder / f'{month}-{digest[:16]}.{extension}'
        temp = path.with_suffix(path.suffix + '.new')
        temp.write_bytes(data)
        temp.replace(path)
        index = self.photos_index()
        index[month] = {'file': path.name, 'revision': digest}
        atomic_json(folder / 'index.json', index)
        return path
