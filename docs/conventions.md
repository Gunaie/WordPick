# 编码约定

> Dart + Flutter + Riverpod + drift + CloudBase 的项目特定约定。
> 参考：Dart 官方 style guide（https://dart.dev/effective-dart）+ Flutter architecture recommendations

---

## 项目工具链

| 工具 | 版本 | 用途 |
|---|---|---|
| Flutter SDK | 最新稳定（≥ 3.22.0） | `flutter --version` 确认 |
| Dart SDK | 随 Flutter | 不要单独装 |
| drift_dev | ≥ 2.20.0 | `dart run drift_dev build` 生成 drift 代码 |
| CloudBase CLI | 可选 | `npm install -g @cloudbase/cli` |
| IDE | VS Code + Flutter 插件 | 推荐 |

### 初始化命令（新克隆的环境）

```bash
flutter pub get                        # 拉依赖
dart run drift_dev build               # 生成 drift .dart 文件
flutter create . --platforms=windows,macos,web   # 如缺少平台目录
flutter run -d windows                 # 跑起来验证
```

---

## 文件命名

| 类型 | 规则 | 例子 |
|---|---|---|
| Dart 文件 | `snake_case.dart` | `dictionary_service.dart` |
| drift schema | `xxx_schema.dart` | `word_schema.dart` |
| drift 生成文件 | `.drift.dart`（自动生成） | `app_database.drift.dart` |
| 测试文件 | `xxx_test.dart`（同目录 `test/` 下） | `dictionary_service_test.dart` |
| 资源文件 | `snake_case.ext` | `cet4_core_2000.json` |
| Riverpod Provider | `xxxProvider` / `xxxNotifier` | `cloudBaseClientProvider` |
| 领域模型 | `PascalCase` | `UserWord`, `ReviewFeedback` |

### 单文件单类

> 一个文件只放一个 `class`，文件名 = 类名（snake_case）。
> 例外：小的 data class（<3 个字段）可以放同文件。

```dart
// ✅ 好
// review_feedback.dart
class ReviewFeedback { ... }

// ❌ 不好：多个类放一个文件
// feedback.dart
class ReviewFeedback { ... }
class SpellingFeedback { ... }
```

---

## 代码风格

### 必须遵循

```dart
// 字符串用单引号
final message = 'hello';        // ✅
final message = "hello";        // ❌

// 大括号不省略（哪怕单语句）
if (isValid) {                  // ✅
  return result;
}
if (isValid) return result;     // ❌

// 每行最多 80 字符（可选，团队共识）
// 链式调用换行时用前导点
future
  .then(a)
  .then(b)
  .catchError(handle);

// 优先用 const 构造函数
const SizedBox(height: 8)       // ✅
SizedBox(height: 8)             // ❌ 如非必须

// null safety：不要用 late 除非确实需要延迟初始化
// Riverpod Notifier 的 state 初始值给好
```

### Riverpod 约定

```dart
// ✅ Provider 定义放在 core/di/ 对应文件里
// ❌ 不要在 UI 文件里定义 Provider

// 定义风格（新 Riverpod v2 语法）
final driftDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

// Notifier 风格
final reviewControllerProvider =
    NotifierProvider<ReviewController, ReviewState>(ReviewController.new);

// ConsumerWidget 用法（简单场景）
class WordCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reviewControllerProvider);
    return ...;
  }
}
```

### drift 约定

```dart
// schema 里用 drift 内置类型，不要用 dart:ffi

// 表名：snake_case
class UserWords extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().named('user_id')();
  DateTimeColumn get nextReview => dateTime().named('next_review')();
  IntColumn get interval => integer()();
}

// 查询用 DAO，不要手写 SQL
class WordDao {
  Future<List<UserWord>> getDueToday(DateTime date) {
    return (select(userWords)
      ..where((u) => u.nextReview.isSmallerOrEqualValue(date)))
      .get();
  }
}

// 生成命令
dart run drift_dev build --delete-conflicting-outputs
```

---

## 错误处理

### 词典 API 调用（核心场景）

