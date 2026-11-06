from __future__ import annotations

import copy
import json
import os
from pathlib import Path
import sys

from PySide6.QtCore import Qt, QObject, QRunnable, QThreadPool, Signal, QSize
from PySide6.QtGui import QColor, QPainter, QPen, QPixmap, QImage, QDesktopServices
from PySide6.QtCore import QUrl
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout, QGridLayout,
    QLabel, QPushButton, QStackedWidget, QComboBox, QLineEdit, QSpinBox,
    QTableWidget, QTableWidgetItem, QHeaderView, QAbstractItemView, QDialog,
    QDialogButtonBox, QFormLayout, QCheckBox, QTextEdit, QMessageBox, QFileDialog,
    QListWidget, QSplitter, QFrame, QGroupBox, QScrollArea,
)

from trackta_core import (
    Workspace, MUSCLES, normalize, all_exercises, new_id, change_summary,
    merge_snapshots, export_csv, progress_values, atomic_json, guard_history,
    can_debloat, debloat_plan, apply_debloat, entry_complete,
)
from usb_client import UsbClient

STYLE = '''
QWidget { background:#101918; color:#eef4ee; font-family:"Segoe UI"; font-size:13px; }
QMainWindow { background:#101918; }
QWidget#sidebar { background:#192622; border-right:1px solid #304139; }
QLabel#brand { font-size:27px; font-weight:700; color:#d4f58a; }
QLabel#title { font-size:27px; font-weight:700; }
QLabel#muted { color:#a0b4aa; }
QLabel#metric { font-size:34px; font-weight:700; color:#d4f58a; }
QFrame#card { background:#1b2725; border:1px solid #304139; border-radius:12px; }
QFrame#card QLabel { background:transparent; }
QPushButton { background:#26382f; border:1px solid #3d5347; border-radius:7px; padding:9px 13px; }
QPushButton:hover { background:#354c3b; border-color:#81cdb8; }
QPushButton:pressed { background:#4d6648; }
QPushButton:disabled { color:#697a70; background:#1c2823; border-color:#2a3931; }
QPushButton#primary { background:#d4f58a; color:#101918; font-weight:700; border:0; }
QPushButton#primary:hover { background:#e3ffab; }
QPushButton#primary:disabled { background:#26382f; color:#697a70; }
QPushButton#nav { text-align:left; background:transparent; border:0; padding:13px 15px; }
QPushButton#nav:checked { background:#33482e; color:#d4f58a; font-weight:600; }
QLineEdit,QSpinBox,QComboBox,QTextEdit { background:#1b2725; border:1px solid #3c5044; border-radius:6px; padding:7px; selection-background-color:#4d6842; }
QComboBox QAbstractItemView { background:#223329; selection-background-color:#425d35; }
QTableWidget,QListWidget { background:#182420; alternate-background-color:#1e2e26; border:1px solid #304139; border-radius:6px; gridline-color:#304139; selection-background-color:#3d5734; }
QTableWidget::item { padding:6px; }
QHeaderView::section { background:#273a30; border:0; border-bottom:1px solid #415447; padding:10px; color:#a9c3b1; font-weight:600; }
QGroupBox { border:1px solid #304139; border-radius:9px; margin-top:12px; padding:15px; }
QGroupBox::title { subcontrol-origin:margin; left:12px; padding:0 5px; color:#a0b4aa; }
QCheckBox { spacing:8px; }
QScrollBar:vertical { background:#182420; width:10px; }
QScrollBar::handle:vertical { background:#49604f; min-height:22px; border-radius:4px; }
QScrollBar::add-line:vertical,QScrollBar::sub-line:vertical { height:0; }
QStatusBar { background:#192622; color:#a0b4aa; }
'''


def button(text, action=None, primary=False):
    result = QPushButton(text)
    if primary:
        result.setObjectName('primary')
    if action:
        result.clicked.connect(action)
    return result


def label(text, kind=None):
    result = QLabel(text)
    result.setWordWrap(True)
    if kind:
        result.setObjectName(kind)
    return result


def table(headers):
    result = QTableWidget(0, len(headers))
    result.setHorizontalHeaderLabels(headers)
    result.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
    result.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
    result.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
    result.setAlternatingRowColors(True)
    result.verticalHeader().hide()
    result.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.ResizeToContents)
    result.horizontalHeader().setStretchLastSection(True)
    return result


def fill_table(widget, rows):
    widget.setRowCount(len(rows))
    for r, row in enumerate(rows):
        for c, value in enumerate(row):
            widget.setItem(r, c, QTableWidgetItem(str(value)))


class TaskSignals(QObject):
    completed = Signal(object)


class Task(QRunnable):
    def __init__(self, work):
        super().__init__()
        self.work = work
        self.signals = TaskSignals()

    def run(self):
        try:
            self.signals.completed.emit((True, self.work()))
        except Exception as exc:
            self.signals.completed.emit((False, str(exc)))


class EditDialog(QDialog):
    def __init__(self, title, parent):
        super().__init__(parent)
        self.setWindowTitle(title)
        self.setMinimumWidth(460)
        self.layout = QVBoxLayout(self)
        self.form = QFormLayout()
        self.form.setSpacing(12)
        self.layout.addLayout(self.form)
        self.buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Save | QDialogButtonBox.StandardButton.Cancel)
        self.buttons.button(QDialogButtonBox.StandardButton.Save).setText('Lưu trên Windows')
        self.buttons.button(QDialogButtonBox.StandardButton.Cancel).setText('Hủy')
        self.buttons.accepted.connect(self.accept)
        self.buttons.rejected.connect(self.reject)

    def finish(self):
        self.layout.addWidget(self.buttons)


class TrendChart(QWidget):
    def __init__(self):
        super().__init__()
        self.values = []
        self.setMinimumHeight(235)

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        x0, y0, width, height = 42, 24, self.width() - 72, self.height() - 66
        maximum = max([v for v in self.values if v is not None] + [1]) * 1.15
        painter.setPen(QPen(QColor('#304139'), 1))
        for n in range(4):
            y = y0 + height * n / 3
            painter.drawLine(x0, int(y), x0 + width, int(y))
        previous = None
        for index, value in enumerate(self.values):
            x = x0 + width * index / max(1, len(self.values) - 1)
            if len(self.values) <= 20:
                painter.setPen(QColor('#a0b4aa'))
                painter.drawText(int(x - 10), int(y0 + height + 26), f'T{index + 1}')
            if value is None:
                previous = None
                continue
            y = y0 + height - height * value / maximum
            painter.setPen(QPen(QColor('#d4f58a'), 2.5))
            if previous:
                painter.drawLine(int(previous[0]), int(previous[1]), int(x), int(y))
            painter.setBrush(QColor('#d4f58a'))
            painter.drawEllipse(int(x - 4), int(y - 4), 8, 8)
            if len(self.values) <= 20:
                painter.drawText(int(x - 14), int(y - 12), f'{value:g}')
            previous = (x, y)
        if not any(v is not None for v in self.values):
            painter.setPen(QColor('#a0b4aa'))
            painter.drawText(self.rect(), Qt.AlignmentFlag.AlignCenter, 'Chưa có dữ liệu cho bài tập này')


