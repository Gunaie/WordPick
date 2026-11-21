/// 默认实现（不支持 dart:io 也不支持浏览器存储时降级为内存）
library;

import 'package:uuid/uuid.dart';

import '../domain/srs.dart';
import 'app_settings.dart';
import 'daily_stat.dart';
import 'note_record.dart';

abstract class ProgressStore {
  Future<Map<String, ReviewState>> loadAll();
  Future<void> upsert(String wordKey, ReviewState state);

  /// 删除某个词的本地复习状态（词条被移除时使用）
  Future<void> deleteState(String wordKey);

  /// 未删除的笔记，按创建时间倒序
  Future<List<NoteRecord>> loadNotes();

  /// 全部笔记（含已软删除），仅用于同步比对
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

  /// 软删除
  Future<void> deleteNote(String id);

  /// 写入/覆盖一条笔记（合并远端数据时使用）
  Future<void> upsertNote(NoteRecord note);

  /// 物理删除（应用远端删除时使用）
  Future<void> hardDeleteNote(String id);

  Future<List<Map<String, dynamic>>> loadCustomBooks();
  Future<void> saveCustomBooks(List<Map<String, dynamic>> books);

  /// 易混词组（内存 JSON 列表）
  Future<List<Map<String, dynamic>>> loadConfusableGroups();
  Future<void> saveConfusableGroups(List<Map<String, dynamic>> groups);

  /// 旧版扁平的「自建词」数据，仅用于一次性迁移
  Future<List<Map<String, dynamic>>> loadLegacyCustomWords();
  Future<void> clearLegacyCustomWords();

  /// 记录一次学习（day 为 yyyy-MM-dd）
  Future<void> recordStudy(String day, {required bool isNewWord});

  /// 全部每日记录，按日期升序
  Future<List<DailyStat>> loadDaily();

  /// 合并每日记录：同一天取更大的计数，避免恢复备份时重复累加
  Future<void> mergeDaily(List<DailyStat> stats);

  Future<AppSettings> loadSettings();
  Future<void> saveSettings(AppSettings settings);

  /// 清空全部本地数据（不可撤销）
  Future<void> clearAll();
}

class MemoryProgressStore implements ProgressStore {
  final Map<String, ReviewState> _states = {};
  final Map<String, NoteRecord> _notes = {};
  List<Map<String, dynamic>> _books = [];
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _legacyWords = [];
  final Map<String, DailyStat> _daily = {};
  AppSettings _settings = const AppSettings();

  @override
  Future<Map<String, ReviewState>> loadAll() async => Map.of(_states);

  @override
  Future<void> upsert(String wordKey, ReviewState state) async {
    _states[wordKey] = state;
  }

  @override
  Future<void> deleteState(String wordKey) async {
    _states.remove(wordKey);
  }

  @override
  Future<List<NoteRecord>> loadNotes() async => _notes.values
      .where((n) => !n.deleted)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<List<NoteRecord>> loadAllNotes() async => _notes.values.toList();

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
    _notes[note.id] = note;
    return note;
  }

  @override
  Future<void> updateNote(
    String id,
    String content, {
    String? title,
    List<String>? tags,
  }) async {
    final n = _notes[id];
    if (n == null) return;
    _notes[id] = n.copyWith(
      content: content,
      title: title,
      tags: tags,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> deleteNote(String id) async {
    final n = _notes[id];
    if (n == null) return;
    _notes[id] = n.copyWith(deleted: true, updatedAt: DateTime.now());
  }

  @override
  Future<void> upsertNote(NoteRecord note) async {
    _notes[note.id] = note;
  }

  @override
  Future<void> hardDeleteNote(String id) async {
    _notes.remove(id);
  }

  @override
  Future<List<Map<String, dynamic>>> loadCustomBooks() async =>
      List.unmodifiable(_books);

  @override
  Future<void> saveCustomBooks(List<Map<String, dynamic>> books) async {
    _books = List.of(books);
  }

  @override
  Future<List<Map<String, dynamic>>> loadConfusableGroups() async =>
      List.unmodifiable(_groups);

  @override
  Future<void> saveConfusableGroups(List<Map<String, dynamic>> groups) async {
    _groups = List.of(groups);
  }

  @override
  Future<List<Map<String, dynamic>>> loadLegacyCustomWords() async =>
      List.unmodifiable(_legacyWords);

  @override
  Future<void> clearLegacyCustomWords() async {
    _legacyWords = [];
  }

  @override
  Future<void> recordStudy(String day, {required bool isNewWord}) async {
    final cur = _daily[day] ?? DailyStat(date: day);
    _daily[day] = DailyStat(
      date: day,
      reviews: cur.reviews + 1,
      newWords: cur.newWords + (isNewWord ? 1 : 0),
    );
  }

  @override
  Future<List<DailyStat>> loadDaily() async {
    final list = _daily.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  @override
  Future<void> mergeDaily(List<DailyStat> stats) async {
    for (final s in stats) {
      final cur = _daily[s.date];
      if (cur == null) {
        _daily[s.date] = s;
        continue;
      }
      _daily[s.date] = DailyStat(
        date: s.date,
        reviews: cur.reviews > s.reviews ? cur.reviews : s.reviews,
        newWords: cur.newWords > s.newWords ? cur.newWords : s.newWords,
      );
    }
  }

  @override
  Future<AppSettings> loadSettings() async => _settings;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
  }

  @override
  Future<void> clearAll() async {
    _states.clear();
    _notes.clear();
    _books = [];
    _groups = [];
    _legacyWords = [];
    _daily.clear();
    _settings = const AppSettings();
  }
}

Future<ProgressStore> createProgressStore() async => MemoryProgressStore();
