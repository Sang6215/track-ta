"""Generate the short, license-free rest timer bell used by Android alerts."""

import math
import struct
import wave
from pathlib import Path

out = Path(__file__).resolve().parents[1] / "android/app/src/main/res/raw/rest_bell.wav"
out.parent.mkdir(parents=True, exist_ok=True)
rate = 22050
samples = []
for frequency, length in [(880, 0.34), (1174.66, 0.5)]:
    count = int(rate * length)
    for i in range(count):
        t = i / rate
        envelope = (1 - math.exp(-30 * t)) * math.exp(-7 * t)
        tone = math.sin(2 * math.pi * frequency * t)
        overtone = 0.25 * math.sin(2 * math.pi * frequency * 2 * t)
        samples.append(int(15000 * envelope * (tone + overtone)))
    samples.extend([0] * int(rate * 0.06))
with wave.open(str(out), "wb") as audio:
    audio.setnchannels(1)
    audio.setsampwidth(2)
    audio.setframerate(rate)
    audio.writeframes(struct.pack(f"<{len(samples)}h", *samples))
print(out)
