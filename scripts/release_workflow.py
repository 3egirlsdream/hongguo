import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import urllib.parse
import urllib.request
from pathlib import Path

from app_build import BuildVariant

ROOT = Path(__file__).resolve().parents[1]
CERTIFICATE = '2B1F9DEC180E972D6C3736C5EFD52EE7952EDE4155EEECDBBC23EA331FFA076E'
CLIENT = 'Yeguo'
VERSION_PATTERN = re.compile(r'^(\d+)\.(\d+)\.(\d+)\+(\d+)$')
TAG_PATTERN = re.compile(r'^app-v(\d+)\.(\d+)\.(\d+)-(\d+)$')


def version_key(version):
    match = VERSION_PATTERN.fullmatch(version)
    if not match:
        raise ValueError('版本必须为 X.Y.Z+构建号：' + version)
    return tuple(map(int, match.groups()))


def current_version():
    text = (ROOT / 'pubspec.yaml').read_text(encoding='utf-8')
    match = re.search(r'^version:\s*(\S+)\s*$', text, re.MULTILINE)
    if not match:
        raise ValueError('pubspec.yaml 缺少版本号')
    version_key(match[1])
    return match[1]


def tag_for(version):
    return 'app-v' + version.replace('+', '-')


def repository():
    repo = os.environ['GITHUB_REPOSITORY']
    if repo != '3egirlsdream/hongguo':
        raise ValueError('发布仅允许从 3egirlsdream/hongguo 执行')
    return repo


def gh(*arguments):
    return subprocess.check_output(
        ['gh', *arguments, '--repo', repository()], cwd=ROOT, text=True,
    ).strip()


def summary(text):
    if path := os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(path, 'a', encoding='utf-8') as stream:
            stream.write(text + '\n')
    print(text)


def detect():
    version = current_version()
    key = version_key(version)
    releases = json.loads(gh('release', 'list', '--limit', '1000', '--json', 'tagName,isDraft,isPrerelease'))
    tags = [row['tagName'] for row in releases if not row['isDraft'] and not row['isPrerelease']]
    versions = {tag: tuple(map(int, match.groups())) for tag in tags
                if (match := TAG_PATTERN.fullmatch(tag))}
    latest = max(versions.values(), default=None)
    sync = os.environ.get('SYNC_BACKEND_ONLY', 'false').lower() == 'true'
    if sync:
        if key != latest:
            raise ValueError('后台重试仅允许当前最高版本的已发布 Release')
        mode = 'sync'
    elif latest is None or key[:3] > latest[:3] and key[3] > max(v[3] for v in versions.values()):
        mode = 'publish'
    elif key == latest:
        mode = 'noop'
    else:
        raise ValueError('功能版本号和构建号必须同时高于已发布版本')
    with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as stream:
        stream.write(f'mode={mode}\nversion={version}\ntag={tag_for(version)}\n')
    summary(f'版本：{version}\n\n发布模式：{mode}')


def verify_certificate(path):
    text = Path(path).read_text(encoding='utf-8')
    digests = re.findall(r'certificate SHA-256 digest:\s*([a-fA-F0-9:]+)', text)
    if len(digests) != 1 or digests[0].replace(':', '').upper() != CERTIFICATE:
        raise ValueError('APK 证书与固定发布证书不一致')
    print('APK 发布证书一致')


def release_url(version):
    return f'https://github.com/{repository()}/releases/download/{tag_for(version)}/'


