/// 云端同步配置
///
/// 环境：腾讯云开发（PostgreSQL 模式）
/// 说明：这里放的是 Publishable Key（anon 角色，权限受限），可以随客户端分发。
///       —— 千万不要把 service_role 密钥放到这个文件里。
library;

class SyncConfig {
  /// 是否启用云同步（关掉则纯本地运行）
  static const bool enabled = true;

  /// 云开发环境 ID
  static const String envId = 'splendid-cephalopod-xxxxxxxx';

  /// Publishable Key（anon 角色）
  static const String apiKey =
      '';

  /// 用户标识：多端使用同一个值即可互通；想隔离就改成不同值
  static const String userId = 'me';

  /// 设备标识（仅用于网关统计，不参与鉴权）
  static const String deviceId = 'es-app';

  static String get baseUrl =>
      'https://$envId.api.tcloudbasegateway.com/v1/rdb/rest';
}
