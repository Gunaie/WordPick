/// Web：不落盘，交给浏览器 HTTP 缓存
class AudioCache {
  Future<String?> pathFor(String key) async => null;

  Future<bool> download(String url, String key) async => false;

  Future<int> sizeBytes() async => 0;

  Future<void> clear() async {}
}

final AudioCache audioCache = AudioCache();