def prepare():
    version = current_version()
    slug = BuildVariant.slug
    output = ROOT / 'release'
    if output.exists():
        shutil.rmtree(output)
    output.mkdir()
    specifications = [('android', 'arm64-v8a', f'{slug}-{version}-arm64-v8a.apk')]
    packages = []
    base = release_url(version)
    for platform, architecture, name in specifications:
        matches = list((ROOT / 'artifacts').glob('*/' + name))
        if len(matches) != 1 or matches[0].stat().st_size == 0:
            raise ValueError('缺少唯一有效发布包：' + name)
        target = output / name
        shutil.copy2(matches[0], target)
        packages.append({
            'platform': platform, 'architecture': architecture, 'name': name,
            'url': base + urllib.parse.quote(name, safe=''),
            'size': target.stat().st_size, 'sha256': file_hash(target),
        })
    notes = f'野果 {version}\n\nAndroid arm64：APK 使用固定 temp 发布证书，可覆盖安装。\n开发快照，尚未集中设备验收。\n'
    tags = subprocess.check_output(['git', 'tag', '--list', 'app-v*'], cwd=ROOT, text=True).splitlines()
    previous = [(tuple(map(int, match.groups())), tag) for tag in tags
                if (match := TAG_PATTERN.fullmatch(tag)) and tuple(map(int, match.groups())) < version_key(version)]
    revision = f'{max(previous)[1]}..HEAD' if previous else 'HEAD'
    notes += '\n本次提交：\n' + subprocess.check_output(
        ['git', 'log', revision, '--format=- %s'], cwd=ROOT, text=True,
    )
    manifest = {'schema': 1, 'client': CLIENT, 'version': version,
                'releaseUrl': f'https://github.com/{repository()}/releases/tag/{tag_for(version)}',
                'notes': notes, 'packages': packages}
    (output / 'update.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (ROOT / 'release-notes.md').write_text(notes, encoding='utf-8')
    checksums = [f'{file_hash(path)}  {path.name}' for path in sorted(output.iterdir())]
    (output / 'SHA256SUMS.txt').write_text('\n'.join(checksums) + '\n', encoding='ascii')


def file_hash(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def publish():
    version = current_version()
    tag = tag_for(version)
    assets = [str(path) for path in sorted((ROOT / 'release').iterdir())]
    existing = json.loads(gh('release', 'list', '--limit', '100', '--json', 'tagName,isDraft'))
    release = next((row for row in existing if row['tagName'] == tag), None)
    if release:
        if not release['isDraft']:
            raise ValueError('相同版本已正式发布，禁止覆盖附件')
        draft = json.loads(gh('release', 'view', tag, '--json', 'targetCommitish,assets'))
        if draft['targetCommitish'] != os.environ['GITHUB_SHA']:
            raise ValueError('同版本草稿来自其他提交，请提升版本后发布')
        gh('release', 'upload', tag, *assets, '--clobber')
        for asset in draft['assets']:
            if asset['name'] not in {Path(path).name for path in assets}:
                gh('release', 'delete-asset', tag, asset['name'], '--yes')
    else:
        gh('release', 'create', tag, *assets, '--draft', '--target', os.environ['GITHUB_SHA'],
           '--title', f'野果 {version}', '--notes-file', str(ROOT / 'release-notes.md'))
    uploaded = json.loads(gh('release', 'view', tag, '--json', 'assets'))['assets']
    for path in (ROOT / 'release').iterdir():
        if not any(item['name'] == path.name and item['size'] == path.stat().st_size for item in uploaded):
            raise ValueError('发布附件上传不完整：' + path.name)
    gh('release', 'edit', tag, '--draft=false', '--latest', '--notes-file', str(ROOT / 'release-notes.md'))
    summary(f'已发布：https://github.com/{repository()}/releases/tag/{tag}')


def request_json(url, payload=None):
    data = None if payload is None else json.dumps(payload, ensure_ascii=False).encode('utf-8')
    request = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json', 'User-Agent': 'Yeguo-Release'})
    with urllib.request.urlopen(request, timeout=60) as response:
        content = response.read(2 * 1024 * 1024 + 1)
        if len(content) > 2 * 1024 * 1024:
            raise ValueError('版本响应过大')
        return json.loads(content)


def matches_fields(data, fields):
    return isinstance(data, dict) and all(data.get(k) == v for k, v in fields.items())


def sync_backend():
    version = current_version()
    backend_version = version.split('+')[0]
    release = json.loads(gh('release', 'view', tag_for(version), '--json', 'assets,isDraft,isPrerelease,body'))
    if release['isDraft'] or release['isPrerelease']:
        raise ValueError('后台仅接受已公开发布的正式 Release')
    expected = release_url(version) + 'update.json'
    asset = next((item for item in release['assets'] if item['name'] == 'update.json'), None)
    if asset is None or asset['url'] != expected:
        raise ValueError('Release 缺少本版本更新清单')
    manifest = request_json(expected)
    if manifest.get('schema') != 1 or manifest.get('client') != CLIENT or manifest.get('version') != version:
        raise ValueError('更新清单身份或版本不符')
    if {(p['platform'], p['architecture']) for p in manifest['packages']} != {
        ('android', 'arm64-v8a'),
    }:
        raise ValueError('更新清单缺少发布平台')
    for package in manifest['packages']:
        found = next((item for item in release['assets'] if item['name'] == package['name']), None)
        if (found is None or found['size'] != package['size'] or
                urllib.parse.unquote(found['url']) != urllib.parse.unquote(package['url'])):
            raise ValueError('Release 附件不完整')
    base = os.environ.get('BACKEND_BASE_URL', 'http://thankful.top:4396').rstrip('/')
    if os.environ.get('BACKEND_CLIENT', CLIENT) != CLIENT:
        raise ValueError('禁止写入其他软件类型')
    query = base + '/api/CloudSync/GetVersion?' + urllib.parse.urlencode({'Client': CLIENT})
    current = request_json(query)
    if current.get('success') is not True:
        raise ValueError('后台查询失败')
    data = current.get('data')
    payload = {'Client': CLIENT, 'Version': backend_version, 'Path': expected, 'Memo': manifest['notes']}
    fields = {'CLIENT': CLIENT, 'VERSION': backend_version, 'PATH': expected, 'MEMO': manifest['notes']}
    if not matches_fields(data, fields):
        if data:
            if data.get('CLIENT') != CLIENT:
                raise ValueError('后台软件类型不匹配')
            previous = version_key(data['VERSION'] + '+0')[:3]
            if previous > version_key(version)[:3]:
                raise ValueError('后台已有更高版本，拒绝回退')
            if previous == version_key(version)[:3] and data.get('PATH') != expected:
                raise ValueError('同版本下载地址不匹配，拒绝覆盖')
        elif current.get('code') != 404:
            raise ValueError('后台缺失记录但未明确返回 404')
        saved = request_json(base + '/api/CloudSync/SaveVersion', payload)
        if saved.get('success') is not True or not matches_fields(saved.get('data'), fields):
            raise ValueError('后台写入未确认成功：' + str(saved.get('message', '响应内容不匹配')))
    verified = request_json(query)
    if verified.get('success') is not True or not matches_fields(verified.get('data'), fields):
        raise ValueError('后台独立回读校验失败')
    summary(f'后台类型：{CLIENT}\n\n已同步版本：{version}\n\n更新清单：{expected}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['detect', 'prepare', 'publish', 'sync', 'verify-certificate'])
    parser.add_argument('path', nargs='?')
    args = parser.parse_args()
    actions = {'detect': detect, 'prepare': prepare, 'publish': publish, 'sync': sync_backend,
               'verify-certificate': lambda: verify_certificate(args.path)}
    try:
        actions[args.action]()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))


if __name__ == '__main__':
    main()
