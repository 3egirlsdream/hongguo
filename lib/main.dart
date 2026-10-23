import 'dart:async';
import 'dart:ui' show DisplayFeature;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core_bridge.dart';
import 'app_layout.dart';
import 'app_orientation.dart';
import 'app_theme.dart';
import 'home_screen.dart';
import 'local_store.dart';
import 'profiles_screen.dart';
import 'media_library.dart';
import 'lan_controller.dart';
import 'player_screen.dart';
import 'playback_continuity.dart';
import 'playback_restore_screen.dart';
import 'theme_appearance.dart';
import 'diary_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DiaryService.add('[App] 应用启动，版本: 0.2.86+93, 平台: Android');
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(AppTheme.systemBars(Brightness.dark));
  MediaKit.ensureInitialized();
  final device = await AppDevice.detect();
  runApp(AppBootstrap(device: device));
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key, this.device = const AppDevice()});
  final AppDevice device;
  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap>
    with WidgetsBindingObserver {
  final repository = NativeRepository();
  final navigator = GlobalKey<NavigatorState>();
  LocalStore? store;
  PlaybackSnapshot? _pendingPlayback;
  bool _restoreScheduled = false;
  Object? error;
  late AppDevice device = widget.device;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LanController.current?.dispose();
    LanController.current = null;
    MediaLibrary.current?.dispose();
    MediaLibrary.current = null;
    repository.stopOfficialSync();
    PlaybackContinuity.watchWindowChanges(null);
    store?.removeListener(_restorePlayback);
    store?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PlaybackContinuity.watchWindowChanges(_refreshDevice);
    _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshDevice());
  }

  Future<void> _refreshDevice() async {
    final detected = await AppDevice.detect(fallback: device);
    if (!mounted ||
        (device.version == detected.version &&
            device.flipDevice == detected.flipDevice &&
            device.pictureInPicture == detected.pictureInPicture)) {
      return;
    }
    setState(() => device = detected);
  }

  Future<void> _initialize() async {
    setState(() {
      error = null;
    });
    try {
      final preferences = await SharedPreferences.getInstance();
      await _refreshDevice();
      await repository.initialize();
      _pendingPlayback = await PlaybackContinuity.takeRestore();
      if (mounted) {
        setState(() {
          store = LocalStore(preferences);
          store!.addListener(_restorePlayback);
          repository.access = store;
          repository.startOfficialSync();
          MediaLibrary.attach(repository, store!);
          LanController.current?.dispose();
          final link = LanController(repository, store!, kind: 'phone');
          LanController.current = link;
          link.openPlayback = (request) async {
            final epoch = request.profileEpoch;
            if (request.cancelled ||
                !mounted ||
                store!.locked ||
                !link.receiving ||
                store!.profileEpoch != epoch ||
                !store!.allowsSource(request.detail.drama.source)) {
              throw StateError('当前用户不能接收播放');
            }
            await link.playbackHost?.stop();
            if (request.cancelled ||
                !mounted ||
                store!.locked ||
                store!.profileEpoch != epoch ||
                !link.receiving) {
              throw StateError('播放接收已取消');
            }
            final navigation = navigator.currentState;
            if (navigation == null) throw StateError('接收设备界面尚未就绪');
            unawaited(
              navigation.pushAndRemoveUntil<void>(
                MaterialPageRoute<void>(
                  builder: (_) => PlayerScreen(
                    detail: request.detail,
                    initialIndex: request.index,
                    initialPosition: request.position,
                    repository: repository,
                    store: store!,
                    handoff: request,
                  ),
                ),
                (route) => route.isFirst,
              ),
            );
          };
        });
        _restorePlayback();
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = failure;
        });
      }
    }
  }

  void _restorePlayback() {
    final snapshot = _pendingPlayback;
    final current = store;
    if (!mounted ||
        snapshot == null ||
        current == null ||
        current.locked ||
        _restoreScheduled) {
      return;
    }
    if (current.profile.id != snapshot.profile) {
      _pendingPlayback = null;
      unawaited(PlaybackContinuity.discardRestore());
      return;
    }
    _restoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreScheduled = false;
      if (!mounted || current.locked) return;
      if (current.profile.id != snapshot.profile) {
        _pendingPlayback = null;
        unawaited(PlaybackContinuity.discardRestore());
        return;
      }
      final navigation = navigator.currentState;
      if (navigation == null) return;
      _pendingPlayback = null;
      unawaited(
        navigation.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => PlaybackRestoreScreen(
              snapshot: snapshot,
              repository: repository,
              store: current,
            ),
          ),
        ),
      );
    });
  }

  @override
  void didChangeMetrics() {
    unawaited(_refreshDevice());
  }

  @override
  Widget build(BuildContext context) => DuanjuApp(
    repository: repository,
    store: store,
    bootstrapError: error?.toString(),
    onRetry: _initialize,
    version: device.version,
    flipDevice: device.flipDevice,
    pictureInPicture: device.pictureInPicture,
    navigatorKey: navigator,
  );
}

