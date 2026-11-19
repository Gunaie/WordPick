# 项目交接文档

> English Study Tool — 英语学习跨端应用（Flutter + CloudBase）
> 版本：v0.1（核心学习流程已实现，可运行）
> 最后更新：2026-11-02
> 交接对象：开发者 / 协作者 / 未来的自己

---

## TL;DR · 5 分钟读完

**这是一个什么项目**：个人用的英语学习 APP，手机（Android/iOS）、电脑（Win/macOS）、网页三端共用数据。功能覆盖四六级、考研英语备考，带英美双发音、拼写练习、错题本、笔记。

**为什么不背单词做参考**：它用了"词根词缀 + 真题例句精确标注 + 派生树 + 考义加粗"这套组合拳，其他竞品没有。我们要抄的就是这套结构，加上竞品没有的拼写练习和跨端同步。

**技术栈一句话**：Flutter 3.50.0（六端一套代码，本机装于 `E:\flutter_sdk\flutter`）+ material_ui（Flutter 3.50 起 `package:flutter/material.dart` 已弃用的官方后继）+ sqlite3 直连（桌面本地库）+ localStorage（Web 本地库）+ 自实现 SM-2（间隔重复）+ 内置 4441 词词库（零网络查词）+ 有道 dictvoice（英美双音）+ CloudBase PostgREST（跨端同步）。

**现在的状态**：v0.6 已可运行，**Web 与 Windows 桌面双端均已构建验证**。功能：4441 词内置词库、单词卡片（英美双音 + 词形拆解）、SM-2 复习、听音拼写、词库浏览、词根词缀专题、学习统计（14 天柱状图 / 连续天数）、「我的」（收藏/错题/笔记/自建词/设置）。**跨端同步覆盖全部个人数据**：复习进度、笔记（UUID + 软删除）、收藏、自建词；设置页可一键清空本机与云端。本地：Web 用 localStorage，桌面用 SQLite；云端 CloudBase PG 模式（PostgREST 直连）。

---

## 1. 必须先读的文件（按顺序）

| 顺序 | 文件 | 读什么 |
|---|---|---|
| ① | `docs/decisions.md` | 所有技术决策，每条带理由和替代方案 |
| ② | `docs/architecture.md` | 当前架构事实：技术栈、代码结构、数据流 |
| ③ | `深度调研与避坑指南.md` | 所有 API 实测数据 + 坑清单 + 存储最终方案 |
| ④ | `docs/api.md` | 有道/FD/CloudBase 接口的参数、URL、响应结构 |
| ⑤ | `docs/conventions.md` | 编码约定：命名、错误处理、测试、Git |
| ⑥ | `docs/known-issues.md` | 已发现的坑和缓解措施 |
| ⑦ | `调研-大白话版.md` | 产品定位 + 功能清单（P0/P1/P2/P3） |
| ⑧ | `调研-专业版.md` | 数据库设计 + 迭代路线图 |

---

## 2. 项目功能全景（按优先级）

```
P0 · MVP（Week 1-12）
├── F0.1  单词卡片（英美双音 + 考纲标签）
├── F0.2  SM-2 间隔重复调度
├── F0.3  官方考纲词表（CET-4/6 + 考研，先高频子集）
├── F0.4  账号 + 跨端同步（CloudBase 实时 watch）
├── F0.5  自建词库（CSV/Excel 导入）
└── F0.6  听音拼写（typo 容错，编辑距离 ≤ 1）

P1 · 进阶（v1.1-1.2）
├── 词根词缀拆解（溯源）
├── 真题例句（精确标注：年份 + section + 题型）
├── 易混易错词 + 拼写纠错练习
├── 错题本（手动 + 自动收集反复遗忘词）
├── 笔记（Markdown）
├── 看义拼写（给中文写英文，三级提示）
└── 用户自定义标签

P2 · 增强（v2.0）
├── 派生树（词根 → 单词族可视化）
├── 考频 + 题型标注（阅读/写作/听力/翻译分题型高频）
├── 长难句拆解（主句/从句/语法结构）
├── 考前冲刺模式（倒计时 → 自动排程）
├── CET 听写模式
├── FSRS-6 算法升级（dart_srs 包）
└── Whisper 跟读打分

P3 · 差异化（竞品没有的）
├── 遗忘预警（主动 push "这 5 个词你快忘了"）
├── 每日长难句推送 + 学习日记
├── 词根词缀主动回忆练习
├── 数据全导出（Notion/Excel/MD/JSON）
├── 学习路径自动规划（"3个月过六级" → 算每日任务）
├── 写作高级替换词包
└── 自建词库 TTS 兜底
```

---

## 3. 技术栈（已定）

| 层 | 选型 | 版本 | 为什么 |
|---|---|---|---|
| 框架 | Flutter | ≥ 3.22.0 | 一套代码六端 |
| 语言 | Dart | ≥ 3.4.0 | 随 Flutter |
| 状态管理 | Riverpod v2 | ≥ 2.6.1 | Flutter 官方推荐，Provider 作者写的现代版 |
| 本地 ORM | drift | ≥ 2.20.0 | 类型安全，Windows 支持 |
| 云端 | CloudBase | SDK 1.2.2 | 国内 20ms，Flutter 全平台 |
| SRS | flutter_spaced_repetition | ≥ 0.2.0 | SM-2 生产级纯 Dart |
| HTTP | dio | ≥ 5.7.0 | 重试 + 超时 + 熔断 |
| 音频 | audioplayers | ≥ 6.1.3 | 跨平台 |
| TTS | flutter_tts | ≥ 4.2.0 | 自建词库兜底 |