class MainWindow(QMainWindow):
    def __init__(self, workspace=None, client=None):
        super().__init__()
        self.setWindowTitle('Track Tạ Windows 1.2.0 · USB')
        self.resize(1280, 840)
        self.setMinimumSize(1000, 700)
        root = Path(os.environ.get('LOCALAPPDATA', Path.home())) / 'TrackTaWindows'
        serial = 'offline'
        last = root / 'last.json'
        if last.exists():
            try:
                serial = json.loads(last.read_text(encoding='utf-8'))['serial']
            except (ValueError, KeyError, OSError):
                pass
        self.ws = workspace or Workspace(root, serial)
        self.client = client or UsbClient()
        self.remote = None
        self.devices = []
        self.photo_remote = {}
        self.busy = False
        self.tasks = []
        self.log_keys = []
        self.exercise_keys = []
        self.pages = QStackedWidget()
        central = QWidget()
        outer = QHBoxLayout(central)
        outer.setContentsMargins(0, 0, 0, 0)
        sidebar = QWidget()
        sidebar.setObjectName('sidebar')
        sidebar.setFixedWidth(210)
        left = QVBoxLayout(sidebar)
        left.setContentsMargins(20, 28, 20, 22)
        left.addWidget(label('track tạ', 'brand'))
        left.addWidget(label('WINDOWS · USB', 'muted'))
        left.addSpacing(28)
        self.nav = []
        for index, name in enumerate(['Tổng quan', 'Kết nối USB', 'Lịch & bài tập', 'Nhật ký', 'Tiến độ', 'Ảnh tháng', 'Sao lưu']):
            b = button(name, lambda checked=False, i=index: self.show_page(i))
            b.setObjectName('nav')
            b.setCheckable(True)
            self.nav.append(b)
            left.addWidget(b)
        left.addStretch()
        left.addWidget(label('Bản làm việc lưu tự động\nĐồng bộ khi bạn bấm gửi', 'muted'))
        self.connection_badge = label('Chưa ghép nối', 'muted')
        left.addWidget(self.connection_badge)
        outer.addWidget(sidebar)
        right = QVBoxLayout()
        right.setContentsMargins(28, 24, 28, 18)
        top = QHBoxLayout()
        self.title_label = label('Tổng quan', 'title')
        top.addWidget(self.title_label)
        top.addStretch()
        self.sync_button = button('Xem trước & đồng bộ', self.sync, True)
        top.addWidget(self.sync_button)
        right.addLayout(top)
        self.local_status = label('', 'muted')
        right.addWidget(self.local_status)
        right.addSpacing(12)
        right.addWidget(self.pages)
        outer.addLayout(right, 1)
        self.setCentralWidget(central)
        self.make_overview()
        self.make_connection()
        self.make_program()
        self.make_log()
        self.make_progress()
        self.make_photos()
        self.make_backups()
        self.refresh_all()
        self.show_page(0)
        self.statusBar().showMessage('Sẵn sàng · Không cần tài khoản')

    def show_page(self, index):
        self.pages.setCurrentIndex(index)
        self.title_label.setText(self.nav[index].text())
        for n, b in enumerate(self.nav):
            b.setChecked(n == index)

    def execute(self, work, success, message):
        if self.busy:
            return
        self.busy = True
        self.centralWidget().setEnabled(False)
        self.statusBar().showMessage(message)
        task = Task(work)
        self.tasks.append(task)
        def done(result):
            self.busy = False
            self.centralWidget().setEnabled(True)
            self.tasks.remove(task)
            self.statusBar().showMessage('Sẵn sàng')
            if result[0]:
                try:
                    success(result[1])
                except Exception as exc:
                    self.error(str(exc))
            else:
                self.error(result[1])
            self.refresh_connection()
        task.signals.completed.connect(done)
        QThreadPool.globalInstance().start(task)

    def error(self, message):
        QMessageBox.warning(self, 'Chưa hoàn tất', message)

    def need_doc(self):
        if self.ws.doc is None:
            self.error('Ghép nối điện thoại để lấy dữ liệu, hoặc mở một bản sao lưu JSON trước.')
            return False
        return True

    def need_connection(self):
        if not self.client.token:
            self.show_page(1)
            self.error('Nhập mã trên điện thoại để ghép nối qua USB.')
            return False
        return True

    def commit(self, doc):
        try:
            self.ws.edit(doc)
            self.refresh_all()
            self.statusBar().showMessage('Đã lưu bản làm việc trên Windows. Bấm đồng bộ để gửi sang điện thoại.')
            return True
        except Exception as exc:
            self.error(str(exc))
            return False

    def refresh_all(self):
        changes = len(change_summary(self.ws.baseline, self.ws.doc)) if self.ws.doc else 0
        self.local_status.setText(f'{changes} mục chưa gửi · Đã lưu trên Windows' if self.ws.dirty else 'Bản làm việc đã khớp lần đồng bộ gần nhất' if self.ws.doc else 'Ghép nối USB để lấy nhật ký đang dùng trên điện thoại')
        self.refresh_connection()
        self.refresh_overview()
        self.refresh_program()
        self.refresh_log_filters()
        self.refresh_progress_filters()
        self.refresh_photos()
        self.refresh_backups()

    def refresh_connection(self):
        self.connection_badge.setText('Đã kết nối USB' if self.client.token else 'Chưa ghép nối')
        self.sync_button.setEnabled(bool(self.client.token and self.ws.doc))

    def page(self):
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(15)
        self.pages.addWidget(page)
        return layout

    def make_overview(self):
        layout = self.page()
        layout.addWidget(label('Nhật ký điện thoại, dễ chỉnh sửa trên máy tính.', 'muted'))
        metrics = QHBoxLayout()
        self.metric_labels = []
        for name in ['Bài đang tập', 'Hiệp đã ghi', 'Tuần có dữ liệu']:
            frame = QFrame()
            frame.setObjectName('card')
            box = QVBoxLayout(frame)
            box.setContentsMargins(22, 20, 22, 20)
            value = label('—', 'metric')
            self.metric_labels.append(value)
            box.addWidget(value)
            box.addWidget(label(name, 'muted'))
            metrics.addWidget(frame)
        layout.addLayout(metrics)
        steps = QGroupBox('Bắt đầu từ bản 1.1.0 của bạn')
        box = QVBoxLayout(steps)
        box.addWidget(label('1. Xuất một bản JSON trên điện thoại để giữ riêng.\n2. Cài đè APK 1.5.0 đi kèm.\n3. Bật Gỡ lỗi USB, cắm cáp và cho phép máy tính.\n4. Mở Dữ liệu → Kết nối Windows qua USB trên điện thoại, rồi nhập mã vào đây.'))
        actions = QHBoxLayout()
        actions.addWidget(button('Kết nối điện thoại', lambda: self.show_page(1), True))
        actions.addWidget(button('Mở bản sao lưu JSON', self.import_json))
        box.addLayout(actions)
        layout.addWidget(steps)
        layout.addWidget(label('Có thể chỉnh sửa khi chưa cắm điện thoại. Khi kết nối lại, app so sánh dữ liệu mới và cho xem thay đổi trước khi gửi. Ảnh tháng có bản sao riêng trên Windows.', 'muted'))
        layout.addStretch()

    def refresh_overview(self):
        doc = self.ws.doc
        if not doc:
            return
        values = [sum(not e['archived'] for _, e in all_exercises(doc).values()),
                  sum(entry_complete(e) for e in doc['entries'].values()),
                  len({k.split(':')[0] for k, e in doc['entries'].items() if entry_complete(e)})]
        for widget, value in zip(self.metric_labels, values):
            widget.setText(str(value))

    def make_connection(self):
        layout = self.page()
        layout.addWidget(label('Cáp USB cần hỗ trợ truyền dữ liệu. Mở khóa điện thoại và cho phép máy tính khi Android hỏi.', 'muted'))
        box = QGroupBox('Điện thoại')
        form = QFormLayout(box)
        row = QHBoxLayout()
        self.device_combo = QComboBox()
        row.addWidget(self.device_combo, 1)
        row.addWidget(button('Tìm thiết bị', self.scan_devices))
        form.addRow('Thiết bị USB', row)
        self.code_input = QLineEdit()
        self.code_input.setPlaceholderText('6 số hiển thị trong Track Tạ trên điện thoại')
        self.code_input.setMaxLength(6)
        form.addRow('Mã ghép nối', self.code_input)
        actions = QHBoxLayout()
        actions.addWidget(button('Ghép nối & tải dữ liệu', self.pair, True))
        actions.addWidget(button('Ngắt kết nối', self.disconnect))
        form.addRow(actions)
        layout.addWidget(box)
        self.connection_text = label('Chưa ghép nối. Trong điện thoại: Dữ liệu → Kết nối Windows qua USB → Bắt đầu kết nối.', 'muted')
        layout.addWidget(self.connection_text)
        row = QHBoxLayout()
        row.addWidget(button('Cài bản Android hỗ trợ USB', self.install_phone))
        row.addWidget(button('Mở app trên điện thoại', self.open_phone))
        row.addStretch()
        layout.addLayout(row)
        layout.addWidget(label('Bản Android 1.1.0 chưa nhận chỉnh sửa qua USB. Cài đè 1.5.0 bằng APK cùng chữ ký để giữ dữ liệu. Chọn “Gỡ lỗi USB” trong Tùy chọn nhà phát triển; mã ghép nối chỉ dùng cho phiên hiện tại.', 'muted'))
        layout.addStretch()

    def scan_devices(self):
        def got(devices):
            self.devices = devices
            self.device_combo.clear()
            for d in devices:
                state = {'device': 'Sẵn sàng', 'unauthorized': 'Chờ cho phép trên điện thoại', 'offline': 'Chưa phản hồi'}.get(d['state'], d['state'])
                self.device_combo.addItem(f"{d['model']} · {state}", d['serial'])
            self.connection_text.setText('Không tìm thấy điện thoại. Kiểm tra cáp, bật Gỡ lỗi USB và driver USB của hãng.' if not devices else 'Chọn điện thoại và nhập mã ghép nối. Nếu chờ cho phép, mở khóa điện thoại và chấp nhận máy tính.')
        self.execute(self.client.devices, got, 'Đang tìm thiết bị USB…')

    def selected_serial(self):
        serial = self.device_combo.currentData()
        device = next((d for d in self.devices if d['serial'] == serial), None)
        if not device or device['state'] != 'device':
            self.error('Tìm thiết bị và cho phép máy tính trên điện thoại trước.')
            return None
        return serial

    def pair(self):
        serial = self.selected_serial()
        code = self.code_input.text().strip()
        if not serial:
            return
        if len(code) != 6 or not code.isdigit():
            self.error('Nhập đúng mã 6 số trong màn hình kết nối của điện thoại.')
            return
        def got(response):
            previous = self.ws
            ws = Workspace(self.ws.root, serial)
            remote = normalize(response['data'])
            if ws.doc is None and previous.serial == 'offline' and previous.doc:
                use = QMessageBox.question(self, 'Bản làm việc ngoại tuyến', 'Bạn đang có bản JSON đã chỉnh trên Windows. Dùng bản này để so sánh và đồng bộ với điện thoại?', QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
                if use == QMessageBox.StandardButton.Yes:
                    ws.doc = copy.deepcopy(previous.doc)
                    ws.save()
            if not ws.dirty:
                ws.accept_remote(remote)
            self.ws, self.remote = ws, response
            atomic_json(ws.root / 'last.json', {'serial': serial})
            self.photo_remote = {}
            self.code_input.clear()
            self.connection_badge.setText('Đã kết nối USB')
            self.connection_text.setText('Đã ghép nối. Bản làm việc có thể chỉnh sửa; điện thoại chỉ thay đổi khi bạn gửi.')
            self.refresh_all()
            self.show_page(2)
        self.execute(lambda: self.client.pair(serial, code), got, 'Đang ghép nối và tải nhật ký…')

    def disconnect(self):
        self.execute(self.client.close, lambda _: self.disconnected(), 'Đang đóng kết nối…')

    def disconnected(self):
        self.connection_badge.setText('Chưa ghép nối')
        self.connection_text.setText('Đã ngắt USB. Bản làm việc và ảnh sao lưu vẫn có trên Windows.')
        self.refresh_all()

    def install_phone(self):
        serial = self.selected_serial()
        if not serial:
            return
        root = Path(sys.executable).parent if getattr(sys, 'frozen', False) else Path(__file__).resolve().parents[1] / 'release'
        apk = root / 'Track-Ta-v1.5.0.apk'
        if not apk.exists():
            path, _ = QFileDialog.getOpenFileName(self, 'Chọn APK hỗ trợ USB', str(root), 'Android (*.apk)')
            if not path:
                return
            apk = Path(path)
        if QMessageBox.question(self, 'Cập nhật điện thoại', 'Cài đè Track Tạ 1.5.0 trên điện thoại đã chọn? Nên xuất bản JSON trong app 1.1.0 trước. Thao tác dùng APK cùng chữ ký và giữ dữ liệu app.', QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No) != QMessageBox.StandardButton.Yes:
            return
        self.client.close()
        self.client.serial = serial
        self.execute(lambda: self.client.install(apk), lambda _: self.connection_text.setText('Đã cài bản hỗ trợ USB. Trên điện thoại: Dữ liệu → Kết nối Windows qua USB → Bắt đầu kết nối.'), 'Đang cài bản cập nhật, giữ cáp cắm…')

    def open_phone(self):
        serial = self.selected_serial()
        if serial:
            if self.client.serial != serial and self.client.token:
                self.client.close()
                self.disconnected()
            self.client.serial = serial
            self.execute(self.client.open_app, lambda _: None, 'Đang mở Track Tạ trên điện thoại…')

    def make_program(self):
        layout = self.page()
        toolbar = QHBoxLayout()
        toolbar.addWidget(button('Thêm buổi', self.add_day))
        toolbar.addWidget(button('Sửa buổi', self.edit_day))
        toolbar.addWidget(button('Nhân bản buổi', self.duplicate_day))
        toolbar.addStretch()
        layout.addLayout(toolbar)
        splitter = QSplitter()
        self.day_list = QListWidget()
        self.day_list.setMaximumWidth(215)
        self.day_list.currentRowChanged.connect(self.refresh_exercises)
        splitter.addWidget(self.day_list)
        right = QWidget()
        box = QVBoxLayout(right)
        box.setContentsMargins(0, 0, 0, 0)
        actions = QHBoxLayout()
        for name, action in [('Thêm bài', self.add_exercise), ('Sửa bài', self.edit_exercise), ('Lưu trữ / mở lại', self.archive_exercise), ('↑', lambda: self.move_exercise(-1)), ('↓', lambda: self.move_exercise(1))]:
            actions.addWidget(button(name, action))
        actions.addStretch()
        box.addLayout(actions)
        self.exercise_table = table(['Bài tập', 'Hiệp', 'Mục tiêu', 'Cách đo', 'Trạng thái'])
        self.exercise_table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        self.exercise_table.cellDoubleClicked.connect(lambda *_: self.edit_exercise())
        box.addWidget(self.exercise_table)
        splitter.addWidget(right)
        splitter.setStretchFactor(1, 1)
        layout.addWidget(splitter, 1)
        layout.addWidget(label('Lưu trữ giúp bỏ bài khỏi buổi đang tập và giữ lịch sử. Bài có nhật ký được giữ mã và cách đo; tạo bài mới nếu chuyển sang loại khác.', 'muted'))

    def refresh_program(self):
        selected = self.day_list.currentRow()
        self.day_list.blockSignals(True)
        self.day_list.clear()
        if self.ws.doc:
            for d in self.ws.doc['days']:
                self.day_list.addItem(f"{d['name']}\n{'Chủ nhật' if d['weekday'] == 7 else 'Thứ ' + str(d['weekday'] + 1)}")
            self.day_list.setCurrentRow(max(0, min(selected, len(self.ws.doc['days']) - 1)))
        self.day_list.blockSignals(False)
        self.refresh_exercises()

    def day_index(self):
        return max(0, self.day_list.currentRow())

    def refresh_exercises(self, *_):
        self.exercise_keys = []
        rows = []
        if self.ws.doc:
            d = self.ws.doc['days'][self.day_index()]
            for e in d['exercises']:
                self.exercise_keys.append(e['id'])
                rows.append([e['name'], e['sets'], e['target'], 'Giây' if e['timed'] else 'Kg trợ lực' if e['assisted'] else 'Kg × reps', 'Đã lưu trữ' if e['archived'] else 'Đang tập'])
        fill_table(self.exercise_table, rows)

    def day_dialog(self, data):
        dlg = EditDialog('Buổi tập', self)
        name, subtitle = QLineEdit(data['name']), QLineEdit(data['subtitle'])
        weekday = QComboBox()
        weekday.addItems(['Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'Chủ nhật'])
        weekday.setCurrentIndex(data['weekday'] - 1)
        dlg.form.addRow('Tên buổi', name)
        dlg.form.addRow('Mô tả', subtitle)
        dlg.form.addRow('Ngày tập', weekday)
        dlg.finish()
        if dlg.exec():
            return {**data, 'name': name.text().strip(), 'subtitle': subtitle.text(), 'weekday': weekday.currentIndex() + 1}

    def add_day(self):
        if not self.need_doc():
            return
        item = {'id': new_id('day_'), 'name': 'Buổi mới', 'subtitle': '', 'weekday': 1,
                'exercises': [{'id': new_id('ex_'), 'name': 'Bài tập mới', 'target': '8-12', 'sets': 3, 'timed': False, 'assisted': False}]}
        result = self.day_dialog(item)
        if result:
            doc = copy.deepcopy(self.ws.doc)
            doc['days'].append(result)
            if self.commit(doc):
                self.day_list.setCurrentRow(len(doc['days']) - 1)

    def edit_day(self):
        if self.need_doc():
            doc = copy.deepcopy(self.ws.doc)
            result = self.day_dialog(doc['days'][self.day_index()])
            if result:
                doc['days'][self.day_index()] = result
                self.commit(doc)

    def duplicate_day(self):
        if not self.need_doc():
            return
        doc = copy.deepcopy(self.ws.doc)
        day = copy.deepcopy(doc['days'][self.day_index()])
        day['id'] = new_id('day_')
        day['name'] += ' (bản sao)'
        for e in day['exercises']:
            e['id'] = new_id('ex_')
        doc['days'].append(day)
        self.commit(doc)

    def exercise_dialog(self, data):
        dlg = EditDialog('Chỉnh sửa bài tập', self)
        name, target = QLineEdit(data['name']), QLineEdit(data['target'])
        sets = QSpinBox()
        sets.setRange(1, 30)
        sets.setValue(data['sets'])
        mode = QComboBox()
        mode.addItems(['Tạ và reps', 'Thời gian (giây)', 'Tạ trợ lực và reps'])
        mode.setCurrentIndex(1 if data['timed'] else 2 if data['assisted'] else 0)
        if self.ws.doc and any(k.split(':')[1] == data['id'] for k in self.ws.doc['entries']):
            mode.setEnabled(False)
        dlg.form.addRow('Tên bài', name)
        dlg.form.addRow('Mục tiêu reps / giây', target)
        dlg.form.addRow('Số hiệp', sets)
        dlg.form.addRow('Cách đo', mode)
        groups = QGroupBox('Nhóm cơ chính / phụ (tùy chọn)')
        grid = QGridLayout(groups)
        checks = []
        grid.addWidget(label('Nhóm cơ'), 0, 0)
        grid.addWidget(label('Chính'), 0, 1)
        grid.addWidget(label('Phụ'), 0, 2)
        for i, (key, title) in enumerate(MUSCLES.items(), 1):
            primary, secondary = QCheckBox(), QCheckBox()
            primary.setChecked(key in data.get('primaryMuscles', []))
            secondary.setChecked(key in data.get('secondaryMuscles', []))
            grid.addWidget(label(title), i, 0)
            grid.addWidget(primary, i, 1)
            grid.addWidget(secondary, i, 2)
            checks.append((key, primary, secondary))
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setWidget(groups)
        scroll.setMaximumHeight(225)
        dlg.layout.addWidget(scroll)
        dlg.layout.addWidget(label('Để trống để dùng phân loại sẵn của bài gốc. Số hiệp cần giữ đủ các hiệp đã ghi.', 'muted'))
        dlg.finish()
        if dlg.exec():
            return {**data, 'name': name.text().strip(), 'target': target.text().strip(), 'sets': sets.value(),
                    'timed': mode.currentIndex() == 1, 'assisted': mode.currentIndex() == 2,
                    'primaryMuscles': [k for k, p, s in checks if p.isChecked()],
                    'secondaryMuscles': [k for k, p, s in checks if s.isChecked()]}

    def add_exercise(self):
        if not self.need_doc():
            return
        data = {'id': new_id('ex_'), 'name': '', 'target': '8-12', 'sets': 3, 'timed': False, 'assisted': False, 'archived': False}
        result = self.exercise_dialog(data)
        if result:
            doc = copy.deepcopy(self.ws.doc)
            doc['days'][self.day_index()]['exercises'].append(result)
            self.commit(doc)

    def selected_exercise(self):
        row = self.exercise_table.currentRow()
        return row if 0 <= row < len(self.exercise_keys) else None

    def edit_exercise(self):
        row = self.selected_exercise()
        if row is not None:
            doc = copy.deepcopy(self.ws.doc)
            result = self.exercise_dialog(doc['days'][self.day_index()]['exercises'][row])
            if result:
                doc['days'][self.day_index()]['exercises'][row] = result
                self.commit(doc)

    def archive_exercise(self):
        row = self.selected_exercise()
        if row is not None:
            doc = copy.deepcopy(self.ws.doc)
            e = doc['days'][self.day_index()]['exercises'][row]
            e['archived'] = not e['archived']
            self.commit(doc)

    def move_exercise(self, delta):
        row = self.selected_exercise()
        if row is not None:
            doc = copy.deepcopy(self.ws.doc)
            items = doc['days'][self.day_index()]['exercises']
            dest = row + delta
            if 0 <= dest < len(items):
                items[row], items[dest] = items[dest], items[row]
                if self.commit(doc):
                    self.exercise_table.selectRow(dest)

    def make_log(self):
        layout = self.page()
        filters = QHBoxLayout()
        self.week = QSpinBox()
        self.week.setPrefix('Tuần ')
        self.week.setRange(1, 8)
        self.week.valueChanged.connect(self.refresh_log)
        self.log_day = QComboBox()
        self.log_day.currentIndexChanged.connect(self.refresh_log)
        self.log_search = QLineEdit()
        self.log_search.setPlaceholderText('Tìm tên bài…')
        self.log_search.textChanged.connect(self.refresh_log)
        self.archived_check = QCheckBox('Cả bài đã lưu trữ')
        self.archived_check.toggled.connect(self.refresh_log)
        for w in [self.week, self.log_day, self.log_search, self.archived_check]:
            filters.addWidget(w)
        filters.addWidget(button('Thêm tuần trống', self.add_week))
        layout.addLayout(filters)
        self.log_table = table(['Buổi', 'Bài tập', 'Hiệp', 'Tuần trước', 'Tạ', 'Reps / giây', 'Ghi chú'])
        self.log_table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        self.log_table.cellDoubleClicked.connect(lambda *_: self.edit_entry())
        layout.addWidget(self.log_table, 1)
        row = QHBoxLayout()
        row.addWidget(button('Sửa hiệp đã chọn', self.edit_entry, True))
        self.debloat_button = button('Tuần debloat', self.preview_debloat)
        row.addWidget(self.debloat_button)
        self.debloat_badge = label('DEBLOAT · Gợi ý chưa tính là đã tập', 'muted')
        row.addWidget(self.debloat_badge)
        row.addStretch()
        row.addWidget(button('Xuất CSV', self.csv_export))
        layout.addLayout(row)

    def refresh_log_filters(self):
        previous = self.log_day.currentData()
        self.log_day.blockSignals(True)
        self.log_day.clear()
        self.log_day.addItem('Tất cả buổi', None)
        if self.ws.doc:
            for day in self.ws.doc['days']:
                self.log_day.addItem(day['name'], day['id'])
            self.week.setMaximum(self.ws.doc['weeks'])
        index = self.log_day.findData(previous)
        self.log_day.setCurrentIndex(max(0, index))
        self.log_day.blockSignals(False)
        self.refresh_log()

    def refresh_log(self, *_):
        self.log_keys = []
        rows = []
        self.debloat_button.setVisible(bool(self.ws.doc and can_debloat(self.ws.doc)))
        self.debloat_badge.setVisible(bool(self.ws.doc and self.week.value() in self.ws.doc.get('debloatWeeks', [])))
        if self.ws.doc:
            week = self.week.value()
            for day in self.ws.doc['days']:
                if self.log_day.currentData() and day['id'] != self.log_day.currentData():
                    continue
                for ex in day['exercises']:
                    if ex['archived'] and not self.archived_check.isChecked() or self.log_search.text().casefold() not in ex['name'].casefold():
                        continue
                    for s in range(1, ex['sets'] + 1):
                        key = f'{week}:{ex["id"]}:{s}'
                        entry = self.ws.doc['entries'].get(key, {})
                        prev = self.ws.doc['entries'].get(f'{week-1}:{ex["id"]}:{s}', {})
                        display = f"{prev.get('reps', '—')} giây" if ex['timed'] and prev else f"{prev.get('weight') or 'BW'} × {prev.get('reps') or '—'}" if prev else '—'
                        rows.append([day['name'], ex['name'], s, display, entry.get('weight', ''), entry.get('reps', ''), entry.get('note', '')])
                        self.log_keys.append(key)
        fill_table(self.log_table, rows)
        for row, key in enumerate(self.log_keys):
            if self.ws.doc['entries'].get(key, {}).get('source') == 'debloat':
                for col in range(self.log_table.columnCount()):
                    self.log_table.item(row, col).setForeground(QColor('#81cdb8'))
                    self.log_table.item(row, col).setToolTip('Gợi ý debloat · Mở và lưu hiệp sau khi tập để xác nhận.')
                item = self.log_table.item(row, 1)
                item.setText('Gợi ý · ' + item.text())

    def preview_debloat(self):
        if not self.need_doc() or not can_debloat(self.ws.doc):
            return
        plan = debloat_plan(self.ws.doc)
        dlg = QDialog(self)
        dlg.setWindowTitle('Tuần 5 · Debloat')
        dlg.resize(1050, 650)
        box = QVBoxLayout(dlg)
        box.addWidget(label(f"{len(plan['values'])} hiệp trống sẽ điền · {plan['preservedSets']} hiệp đã có được giữ (ở các bài đủ dữ liệu)."))
        box.addWidget(label('Hồi quy trên các tuần có dữ liệu trong tuần 1–4 (bài có 1–3 tuần vẫn tính; tuần thiếu không tính là 0), kẹp dự báo trong 0–mức tốt nhất đã ghi (trợ lực: thấp nhất). Tạ/giây ×60%; trợ lực ÷60%. Tạ làm tròn 2,5 kg mỗi quả khi ghi 2x; trợ lực làm tròn lên; giây làm tròn 5, tối thiểu 5 giây. Gợi ý chưa tính là đã tập.'))
        preview = table(['Bài tập', 'Tuần 1–4', 'Dự báo → giới hạn', 'Đề xuất', 'Reps / giây', 'Dữ liệu', 'Điền / giữ'])
        rows = []
        for s in plan['suggestions']:
            weekly = ' → '.join(('BW' if s['forecast'] is None else '—') if v is None else f'{v:g}' for v in s['weeklyValues'])
            prediction = 'BW' if s['forecast'] is None else f"{s['rawForecast']:g} → {s['forecast']:g}"
            rows.append([s['exercise']['name'], weekly, prediction, s['weight'] or ('Giây' if s['exercise']['timed'] else 'BW'), s['reps'], f"{s['weeksUsed']}/4", f"{s['emptySets']} / {s['preservedSets']}"])
        fill_table(preview, rows)
        box.addWidget(preview, 1)
        skipped = QTextEdit()
        skipped.setReadOnly(True)
        skipped.setMaximumHeight(120)
        skipped.setPlainText('\n'.join(f"Bỏ qua {s['exercise']['name']}: {s['reason']}" for s in plan['skipped']) or 'Tất cả bài đang tập đều đủ dữ liệu.')
        box.addWidget(skipped)
        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
        buttons.button(QDialogButtonBox.StandardButton.Ok).setText('Áp dụng vào tuần 5 trên Windows')
        buttons.button(QDialogButtonBox.StandardButton.Ok).setEnabled(bool(plan['suggestions']))
        buttons.accepted.connect(dlg.accept)
        buttons.rejected.connect(dlg.reject)
        box.addWidget(buttons)
        if dlg.exec():
            try:
                fresh = debloat_plan(self.ws.doc)
                self.ws.backup(self.ws.doc, 'before-debloat')
                if self.commit(apply_debloat(self.ws.doc, fresh)):
                    self.week.setValue(5)
                    self.statusBar().showMessage(f"Đã điền {len(fresh['values'])} hiệp gợi ý trên Windows. Bấm đồng bộ để gửi điện thoại.")
            except Exception as exc:
                self.error(str(exc))

    def edit_entry(self):
        row = self.log_table.currentRow()
        if not 0 <= row < len(self.log_keys):
            return
        key = self.log_keys[row]
        ex = all_exercises(self.ws.doc)[key.split(':')[1]][1]
        data = self.ws.doc['entries'].get(key, {})
        dlg = EditDialog(f'Tuần {self.week.value()} · Hiệp {key.split(":")[2]}', self)
        dlg.layout.insertWidget(0, label(ex['name']))
        weight, reps, note = QLineEdit(data.get('weight', '')), QLineEdit(data.get('reps', '')), QTextEdit(data.get('note', ''))
        weight.setPlaceholderText('35kg hoặc 2x12.5kg; để trống nếu BW')
        weight.setMaxLength(40)
        weight.setEnabled(not ex['timed'])
        reps.setMaxLength(5)
        note.setMaximumHeight(100)
        dlg.form.addRow('Tạ trợ lực (kg)' if ex['assisted'] else 'Tạ (kg)', weight)
        dlg.form.addRow('Giây' if ex['timed'] else 'Reps', reps)
        dlg.form.addRow('Ghi chú', note)
        clear = QCheckBox('Xóa dữ liệu hiệp này')
        dlg.form.addRow(clear)
        dlg.finish()
        if dlg.exec():
            doc = copy.deepcopy(self.ws.doc)
            values = {'weight': '' if ex['timed'] else weight.text().strip(), 'reps': reps.text().strip(), 'note': note.toPlainText(), 'source': 'windows'}
            if clear.isChecked() or not any(values[k] for k in ('weight', 'reps', 'note')):
                doc['entries'].pop(key, None)
            else:
                doc['entries'][key] = values
            self.commit(doc)

    def add_week(self):
        if self.need_doc():
            doc = copy.deepcopy(self.ws.doc)
            doc['weeks'] += 1
            if self.commit(doc):
                self.week.setValue(doc['weeks'])

    def make_progress(self):
        layout = self.page()
        self.progress_ex = QComboBox()
        self.progress_ex.currentIndexChanged.connect(self.refresh_chart)
        layout.addWidget(self.progress_ex)
        self.chart = TrendChart()
        layout.addWidget(self.chart)
        self.chart_note = label('', 'muted')
        layout.addWidget(self.chart_note)
        row = QHBoxLayout()
        self.compare_a, self.compare_b = QSpinBox(), QSpinBox()
        self.compare_a.setPrefix('Tuần A: ')
        self.compare_b.setPrefix('Tuần B: ')
        self.compare_a.setRange(1, 8)
        self.compare_b.setRange(1, 8)
        self.compare_b.setValue(2)
        self.compare_a.valueChanged.connect(self.refresh_comparison)
        self.compare_b.valueChanged.connect(self.refresh_comparison)
        row.addWidget(self.compare_a)
        row.addWidget(self.compare_b)
        row.addStretch()
        layout.addLayout(row)
        self.compare_table = table(['Bài tập', 'Cách đo', 'Tuần A', 'Tuần B', 'Thay đổi'])
        self.compare_table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        layout.addWidget(self.compare_table, 1)

    def refresh_progress_filters(self):
        previous = self.progress_ex.currentData()
        self.progress_ex.blockSignals(True)
        self.progress_ex.clear()
        if self.ws.doc:
            for day, ex in all_exercises(self.ws.doc).values():
                self.progress_ex.addItem(f"{day['name']} · {ex['name']}", ex['id'])
            for spin in [self.compare_a, self.compare_b]:
                spin.setMaximum(self.ws.doc['weeks'])
        self.progress_ex.setCurrentIndex(max(0, self.progress_ex.findData(previous)))
        self.progress_ex.blockSignals(False)
        self.refresh_chart()
        self.refresh_comparison()

    def refresh_chart(self, *_):
        eid = self.progress_ex.currentData()
        if not self.ws.doc or not eid:
            return
        self.chart.values = progress_values(self.ws.doc, eid)
        self.chart.update()
        ex = all_exercises(self.ws.doc)[eid][1]
        self.chart_note.setText('Thời gian cao nhất (giây).' if ex['timed'] else 'Kg trợ lực thấp nhất: thấp hơn là ít hỗ trợ hơn.' if ex['assisted'] else 'Tạ cao nhất (kg quy đổi). 2x12.5kg = 25kg; không cộng thanh đòn. Tuần trống để trống.')

    def refresh_comparison(self, *_):
        rows = []
        if self.ws.doc:
            for _, ex in all_exercises(self.ws.doc).values():
                values = progress_values(self.ws.doc, ex['id'])
                a, b = values[self.compare_a.value() - 1], values[self.compare_b.value() - 1]
                delta = f'{b-a:+g}' if a is not None and b is not None else '—'
                rows.append([ex['name'], 'Giây' if ex['timed'] else 'Kg trợ lực' if ex['assisted'] else 'Kg', f'{a:g}' if a is not None else '—', f'{b:g}' if b is not None else '—', delta])
        fill_table(self.compare_table, rows)

    def make_photos(self):
        layout = self.page()
        actions = QHBoxLayout()
        actions.addWidget(button('Tải & sao lưu toàn bộ ảnh', self.backup_photos, True))
        actions.addWidget(button('Thêm / thay ảnh điện thoại', self.upload_photo))
        actions.addWidget(button('Xóa ảnh điện thoại', self.delete_photo))
        actions.addWidget(button('Mở thư mục ảnh', lambda: self.open_folder(self.ws.directory / 'photos')))
        layout.addLayout(actions)
        row = QHBoxLayout()
        self.photo_a, self.photo_b = QComboBox(), QComboBox()
        self.photo_a.currentIndexChanged.connect(self.update_photo_views)
        self.photo_b.currentIndexChanged.connect(self.update_photo_views)
        row.addWidget(label('Tháng A'))
        row.addWidget(self.photo_a, 1)
        row.addWidget(label('Tháng B'))
        row.addWidget(self.photo_b, 1)
        layout.addLayout(row)
        views = QHBoxLayout()
        self.photo_views = []
        for _ in range(2):
            image = QLabel('Chưa có bản sao ảnh trên Windows')
            image.setAlignment(Qt.AlignmentFlag.AlignCenter)
            image.setMinimumSize(230, 320)
            image.setStyleSheet('background:#1b2725; border:1px solid #304139; border-radius:12px;')
            self.photo_views.append(image)
            views.addWidget(image, 1)
        layout.addLayout(views, 1)
        self.photo_note = label('Ảnh gốc được giữ trên Windows. Khi thay hoặc xóa ảnh điện thoại, bản trước vẫn nằm trong thư mục sao lưu.', 'muted')
        layout.addWidget(self.photo_note)

    def refresh_photos(self):
        index = self.ws.photos_index()
        months = sorted(index, reverse=True)
        for n, combo in enumerate([self.photo_a, self.photo_b]):
            previous = combo.currentData()
            combo.blockSignals(True)
            combo.clear()
            for m in months:
                combo.addItem(m, m)
            match = combo.findData(previous)
            combo.setCurrentIndex(match if match >= 0 else min(n, len(months) - 1))
            combo.blockSignals(False)
        self.update_photo_views()

    def update_photo_views(self, *_):
        index = self.ws.photos_index()
        for combo, view in zip([self.photo_a, self.photo_b], self.photo_views):
            item = index.get(combo.currentData())
            if item:
                pixmap = QPixmap(str(self.ws.directory / 'photos' / item['file']))
                if not pixmap.isNull():
                    view.setPixmap(pixmap.scaled(QSize(max(230, view.width() - 20), max(320, view.height() - 20)), Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation))
                    continue
            view.clear()
            view.setText('Chưa có bản sao ảnh trên Windows')

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if hasattr(self, 'photo_views'):
            self.update_photo_views()

    def backup_photos(self):
        if not self.need_connection():
            return
        ws = self.ws
        def work():
            items = self.client.photo_list()
            for item in items:
                ws.save_photo(item['month'], self.client.photo_bytes(item['month']), item['revision'])
            return items
        def got(items):
            self.photo_remote = {i['month']: i for i in items}
            self.refresh_photos()
            self.photo_note.setText(f'Đã sao lưu {len(items)} ảnh vào {ws.directory / "photos"}. Các phiên bản cũ được giữ bằng tên riêng.')
        self.execute(work, got, 'Đang tải ảnh gốc qua USB, giữ điện thoại mở…')

    def upload_photo(self):
        if not self.need_connection():
            return
        filename, _ = QFileDialog.getOpenFileName(self, 'Chọn ảnh tháng JPG / PNG', '', 'Ảnh (*.jpg *.jpeg *.png)')
        if not filename:
            return
        try:
            data = Path(filename).read_bytes()
        except OSError as exc:
            self.error(f'Không đọc được ảnh đã chọn.\n{exc}')
            return
        if len(data) > 15 * 1024 * 1024 or QImage.fromData(data).isNull():
            self.error('Chọn ảnh JPG hoặc PNG đọc được và không quá 15 MB.')
            return
        dlg = EditDialog('Tháng lưu ảnh trên điện thoại', self)
        from datetime import date
        month = QLineEdit(self.photo_a.currentData() or date.today().strftime('%Y-%m'))
        dlg.form.addRow('Tháng (YYYY-MM)', month)
        preview = QLabel()
        preview.setAlignment(Qt.AlignmentFlag.AlignCenter)
        preview.setPixmap(QPixmap(filename).scaled(300, 240, Qt.AspectRatioMode.KeepAspectRatio, Qt.TransformationMode.SmoothTransformation))
        dlg.layout.addWidget(preview)
        dlg.layout.addWidget(label('Gửi ảnh sang điện thoại; nếu tháng đã có ảnh, bản cũ sẽ được sao lưu trước.', 'muted'))
        dlg.buttons.button(QDialogButtonBox.StandardButton.Save).setText('Sao lưu & gửi ảnh')
        dlg.finish()
        if not dlg.exec():
            return
        import re
        m = month.text().strip()
        if not re.fullmatch(r'\d{4}-(0[1-9]|1[0-2])', m):
            self.error('Tháng cần có dạng 2026-10.')
            return
        ws = self.ws
        def work():
            current = {i['month']: i for i in self.client.photo_list()}.get(m)
            if current:
                ws.save_photo(m, self.client.photo_bytes(m), current['revision'])
            result = self.client.send_photo(m, data, current['revision'] if current else None)
            ws.save_photo(m, data, result['revision'])
            return m
        self.execute(work, lambda result: (self.refresh_photos(), self.photo_note.setText(f'Đã gửi ảnh tháng {result} và giữ bản sao trên Windows.')), 'Đang sao lưu và gửi ảnh qua USB…')

    def delete_photo(self):
        if not self.need_connection():
            return
        month = self.photo_a.currentData()
        if not month:
            self.error('Tải ảnh trước rồi chọn tháng A cần xóa trên điện thoại.')
            return
        if QMessageBox.question(self, 'Xóa ảnh điện thoại', f'Xóa ảnh tháng {month} trên điện thoại? Bản sao trên Windows và bản cũ trong điện thoại sẽ được giữ.', QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No) != QMessageBox.StandardButton.Yes:
            return
        ws = self.ws
        def work():
            current = {i['month']: i for i in self.client.photo_list()}.get(month)
            if not current:
                raise ValueError('Điện thoại không còn ảnh tháng này. Bản sao Windows vẫn được giữ.')
            ws.save_photo(month, self.client.photo_bytes(month), current['revision'])
            self.client.delete_photo(month, current['revision'])
            return month
        self.execute(work, lambda m: self.photo_note.setText(f'Đã xóa ảnh tháng {m} trên điện thoại. Bản sao Windows vẫn hiển thị để xem hoặc gửi lại.'), 'Đang sao lưu ảnh trước khi xóa…')

    def make_backups(self):
        layout = self.page()
        actions = QHBoxLayout()
        for name, action in [('Lưu JSON ra file', self.json_export), ('Mở / khôi phục JSON', self.import_json), ('Xuất CSV', self.csv_export), ('Mở thư mục sao lưu', lambda: self.open_folder(self.ws.directory / 'backups'))]:
            actions.addWidget(button(name, action))
        layout.addLayout(actions)
        layout.addWidget(label('Trước mỗi lần gửi, app giữ bản trên điện thoại và bản trên Windows. Khôi phục ở đây chỉ thay bản làm việc; bạn vẫn xem trước trước khi gửi sang điện thoại.', 'muted'))
        self.backup_list = QListWidget()
        layout.addWidget(self.backup_list, 1)
        layout.addWidget(button('Khôi phục bản đã chọn vào Windows', self.restore_selected))

    def refresh_backups(self):
        self.backup_list.clear()
        folder = self.ws.directory / 'backups'
        if folder.exists():
            for path in sorted(folder.glob('*.json'), reverse=True):
                self.backup_list.addItem(path.name)

    def restore_selected(self):
        item = self.backup_list.currentItem()
        if item:
            self.import_path(self.ws.directory / 'backups' / item.text())

    def import_json(self):
        name, _ = QFileDialog.getOpenFileName(self, 'Mở bản sao lưu Track Tạ', '', 'Track Tạ JSON (*.json)')
        if name:
            self.import_path(Path(name))

    def import_path(self, path):
        try:
            if path.stat().st_size > 10 * 1024 * 1024:
                raise ValueError('Bản JSON không được quá 10 MB.')
            doc = normalize(json.loads(path.read_text(encoding='utf-8-sig')))
            if self.ws.doc:
                if QMessageBox.question(self, 'Thay bản làm việc Windows', 'Dùng bản JSON này làm bản làm việc? Bản đang chỉnh sẽ được sao lưu. Điện thoại chưa thay đổi.', QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No) != QMessageBox.StandardButton.Yes:
                    return
                self.ws.backup(self.ws.doc, 'before-import')
            self.commit(doc)
        except Exception as exc:
            self.error(str(exc))

    def json_export(self):
        if self.need_doc():
            path, _ = QFileDialog.getSaveFileName(self, 'Lưu nhật ký và lịch tập', 'track-ta.json', 'JSON (*.json)')
            if path:
                try:
                    atomic_json(Path(path), self.ws.doc)
                except Exception as exc:
                    self.error(str(exc))

    def csv_export(self):
        if self.need_doc():
            path, _ = QFileDialog.getSaveFileName(self, 'Xuất nhật ký CSV', 'track-ta.csv', 'CSV (*.csv)')
            if path:
                try:
                    Path(path).write_text(export_csv(self.ws.doc), encoding='utf-8', newline='')
                except Exception as exc:
                    self.error(str(exc))

    def open_folder(self, path):
        path.mkdir(parents=True, exist_ok=True)
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(path)))

    def resolve_conflicts(self, conflicts):
        dlg = QDialog(self)
        dlg.setWindowTitle('Chọn dữ liệu khi hai bên cùng sửa')
        dlg.resize(900, 500)
        box = QVBoxLayout(dlg)
        box.addWidget(label('Các chỉnh sửa khác nhau sẽ được ghép tự động. Chọn bản muốn giữ cho những mục dưới đây.'))
        view = table(['Mục', 'Trên Windows', 'Trên điện thoại', 'Giữ bản'])
        view.setRowCount(len(conflicts))
        selectors = []
        def show(value):
            if value is None:
                return 'Đã xóa'
            if isinstance(value, list):
                return ' / '.join(d['name'] for d in value)
            return f"{value['weight'] or 'BW'} × {value['reps'] or '—'} · {value['note']}"
        for i, conflict in enumerate(conflicts):
            for c, value in enumerate(['Lịch tập' if conflict['key'] == 'days' else conflict['key'], show(conflict['local']), show(conflict['remote'])]):
                view.setItem(i, c, QTableWidgetItem(value))
            combo = QComboBox()
            combo.addItem('Chọn bản cần giữ…', None)
            combo.addItem('Windows', 'local')
            combo.addItem('Điện thoại', 'remote')
            view.setCellWidget(i, 3, combo)
            selectors.append(combo)
        box.addWidget(view)
        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
        buttons.button(QDialogButtonBox.StandardButton.Ok).setText('Tiếp tục xem trước')
        buttons.button(QDialogButtonBox.StandardButton.Cancel).setText('Hủy')
        def accept():
            if any(c.currentData() is None for c in selectors):
                self.error('Chọn bản cần giữ cho từng mục xung đột.')
            else:
                dlg.accept()
        buttons.accepted.connect(accept)
        buttons.rejected.connect(dlg.reject)
        box.addWidget(buttons)
        if dlg.exec():
            return {conflict['key']: selector.currentData() for conflict, selector in zip(conflicts, selectors)}
        return None

    def sync(self):
        if not self.need_doc() or not self.need_connection():
            return
        def fetched(response):
            remote = normalize(response['data'])
            merged, conflicts = merge_snapshots(self.ws.baseline, self.ws.doc, remote)
            if conflicts:
                choices = self.resolve_conflicts(conflicts)
                if choices is None:
                    return
                merged, _ = merge_snapshots(self.ws.baseline, self.ws.doc, remote, choices)
            guard_history(remote, merged)
            changes = change_summary(remote, merged)
            dlg = QDialog(self)
            dlg.setWindowTitle('Xem trước đồng bộ USB')
            dlg.resize(700, 440)
            box = QVBoxLayout(dlg)
            box.addWidget(label(f'{len(changes)} mục sẽ thay đổi trên điện thoại. Bản cũ được sao lưu ở cả hai thiết bị.'))
            listing = QListWidget()
            listing.addItems(changes or ['Không có thay đổi trên điện thoại; cập nhật bản Windows bằng dữ liệu mới nhất.'])
            box.addWidget(listing)
            buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
            buttons.button(QDialogButtonBox.StandardButton.Ok).setText('Sao lưu & đồng bộ')
            buttons.button(QDialogButtonBox.StandardButton.Cancel).setText('Hủy')
            buttons.accepted.connect(dlg.accept)
            buttons.rejected.connect(dlg.reject)
            box.addWidget(buttons)
            if not dlg.exec():
                return
            ws = self.ws
            local = copy.deepcopy(ws.doc)
            def send():
                ws.backup(remote, 'phone-before-sync')
                ws.backup(local, 'windows-before-sync')
                return self.client.send_snapshot(merged, response['revision']) if changes else response
            def sent(result):
                ws.accept_remote(result['data'])
                self.remote = result
                self.refresh_all()
                self.statusBar().showMessage('Đồng bộ thành công. Windows và điện thoại đã khớp.')
                QMessageBox.information(self, 'Đã đồng bộ', 'Lịch tập và nhật ký đã khớp. Ảnh được quản lý riêng trong mục Ảnh tháng.')
            self.execute(send, sent, 'Đang sao lưu và đồng bộ qua USB…')
        self.execute(self.client.snapshot, fetched, 'Đang lấy dữ liệu mới nhất để so sánh…')

    def closeEvent(self, event):
        if self.busy:
            self.error('Đang truyền dữ liệu. Đợi thao tác hoàn tất trước khi đóng.')
            event.ignore()
            return
        self.client.close()
        event.accept()
