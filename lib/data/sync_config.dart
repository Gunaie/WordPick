/// 云端同步配置（BYOC：运行时由用户在设置页自填，不打进安装包）
///
/// 设计目标：
///   * 仓库与发布的 APK 都不含任何云端地址或密钥——数据默认只在本机。
///   * 每个用户用自己的 CloudBase 环境与 Publishable Key，环境之间天然隔离，
///     实现「每个人的数据存储在个人手中」。
///   * user_id 用于同一人多台设备之间互通；不同人务必用不同值（或干脆各自独立环境）。
///
/// 只放 Publishable（anon）Key；service_role 等私钥绝不能进客户端。
library;

/// 运行时同步配置。[empty] 表示未配置（纯本地运行）。
class SyncConfig {
  /// 是否启用云同步
  final bool enabled;

  /// 云开发环境 ID
  final String envId;

  /// Publishable Key（anon 角色）
  final String apiKey;

  /// 用户标识：同一标识的多台设备互通；不同人务必用不同值
  final String userId;

  /// 设备标识（仅用于网关统计，不参与鉴权）
  final String deviceId;

  const SyncConfig({
    this.enabled = false,
    this.envId = '',
    this.apiKey = '',
    this.userId = '',
    this.deviceId = 'es-app',
  });

  /// 未配置的空实例
  static const empty = SyncConfig();

  /// 启用且三项必填齐全才真正生效，避免半配置时发出无效请求
  bool get active =>
      enabled &&
      envId.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      userId.trim().isNotEmpty;

  String get baseUrl =>
      'https://${envId.trim()}.api.tcloudbasegateway.com/v1/rdb/rest';

  /// 是否填写过任一字段（用于设置页判断「已有配置」）
  bool get hasAnyField =>
      envId.isNotEmpty || apiKey.isNotEmpty || userId.isNotEmpty;

  SyncConfig copyWith({
    bool? enabled,
    String? envId,
    String? apiKey,
    String? userId,
    String? deviceId,
  }) =>
      SyncConfig(
        enabled: enabled ?? this.enabled,
        envId: envId ?? this.envId,
        apiKey: apiKey ?? this.apiKey,
        userId: userId ?? this.userId,
        deviceId: deviceId ?? this.deviceId,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'envId': envId,
        'apiKey': apiKey,
        'userId': userId,
        'deviceId': deviceId,
      };

  factory SyncConfig.fromJson(Map<String, dynamic> j) => SyncConfig(
        enabled: (j['enabled'] as bool?) ?? false,
        envId: (j['envId'] as String?) ?? '',
        apiKey: (j['apiKey'] as String?) ?? '',
        userId: (j['userId'] as String?) ?? '',
        deviceId: (j['deviceId'] as String?) ?? 'es-app',
      );
}
