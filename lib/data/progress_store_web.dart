/// Web 平台实现：localStorage 持久化
///
/// 存储键：
///   es_review_v1    -> { "word": {ease, interval, reps, lapses, due, updated_at} }
///   es_notes_v1     -> [ {id, word_key, content, created_at, updated_at, deleted} ]
///   es_books_v1     -> [ {id, name, created_at, words:[{w, defs, added_at, add_count}]} ]
///   es_confusable_v1 -> [ {id, name, word_keys, created_at} ]
///   es_custom_v1    -> 旧版扁平自建词，仅用于迁移
library;

import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:web/web.dart' as web;

import '../domain/srs.dart';
import 'app_settings.dart';
import 'daily_stat.dart';
import 'note_record.dart';

abstract class ProgressStore {
  Future<Map<String, ReviewState>> loadAll();
  Future<void> upsert(String wordKey, ReviewState state);

  /// 删除某个词的本地复习状态（词条被移除时使用）
  Future<void> deleteState(String wordKey);

  Future<List<NoteRecord>> loadNotes();
  Future<List<NoteRecord>> loadAllNotes();
  Future<NoteRecord> addNote(
    String wordKey,
    String content, {
    String title = '',
    List<String> tags = const [],
  });

  /// 编辑内容（保留创建时间）
  Future<void> updateNote(
    String id,
    String content, {
    String? title,
    List<String>? tags,
  });
  Future<void> deleteNote(String id);
  Future<void> upsertNote(NoteRecord note);
  Future<void> hardDeleteNote(String id);

  Future<List<Map<String, dynamic>>> loadCustomBooks();
  Future<void> saveCustomBooks(List<Map<String, dynamic>> books);

  /// 易混词组（localStorage JSON 列表）
  Future<List<Map<String, dynamic>>> loadConfusableGroups();
  Future<void> saveConfusableGroups(List<Map<String, dynamic>> groups);

  /// 旧版扁平的「自建词」数据，仅用于一次性迁移
  Future<List<Map<String, dynamic>>> loadLegacyCustomWords();
  Future<void> clearLegacyCustomWords();

  Future<void> recordStudy(String day, {required bool isNewWord});
  Future<List<DailyStat>> loadDaily();

  /// 合并每日记录：同一天取更大的计数，避免恢复备份时重复累加
  Future<void> mergeDaily(List<DailyStat> stats);

  Future<AppSettings> loadSettings();
  Future<void> saveSettings(AppSettings settings);

  Future<void> clearAll();
}

class LocalStorageProgressStore implements ProgressStore {
  static const _kReview = 'es_review_v1';
  static const _kNotes = 'es_notes_v1';
  static const _kFav = 'es_favorites_v1';
  static const _kBooks = 'es_books_v1';
  static const _kConfusable = 'es_confusable_v1';
  static const _kCustom = 'es_custom_v1';
  static const _kDaily = 'es_daily_v1';
  static const _kSettings = 'es_settings_v1';

  final Map<String, ReviewState> _cache = {};
  Map<String, NoteRecord>? _notes;
  List<Map<String, dynamic>>? _custom;
  List<Map<String, dynamic>>? _groups;
  Map<String, DailyStat>? _daily;

  LocalStorageProgressStore() {
    // 收藏功能已下线，清掉旧版本残留
    try {
      web.window.localStorage.removeItem(_kFav);
    } catch (_) {}
  }

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

  @override
  Future<void> deleteState(String wordKey) async {
    _cache.remove(wordKey);
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
  Future<NoteRecord> addNote(
    String wordKey,
    String content, {
    String title = '',
    List<String> tags = const [],
  }) async {
    final now = DateTime.now();
    final note = NoteRecord(
      id: const Uuid().v4(),
      wordKey: wordKey,
      title: title,
      content: content,
      tags: tags,
      createdAt: now,
      updatedAt: now,
    );
    _loadNoteMap()[note.id] = note;
    _flushNotes();
    return note;
  }

  @override
  Future<void> updateNote(
    String id,
    String content, {
    String? title,
    List<String>? tags,
  }) async {
    final map = _loadNoteMap();
    final n = map[id];
    if (n == null) return;
    map[id] = n.copyWith(
      content: content,
      title: title,
      tags: tags,
      updatedAt: DateTime.now(),
    );
    _flushNotes();
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

  // ── 自建单词本 ──

  @override
  Future<List<Map<String, dynamic>>> loadCustomBooks() async {
    final cached = _custom;
    if (cached != null) return List.unmodifiable(cached);
    final list = <Map<String, dynamic>>[];
    final raw = _read(_kBooks);
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
  Future<void> saveCustomBooks(List<Map<String, dynamic>> books) async {
    _custom = List.of(books);
    _write(_kBooks, jsonEncode(books));
  }

  @override
  Future<List<Map<String, dynamic>>> loadConfusableGroups() async {
    final cached = _groups;
    if (cached != null) return List.unmodifiable(cached);
    final list = <Map<String, dynamic>>[];
    final raw = _read(_kConfusable);
    if (raw != null && raw.isNotEmpty) {
      try {
        for (final e in jsonDecode(raw) as List) {
          list.add(e as Map<String, dynamic>);
        }
      } catch (_) {}
    }
    _groups = list;
    return List.unmodifiable(list);
  }

  @override
  Future<void> saveConfusableGroups(List<Map<String, dynamic>> groups) async {
    _groups = List.of(groups);
    _write(_kConfusable, jsonEncode(groups));
  }

  @override
  Future<List<Map<String, dynamic>>> loadLegacyCustomWords() async {
    final list = <Map<String, dynamic>>[];
    final raw = _read(_kCustom);
    if (raw != null && raw.isNotEmpty) {
      try {
        for (final e in jsonDecode(raw) as List) {
          list.add(e as Map<String, dynamic>);
        }
      } catch (_) {}
    }
    return list;
  }

  @override
  Future<void> clearLegacyCustomWords() async {
    try {
      web.window.localStorage.removeItem(_kCustom);
    } catch (_) {}
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
  Future<void> mergeDaily(List<DailyStat> stats) async {
    final map = _loadDailyMap();
    for (final s in stats) {
      final cur = map[s.date];
      if (cur == null) {
        map[s.date] = s;
        continue;
      }
      map[s.date] = DailyStat(
        date: s.date,
        reviews: cur.reviews > s.reviews ? cur.reviews : s.reviews,
        newWords: cur.newWords > s.newWords ? cur.newWords : s.newWords,
      );
    }
    _write(
      _kDaily,
      jsonEncode({for (final e in map.entries) e.key: e.value.toJson()}),
    );
  }

  @override
  Future<AppSettings> loadSettings() async {
    final raw = _read(_kSettings);
    if (raw == null || raw.isEmpty) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _write(_kSettings, jsonEncode(settings.toJson()));
  }

  @override
  Future<void> clearAll() async {
    _cache.clear();
    _notes = {};
    _custom = [];
    _groups = [];
    _daily = {};
    for (final k in [
      _kReview,
      _kNotes,
      _kFav,
      _kBooks,
      _kConfusable,
      _kCustom,
      _kDaily,
      _kSettings,
    ]) {
      try {
        web.window.localStorage.removeItem(k);
      } catch (_) {}
    }
  }
}

Future<ProgressStore> createProgressStore() async =>
    LocalStorageProgressStore();
