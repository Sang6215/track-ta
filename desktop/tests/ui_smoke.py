"""Render our own widgets offscreen and exercise the record editor."""
import os
os.environ['QT_QPA_PLATFORM']='offscreen'
import json
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from PySide6.QtWidgets import QApplication,QLineEdit,QDialog
from PySide6.QtGui import QFontDatabase
from PySide6.QtCore import QTimer
from trackta_core import Workspace,normalize,entry_complete
from window import MainWindow,EditDialog,STYLE

app=QApplication([])
for name in ['segoeui.ttf','segoeuib.ttf','seguisb.ttf']:
    QFontDatabase.addApplicationFont(str(Path('C:/Windows/Fonts')/name))
app.setStyle('Fusion')
app.setStyleSheet(STYLE)
with tempfile.TemporaryDirectory() as folder:
    seed=json.loads((Path(__file__).resolve().parents[2]/'assets/seed.json').read_text(encoding='utf-8'))
    ws=Workspace(folder,'test-phone')
    ws.accept_remote(normalize({'app':'trackta','version':1,'weeks':seed['weeks'],'entries':seed['entries']}))
    window=MainWindow(workspace=ws)
    window.show()
    app.processEvents()
    for index in range(7):
        window.show_page(index)
        app.processEvents()
    window.show_page(3)
    window.log_table.selectRow(0)
    def edit(dialog):
        fields=dialog.findChildren(QLineEdit)
        fields[0].setText('2x15kg')
        fields[1].setText('10')
        return 1
    with patch.object(EditDialog,'exec',edit):
        window.edit_entry()
    assert ws.doc['entries']['1:d1e1:1']['weight']=='2x15kg'
    assert Workspace(folder,'test-phone').doc['entries']['1:d1e1:1']['reps']=='10'
    window.show_page(2)
    app.processEvents()
    output=Path(__file__).resolve().parents[2]/'release/screenshots/windows-program.png'
    output.parent.mkdir(parents=True,exist_ok=True)
    assert window.grab().save(str(output))
    window.show_page(4)
    app.processEvents()
    assert window.grab().save(str(output.with_name('windows-progress.png')))
    window.show_page(3)
    assert window.debloat_button.isHidden()
    doc=json.loads(json.dumps(ws.doc))
    for week in range(1,5):
        doc['entries'][f'{week}:d1e1:1']={'weight':'40kg','reps':'8','note':'','source':'app'}
    assert window.commit(doc)
    confirmed_before = sum(entry_complete(e) for e in doc['entries'].values())
    assert not window.debloat_button.isHidden()
    with patch.object(QDialog,'exec',return_value=1):
        window.preview_debloat()
    app.processEvents()
    assert ws.doc['debloatWeeks']==[5]
    assert window.week.value()==5 and not window.debloat_badge.isHidden()
    assert window.metric_labels[1].text()==str(confirmed_before)
    assert ws.doc['entries']['5:d1e1:1']['source']=='debloat'
    assert window.grab().save(str(output.with_name('windows-debloat.png')))
    window.log_table.selectRow(0)
    with patch.object(EditDialog,'exec',lambda _: 1):
        window.edit_entry()
    assert ws.doc['entries']['5:d1e1:1']['source']=='windows'
    assert window.metric_labels[1].text()==str(confirmed_before+1)
    window.close()
print('Desktop UI: 7 pages render; edited set persists; screenshots saved.')
