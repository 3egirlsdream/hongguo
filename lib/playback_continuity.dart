import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.profile,
    required this.drama,
    required this.episodeId,
    required this.episodeNumber,
    required this.position,
    required this.playing,
    required this.localOnly,
    required this.allowOnlineFallback,
    this.mediaId,
  });

  final String profile;
  final Drama drama;
  final String episodeId;
  final int episodeNumber;
  final double position;
  final bool playing;
  final bool localOnly;
  final bool allowOnlineFallback;
  final String? mediaId;

  String encode() => jsonEncode({
    'schema': 1,
    'profile': profile,
    'drama': drama.toJson(),
    'episodeId': episodeId,
    'episodeNumber': episodeNumber,
    'position': position,
    'playing': playing,
    'localOnly': localOnly,
    'allowOnlineFallback': allowOnlineFallback,
    'mediaId': mediaId,
    'updatedAt': DateTime.now().millisecondsSinceEpoch,
  });

  static PlaybackSnapshot? decode(String value) {
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      final age =
          DateTime.now().millisecondsSinceEpoch - (json['updatedAt'] as int);
      final position = (json['position'] as num).toDouble();
      if (json['schema'] != 1 ||
          age < 0 ||
          age > 86400000 ||
          !position.isFinite ||
          position < 0) {
        return null;
      }
      return PlaybackSnapshot(
        profile: json['profile'] as String,
        drama: Drama.fromJson(Map<String, dynamic>.from(json['drama'] as Map)),
        episodeId: json['episodeId'] as String,
        episodeNumber: json['episodeNumber'] as int,
        position: position,
        playing: json['playing'] == true,
        localOnly: json['localOnly'] == true,
        allowOnlineFallback: json['allowOnlineFallback'] == true,
        mediaId: json['mediaId'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

class PlaybackContinuity {
  static const _channel = MethodChannel('duanju/playback');
  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static void watchWindowChanges(Future<void> Function()? listener) {
    if (!_supported) return;
    _channel.setMethodCallHandler(
      listener == null
          ? null
          : (call) async {
              if (call.method == 'windowChanged') await listener();
              return null;
            },
    );
  }

  static Future<void> discardRestore() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('discardRestore');
    } catch (_) {}
  }

  static Future<void> checkpoint(
    String owner,
    PlaybackSnapshot snapshot,
  ) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('checkpoint', {
        'owner': owner,
        'snapshot': snapshot.encode(),
      });
    } catch (_) {}
  }

  static Future<void> clear(String owner) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('clear', {'owner': owner});
    } catch (_) {}
  }

  static Future<PlaybackSnapshot?> takeRestore() async {
    if (!_supported) return null;
    try {
      final value = await _channel.invokeMethod<String>('takeRestore');
      return value == null ? null : PlaybackSnapshot.decode(value);
    } catch (_) {
      return null;
    }
  }
}
