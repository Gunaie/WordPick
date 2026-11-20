import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// 通过 Blob + 临时链接触发浏览器下载
Future<String> saveExport({
  required String fileName,
  required String content,
  required String mimeType,
}) async {
  final blob = web.Blob(
    <JSAny>[content.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName;
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  // 立即 revoke 在部分浏览器会取消下载，延后释放
  await Future<void>.delayed(const Duration(seconds: 1));
  web.URL.revokeObjectURL(url);
  return '已开始下载 $fileName';
}
