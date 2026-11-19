/// 云端同步：直接调用 CloudBase 的 PostgREST 接口
///
/// 为什么不依赖 CloudBase SDK：
///   1. SDK 会引入 shared_preferences 等额外插件，增加构建复杂度；
///   2. 我们只需要 3 张表的增删改查，PostgREST 足够；
///   3. 直连 HTTP 在 Web / 桌面 / 移动端行为完全一致。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/srs.dart';
import 'note_record.dart';
import 'sync_config.dart';

class SyncException implements Exception {
  final String message;
  final int? statusCode;
  const SyncException(this.message, [this.statusCode]);
  @override
  String toString() => 'SyncException($statusCode): $message';
}

class CloudSync {
  final http.Client _client;

  /// 仅供测试：覆盖密钥（默认使用 [SyncConfig.apiKey]）
  final String? apiKeyOverride;

  CloudSync({http.Client? client, this.apiKeyOverride})
      : _client = client ?? http.Client();

  static const _timeout = Duration(seconds: 12);

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${apiKeyOverride ?? SyncConfig.apiKey}',
        'Content-Type': 'application/json',
        'x-device-id': SyncConfig.deviceId,
        // 冲突时按主键合并（upsert）
        'Prefer': 'resolution=merge-duplicates,return=minimal',
      };

  Uri _uri(String table, [Map<String, String>? query]) {
    final base = Uri.parse('${SyncConfig.baseUrl}/$table');
    return base.replace(queryParameters: {
      'user_id': 'eq.${SyncConfig.userId}',
      ...?query,
    });
  }

  void _ensureSuccess(http.Response r, String action) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    throw SyncException('$action 失败: ${r.body}', r.statusCode);
  }

  // ── 学习进度 ──────────────────────────────────────────

  /// 拉取全部学习状态
  Future<Map<String, ReviewState>> pullReviewStates() async {
    final r = await _client
        .get(_uri('review_state', {'select': '*'}), headers: _headers)
        .timeout(_timeout);
    _ensureSuccess(r, '拉取进度');

    final list = jsonDecode(r.body) as List<dynamic>;
    final out = <String, ReviewState>{};
    for (final item in list) {
      final m = item as Map<String, dynamic>;
      final key = m['word_key'] as String;
      out[key] = ReviewState(
        ease: (m['ease'] as num?)?.toDouble() ?? 2.5,
        interval: (m['interval'] as num?)?.toInt() ?? 0,
        reps: (m['reps'] as num?)?.toInt() ?? 0,
        lapses: (m['lapses'] as num?)?.toInt() ?? 0,
        due: DateTime.tryParse(m['due'] as String? ?? '') ?? DateTime.now(),
        updatedAt:
            DateTime.tryParse(m['updated_at'] as String? ?? '') ?? DateTime.now(),
      );
    }
    return out;
  }

  /// 批量上传学习状态
  Future<void> pushReviewStates(Map<String, ReviewState> states) async {
    if (states.isEmpty) return;
    final body = [
      for (final e in states.entries)
        {
          'user_id': SyncConfig.userId,
          'word_key': e.key,
          'ease': e.value.ease,
          'interval': e.value.interval,
          'reps': e.value.reps,
          'lapses': e.value.lapses,
          'due': e.value.due.toIso8601String(),
          'updated_at': e.value.updatedAt.toIso8601String(),
        }
    ];
    final r = await _client
        .post(_uri('review_state'), headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    _ensureSuccess(r, '上传进度');
  }

  Future<void> pushReviewState(String wordKey, ReviewState s) =>
      pushReviewStates({wordKey: s});

  // ── 笔记 ──────────────────────────────────────────────

  /// 拉取全部笔记（含已软删除，用于把删除动作同步下来）
  Future<List<NoteRecord>> pullNotes() async {
    final r = await _client
        .get(_uri('note', {'select': '*'}), headers: _headers)
        .timeout(_timeout);
    _ensureSuccess(r, '拉取笔记');

    final list = jsonDecode(r.body) as List<dynamic>;
    return [
      for (final item in list)
        NoteRecord.fromJson(item as Map<String, dynamic>)
    ];
  }

  Future<void> pushNotes(List<NoteRecord> notes) async {
    if (notes.isEmpty) return;
    final body = [
      for (final n in notes)
        {
          'id': n.id,
          'user_id': SyncConfig.userId,
          'word_key': n.wordKey,
          'content': n.content,
          'created_at': n.createdAt.toIso8601String(),
          'updated_at': n.updatedAt.toIso8601String(),
          'deleted': n.deleted,
        }
    ];
    final r = await _client
        .post(_uri('note'), headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    _ensureSuccess(r, '上传笔记');
  }

  // ── 键值数据（收藏 / 自建词 / 设置） ────────────────────

  Future<Map<String, String>> pullMeta() async {
    final r = await _client
        .get(_uri('user_meta', {'select': 'key,value'}), headers: _headers)
        .timeout(_timeout);
    _ensureSuccess(r, '拉取配置');

    final list = jsonDecode(r.body) as List<dynamic>;
    return {
      for (final item in list)
        (item as Map<String, dynamic>)['key'] as String:
            item['value'] as String
    };
  }

  Future<void> pushMeta(Map<String, String> values) async {
    if (values.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    final body = [
      for (final e in values.entries)
        {
          'user_id': SyncConfig.userId,
          'key': e.key,
          'value': e.value,
          'updated_at': now,
        }
    ];
    final r = await _client
        .post(_uri('user_meta'), headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    _ensureSuccess(r, '上传配置');
  }

  /// 清空本用户在云端的全部数据（不可撤销）
  Future<void> wipeAll() async {
    for (final table in ['review_state', 'note', 'user_meta']) {
      final r = await _client
          .delete(_uri(table), headers: _headers)
          .timeout(_timeout);
      _ensureSuccess(r, '清空 $table');
    }
  }

  void dispose() => _client.close();
}
