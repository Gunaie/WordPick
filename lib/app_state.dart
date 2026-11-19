/// 应用全局状态（ChangeNotifier）
///
/// 说明：本迭代用最简单的 ChangeNotifier + ListenableBuilder。
/// 待核心流程稳定后，再评估是否引入 Riverpod（见 docs/decisions.md D08 / D12）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'data/affix_repository.dart';
import 'data/cloud_sync.dart';
import 'data/daily_stat.dart';
import 'data/progress_store.dart';
import 'data/sync_config.dart';
import 'data/word_repository.dart';
import 'domain/custom_word_parser.dart';
import 'domain/srs.dart';
import 'domain/word.dart';

class AppState extends ChangeNotifier {
  final WordRepository repo = WordRepository();
  final AffixRepository affixes = AffixRepository();
  late ProgressStore _store;

  Map<String, ReviewState> _states = {};
  List<Word> _customWords = [];
  Set<String> _favorites = {};
  List<NoteRecord> _notes = [];
  List<DailyStat> _daily = [];

  String? _examTag; // null = 全部
  bool _ready = false;
  String? _error;

  // ── 云同步状态 ──
  final CloudSync? _sync = SyncConfig.enabled ? CloudSync() : null;
  bool _syncing = false;
  String? _syncError;
  DateTime? _lastSyncedAt;

  bool get isReady => _ready;
  String? get error => _error;
  String? get examTag => _examTag;
  ProgressStore get store => _store;

  bool get syncEnabled => _sync != null;
  bool get syncing => _syncing;
  String? get syncError => _syncError;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  Map<String, ReviewState> get states => Map.unmodifiable(_states);
  List<Word> get customWords => List.unmodifiable(_customWords);
  Set<String> get favorites => Set.unmodifiable(_favorites);
  List<NoteRecord> get notes => List.unmodifiable(_notes);

  int get learnedCount => _states.length;
  int get dueCount => _states.values.where((s) => s.isDue).length;
  int get scheduledCount => _states.length - dueCount;

  /// 熟记：复习间隔 ≥ 21 天（SM-2 常用阈值）
  int get masteredCount =>
      _states.values.where((s) => s.interval >= 21).length;

  List<DailyStat> get dailyStats => List.unmodifiable(_daily);

  int get streakDays => streakOf(_daily);

  /// 当前筛选下可用的考试练习题数量
  int get quizQuestionCount {
    var n = 0;
    for (final w in pool) {
      n += w.quiz.length;
    }
    return n;
  }

  int get todayReviews {
    final key = dayKey(DateTime.now());
    for (final d in _daily) {
      if (d.date == key) return d.reviews;
    }
    return 0;
  }

  /// 错题：曾经遗忘过的词（lapses > 0）
  List<String> get mistakeKeys => _states.entries
      .where((e) => e.value.lapses > 0)
      .map((e) => e.key)
      .toList();

  /// 某词累计遗忘次数（未学过返回 0）
  int lapsesFor(String key) => _states[key]?.lapses ?? 0;

  Future<void> init() async {
    try {
      _store = await createProgressStore();
      await repo.load();
      await affixes.load();
      _states = await _store.loadAll();
      _favorites = await _store.loadFavorites();
      _notes = await _store.loadNotes();
      _daily = await _store.loadDaily();
      final rawCustom = await _store.loadCustomWords();
      _customWords = rawCustom.map((j) => Word.fromJson(j)).toList();
      _ready = true;
    } catch (e) {
      _error = '$e';
    } finally {
      notifyListeners();
    }

    // 启动后后台拉一次云端数据（不阻塞首屏）
    if (_error == null) unawaited(syncNow());
  }

