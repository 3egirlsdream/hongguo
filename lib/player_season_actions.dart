import 'dart:async';

import 'package:flutter/material.dart';

import 'core_bridge.dart';
import 'hongguo_account_screen.dart';
import 'local_store.dart';
import 'models.dart';

class PlayerSeasonActions extends StatefulWidget {
  const PlayerSeasonActions({
    super.key,
    required this.season,
    required this.repository,
    required this.store,
    required this.onPlay,
    this.opening = false,
    this.label = '下一季',
    this.bottomInset = true,
  });
  final DramaSeason season;
  final AppRepository repository;
  final LocalStore store;
  final Future<void> Function() onPlay;
  final bool opening;
  final String label;
  final bool bottomInset;

  @override
  State<PlayerSeasonActions> createState() => _PlayerSeasonActionsState();
}

class _PlayerSeasonActionsState extends State<PlayerSeasonActions> {
  bool _busy = false;
  bool? _reserved;
  String _uid = '';
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.repository.accountStatus.addListener(_accountChanged);
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(PlayerSeasonActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.season.drama.id != oldWidget.season.drama.id) {
      _reserved = null;
      unawaited(_refresh());
    }
  }

  void _accountChanged() {
    unawaited(_refresh());
  }

  bool _current(int generation, int epoch) =>
      mounted &&
      generation == _generation &&
      epoch == widget.store.profileEpoch;

  Future<void> _refresh() async {
    final generation = ++_generation;
    final epoch = widget.store.profileEpoch;
    if (!widget.repository.supportsOfficialAccount || !widget.season.reservable)
      return;
    try {
      var status = widget.repository.accountStatus.value;
      if (status.isEmpty)
        status = await widget.repository.hongguoAccount('status');
      if (!_current(generation, epoch)) return;
      final uid = (status['profile'] as Map?)?['uid'] as String? ?? '';
      setState(() {
        _uid = uid;
        _reserved = null;
      });
      if (uid.isEmpty) return;
      var offset = 0;
      var cursor = '';
      for (var page = 0; page < 100; page++) {
        final result = await widget.repository.hongguoAccount('reservations', {
          'uid': uid,
          'mode': widget.season.playable ? 'online' : 'upcoming',
          'offset': offset,
          'cursor': cursor,
        });
        if (!_current(generation, epoch) || _uid != uid) return;
        final rows = result['items'] as List? ?? const [];
        if (rows.any(
          (row) =>
              (row as Map)['id'].toString() == widget.season.drama.sourceId,
        )) {
          setState(() => _reserved = true);
          return;
        }
        if (result['hasMore'] != true) {
          setState(() => _reserved = false);
          return;
        }
        final next = intValue(result['offset']);
        final nextCursor = result['cursor'] as String? ?? '';
        if (next <= offset && nextCursor == cursor) return;
        offset = next;
        cursor = nextCursor;
      }
    } catch (_) {}
  }

  Future<void> _reserve() async {
    if (_busy) return;
    if (_uid.isEmpty || _reserved == null) {
      setState(() => _busy = true);
      try {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => HongguoAccountScreen(
              repository: widget.repository,
              store: widget.store,
              initialTab: 2,
              drama: widget.season.drama,
            ),
          ),
        );
        if (mounted) await _refresh();
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    final epoch = widget.store.profileEpoch;
    final uid = _uid;
    final desired = _reserved != true;
    setState(() => _busy = true);
    try {
      final result = await widget.repository.hongguoAccount('reserve', {
        'uid': uid,
        'id': widget.season.drama.sourceId,
        'reserved': desired,
      });
      if (!mounted || epoch != widget.store.profileEpoch || uid != _uid) return;
      if (result['confirmed'] != true || result['reserved'] != desired) {
        throw AppFailure('预约状态尚未确认，请刷新后重试');
      }
      setState(() => _reserved = desired);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(desired ? '已确认预约下一季' : '已确认取消预约')));
    } catch (error) {
      if (mounted && epoch == widget.store.profileEpoch) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.repository.accountStatus.removeListener(_accountChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final season = widget.season;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        bottom: widget.bottomInset,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.label} · ${season.drama.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!season.playable || season.publishText.isNotEmpty)
                      Text(
                        season.publishText.isEmpty
                            ? '上线时间待公布'
                            : season.publishText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (season.reservable &&
                  widget.repository.supportsOfficialAccount)
                TextButton.icon(
                  onPressed: _busy ? null : _reserve,
                  icon: Icon(
                    _reserved == true
                        ? Icons.notifications_active_outlined
                        : Icons.notification_add_outlined,
                    size: 18,
                  ),
                  label: Text(
                    _busy
                        ? '提交中'
                        : _reserved == true
                        ? '取消预约'
                        : '预约',
                  ),
                ),
              if (season.playable)
                FilledButton(
                  onPressed: widget.opening ? null : widget.onPlay,
                  child: Text(widget.opening ? '正在打开' : '播放下一季'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
