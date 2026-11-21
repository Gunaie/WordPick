/// 桌面 / 移动平台实现：SQLite 持久化
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
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

  Future<List<NoteRecord>> loadNotes();
  Future<List<NoteRecord>> loadAllNotes();
  Future<NoteRecord> addNote(
    String wordKey,
    String content, {
    String title = '',
    List<String> tags = const [],
  });
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

  /// 易混词组（JSON 列表，复用 meta 表）
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
        title      TEXT    NOT NULL DEFAULT '',
        content    TEXT    NOT NULL,
        tags       TEXT    NOT NULL DEFAULT '[]',
        created_at TEXT    NOT NULL,
        updated_at TEXT    NOT NULL,
        deleted    INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // v0.10 起笔记支持标题与标签，旧库就地补列
    final noteColumnNames = _db
        .select('PRAGMA table_info(note)')
        .map((r) => r['name'].toString())
        .toSet();
    if (!noteColumnNames.contains('title')) {
      _db.execute(
        "ALTER TABLE note ADD COLUMN title TEXT NOT NULL DEFAULT ''",
      );
    }
    if (!noteColumnNames.contains('tags')) {
      _db.execute(
        "ALTER TABLE note ADD COLUMN tags TEXT NOT NULL DEFAULT '[]'",
      );
    }

    _db.execute('''
      CREATE TABLE IF NOT EXISTS meta (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // 收藏功能已下线，清掉旧版本残留
    _db.execute("DELETE FROM meta WHERE key = 'favorites'");

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

  @override
  Future<void> deleteState(String wordKey) async {
    _db.execute('DELETE FROM review_state WHERE word_key = ?', [wordKey]);
  }

  // ── 笔记 ──

  NoteRecord _rowToNote(Row r) => NoteRecord(
        id: r['id'] as String,
        wordKey: r['word_key'] as String,
        title: (r['title'] as String?) ?? '',
        content: r['content'] as String,
        tags: _decodeTags(r['tags'] as String?),
        createdAt: DateTime.parse(r['created_at'] as String),
        updatedAt: DateTime.parse(r['updated_at'] as String),
        deleted: (r['deleted'] as num).toInt() == 1,
      );

  List<String> _decodeTags(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List).whereType<String>().toList();
    } catch (_) {
      return const [];
    }
  }

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
    _db.execute(
      'INSERT INTO note (id, word_key, title, content, tags, created_at, updated_at, deleted) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, 0)',
      [
        note.id,
        wordKey,
        title,
        content,
        jsonEncode(tags),
        now.toIso8601String(),
        now.toIso8601String(),
      ],
    );
    return note;
  }

  @override
  Future<void> updateNote(
    String id,
    String content, {
    String? title,
    List<String>? tags,
  }) async {
    final sets = <String>['content = ?', 'updated_at = ?'];
    final args = <Object?>[content, DateTime.now().toIso8601String()];
    if (title != null) {
      sets.add('title = ?');
      args.add(title);
    }
    if (tags != null) {
      sets.add('tags = ?');
      args.add(jsonEncode(tags));
    }
    args.add(id);
    _db.execute('UPDATE note SET ${sets.join(', ')} WHERE id = ?', args);
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
      INSERT INTO note (id, word_key, title, content, tags, created_at, updated_at, deleted)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        word_key = excluded.word_key,
        title = excluded.title,
        content = excluded.content,
        tags = excluded.tags,
        updated_at = excluded.updated_at,
        deleted = excluded.deleted
      ''',
      [
        n.id,
        n.wordKey,
        n.title,
        n.content,
        jsonEncode(n.tags),
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

  // ── 自建单词本 ──

  @override
  Future<List<Map<String, dynamic>>> loadCustomBooks() async =>
      _decodeList('custom_books');

  @override
  Future<void> saveCustomBooks(List<Map<String, dynamic>> books) async {
    _setMeta('custom_books', jsonEncode(books));
  }

  @override
  Future<List<Map<String, dynamic>>> loadConfusableGroups() async =>
      _decodeList('confusable_groups');

  @override
  Future<void> saveConfusableGroups(List<Map<String, dynamic>> groups) async {
    _setMeta('confusable_groups', jsonEncode(groups));
  }

  @override
  Future<List<Map<String, dynamic>>> loadLegacyCustomWords() async =>
      _decodeList('custom_words');

  @override
  Future<void> clearLegacyCustomWords() async {
    _db.execute("DELETE FROM meta WHERE key = 'custom_words'");
  }

  List<Map<String, dynamic>> _decodeList(String key) {
    final raw = _getMeta(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
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
  Future<void> mergeDaily(List<DailyStat> stats) async {
    for (final s in stats) {
      _db.execute(
        '''
        INSERT INTO daily_stat (date, reviews, new_words) VALUES (?, ?, ?)
        ON CONFLICT(date) DO UPDATE SET
          reviews = MAX(reviews, excluded.reviews),
          new_words = MAX(new_words, excluded.new_words)
        ''',
        [s.date, s.reviews, s.newWords],
      );
    }
  }

  @override
  Future<AppSettings> loadSettings() async {
    final raw = _getMeta('settings');
    if (raw == null || raw.isEmpty) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _setMeta('settings', jsonEncode(settings.toJson()));
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
