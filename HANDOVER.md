# 项目交接文档

> English Study Tool — 跨端英语学习应用（Flutter + CloudBase PostgREST）
> 当前版本：v0.14（M1–M10 完成：学习闭环 + 发音缓存 + 数据导出 / 恢复 + 时间线小记 / 多释义词条 + 设置生效 + 到期词分批 + 回前台同步 + 拼写四选一）
> 最后更新：2026-11-20

---

## TL;DR · 5 分钟读完

**这是什么**：个人用英语学习 APP，Android / Web 双端运行（Windows 工程保留但本机无法构建），数据可选跨端同步。只使用自建单词本：四选一学习卡、SM-2 复习、拼写练习、词根词缀、学习统计、笔记。

**技术栈一句话**：Flutter 3.50.0（`E:\flutter_sdk\flutter`）+ material_ui（3.50 起替代 `flutter/material.dart`）+ `ChangeNotifier` 状态管理 + sqlite3 直连（原生）/ localStorage（Web）+ 自实现 SM-2 + 自建词单（无内置词库）+ 有道 dictvoice + CloudBase PostgreSQL 的 PostgREST（http 直连同步）。

**现在的状态**：
- 已实现：今日页（签到、待复习 / 今日已学、拼写入口）、学习页（四选一、自动评分、降级自评、到期词分批、结束页）、词单（多本单词本、词条增删改查 / 粘贴导入 / 重复导入累加 / 词性与多释义 / 离线词典带出音标释义）、拼写练习（发音 + 释义同时展示，首字母 / 音节 / 词根 / 四选一四级提示）、笔记（时间线小记 + 标签筛选 + 搜索 + 增删改查）、词根词缀（自建词拆解 + 词缀表）、学习统计（签到同源、14 天新学 / 复习柱状图）、设置页（学习设置、立即同步、发音缓存清理、JSON 导出 / 恢复、Markdown 导出、关于）、发音缓存 + TTS 兜底、云同步（启动 + 回前台自动同步）。
- 已下线：内置词库（words.json）、考试练习、真题例句、考纲筛选、收藏、错题本。
- 验证方式：`flutter analyze --no-pub` 0 issue；`flutter test --no-pub` 51 项通过；`flutter build web --no-pub` 通过；`preview_web.cmd` 电脑端预览正常。
- 升级提示：笔记新增 `title` / `tags`，云端 `note` 表需手工执行一次 `ALTER TABLE`（ISSUE-033）；本地 SQLite 自动迁移。

> **剩余可选项**：暂无。后续可考虑笔记导出按日期分组、词条批量操作、存储层集成测试。

---

## 1. 文档地图（按阅读顺序）

| 顺序 | 文件 | 读什么 |
|---|---|---|
| ① | `docs/architecture.md` | **当前实现**：技术栈、目录、数据流、表结构 |
| ② | `docs/api.md` | 实际调用的接口（发音 / 同步 / 本地存储），并明确列出未接入的历史方案 |
| ③ | `docs/conventions.md` | 编码、状态管理、构建验证、Git、测试、文档约定 |
| ④ | `docs/decisions.md` | 技术决策 D01–D40，含被推翻的方案，只追加不改写 |
| ⑤ | `docs/known-issues.md` | 坑与规避；早期条目的“已缓解”已按现状校正 |
| ⑥ | `docs/cloudbase_schema.sql` | 云端建表与授权 SQL |
| ⑦ | `README.md` | 功能表、目录树、常用命令 |
| ⑧ | `PROJECT_MEMORY.md` | 逐次开发会话的经验沉淀（历史记录，非现状手册） |
| ⑨ | `docs/research/` | 早期产品调研与 API 实测，**仅存档**，不要当现状引用 |

---

## 2. 功能现状（替代旧版“优先级全景”）

```
已实现
├── 今日：签到卡、待复习 / 今日已学数字块、开始学习与拼写入口
├── 学习：自建词四选一、自动评分、到期词分批、词池不足时降级自评、结束页
├── 词单：多本单词本、命名 / 重命名 / 删除；词条增删改查、粘贴导入（词性 / 多释义 / 音标）、重复导入计数、离线词典带出音标与释义
├── 拼写练习：发音 + 释义同时展示，编辑距离容错，四选一提示兜底
├── 词根词缀：自建词拆解 + 词缀库检索，无匹配时给出说明
├── 学习统计：与签到同源，14 天新学 / 复习柱状图、连续天数
├── 笔记：时间线小记（标题 / 正文 / 标签 / 可选关联单词），标签筛选、搜索 / 增删改查，UUID + 软删除，可同步
├── 设置：学习设置（口音 / 每组新词 / 每组复习 / 拼写题量）、同步状态与立即同步、发音缓存清理、JSON 导出与恢复、Markdown 导出、清空、关于
├── 发音：mp3 本地缓存，网络失败 TTS 兜底
└── 云同步：复习进度 / 笔记 / 自建单词本，离线优先，失败不影响本地

已下线
├── 内置词库 words.json、考试练习、真题例句、考纲筛选
├── 收藏（本地与云端残留自动清理）
└── 错题本（`lapses` 字段保留给 SM-2 使用）

待实施
└── 可选：回前台自动同步、拼写选择题提示
```

早期设想但**未实现**的功能（真题长难句标注、派生树、听写模式、跟读打分、考前冲刺等）仍留在 `docs/research/`，需要时再单独评估。

---

## 3. 技术栈（实际）

