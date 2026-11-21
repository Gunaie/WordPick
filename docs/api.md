# 接口约定

> 本文记录**当前代码实际使用**的对外接口与内部接口。
> 技术选型的历史背景见 `decisions.md`；早期调研与实测数据见 `docs/research/`。
> 接口稳定性：🟢 稳定 / 🟡 灰色（内部接口，可能随时变） / ⚪ 仅设计稿（未接入）

---

## 0. 现状总览

| 接口 | 状态 | 代码位置 | 说明 |
|---|---|---|---|
| 有道 dictvoice 发音 | 🟡 已接入 | `lib/services/audio_service.dart` | 英 / 美双音 mp3，本地缓存 + TTS 兜底 |
| CloudBase PostgREST 同步 | 🟢 已接入（可选） | `lib/data/cloud_sync.dart` | 3 张表增删改查，未配置时纯本地运行 |
| 本地存储（sqlite3 / localStorage） | 🟢 已接入 | `lib/data/progress_store*.dart` | 见第 3 节 |
| 有道 jsonapi 查词 | ⚪ 未接入 | — | 释义来自自建词条与离线词典（M3B） |
| Free Dictionary API | ⚪ 未接入 | — | 原 fallback 方案，`DictionaryService` 已删除 |
| 系统 TTS（flutter_tts） | 🟢 已接入（兜底） | `lib/services/audio_service.dart` | 网络发音失败时朗读，Web 走 SpeechSynthesis |
| CloudBase Flutter SDK | ⚪ 未使用 | — | 改为 http 直连 PostgREST（D20） |
| drift ORM | ⚪ 未使用 | — | 改为 sqlite3 手写 SQL（D11） |
| 词典熔断器 | ⚪ 未实现 | — | 只存在于早期设计（D10），现无该代码 |

> 也就是说：应用只有一个真实的外部网络依赖——`dict.youdao.com`（发音），
> 外加一个可开关的同步依赖——CloudBase PostgREST。

---

## 1. 发音：有道 dictvoice（🟡 灰色接口）

| 项 | 值 |
|---|---|
| URL | `https://dict.youdao.com/dictvoice?type={0\|1}&audio={word}` |
| `type=0` | 美式发音 |
| `type=1` | 英式发音 |
| 音频格式 | MP3（约 10 KB / 词） |
| 实测延迟 | 52–94 ms |
| 超时 | 缓存下载 4 s；播放失败回退设备 TTS，不中断学习流程 |
| 缓存 | 应用缓存目录 `pronunciation/word_type.mp3`，命中直接播本地（D35） |

```dart
// lib/services/audio_service.dart
static String urlFor(String word, {required bool uk}) {
  final type = uk ? 1 : 0;
  return 'https://dict.youdao.com/dictvoice'
      '?type=$type&audio=${Uri.encodeComponent(word)}';
}
```

- 播放顺序：本地缓存 → 下载并缓存 → `UrlSource` 在线播放 → 设备 TTS。
- 默认口音是英音（`AudioService.isUk = true`）；设置页可切换英 / 美音，选择存本地并在启动时写回。
- 风险：属于未公开接口，可能随时失效或被限流；已缓存词仍可离线播放，未缓存词由 TTS 兜底。

---

## 2. 云同步：CloudBase PostgREST（🟢 已接入，可关闭）

### 2.1 连接信息

| 项 | 值 |
|---|---|
| 基址 | `https://{envId}.api.tcloudbasegateway.com/v1/rdb/rest` |
| envId | 见 `lib/data/sync_config.dart` |
| 鉴权 | `Authorization: Bearer {Publishable Key}`（anon 角色） |
| 其他请求头 | `Content-Type: application/json`、`x-device-id` |
| 写入头 | `Prefer: resolution=merge-duplicates,return=minimal`（按主键 upsert） |
| 超时 | 12 秒（`CloudSync._timeout`） |
| 用户过滤 | 所有请求自动带 `user_id=eq.{SyncConfig.userId}`；当前固定为 `me`，多端填同一个值即可互通 |
| 开关 | `SyncConfig.enabled`，关闭后完全离线 |

> Publishable Key 是 anon 角色密钥，可随客户端分发；**禁止**把 `service_role` 密钥写进客户端。

### 2.2 数据表

| 表 | 主键 | 字段 | 用途 |
|---|---|---|---|
| `review_state` | `(user_id, word_key)` | `ease` `interval` `reps` `lapses` `due` `updated_at` `stability` `difficulty` `fsrs_state` `fsrs_step` `last_review` | 每词复习状态（v0.22 起默认 FSRS-6，SM-2 字段保留用于回滚；旧库需 ALTER 加 FSRS 列，见 ISSUE-035） |
| `note` | `id` | `user_id` `word_key` `title` `content` `tags` `created_at` `updated_at` `deleted` | 笔记（UUID + 软删除；`title` / `tags` 需旧库 ALTER，见 ISSUE-033） |
| `user_meta` | `(user_id, key)` | `value` `updated_at` | 键值 JSON：自建单词本 `custom_books`、易混词组 `confusable_groups` 等 |

