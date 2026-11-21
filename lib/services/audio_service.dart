/// 发音播放服务
///
/// 音频来源：有道 dictvoice（实测约 50-100ms，英美双音）
/// - type=0 美音
/// - type=1 英音
///
/// 播放顺序：本地缓存 → 下载并缓存 → 在线播放（3s 超时）→ 设备 TTS 兜底
/// 连续 3 次网络失败后熔断 60s，期间跳过网络直接走 TTS（ISSUE-001）
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'audio_cache.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();
  FlutterTts? _tts;

  /// 当前默认发音口音（true = 英音），由 AppState 在启动与修改设置时写入
  static bool isUk = true;

  // ── 超时与熔断 ──────────────────────────────────────
  // 有道 dictvoice 是非公开接口，可能无响应；在线播放必须有上限，
  // 连续失败后短期熔断，避免每个词都重复卡超时（ISSUE-001）。
  static const _onlinePlayTimeout = Duration(seconds: 3);
  static const _circuitThreshold = 3; // 连续失败次数触发熔断
  static const _circuitCooldown = Duration(seconds: 60);

  // 熔断状态跨 AudioService 实例共享（每个页面会新建实例）
  static int _consecutiveFailures = 0;
  static DateTime? _circuitOpenUntil;

  /// 熔断是否开启（开启期间跳过一切网络发音，直接走 TTS）
  static bool get _circuitOpen {
    final until = _circuitOpenUntil;
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _circuitOpenUntil = null; // 冷却结束自动复位，允许再试一次
      return false;
    }
    return true;
  }

  static void _recordFailure() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= _circuitThreshold) {
      _circuitOpenUntil = DateTime.now().add(_circuitCooldown);
    }
  }

  static void _recordSuccess() {
    _consecutiveFailures = 0;
    _circuitOpenUntil = null;
  }

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

    // 1. 缓存命中直接播放（本地文件，不计入网络熔断）
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

    // 熔断开启中：跳过下载与在线播放，直接 TTS，避免逐词卡超时
    if (_circuitOpen) {
      await _speak(text, useUk);
      return;
    }

    // 2. 首次播放：先下载落盘，再播本地文件
    //    （原生端 download 内部已带 4s 超时；Web / stub 直接返回 false）
    final downloaded = await audioCache.download(url, key);
    if (downloaded) {
      final path = await audioCache.pathFor(key);
      if (path != null) {
        try {
          await _player.play(DeviceFileSource(path));
          _recordSuccess();
          return;
        } catch (_) {
          // 本地文件播放失败，回退在线播放
        }
      }
    } else {
      _recordFailure(); // 下载失败（网络异常或超时）
    }

    // 3. 在线播放（带 3s 超时；超时 / 异常 → 设备 TTS）
    try {
      await _player.play(UrlSource(url)).timeout(_onlinePlayTimeout);
      _recordSuccess();
    } on TimeoutException {
      await _stopQuietly();
      _recordFailure();
      await _speak(text, useUk);
    } catch (_) {
      _recordFailure();
      // 4. 网络失败 → 设备 TTS
      await _speak(text, useUk);
    }
  }

  Future<void> _stopQuietly() async {
    try {
      await _player.stop();
    } catch (_) {
      // 停止失败不影响后续 TTS 兜底
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
