/// 词根词缀数据仓库
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../domain/affix.dart';

class AffixRepository {
  List<Affix> _all = const [];

  bool get isLoaded => _all.isNotEmpty;
  List<Affix> get all => _all;

  int countOf(AffixType type) => _all.where((a) => a.type == type).length;

  List<Affix> byType(AffixType? type) =>
      type == null ? _all : _all.where((a) => a.type == type).toList();

  Future<void> load() async {
    if (isLoaded) return;
    final raw = await rootBundle.loadString('assets/data/affixes.json');
    _all = (jsonDecode(raw) as List)
        .map((e) => Affix.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// 按形式、含义、示例词搜索
  List<Affix> search(String query, {AffixType? type}) {
    final pool = byType(type);
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return pool;
    return pool.where((a) {
      return a.form.toLowerCase().contains(q) ||
          a.meaning.contains(q) ||
          a.examples.any((e) => e.toLowerCase().contains(q));
    }).toList();
  }
}
