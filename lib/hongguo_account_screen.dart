import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core_bridge.dart';
import 'local_store.dart';
import 'models.dart';
import 'hongguo_account_models.dart';
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
  });
  final AppRepository repository;
  final LocalStore store;
  final Drama? drama;
  final bool collections;
  final int initialTab;
  @override
  State<HongguoAccountScreen> createState() => _HongguoAccountScreenState();
}

class _HongguoAccountScreenState extends State<HongguoAccountScreen>
    with SingleTickerProviderStateMixin {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _scroll = ScrollController();
  late final TabController _tabs;
  late final int _epoch;
  Timer? _clock;
  Timer? _verification;
  Map<String, dynamic> _status = {};
  final List<Map<String, dynamic>> _items = [];
  List<WatchEntry> _accountHistory = const [];
  bool _busy = false, _loading = false, _hasMore = false;
  int _offset = 0, _revision = 0;
  int? _subscribeOffset;
  bool _statusLoading = false;
  int _selectedTab = 0;
  String _cursor = '';
  String _reservationMode = 'upcoming';
  String? _error, _message;
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
    _scroll.addListener(_loadNearEnd);
    widget.store.addListener(_accessChanged);
    widget.repository.accountFavorites.addListener(_favoritesChanged);
    _refreshStatus();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_active && !_busy && !_loading && _tabs.index == 0) _refreshStatus();
    });
  }

  void _favoritesChanged() {
    if (_active &&
        widget.collections &&
        _tabs.index == 0 &&
        _logged &&
        !_loading &&
        !_busy &&
        !_statusLoading)
      unawaited(_load());
  }

  void _accessChanged() {
    if (!_active) {
      _verification?.cancel();
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

  void _loadNearEnd() {
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < 350 &&
        _hasMore &&
        !_loading) {
      _load(more: true);
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _verification?.cancel();
    _tabs.dispose();
    _scroll.dispose();
    _phone.dispose();
    _code.dispose();
    widget.store.removeListener(_accessChanged);
    widget.repository.accountFavorites.removeListener(_favoritesChanged);
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    if (!_active ||
        _statusLoading ||
        !widget.repository.supportsOfficialAccount) {
      return;
    }
    _statusLoading = true;
    try {
      final result = await widget.repository.hongguoAccount('status');
      if (_active) {
        final wasLogged = _logged;
        final previousUID = _uid;
        final previousSync = _status['lastSync'];
        setState(() {
          _status = result;
          if (previousUID != _uid) {
            _revision++;
            _items.clear();
            _accountHistory = const [];
            _error = null;
            _hasMore = false;
          }
        });
        if (_logged &&
            widget.collections &&
            (previousUID != _uid || previousSync != _status['lastSync']))
          await _readHistory();
        if (!wasLogged && _logged && widget.collections) unawaited(_load());
      }
    } catch (error) {
      if (_active) setState(() => _error = error.toString());
    } finally {
      _statusLoading = false;
    }
  }

  Future<bool> _run(
    String command, [
    Map<String, dynamic> input = const {},
  ]) async {
    if (!_active || _busy || _loading) return false;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await widget.repository.hongguoAccount(command, input);
      if (!_active) return false;
      setState(() {
        if (result.containsKey('loggedIn')) _status = result;
      });
      return true;
    } catch (error) {
      if (_active) setState(() => _error = error.toString());
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
        _code.clear();
        _phone.clear();
        await _sync();
      }
    } else {
      await _refreshStatus();
    }
  }

  Future<void> _checkSMS() async {
    _verification?.cancel();
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    Future<void> poll() async {
      if (!_active || DateTime.now().isAfter(deadline)) {
        _verification?.cancel();
        if (_active) setState(() => _message = '本轮验证等待已结束，可再次检查或取消登录。');
        return;
      }
      if (_busy) return;
      final okay = await _run('verifySMS');
      if (!okay) {
        _verification?.cancel();
        return;
      }
      if (_logged) {
        _verification?.cancel();
        _code.clear();
        _phone.clear();
        await _sync();
      }
    }

    await poll();
    if (_active && !_logged && _error == null) {
      _verification = Timer.periodic(const Duration(seconds: 3), (_) => poll());
    }
  }

  Future<void> _cancel() async {
    if (!_active) return;
    _verification?.cancel();
    if (await widget.repository
        .hongguoAccount('cancel')
        .then((value) {
          if (_active) setState(() => _status = value);
          return true;
        })
        .catchError((Object error) {
          if (_active) setState(() => _error = error.toString());
          return false;
        })) {
      _code.clear();
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
      _verification?.cancel();
      _code.clear();
      _tabs.index = 0;
    }
  }

  Future<void> _sync() async {
    if (await _run('sync', {'uid': _uid})) {
      if (_active) setState(() => _message = '观看历史同步完成');
      try {
        await widget.repository.hongguoAccount('favorites', {'uid': _uid});
      } catch (error) {
        if (_active) setState(() => _error = '追剧同步暂未完成：$error');
      }
      if (widget.collections) {
        await _readHistory();
        await _load();
      }
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
        _items.clear();
        _offset = 0;
        _cursor = '';
        _subscribeOffset = null;
        _hasMore = false;
      }
    });
    try {
      final command = tab == 0
          ? 'favorites'
          : tab == 1
          ? 'history'
          : tab == 2 || tab == 0
          ? 'reservations'
          : 'calendar';
      final result = await widget.repository.hongguoAccount(command, {
        'uid': owner,
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
        if ((result['warning'] as String? ?? '').isNotEmpty)
          _error = result['warning'] as String;
        if (tab == 1)
          _accountHistory = [for (final row in rows) WatchEntry.fromJson(row)];
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

  Future<void> _uploadLocal() async {
    final rows = widget.store.history
        .where((entry) => entry.drama.source == 'hongguo')
        .toList();
    final uid = _uid;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('上传本机历史？'),
        content: Text('将本地用户的 ${rows.length} 条观看记录加入当前账号的同步队列，保留双方时间较新的进度。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('上传'),
          ),
        ],
      ),
    );
    if (accepted != true || !_active) return;
    if (_busy || _loading) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    var added = 0;
    try {
      for (final row in rows) {
        if (!_active || _uid != uid) return;
        final detail = await widget.repository.detail(row.drama);
        final ep = detail.episodes
            .where((ep) => ep.number == row.episode)
            .firstOrNull;
        if (ep == null) {
          throw AppFailure(
            '剧集 ${row.drama.title} 暂未返回第 ${row.episode} 集，已加入的记录保留在队列',
          );
        }
        final id = hongguoEpisodeID(ep);
        await widget.repository.hongguoAccount('queueProgress', {
          'uid': uid,
          'watch': {...row.toJson(), 'videoId': id},
        });
        added++;
      }
      if (_active) setState(() => _message = '已加入 $added 条历史，正在同步');
    } catch (error) {
      if (_active) setState(() => _error = '已加入 $added 条记录。$error');
    } finally {
      if (_active) setState(() => _busy = false);
    }
    if (_active && _uid == uid) {
      final failure = _error;
      await _sync();
      if (_active && failure != null) setState(() => _error = failure);
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
      if (_active && owner == _uid) setState(() => _accountHistory = rows);
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(child: Text(_logged ? '本机与账号记录合并显示' : '登录后可同步账号记录')),
              TextButton(
                onPressed: _busy || _loading
                    ? null
                    : !_logged
                    ? _openAccount
                    : history
                    ? _sync
                    : _load,
                child: Text(
                  !_logged
                      ? '登录'
                      : history
                      ? '同步'
                      : '刷新',
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SavedLibrary(
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
            onHistoryContinue: (entry) => openPlaybackDirectly(
              context,
              drama: entry.drama,
              repository: widget.repository,
              store: widget.store,
              resumeOverride: entry,
            ),
            onOpen: (drama) => openPlaybackDirectly(
              context,
              drama: drama,
              repository: widget.repository,
              store: widget.store,
            ),
            onContinue: (drama) => openPlaybackDirectly(
              context,
              drama: drama,
              repository: widget.repository,
              store: widget.store,
            ),
            onDownload:
                widget.store.canDownload && widget.repository.supportsDownloads
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
          Text(
            p['name'] as String? ?? '用户',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text('${p['phone'] ?? ''} · UID ${p['uid']}'),
          const SizedBox(height: 16),
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
          FilledButton.icon(
            onPressed: _busy ? null : _sync,
            icon: const Icon(Icons.sync),
            label: const Text('立即同步观看历史'),
          ),
          OutlinedButton(
            onPressed: _busy ? null : _uploadLocal,
            child: const Text('上传本机历史'),
          ),
          TextButton(
            onPressed: _busy ? null : _logout,
            child: const Text('退出账号'),
          ),
          const Text('播放时自动加入当前账号的进度队列。登录前的本机历史需手动上传；删除本机记录不会删除观看历史。'),
        ],
      );
    }
    if (phase == 'mfa') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('账号需要进一步验证'),
          const Text('请用登录手机号向以下号码发送本次指定的短信，然后检查验证结果。'),
          SelectableText(
            '号码：${_status['smsNumber'] ?? ''}\n内容：${_status['smsContent'] ?? ''}',
          ),
          FilledButton(
            onPressed: _busy ? null : _checkSMS,
            child: const Text('我已发送，检查验证'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.collections ? '我的片单' : '账号与同步'),
        bottom: !widget.collections
            ? null
            : TabBar(
                controller: _tabs,
                isScrollable: true,
                tabs: const [
                  Tab(text: '追剧'),
                  Tab(text: '历史'),
                  Tab(text: '预约'),
                  Tab(text: '上新预约'),
                ],
              ),
      ),
      body: Center(
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
                                  if (_tabs.index == 2)
                                    SegmentedButton<String>(
                                      segments: const [
                                        ButtonSegment(
                                          value: 'upcoming',
                                          label: Text('待上线'),
                                        ),
                                        ButtonSegment(
                                          value: 'online',
                                          label: Text('已上线'),
                                        ),
                                      ],
                                      selected: {_reservationMode},
                                      onSelectionChanged: _busy || _loading
                                          ? null
                                          : (value) {
                                              setState(
                                                () => _reservationMode =
                                                    value.single,
                                              );
                                              _load();
                                            },
                                    ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton.icon(
                                        onPressed: _loading || _busy
                                            ? null
                                            : _load,
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('刷新'),
                                      ),
                                    ],
                                  ),
                                  Expanded(
                                    child: RefreshIndicator(
                                      onRefresh: _load,
                                      child: ListView.builder(
                                        controller: _scroll,
                                        padding: const EdgeInsets.all(16),
                                        itemCount: _items.length + 1,
                                        itemBuilder: (context, index) {
                                          if (index == _items.length) {
                                            return Padding(
                                              padding: const EdgeInsets.all(24),
                                              child: Center(
                                                child: _hasMore
                                                    ? TextButton(
                                                        onPressed:
                                                            _loading || _busy
                                                            ? null
                                                            : () => _load(
                                                                more: true,
                                                              ),
                                                        child: const Text(
                                                          '加载更多',
                                                        ),
                                                      )
                                                    : Text(
                                                        _items.isEmpty
                                                            ? '暂无记录'
                                                            : '已显示全部',
                                                      ),
                                              ),
                                            );
                                          }
                                          final row = _items[index];
                                          final drama = Drama.fromJson(
                                            Map<String, dynamic>.from(
                                              row['drama'] as Map,
                                            ),
                                          );
                                          return Card(
                                            child: ListTile(
                                              leading: SizedBox(
                                                width: 48,
                                                height: 72,
                                                child: DramaCover(
                                                  drama: drama,
                                                  repository: widget.repository,
                                                ),
                                              ),
                                              title: Text(drama.title),
                                              subtitle: Text(
                                                row['publishText'] as String? ??
                                                    '',
                                              ),
                                              trailing: TextButton(
                                                onPressed: _busy || _loading
                                                    ? null
                                                    : () => _reserve(row),
                                                child: Text(
                                                  row['reserved'] == true
                                                      ? '取消预约'
                                                      : '预约',
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
