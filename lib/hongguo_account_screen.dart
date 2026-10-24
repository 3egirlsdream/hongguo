import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core_bridge.dart';
import 'local_store.dart';
import 'models.dart';
import 'playback_launch_screen.dart';
import 'widgets.dart';
import 'saved_library.dart';
import 'detail_screen.dart';

Future<void> openHongguoAccount(
  BuildContext context,
  AppRepository repository,
  LocalStore store, {
  Drama? drama,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => HongguoAccountScreen(
      repository: repository,
      store: store,
      drama: drama,
      collections: drama != null,
    ),
  ),
);

Future<void> openPersonalLibrary(
  BuildContext context,
  AppRepository repository,
  LocalStore store, {
  int initialTab = 0,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => HongguoAccountScreen(
      repository: repository,
      store: store,
      collections: true,
      initialTab: initialTab,
    ),
  ),
);

class HongguoAccountScreen extends StatefulWidget {
  const HongguoAccountScreen({
    super.key,
    required this.repository,
    required this.store,
    this.drama,
    this.collections = false,
    this.initialTab = 0,
    this.embedded = false,
    this.refreshToken = 0,
  });
  final AppRepository repository;
  final LocalStore store;
  final Drama? drama;
  final bool collections;
  final int initialTab;
  final bool embedded;
  final int refreshToken;
  @override
  State<HongguoAccountScreen> createState() => _HongguoAccountScreenState();
}

