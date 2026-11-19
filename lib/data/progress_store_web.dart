/// Web 平台实现：localStorage 持久化
///
/// 存储键：
///   es_review_v1    -> { "word": {ease, interval, reps, lapses, due, updated_at} }
///   es_notes_v1     -> [ {id, word_key, content, created_at, updated_at, deleted} ]
///   es_favorites_v1 -> ["word", ...]
///   es_custom_v1    -> [ {w, defs:[...], ...} ]
library;

import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:web/web.dart' as web;

import '../domain/srs.dart';
import 'daily_stat.dart';
import 'note_record.dart';

abstract class ProgressStore {
  Future<Map<String, ReviewState>> loadAll();
  Future<void> upsert(String wordKey, ReviewState state);

  Future<List<NoteRecord>> loadNotes();
  Future<List<NoteRecord>> loadAllNotes();
  Future<NoteRecord> addNote(String wordKey, String content);
  Future<void> deleteNote(String id);
  Future<void> upsertNote(NoteRecord note);
  Future<void> hardDeleteNote(String id);

  Future<Set<String>> loadFavorites();
  Future<void> saveFavorites(Set<String> keys);

  Future<List<Map<String, dynamic>>> loadCustomWords();
  Future<void> saveCustomWords(List<Map<String, dynamic>> words);

  Future<void> recordStudy(String day, {required bool isNewWord});
  Future<List<DailyStat>> loadDaily();
  Future<void> clearAll();
}

class LocalStorageProgressStore implements ProgressStore {
  static const _kReview = 'es_review_v1';
  static const _kNotes = 'es_notes_v1';
  static const _kFav = 'es_favorites_v1';
  static const _kCustom = 'es_custom_v1';
  static const _kDaily = 'es_daily_v1';

  final Map<String, ReviewState> _cache = {};
  Map<String, NoteRecord>? _notes;
  Set<String>? _favorites;
  List<Map<String, dynamic>>? _custom;
  Map<String, DailyStat>? _daily;

  String? _read(String key) {
    try {
      return web.window.localStorage.getItem(key);
    } catch (_) {
      return null;
    }
  }

  void _write(String key, String value) {
    try {
      web.window.localStorage.setItem(key, value);
    } catch (_) {
      // 隐私模式/配额超限时静默降级
    }
  }

  // ── 复习进度 ──

  @override
  Future<Map<String, ReviewState>> loadAll() async {
    if (_cache.isNotEmpty) return Map.of(_cache);
    final raw = _read(_kReview);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final e in map.entries) {
        _cache[e.key] = ReviewState.fromJson(e.value as Map<String, dynamic>);
      }
    } catch (_) {}
    return Map.of(_cache);
  }

  @override
  Future<void> upsert(String wordKey, ReviewState state) async {
    _cache[wordKey] = state;
    _write(
      _kReview,
      jsonEncode({for (final e in _cache.entries) e.key: e.value.toJson()}),
    );
  }

  // ── 笔记 ──

  Map<String, NoteRecord> _loadNoteMap() {
    final cached = _notes;
    if (cached != null) return cached;
    final map = <String, NoteRecord>{};
    final raw = _read(_kNotes);
    if (raw != null && raw.isNotEmpty) {
      try {
        for (final e in jsonDecode(raw) as List) {
          final n = NoteRecord.fromJson(e as Map<String, dynamic>);
          map[n.id] = n;
        }
      } catch (_) {}
    }
    _notes = map;
    return map;
  }

  void _flushNotes() {
    final list = _loadNoteMap().values.map((n) => n.toJson()).toList();
    _write(_kNotes, jsonEncode(list));
  }

  @override
  Future<List<NoteRecord>> loadNotes() async {
    final list = _loadNoteMap().values.where((n) => !n.deleted).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(list);
  }

  @override
  Future<List<NoteRecord>> loadAllNotes() async =>
      List.unmodifiable(_loadNoteMap().values.toList());

  @override
  Future<NoteRecord> addNote(String wordKey, String content) async {
    final now = DateTime.now();
    final note = NoteRecord(
      id: const Uuid().v4(),
      wordKey: wordKey,
      content: content,
      createdAt: now,
      updatedAt: now,
    );
    _loadNoteMap()[note.id] = note;
    _flushNotes();
    return note;
  }

  @override
  Future<void> deleteNote(String id) async {
    final map = _loadNoteMap();
    final n = map[id];
    if (n == null) return;
    map[id] = n.copyWith(deleted: true, updatedAt: DateTime.now());
    _flushNotes();
  }

  @override
  Future<void> upsertNote(NoteRecord note) async {
    _loadNoteMap()[note.id] = note;
    _flushNotes();
  }

  @override
  Future<void> hardDeleteNote(String id) async {
    _loadNoteMap().remove(id);
    _flushNotes();
  }

  // ── 收藏 ──

  @override
  Future<Set<String>> loadFavorites() async {
    final cached = _favorites;
    if (cached != null) return Set.of(cached);
    final raw = _read(_kFav);
    final set = <String>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        for (final e in jsonDecode(raw) as List) {
          set.add(e.toString());
        }
      } catch (_) {}
    }
    _favorites = set;
    return Set.of(set);
  }

  @override
  Future<void> saveFavorites(Set<String> keys) async {
    _favorites = Set.of(keys);
    _write(_kFav, jsonEncode(keys.toList()));
  }

  // ── 自建词 ──

  @override
  Future<List<Map<String, dynamic>>> loadCustomWords() async {
    final cached = _custom;
    if (cached != null) return List.unmodifiable(cached);
    final raw = _read(_kCustom);
    final list = <Map<String, dynamic>>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        for (final e in jsonDecode(raw) as List) {
          list.add(e as Map<String, dynamic>);
        }
      } catch (_) {}
    }
    _custom = list;
    return List.unmodifiable(list);
  }

  @override
  Future<void> saveCustomWords(List<Map<String, dynamic>> words) async {
    _custom = List.of(words);
    _write(_kCustom, jsonEncode(words));
  }

  Map<String, DailyStat> _loadDailyMap() {
    final cached = _daily;
    if (cached != null) return cached;
    final map = <String, DailyStat>{};
    final raw = _read(_kDaily);
    if (raw != null && raw.isNotEmpty) {
      try {
        final obj = jsonDecode(raw) as Map<String, dynamic>;
        for (final e in obj.entries) {
          map[e.key] =
              DailyStat.fromJson(e.key, e.value as Map<String, dynamic>);
        }
      } catch (_) {}
    }
    _daily = map;
    return map;
  }

  @override
  Future<void> recordStudy(String day, {required bool isNewWord}) async {
    final map = _loadDailyMap();
    final cur = map[day] ?? DailyStat(date: day);
    map[day] = DailyStat(
      date: day,
      reviews: cur.reviews + 1,
      newWords: cur.newWords + (isNewWord ? 1 : 0),
    );
    _write(
      _kDaily,
      jsonEncode({for (final e in map.entries) e.key: e.value.toJson()}),
    );
  }

  @override
  Future<List<DailyStat>> loadDaily() async {
    final list = _loadDailyMap().values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  @override
  Future<void> clearAll() async {
    _cache.clear();
    _notes = {};
    _favorites = {};
    _custom = [];
    _daily = {};
    for (final k in [_kReview, _kNotes, _kFav, _kCustom, _kDaily]) {
      try {
        web.window.localStorage.removeItem(k);
      } catch (_) {}
    }
  }
}

Future<ProgressStore> createProgressStore() async =>
    LocalStorageProgressStore();
