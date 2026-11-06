"""Portable Windows companion entry point; does not need Python on the user PC."""
import sys
import os
if '--self-test' in sys.argv:
    os.environ['QT_QPA_PLATFORM'] = 'windows' if '--native-window' in sys.argv else 'offscreen'
from pathlib import Path
import traceback


def startup_error(kind, error, trace):
    path = Path(os.environ.get('LOCALAPPDATA', Path.home())) / 'TrackTaWindows' / 'startup-error.log'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(''.join(traceback.format_exception(kind, error, trace)), encoding='utf-8')


sys.excepthook = startup_error
from PySide6.QtGui import QFontDatabase
from PySide6.QtWidgets import QApplication, QMessageBox
from window import MainWindow, STYLE


def main():
    app = QApplication(sys.argv)
    app.setApplicationName('Track Tạ Windows')
    app.setApplicationVersion('1.2.0')
    app.setOrganizationName('TrackTa')
    for name in ['segoeui.ttf', 'segoeuib.ttf', 'seguisb.ttf']:
        path = Path('C:/Windows/Fonts') / name
        if path.exists():
            QFontDatabase.addApplicationFont(str(path))
    app.setStyle('Fusion')
    app.setStyleSheet(STYLE)
    if '--self-test' in sys.argv:
        from deployment_smoke import run
        usb_test = None
        if '--usb-emulator' in sys.argv:
            index = sys.argv.index('--usb-emulator')
            usb_test = (sys.argv[index + 1], sys.argv[index + 2])
        return run(app, Path(sys.argv[sys.argv.index('--self-test') + 1]), usb_test)
    try:
        window = MainWindow()
    except Exception as exc:
        QMessageBox.critical(None, 'Không mở được bản làm việc', f'Dữ liệu vẫn ở trong thư mục TrackTaWindows.\n{exc}')
        return 1
    window.show()
    return app.exec()


if __name__ == '__main__':
    sys.exit(main())
