/// 默认实现（不支持 dart:io 也不支持浏览器存储时降级为内存）
library;

import 'package:uuid/uuid.dart';

import '../domain/srs.dart';
import 'daily_stat.dart';
import 'note_record.dart';

abstract class ProgressStore {
  Future<Map<String, ReviewState>> loadAll();
  Future<void> upsert(String wordKey, ReviewState state);

  /// 未删除的笔记，按创建时间倒序
  Future<List<NoteRecord>> loadNotes();

  /// 全部笔记（含已软删除），仅用于同步比对
  Future<List<NoteRecord>> loadAllNotes();

  Future<NoteRecord> addNote(String wordKey, String content);

  /// 软删除
  Future<void> deleteNote(String id);

  /// 写入/覆盖一条笔记（合并远端数据时使用）
  Future<void> upsertNote(NoteRecord note);

  /// 物理删除（应用远端删除时使用）
  Future<void> hardDeleteNote(String id);

  Future<Set<String>> loadFavorites();
  Future<void> saveFavorites(Set<String> keys);

  Future<List<Map<String, dynamic>>> loadCustomWords();
  Future<void> saveCustomWords(List<Map<String, dynamic>> words);

  /// 记录一次学习（day 为 yyyy-MM-dd）
  Future<void> recordStudy(String day, {required bool isNewWord});

  /// 全部每日记录，按日期升序
  Future<List<DailyStat>> loadDaily();

  /// 清空全部本地数据（不可撤销）
  Future<void> clearAll();
}

class MemoryProgressStore implements ProgressStore {
  final Map<String, ReviewState> _states = {};
  final Map<String, NoteRecord> _notes = {};
  Set<String> _favorites = {};
  List<Map<String, dynamic>> _custom = [];
  final Map<String, DailyStat> _daily = {};

  @override
  Future<Map<String, ReviewState>> loadAll() async => Map.of(_states);

  @override
  Future<void> upsert(String wordKey, ReviewState state) async {
    _states[wordKey] = state;
  }

  @override
  Future<List<NoteRecord>> loadNotes() async => _notes.values
      .where((n) => !n.deleted)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<List<NoteRecord>> loadAllNotes() async => _notes.values.toList();

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
    _notes[note.id] = note;
    return note;
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
  Future<Set<String>> loadFavorites() async => Set.of(_favorites);

  @override
  Future<void> saveFavorites(Set<String> keys) async {
    _favorites = Set.of(keys);
  }

  @override
  Future<List<Map<String, dynamic>>> loadCustomWords() async =>
      List.unmodifiable(_custom);

  @override
  Future<void> saveCustomWords(List<Map<String, dynamic>> words) async {
    _custom = List.of(words);
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
  Future<void> clearAll() async {
    _states.clear();
    _notes.clear();
    _favorites = {};
    _custom = [];
    _daily.clear();
  }
}

Future<ProgressStore> createProgressStore() async => MemoryProgressStore();
