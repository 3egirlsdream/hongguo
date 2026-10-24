import 'dart:io';

import 'package:duanju_app/diary_service.dart';
import 'package:duanju_app/playback_trace.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('playback diagnostics redact credentials and media addresses', () {
    final raw = '''open https://cdn.test/video/secret.mp4?token=abc
Cookie: sessionid=private; other=sensitive
Authorization: Bearer verysecret
x-tt-token="session-token" decryption_key=0123456789abcdef0123456789abcdef
{"token":"json-secret","password":"pass-secret"}
file:///data/user/0/package/private.mp4''';
    final safe = DiaryService.sanitize(raw);
    for (final secret in [
      'cdn.test',
      'secret.mp4',
      'abc',
      'private;',
      'sensitive',
      'verysecret',
      'session-token',
      '0123456789abcdef0123456789abcdef',
      'json-secret',
      'pass-secret',
      'private.mp4',
    ]) {
      expect(safe, isNot(contains(secret)), reason: secret);
    }
  });

  test(
    'diagnostics retain prior run, failed stages and bounded disk logs',
    () async {
      final directory = await Directory.systemTemp.createTemp('guo-diary-');
      addTearDown(() async {
        await DiaryService.flush();
        await directory.delete(recursive: true);
      });
      final file = File('${directory.path}/logs/playback.log');
      await file.parent.create(recursive: true);
      await file.writeAsString('[previous run] playback_stalled\n');
      DiaryService.add('[boot] current run');
      await DiaryService.initialize(directory.path);
      expect(
        DiaryService.fullText,
        contains('[previous run] playback_stalled'),
      );
      const channel = MethodChannel('duanju/device');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => {
              'transports': ['wifi'],
              'validated': true,
              'sdk': 36,
              'unexpectedPrivateValue': 'do-not-store',
            },
          );
      final trace = PlaybackTrace('test');
      await expectLater(
        trace.measure<void>('resolve', () async {
          throw StateError('HTTP 403 https://cdn.test/private?token=secret');
        }),
        throwsStateError,
      );
      await trace.networkSnapshot();
      await DiaryService.flush();
      final saved = await file.readAsString();
      expect(saved, contains('stage_failed'));
      expect(saved, contains('HTTP 403'));
      expect(saved, contains('wifi'));
      expect(saved, isNot(contains('cdn.test')));
      expect(saved, isNot(contains('do-not-store')));
      await file.writeAsString('x' * DiaryService.maxFileBytes);
      DiaryService.add('[Playback] failure after rotate');
      await DiaryService.flush();
      expect(await File('${file.path}.1').exists(), isTrue);
      expect(await file.readAsString(), contains('failure after rotate'));
      DiaryService.clear();
      await DiaryService.flush();
      expect(await file.exists(), isFalse);
      expect(await File('${file.path}.1').exists(), isFalse);
      expect(DiaryService.entries, isEmpty);
    },
  );
}
