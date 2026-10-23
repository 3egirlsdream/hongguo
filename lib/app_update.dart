import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const developerUrl = 'https://github.com/3egirlsdream';
const appRepositoryUrl = '$developerUrl/hongguo';
const appDownloadUrl = '$appRepositoryUrl/releases/latest';
const updateClient = 'Yeguo';
const updateBackendUrl = 'http://thankful.top:4396';

class AppVersion implements Comparable<AppVersion> {
  AppVersion(this.text) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)\+(\d+)$').firstMatch(text);
    if (match == null) throw const FormatException('版本信息格式无效');
    parts = List.generate(4, (index) => int.parse(match.group(index + 1)!));
  }

  final String text;
  late final List<int> parts;

  String get tag => 'app-v${text.replaceAll('+', '-')}';

  @override
  int compareTo(AppVersion other) {
    for (var index = 0; index < parts.length; index++) {
      final comparison = parts[index].compareTo(other.parts[index]);
      if (comparison != 0) return comparison;
    }
    return 0;
  }
}

class AppUpdatePackage {
  AppUpdatePackage(Map<String, dynamic> data, AppVersion version)
    : name = data['name'] as String,
      url = Uri.parse(data['url'] as String),
      size = data['size'] as int,
      digest = data['sha256'] as String {
    const extension = '.apk';
    if (name != p.basename(name) ||
        !name.startsWith('yeguo-${version.text}-') ||
        !name.endsWith(extension) ||
        url.scheme != 'https' ||
        url.host != 'github.com' ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment ||
        !listEquals(url.pathSegments, [
          '3egirlsdream',
          'hongguo',
          'releases',
          'download',
          version.tag,
          name,
        ]) ||
        size <= 0 ||
        size > 2 * 1024 * 1024 * 1024 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('更新包信息无效');
    }
  }

  final String name;
  final Uri url;
  final int size;
  final String digest;
}

class AppUpdateService extends ChangeNotifier {
  AppUpdateService._();

  static final instance = AppUpdateService._();
  static const _channel = MethodChannel('duanju/update');

  String installedVersion = '';
  AppVersion? availableVersion;
  AppUpdatePackage? package;
  String notes = '';
  String? message;
  bool checking = false;
  bool downloading = false;
  bool installing = false;
  bool installPermissionRequired = false;
  bool canInstall = false;
  int received = 0;
  File? _downloaded;
  HttpClient? _downloadClient;
  bool _cancelled = false;

  bool get busy => checking || downloading || installing;
  bool get downloaded => _downloaded != null;
  double? get progress => package == null ? null : received / package!.size;

  static Future<void> showUpdateToast(String version) async {
    try {
      await _channel.invokeMethod<void>('showUpdateToast', {
        'version': version,
      });
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }

  Future<void> loadInstalledVersion() async {
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>('info');
      if (info == null) throw const FormatException('无法读取当前版本');
      installedVersion = '${info['version']}+${info['build']}';
      AppVersion(installedVersion);
      canInstall = info['canInstall'] == true;
    } catch (error) {
      installedVersion = '';
      message = '无法读取当前版本：$error';
      canInstall = false;
    }
    notifyListeners();
  }

  Future<void> check() async {
    if (busy) return;
    checking = true;
    message = null;
    availableVersion = null;
    package = null;
    _downloaded = null;
    installPermissionRequired = false;
    received = 0;
    notes = '';
    notifyListeners();
    final client = _client();
    try {
      await loadInstalledVersion();
      if (installedVersion.isEmpty) throw const FormatException('无法确定当前版本');
      final current = AppVersion(installedVersion);
      final response = await _json(
        client,
        Uri.parse(
          '$updateBackendUrl/api/CloudSync/GetVersion?Client=$updateClient',
        ),
      );
      if (response['success'] != true) throw const FormatException('后台查询失败');
      final data = response['data'];
      if (data == null && response['code'] == 404) {
        message = '后台尚未发布本软件的更新版本';
        return;
      }
      if (data is! Map || data['CLIENT'] != updateClient) {
        throw const FormatException('后台软件类型不匹配');
      }
      final backendVersion = data['VERSION'] as String;
      final manifestUrl = Uri.parse(data['PATH'] as String);
      final segments = manifestUrl.pathSegments;
      final tag = segments.length == 6
          ? RegExp(r'^app-v(\d+\.\d+\.\d+)-(\d+)$').firstMatch(segments[4])
          : null;
      if (manifestUrl.scheme != 'https' ||
          manifestUrl.host != 'github.com' ||
          manifestUrl.userInfo.isNotEmpty ||
          manifestUrl.hasQuery ||
          manifestUrl.hasFragment ||
          tag == null ||
          tag.group(1) != backendVersion ||
          !listEquals(segments.take(4).toList(), [
            '3egirlsdream',
            'hongguo',
            'releases',
            'download',
          ]) ||
          segments.last != 'update.json') {
        throw const FormatException('后台更新清单地址无效');
      }
      final version = AppVersion('${tag.group(1)}+${tag.group(2)}');
      if (version.compareTo(current) <= 0) {
        message = '当前已是最新版本';
        return;
      }
      final manifest = await _json(client, manifestUrl);
      if (manifest['schema'] != 1 ||
          manifest['client'] != updateClient ||
          manifest['version'] != version.text) {
        throw const FormatException('更新清单版本不一致');
      }
      notes = manifest['notes'] as String? ?? '';
      final architecture = switch (Abi.current()) {
        Abi.androidArm64 => 'arm64-v8a',
        _ => '',
      };
      final packages = manifest['packages'] as List;
      final candidates = packages.whereType<Map<String, dynamic>>().where(
        (item) =>
            item['platform'] == 'android' &&
            item['architecture'] == architecture,
      );
      if (canInstall && candidates.length == 1) {
        package = AppUpdatePackage(candidates.single, version);
        message = '发现新版本 ${version.text}';
      } else {
        message = '发现新版本 ${version.text}，请前往下载页面选择安装包';
      }
      availableVersion = version;
    } catch (error) {
      message = '检查更新失败：$error';
    } finally {
      client.close(force: true);
      checking = false;
      notifyListeners();
    }
  }

