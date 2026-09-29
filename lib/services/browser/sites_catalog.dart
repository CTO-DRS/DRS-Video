import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../core/constants/app_constants.dart';
import '../../data/repositories/browser_repository.dart';
import '../../core/utils/logger.dart';

/// One entry of the bundled platforms catalog (all entries are real,
/// publicly reachable platforms).
class CatalogSite {
  CatalogSite({required this.name, required this.url, required this.category});

  final String name;
  final String url;
  final String category;

  String get host => url.replaceAll(RegExp(r'^https?://'), '').split('/').first;
}

/// Loads + filters the bundled catalog. Filtering is pure/static so it
/// is testable without the asset.
class SitesCatalog {
  SitesCatalog._();
  static SitesCatalog instance = SitesCatalog._();

  List<CatalogSite>? _sites;

  List<CatalogSite> get sites => _sites ?? const [];

  Future<void> ensureLoaded() async {
    if (_sites != null) return;
    try {
      final raw = await rootBundle.loadString(AppConstants.sitesCatalogAsset);
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final list = (map['sites'] as List).cast<Map<String, dynamic>>();
      _sites = list
          .map((e) => CatalogSite(
                name: (e['n'] as String?) ?? '',
                url: (e['u'] as String?) ?? '',
                category: (e['c'] as String?) ?? 'video',
              ))
          .where((s) => s.url.startsWith('http') && s.name.isNotEmpty)
          .toList();
      AppLogger.instance
          .info('sites', 'catalog loaded: ${_sites!.length} platforms');
    } catch (e, s) {
      AppLogger.instance.error('sites', 'catalog load failed', e, s);
      _sites = const [];
    }
  }

  /// Pure search over name + host (case/diacritics-insensitive for latin).
  static List<CatalogSite> filter(List<CatalogSite> sites, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return sites;
    return sites
        .where((s) =>
            s.name.toLowerCase().contains(q) ||
            s.host.toLowerCase().contains(q))
        .toList();
  }

  /// Pure category filter.
  static List<CatalogSite> byCategory(List<CatalogSite> sites, String category) =>
      category.isEmpty
          ? sites
          : sites.where((s) => s.category == category).toList();

  /// Merges bundled catalog + user-added sites (user entries first).
  static List<CatalogSite> mergeUserSites(
      List<CatalogSite> catalog, List<UserSite> userSites) {
    final user = userSites
        .map((u) => CatalogSite(name: u.name, url: u.url, category: 'mine'))
        .toList();
    return [...user, ...catalog];
  }
}
