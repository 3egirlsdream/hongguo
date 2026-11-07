from pathlib import Path
import os
import subprocess
import zipfile


project = Path(__file__).resolve().parents[1]
source = project / 'scripts/android_device'
root = project / 'build/android-device-helper'
root.mkdir(parents=True, exist_ok=True)
for name in ['Probe.java', 'Ui.java', 'probe.c', 'AndroidManifest.xml']:
    (root / name).write_bytes((source / name).read_bytes())
sdk = Path(os.environ.get('ANDROID_HOME', Path.home() / 'Library/Android/sdk'))
bt = sorted((sdk / 'build-tools').iterdir(), key=lambda p: tuple(
    int(n) for n in p.name.split('.') if n.isdigit()
))[-1]
jar = sorted((sdk / 'platforms').glob('android-*/android.jar'),
             key=lambda p: int(p.parent.name.split('-')[-1]))[-1]
java = Path(os.environ['JAVA_HOME']) if os.environ.get('JAVA_HOME') else Path(
    subprocess.check_output(['/usr/libexec/java_home', '-v', '17'], text=True).strip()
)
environment = os.environ.copy()
environment['JAVA_HOME'] = str(java)


def run(command):
    subprocess.run([str(value) for value in command], check=True,
                   env=environment, cwd=root)


(root / 'classes').mkdir(exist_ok=True)
(root / 'dex').mkdir(exist_ok=True)
run([java / 'bin/javac', '-source', '8', '-target', '8', '-cp', jar, '-d',
     root / 'classes', root / 'Probe.java', root / 'Ui.java'])
run([bt / 'd8', '--min-api', '33', '--lib', jar, '--output', root / 'dex',
     *sorted((root / 'classes').rglob('*.class'))])
run([bt / 'aapt2', 'link', '-I', jar, '--manifest', root / 'AndroidManifest.xml',
     '-o', root / 'unsigned.apk'])
ndk = Path(os.environ['ANDROID_NDK_HOME']) if os.environ.get('ANDROID_NDK_HOME') else sorted(
    (sdk / 'ndk').iterdir()
)[-1]
compiler = ndk / 'toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android26-clang'
run([compiler, '-shared', '-fPIC', '-Wl,-z,max-page-size=16384', '-o',
     root / 'libguo_probe.so', root / 'probe.c', '-ldl'])
with zipfile.ZipFile(root / 'unsigned.apk', 'a') as archive:
    archive.write(root / 'dex/classes.dex', 'classes.dex')
    archive.write(root / 'libguo_probe.so', 'lib/arm64-v8a/libguo_probe.so')
run([bt / 'zipalign', '-P', '16', '-f', '4', root / 'unsigned.apk', root / 'aligned.apk'])
values = {}
for line in (project / 'android/key.properties').read_text().splitlines():
    if '=' in line:
        key, value = line.split('=', 1)
        values[key.strip()] = value.strip()
if values.get('keyAlias') != 'temp':
    raise SystemExit('设备辅助必须使用 temp 签名')
environment['GUO_PROBE_STORE_PASS'] = values['storePassword']
environment['GUO_PROBE_KEY_PASS'] = values['keyPassword']
run([bt / 'apksigner', 'sign', '--ks', values['storeFile'], '--ks-key-alias', 'temp',
     '--ks-pass', 'env:GUO_PROBE_STORE_PASS', '--key-pass', 'env:GUO_PROBE_KEY_PASS',
     '--out', root / 'probe.apk', root / 'aligned.apk'])
certificate = subprocess.check_output([
    str(bt / 'apksigner'), 'verify', '--print-certs', str(root / 'probe.apk')
], env=environment, text=True)
expected = '2b1f9dec180e972d6c3736c5efd52ee7952ede4155eeecdbbc23ea331ffa076e'
if expected not in certificate.lower():
    raise SystemExit('设备辅助签名证书不符')
print(root / 'probe.apk')
