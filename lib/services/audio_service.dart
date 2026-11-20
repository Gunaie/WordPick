/// 发音播放服务
///
/// 音频来源：有道 dictvoice（实测约 50-100ms，英美双音）
/// - type=0 美音
/// - type=1 英音
///
/// 播放顺序：本地缓存 → 下载并缓存 → 在线播放 → 设备 TTS 兜底
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'audio_cache.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();
  FlutterTts? _tts;

  /// 当前默认发音口音（true = 英音），由 AppState 在启动与修改设置时写入
  static bool isUk = true;

  static String urlFor(String word, {required bool uk}) {
    final type = uk ? 1 : 0;
    return 'https://dict.youdao.com/dictvoice?type=$type&audio=${Uri.encodeComponent(word)}';
  }

  /// 缓存键：word_type.mp3（非字母数字折叠为下划线）
  static String cacheKey(String word, {required bool uk}) {
    final safe = word.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9-]+'),
      '_',
    );
    return '${safe}_${uk ? 1 : 0}.mp3';
  }

  Future<void> play(String word, {bool? uk}) async {
    final text = word.trim();
    if (text.isEmpty) return;
    final useUk = uk ?? isUk;
    final key = cacheKey(text, uk: useUk);
    final url = urlFor(text, uk: useUk);

    // 1. 缓存命中直接播放
    try {
      await _player.stop();
      final cached = await audioCache.pathFor(key);
      if (cached != null) {
        await _player.play(DeviceFileSource(cached));
        return;
      }
    } catch (_) {
      // 缓存异常时继续走网络
    }

    // 2. 首次播放：先下载落盘，再播本地文件
    if (await audioCache.download(url, key)) {
      final path = await audioCache.pathFor(key);
      if (path != null) {
        try {
          await _player.play(DeviceFileSource(path));
          return;
        } catch (_) {
          // 本地文件播放失败，回退在线播放
        }
      }
    }

    // 3. 在线播放
    try {
      await _player.play(UrlSource(url));
    } catch (_) {
      // 4. 网络失败 → 设备 TTS
      await _speak(text, useUk);
    }
  }

  Future<void> _speak(String word, bool uk) async {
    try {
      final tts = _tts ??= FlutterTts();
      await tts.setLanguage(uk ? 'en-GB' : 'en-US');
      await tts.setSpeechRate(0.45);
      await tts.speak(word);
    } catch (_) {
      // TTS 不可用时静默，不影响学习流程
    }
  }

  Future<void> dispose() async {
    await _player.dispose();
    await _tts?.stop();
  }
}
