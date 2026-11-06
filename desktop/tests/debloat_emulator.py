"""Compare Android's applied plan with Python; only the dedicated test emulator."""
import copy
import json
from pathlib import Path
import re
import sys
import time
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from trackta_core import normalize, debloat_plan, apply_debloat, entry_complete
from usb_client import UsbClient

ROOT = Path(__file__).resolve().parents[2]
SERIAL = 'emulator-5554'
client = UsbClient()
client.serial = SERIAL
assert client.run('emu','avd','name',selected=True).splitlines()[0].strip() == 'TrackTaUsbTest'


def tree():
    client.run('shell','uiautomator','dump','/sdcard/trackta-debloat-qa.xml',selected=True)
    return ET.fromstring(client.run('shell','cat','/sdcard/trackta-debloat-qa.xml',selected=True))


def tap(prefix):
    for node in tree().iter('node'):
        value=node.attrib.get('text') or node.attrib.get('content-desc','')
        if value.startswith(prefix):
            x1,y1,x2,y2=map(int,re.findall(r'\d+',node.attrib['bounds']))
            client.run('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2),selected=True)
            time.sleep(.3)
            return
    raise AssertionError('UI not found: '+prefix)


def restart():
    client.close()
    client.run('shell','am','force-stop','vn.trackta.track_ta',selected=True)
    client.open_app()
    time.sleep(1)


def pair():
    tap('Dữ liệu')
    tap('Kết nối Windows qua USB')
    tap('Bắt đầu kết nối')
    code=next(n.attrib.get('text') or n.attrib.get('content-desc') for n in tree().iter('node') if re.fullmatch(r'\d{6}',n.attrib.get('text') or n.attrib.get('content-desc','')))
    return client.pair(SERIAL,code)


restart()
response=pair()
original=normalize(response['data'])
assert response['appVersion']=='1.4.0'
prepared=copy.deepcopy(original)
prepared['entries']={}
prepared['debloatWeeks']=[]
exercises=[e for d in prepared['days'] for e in d['exercises']]
bench=exercises[0]
assisted=next(e for e in exercises if e['assisted'])
plank=next(e for e in exercises if e['timed'])
for ex, values in [(bench,['40kg','42.5kg','45kg','47.5kg']), (assisted,['40','45','45','50']), (plank,['60']*4)]:
    for w, value in enumerate(values,1):
        prepared['entries'][f'{w}:{ex["id"]}:1']={'weight':'' if ex['timed'] else value,'reps':value if ex['timed'] else '8','note':'','source':'windows'}
prepared['entries']['5:d1e1:1']={'weight':'','reps':'','note':'Preserve existing note','source':'windows'}
applied=apply_debloat(prepared,debloat_plan(prepared))
sent=client.send_snapshot(prepared,response['revision'])
checks=[]
try:
    restart()
    # The first visible workout action opens the preview regardless of selected day.
    tap('Xem & áp dụng')
    labels=[n.attrib.get('text') or n.attrib.get('content-desc','') for n in tree().iter('node')]
    assert any('Tuần 5' in s and 'Debloat' in s for s in labels)
    tap('Áp dụng vào tuần 5')
    restart()
    response=pair()
    actual=normalize(response['data'])
    assert actual==applied, 'Android plan differs from the Python plan'
    assert sum(entry_complete(e) for e in actual['entries'].values())==12
    assert actual['entries']['5:d1e1:2']['weight']=='27.5kg'
    assert actual['entries'][f'5:{assisted["id"]}:1']['weight']=='67.5kg'
    assert actual['entries'][f'5:{plank["id"]}:1']['reps']=='35'
    checks += ['Android preview and apply UI', 'Android/Python exact snapshot parity for normal, assisted and timed sets', 'existing week-five note preserved', 'debloat labels and unconfirmed status survive Android restart and USB']
finally:
    # Restore only the emulator fixture, never a user's real phone.
    current=client.snapshot()
    client.send_snapshot(original,current['revision'])
    client.close()
report={'ok':True,'androidVersion':'1.4.0','windowsVersion':'1.1.0','checks':checks,'physicalPhoneTested':False}
(ROOT/'release/DEBLOAT-USB-TEST-REPORT.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False,indent=2))
