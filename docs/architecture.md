# 架构事实

> 本文档记录系统架构的**当前实现**（与 `lib/` 代码一致）。
> 设计背景与取舍见 `decisions.md`；已知问题见 `known-issues.md`。

---

## 技术栈

| 层级 | 选型 | 版本 | 包名 / 位置 |
|---|---|---|---|
| 客户端框架 | Flutter | 3.50.0（`E:\flutter_sdk\flutter`） | `flutter` SDK |
| 语言 | Dart | 3.14.0（随 Flutter 3.50.0） | — |
| UI 库 | material_ui | ^1.11.0 | `material_ui` |
| 状态管理 | ChangeNotifier | — | `lib/app_state.dart` |
| 本地存储（原生） | sqlite3 直连（FFI） | ^3.8.0 | `lib/data/progress_store_native.dart` |
| 本地存储（Web） | localStorage | — | `lib/data/progress_store_web.dart` |
| 云端 | PostgREST（CloudBase 托管 PostgreSQL） | — | `lib/data/cloud_sync.dart` |
| 间隔重复 | 自实现 SM-2 | — | `lib/domain/srs.dart` |
| HTTP | http | ^1.6.0 | `http` |
| 音频播放 | audioplayers + flutter_tts | ^6.8.1 / ^4.2.3 | `lib/services/audio_service.dart` |
| 文件路径 | path_provider + path | ≥2.1.6 | `path_provider`, `path` |
| 导出 | share_plus（原生）/ Blob（Web） | ^10.1.4 | `lib/services/export_service.dart` |
| 拍照识别 | google_mlkit_text_recognition + image_picker | ^1.0.3 / ^1.2.4 | `lib/services/ocr_native.dart`（仅 Android / iOS） |
| 其他 | uuid（笔记 ID）、web（条件导出） | — | `uuid`, `web` |

> 与最初方案的差异：drift + build_runner 未采用（改手写 SQL）；Riverpod 未引入（D12）；
> 在线词典 `DictionaryService` 已移除，改为离线词典 `DictionaryRepository`（`assets/data/dict_core.json`）；内置 `words.json` 已下线，复习池只来自自建单词本。

## 平台支持

| 平台 | 状态 | 说明 |
|---|---|---|
| Android | ✅ 主要目标，真机验证通过 | API 24+；release 包需 `INTERNET` 权限 |
| Web | ✅ 次要目标 / 日常预览 | localStorage 持久化；`scripts\preview_web.cmd` 用 Edge 预览 |
| Windows | ⚪ 保留工程，本机未验证 | 缺 VS C++ 工作负载与开发者模式，当前无法构建（ISSUE-027） |
| iOS / macOS | ⚪ 保留工程，未验证 | — |
| Linux | ⚪ 未接入 | — |

---

## 代码结构

