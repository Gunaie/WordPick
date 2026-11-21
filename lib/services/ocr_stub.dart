/// 拍照识别：Web 等平台不支持时的空实现
library;

import 'ocr_types.dart';

/// 当前平台是否支持拍照识别
bool get ocrSupported => false;

/// 取一张图；不支持时返回 null
Future<String?> pickImageForOcr(OcrSource source) async => null;

/// 识别图片中的文字；不支持时抛出异常
Future<String> recognizeOcrText(String imagePath) async {
  throw UnsupportedError('当前平台不支持拍照识别');
}