  /// 全量同步：先拉远端，按 updated_at 合并，再把本地更新的推上去
  Future<void> syncNow() async {
    final sync = _sync;
    if (sync == null || _syncing) return;

    _syncing = true;
    _syncError = null;
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

  /// 元数据合并：收藏取并集，自建词按词形取并集（本地优先）
  Future<void> _syncMeta(CloudSync sync) async {
    final remoteMeta = await sync.pullMeta();
    final push = <String, String>{};

    // 收藏
    final remoteFav = _decodeStringSet(remoteMeta['favorites']);
    final mergedFav = {..._favorites, ...remoteFav};
    if (mergedFav.length != _favorites.length ||
        !mergedFav.containsAll(_favorites)) {
      _favorites = mergedFav;
      await _store.saveFavorites(_favorites);
    }
    if (mergedFav.length != remoteFav.length ||
        !mergedFav.containsAll(remoteFav)) {
      push['favorites'] = jsonEncode(mergedFav.toList());
    }

    // 自建词：按小写词形去重，本地内容优先
    final remoteCustom = _decodeCustom(remoteMeta['custom_words']);
    final merged = <String, Map<String, dynamic>>{
      for (final w in remoteCustom)
        (w['w'] ?? '').toString().toLowerCase(): w,
    };
    for (final w in _customWords) {
      merged[w.key] = _toJson(w);
    }
    if (merged.length != remoteCustom.length) {
      final list = merged.values.toList();
      await _store.saveCustomWords(list);
      _customWords = list.map((j) => Word.fromJson(j)).toList();
    }
    if (merged.length != _customWords.length ||
        remoteCustom.length != merged.length) {
      push['custom_words'] = jsonEncode(merged.values.toList());
    }

    if (push.isNotEmpty) await sync.pushMeta(push);
  }

  Set<String> _decodeStringSet(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  List<Map<String, dynamic>> _decodeCustom(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

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

  void setExamTag(String? tag) {
    if (_examTag == tag) return;
    _examTag = tag;
    notifyListeners();
  }

  /// 当前词池：内置词库（按考试筛选）+ 自建词
  List<Word> get pool {
    final base = _examTag == null ? repo.all : repo.byTag(_examTag!);
    return [..._customWords, ...base];
  }

  /// 查词：优先自建词，其次内置词库
  Word? findWord(String key) {
    final k = key.toLowerCase();
    for (final w in _customWords) {
      if (w.key == k) return w;
    }
    return repo.byKey(k);
  }

  /// 今日队列：到期复习 + 新词
  List<Word> buildTodayQueue({int newLimit = 20}) {
    final dueKeys =
        _states.entries.where((e) => e.value.isDue).map((e) => e.key).toSet();
    final seen = _states.keys.toSet();
    final dueWords = <Word>[];
    for (final w in pool) {
      if (dueKeys.contains(w.key)) dueWords.add(w);
    }
    final fresh = <Word>[];
    for (final w in pool) {
      if (seen.contains(w.key)) continue;
      fresh.add(w);
      if (fresh.length >= newLimit) break;
    }
    return [...dueWords, ...fresh];
  }

  Future<ReviewState> grade(Word word, ReviewGrade g) async {
    final isNew = !_states.containsKey(word.key);
    final cur = _states[word.key] ?? ReviewState.initial();
    final next = SrsEngine.next(cur, g);
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

  // ── 收藏 ──

  bool isFavorite(Word word) => _favorites.contains(word.key);

  Future<void> toggleFavorite(Word word) async {
    if (_favorites.contains(word.key)) {
      _favorites.remove(word.key);
    } else {
      _favorites.add(word.key);
    }
    await _store.saveFavorites(_favorites);
    notifyListeners();
    unawaited(_pushMetaValue('favorites', jsonEncode(_favorites.toList())));
  }

  List<Word> get favoriteWords =>
      _favorites.map((k) => findWord(k)).whereType<Word>().toList();

  // ── 笔记 ──

  List<NoteRecord> notesFor(String wordKey) =>
      _notes.where((n) => n.wordKey == wordKey).toList();

  Future<void> addNote(Word word, String content) async {
    final text = content.trim();
    if (text.isEmpty) return;
    final note = await _store.addNote(word.key, text);
    _notes = await _store.loadNotes();
    notifyListeners();
    unawaited(_pushNote(note));
  }

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

  // ── 错题 ──

  List<Word> get mistakeWords {
    final list =
        mistakeKeys.map((k) => findWord(k)).whereType<Word>().toList();
    // 遗忘次数多的排前，同级按词形排序，便于优先攻克最薄弱的词
    list.sort((a, b) {
      final la = lapsesFor(a.key);
      final lb = lapsesFor(b.key);
      if (lb != la) return lb.compareTo(la);
      return a.w.compareTo(b.w);
    });
    return list;
  }

  Future<void> removeFromMistakes(Word word) async {
    final cur = _states[word.key];
    if (cur == null) return;
    final next = ReviewState(
      ease: cur.ease,
      interval: cur.interval,
      reps: cur.reps,
      lapses: 0,
      due: cur.due,
      updatedAt: DateTime.now(),
    );
    _states[word.key] = next;
    await _store.upsert(word.key, next);
    notifyListeners();
    unawaited(_pushOne(word.key, next));
  }

  // ── 自建词库 ──

  /// 解析粘贴的文本并导入自建词库，返回明细（新增 / 已存在 / 无法识别）
  Future<CustomWordParseResult> importCustomWords(String text) async {
    final exclude = <String>{
      ..._customWords.map((w) => w.key),
      ...repo.all.map((w) => w.key),
    };
    final result = parseCustomWordsDetailed(text, exclude: exclude);
    if (result.added.isEmpty) return result;

    _customWords.addAll(result.added);
    await _store.saveCustomWords(_customWords.map(_toJson).toList());
    notifyListeners();
    unawaited(
      _pushMetaValue(
        'custom_words',
        jsonEncode(_customWords.map(_toJson).toList()),
      ),
    );
    return result;
  }

  Future<void> removeCustomWord(Word word) async {
    _customWords.removeWhere((w) => w.key == word.key);
    await _store.saveCustomWords(_customWords.map(_toJson).toList());
    notifyListeners();
    unawaited(
      _pushMetaValue(
        'custom_words',
        jsonEncode(_customWords.map(_toJson).toList()),
      ),
    );
  }

  /// 清空全部数据：本机 + 云端（不可撤销）
  Future<void> resetAll() async {
    await _store.clearAll();
    _states = {};
    _notes = [];
    _favorites = {};
    _customWords = [];
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

  Map<String, dynamic> _toJson(Word w) => {
        'w': w.w,
        'uk': w.uk,
        'us': w.us,
        'defs': w.defs.map((d) => {'pos': d.pos, 'cn': d.cn, 'en': d.en}).toList(),
        'tags': w.tags,
      };
}