```
lib/
├── main.dart                      App 入口与三 Tab 导航（今日 / 词单 / 我的）
├── app_state.dart                 全局状态（ChangeNotifier）+ 业务编排 + 持久化调度
│
├── data/                          数据层（IO、仓储、同步）
│   ├── affix_repository.dart      加载 assets/data/affixes.json
│   ├── dictionary_repository.dart 加载 assets/data/dict_core.json（约 1.4 万词）
│   ├── progress_store.dart        条件导出：native / web / stub
│   ├── progress_store_native.dart sqlite3 实现（review_state/note/meta/daily_stat）
│   ├── progress_store_web.dart    localStorage 实现
│   ├── progress_store_stub.dart   兜底空实现
│   ├── cloud_sync.dart            PostgREST 同步（拉取 / 推送 / 清空）
│   ├── sync_config.dart           同步地址与密钥
│   ├── note_record.dart           笔记模型
│   ├── daily_stat.dart            每日统计模型
│   └── app_settings.dart          学习设置模型（口音 / 题量，仅本地）
│
├── domain/                        纯逻辑（无 IO，可单测）
│   ├── word.dart                  单词 / 释义模型
│   ├── affix.dart                 词根词缀模型
│   ├── srs.dart                   SM-2 调度
│   ├── learning_quiz.dart         四选一题目与自动评分映射
│   ├── export_builder.dart        JSON / Markdown 导出内容构造
│   ├── export_import.dart         备份 JSON 解析（恢复用，纯逻辑）
│   ├── edit_distance.dart         拼写容错判定
│   ├── spelling_hints.dart        拼写提示：首字母 / 音节 / 词根 / 四选一
│   ├── markdown.dart              笔记 Markdown 块级解析（预览用）
│   ├── custom_word_parser.dart    自建词文本解析（批量导入 / 拍照识别共用）
│   ├── ocr_candidates.dart        OCR 文本行合并 → 候选词条（纯逻辑）
│   ├── confusable_group.dart      易混词组模型
│   └── confusable_queue.dart      易混组在队列中的插入（纯函数）
│
├── services/
│   ├── audio_service.dart         dictvoice 音源 + 缓存 + TTS 兜底
│   ├── audio_cache.dart           缓存接口（native / web / stub 条件导出）
│   ├── export_service.dart        导出落盘（share_plus / Blob 条件导出）
│   ├── export_native.dart         原生：临时文件 + 系统分享
│   ├── ocr_service.dart           拍照识别接口（native / stub 条件导出）
│   ├── ocr_native.dart            ML Kit 离线识别 + image_picker 取图
│   └── ocr_types.dart             取图来源等公共类型
│
└── ui/                            页面
    ├── theme.dart                 配色 / 渐变背景 / 玻璃卡片 / 统一页头 PageHeader
    ├── today_page.dart            今日（签到、数字块、入口）
    ├── learning_page.dart         学习（四选一 / 自评 / 结束页）
    ├── books_page.dart            词单（单词本列表）
    ├── word_book_page.dart        自建单词本详情（词条增删改查）
    ├── spelling_page.dart         拼写练习
    ├── notes_page.dart            笔记（时间线小记 + 标签筛选 + 搜索、增删改查）
    ├── note_editor_page.dart      笔记编辑（Markdown 工具栏 + 预览切换）
    ├── markdown_text.dart         Markdown 渲染（标题 / 列表 / 引用 / 代码）
    ├── affix_page.dart            词根词缀专题（自建词拆解 + 词缀检索）
    ├── confusable_page.dart       易混词分组管理
    ├── stats_page.dart            学习统计（签到同源、14 天柱状图）
    ├── settings_page.dart         设置
    └── profile_page.dart          我的（功能入口）
```

---

## 数据流

### 启动

```
main() → AppState 初始化
  ├─ AffixRepository.load()   ← assets/data/affixes.json
  ├─ DictionaryRepository.load() ← assets/data/dict_core.json（失败静默）
  ├─ ProgressStore.loadAll() / loadNotes() / loadDaily() / loadCustomBooks() / loadConfusableGroups() / loadSettings()
  │                          ← 原生 sqlite3 / Web localStorage
  └─ 可选：CloudSync.pull()   ← PostgREST，失败不阻塞启动
```

### 学习与拼写

```
今日页 → buildTodayQueue()（到期词按上限截断 + 未学新词，数量取自本地设置：
           到期默认 20、新词默认 10；随后由 buildConfusableRound 插入易混组同伴）
  │
  ├─ learning_quiz.dart 生成四选一 → 答对 / 答错
  ├─ 自动评分：错→重来；对→一般；对且 reps ≥ 3→简单
  ├─ 词池不足 4 个有释义的词时降级为自评四档
  ├─ srs.dart 计算下次复习时间
  ├─ AppState 更新内存状态 → notifyListeners()
  ├─ ProgressStore.upsert()   立即落本地
  └─ recordStudy() 累计写入 daily_stat（新学数 / 复习数）
```

### 同步（可选）

