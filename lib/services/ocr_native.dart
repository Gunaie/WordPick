/// 拍照识别：Android / iOS 端上离线识别
///
/// 使用 ML Kit 中文模型（同时可识别拉丁字母），模型随包，无需联网。
/// 其它原生平台（桌面）没有实现，统一返回不支持。
library;

import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'ocr_types.dart';

/// 当前平台是否支持拍照识别
bool get ocrSupported => Platform.isAndroid || Platform.isIOS;

final ImagePicker _picker = ImagePicker();

/// 取一张图，返回本地临时文件路径；用户取消时返回 null
Future<String?> pickImageForOcr(OcrSource source) async {
  final file = await _picker.pickImage(
    source: source == OcrSource.camera ? ImageSource.camera : ImageSource.gallery,
    // 手写本照片压缩到够识别即可，避免大图拖慢端上推理
    maxWidth: 2400,
    imageQuality: 92,
  );
  return file?.path;
}

/// 识别图片中的文字，按 OCR 原始行返回（含换行）
Future<String> recognizeOcrText(String imagePath) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
  try {
    final result = await recognizer.processImage(
      InputImage.fromFilePath(imagePath),
    );
    return result.text;
  } finally {
    await recognizer.close();
  }
}
