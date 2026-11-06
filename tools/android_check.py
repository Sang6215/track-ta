"""Small adb helper for verifying the local test emulator, never a user's device."""
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADB = str(ROOT / '.tooling/android-sdk/platform-tools/adb.exe')
def adb(*args):
    return subprocess.check_output([ADB, '-s', 'emulator-5554', *args])
def tree():
    adb('shell', 'uiautomator', 'dump', '/sdcard/trackta-ui.xml')
    return ET.fromstring(adb('shell', 'cat', '/sdcard/trackta-ui.xml'))
if sys.argv[1] == 'dump':
    for n in tree().iter('node'):
        a = n.attrib
        if a.get('text') or a.get('content-desc'):
            print(a.get('text') or a.get('content-desc'), a['bounds'], a['class'])
elif sys.argv[1] == 'tap':
    target = sys.argv[2]
    nodes = [n for n in tree().iter('node') if target in (n.attrib.get('text',''), n.attrib.get('content-desc',''))]
    if len(nodes) != 1:
        raise RuntimeError(f'Expected exactly one match for {target!r}: {len(nodes)}')
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', nodes[0].attrib['bounds']))
    adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
elif sys.argv[1] == 'screenshot':
    (ROOT / 'release/screenshots' / sys.argv[2]).write_bytes(adb('exec-out', 'screencap', '-p'))