建表与授权 SQL 见 `docs/cloudbase_schema.sql`。

### 2.3 调用方法

| 方法 | 请求 | 说明 |
|---|---|---|
| `pullReviewStates()` | `GET review_state?select=*&user_id=eq.me` | 全量拉取，返回 `Map<wordKey, ReviewState>` |
| `pushReviewStates(states)` | `POST review_state`（数组） | 批量 upsert |
| `pullNotes()` | `GET note?select=*&user_id=eq.me` | 含已软删除记录，好让删除动作同步下去 |
| `pushNotes(notes)` | `POST note`（数组） | 按 `id` upsert |
| `pullMeta()` | `GET user_meta?select=key,value&user_id=eq.me` | 返回 `Map<String, String>` |
| `pushMeta(values)` | `POST user_meta`（数组） | 按 `(user_id,key)` upsert |
| `deleteMeta(key)` | `DELETE user_meta?key=eq.{key}&user_id=eq.me` | 清理已下线功能的残留键 |
| `wipeAll()` | `DELETE` 三张表 | 「清空数据」时本地 + 云端一起清（D26，不可撤销） |

### 2.4 合并策略

- 复习状态：以 `updated_at` 为准，后写覆盖先写（LWW，D22）。
- 笔记：按 `id` 合并，`deleted=true` 视为删除。
- 自建单词本：按书 `id` 合并；本地内容优先，与远端 JSON 有差异即回推。
- 同步失败不阻塞启动，也不丢本地数据；下次回前台、启动或手动同步时重试。
- 自动同步时机：启动一次；应用回到前台（Web 为标签页重新可见）时触发，60 秒冷却，手动「立即同步」不受限。

---

## 3. 本地存储接口（🟢 已接入）

统一入口 `ProgressStore`（`lib/data/progress_store.dart` 条件导出）：

| 平台 | 实现 | 介质 |
|---|---|---|
| Android / iOS / Windows / macOS | `SqliteProgressStore` | sqlite3 手写 SQL |
| Web | `WebProgressStore` | localStorage |
| 兜底 / 测试 | `MemoryProgressStore` | 内存 |

主要方法：

```dart
Future<Map<String, ReviewState>> loadAll();
Future<void> upsert(String wordKey, ReviewState state);

Future<List<NoteRecord>> loadNotes();          // 未删除
Future<List<NoteRecord>> loadAllNotes();       // 含软删除，用于同步
Future<NoteRecord> addNote(String wordKey, String content);
Future<void> updateNote(String id, String content);
Future<void> deleteNote(String id);            // 软删除
Future<void> upsertNote(NoteRecord note);      // 同步落库
Future<void> hardDeleteNote(String id);

Future<List<Map<String, dynamic>>> loadCustomBooks();
Future<void> saveCustomBooks(List<Map<String, dynamic>> books);
Future<List<Map<String, dynamic>>> loadLegacyCustomWords();  // 旧扁平结构，仅迁移用
Future<void> clearLegacyCustomWords();

Future<void> recordStudy(String day, {required bool isNewWord});
Future<List<DailyStat>> loadDaily();
Future<void> clearAll();
```

存储位置：

| 平台 | 位置 / 键 |
|---|---|
| 原生 | 应用文档目录下 SQLite 文件；表 `review_state` / `note` / `daily_stat` / `meta` |
| Web | `es_review_v1`、`es_notes_v1`、`es_books_v1`、`es_daily_v1`、`es_settings_v1` 等 localStorage 键；旧 `es_custom_v1` 启动时迁移，`es_favorites_v1` 直接清除 |

---

## 4. 未接入的历史设计（仅存档）

以下内容曾在早期设计或调研中出现，**当前代码中多数已不存在**，保留为避免误导与方便日后重开：

- **有道 jsonapi 查词**：`dicts=ec.basic,phonetic`，实测约 90 ms。当年作为「自建词查释义」方案，后被「释义只来自打包词表 + 用户手填」（D16）取代。
- **Free Dictionary API**：`https://api.dictionaryapi.dev/api/v2/entries/en/{word}`，实测 1.6 s/词，英音缺失率高，已随 `DictionaryService` 一起删除。
- **系统 TTS 兜底**：已由 M5 重新接入 `flutter_tts`，见 D35。
- **CloudBase Flutter SDK**：`cloudbase_flutter` 会带进 `shared_preferences` 等插件、且不含 `watch()`；改为 http 直连 PostgREST（D20 / ISSUE-020）。
- **drift + drift_dev**：去掉代码生成环节，改手写 SQL（D11）。
- **熔断器**：D10 曾定「有道 500 ms 超时 + 连续 3 次失败熔断 10 分钟」，实际未落地；现在发音失败只是静默跳过。

需要这些接口的原始实测响应、字段说明与速率限制时，看 `docs/research/` 下的调研文档。