  Future<void> download() async {
    final update = package;
    if (busy || update == null) return;
    downloading = true;
    _cancelled = false;
    received = 0;
    _downloaded = null;
    installPermissionRequired = false;
    message = '正在下载更新';
    notifyListeners();
    final client = _client();
    _downloadClient = client;
    File? partial;
    IOSink? sink;
    try {
      final cache = await getTemporaryDirectory();
      final directory = Directory(p.join(cache.path, 'app-updates'));
      await directory.create(recursive: true);
      for (final old in directory.listSync().whereType<File>()) {
        await old.delete();
      }
      partial = File(p.join(directory.path, '${update.name}.part'));
      final target = File(p.join(directory.path, update.name));
      final response = await _get(client, update.url);
      if (response.contentLength != -1 &&
          response.contentLength != update.size) {
        throw const FormatException('更新包长度与发布信息不符');
      }
      sink = partial.openWrite();
      var lastNotice = DateTime.now();
      await for (final chunk in response.timeout(const Duration(seconds: 45))) {
        if (_cancelled) throw const HttpException('下载已取消');
        received += chunk.length;
        if (received > update.size) throw const FormatException('更新包超过声明大小');
        sink.add(chunk);
        if (DateTime.now().difference(lastNotice).inMilliseconds >= 150) {
          await sink.flush();
          notifyListeners();
          lastNotice = DateTime.now();
        }
      }
      await sink.close();
      sink = null;
      if (_cancelled) throw const HttpException('下载已取消');
      if (received != update.size ||
          (await sha256.bind(partial.openRead()).first).toString() !=
              update.digest) {
        throw const FormatException('更新包完整性校验失败，请重试');
      }
      _downloaded = await partial.rename(target.path);
      partial = null;
      message = '下载及校验完成';
    } catch (error) {
      message = _cancelled ? '下载已取消，可重新下载' : '下载更新失败：$error';
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        if (partial != null && await partial.exists()) await partial.delete();
      } catch (_) {}
      client.close(force: true);
      _downloadClient = null;
      downloading = false;
      notifyListeners();
    }
    if (_downloaded != null && !_cancelled) await install();
  }

  void cancelDownload() {
    if (!downloading) return;
    _cancelled = true;
    _downloadClient?.close(force: true);
  }

  Future<void> install() async {
    final file = _downloaded;
    final update = package;
    if (busy || file == null || update == null) return;
    installing = true;
    message = null;
    notifyListeners();
    try {
      if (await file.length() != update.size ||
          (await sha256.bind(file.openRead()).first).toString() !=
              update.digest) {
        _downloaded = null;
        throw const FormatException('更新包校验失败，请重新下载');
      }
      final status = await _channel.invokeMethod<String>('install', {
        'path': file.path,
      });
      installPermissionRequired = status == 'permissionRequired';
      message = installPermissionRequired
          ? '请允许安装此来源的应用，返回后点击「继续安装」'
          : '已打开系统安装界面，请完成安装';
    } catch (error) {
      message = '启动安装失败：$error';
    } finally {
      installing = false;
      notifyListeners();
    }
  }

  static Future<void> openLink(String url) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' || uri.host != 'github.com') {
      throw const FormatException('链接地址无效');
    }
    await _channel.invokeMethod<void>('openLink', {'url': url});
  }

  static HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..userAgent = 'Yeguo-Updater/1';

  static Future<HttpClientResponse> _get(HttpClient client, Uri url) async {
    var target = url;
    for (var redirects = 0; redirects <= 5; redirects++) {
      final request = await client
          .getUrl(target)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>().timeout(const Duration(seconds: 10));
        if (location == null) throw const FormatException('下载重定向缺少地址');
        target = target.resolve(location);
        if (target.scheme != 'https' ||
            target.userInfo.isNotEmpty ||
            !(target.host == 'github.com' ||
                target.host.endsWith('.githubusercontent.com'))) {
          throw const FormatException('下载重定向地址不受支持');
        }
        continue;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('服务器返回 HTTP ${response.statusCode}');
      }
      return response;
    }
    throw const HttpException('下载重定向次数过多');
  }

  static Future<Map<String, dynamic>> _json(HttpClient client, Uri url) async {
    final response = await _get(client, url);
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      bytes.add(chunk);
      if (bytes.length > 1024 * 1024) throw const FormatException('版本响应过大');
    }
    final data = jsonDecode(utf8.decode(bytes.takeBytes()));
    if (data is! Map<String, dynamic>) throw const FormatException('版本响应格式无效');
    return data;
  }
}
