/// 导出落盘（按平台条件导出）
///
/// - 桌面 / 移动：写入临时文件后调起系统分享
/// - Web：浏览器下载
library;

export 'export_stub.dart'
    if (dart.library.io) 'export_native.dart'
    if (dart.library.js_interop) 'export_web.dart';
