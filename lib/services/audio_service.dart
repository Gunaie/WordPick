/// 发音播放服务
///
/// 音频来源：有道 dictvoice（实测约 50-100ms，英美双音）
/// - type=0 美音
/// - type=1 英音
library;

import 'package:audioplayers/audioplayers.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();

  /// 当前默认发音口音（true = 英音）
  bool isUk = true;

  static String urlFor(String word, {required bool uk}) {
    final type = uk ? 1 : 0;
    return 'https://dict.youdao.com/dictvoice?type=$type&audio=${Uri.encodeComponent(word)}';
  }

  Future<void> play(String word, {bool? uk}) async {
    if (word.trim().isEmpty) return;
    final useUk = uk ?? isUk;
    try {
      await _player.stop();
      await _player.play(UrlSource(urlFor(word, uk: useUk)));
    } catch (_) {
      // 播放失败静默处理：不影响学习流程
    }
  }

  Future<void> dispose() => _player.dispose();
}
