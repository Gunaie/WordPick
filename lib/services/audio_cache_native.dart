import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 发音缓存：mp3 落在应用缓存目录的 pronunciation/ 下
class AudioCache {
  Directory? _dir;

  Future<Directory> _ensureDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    final base = await getApplicationCacheDirectory();
    final dir = Directory(p.join(base.path, 'pronunciation'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  /// 命中返回本地文件路径
  Future<String?> pathFor(String key) async {
    try {
      final dir = await _ensureDir();
      final file = File(p.join(dir.path, key));
      return await file.exists() ? file.path : null;
    } catch (_) {
      return null;
    }
  }

  /// 下载并写入缓存；失败返回 false
  Future<bool> download(String url, String key) async {
    try {
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return false;
      final dir = await _ensureDir();
      await File(p.join(dir.path, key))
          .writeAsBytes(res.bodyBytes, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 当前缓存占用字节数
  Future<int> sizeBytes() async {
    try {
      final dir = await _ensureDir();
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is File) total += await entity.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<void> clear() async {
    try {
      final dir = await _ensureDir();
      await for (final entity in dir.list()) {
        if (entity is File) {
          try {
            await entity.delete();
          } catch (_) {
            // 单个文件删不掉不影响其余缓存清理
          }
        }
      }
    } catch (_) {
      // 缓存目录不可用时不阻塞设置页
    }
  }
}

final AudioCache audioCache = AudioCache();
