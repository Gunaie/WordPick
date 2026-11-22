/// 应用全局状态（ChangeNotifier）
///
/// 说明：本迭代用最简单的 ChangeNotifier + ListenableBuilder。
/// 待核心流程稳定后，再评估是否引入 Riverpod（见 docs/decisions.md D08 / D12）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'data/affix_repository.dart';
import 'data/app_settings.dart';
import 'data/cloud_sync.dart';
import 'data/daily_stat.dart';
import 'data/dictionary_repository.dart';
import 'data/progress_store.dart';
import 'data/sync_config.dart';
import 'domain/confusable_group.dart';
import 'domain/confusable_queue.dart';
import 'domain/custom_word_parser.dart';
import 'domain/export_import.dart';
import 'domain/srs.dart';
import 'domain/word.dart';
import 'services/audio_service.dart';

/// 从备份恢复后的变更统计
class RestoreReport {
  final int booksAdded;
  final int wordsAdded;
  final int notesAdded;
  final int notesUpdated;
  final int statesAdded;
  final int statesUpdated;

  const RestoreReport({
    this.booksAdded = 0,
    this.wordsAdded = 0,
    this.notesAdded = 0,
    this.notesUpdated = 0,
    this.statesAdded = 0,
    this.statesUpdated = 0,
  });

  bool get hasChanges =>
      booksAdded + wordsAdded + notesAdded + notesUpdated + statesAdded + statesUpdated > 0;

  String get summary => '新增 $booksAdded 本词书 / $wordsAdded 个词 / '
      '$notesAdded 条笔记，更新 $notesUpdated 条笔记、$statesUpdated 个复习状态';
}

class AppState extends ChangeNotifier {
  final AffixRepository affixes = AffixRepository();
  final DictionaryRepository dictionary = DictionaryRepository();
  late ProgressStore _store;

  Map<String, ReviewState> _states = {};
  List<CustomWordBook> _customBooks = [];
  List<ConfusableGroup> _groups = [];
  List<NoteRecord> _notes = [];
  List<DailyStat> _daily = [];
  AppSettings _settings = const AppSettings();

  bool _ready = false;
  String? _error;

  // ── 云同步状态 ──
  final CloudSync? _sync = SyncConfig.enabled ? CloudSync() : null;
  bool _syncing = false;
  String? _syncError;
  DateTime? _lastSyncedAt;
  DateTime? _lastSyncAttempt;

  bool get isReady => _ready;
  String? get error => _error;
  ProgressStore get store => _store;

  bool get syncEnabled => _sync != null;
  bool get syncing => _syncing;
  String? get syncError => _syncError;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  Map<String, ReviewState> get states => Map.unmodifiable(_states);
  List<CustomWordBook> get customBooks => List.unmodifiable(_customBooks);
  List<ConfusableGroup> get confusableGroups => List.unmodifiable(_groups);

  /// 所有自建单词本里的词
  List<CustomWordEntry> get customWords =>
      List.unmodifiable(_customBooks.expand((b) => b.words).toList());
  List<NoteRecord> get notes => List.unmodifiable(_notes);

