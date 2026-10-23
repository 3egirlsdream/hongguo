import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import zipfile
from pathlib import Path

from app_build import BuildVariant

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--abi', action='append', choices=['arm64-v8a', 'armeabi-v7a', 'x86_64'])
options = parser.parse_args()
variant = BuildVariant()
match = re.search(r'^version:\s*([\w.+-]+)\s*$', (root / 'pubspec.yaml').read_text(encoding='utf-8'), re.MULTILINE)
if not match:
    raise SystemExit('pubspec.yaml 缺少合法版本号。')
version = match.group(1)
output = root / 'dist' / 'android'
output.mkdir(parents=True, exist_ok=True)
artifacts = []

sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
tools = sorted((Path(sdk) / 'build-tools').glob('*/aapt*')) if sdk else []
aapt = next((tool for tool in reversed(tools) if tool.name in {'aapt', 'aapt.exe'}), None)
if aapt is None:
    raise SystemExit('请通过 ANDROID_HOME 指定包含 aapt 的 Android SDK。')
version_name, build_number = version.split('+')
version_code = 2000 + int(build_number)
for abi in options.abi or ['arm64-v8a', 'armeabi-v7a', 'x86_64']:
    source = root / 'build' / 'app' / 'outputs' / 'flutter-apk' / f'app-{abi}-release.apk'
    if not source.is_file():
        raise SystemExit('缺少 APK：' + str(source))
    badging = subprocess.check_output([str(aapt), 'dump', 'badging', str(source)], text=True)
    if (f"versionName='{version_name}'" not in badging or
            f"versionCode='{version_code}'" not in badging or
            "name='com.duanju.duanju_app'" not in badging or
            f"native-code: '{abi}'" not in badging):
        raise SystemExit('APK 的应用标识、内部版本或架构与当前源码不符，拒绝打包：' + str(source))
    with zipfile.ZipFile(source) as archive:
        names = set(archive.namelist())
        required = [f'lib/{abi}/{library}' for library in
                    ['libduanju_core.so', 'libflutter.so', 'libapp.so', 'libmpv.so', 'libffmpegkit.so']]
        missing = set(required) - names
        if missing:
            raise SystemExit('APK 缺少原生库：' + ', '.join(sorted(missing)))
        manifest = 'assets/flutter_assets/FontManifest.json'
        material = 'assets/flutter_assets/fonts/MaterialIcons-Regular.otf'
        if manifest not in names or material not in names or archive.getinfo(material).file_size == 0:
            raise SystemExit('APK 缺少 Material 图标字体，请确认 uses-material-design 并重新构建。')
        fonts = json.loads(archive.read(manifest))
        if not any(font.get('family') == 'MaterialIcons' and
                   any(row.get('asset') == 'fonts/MaterialIcons-Regular.otf' for row in font.get('fonts', []))
                   for font in fonts):
            raise SystemExit('APK 图标字体未注册到 FontManifest。')
    target = output / f'{variant.slug}-{version}-{abi}.apk'
    shutil.copy2(source, target)
    artifacts.append(target)

checksums = []
for artifact in sorted(output.glob(f'*-{version}-*')):
    digest = hashlib.sha256()
    with artifact.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    checksums.append(f'{digest.hexdigest()}  {artifact.name}')
    print(artifact)
(output / 'SHA256SUMS.txt').write_text('\n'.join(checksums) + '\n', encoding='ascii')