```dart
class DictionaryService {
  final Logger _logger = Logger('DictionaryService');

  Future<Result<WordData>> fetch(String word) async {
    // 1. 本地缓存
    final cached = await _cache.get(word);
    if (cached != null) return Result.ok(cached);

    // 2. 有道（带超时 + 熔断）
    if (!_circuitBreaker.isOpen) {
      try {
        final data = await _youdao.fetch(word)
            .timeout(const Duration(milliseconds: 500));
        await _cache.save(word, data);
        _circuitBreaker.recordSuccess();
        return Result.ok(data);
      } catch (e) {
        _logger.w('有道失败: $word', e);
        _circuitBreaker.recordFailure();
      }
    }

    // 3. Free Dictionary fallback
    try {
      final data = await _freeDict.fetch(word)
          .timeout(const Duration(milliseconds: 500));
      await _cache.save(word, data);
      return Result.ok(data);
    } catch (e) {
      _logger.w('FD fallback 失败: $word', e);
    }

    // 4. 返回错误，不要 silent fail
    return Result.err(DictionaryException.notFound(word));
  }
}
```

### 统一 Result 类型

```dart
// 不要到处 try/catch + 返回 null
// 用 sealed class 包装结果
sealed class Result<T> {
  const Result();
  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;
}

final class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

final class Err<T> extends Result<T> {
  final Exception exception;
  const Err(this.exception);
}
```

---

## Git 约定

### Commit Message

```
<type>(<scope>): <subject>

type: feat | fix | refactor | docs | chore | test | build
scope: words | srs | sync | dict | ui | infra

示例:
  feat(words): 实现听音拼写的 typo 容错
  fix(sync): 修复 offline 时 pending 队列不重试
  refactor(srs): SM-2 调度器抽出单独 Service
  docs: 更新 architecture.md 同步 D02 决策
```

### Branch 策略

```
main          —— 永远可发布
develop       —— 集成分支（每日合并）
feature/xxx   —— 功能分支（从 develop 切）
fix/xxx       —— bug 修复分支
hotfix/xxx    —— 紧急修复（从 main 切）
```

### .gitignore 关键项

```
# drift 生成
*.drift.dart

# IDE
.vscode/
.idea/

# Flutter
build/
.dart_tool/
.packages

# CloudBase 配置（含 Secret，绝对不能提交）
cloudbaserc.json
.env*
```

---

## 测试约定

### 分层测试策略

| 层 | 什么要测 | 怎么测 |
|---|---|---|
| **Service / SRS** | SM-2 调度结果正确、词典熔断逻辑 | `flutter_test` 纯单元测试 |
| **Repository** | drift 查询正确、序列化正确 | `mocktail` 或内存 drift |
| **UI / Widget** | 基本渲染不崩、按钮点击有反应 | `flutter_test` Widget Test |
| **CloudBase 集成** | watch() 推送正常 | 手动测 + CloudBase 模拟器 |

### 必须写测试的模块

- SM-2 调度器（边界值：interval 计算、E-Factor 调整）
- 词典 Service（三源切换逻辑、熔断）
- 拼写 typo 容错（编辑距离计算）
- SyncManager（offline 队列行为）

---

## 性能约定

| 指标 | 目标 | 手段 |
|---|---|---|
| 词典首屏 | < 1s | 有道 90ms + 本地缓存 |
| 复习切卡 | < 100ms | 数据全本地 drift |
| 启动到首页 | < 2s | 静态词表打包 + bootstrap 异步 |
| 音频播放延迟 | < 200ms | audioplayers preload |
| 离线可用 | 100% | drift 优先 + pending 队列 |

---

## 数据迁移约定

### drift Schema 变更流程

```dart
// 1. 在 schema 里加新列 / 新表（不要删已有）
// 2. 写 Migration
MigrationStrategy get migration => MigrationStrategy(
  onCreate: (m) async { await m.createAll(); },
  onUpgrade: (m, from, to) async {
    if (from < 2) {
      await m.addColumn(userWords, userWords.spellingCount);
    }
  },
);

// 3. bump drift_dev build
// 4. 部署新版本前：旧版本用户启动时自动迁移
```

### 静态词表更新

```bash
# 每年 1-2 次，考纲变化时
cd scripts
dart run import_words.dart \
  --input ../assets/data/words.csv \
  --output ../assets/data/words.json
```
