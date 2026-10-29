import 'package:flutter/material.dart';

import 'data/tour_repository.dart';
import 'logic/favorites_controller.dart';
import 'logic/notifier_scope.dart';
import 'logic/search_filter_controller.dart';
import 'logic/tour_catalog.dart';
import 'screens/home_shell.dart';
import 'theme/app_theme.dart';

class TourExplorerApp extends StatefulWidget {
  const TourExplorerApp({super.key, this.repository = const TourRepository()});

  final TourRepository repository;

  @override
  State<TourExplorerApp> createState() => _TourExplorerAppState();
}

class _TourExplorerAppState extends State<TourExplorerApp> {
  late final _catalog = TourCatalog(widget.repository)..load();
  final _favorites = FavoritesController();
  final _searchFilter = SearchFilterController();

  @override
  void dispose() {
    _catalog.dispose();
    _favorites.dispose();
    _searchFilter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The state sits above MaterialApp so pushed routes, sheets and dialogs
    // all see the same catalog, favorites and search.
    return NotifierScope<TourCatalog>(
      notifier: _catalog,
      child: NotifierScope<FavoritesController>(
        notifier: _favorites,
        child: NotifierScope<SearchFilterController>(
          notifier: _searchFilter,
          child: MaterialApp(
            title: 'Tour Explorer',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            home: const HomeShell(),
          ),
        ),
      ),
    );
  }
}