class _HongguoAccountScreenState extends State<HongguoAccountScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  late final TabController _tabs;
  late final int _epoch;
  Timer? _clock;
  Timer? _verification;
  int _verificationRun = 0;
  bool _checkingSMS = false;
  int _verificationChecks = 0;
  DateTime? _verificationDeadline;
  Map<String, dynamic> _status = {};
  final List<Map<String, dynamic>> _items = [];
  List<WatchEntry> _accountHistory = const [];
  bool _busy = false, _loading = false, _hasMore = false;
  int _offset = 0, _revision = 0;
  int? _subscribeOffset;
  bool _statusLoading = false;
  bool _statusRefreshPending = false;
  int _statusVersion = 0;
  int _selectedTab = 0;
  String _cursor = '';
  String _reservationMode = 'upcoming';
  String _calendarFilter = '';
  bool _reservationLoadScheduled = false;
  String? _error, _message;
  bool _librarySearching = false;
  bool get _active =>
      mounted &&
      widget.store.profileEpoch == _epoch &&
      widget.store.allowsSource('hongguo');
  String get _uid => (_status['profile'] as Map?)?['uid'] as String? ?? '';
  bool get _logged => _status['loggedIn'] == true;

  @override
  void initState() {
    super.initState();
    _epoch = widget.store.profileEpoch;
    _tabs = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.drama == null ? widget.initialTab : 2,
    )..addListener(_tabChanged);
    _selectedTab = _tabs.index;
    widget.store.addListener(_accessChanged);
    widget.repository.accountFavorites.addListener(_favoritesChanged);
    widget.repository.accountStatus.addListener(_accountStatusChanged);
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus(loadCollections: true);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_active &&
          !widget.collections &&
          (!_busy || _checkingSMS) &&
          !_loading) {
        _refreshStatus();
      }
    });
  }

  @override
  void didUpdateWidget(covariant HongguoAccountScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      unawaited(_refreshStatus(loadCollections: true));
    }
    if (oldWidget.initialTab != widget.initialTab) {
      _tabs.animateTo(widget.initialTab);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _active &&
        ModalRoute.of(context)?.isCurrent == true) {
      unawaited(_resumeAccount());
    }
  }

  Future<void> _resumeAccount() async {
    await _refreshStatus(loadCollections: true);
    if (_active &&
        !widget.collections &&
        !_logged &&
        _status['phase'] == 'mfa') {
      if (_checkingSMS &&
          !_busy &&
          _verificationDeadline?.isBefore(DateTime.now()) == true) {
        _stopSMSChecks();
      }
      await _checkSMS();
    }
  }

  void _accountStatusChanged() {
    if (!_active) return;
    final result = widget.repository.accountStatus.value;
    final previousUID = _uid;
    final wasLogged = _logged;
    final previousSync = _status['lastSync'];
    final previousLoginError = _status['loginError'] as String? ?? '';
    _statusVersion++;
    setState(() {
      _status = result;
      if (previousUID != _uid) {
        _revision++;
        _items.clear();
        _accountHistory = const [];
        _hasMore = false;
        _error = null;
      }
      final loginError = result['loginError'] as String? ?? '';
      if (loginError.isNotEmpty) {
        _error = loginError;
      } else if (previousLoginError.isNotEmpty &&
          _error == previousLoginError) {
        _error = null;
      }
    });
    if (widget.collections && _logged) {
      if (previousUID != _uid || !wasLogged) {
        if (_statusLoading) {
          _statusRefreshPending = true;
        } else {
          unawaited(_load());
        }
      } else if (previousSync != _status['lastSync']) {
        unawaited(_readHistory());
      }
    }
  }

  void _favoritesChanged() {
    if (_active &&
        widget.collections &&
        _tabs.index == 0 &&
        _logged &&
        !_loading &&
        !_busy &&
        !_statusLoading) {
      unawaited(_load());
    }
  }

  void _accessChanged() {
    if (!_active) {
      _stopSMSChecks();
      _clock?.cancel();
      _revision++;
      if (mounted) setState(() {});
    }
  }

  void _tabChanged() {
    if (_selectedTab == _tabs.index) return;
    _selectedTab = _tabs.index;
    setState(() {
      _revision++;
      _items.clear();
      _hasMore = false;
      _offset = 0;
      _cursor = '';
      _subscribeOffset = null;
      _message = null;
      _error = null;
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _stopSMSChecks();
    _tabs.dispose();
    _phone.dispose();
    _code.dispose();
    widget.store.removeListener(_accessChanged);
    widget.repository.accountFavorites.removeListener(_favoritesChanged);
    widget.repository.accountStatus.removeListener(_accountStatusChanged);
    super.dispose();
  }

  Future<void> _refreshStatus({bool loadCollections = false}) async {
    if (!_active || !widget.repository.supportsOfficialAccount) return;
    if (_statusLoading) {
      _statusRefreshPending = _statusRefreshPending || loadCollections;
      return;
    }
    _statusLoading = true;
    final statusVersion = _statusVersion;
    try {
      final result = await widget.repository.hongguoAccount('status');
      if (statusVersion != _statusVersion) {
        _statusRefreshPending = true;
        return;
      }
      if (_active) {
        final wasLogged = _logged;
        final previousUID = _uid;
        final previousSync = _status['lastSync'];
        final previousLoginError = _status['loginError'] as String? ?? '';
        setState(() {
          _status = result;
          if (previousUID != _uid) {
            _revision++;
            _items.clear();
            _accountHistory = const [];
            _error = null;
            _hasMore = false;
          }
          final loginError = result['loginError'] as String? ?? '';
          if (loginError.isNotEmpty) {
            _error = loginError;
            _message = null;
          } else if (previousLoginError.isNotEmpty &&
              _error == previousLoginError) {
            _error = null;
          }
        });
        if (_logged && (loadCollections || !wasLogged || previousUID != _uid)) {
          widget.repository.requestOfficialSync();
        }
        if (_logged &&
            widget.collections &&
            (previousUID != _uid || previousSync != _status['lastSync'])) {
          await _readHistory();
        }
        if ((loadCollections || !wasLogged) && _logged && widget.collections) {
          await _load();
        }
        if (loadCollections &&
            !widget.collections &&
            !_logged &&
            _status['phase'] == 'mfa' &&
            (_status['loginError'] as String? ?? '').isEmpty) {
          unawaited(_checkSMS());
        }
      }
    } catch (error) {
      if (_active) setState(() => _error = error.toString());
    } finally {
      _statusLoading = false;
      if (_statusRefreshPending && _active) {
        _statusRefreshPending = false;
        unawaited(_refreshStatus(loadCollections: true));
      }
    }
  }

  Future<bool> _run(
    String command, [
    Map<String, dynamic> input = const {},
  ]) async {
    if (!_active || _busy || _loading) return false;
    final loginOperation = {'sendCode', 'login', 'verifySMS'}.contains(command);
    final loginRun = _verificationRun;
    bool current() =>
        _active && (!loginOperation || loginRun == _verificationRun);
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await widget.repository.hongguoAccount(command, input);
      if (!current()) return false;
      _statusVersion++;
      setState(() {
        if (result.containsKey('loggedIn')) _status = result;
        if ((result['warning'] as String? ?? '').isNotEmpty) {
          _error = result['warning'] as String;
        }
      });
      return (result['warning'] as String? ?? '').isEmpty;
    } catch (error) {
      if (current()) setState(() => _error = error.toString());
      return false;
    } finally {
      if (_active) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    if (await _run('sendCode', {'phone': _phone.text.trim()})) {
      if (_active) setState(() => _message = '验证码已发送，请在此输入。');
    } else {
      await _refreshStatus();
    }
  }

  Future<void> _login() async {
    if (await _run('login', {'code': _code.text.trim()})) {
      if (_logged) {
        await _completeLogin();
      } else if (_status['phase'] == 'mfa') {
        await _checkSMS();
      }
    } else {
      await _refreshStatus();
    }
  }

  void _stopSMSChecks() {
    _verificationRun++;
    _verification?.cancel();
    _verification = null;
    _checkingSMS = false;
    _verificationDeadline = null;
  }

  Future<void> _completeLogin() async {
    if (!_active || !_logged) return;
    final owner = _uid;
    _stopSMSChecks();
    _code.clear();
    _phone.clear();
    widget.repository.requestOfficialSync();
    if (!_active || !_logged || _uid != owner) return;
    setState(() {
      _message = '登录成功，观看历史将自动同步';
      if (_error != null) _error = '账号已登录，资料同步暂未完成：$_error';
    });
  }

  Future<void> _checkSMS() async {
    if (!_active || _logged || _status['phase'] != 'mfa' || _checkingSMS) {
      return;
    }
    _verification?.cancel();
    final run = ++_verificationRun;
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    setState(() {
      _checkingSMS = true;
      _verificationChecks = 0;
      _verificationDeadline = deadline;
      _error = null;
      _message = null;
    });
    Future<void> poll() async {
      if (!_active || run != _verificationRun) return;
      if (_logged) {
        await _completeLogin();
        return;
      }
      if (_status['phase'] != 'mfa') {
        setState(() {
          _stopSMSChecks();
          final loginError = _status['loginError'] as String? ?? '';
          _error = loginError.isNotEmpty ? loginError : '本次短信验证已结束，请在此重新获取验证码';
        });
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        setState(() {
          _stopSMSChecks();
          _error = _status['verificationState'] == 'verified'
              ? '短信已验证，但登录暂未完成。可点击“重试完成登录”，无需退出重登。'
              : '90 秒内未确认短信验证结果。请确认短信已发送，可点击“继续检查”，无需退出重登。';
        });
        return;
      }
      if (_busy || _loading) {
        _verification = Timer(const Duration(seconds: 3), poll);
        return;
      }
      setState(() => _verificationChecks++);
      final okay = await _run('verifySMS');
      if (!_active || run != _verificationRun) return;
      if (!okay) {
        final failure = _error;
        await _refreshStatus();
        if (!_active || run != _verificationRun) return;
        if (_logged) {
          await _completeLogin();
          return;
        }
        setState(() {
          _stopSMSChecks();
          final loginError = _status['loginError'] as String? ?? '';
          _error = loginError.isNotEmpty
              ? loginError
              : failure ?? '检查未完成，请在当前页面重试';
          _message = null;
        });
        return;
      }
      if (_logged) {
        await _completeLogin();
        return;
      }
      _verification = Timer(const Duration(seconds: 3), poll);
    }

    await poll();
  }

  Future<void> _cancel() async {
    if (!_active) return;
    setState(() {
      _stopSMSChecks();
      _statusVersion++;
      _error = null;
      _message = null;
    });
    try {
      final result = await widget.repository.hongguoAccount('cancel');
      if (!_active) return;
      setState(() {
        _statusVersion++;
        _status = result;
        _message = _logged ? '登录成功' : '已取消登录';
      });
      _code.clear();
      if (_logged) _phone.clear();
    } catch (error) {
      if (_active) setState(() => _error = error.toString());
    }
  }

  Future<void> _logout() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出账号？'),
        content: const Text('本机观看记录和待同步进度会保留，再次登录此账号后可继续同步。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (accepted == true && await _run('logout')) {
      _revision++;
      _items.clear();
      _stopSMSChecks();
      _code.clear();
      _tabs.index = 0;
    }
  }

  Future<void> _load({bool more = false}) async {
    if (!_active || !_logged || !widget.collections || _loading || _busy) {
      return;
    }
    final tab = _tabs.index, revision = ++_revision;
    final owner = _uid;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) {
        _offset = 0;
        _cursor = '';
        _subscribeOffset = null;
        _hasMore = false;
      }
    });
    try {
      if (tab == 1 && !more) widget.repository.requestOfficialSync();
      final command = tab == 0
          ? 'favorites'
          : tab == 1
          ? 'history'
          : tab == 2
          ? 'reservations'
          : 'calendar';
      final result = await widget.repository.hongguoAccount(command, {
        'uid': owner,
        'refresh': false,
        'offset': _offset,
        'cursor': _cursor,
        'mode': tab == 0
            ? 'online'
            : tab == 2
            ? _reservationMode
            : '',
        if (_subscribeOffset != null) 'subscribeOffset': _subscribeOffset,
      });
      if (!_active ||
          revision != _revision ||
          tab != _tabs.index ||
          owner != _uid) {
        return;
      }
      final rows = [
        for (final row in result['items'] as List? ?? [])
          Map<String, dynamic>.from(row as Map),
      ];
      if (tab == 1) {
        rows.sort(
          (a, b) =>
              DateTime.tryParse('${b['updatedAt']}')?.compareTo(
                DateTime.tryParse('${a['updatedAt']}') ?? DateTime(2000),
              ) ??
              0,
        );
      }
      setState(() {
        if ((result['warning'] as String? ?? '').isNotEmpty) {
          _error = result['warning'] as String;
        }
        if (tab == 1) {
          _accountHistory = [for (final row in rows) WatchEntry.fromJson(row)];
        }
        if (!more) _items.clear();
        final existing = _items
            .map((row) => '${row['id'] ?? (row['drama'] as Map?)?['id']}')
            .toSet();
        for (final row in rows) {
          if (existing.add('${row['id'] ?? (row['drama'] as Map?)?['id']}')) {
            _items.add(row);
          }
        }
        _hasMore = result['hasMore'] == true;
        _offset = intValue(result['offset']);
        _cursor = result['cursor'] as String? ?? '';
        _subscribeOffset = result['subscribeOffset'] as int?;
      });
    } catch (error) {
      if (_active && revision == _revision) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (_active) {
        setState(() => _loading = false);
        if (tab != _tabs.index) unawaited(_load());
      }
    }
  }

  Future<void> _reserve(Map<String, dynamic> item) async {
    final desired = item['reserved'] != true;
    if (await _run('reserve', {
      'uid': _uid,
      'id': item['id'],
      'reserved': desired,
    })) {
      if (_active) {
        setState(() => _message = desired ? '已在云端列表确认预约' : '已在云端列表确认取消预约');
        await _load();
      }
    }
  }

  Future<void> _readHistory() async {
    final owner = _uid;
    try {
      final result = await widget.repository.hongguoAccount('history', {
        'uid': owner,
      });
      final rows = [
        for (final row in result['items'] as List? ?? [])
          WatchEntry.fromJson(Map<String, dynamic>.from(row as Map)),
      ];
      if (_active && owner == _uid) {
        setState(() {
          _accountHistory = rows;
          if ((result['warning'] as String? ?? '').isNotEmpty) {
            _error = result['warning'] as String;
          }
        });
      }
    } catch (error) {
      if (_active && owner == _uid) setState(() => _error = '账号历史暂不可用：$error');
    }
  }

  Future<void> _openAccount() async {
    await openHongguoAccount(context, widget.repository, widget.store);
    if (_active) {
      await _refreshStatus();
      await _load();
    }
  }

  Future<void> _unfollow(Drama drama) async {
    final row = _items
        .where((r) => (r['drama'] as Map?)?['id'] == drama.id)
        .firstOrNull;
    if (row == null) return;
    if (await _run('favorite', {
      'uid': _uid,
      'id': row['id'],
      'followed': false,
    })) {
      if (!_active) return;
      if (mounted && widget.store.following(drama.id) != null) {
        await saveUserChange(context, () => widget.store.toggleFavorite(drama));
      }
      if (_active) await _load();
    }
  }

  Widget _savedCollections() {
    final history = _tabs.index == 1;
    return Column(
      children: [
        if (!widget.embedded)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _logged ? '打开时自动更新' : '登录后同步账号记录',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (!_logged || !history)
                  TextButton(
                    onPressed: _busy || _loading
                        ? null
                        : !_logged
                        ? _openAccount
                        : _load,
                    child: Text(_logged ? '刷新' : '登录'),
                  ),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: SavedLibrary(
              compact: widget.embedded,
              searchVisible: widget.embedded ? _librarySearching : null,
              key: ValueKey('collection-$history'),
              repository: widget.repository,
              store: widget.store,
              history: history,
              remoteHistory: _accountHistory,
              remoteFavorites: !history
                  ? [
                      for (final row in _items)
                        Drama.fromJson(
                          Map<String, dynamic>.from(row['drama'] as Map),
                        ),
                    ]
                  : const [],
              onRemoteUnfollow: _unfollow,
              onHistoryContinue: (entry) async {
                await openPlaybackDirectly(
                  context,
                  drama: entry.drama,
                  repository: widget.repository,
                  store: widget.store,
                  resumeOverride: entry,
                );
                if (_active) await _load();
              },
              onOpen: (drama) async {
                await openPlaybackDirectly(
                  context,
                  drama: drama,
                  repository: widget.repository,
                  store: widget.store,
                );
                if (_active) await _load();
              },
              onContinue: (drama) async {
                await openPlaybackDirectly(
                  context,
                  drama: drama,
                  repository: widget.repository,
                  store: widget.store,
                );
                if (_active) await _load();
              },
              onDownload:
                  widget.store.canDownload &&
                      widget.repository.supportsDownloads
                  ? (drama) => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => DetailScreen(
                          drama: drama,
                          repository: widget.repository,
                          store: widget.store,
                          downloadOnOpen: true,
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ),
        if (!history && _hasMore)
          TextButton(
            onPressed: _loading || _busy ? null : () => _load(more: true),
            child: const Text('加载更多追剧'),
          ),
      ],
    );
  }

  Widget _account() {
    final phase = _status['phase'], retry = intValue(_status['retryAfter']);
    if (_logged) {
      final p = _status['profile'] as Map;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: AccountAvatar(url: '${p['avatarUrl'] ?? ''}'),
          ),
          const SizedBox(height: 12),
          Text(
            p['name'] as String? ?? '用户',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text('${p['phone'] ?? ''} · 红果号 ${p['publicId'] ?? p['uid']}'),
          if ((_status['profileError'] as String? ?? '').isNotEmpty)
            Text('资料更新暂未完成：${_status['profileError']}'),
          const SizedBox(height: 16),
          ValueListenableBuilder<String>(
            valueListenable: widget.repository.accountSyncMessage,
            builder: (context, message, _) =>
                Text(message.isEmpty ? '观看历史自动同步已开启' : message),
          ),
          Text('待上传 ${intValue(_status['pending'])} 条进度'),
          Text(
            '最近同步：${(DateTime.tryParse('${_status['lastSync']}')?.year ?? 0) >= 2000 ? DateTime.parse('${_status['lastSync']}').toLocal().toString() : '尚未同步'}',
          ),
          if ((_status['syncError'] as String? ?? '').isNotEmpty)
            Text(
              _status['syncError'] as String,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _busy ? null : _logout,
            child: const Text('退出账号'),
          ),
          const Text(
            '观看历史全自动同步。每集播完、切集或退出播放时自动上传，登录前的本机历史自动补传；未成功的记录保留并自动重试。删除本机记录不会删除云端历史。',
          ),
        ],
      );
    }
    if (phase == 'mfa') {
      final verified = _status['verificationState'] == 'verified';
      final remaining =
          _verificationDeadline
              ?.difference(DateTime.now())
              .inSeconds
              .clamp(0, 90) ??
          0;
      final feedback = _checkingSMS
          ? verified
                ? '短信验证已通过，正在自动完成登录…'
                : _busy
                ? _verificationChecks == 0
                      ? '正在准备检查短信验证状态…'
                      : '正在进行第 $_verificationChecks 次检查，验证通过后会自动登录…'
                : '等待红果确认短信，3 秒后自动检查。本轮剩余 $remaining 秒。'
          : verified
          ? '短信验证已通过，可直接重试完成登录，无需重新发送短信。'
          : '检查已暂停，可在本页继续检查。';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(verified ? '短信验证已通过' : '账号需要短信验证'),
          if (!verified) ...[
            const SizedBox(height: 8),
            const Text('请用登录手机号向以下号码发送本次指定的短信。发送后返回此页，将自动检查并完成登录。'),
            const SizedBox(height: 8),
            SelectableText(
              '号码：${_status['smsNumber'] ?? ''}\n内容：${_status['smsContent'] ?? ''}',
            ),
          ],
          const SizedBox(height: 16),
          Semantics(liveRegion: true, child: Text(feedback)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy || _checkingSMS ? null : _checkSMS,
            child: Text(
              _checkingSMS
                  ? verified
                        ? '正在完成登录…'
                        : '自动检查中…'
                  : verified
                  ? '重试完成登录'
                  : '继续检查',
            ),
          ),
          TextButton(onPressed: _cancel, child: const Text('取消登录')),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '账号登录',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text('使用中国大陆手机号和短信验证码。官方会话与当前本地用户独立绑定。'),
        const SizedBox(height: 16),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          maxLength: 11,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          enabled: !_busy && retry == 0,
          autofillHints: const [AutofillHints.telephoneNumber],
          decoration: const InputDecoration(
            labelText: '手机号',
            prefixText: '+86 ',
          ),
        ),
        OutlinedButton(
          onPressed: _busy || retry > 0 ? null : _send,
          child: Text(retry > 0 ? '$retry 秒后可重试' : '获取验证码'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          maxLength: 8,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          enableSuggestions: false,
          autofillHints: const [AutofillHints.oneTimeCode],
          onSubmitted: (_) {
            if (!_busy) unawaited(_login());
          },
          decoration: const InputDecoration(labelText: '短信验证码'),
        ),
        FilledButton(
          onPressed: _busy || phase != 'code' ? null : _login,
          child: const Text('登录'),
        ),
        if (phase == 'code' || _busy)
          TextButton(onPressed: _cancel, child: const Text('取消登录 / 换手机号')),
      ],
    );
  }

  Map<String, dynamic> _reservationRow(Drama drama) =>
      _items.firstWhere((row) => (row['drama'] as Map?)?['id'] == drama.id);

  String _reservationDate(Drama drama) {
    final row = _reservationRow(drama);
    final date = (row['publishText'] as String? ?? '').trim();
    return date.isNotEmpty
        ? date
        : drama.onlineDate.isNotEmpty
        ? drama.onlineDate
        : '上线时间待公布';
  }

  Future<void> _manageReservation(Drama drama) async {
    final row = _reservationRow(drama);
    final date = _reservationDate(drama);
    final owner = _uid;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(drama.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(date),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy || _loading
                    ? null
                    : () => Navigator.pop(context, true),
                child: Text(row['reserved'] == true ? '取消预约' : '预约'),
              ),
            ],
          ),
        ),
      ),
    );
    if (accepted == true && _active && owner == _uid) await _reserve(row);
  }

  Future<void> _openReservation(Drama drama) async {
    if (_reservationRow(drama)['upcoming'] != false) {
      await _manageReservation(drama);
      return;
    }
    await openPlaybackDirectly(
      context,
      drama: drama,
      repository: widget.repository,
      store: widget.store,
    );
    if (_active) await _load();
  }

  Widget _reservationList() {
    final calendar = _tabs.index == 3;
    final rows = _items.where(
      (row) =>
          !calendar ||
          _calendarFilter.isEmpty ||
          (row['reserved'] == true) == (_calendarFilter == 'reserved'),
    );
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 &&
            notification.metrics.axis == Axis.vertical &&
            notification.metrics.pixels > 0 &&
            notification.metrics.extentAfter < 350 &&
            _hasMore &&
            !_loading &&
            !_busy &&
            !_reservationLoadScheduled) {
          _reservationLoadScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _reservationLoadScheduled = false;
            if (_active &&
                _tabs.index >= 2 &&
                _hasMore &&
                !_loading &&
                !_busy) {
              unawaited(_load(more: true));
            }
          });
        }
        return false;
      },
      child: SavedLibrary(
        key: ValueKey('reservation-library-${_tabs.index}'),
        repository: widget.repository,
        store: widget.store,
        history: false,
        compact: true,
        searchVisible: widget.embedded ? _librarySearching : null,
        filterOptions: calendar
            ? const [('', '全部'), ('reserved', '已预约'), ('unreserved', '未预约')]
            : const [('upcoming', '待上线'), ('online', '已上线')],
        filterValue: calendar ? _calendarFilter : _reservationMode,
        onFilterChanged: (value) {
          if (_busy || _loading) return;
          if (calendar) {
            setState(() => _calendarFilter = value);
          } else if (value != _reservationMode) {
            setState(() {
              _reservationMode = value;
              _items.clear();
            });
            unawaited(_load());
          }
        },
        remoteFavorites: [
          for (final row in rows)
            Drama.fromJson(Map<String, dynamic>.from(row['drama'] as Map)),
        ],
        subtitle: _reservationDate,
        onOpen: _openReservation,
        onContinue: _openReservation,
        onManage: _manageReservation,
        hasMore: _hasMore,
        loadingMore: _loading && _items.isNotEmpty,
        onLoadMore: () {
          if (!_busy && !_loading) unawaited(_load(more: true));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: !_active
            ? const Center(child: Text('本地用户已变更，请返回后重新打开。'))
            : AnimatedBuilder(
                animation: _tabs,
                builder: (context, _) => Column(
                  children: [
                    if (_busy || _loading) const LinearProgressIndicator(),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_message!),
                      ),
                    Expanded(
                      child: !widget.collections
                          ? ListView(
                              padding: const EdgeInsets.all(20),
                              children: [_account()],
                            )
                          : _tabs.index <= 1
                          ? _savedCollections()
                          : !_logged
                          ? Center(
                              child: FilledButton(
                                onPressed: _openAccount,
                                child: const Text('登录账号查看预约'),
                              ),
                            )
                          : Column(
                              children: [
                                if (widget.drama != null && _tabs.index == 2)
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      Text(widget.drama!.title),
                                      TextButton(
                                        onPressed: _busy || _loading
                                            ? null
                                            : () => _reserve({
                                                'id':
                                                    widget
                                                        .drama!
                                                        .sourceId
                                                        .isEmpty
                                                    ? widget.drama!.id
                                                          .split(':')
                                                          .last
                                                    : widget.drama!.sourceId,
                                                'reserved': false,
                                              }),
                                        child: const Text('预约本剧'),
                                      ),
                                      TextButton(
                                        onPressed: _busy || _loading
                                            ? null
                                            : () => _reserve({
                                                'id':
                                                    widget
                                                        .drama!
                                                        .sourceId
                                                        .isEmpty
                                                    ? widget.drama!.id
                                                          .split(':')
                                                          .last
                                                    : widget.drama!.sourceId,
                                                'reserved': true,
                                              }),
                                        child: const Text('取消本剧预约'),
                                      ),
                                    ],
                                  ),
                                Expanded(
                                  child: RefreshIndicator(
                                    onRefresh: _load,
                                    child: _reservationList(),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
      ),
    );
    final tabs = TabBar(
      controller: _tabs,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      dividerColor: widget.embedded ? Colors.transparent : null,
      indicator: widget.embedded ? const BoxDecoration() : null,
      labelColor: widget.embedded
          ? Theme.of(context).colorScheme.onSurface
          : null,
      unselectedLabelColor: widget.embedded
          ? Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: .7)
          : null,
      labelStyle: widget.embedded
          ? const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)
          : null,
      unselectedLabelStyle: widget.embedded
          ? const TextStyle(fontSize: 17, fontWeight: FontWeight.w400)
          : null,
      labelPadding: widget.embedded
          ? const EdgeInsets.symmetric(horizontal: 10)
          : null,
      tabs: const [
        Tab(text: '追剧'),
        Tab(text: '历史'),
        Tab(text: '预约'),
        Tab(text: '上新预约'),
      ],
    );
    if (widget.embedded) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
            child: Row(
              children: [
                Expanded(child: tabs),
                IconButton(
                  tooltip: '搜索片单',
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  icon: Icon(
                    _librarySearching
                        ? Icons.close_rounded
                        : Icons.search_rounded,
                    size: 22,
                  ),
                  onPressed: () =>
                      setState(() => _librarySearching = !_librarySearching),
                ),
              ],
            ),
          ),
          Expanded(child: content),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.collections ? '我的片单' : '账号与同步'),
        bottom: widget.collections ? tabs : null,
      ),
      body: content,
    );
  }
}