  /// 按 id 取一本自建单词本
  CustomWordBook? bookById(String id) {
    for (final b in _customBooks) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// 已学 / 待复习 / 熟记只统计当前词池里的词；
  /// 内置词库下线后留下的历史复习状态视为孤儿数据，不展示也不删除。
  int get learnedCount =>
      pool.where((w) => _states.containsKey(w.key)).length;
  int get dueCount =>
      pool.where((w) => _states[w.key]?.isDue ?? false).length;
  int get scheduledCount =>
      pool.where((w) {
        final s = _states[w.key];
        return s != null && !s.isDue;
      }).length;

  /// 熟记：复习间隔 ≥ 21 天（SM-2 常用阈值）
  int get masteredCount =>
      pool.where((w) => (_states[w.key]?.interval ?? 0) >= 21).length;

  List<DailyStat> get dailyStats => List.unmodifiable(_daily);
  AppSettings get settings => _settings;

  int get streakDays => streakOf(_daily);

  int get todayReviews {
    final key = dayKey(DateTime.now());
    for (final d in _daily) {
      if (d.date == key) return d.reviews;
    }
    return 0;
  }

  /// 今天是否已学习（签到由每日学习记录派生）
  bool get studiedToday => todayReviews > 0;

  /// 今日已学：今天更新过复习状态的词，按词去重
  int get todayLearnedCount {
    final now = DateTime.now();
    return pool.where((w) {
      final s = _states[w.key];
      if (s == null) return false;
      final t = s.updatedAt;
      return t.year == now.year && t.month == now.month && t.day == now.day;
    }).length;
  }

  Future<void> init() async {
    try {
      _store = await createProgressStore();
      await affixes.load();
      await dictionary.load();
      _states = await _store.loadAll();
      _notes = await _store.loadNotes();
      _daily = await _store.loadDaily();
      _settings = await _store.loadSettings();
      AudioService.isUk = _settings.useUkAccent;
      await _loadCustomBooks();
      _groups = (await _store.loadConfusableGroups())
          .map(ConfusableGroup.fromJson)
          .toList();
      _ready = true;
    } catch (e) {
      _error = '$e';
    } finally {
      notifyListeners();
    }

    // 启动后后台拉一次云端数据（不阻塞首屏）
    if (_error == null) unawaited(syncNow());
  }

  /// 读取自建单词本；旧版扁平「自建词」自动迁移成一本「我的单词本」
  Future<void> _loadCustomBooks() async {
    final raw = await _store.loadCustomBooks();
    if (raw.isNotEmpty) {
      _customBooks = raw.map(CustomWordBook.fromJson).toList();
      await _store.clearLegacyCustomWords();
      return;
    }
    final legacy = await _store.loadLegacyCustomWords();
    if (legacy.isEmpty) return;

    final entries = legacy.map(CustomWordEntry.fromJson).toList();
    _customBooks = [
      CustomWordBook(
        id: 'legacy',
        name: '我的单词本',
        createdAt: DateTime.now(),
        words: entries,
      ),
    ];
    await _store.saveCustomBooks(_booksData());
    await _store.clearLegacyCustomWords();
  }

  /// 保存学习设置；口音立即生效
  Future<void> updateSettings(AppSettings next) async {
    _settings = next;
    AudioService.isUk = next.useUkAccent;
    // 先通知界面再落盘：本地存储写入失败时设置项仍然立即生效，
    // 不会出现「点了没反应」的观感
    notifyListeners();
    await _store.saveSettings(next);
  }

  /// 从备份 JSON 合并恢复：词书 / 笔记 / 复习状态 / 每日统计。
  ///
  /// 策略为「合并」而非覆盖：词按 key 去重，笔记与复习状态按 updatedAt 后写覆盖，
  /// 每日统计按日期取较大值。格式错误抛出 [FormatException]，由界面提示。
  Future<RestoreReport> restoreFromJson(String raw) async {
    final data = parseExportJson(raw);
    var booksAdded = 0;
    var wordsAdded = 0;
    var notesAdded = 0;
    var notesUpdated = 0;
    var statesAdded = 0;
    var statesUpdated = 0;

    // 词书：同 id 合并词条，新书追加；全局按 key 去重，避免跨书重复
    final knownKeys = <String>{
      for (final b in _customBooks)
        for (final e in b.words) e.key,
    };
    final incomingById = {for (final b in data.books) b.id: b};
    final mergedBooks = <CustomWordBook>[];
    for (final local in _customBooks) {
      final incoming = incomingById.remove(local.id);
      if (incoming == null) {
        mergedBooks.add(local);
        continue;
      }
      final additions = incoming.words
          .where((e) => knownKeys.add(e.key))
          .toList();
      mergedBooks.add(
        additions.isEmpty
            ? local
            : local.copyWith(words: [...local.words, ...additions]),
      );
      wordsAdded += additions.length;
    }
    for (final incoming in incomingById.values) {
      final additions = incoming.words
          .where((e) => knownKeys.add(e.key))
          .toList();
      mergedBooks.add(incoming.copyWith(words: additions));
      booksAdded++;
      wordsAdded += additions.length;
    }
    if (booksAdded > 0 || wordsAdded > 0) {
      _customBooks = mergedBooks;
      await _store.saveCustomBooks(_booksData());
    }

    // 笔记：按 id 合并，较新的覆盖
    if (data.notes.isNotEmpty) {
      final localById = {for (final n in await _store.loadAllNotes()) n.id: n};
      for (final n in data.notes) {
        final local = localById[n.id];
        if (local == null) {
          await _store.upsertNote(n);
          notesAdded++;
        } else if (n.updatedAt.isAfter(local.updatedAt)) {
          await _store.upsertNote(n);
          notesUpdated++;
        }
      }
      _notes = await _store.loadNotes();
    }

    // 复习状态：按词 key 合并，较新的覆盖
    for (final e in data.states.entries) {
      final local = _states[e.key];
      if (local == null) {
        _states[e.key] = e.value;
        await _store.upsert(e.key, e.value);
        statesAdded++;
      } else if (e.value.updatedAt.isAfter(local.updatedAt)) {
        _states[e.key] = e.value;
        await _store.upsert(e.key, e.value);
        statesUpdated++;
      }
    }

    // 每日统计：按日期取较大值，避免重复累加
    if (data.daily.isNotEmpty) {
      await _store.mergeDaily(data.daily);
      _daily = await _store.loadDaily();
    }

    final report = RestoreReport(
      booksAdded: booksAdded,
      wordsAdded: wordsAdded,
      notesAdded: notesAdded,
      notesUpdated: notesUpdated,
      statesAdded: statesAdded,
      statesUpdated: statesUpdated,
    );
    notifyListeners();
    if (report.hasChanges) unawaited(syncNow());
    return report;
  }

  /// 全量同步：先拉远端，按 updated_at 合并，再把本地更新的推上去
  Future<void> syncNow() async {
    final sync = _sync;
    if (sync == null || _syncing) return;

    _syncing = true;
    _syncError = null;
    _lastSyncAttempt = DateTime.now();
    notifyListeners();

    try {
      final remote = await sync.pullReviewStates();

      for (final e in remote.entries) {
        final local = _states[e.key];
        if (local == null || e.value.updatedAt.isAfter(local.updatedAt)) {
          _states[e.key] = e.value;
          await _store.upsert(e.key, e.value);
        }
      }

      final toPush = <String, ReviewState>{};
      for (final e in _states.entries) {
        final r = remote[e.key];
        if (r == null || e.value.updatedAt.isAfter(r.updatedAt)) {
          toPush[e.key] = e.value;
        }
      }
      if (toPush.isNotEmpty) await sync.pushReviewStates(toPush);

      await _syncNotes(sync);
      await _syncMeta(sync);

      _lastSyncedAt = DateTime.now();
      _syncError = null;
    } catch (e) {
      _syncError = e is SyncException ? e.message : '$e';
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// 回到前台时静默同步：未就绪、未启用、正在同步或距上次尝试不足冷却时间则跳过。
  ///
  /// 手动「立即同步」仍走 [syncNow]，不受冷却限制。
  Future<void> autoSync() async {
    if (!_ready || !syncEnabled || _syncing) return;
    final last = _lastSyncAttempt;
    if (last != null && DateTime.now().difference(last) < _autoSyncCooldown) {
      return;
    }
    await syncNow();
  }

  static const Duration _autoSyncCooldown = Duration(seconds: 60);

  /// 笔记合并：远端软删除 → 本地物理删除；其余按 updated_at 取新
  Future<void> _syncNotes(CloudSync sync) async {
    final remote = await sync.pullNotes();
    final remoteById = {for (final n in remote) n.id: n};
    final localAll = await _store.loadAllNotes();
    final localById = {for (final n in localAll) n.id: n};

    for (final r in remote) {
      final l = localById[r.id];
      if (r.deleted) {
        if (l != null) await _store.hardDeleteNote(r.id);
        continue;
      }
      if (l == null || r.updatedAt.isAfter(l.updatedAt)) {
        await _store.upsertNote(r);
      }
    }

    final toPush = <NoteRecord>[];
    for (final l in localAll) {
      final r = remoteById[l.id];
      if (r == null || l.updatedAt.isAfter(r.updatedAt)) toPush.add(l);
    }
    await sync.pushNotes(toPush);

    _notes = await _store.loadNotes();
  }

  /// 元数据合并：自建单词本按 id 取并集（本地内容优先）
  Future<void> _syncMeta(CloudSync sync) async {
    final remoteMeta = await sync.pullMeta();
    final push = <String, String>{};

    // 旧版本存过「收藏」，功能已下线，顺手清掉云端残留
    if (remoteMeta.containsKey('favorites')) {
      try {
        await sync.deleteMeta('favorites');
      } catch (_) {
        // 清理失败不影响本次同步
      }
    }

    // 旧版扁平自建词：包装成「我的单词本」
    var remoteBooks = _decodeBooks(remoteMeta['custom_books']);
    final legacy = _decodeList(remoteMeta['custom_words']);
    if (remoteBooks.isEmpty && legacy.isNotEmpty) {
      remoteBooks = [
        CustomWordBook(
          id: 'legacy',
          name: '我的单词本',
          createdAt: DateTime.now(),
          words: legacy.map(CustomWordEntry.fromJson).toList(),
        ),
      ];
    }

    final remoteById = {for (final b in remoteBooks) b.id: b};
    final localById = {for (final b in _customBooks) b.id: b};
    final merged = {...remoteById, ...localById};

    // 云端有本地没有的单词本 → 落到本地
    if (remoteById.keys.any((k) => !localById.containsKey(k))) {
      _customBooks = merged.values.toList();
      await _store.saveCustomBooks(_booksData());
    }
    // 本地新增/改过的单词本 → 推上去
    final changed = localById.entries.any((e) {
      final r = remoteById[e.key];
      return r == null ||
          jsonEncode(r.toJson()) != jsonEncode(e.value.toJson());
    });
    if (changed || remoteMeta.containsKey('custom_words')) {
      push['custom_books'] = jsonEncode(_booksData(merged.values));
    }

    // 易混词组：与词书一致，按 id 取并集、本地优先
    final remoteGroups = _decodeGroups(remoteMeta['confusable_groups']);
    final remoteGroupById = {for (final g in remoteGroups) g.id: g};
    final localGroupById = {for (final g in _groups) g.id: g};
    final mergedGroups = {...remoteGroupById, ...localGroupById};

    if (remoteGroupById.keys.any((k) => !localGroupById.containsKey(k))) {
      _groups = mergedGroups.values.toList();
      await _store.saveConfusableGroups(_groupsData());
    }
    final groupsChanged = localGroupById.entries.any((e) {
      final r = remoteGroupById[e.key];
      return r == null ||
          jsonEncode(r.toJson()) != jsonEncode(e.value.toJson());
    });
    if (groupsChanged) {
      push['confusable_groups'] = jsonEncode(_groupsData(mergedGroups.values));
    }

    if (push.isNotEmpty) await sync.pushMeta(push);
    if (remoteMeta.containsKey('custom_words')) {
      try {
        await sync.deleteMeta('custom_words');
      } catch (_) {
        // 清理失败不影响本次同步
      }
    }
  }

  List<Map<String, dynamic>> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  List<CustomWordBook> _decodeBooks(String? raw) => _decodeList(raw)
      .map(CustomWordBook.fromJson)
      .where((b) => b.id.isNotEmpty)
      .toList();

  List<ConfusableGroup> _decodeGroups(String? raw) => _decodeList(raw)
      .map(ConfusableGroup.fromJson)
      .where((g) => g.id.isNotEmpty && g.wordKeys.length >= 2)
      .toList();

  String _booksJson() => jsonEncode(_booksData());

  List<Map<String, dynamic>> _booksData([Iterable<CustomWordBook>? books]) =>
      (books ?? _customBooks).map((b) => b.toJson()).toList();

  /// 单条元数据推送
  Future<void> _pushMetaValue(String key, String value) async {
    final sync = _sync;
    if (sync == null) return;
    try {
      await sync.pushMeta({key: value});
      _lastSyncedAt = DateTime.now();
      _syncError = null;
    } catch (e) {
      _syncError = e is SyncException ? e.message : '$e';
    }
    notifyListeners();
  }

  /// 单条笔记推送
  Future<void> _pushNote(NoteRecord note) async {
    final sync = _sync;
    if (sync == null) return;
    try {
      await sync.pushNotes([note]);
      _lastSyncedAt = DateTime.now();
      _syncError = null;
    } catch (e) {
      _syncError = e is SyncException ? e.message : '$e';
    }
    notifyListeners();
  }

  /// 单条推送（评分后调用，失败不影响本地记录）
  Future<void> _pushOne(String wordKey, ReviewState s) async {
    final sync = _sync;
    if (sync == null) return;
    try {
      await sync.pushReviewState(wordKey, s);
      _lastSyncedAt = DateTime.now();
      _syncError = null;
    } catch (e) {
      _syncError = e is SyncException ? e.message : '$e';
    }
    notifyListeners();
  }

  /// 当前词池：只来自自建单词本，按单词去重
  List<Word> get pool {
    final seen = <String>{};
    final out = <Word>[];
    for (final e in customWords) {
      if (seen.add(e.key)) out.add(e.word);
    }
    return List.unmodifiable(out);
  }

  /// 查词：只在自建单词本里找
  Word? findWord(String key) {
    final k = key.toLowerCase();
    for (final b in _customBooks) {
      for (final e in b.words) {
        if (e.key == k) return e.word;
      }
    }
    return null;
  }

  /// 今日队列：到期复习 + 新词，并把易混组同伴紧接插入。
  ///
  /// 关联插入占用本轮上限（`dueLimit + newLimit`），从尾部挤占新词，
  /// 不额外加长队列，也不链式触发其他组。
  ConfusableRound buildTodayQueue({int newLimit = 20, int dueLimit = 20}) {
    final dueKeys =
        _states.entries.where((e) => e.value.isDue).map((e) => e.key).toSet();
    final seen = _states.keys.toSet();
    final dueWords = <Word>[];
    for (final w in pool) {
      if (!dueKeys.contains(w.key)) continue;
      dueWords.add(w);
      // 到期词分批，避免积压后一轮上百个
      if (dueWords.length >= dueLimit) break;
    }
    final fresh = <Word>[];
    for (final w in pool) {
      if (seen.contains(w.key)) continue;
      fresh.add(w);
      if (fresh.length >= newLimit) break;
    }
    return buildConfusableRound(
      dueWords: dueWords,
      freshWords: fresh,
      groups: _groups,
      poolByKey: {for (final w in pool) w.key: w},
      maxLength: dueLimit + newLimit,
    );
  }

  Future<ReviewState> grade(Word word, ReviewGrade g) async {
    final isNew = !_states.containsKey(word.key);
    final cur = _states[word.key] ?? ReviewState.initial();
    final next = SrsEngine.next(
      cur,
      g,
      algorithm:
          _settings.useFsrs ? SrsAlgorithm.fsrs : SrsAlgorithm.sm2,
    );
    _states[word.key] = next;
    await _store.upsert(word.key, next);

    // 记一次学习（用于统计与连续天数）
    final key = dayKey(DateTime.now());
    await _store.recordStudy(key, isNewWord: isNew);
    _daily = await _store.loadDaily();

    notifyListeners();
    unawaited(_pushOne(word.key, next));
    return next;
  }

  // ── 笔记 ──

  Future<void> addNote(
    String content, {
    String title = '',
    List<String> tags = const [],
  }) async {
    final text = content.trim();
    final heading = title.trim();
    if (text.isEmpty && heading.isEmpty) return;
    final note = await _store.addNote(
      '',
      text,
      title: heading,
      tags: _cleanTags(tags),
    );
    _notes = await _store.loadNotes();
    notifyListeners();
    unawaited(_pushNote(note));
  }

  Future<void> updateNote(
    String id,
    String content, {
    String? title,
    List<String>? tags,
  }) async {
    final text = content.trim();
    final heading = title?.trim();
    if (text.isEmpty && (heading == null || heading.isEmpty)) return;
    await _store.updateNote(
      id,
      text,
      title: heading,
      tags: tags == null ? null : _cleanTags(tags),
    );
    _notes = await _store.loadNotes();
    notifyListeners();

    final all = await _store.loadAllNotes();
    for (final n in all) {
      if (n.id == id) {
        unawaited(_pushNote(n));
        break;
      }
    }
  }

  List<String> _cleanTags(List<String> tags) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in tags) {
      final tag = raw.trim().replaceFirst(RegExp(r'^#'), '');
      if (tag.isNotEmpty && seen.add(tag)) out.add(tag);
    }
    return out;
  }

  List<WordSense> _cleanSenses(List<WordSense> senses) => [
        for (final s in senses)
          if (s.cn.trim().isNotEmpty || s.en.trim().isNotEmpty)
            WordSense(
              pos: s.pos.trim(),
              cn: s.cn.trim(),
              en: s.en.trim(),
            ),
      ];

  Future<void> deleteNote(String id) async {
    await _store.deleteNote(id);
    _notes = await _store.loadNotes();
    notifyListeners();

    final all = await _store.loadAllNotes();
    for (final n in all) {
      if (n.id == id) {
        unawaited(_pushNote(n));
        break;
      }
    }
  }

  // ── 自建单词本 ──

  /// 新建一本单词本
  Future<CustomWordBook> createCustomBook(String name) async {
    final text = name.trim();
    final book = CustomWordBook(
      id: const Uuid().v4(),
      name: text.isEmpty ? '未命名单词本' : text,
      createdAt: DateTime.now(),
    );
    _customBooks = [..._customBooks, book];
    await _persistBooks();
    return book;
  }

  /// 重命名；失败时返回提示文案
  Future<String?> renameCustomBook(String id, String name) async {
    final text = name.trim();
    if (text.isEmpty) return '名称不能为空';
    _customBooks = [
      for (final b in _customBooks) b.id == id ? b.copyWith(name: text) : b,
    ];
    await _persistBooks();
    return null;
  }

  Future<void> deleteCustomBook(String id) async {
    final removedKeys = [
      for (final b in _customBooks)
        if (b.id == id) ...b.words.map((e) => e.key),
    ];
    _customBooks = [
      for (final b in _customBooks)
        if (b.id != id) b,
    ];
    await _persistBooks();

    // 只清理已不在其他单词本里的词的复习状态
    for (final key in removedKeys) {
      if (findWord(key) == null && _states.remove(key) != null) {
        await _store.deleteState(key);
      }
    }
    await _pruneConfusableGroups();
    notifyListeners();
  }

  /// 粘贴文本导入某本单词本，返回明细（新增 / 重复累加 / 无法识别）
  Future<CustomWordParseResult> importWordsToBook(
    String bookId,
    String text,
  ) async {
    final book = bookById(bookId);
    if (book == null) return const CustomWordParseResult();

    final result = parseCustomWordsDetailed(
      text,
      repeatable: book.words.map((e) => e.key).toSet(),
    );
    if (result.added.isEmpty && result.repeated.isEmpty) return result;

    final now = DateTime.now();
    final nextWords = <CustomWordEntry>[
      for (final e in book.words)
        if ((result.repeated[e.key] ?? 0) > 0)
          e.copyWith(addCount: e.addCount + result.repeated[e.key]!)
        else
          e,
      for (final w in result.added) CustomWordEntry(word: w, addedAt: now),
    ];
    _replaceBook(book.copyWith(words: nextWords));
    await _persistBooks();
    return result;
  }

  /// 手动添加一个词；失败时返回提示文案
  Future<String?> addWordToBook(
    String bookId, {
    required String word,
    required List<WordSense> senses,
    String phonetic = '',
  }) async {
    final book = bookById(bookId);
    if (book == null) return '单词本不存在';

    final text = word.trim();
    if (text.isEmpty) return '单词不能为空';
    final key = text.toLowerCase();
    if (findWord(key) != null) return '「$text」已在单词本中';

    final defs = _cleanSenses(senses);
    final ph = phonetic.trim();
    final entry = CustomWordEntry(
      word: Word(
        w: text,
        uk: ph,
        defs: defs,
        tags: const ['custom'],
      ),
      addedAt: DateTime.now(),
    );
    _replaceBook(book.copyWith(words: [...book.words, entry]));
    await _persistBooks();
    return null;
  }

  /// 修改某个词的词形、音标与释义；失败时返回提示文案
  Future<String?> updateWordInBook(
    String bookId,
    CustomWordEntry entry, {
    required String word,
    required List<WordSense> senses,
    String phonetic = '',
  }) async {
    final book = bookById(bookId);
    if (book == null) return '单词本不存在';

    final text = word.trim();
    if (text.isEmpty) return '单词不能为空';
    final key = text.toLowerCase();
    if (key != entry.key && findWord(key) != null) return '「$text」已存在';

    final updated = Word(
      w: text,
      uk: phonetic.trim(),
      us: entry.word.us,
      defs: _cleanSenses(senses),
      tags: entry.word.tags,
    );
    _replaceBook(book.copyWith(words: [
      for (final e in book.words)
        if (e.key == entry.key) entry.copyWith(word: updated) else e,
    ]));
    await _persistBooks();
    return null;
  }

  Future<void> removeWordFromBook(String bookId, String key) async {
    final book = bookById(bookId);
    if (book == null) return;
    final k = key.toLowerCase();
    final nextWords = [
      for (final e in book.words)
        if (e.key != k) e,
    ];
    _replaceBook(book.copyWith(words: nextWords));
    await _persistBooks();

    // 该词若已不在任何单词本中，清掉本地复习状态（云端残留不影响使用）
    if (findWord(k) == null) {
      _states.remove(k);
      await _store.deleteState(k);
      notifyListeners();
    }
    await _pruneConfusableGroups();
  }

  void _replaceBook(CustomWordBook book) {
    _customBooks = [
      for (final b in _customBooks) b.id == book.id ? book : b,
    ];
  }

  Future<void> _persistBooks() async {
    await _store.saveCustomBooks(_booksData());
    notifyListeners();
    unawaited(_pushMetaValue('custom_books', _booksJson()));
  }

  // ── 易混词组 ──

  ConfusableGroup? confusableGroupById(String id) {
    for (final g in _groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// 新建或修改易混词组；失败时返回提示文案。
  ///
  /// [wordKeys] 必须是词池里存在的 2–4 个词；[name] 留空时自动用词形拼接。
  Future<String?> saveConfusableGroup({
    String? id,
    required String name,
    required List<String> wordKeys,
  }) async {
    final keys = <String>[];
    for (final raw in wordKeys) {
      final key = raw.trim().toLowerCase();
      if (key.isNotEmpty && !keys.contains(key)) keys.add(key);
    }
    if (keys.length < 2) return '至少选择 2 个词';
    if (keys.length > 4) return '最多选择 4 个词';
    for (final key in keys) {
      if (findWord(key) == null) return '「$key」不在单词本中';
    }

    final text = name.trim();
    final display = text.isNotEmpty
        ? text
        : keys.map((k) => findWord(k)?.w ?? k).join(' / ');

    if (id == null || confusableGroupById(id) == null) {
      _groups = [
        ..._groups,
        ConfusableGroup(
          id: const Uuid().v4(),
          name: display,
          wordKeys: keys,
          createdAt: DateTime.now(),
        ),
      ];
    } else {
      _groups = [
        for (final g in _groups)
          g.id == id ? g.copyWith(name: display, wordKeys: keys) : g,
      ];
    }
    await _persistGroups();
    return null;
  }

  Future<void> deleteConfusableGroup(String id) async {
    _groups = [
      for (final g in _groups)
        if (g.id != id) g,
    ];
    await _persistGroups();
  }

  /// 词条被删除后清理分组引用；不足 2 个有效词的组直接丢弃
  Future<void> _pruneConfusableGroups() async {
    final valid = {for (final w in pool) w.key};
    var changed = false;
    final next = <ConfusableGroup>[];
    for (final g in _groups) {
      final keys = [
        for (final k in g.wordKeys)
          if (valid.contains(k)) k,
      ];
      if (keys.length == g.wordKeys.length) {
        next.add(g);
        continue;
      }
      changed = true;
      if (keys.length >= 2) next.add(g.copyWith(wordKeys: keys));
    }
    if (!changed) return;
    _groups = next;
    await _persistGroups();
  }

  List<Map<String, dynamic>> _groupsData([Iterable<ConfusableGroup>? groups]) =>
      (groups ?? _groups).map((g) => g.toJson()).toList();

  Future<void> _persistGroups() async {
    await _store.saveConfusableGroups(_groupsData());
    notifyListeners();
    unawaited(
      _pushMetaValue('confusable_groups', jsonEncode(_groupsData())),
    );
  }

  /// 清空全部数据：本机 + 云端（不可撤销）
  Future<void> resetAll() async {
    await _store.clearAll();
    _states = {};
    _notes = [];
    _customBooks = [];
    _groups = [];
    _daily = [];
    notifyListeners();

    final sync = _sync;
    if (sync != null) {
      try {
        await sync.wipeAll();
        _lastSyncedAt = DateTime.now();
        _syncError = null;
      } catch (e) {
        _syncError = e is SyncException ? e.message : '$e';
      }
      notifyListeners();
    }
  }
}