class DuanjuApp extends StatelessWidget {
  const DuanjuApp({
    super.key,
    required this.repository,
    this.store,
    this.bootstrapError,
    this.onRetry,
    this.version = appVersion,
    this.navigatorKey,
    this.flipDevice = false,
    this.pictureInPicture = false,
  });
  final AppRepository repository;
  final LocalStore? store;
  final String? bootstrapError;
  final VoidCallback? onRetry;
  final bool flipDevice;
  final bool pictureInPicture;
  final String version;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([store]),
    builder: (_, _) => _application(),
  );

  ThemeAppearance get _appearance =>
      store?.themeAppearance ?? const ThemeAppearance();

  ThemeData _themed(ThemeData base, ThemeAppearance appearance) =>
      base.copyWith(
        pageTransitionsTheme: PageTransitionsTheme(
          builders: {
            TargetPlatform.android:
                appearance.predictiveBack || appearance.swipeBack
                ? const CupertinoPageTransitionsBuilder()
                : const FadeUpwardsPageTransitionsBuilder(),
          },
        ),
      );

  /// 全局界面缩放：按逻辑尺寸反向缩放内容，保证布局与点击区域同步缩放。
  Widget _scaled(Widget child, double scale, BuildContext context) {
    if ((scale - 1).abs() < 0.001) return child;
    final media = MediaQuery.of(context);
    final size = media.size;
    return MediaQuery(
      data: media.copyWith(
        size: size / scale,
        devicePixelRatio: media.devicePixelRatio * scale,
        padding: media.padding / scale,
        viewPadding: media.viewPadding / scale,
        viewInsets: media.viewInsets / scale,
        systemGestureInsets: media.systemGestureInsets / scale,
        displayFeatures: media.displayFeatures
            .map(
              (feature) => DisplayFeature(
                bounds: Rect.fromLTRB(
                  feature.bounds.left / scale,
                  feature.bounds.top / scale,
                  feature.bounds.right / scale,
                  feature.bounds.bottom / scale,
                ),
                type: feature.type,
                state: feature.state,
              ),
            )
            .toList(),
      ),
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: size.width / scale,
          height: size.height / scale,
          child: child,
        ),
      ),
    );
  }

  Widget _application() {
    final navigationKey =
        navigatorKey ?? GlobalObjectKey<NavigatorState>(repository);
    return MaterialApp(
      navigatorKey: navigationKey,
      title: appName,
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: _themed(AppTheme.light, _appearance),
      darkTheme: _themed(AppTheme.dark, _appearance),
      themeMode: AppTheme.mode(store?.themeMode ?? 'system'),
      builder: (context, child) {
        final theme = Theme.of(context);
        final window = MediaQuery.sizeOf(context);
        final coverWindow =
            flipDevice &&
            !pictureInPicture &&
            window.width < 600 &&
            window.height < 600;
        final content = AnnotatedRegion<SystemUiOverlayStyle>(
          value: AppTheme.systemBars(theme.brightness),
          child: ColoredBox(
            color: theme.scaffoldBackgroundColor,
            child: AppOrientationScope(
              coverWindow: coverWindow,
              child: AppLayout(
                coverWindow: coverWindow,
                version: version,
                child: Theme(
                  data: theme,
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(
                        LogicalKeyboardKey.goBack,
                        includeRepeats: false,
                      ): () =>
                          navigationKey.currentState?.maybePop(),
                      const SingleActivator(
                        LogicalKeyboardKey.escape,
                        includeRepeats: false,
                      ): () =>
                          navigationKey.currentState?.maybePop(),
                    },
                    child: Builder(
                      builder: (context) => _scaled(
                        FocusTraversalGroup(child: child!),
                        _appearance.scale,
                        context,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        return content;
      },
      home: store != null
          ? store!.locked
                ? ProfilesScreen(store: store!, locked: true)
                : HomeScreen(
                    key: ValueKey(
                      'profile-${store!.profile.id}-${store!.profileEpoch}',
                    ),
                    repository: repository,
                    store: store!,
                  )
          : Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.play_circle_fill_rounded,
                        color: Color(0xFFFF765F),
                        size: 72,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        bootstrapError ?? '正在打开$appName',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 24),
                      if (bootstrapError == null)
                        const CircularProgressIndicator()
                      else
                        FilledButton(
                          onPressed: onRetry,
                          child: const Text('重新打开'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