| 层 | 选型 | 版本 / 位置 | 备注 |
|---|---|---|---|
| 框架 | Flutter | 3.50.0 | `E:\flutter_sdk\flutter` |
| UI | material_ui | ^1.11.0 | 不要用已弃用的 `flutter/material.dart` |
| 状态管理 | ChangeNotifier | `lib/app_state.dart` | 单一全局 `AppState`；Riverpod 未引入（D12） |
| 本地存储 | sqlite3 手写 SQL | `lib/data/progress_store_native.dart` | drift 未引入（D11） |
| Web 存储 | localStorage | `lib/data/progress_store_web.dart` | 键 `es_review_v1` / `es_notes_v1` / `es_books_v1` |
| 云端 | PostgREST（CloudBase PG） | `lib/data/cloud_sync.dart` | 不用 CloudBase SDK（D20） |
| 间隔重复 | 自实现 SM-2 | `lib/domain/srs.dart` | 约 50 行 + 单测 |
| HTTP | http | ^1.6.0 | 不用 dio |
| 音频 | audioplayers + flutter_tts | ^6.8.1 / ^4.2.3 | dictvoice 播放 + 缓存 + TTS 兜底 |
| 导出 | share_plus + Blob | ^10.1.4 | 原生系统分享，Web 浏览器下载 |

**待决策项**：D05（SM-2 还是 FSRS-6）、D08（是否引入 Riverpod）——都在 `decisions.md` 中保持开放。

---

## 4. 环境与常用命令

| 项 | 值 |
|---|---|
| Flutter | 3.50.0（`E:\flutter_sdk\flutter`，`shared.bat` 有一行退出码补丁，见 ISSUE-023） |
| JDK | 17（`D:\Javadevelop\jdk-17.0.20.1+1`） |
| Android SDK | `E:\Android\Sdk`（platform 36 / build-tools 36.0.0 / NDK 28.2） |

```bash
dart pub get                          # 依赖解析（不要用 flutter pub get）
flutter analyze --no-pub              # 静态检查
flutter test --no-pub                 # 单元 + Widget 测试
preview_web.cmd                       # 电脑端预览（Edge，端口 8091）
build_apk.cmd                         # 打包 APK → E:\APK\app-release.apk
```

注意事项：
- 所有 `flutter` 命令要带 `--no-pub`；agent 在 shell 中调用需独立控制台启动（ISSUE-024）。
- 构建产物不要落工作区 `build/`（文件监视器会回收，ISSUE-025 / ISSUE-029）。
- Windows 桌面端本机缺 VS C++ 与开发者模式，无法构建（ISSUE-027）；日常用 Web 预览。
- 打包 APK 仅在明确需要时执行，不要每次改动都打包。

---

## 5. 云同步速查

| 项 | 值 |
|---|---|
| 基址 | `https://{envId}.api.tcloudbasegateway.com/v1/rdb/rest` |
| 鉴权 | `Authorization: Bearer {Publishable Key}`（anon） |
| 表 | `review_state`、`note`、`user_meta`（设置只存本地，不参与同步） |
| 触发 | 启动一次、回到前台静默同步（60 秒冷却）、设置页手动「立即同步」 |
| 用户隔离 | 所有请求带 `user_id=eq.{SyncConfig.userId}`（当前固定 `me`） |
| 冲突策略 | 复习 / 笔记按 `updated_at` 后写覆盖；自建单词本按书 id 并集，本地优先 |
| note 列 | `id` `user_id` `word_key` `title` `content` `tags` `created_at` `updated_at` `deleted`；旧库需补 `title` / `tags`（ISSUE-033） |
| 关闭方式 | `SyncConfig.enabled = false` → 纯本地运行 |

细节见 `docs/api.md` 第 2 节与 `docs/cloudbase_schema.sql`。

---

## 6. 常见问题

**Q: 为什么选 Flutter？**
A: 一套代码覆盖 Android / Web / 桌面，UI 一致；本项目只维护一个人的时间成本。

**Q: 为什么不用 Riverpod / drift？**
A: 只有一个全局 `AppState`，`ChangeNotifier` 足够；表只有 4 张，手写 SQL 比引入 build_runner 更省事。表数量 > 10 再考虑 drift（D11 / D12）。

**Q: 有声词典吗？**
A: 没有。释义来自自建词条；只有发音走有道 dictvoice，首次播放后缓存到本地，网络失败时用设备 TTS 朗读。

**Q: 有道接口挂了会怎样？**
A: 已缓存的词仍可离线发音；未缓存的词回退设备 TTS，学习流程不受影响。

**Q: 词库版权？**
A: 内置词库已下线；当前词条全部由用户自己导入，离线词典数据见 6.3（qwerty-learner 七本词书，个人自用，分发前需核验授权，ISSUE-016）。

**Q: 数据怎么迁移？**
A: 本地是标准 SQLite 文件；云端是普通 PostgreSQL 表。设置页可导出完整 JSON 与笔记 Markdown（Web 下载，原生系统分享）；JSON 可在设置页粘贴回填，按合并策略恢复。

---

## 7. 变更流程约定

| 事项 | 做法 |
|---|---|
| 技术选型变化 | 在 `decisions.md` 追加新条目，注明“推翻 Dxx” |
| 功能增删 | 先更新 `architecture.md` + `README.md` 功能表，再改代码 |
| 新坑 | 追加 `known-issues.md`（写日期、根因、规避） |
| 接口变化 | 同步 `api.md` 与 `cloudbase_schema.sql` |
| 每次开发会话 | 在 `PROJECT_MEMORY.md` 追加本次结论 |

> 文档第一原则：让人能判断“代码现在到底在做什么”。未接入的东西必须显式标注「未接入」。

---

## 8. 参考项目

| 项目 | 借鉴点 |
|---|---|
| Anki | FSRS 调度器、review 日志 |
| Echo Loop（Dart/Flutter） | 纯 Dart 英语 APP 结构 |
| My Vocabulary（Flutter + Isar） | 词卡交互 |
| 不背单词 | 词根词缀 + 真题例句 + 考义加粗的产品组合 |
