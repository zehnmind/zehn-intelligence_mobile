import 'package:flutter/material.dart';

import '../logic/notifier_scope.dart';
import '../logic/search_filter_controller.dart';
import '../logic/tour_filter.dart';
import '../models/destination.dart';
import 'explore_screen.dart';
import 'favorites_screen.dart';
import 'search_screen.dart';

/// Bottom navigation between Explore, Search and Favorites. The tabs stay
/// alive while hidden, so scroll positions and the search survive switching.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _exploreTab = 0;
  static const _searchTab = 1;

  int _index = _exploreTab;
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  SearchFilterController get _searchFilter =>
      NotifierScope.read<SearchFilterController>(context);

  void _selectTab(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _index = index);
  }

  void _openSearch({bool focusField = false}) {
    _selectTab(_searchTab);
    if (focusField) {
      // The field can only take focus once its tab is visible.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  void _showAllTours() {
    _searchFilter.reset();
    _openSearch();
  }

  void _showDestination(Destination destination) {
    _searchFilter.update(TourFilter(destination: destination));
    _openSearch();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back from another tab returns to Explore instead of leaving the app.
      canPop: _index == _exploreTab,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _selectTab(_exploreTab);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            ExploreScreen(
              onSearchTap: () => _openSearch(focusField: true),
              onDestinationTap: _showDestination,
              onSeeAllTap: _showAllTours,
            ),
            SearchScreen(focusNode: _searchFocus),
            FavoritesScreen(onExploreTap: () => _selectTab(_exploreTab)),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _selectTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore_rounded),
              label: 'Explore',
            ),
            NavigationDestination(
              icon: Icon(Icons.search_rounded),
              label: 'Search',
            ),
            NavigationDestination(
              icon: _FavoritesIcon(selected: false),
              selectedIcon: _FavoritesIcon(selected: true),
              label: 'Favorites',
            ),
          ],
        ),
      ),
    );
  }
}

/// Heart with a badge counting the saved tours.
class _FavoritesIcon extends StatelessWidget {
  const _FavoritesIcon({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final count = context.favorites.count;
    return Badge.count(
      count: count,
      isLabelVisible: count > 0,
      child: Icon(
        selected ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      ),
    );
  }
}
