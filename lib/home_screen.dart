import 'package:flutter/material.dart';

import 'app_layout.dart';
import 'app_bottom_navigation.dart';
import 'core_bridge.dart';
import 'local_store.dart';
import 'my_screen.dart';
import 'rankings_screen.dart';
import 'recommendations_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository, required this.store});
  final AppRepository repository;
  final LocalStore store;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _homeTab = 0;
  static const _rankingsTab = 1;
  static const _searchTab = 2;
  static const _myTab = 3;
  int _tab = _homeTab;
  final _visitedTabs = <int>{_homeTab};
  final _tabHistory = <int>[_homeTab];
  final _selection = ValueNotifier<bool>(false);
  Widget? _backgroundCache;

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  void _changeTab(int tab) {
    if (tab == _tab) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _selection.value = false;
    setState(() {
      _tab = tab;
      _visitedTabs.add(tab);
      _tabHistory.add(tab);
    });
  }

  void _back() {
    if (_tabHistory.length < 2) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _tabHistory.removeLast();
      _tab = _tabHistory.last;
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.store, _selection]),
    builder: (context, _) {
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent && _backgroundCache != null) {
        return _backgroundCache!;
      }
      final child = LayoutBuilder(
        builder: (context, constraints) {
          final selecting = _selection.value;
          final television = AppLayout.isTelevision(context);
          final desktop = constraints.maxWidth >= 840;
          final appearance = widget.store.themeAppearance;
          final blurredBars = appearance.blurBars && !desktop && !television;
          final floatingBar = appearance.floatingBar && !desktop && !television;
          final pages = <Widget>[
            RecommendationsScreen(
              key: ValueKey('recommendations-${widget.store.profileEpoch}'),
              repository: widget.repository,
              store: widget.store,
              embedded: true,
              active: _tab == _homeTab,
            ),
            if (_visitedTabs.contains(_rankingsTab))
              RankingsScreen(
                key: ValueKey('rankings-${widget.store.profileEpoch}'),
                repository: widget.repository,
                store: widget.store,
                embedded: true,
                active: _tab == _rankingsTab,
              )
            else
              const SizedBox.shrink(),
            SearchScreen(
              key: ValueKey('search-${widget.store.profileEpoch}'),
              repository: widget.repository,
              store: widget.store,
              embedded: true,
              active: _tab == _searchTab,
              selectionMode: _selection,
            ),
            if (_visitedTabs.contains(_myTab))
              MyScreen(
                key: ValueKey('my-${widget.store.profileEpoch}'),
                repository: widget.repository,
                store: widget.store,
                active: _tab == _myTab,
                onRankings: () => _changeTab(_rankingsTab),
              )
            else
              const SizedBox.shrink(),
          ];
          final content = IndexedStack(
            index: _tab,
            children: [
              for (var index = 0; index < pages.length; index++)
                TickerMode(
                  enabled: _tab == index,
                  child: ExcludeFocus(
                    excluding: _tab != index,
                    child: pages[index],
                  ),
                ),
            ],
          );
          final scaffold = Scaffold(
            extendBody: floatingBar || blurredBars,
            body: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  if (desktop || television) ...[
                    NavigationRail(
                      selectedIndex: _tab,
                      onDestinationSelected: _changeTab,
                      labelType: NavigationRailLabelType.all,
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.explore_outlined),
                          selectedIcon: Icon(Icons.explore),
                          label: Text('首页'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.leaderboard_outlined),
                          selectedIcon: Icon(Icons.leaderboard_rounded),
                          label: Text('排行榜'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.search_rounded),
                          label: Text('搜索'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.person_outline_rounded),
                          selectedIcon: Icon(Icons.person_rounded),
                          label: Text('我的'),
                        ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                  ],
                  Expanded(child: content),
                ],
              ),
            ),
            bottomNavigationBar: desktop || television || selecting
                ? null
                : AppBottomNavigation(
                    selectedIndex: _tab,
                    onDestinationSelected: _changeTab,
                    floating: floatingBar,
                    blurred: blurredBars,
                    liquidGlass: floatingBar && appearance.liquidGlass,
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.explore_outlined),
                        selectedIcon: Icon(Icons.explore),
                        label: '首页',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.leaderboard_outlined),
                        selectedIcon: Icon(Icons.leaderboard_rounded),
                        label: '排行榜',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.search_rounded),
                        label: '搜索',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.person_outline_rounded),
                        selectedIcon: Icon(Icons.person_rounded),
                        label: '我的',
                      ),
                    ],
                  ),
          );
          return PopScope<void>(
            canPop: _tabHistory.length == 1 && !selecting,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop &&
                  !selecting &&
                  ModalRoute.of(context)?.isCurrent != false) {
                _back();
              }
            },
            child: scaffold,
          );
        },
      );
      _backgroundCache = child;
      return child;
    },
  );
}
