import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

export 'app_build.dart';

const appVersion = '0.2.106';

class AppDevice {
  const AppDevice({
    this.version = appVersion,
    this.flipDevice = false,
    this.pictureInPicture = false,
  });
  final String version;
  final bool flipDevice;
  final bool pictureInPicture;
  static const channel = MethodChannel('duanju/device');

  static Future<AppDevice> detect({
    AppDevice fallback = const AppDevice(),
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const AppDevice();
    }
    try {
      final data = await channel
          .invokeMapMethod<String, dynamic>('deviceInfo')
          .timeout(const Duration(seconds: 2));
      if (data == null) return fallback;
      final version = data['version'];
      return AppDevice(
        flipDevice: data['flipDevice'] == true,
        pictureInPicture: data['pictureInPicture'] == true,
        version: version is String && version.isNotEmpty
            ? version
            : fallback.version,
      );
    } on PlatformException {
      return fallback;
    } on MissingPluginException {
      return fallback;
    } on TimeoutException {
      return fallback;
    }
  }

  static Future<double> getBrightness() async {
    if (defaultTargetPlatform != TargetPlatform.android) return 0.5;
    try {
      final value = await channel.invokeMethod<double>('getBrightness');
      return (value ?? 0.5).clamp(0.0, 1.0);
    } catch (_) {
      return 0.5;
    }
  }

  static Future<void> setBrightness(double brightness) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await channel.invokeMethod('setBrightness', {
        'brightness': brightness.clamp(0.01, 1.0),
      });
    } catch (_) {}
  }

  static Future<void> resetBrightness() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await channel.invokeMethod('resetBrightness');
    } catch (_) {}
  }
}

class AppLayout extends InheritedWidget {
  const AppLayout({
    super.key,
    this.coverWindow = false,
    this.version = appVersion,
    required super.child,
  });
  final bool coverWindow;
  final String version;

  static bool isCoverWindow(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLayout>()?.coverWindow ??
      false;
  static String versionOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLayout>()?.version ??
      appVersion;

  @override
  bool updateShouldNotify(AppLayout oldWidget) =>
      coverWindow != oldWidget.coverWindow || version != oldWidget.version;
}
