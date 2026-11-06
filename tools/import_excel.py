"""Reproducible, read-only import; does not modify the source workbook."""
import json
from pathlib import Path
import openpyxl

root = Path(__file__).resolve().parents[1]
source = root / 'Lich_Tap_5_Ngay_Tuan.xlsx'
book = openpyxl.load_workbook(source, data_only=True)
days, entries = [], {}
for sheet, day, name, subtitle in [
    ('Th2 - Upper', 1, 'Upper', 'Thân trên · Sức mạnh nền tảng'),
    ('Th3 - Lower', 2, 'Lower', 'Thân dưới · Đùi trước & sức mạnh'),
    ('Th5 - Push', 4, 'Push', 'Ngực, vai & tay sau'),
    ('Th6 - Pull', 5, 'Pull', 'Lưng, xô & tay trước'),
    ('Th7 - Legs', 6, 'Legs', 'Chân, mông & bụng'),
]:
    exercises = []
    for rownum, row in enumerate(book[sheet].iter_rows(min_row=4, values_only=True), 4):
        if row[0] is not None:
            ex = {'id': f'd{day}e{len(exercises)+1}', 'name': str(row[0]).strip(),
                  'target': str(row[2]), 'sets': 0, 'timed': str(row[2]).endswith('s'),
                  'assisted': 'Assisted' in str(row[0]), 'sourceRow': rownum}
            exercises.append(ex)
        if row[1] is None:
            continue
        ex['sets'] += 1
        for week in range(1, 9):
            weight, reps = row[3+(week-1)*2:5+(week-1)*2]
            if weight is not None or reps is not None:
                entries[f'{week}:{ex["id"]}:{int(row[1])}'] = {
                    'weight': '' if weight is None else str(weight),
                    'reps': '' if reps is None else str(reps), 'note': '', 'source': 'excel'}
    days.append({'weekday': day, 'name': name, 'subtitle': subtitle,
                 'sourceSheet': sheet, 'exercises': exercises})
data = {'version': 1, 'source': source.name, 'weeks': 8, 'days': days, 'entries': entries}
out = root / 'assets' / 'seed.json'
out.parent.mkdir(exist_ok=True)
out.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
print(f'{len(days)} days, {sum(len(d["exercises"]) for d in days)} exercises, '
      f'{sum(e["sets"] for d in days for e in d["exercises"])} sets/week, {len(entries)} recorded sets')
