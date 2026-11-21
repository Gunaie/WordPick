/// 拍照识别（按平台条件导出）
///
/// - Android / iOS：端上 ML Kit 离线识别（中文 + 拉丁手写）
/// - Web / 桌面：不支持，界面需先判断 [ocrSupported]
library;

export 'ocr_stub.dart' if (dart.library.io) 'ocr_native.dart';
export 'ocr_types.dart';
