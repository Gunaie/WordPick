/// 桌面 / 移动平台实现：SQLite 持久化
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

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

class SqliteProgressStore implements ProgressStore {
  final Database _db;

  SqliteProgressStore._(this._db) {
    _migrate();
  }

  static Future<SqliteProgressStore> open() async {
    final dir = await getApplicationSupportDirectory();
    await Directory(dir.path).create(recursive: true);
    final file = p.join(dir.path, 'english_study.db');
    final db = sqlite3.open(file);
    return SqliteProgressStore._(db);
  }

  void _migrate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS review_state (
        word_key   TEXT PRIMARY KEY,
        ease       REAL    NOT NULL,
        interval   INTEGER NOT NULL,
        reps       INTEGER NOT NULL,
        lapses     INTEGER NOT NULL,
        due        TEXT    NOT NULL,
        updated_at TEXT    NOT NULL
      )
    ''');

    // 旧版本的 note 表用的是 INTEGER 自增主键；跨端同步需要客户端生成的 TEXT uuid
    final noteCols = _db.select('PRAGMA table_info(note)');
    if (noteCols.isNotEmpty) {
      var idType = '';
      for (final c in noteCols) {
        if (c['name'] == 'id') {
          idType = (c['type'] ?? '').toString().toUpperCase();
          break;
        }
      }
      if (!idType.contains('TEXT')) {
        _db.execute('DROP TABLE IF EXISTS note');
      }
    }

    _db.execute('''
      CREATE TABLE IF NOT EXISTS note (
        id         TEXT PRIMARY KEY,
        word_key   TEXT    NOT NULL,
        content    TEXT    NOT NULL,
        created_at TEXT    NOT NULL,
        updated_at TEXT    NOT NULL,
        deleted    INTEGER NOT NULL DEFAULT 0
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS meta (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS daily_stat (
        date      TEXT    PRIMARY KEY,
        reviews   INTEGER NOT NULL DEFAULT 0,
        new_words INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  String? _getMeta(String key) {
    final rows = _db.select('SELECT value FROM meta WHERE key = ?', [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  void _setMeta(String key, String value) {
    _db.execute(
      'INSERT INTO meta (key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, value],
    );
  }

  // ── 复习进度 ──

  @override
  Future<Map<String, ReviewState>> loadAll() async {
    final rows = _db.select('SELECT * FROM review_state');
    return {
      for (final r in rows)
        r['word_key'] as String: ReviewState(
          ease: (r['ease'] as num).toDouble(),
          interval: (r['interval'] as num).toInt(),
          reps: (r['reps'] as num).toInt(),
          lapses: (r['lapses'] as num).toInt(),
          due: DateTime.parse(r['due'] as String),
          updatedAt: DateTime.parse(r['updated_at'] as String),
        ),
    };
  }

  @override
  Future<void> upsert(String wordKey, ReviewState s) async {
    _db.execute(
      '''
      INSERT INTO review_state (word_key, ease, interval, reps, lapses, due, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(word_key) DO UPDATE SET
        ease = excluded.ease,
        interval = excluded.interval,
        reps = excluded.reps,
        lapses = excluded.lapses,
        due = excluded.due,
        updated_at = excluded.updated_at
      ''',
      [
        wordKey,
        s.ease,
        s.interval,
        s.reps,
        s.lapses,
        s.due.toIso8601String(),
        s.updatedAt.toIso8601String(),
      ],
    );
  }

  // ── 笔记 ──

  NoteRecord _rowToNote(Row r) => NoteRecord(
        id: r['id'] as String,
        wordKey: r['word_key'] as String,
        content: r['content'] as String,
        createdAt: DateTime.parse(r['created_at'] as String),
        updatedAt: DateTime.parse(r['updated_at'] as String),
        deleted: (r['deleted'] as num).toInt() == 1,
      );

  @override
  Future<List<NoteRecord>> loadNotes() async {
    final rows = _db.select(
      'SELECT * FROM note WHERE deleted = 0 ORDER BY created_at DESC',
    );
    return rows.map(_rowToNote).toList();
  }

  @override
  Future<List<NoteRecord>> loadAllNotes() async {
    final rows = _db.select('SELECT * FROM note');
    return rows.map(_rowToNote).toList();
  }

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
    _db.execute(
      'INSERT INTO note (id, word_key, content, created_at, updated_at, deleted) '
      'VALUES (?, ?, ?, ?, ?, 0)',
      [
        note.id,
        wordKey,
        content,
        now.toIso8601String(),
        now.toIso8601String(),
      ],
    );
    return note;
  }

  @override
  Future<void> deleteNote(String id) async {
    _db.execute(
      'UPDATE note SET deleted = 1, updated_at = ? WHERE id = ?',
      [DateTime.now().toIso8601String(), id],
    );
  }

  @override
  Future<void> upsertNote(NoteRecord n) async {
    _db.execute(
      '''
      INSERT INTO note (id, word_key, content, created_at, updated_at, deleted)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        content = excluded.content,
        updated_at = excluded.updated_at,
        deleted = excluded.deleted
      ''',
      [
        n.id,
        n.wordKey,
        n.content,
        n.createdAt.toIso8601String(),
        n.updatedAt.toIso8601String(),
        n.deleted ? 1 : 0,
      ],
    );
  }

  @override
  Future<void> hardDeleteNote(String id) async {
    _db.execute('DELETE FROM note WHERE id = ?', [id]);
  }

  // ── 收藏 ──

  @override
  Future<Set<String>> loadFavorites() async {
    final raw = _getMeta('favorites');
    if (raw == null || raw.isEmpty) return {};
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> saveFavorites(Set<String> keys) async {
    _setMeta('favorites', jsonEncode(keys.toList()));
  }

  // ── 自建词 ──

  @override
  Future<List<Map<String, dynamic>>> loadCustomWords() async {
    final raw = _getMeta('custom_words');
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> saveCustomWords(List<Map<String, dynamic>> words) async {
    _setMeta('custom_words', jsonEncode(words));
  }

  @override
  Future<void> recordStudy(String day, {required bool isNewWord}) async {
    _db.execute(
      '''
      INSERT INTO daily_stat (date, reviews, new_words) VALUES (?, 1, ?)
      ON CONFLICT(date) DO UPDATE SET
        reviews = reviews + 1,
        new_words = new_words + excluded.new_words
      ''',
      [day, isNewWord ? 1 : 0],
    );
  }

  @override
  Future<List<DailyStat>> loadDaily() async {
    final rows = _db.select('SELECT * FROM daily_stat ORDER BY date ASC');
    return rows
        .map((r) => DailyStat(
              date: r['date'] as String,
              reviews: (r['reviews'] as num).toInt(),
              newWords: (r['new_words'] as num).toInt(),
            ))
        .toList();
  }

  @override
  Future<void> clearAll() async {
    _db.execute('DELETE FROM review_state');
    _db.execute('DELETE FROM note');
    _db.execute('DELETE FROM meta');
    _db.execute('DELETE FROM daily_stat');
  }
}

Future<ProgressStore> createProgressStore() async => SqliteProgressStore.open();
