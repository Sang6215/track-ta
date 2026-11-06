from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
image = Image.new('RGB', (512, 512), '#101918')
d = ImageDraw.Draw(image)
d.rounded_rectangle((52, 52, 460, 460), 100, fill='#d4f58a')
d.rounded_rectangle((115, 183, 157, 329), 14, fill='#101918')
d.rounded_rectangle((164, 151, 211, 361), 15, fill='#101918')
d.rounded_rectangle((301, 151, 348, 361), 15, fill='#101918')
d.rounded_rectangle((355, 183, 397, 329), 14, fill='#101918')
d.rectangle((198, 236, 314, 276), fill='#101918')
for folder, size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    image.resize((size,size),Image.Resampling.LANCZOS).save(root/f'android/app/src/main/res/mipmap-{folder}/ic_launcher.png')
for name,size in [('Icon-192.png',192),('Icon-512.png',512),('Icon-maskable-192.png',192),('Icon-maskable-512.png',512)]:
    image.resize((size,size),Image.Resampling.LANCZOS).save(root/'web/icons'/name)
image.resize((48,48),Image.Resampling.LANCZOS).save(root/'web/favicon.png')
