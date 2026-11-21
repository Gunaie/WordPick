# 编码约定

> 适用于本仓库（Flutter 3.50 + material_ui + ChangeNotifier + sqlite3/PostgREST）。
> 通用风格参考 Dart 官方 [Effective Dart](https://dart.dev/effective-dart)。
> **注意**：早期文档里写的 Riverpod / drift / CloudBase SDK 均未采用，见 `decisions.md` D11 / D12 / D20。

---

## 1. 技术栈基线

| 项 | 当前值 | 备注 |
|---|---|---|
| Flutter | 3.50.0（`E:\flutter_sdk\flutter`） | 命令需带 `--no-pub`，见第 7 节 |
| UI 库 | `package:material_ui/material_ui.dart` | **不要** import `package:flutter/material.dart`（3.50 起已弃用，ISSUE-026） |
| 状态管理 | `ChangeNotifier` + `ListenableBuilder` | 全局单例 `AppState`，不引入 Riverpod |
| 本地存储 | `sqlite3` 手写 SQL / Web `localStorage` | 条件导出，见 `lib/data/progress_store.dart` |
| 云端 | `http` 直连 CloudBase PostgREST | `lib/data/cloud_sync.dart` |
| HTTP | `http` | 不用 dio |
| 音频 | `audioplayers` + 有道 dictvoice | `lib/services/audio_service.dart` |

新增依赖前先问：能否用现有包 + 手写少量代码解决？本项目刻意保持依赖精简。

---

## 2. 文件与命名

| 类型 | 规则 | 例子 |
|---|---|---|
| Dart 文件 | `snake_case.dart` | `custom_word_parser.dart` |
| 页面 | `xxx_page.dart`，类名 `XxxPage` | `word_book_page.dart` |
| 数据层 | `xxx_store.dart` / `xxx_repository.dart` / `xxx_sync.dart` | `progress_store_native.dart` |
| 领域逻辑 | 放 `lib/domain/`，纯 Dart，无 IO | `srs.dart`、`edit_distance.dart` |
| 测试 | `test/domain/`、`test/data/` 下按模块拆 `xxx_test.dart` | `srs_test.dart`、`dictionary_test.dart` |
| 脚本 | 统一放 `scripts/`；`*.cmd` **内容必须是纯 ASCII** | `scripts/build_apk.cmd` |

- 一个文件一个主要类；**配套的小模型 / 异常类可以同文件**（如 `cloud_sync.dart` 里的 `SyncException`、`custom_word_parser.dart` 里的 `CustomWordEntry` / `CustomWordBook`）。
- 领域模型用 `PascalCase`；私有字段 `_camelCase`；JSON 键统一 `snake_case`。
- 文件顶部写 `///` 库注释说明职责，重要的“为什么不这么做”要写清（本项目多处依赖这类注释）。

---

## 3. 代码风格

```dart
// 单引号
final msg = 'hello';

// 大括号不省略
if (ok) {
  return value;
}

// 优先 const
const SizedBox(height: 8);

// 链式调用换行用前导点
future
    .then(a)
    .catchError(handle);
```

- 注释、UI 文案、文档一律中文；变量 / 类名英文。
- 避免 `late`，除非确实需要延迟初始化。
- 不给未改动的代码补注释、补类型。
- 不写“以防万一”的兜底分支；只在系统边界（网络、用户输入、文件）做校验。

---

## 4. 状态管理约定

- 全局状态只有 `AppState`（`lib/app_state.dart`），页面通过构造函数接收 `state`，再用 `ListenableBuilder` 订阅。
- **业务编排写在 `AppState`**，页面只负责展示与交互；不要在 UI 文件里散落持久化代码。
- 改动内存状态后必须 `notifyListeners()`；需要落盘的走 `_persist*()` 统一入口。
- 写操作顺序固定：**先更新内存 → 落本地 → 再异步推云端**（推送失败只记录，不影响本地）。
- 新增字段时同步检查：`_load*()` 初始化、`_persist*()` 保存、`_syncMeta()` 合并三处。

---

## 5. 数据与同步约定

- 复习状态：`ReviewState`（`ease` / `interval` / `reps` / `lapses` / `due` / `updatedAt`），SM-2 在 `lib/domain/srs.dart`。
- 笔记：UUID 主键 + 软删除（`deleted`），同步时必须连带已删除记录。
- 自建单词本：`custom_books` 为 `user_meta` 里的 JSON 数组，按书 `id` 合并；本地内容优先，与远端不一致才回推。
- 易混词组：`confusable_groups` 为 `user_meta` 里的 JSON 数组，按组 `id` 合并；Web 本地键 `es_confusable_v1`，原生 `meta.confusable_groups`。
- 所有云端表操作都必须带 `user_id` 过滤；`CloudSync` 已统一处理，不要绕过它直接发请求。
- 新增 / 修改表结构时，同步更新 `docs/cloudbase_schema.sql` 与 `docs/api.md`。

---

## 6. 错误处理

- 只分两类：**可恢复** → 提示用户后继续；**不可恢复** → 抛出带上下文的异常。
- 网络同步失败：抛 `SyncException(message, statusCode)`，调用方决定是否提示；不阻塞启动。
- 音频播放失败：静默忽略（学习流程优先），不加弹窗。
- 不要用 `null` 表示错误；不要到处 `try/catch` 后返回空值。
- 用户可感知的错误必须给中文文案，避免直接抛英文异常给用户。

---

## 7. 构建与验证（重要）

| 场景 | 命令 | 注意 |
|---|---|---|
| 依赖解析 | `dart pub get` | **不要用** `flutter pub get`（插件符号链接会失败，ISSUE-027） |
| 静态检查 | `flutter analyze --no-pub` | 应为 `No issues found` |
| 单元测试 | `flutter test --no-pub` | 当前 70 项全过 |
| 本机预览 | 双击 `scripts\preview_web.cmd` | Edge + 端口 8091，构建目录在 `%TEMP%` |
| 打包 APK | 双击 `scripts\build_apk.cmd` | 产物 `E:\APK\app-release.apk`；**仅用户明确要求时才打包** |

agent 在 shell 里调用 Flutter 时，必须用独立控制台启动，否则会卡死（ISSUE-024）：

```powershell
Start-Process -FilePath 'E:\flutter_sdk\flutter\bin\flutter.bat' `
  -ArgumentList 'analyze','--no-pub' -PassThru -WindowStyle Hidden `
  -RedirectStandardOutput out.txt -RedirectStandardError err.txt
```

且需要 `dangerouslyDisableSandbox: true`（SDK 与 Pub 缓存在沙箱白名单外）。
构建产物不要落在工作区 `build/`（文件监视器会回收，ISSUE-025 / ISSUE-029）。

---

## 8. Git 约定

提交信息沿用 Conventional Commits：

```
<type>(<scope>): <subject>

type:  feat | fix | refactor | docs | chore | test | build
scope: words | srs | spelling | sync | store | ui | docs | build

示例:
  feat(ui): 自建单词本支持重命名与批量导入
  fix(sync): 自建单词本按 id 合并，避免离线修改被覆盖
  docs: 校准 api.md 与 conventions.md 到当前实现
```

- 不提交：`build/`、`.dart_tool/`、`*.iml`、`.env*`、`cloudbaserc.json`。
- 密钥只允许 anon Publishable Key 出现在 `lib/data/sync_config.dart`，`service_role` 永不入库。
- 提交 / 推送 / 改写历史仅在用户明确要求时执行。

---

## 9. 测试约定

| 类型 | 范围 | 位置 |
|---|---|---|
| 纯逻辑单测 | SM-2、拼写提示、自建词解析、易混组、导出 / 恢复、拍照识别候选 | `test/domain/`、`test/data/` |
| Widget 冒烟 | 页面能构建、关键文案存在 | 当前未覆盖；新增时放 `test/ui/` |
| 手工验证 | 发音、同步、真机交互 | 电脑端预览或真机 |

- 新逻辑优先写成 `lib/domain/` 里的纯函数，方便无 Flutter 依赖地测试。
- 改动持久化 / 序列化 / 解析逻辑时，必须补一条往返或兼容性测试。
- 提交前至少跑 `flutter analyze --no-pub` 与 `flutter test --no-pub`。

---

## 10. 文档约定

| 文件 | 该写什么 | 不该写什么 |
|---|---|---|
| `README.md` | 功能表、目录树、环境、常用命令 | 详细设计 |
| `docs/architecture.md` | **当前实现**的技术栈、目录、数据流、表结构 | 未落地的设想 |
| `docs/api.md` | 实际调用的接口 + 明确标注“未接入”的历史方案 | 把设计稿写成已实现 |
| `docs/decisions.md` | 决策记录 Dxx，只追加不改写 | 删除历史 |
| `docs/known-issues.md` | 坑与规避，已修复的保留 | 无证据的猜测 |
| `PROJECT_MEMORY.md` | 每次开发会话的经验沉淀 | 与代码重复的手册 |
| `docs/research/` | 早期调研原始结论，**只存档** | 当成现状文档引用 |

写文档的第一原则：**读者要能通过文档判断“这段代码现在到底在做什么”**。
未接入的东西必须显式写「未接入」，并指向决策编号。