```
启动完成（_ready = true）→ unawaited(syncNow())      不阻塞首屏
AppLifecycleState.resumed → autoSync()                 60 秒冷却，Web 对应标签页可见
syncNow():
  ├─ pull review_state  → 逐词比较 updated_at，远端新则落本地
  ├─ 本地更新的词 → 批量 upsert 回远端
  ├─ pull note          → 远端软删除则本地物理删除；否则按 updated_at 取新
  ├─ pull user_meta     → 自建单词本按书 id 取并集（本地内容优先）
  │                      → 易混词组按组 id 取并集（本地内容优先）
  └─ 清理旧键（favorites / custom_words）
```

- 失败只写 `_syncError`，不影响本地使用；下次回前台、启动或手动同步时重试。
- 回前台同步以「最近一次尝试」计时冷却，同步中、未就绪、未启用时跳过（D39）。
- 没有「待同步队列」：每次都是全量比对，本地状态是唯一事实来源。
- 冲突策略：按 `updated_at` 后写覆盖（D22）；自建单词本用 JSON 差异判断是否需要回推。
- 学习设置只存本地 `meta.settings`，不参与同步（D37）。
- 接口细节见 `api.md` 第 2 节。

### 备份与恢复

```
设置页导出 JSON（buildJsonExport）
  ↓ 用户保存文件
设置页「从 JSON 恢复」→ parseExportJson（校验 app / schema）
  ↓ 预览数量并确认
AppState.restoreFromJson 合并：
  ├─ 词书：同书 id 合并，词按 key 全局去重
  ├─ 笔记：按 id，updatedAt 较新者覆盖
  ├─ 复习状态：按词 key，updatedAt 较新者覆盖
  └─ 每日统计：同日期取较大值 → mergeDaily
  ↓ 有变更时触发一次 syncNow()
```

### 拍照识别手写

```
词单详情 →「拍照识别手写」（仅 ocrSupported 为真的 Android / iOS 显示）
  ↓ 弹层选择拍照 / 相册
image_picker 取图（临时文件，不写入数据库）
  ↓
ocr_native.dart：ML Kit 中文模型端上离线识别 → 原始文本
  ↓
ocr_candidates.dart：合并「单词一行、释义下一行」的写法 → OcrScanResult
  ↓
候选校对页：逐条编辑 / 删除 → 确认
  ↓
importWordsToBook()：复用粘贴导入的解析、去重与重复次数累加
```

- Web / 桌面走 `ocr_stub.dart`，`ocrSupported = false`，界面不显示入口；`flutter build web` 不受影响。
- 手写（尤其中文）准确率有限，产品上以「候选校对」兜底；中文识别模型随 APK 打包，约增加 20–40MB。
- Android 侧需在 `android/app/build.gradle.kts` 显式引入 `com.google.mlkit:text-recognition-chinese`（Flutter 插件只声明 compileOnly）。

---

## 本地数据表（sqlite3）

| 表 | 内容 |
|---|---|
| `review_state` | 每个词的学习状态（SM-2 参数、下次复习、遗忘次数） |
| `note` | 笔记（UUID + 软删除；`title` / `tags` 为 M6 新增列） |
| `daily_stat` | 每日新学 / 复习计数 |
| `meta` | 杂项键值（自建单词本 `custom_books`、易混词组 `confusable_groups`、设置等；收藏功能已下线） |

云端对应表：`review_state`、`note`、`user_meta`（结构见 `docs/cloudbase_schema.sql`）。

---

## 外部依赖

| 服务 | 用途 | 备注 |
|---|---|---|
| `dict.youdao.com/dictvoice` | 英美发音 mp3 | 灰色接口，仅播放音频，不做释义查询 |
| PostgREST（CloudBase） | 跨端同步 | 未配置时全部功能离线可用 |

> 发音与同步均需联网；Android release 包必须声明 `INTERNET` 权限，否则静默失败。

---

## 安全设计

| 项 | 现状 |
|---|---|
| 同步密钥 | 内置在 `lib/data/sync_config.dart`（个人自用，未做服务端鉴权轮换） |
| 数据库访问 | CloudBase 侧用 `GRANT` 控制角色权限（D21） |
| 数据清理 | 「清空数据」同时清本地与云端（D26） |
| 敏感信息 | 不提交任何含密钥的额外配置文件；仓库为私有单机项目 |
