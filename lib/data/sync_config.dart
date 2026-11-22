/// 云端同步配置
///
/// 默认不启用，仓库里不内置任何云端地址与密钥。
/// 需要多端同步时，用自己的环境重新构建：
///
/// ```bash
/// flutter build apk --release \
///   --dart-define=SYNC_ENABLED=true \
///   --dart-define=SYNC_ENV_ID=<环境ID> \
///   --dart-define=SYNC_API_KEY=<Publishable Key> \
///   --dart-define=SYNC_USER_ID=<自定义标识>
/// ```
///
/// 只放 Publishable（anon）Key；service_role 等私钥绝不能打进客户端。
library;

class SyncConfig {
  /// 是否启用云同步（默认关闭，纯本地运行）
  static const bool enabled =
      bool.fromEnvironment('SYNC_ENABLED', defaultValue: false);

  /// 云开发环境 ID
  static const String envId =
      String.fromEnvironment('SYNC_ENV_ID', defaultValue: '');

  /// Publishable Key（anon 角色）
  static const String apiKey =
      String.fromEnvironment('SYNC_API_KEY', defaultValue: '');

  /// 用户标识：同一标识的多台设备互通；不同人务必用不同值
  static const String userId =
      String.fromEnvironment('SYNC_USER_ID', defaultValue: 'me');

  /// 设备标识（仅用于网关统计，不参与鉴权）
  static const String deviceId =
      String.fromEnvironment('SYNC_DEVICE_ID', defaultValue: 'es-app');

  /// 三项配置齐全才真正启用，避免半配置时发出无效请求
  static bool get active => enabled && envId.isNotEmpty && apiKey.isNotEmpty;

  static String get baseUrl =>
      'https://$envId.api.tcloudbasegateway.com/v1/rdb/rest';
}