**⚠️ 待决策项**：D05（SM-2 还是直接上 FSRS？Anki 2024 已换 FSRS，dart_srs 包已就绪）+ D08（状态管理 Riverpod 还是 Provider？）

---

## 4. Week 1 前置清单（不做完做不了 Week 2）

| # | 任务 | 时间 | 验收标准 |
|---|---|---|---|
| 1 | `flutter doctor` 全绿 + Windows Desktop workload | 2h | `flutter run -d windows` 能出 exe |
| 2 | CloudBase 免费环境 + 兑换码 | 30min | 拿到 envId |
| 3 | 手动整理 CET-4 高频 2000 词 CSV | 4-6h | `words.csv` 有 phonetic、exam_tags 字段 |
| 4 | drift schema + 代码生成 | 1h | `dart run drift_dev build` 成功 |
| 5 | 有道 + FD + 熔断代码单元测试 | 2h | 连续调用 10 次有道，400ms 以下 |
| 6 | CloudBase RLS + 匿名登录 | 1h | 注册后能看到空 user_words 表 |
| 7 | README.md + 开发环境文档 | 30min | 新人按文档 30min 跑起来 |

---

## 5. API 实测数据（已验证）

```dart
// 有道 dict.youdao.com — 主源
// 实测速度：英音 94ms, 美音 52ms, 查词 90ms
// 音频 URL 拼接：http://dict.youdao.com/dictvoice?type={0|1}&audio={word}

// Free Dictionary — fallback
// 实测：10词串行 16s（1619ms/词），只有美式音频，无中文
// GET https://api.dictionaryapi.dev/api/v2/entries/en/{word}

// SRS 包
// flutter_spaced_repetition: SM-2 / SM-2+，pub.dev 最新
// dart_srs: FSRS-6，可插拔，v2.0 升级目标
```

---

## 6. 目录结构（实际）

```
English/
├── docs/                          文档
│   ├── architecture.md            技术栈 / 代码结构 / 数据流（当前实现）
│   ├── api.md                     外部接口约定
│   ├── conventions.md             编码 / Git / 测试约定
│   ├── decisions.md               技术决策 D01–D27
│   ├── known-issues.md            已知问题与规避
│   ├── cloudbase_schema.sql       云端建表与授权
│   └── research/                  早期调研（大白话版 / 专业版 / 避坑指南）
│
├── lib/                           Flutter 代码
│   ├── main.dart                  入口
│   ├── app_state.dart             全局状态 + 业务编排
│   ├── data/                      仓储 / 持久化 / 云同步
│   ├── domain/                    纯逻辑（SRS / 拼写 / 解析）
│   ├── services/                  发音播放
│   └── ui/                        页面
│
├── assets/data/                   words.json、affixes.json
├── android/ ios/ macos/ windows/ web/    各端工程
├── scripts/                       fix_plugin_links.ps1、build_word_assets.js、parse_probe.dart、build_windows.bat
├── test/widget_test.dart
│
├── build_apk.cmd                  Android 一键打包（产物 E:\APK\app-release.apk）
├── README.md                      项目说明与常用命令
├── HANDOVER.md                    本文件
└── PROJECT_MEMORY.md              开发历程与经验沉淀
```

---
## 7. 常见问题 FAQ

**Q: 为什么选 Flutter 而不是 React Native？**
A: Flutter 一套代码出六端，Windows 桌面端 CI 已稳定。RN 在 Windows 上基本没官方支持。Flutter UI 一致性 100%。

**Q: 为什么放弃 Supabase/Firebase？**
A: 国内延迟 200ms+，实时同步卡顿。CloudBase 实测 20-40ms。

**Q: 有道接口稳定吗？**
A: 是网易 APP 内部接口，随时可能封。已做：500ms 超时 + 3 次失败熔断 10 分钟 + FD fallback + 本地缓存。长期可接有道智云付费 API（约 ¥0.001/次）。

**Q: 静态词表打包进 APP 为什么？**
A: 省 CloudBase 资源点（不走云端）、秒开、离线可用。考纲每年变 <5%，发版时更新即可。

**Q: SM-2 还是 FSRS？**
A: D05 待重开。Anki 2024.11 刚把 FSRS 设为默认。`dart_srs` 包已支持 FSRS-6。如果直接上 FSRS，不用 v2.0 再迁移，但 FSRS 比 SM-2 复杂。

**Q: 数据导出/换工具怎么办？**
A: 所有数据（本地 SQLite + CloudBase）都有标准导出方式。P3 规划了"数据全导出"功能，支持导出到 Notion/Excel/MD/JSON。

---

## 8. 联系 & 后续

| 事项 | 怎么做 |
|---|---|
| 继续开发 | 按 Week 1 清单开始，遇到技术决策 → 更新 `decisions.md` |
| 功能变更 | 更新 `调研-大白话版.md` + 同步 `architecture.md` 的变更点 |
| 遇到新坑 | 追加 `known-issues.md`（带发现日期）|
| 改 API 契约 | 更新 `api.md` + 标注变更版本 |
| 版本发布 | 记录到 `PROJECT_MEMORY.md`（仓库外的 memory_root）|

---

## 9. 参考项目（可以借鉴的）

| 项目 | 语言 | 借鉴点 |
|---|---|---|
| Anki（ankitects/anki） | Rust + TS | FSRS 调度器、review 日志 |
| Echo Loop（hysenlabs/echo-loop） | Dart/Flutter | 纯 Dart 的英语 APP，AGPL 开源 |
| My Vocabulary（m1ra7/vocabulary） | Flutter + Isar | Flutter + NoSQL 词卡 APP |
| 不背单词（bbdc.cn） | 闭源 | 词根词缀 + 真题例句 + 考义加粗的产品组合 |
| CloudBase Flutter SDK 示例 | — | 官方多端示例 |
