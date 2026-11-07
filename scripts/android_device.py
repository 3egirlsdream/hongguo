import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / '.local' / 'android-device.json'


def adb_path():
    sdk = os.environ.get('ANDROID_HOME', str(Path.home() / 'Library/Android/sdk'))
    executable = shutil.which('adb') or str(Path(sdk) / 'platform-tools/adb')
    if not Path(executable).is_file():
        raise RuntimeError('找不到本机 adb')
    return executable


def run_probe(mode, *, phone='', subscription=None, dry_run=False, click='', video='', serial=''):
    command = [adb_path()]
    if serial:
        command += ['-s', serial]
    arguments = ['am', 'instrument', '-w', '-e', 'mode', mode]
    for name, value in [('phone', phone), ('click', click), ('video', video)]:
        if value:
            arguments += ['-e', name, value]
    if subscription is not None:
        arguments += ['-e', 'subscription', str(subscription)]
    if dry_run:
        arguments += ['-e', 'dryRun', 'true']
    target = 'Ui' if mode == 'ui' else 'Probe'
    arguments += [f'com.duanju.historyprobe/.{target}']
    import shlex
    result = subprocess.run(command + ['shell', shlex.join(arguments)], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=200)
    match = re.search(r'^INSTRUMENTATION_RESULT: summary=(.+)$', result.stdout, re.MULTILINE)
    if result.returncode or not match:
        failure = re.search(r'^INSTRUMENTATION_RESULT: error=([a-zA-Z_]+)$', result.stdout, re.MULTILINE)
        raise RuntimeError(failure[1] if failure else '设备验证辅助未完成，请确认工具已覆盖安装且手机已连接')
    return json.loads(match[1])


def main():
    parser = argparse.ArgumentParser(description='保留已安装应用及登录态的 Android 设备验证辅助')
    parser.add_argument('mode', choices=['status', 'login', 'ui', 'fixture', 'restore', 'configure'])
    parser.add_argument('--phone', default='')
    parser.add_argument('--subscription', type=int)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--serial', default='')
    parser.add_argument('--click', default='')
    parser.add_argument('--video', default='')
    args = parser.parse_args()
    config = json.loads(CONFIG.read_text()) if CONFIG.exists() else {}
    phone = args.phone or config.get('phone', '')
    subscription = args.subscription if args.subscription is not None else config.get('subscription')
    if args.mode == 'configure':
        if not re.fullmatch(r'1\d{10}', phone):
            parser.error('请提供有效的中国大陆手机号')
        CONFIG.parent.mkdir(parents=True, exist_ok=True)
        CONFIG.parent.chmod(0o700)
        CONFIG.write_text(json.dumps({'phone': phone, 'subscription': subscription}, ensure_ascii=False))
        CONFIG.chmod(0o600)
        print('本机登录配置已保存；不包含验证码或会话，不进入源码镜像。')
        return
    result = run_probe(args.mode, phone=phone, subscription=subscription,
                       dry_run=args.dry_run, click=args.click, video=args.video, serial=args.serial)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
