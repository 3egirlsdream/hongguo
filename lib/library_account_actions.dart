import 'package:flutter/material.dart';

import 'core_bridge.dart';
import 'follow_state.dart';
import 'local_store.dart';
import 'models.dart';

final _followingRequests = <String>{};

Future<void> updateLibraryFollowing(
  BuildContext context,
  AppRepository repository,
  LocalStore store,
  Drama drama, {
  FollowStatus? status,
}) async {
  if (!store.allowsSource(drama.source)) return;
  final epoch = store.profileEpoch;
  final key = '${identityHashCode(store)}:$epoch:${drama.id}';
  if (!_followingRequests.add(key)) return;
  try {
    Map<String, dynamic>? account;
    if (repository.supportsOfficialAccount) {
      account = await repository.hongguoAccount('status');
      if (account['loggedIn'] == true && !repository.accountFavoritesLoaded) {
        await repository.hongguoAccount('favorites', {
          'uid': (account['profile'] as Map)['uid'],
        });
      }
    }
    if (epoch != store.profileEpoch || store.locked || !context.mounted) return;
    final desired =
        status != null ||
        !(store.isFavorite(drama.id) || repository.isAccountFavorite(drama.id));
    if (account?['loggedIn'] == true) {
      final id = drama.sourceId.isEmpty
          ? drama.id.split(':').last
          : drama.sourceId;
      await repository.hongguoAccount('favorite', {
        'uid': (account!['profile'] as Map)['uid'],
        'id': id,
        'followed': desired,
      });
    }
    if (epoch != store.profileEpoch || store.locked) return;
    if (status != null) {
      await store.setFollowStatus(drama, status);
    } else if (store.isFavorite(drama.id) != desired) {
      await store.toggleFavorite(drama);
    }
  } catch (error) {
    if (context.mounted && epoch == store.profileEpoch)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('追剧更新失败：$error')));
  } finally {
    _followingRequests.remove(key);
  }
}
