"""USB-only adb forwarding with a short-lived app pairing token."""
from __future__ import annotations

import base64
import json
from pathlib import Path
import re
import subprocess
import urllib.error
import urllib.request

from trackta_core import normalize, resource_path

PACKAGE = 'vn.trackta.track_ta'


class UsbError(Exception):
    pass


class ConflictError(UsbError):
    pass


class UsbClient:
    def __init__(self, adb_path=None):
        self.adb = Path(adb_path or resource_path('usb/adb.exe'))
        if not self.adb.exists():
            self.adb = resource_path('.tooling/android-sdk/platform-tools/adb.exe')
        self.serial = None
        self.port = None
        self.token = None
        self.remote_version = None
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def run(self, *args, timeout=20, selected=False):
        if not self.adb.is_file():
            raise UsbError('Thiếu công cụ USB. Giải nén đầy đủ bộ Track Tạ Windows.')
        command = [str(self.adb)]
        if selected:
            if not self.serial:
                raise UsbError('Chưa chọn điện thoại.')
            command += ['-s', self.serial]
        command += list(args)
        try:
            result = subprocess.run(command, capture_output=True, timeout=timeout,
                                    creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        except subprocess.TimeoutExpired as exc:
            raise UsbError('Điện thoại chưa phản hồi. Kiểm tra cáp và mở khóa màn hình.') from exc
        output = result.stdout.decode('utf-8', 'replace')
        if result.returncode:
            error = result.stderr.decode('utf-8', 'replace').strip() or output.strip()
            raise UsbError(error[:1000])
        return output.strip()

    def devices(self):
        output = self.run('devices', '-l')
        devices = []
        for line in output.splitlines():
            parts = line.split()
            if len(parts) < 2 or parts[0] == 'List' or parts[0].startswith('*'):
                continue
            # Wireless adb endpoints have colon-delimited serials; this app is USB.
            if ':' in parts[0] or '_adb-tls-' in parts[0]:
                continue
            model = next((p.split(':', 1)[1].replace('_', ' ') for p in parts[2:] if p.startswith('model:')), parts[0])
            devices.append({'serial': parts[0], 'state': parts[1], 'model': model})
        return devices

    def app_version(self):
        output = self.run('shell', 'dumpsys', 'package', PACKAGE, selected=True)
        match = re.search(r'versionName=([^\s]+)', output)
        return match[1] if match else None

    def open_app(self):
        self.run('shell', 'am', 'start', '-n', PACKAGE + '/.MainActivity', selected=True)

    def install(self, apk):
        if not Path(apk).is_file():
            raise UsbError('Không tìm thấy APK cập nhật. Chọn Track-Ta-v1.5.0.apk đi kèm.')
        output = self.run('install', '-r', str(apk), timeout=180, selected=True)
        if 'Success' not in output:
            raise UsbError(output or 'Android chưa cài được bản cập nhật. Giữ app hiện có và thử lại.')
        self.open_app()
        return output

    def pair(self, serial, code):
        self.close()
        self.serial = serial
        try:
            self.port = int(self.run('forward', 'tcp:0', 'tcp:47821', selected=True))
            response = self.request('POST', '/pair', {'code': code}, authenticated=False)
            if response.get('protocol') != 1:
                raise UsbError('Phiên bản điện thoại chưa hỗ trợ giao thức USB này.')
            normalize(response['data'])
            self.token = response['token']
            self.remote_version = response.get('appVersion')
            return response
        except Exception:
            self.close()
            raise

    def request(self, method, path, data=None, authenticated=True, binary=False):
        if self.port is None or (authenticated and not self.token):
            raise UsbError('Nhập mã trên điện thoại để ghép nối trước.')
        headers = {'Content-Type': 'application/json'}
        if authenticated:
            headers['Authorization'] = 'Bearer ' + self.token
        request = urllib.request.Request(f'http://127.0.0.1:{self.port}{path}',
                                         data=json.dumps(data, ensure_ascii=False).encode('utf-8') if data is not None else None,
                                         method=method, headers=headers)
        try:
            with self.opener.open(request, timeout=40) as response:
                body = response.read(25 * 1024 * 1024 + 1)
                if len(body) > 25 * 1024 * 1024:
                    raise UsbError('Dữ liệu quá lớn.')
                return body if binary else json.loads(body)
        except urllib.error.HTTPError as exc:
            if authenticated and exc.code == 401:
                self.token = None
            try:
                error = json.loads(exc.read()).get('error', 'Kết nối không thành công.')
            except (ValueError, OSError):
                error = 'Kết nối không thành công.'
            if exc.code == 409:
                raise ConflictError(error) from exc
            raise UsbError(error) from exc
        except (urllib.error.URLError, TimeoutError, ConnectionError, json.JSONDecodeError) as exc:
            raise UsbError('Chưa kết nối được. Cài bản Android 1.4.0, vào Dữ liệu → Kết nối Windows qua USB → Bắt đầu kết nối; giữ màn hình đó mở và kiểm tra cáp.') from exc

    def snapshot(self):
        response = self.request('GET', '/snapshot')
        if response.get('protocol') != 1:
            raise UsbError('Giao thức USB không tương thích.')
        normalize(response['data'])
        return response

    def send_snapshot(self, doc, revision):
        if (doc.get('debloatWeeks') or any(e.get('source') == 'debloat' for e in doc['entries'].values())):
            parts = tuple(int(p) for p in (self.remote_version or '0').split('.') if p.isdigit())
            if parts < (1, 4, 0):
                raise UsbError('Cài Android 1.4.0 để giữ nhãn và trạng thái hiệp gợi ý debloat trước khi đồng bộ.')
        return self.request('PUT', '/snapshot', {'baseRevision': revision, 'data': normalize(doc)})

    def photo_list(self):
        return self.request('GET', '/photos')['items']

    def photo_bytes(self, month):
        return self.request('GET', '/photos/' + month, binary=True)

    def send_photo(self, month, data, revision):
        return self.request('PUT', '/photos/' + month, {'baseRevision': revision, 'contentBase64': base64.b64encode(data).decode('ascii')})

    def delete_photo(self, month, revision):
        return self.request('DELETE', '/photos/' + month, {'baseRevision': revision})

    def close(self):
        if self.port is not None:
            try:
                self.run('forward', '--remove', f'tcp:{self.port}', selected=True)
            except Exception:
                pass
        self.port = self.token = self.remote_version = None
