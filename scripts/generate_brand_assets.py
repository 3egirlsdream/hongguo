import argparse
from pathlib import Path

from PIL import Image


root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description='从野果图标母版导出 Android 资源；需要 Pillow。')
parser.add_argument('--output', type=Path, default=root)
parser.add_argument('--source', type=Path, default=root / 'assets/branding/app_icon.png')
options = parser.parse_args()
output = options.output
icon = Image.open(options.source).convert('RGB')
if icon.width != icon.height:
    raise SystemExit('图标母版必须是正方形。')
background = icon.getpixel((0, 0))
background_hex = '#%02X%02X%02X' % background


def save(image, name, **kwargs):
    destination = output / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, **kwargs)


def save_text(content, name):
    destination = output / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(content, encoding='utf-8')


for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    save(icon.resize((size, size), Image.Resampling.LANCZOS),
         f'android/app/src/main/res/mipmap-{density}/ic_launcher.png')

save(icon.resize((512, 512), Image.Resampling.LANCZOS),
     'android/app/src/main/res/drawable-nodpi/app_icon_image.png')
save_text('''<bitmap xmlns:android="http://schemas.android.com/apk/res/android"
    android:src="@drawable/app_icon_image" android:gravity="fill" android:filter="true"/>
''', 'android/app/src/main/res/drawable/app_icon.xml')
save_text('''<inset xmlns:android="http://schemas.android.com/apk/res/android"
    android:drawable="@drawable/app_icon" android:inset="18dp"/>
''', 'android/app/src/main/res/drawable/app_icon_foreground.xml')
save_text(f'''<resources>
    <color name="app_icon_background">{background_hex}</color>
</resources>
''', 'android/app/src/main/res/values/app_icon_colors.xml')
save_text('''<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/app_icon_background"/>
    <foreground android:drawable="@drawable/app_icon_foreground"/>
</adaptive-icon>
''', 'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml')

print('已从统一母版导出野果 Android 手机和平板图标资源。')
