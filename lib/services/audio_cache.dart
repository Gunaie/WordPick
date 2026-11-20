/// 发音缓存（按平台条件导出）
///
/// - 桌面 / 移动：文件系统缓存
/// - Web：浏览器自行管理 HTTP 缓存，不做本地落盘
library;

export 'audio_cache_stub.dart'
    if (dart.library.io) 'audio_cache_native.dart'
    if (dart.library.js_interop) 'audio_cache_web.dart';
