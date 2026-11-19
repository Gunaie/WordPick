# 接口约定

> 外部接口（有道发音、CloudBase 同步）、本地存储接口。
> 接口稳定性等级：🟢 稳定 / 🟡 灰色（内部接口，可能变） / 🔴 待实现
>
> **现状校准（2026-11-19）**：第 1.1 节（dictvoice 发音）与第 3 节（同步）为当前实现；
> 第 1.2 节的有道 jsonapi、第 2 节 Free Dictionary **均未接入**，原 `DictionaryService`
> 已删除，释义全部来自打包的 `words.json`（见 D16）。以下保留为历史设计参考。
> 本地存储实际为 sqlite3 手写 SQL（非 drift），表结构见 `architecture.md`。

---

## 1. 有道词典 API（🟡 灰色接口）

### 1.1 发音（音频）

| 项 | 值 |
|---|---|
| **URL** | `http://dict.youdao.com/dictvoice?type={0\|1}&audio={word}` |
| **type=0** | 美式发音 |
| **type=1** | 英式发音 |
| **音频格式** | MP3 |
| **响应** | 直接返回音频流 |
| **超时** | 500ms（超过则熔断） |
| **实测速度** | 52-94 ms |
| **大小** | ~10 KB / 词 |

```dart
// 正确拼接方式（参数顺序不能乱）
Uri.http('dict.youdao.com', '/dictvoice', {
  'type': '0',           // 0=美, 1=英
  'audio': 'predict',    // 单词（URL encode 特殊字符）
});
// → http://dict.youdao.com/dictvoice?type=0&audio=predict
```

### 1.2 查词（释义 + 音标）

| 项 | 值 |
|---|---|
| **URL** | `https://dict.youdao.com/jsonapi?dicts={modules}&q={word}` |
| **dicts** | `ec.basic`（最简）|
| **额外模块** | `ce.basic,phonetic,web_trans` |
| **响应** | JSON |
| **超时** | 500ms |
| **实测速度** | ~90 ms |

```dart
Uri.https('dict.youdao.com', '/jsonapi', {
  'dicts': 'ec.basic,phonetic',
  'q': 'predict',
});
```

#### 响应字段（已实测）

```json
{
  "ec": {
    "word": [{
      "usphone": "prɪˈdɪkt",          // 美音音标
      "ukphone": "prɪˈdɪkt",          // 英音音标
      "ukspeech": "predict&type=1",   // 英音发音参数（需拼接完整 URL）
      "usspeech": "predict&type=2",   // 美音发音参数
      "trs": [{
        "tr": [{
          "l": { "i": ["v. 预言，预计，预卜"] }
        }]
      }]
    }]
  }
}
```

**⚠️ 注意**：
- `ukspeech` / `usspeech` 字段值不是完整 URL，只给了"单词 + type"参数
- 要自己拼成完整 URL：`http://dict.youdao.com/dictvoice?type=1&audio=predict`
- 返回的 `phonetic` 模块里有 web_trans（网络翻译），但结构不统一，谨慎使用

---

## 2. Free Dictionary API（🟢 稳定）

| 项 | 值 |
|---|---|
| **URL** | `https://api.dictionaryapi.dev/api/v2/entries/en/{word}` |
| **授权** | CC BY-SA 3.0 |
| **超时** | 500ms（实测 1.6s/词，作为 fallback） |
| **响应** | JSON 数组 |
| **速率限制** | 每 IP 每分钟 60 次（非官方声明） |

#### 响应字段

```json
[{
  "word": "predict",
  "phonetic": "/prɪˈdɪkt/",              // 主音标
  "phonetics": [
    {
      "text": "/prɪˈdɪkt/",
      "audio": "https://.../predict-us.mp3",  // 常只有美式
      "sourceUrl": "https://...dict",
      "license": { "name": "CC BY-SA 3.0" }
    }
  ],
  "meanings": [{
    "partOfSpeech": "verb",
    "definitions": [{
      "definition": "say that something will happen in the future",
      "example": "She predicted the company would go bankrupt.",
      "synonyms": ["foretell", "prophesy"]
    }]
  }],
  "license": { "name": "CC BY-SA 3.0" }
}]
```

**⚠️ 已知问题**：
- 经常只返回美式音频（英音缺失率 > 50%）
- 无中文释义（只有英文定义）
- 404 时返回 `{ "title": "No Definitions Found", "message": "...", "resolution": "..." }`

---

## 3. 系统 TTS（✅ 平台原生）

