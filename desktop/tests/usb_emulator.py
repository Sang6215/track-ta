"""End-to-end release check, restricted to the local Android test emulator."""
import base64
import copy
import hashlib
import json
from pathlib import Path
import re
import sys
import tempfile
import time
import xml.etree.ElementTree as ET

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from trackta_core import Workspace, normalize, debloat_plan, apply_debloat, entry_complete
from usb_client import UsbClient, ConflictError, UsbError

ROOT=Path(__file__).resolve().parents[2]
client=UsbClient()
SERIAL='emulator-5554'
assert SERIAL.startswith('emulator-')

def tree():
    client.run('shell','uiautomator','dump','/sdcard/trackta-usb-e2e.xml',selected=True)
    return ET.fromstring(client.run('shell','cat','/sdcard/trackta-usb-e2e.xml',selected=True))

def tap_text(prefix):
    for node in tree().iter('node'):
        value=node.attrib.get('text') or node.attrib.get('content-desc','')
        if value.startswith(prefix):
            x1,y1,x2,y2=map(int,re.findall(r'\d+',node.attrib['bounds']))
            client.run('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2),selected=True)
            time.sleep(.5)
            return
    raise AssertionError('UI not found: '+prefix)

response=client.pair(SERIAL,sys.argv[1])
original=normalize(response['data'])
assert original['entries']['3:d5e1:1']['weight']=='42.5kg', '1.1 edited log not preserved'
assert len(original['entries'])==108
photos={item['month']:item for item in client.photo_list()}
assert '2026-10' in photos,'1.1 camera photo not preserved'
original_photo=client.photo_bytes('2026-10')
assert hashlib.sha256(original_photo).hexdigest()==photos['2026-10']['revision']
checks=[]
with tempfile.TemporaryDirectory(prefix='trackta-usb-e2e-') as directory:
    ws=Workspace(directory,SERIAL)
    ws.accept_remote(original)
    ws.save_photo('2026-10',original_photo,photos['2026-10']['revision'])
    edited=copy.deepcopy(original)
    edited['days'][0]['exercises'][0]['name']='Bench Press · chỉnh trên Windows'
    edited['days'][0]['exercises'].append({'id':'ex_usb_test','name':'Glute bridge · USB test','target':'10-12','sets':2,'timed':False,'assisted':False,'archived':False,'primaryMuscles':['glutes'],'secondaryMuscles':['hamstrings']})
    edited['entries']['4:d1e1:1']={'weight':'2x15kg','reps':'8','note':'Đã gửi qua USB','source':'windows'}
    for w, weight in enumerate(['40kg','42.5kg','45kg','47.5kg'],1):
        edited['entries'][f'{w}:d1e1:1']={'weight':weight,'reps':'8','note':'','source':'windows'}
    edited=apply_debloat(edited,debloat_plan(edited))
    assert edited['debloatWeeks']==[5]
    assert edited['entries']['5:d1e1:1']['weight']=='27.5kg'
    ws.edit(edited)
    ws.backup(original,'phone-before-sync')
    sent=client.send_snapshot(ws.doc,response['revision'])
    assert normalize(sent['data'])==ws.doc
    assert not entry_complete(sent['data']['entries']['5:d1e1:1'])
    checks.append('debloat label and unconfirmed suggestions survive USB round trip')
    checks.append('program and set edit transmitted')
    try:
        client.send_snapshot(original,response['revision'])
        raise AssertionError('stale revision accepted')
    except ConflictError:
        checks.append('stale snapshot rejected')
    client.send_photo('2026-09',original_photo,None)
    ws.save_photo('2026-09',client.photo_bytes('2026-09'))
    png=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==')
    changed=client.send_photo('2026-10',png,photos['2026-10']['revision'])
    ws.save_photo('2026-10',png,changed['revision'])
    try:
        client.delete_photo('2026-10',photos['2026-10']['revision'])
        raise AssertionError('stale photo revision accepted')
    except ConflictError:
        checks.append('stale photo rejected')
    september=next(i for i in client.photo_list() if i['month']=='2026-09')
    client.delete_photo('2026-09',september['revision'])
    assert '2026-09' not in {i['month'] for i in client.photo_list()}
    assert len(list((ws.directory/'photos').glob('*.*')))>=4
    checks.append('photo backup, replacement and deletion with retained files')
    restored=client.send_photo('2026-10',original_photo,changed['revision'])
    ws.save_photo('2026-10',original_photo,restored['revision'])
    client.close()
    client.serial=SERIAL
    client.run('shell','am','force-stop','vn.trackta.track_ta',selected=True)
    client.open_app()
    time.sleep(1)
    tap_text('Dữ liệu')
    tap_text('Kết nối Windows qua USB')
    tap_text('Bắt đầu kết nối')
    code=next((n.attrib.get('text') or n.attrib.get('content-desc')) for n in tree().iter('node') if re.fullmatch(r'\d{6}',n.attrib.get('text') or n.attrib.get('content-desc','')))
    restarted=client.pair(SERIAL,code)
    assert normalize(restarted['data'])==normalize(sent['data'])
    assert client.photo_bytes('2026-10')==original_photo
    checks.append('program, logs and photo persist after process restart')
    client.send_snapshot(original,restarted['revision'])
    checks.append('original emulator data restored through protocol')
    client.token = 'invalid-test-token'
    try:
        client.snapshot()
        raise AssertionError('invalid session accepted')
    except UsbError:
        assert client.token is None
        checks.append('invalid session clears Windows pairing state')
    import os
    os.environ['QT_QPA_PLATFORM']='offscreen'
    from PySide6.QtWidgets import QApplication
    from PySide6.QtGui import QFontDatabase
    from window import MainWindow,STYLE
    app=QApplication([])
    for name in ['segoeui.ttf','segoeuib.ttf','seguisb.ttf']:
        QFontDatabase.addApplicationFont(str(Path('C:/Windows/Fonts')/name))
    app.setStyle('Fusion')
    app.setStyleSheet(STYLE)
    window=MainWindow(workspace=ws,client=client)
    window.show()
    window.show_page(5)
    app.processEvents()
    window.refresh_photos()
    app.processEvents()
    screenshot=ROOT/'release/screenshots/windows-photos.png'
    assert window.grab().save(str(screenshot))
    window.close()
report={'ok':True,'androidVersion':client.app_version(),'preservedUpgradeData':'1.1.0 to 1.3.0 to 1.4.0, same signature','originalEntries':108,'originalEditedWeight':'42.5kg','originalPhotoBytes':len(original_photo),'checks':checks,'physicalPhoneTested':False}
(ROOT/'release/USB-TEST-REPORT.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False,indent=2))
