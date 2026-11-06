"""Packaging check uses a temporary workspace, never the user's saved data."""
import json
import tempfile
import copy
from PySide6.QtCore import Qt
from PySide6.QtGui import QImage
from trackta_core import Workspace, normalize, resource_path, debloat_plan, apply_debloat, entry_complete
from usb_client import UsbClient
from window import MainWindow


def run(app, output, usb_test=None):
    output.mkdir(parents=True, exist_ok=True)
    client = None
    try:
        with tempfile.TemporaryDirectory() as folder:
            seed = json.loads(resource_path('assets/seed.json').read_text(encoding='utf-8'))
            ws = Workspace(folder, 'deployment-test')
            ws.accept_remote(normalize({'app':'trackta','version':1,'weeks':seed['weeks'],'entries':seed['entries']}))
            client = UsbClient()
            version = client.run('version')
            checks = ['seven pages render','program and log edits persist','JSON backup round trip','bundled adb starts']
            usb_report = None
            if usb_test:
                serial, code = usb_test
                if not serial.startswith('emulator-'):
                    raise ValueError('Deployment test may only connect to a test emulator.')
                assert any(d['serial'] == serial and d['state'] == 'device' for d in client.devices())
                client.pair(serial, code)
                snapshot = client.snapshot()
                ws.accept_remote(normalize(snapshot['data']))
                photos = client.photo_list()
                for photo in photos:
                    data = client.photo_bytes(photo['month'])
                    assert not QImage.fromData(data).isNull()
                    ws.save_photo(photo['month'], data, photo['revision'])
                usb_report = {'entries':len(ws.doc['entries']), 'photos':len(photos)}
                checks += ['packaged USB pairing and snapshot','packaged photo download and decoding']
            window = MainWindow(workspace=ws,client=client)
            window.setAttribute(Qt.WidgetAttribute.WA_DontShowOnScreen)
            window.show()
            app.processEvents()
            for index in range(7):
                window.show_page(index)
                app.processEvents()
            updated = copy.deepcopy(ws.doc)
            updated['days'][0]['exercises'][0]['name'] = 'Bench Press · kiểm tra Windows'
            for w, weight in enumerate(['40kg','42.5kg','45kg','47.5kg'],1):
                updated['entries'][f'{w}:d1e1:1'] = {'weight':weight,'reps':'8','note':'Kiểm tra đóng gói','source':'windows'}
            assert window.commit(updated)
            assert Workspace(folder, 'deployment-test').doc == ws.doc
            backup = ws.backup(ws.doc, 'deployment-test')
            assert normalize(json.loads(backup.read_text(encoding='utf-8'))) == ws.doc
            confirmed = sum(entry_complete(e) for e in ws.doc['entries'].values())
            assert window.commit(apply_debloat(ws.doc,debloat_plan(ws.doc)))
            assert ws.doc['debloatWeeks']==[5]
            assert ws.doc['entries']['5:d1e1:1']['weight']=='27.5kg'
            assert sum(entry_complete(e) for e in ws.doc['entries'].values())==confirmed
            assert Workspace(folder,'deployment-test').doc==ws.doc
            window.show_page(3)
            window.week.setValue(5)
            app.processEvents()
            assert window.grab().save(str(output / 'packaged-debloat.png'))
            checks.append('debloat suggestions and labels persist without adding completed sets')
            window.show_page(2)
            app.processEvents()
            assert window.grab().save(str(output / 'packaged-windows.png'))
            if usb_test:
                window.show_page(5)
                app.processEvents()
                assert window.grab().save(str(output / 'packaged-photos.png'))
            window.close()
            (output / 'deployment-check.json').write_text(json.dumps({
                'ok':True, 'platform':app.platformName(), 'seedEntries':len(seed['entries']),
                'checks':checks, 'adb':version, 'usbEmulator':usb_report,
            },indent=2),encoding='utf-8')
        return 0
    except Exception as exc:
        (output / 'deployment-check.json').write_text(json.dumps({'ok':False,'error':str(exc)}),encoding='utf-8')
        return 1
    finally:
        if client:
            client.close()