| 平台 | 实现 | flutter_tts 包自动调用 |
|---|---|---|
| iOS | AVFoundation | ✅ |
| Android | TextToSpeech | ✅ |
| Windows | Speech API (SAPI) | ✅ |
| macOS | NSSpeechSynthesizer | ✅ |

```dart
import 'package:flutter_tts/flutter_tts.dart';

final tts = FlutterTts();
await tts.setLanguage('en-US');   // 美音
await tts.setLanguage('en-GB');   // 英音
await tts.speak('accommodate');
```

**音质**：比原生词典音频差，但自建词库的单词必须用这个兜底。

---

## 4. CloudBase Flutter SDK（🟢 稳定）

### 4.1 初始化

```dart
import 'package:cloudbase_core/cloudbase_core.dart';

await CloudBaseCore.init({
  'env': 'your-env-id-xxxxx',    // 腾讯云开发控制台 → 环境设置
});
```

### 4.2 Auth

```dart
// 匿名登录（无手机号/邮箱也能用）
final loginResult = await CloudBaseAuth.instance.signInAnonymously();
final uid = loginResult.user.uid;
```

### 4.3 文档数据库（用户数据）

```dart
final db = CloudBaseDatabase.instance;
final collection = db.collection('user_words');

// 查询（按 user_id 过滤）
final result = await collection
    .where({'user_id': uid, 'next_review': lte(DateTime.now().toIso8601String())})
    .limit(20)
    .get();

// 写入
await collection.add({
  'user_id': uid,
  'word_id': 'cet4-0001',
  'ease_factor': 2.5,
  'interval': 1,
  'repetitions': 0,
  'next_review': DateTime.now().add(Duration(days: 1)).toIso8601String(),
  'updated_at': DateTime.now().toIso8601String(),
  'version': 1,
});

// 更新
await collection.doc(docId).update({
  'interval': 3,
  'next_review': nextDate.toIso8601String(),
  'updated_at': DateTime.now().toIso8601String(),
  'version': 2,
});
```

### 4.4 实时同步（watch）

```dart
final watcher = collection
    .where({'user_id': uid})
    .watch()
    .listen((event) {
      // event.docs: 变化的文档
      // 触发本地刷新
      ref.invalidate(userWordsProvider);
    });

// 停止监听
watcher.cancel();
```

### 4.5 Row Level Security（数据隔离）

在 CloudBase 控制台 → 数据库 → 安全规则设置：

```json
{
  "read": "doc.user_id == auth.uid()",
  "write": "doc.user_id == auth.uid()",
  "create": "auth != null",
  "update": "doc.user_id == auth.uid()",
  "delete": "doc.user_id == auth.uid()"
}
```

---

## 5. 本地 drift DAO（✅ 应用内）

### userWords DAO 示例

```dart
// 在 lib/database/user_schema.dart
@DriftDatabase(tables: [UserWords, Notes, UserTags, ...])
class AppDatabase extends _$AppDatabase {
  // ... 构造和 schemaVersion
}

class UserWordDao {
  final AppDatabase _db;
  UserWordDao(this._db);

  /// 获取今日待复习的词
  Future<List<UserWord>> getDueToday(DateTime today) {
    return (_db.select(_db.userWords)
      ..where((u) => u.nextReview.isSmallerOrEqualValue(today))
      ..orderBy([(u) => OrderingTerm.asc(u.nextReview)])
      ..limit(50))
      .get();
  }

  /// 标记复习结果（SRS 后更新）
  Future<void> updateAfterReview(String id, SRSResult result) async {
    await (_db.update(_db.userWords)
      ..where((u) => u.id.equals(id)))
      .write(UserWordsCompanion(
        interval: Value(result.interval),
        easeFactor: Value(result.easeFactor),
        repetitions: Value(result.repetitions),
        nextReview: Value(result.nextReview),
        updatedAt: Value(DateTime.now()),
        version: Value(result.version),
      ));
  }
}
```

---

## 6. 熔断接口状态

```dart
class CircuitBreaker {
  final int failureThreshold;  // 连续失败多少次熔断
  final Duration openDuration; // 熔断时长
  int _failures = 0;
  DateTime? _openedAt;

  bool get isOpen {
    if (_openedAt == null) return false;
    return DateTime.now().difference(_openedAt!) < openDuration;
  }

  void recordSuccess() { _failures = 0; _openedAt = null; }
  void recordFailure() {
    _failures++;
    if (_failures >= failureThreshold) {
      _openedAt = DateTime.now();
    }
  }
}

// 默认配置：连续 3 次失败 → 熔断 10 分钟
final youdaoBreaker = CircuitBreaker(
  failureThreshold: 3,
  openDuration: Duration(minutes: 10),
);
```
