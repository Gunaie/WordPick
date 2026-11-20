import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 生成导出文件并调起系统分享；分享不可用时退回应用文档目录
Future<String> saveExport({
  required String fileName,
  required String content,
  required String mimeType,
}) async {
  try {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(content);
    await Share.shareXFiles([
      XFile(file.path, mimeType: mimeType, name: fileName),
    ], subject: fileName);
    return '已导出 $fileName';
  } catch (_) {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(content);
    return '已保存到 ${file.path}';
  }
}
