/// 学习进度存储接口（按平台条件导出）
///
/// - 桌面/移动（dart:io）：SQLite 持久化
/// - Web：localStorage 持久化
library;

export 'note_record.dart';
export 'progress_store_stub.dart'
    if (dart.library.io) 'progress_store_native.dart'
    if (dart.library.js_interop) 'progress_store_web.dart';
