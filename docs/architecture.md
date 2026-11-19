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
| 音频播放 | audioplayers | ^6.8.1 | `lib/services/audio_service.dart` |
| 文件路径 | path_provider + path | ≥2.1.6 | `path_provider`, `path` |
| 其他 | uuid（笔记 ID）、web（条件导出） | — | `uuid`, `web` |

> 与最初方案的差异：drift + build_runner 未采用（改手写 SQL）；Riverpod 未引入（D12）；
> 词典服务 `DictionaryService` 已移除，释义全部来自打包的 `words.json`（D16）。

## 平台支持

| 平台 | 状态 | 说明 |
|---|---|---|
| Android | ✅ 主要目标，真机验证通过 | API 24+；release 包需 `INTERNET` 权限 |
| Web | ✅ 次要目标 | localStorage 持久化 |
| Windows | ✅ 次要目标 | 需运行 `scripts/fix_plugin_links.ps1` 修插件 junction |
| iOS / macOS | ⚪ 保留工程，未验证 | — |
| Linux | ⚪ 未接入 | — |

---

## 代码结构

```
lib/
├── main.dart                      App 入口与页面装配
├── app_state.dart                 全局状态（ChangeNotifier）+ 业务编排 + 持久化调度
│
├── data/                          数据层（IO、仓储、同步）
│   ├── word_repository.dart       加载 assets/data/words.json
│   ├── affix_repository.dart      加载 assets/data/affixes.json
│   ├── progress_store.dart        条件导出：native / web / stub
│   ├── progress_store_native.dart sqlite3 实现（review_state/note/meta/daily_stat）
│   ├── progress_store_web.dart    localStorage 实现
│   ├── progress_store_stub.dart   兜底空实现
│   ├── cloud_sync.dart            PostgREST 同步（拉取 / 推送 / 清空）
│   ├── sync_config.dart           同步地址与密钥
│   ├── note_record.dart           笔记模型
│   └── daily_stat.dart            每日统计模型
│
├── domain/                        纯逻辑（无 IO，可单测）
│   ├── word.dart                  单词 / 释义 / 考纲标签模型
│   ├── affix.dart                 词根词缀模型
│   ├── srs.dart                   SM-2 调度
│   ├── edit_distance.dart         拼写容错判定
│   ├── spelling_hints.dart        逐字母提示
│   └── custom_word_parser.dart    自建词文本解析
│
├── services/
│   └── audio_service.dart         dictvoice 音源 + audioplayers 播放
│
└── ui/                            页面
    ├── review_page.dart           单词卡片复习
    ├── spelling_page.dart         拼写练习
    ├── quiz_page.dart  quiz_widgets.dart   选择题型
    ├── library_page.dart          词库浏览
    ├── exam_sentence_page.dart    真题长难句
    ├── affix_page.dart            词根词缀专题
    ├── stats_page.dart            学习统计
    └── profile_page.dart          我的（收藏 / 错题 / 笔记 / 自建词 / 设置）
```

---

## 数据流

### 启动

```
main() → AppState 初始化
  ├─ WordRepository.load()    ← assets/data/words.json（约 4.9 MB，一次读入内存）
  ├─ AffixRepository.load()   ← assets/data/affixes.json
  ├─ ProgressStore.load()     ← 原生 sqlite3 / Web localStorage
  └─ 可选：CloudSync.pull()   ← PostgREST，失败不阻塞启动
```

### 复习与拼写

```
用户操作（认识 / 模糊 / 不认识，或拼写判定）
  │
  ├─ srs.dart 计算下次复习时间
  ├─ AppState 更新内存状态 → notifyListeners()
  ├─ ProgressStore.save()     立即落本地
  └─ 累计写入 daily_stat（新学数 / 复习数）
```

### 同步（可选）

```
本地写入 → 标记待同步 → CloudSync.push()
  失败则保留本地数据，下次启动或手动触发时重试
冲突策略：按 updated_at 后写覆盖（D22）
```

---

## 本地数据表（sqlite3）

| 表 | 内容 |
|---|---|
| `review_state` | 每个词的学习状态（SM-2 参数、下次复习、错题标记） |
| `note` | 笔记（UUID + 软删除） |
| `daily_stat` | 每日新学 / 复习计数 |
| `meta` | 杂项键值（收藏、自建词、设置等） |

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
