/// 同步配置的本地持久化（BYOC）
///
/// 用 shared_preferences：原生端走各平台 KV，Web 端走 localStorage。
/// 存的是 Publishable（anon）Key，不是高价值密钥，故不额外加密；
/// 真正隔离靠「每人用自己的 CloudBase 环境」，而不是靠藏 Key。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'sync_config.dart';

class SyncConfigStore {
  static const _key = 'sync_config_v1';

  final SharedPreferences _prefs;

  SyncConfigStore(this._prefs);

  /// 打开（或复用）SharedPreferences 实例
  static Future<SyncConfigStore> open() async =>
      SyncConfigStore(await SharedPreferences.getInstance());

  /// 读取本地保存的配置；从未配置过返回 [SyncConfig.empty]
  SyncConfig load() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return SyncConfig.empty;
    try {
      return SyncConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // 损坏的配置直接丢弃，按未配置处理，避免启动卡死
      return SyncConfig.empty;
    }
  }

  Future<void> save(SyncConfig config) =>
      _prefs.setString(_key, jsonEncode(config.toJson()));

  /// 清除配置（断开同步时调用）
  Future<void> clear() => _prefs.remove(_key);
}
