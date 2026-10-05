import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/opportunity_entity.dart';

/// Local-only persistence. Opportunities live in SharedPreferences as JSON;
/// nothing leaves the device. Platform storage is via shared_preferences on
/// web (localStorage) and Android (SharedPreferences).
class OpportunityRepository {
  OpportunityRepository({required this.prefs});

  final SharedPreferences prefs;

  static const _storageKey = 'opportunities.v1';
  static const _maxOpportunities = 500;

  List<Opportunity> _cache = const [];
  bool _loaded = false;

  Future<List<Opportunity>> loadAll() async {
    if (!_loaded) {
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw) as List;
          _cache = decoded
              .map(
                (e) => Opportunity.fromJson((e as Map).cast<String, dynamic>()),
              )
              .toList();
        } on FormatException {
          _cache = const [];
        }
      }
      _loaded = true;
    }
    return List.unmodifiable(_sortedList());
  }

  Future<void> save(Opportunity opportunity) async {
    await loadAll();
    final index = _cache.indexWhere((o) => o.id == opportunity.id);
    if (index >= 0) {
      _cache[index] = opportunity;
    } else {
      _cache = [opportunity, ..._cache];
      if (_cache.length > _maxOpportunities) {
        _cache = _cache.sublist(0, _maxOpportunities);
      }
    }
    await _persist();
  }

  Future<void> delete(String id) async {
    await loadAll();
    _cache = _cache.where((o) => o.id != id).toList();
    await _persist();
  }

  Future<void> _persist() async {
    final encoded = jsonEncode(_sortedList().map((o) => o.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }

  List<Opportunity> _sortedList() {
    final list = [..._cache];
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }
}
