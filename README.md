# english_study

跨端英语学习工具：英美双发音、四六级/考研词库、拼写练习、错题本与笔记。

## 功能

| 模块 | 说明 |
|---|---|
| 词库浏览 | 内置 `assets/data/words.json`（CET-4 / CET-6 / 考研），离线可用 |
| 单词卡片 | 自实现 SM-2 间隔重复，四档反馈（重来 / 难 / 一般 / 简单） |
| 拼写练习 | 听音拼写、看义拼写，编辑距离容错 + 逐字母提示 |
| 发音 | 有道 dictvoice，英音 / 美音可切换（需联网） |
| 我的 | 收藏 / 错题本 / 笔记 / 自建词 / 设置 |
| 学习统计 | 每日新学与复习记录、连续天数 |
| 词根词缀 | 自建词缀库 + 保守匹配的专题页 |
| 云同步 | 直连 PostgREST（可选，未配置时不影响本地使用） |

## 目录结构

```
English/
├── lib/
│   ├── main.dart                 入口
│   ├── app_state.dart            全局状态（ChangeNotifier）+ 业务编排
│   ├── data/                     仓储与持久化
│   │   ├── word_repository.dart  词库加载
│   │   ├── affix_repository.dart 词缀库加载
│   │   ├── progress_store.dart   条件导出（native / web / stub）
│   │   ├── progress_store_native.dart
│   │   ├── progress_store_web.dart
│   │   ├── cloud_sync.dart       PostgREST 同步
│   │   ├── sync_config.dart
│   │   ├── note_record.dart
│   │   └── daily_stat.dart
│   ├── domain/                   纯逻辑，无 IO、可单测
│   │   ├── word.dart  affix.dart  srs.dart
│   │   ├── edit_distance.dart  spelling_hints.dart
│   │   └── custom_word_parser.dart
│   ├── services/
│   │   └── audio_service.dart    dictvoice 播放
│   └── ui/                       页面（复习 / 拼写 / 词库 / 统计 / 我的 …）
├── assets/data/                  words.json、affixes.json
├── android/  ios/  macos/  windows/  web/    各端工程
├── docs/                         文档（见下）
│   └── research/                 早期调研与避坑记录
├── scripts/                      构建与验证脚本
├── test/widget_test.dart
├── build_apk.cmd                 Android 一键打包
├── PROJECT_MEMORY.md             开发历程与经验沉淀
└── HANDOVER.md                   交接说明
```

## 环境要求

| 项 | 本机路径 / 版本 |
|---|---|
| Flutter | 3.50.0（`E:\flutter_sdk\flutter`） |
| JDK | 17（`D:\Javadevelop\jdk-17.0.20.1+1`） |
| Android SDK | `E:\Android\Sdk`（platform 36、build-tools 36.0.0、NDK 28.2.13676358、CMake 3.22.1） |
| Gradle 缓存 | `%LOCALAPPDATA%\Temp\gradle-home`（由脚本注入，不写工作区） |

## 常用命令

```bash
flutter pub get
dart analyze
flutter test
flutter run -d chrome        # Web
flutter run -d windows       # Windows 桌面（需已修好插件 junction）
flutter run -d <设备ID>       # Android 真机
```

## 打包 Android APK

双击 `build_apk.cmd`，产物输出到 `E:\APK\app-release.apk`。

脚本做三件事：把源码同步到 `%TEMP%\english_build` → 在该副本里直接调用 `flutter build apk --release` → 复制 APK 到输出目录。

> 为什么不在工作区直接构建：Trae 的文件监视器会在编译期间回收 `build/` 下的 Kotlin 增量缓存，导致构建随机失败；`jni` 插件还要往 Pub 缓存里写 `.cxx` 中间产物。脚本用独立的 `PUB_CACHE` 和副本目录规避了这两点。详见 `docs/known-issues.md`。

## 文档

| 文件 | 内容 |
|---|---|
| [docs/architecture.md](docs/architecture.md) | 技术栈、代码结构、数据流 |
| [docs/api.md](docs/api.md) | 外部接口约定（dictvoice、同步接口） |
| [docs/conventions.md](docs/conventions.md) | 编码 / Git / 测试约定 |
| [docs/decisions.md](docs/decisions.md) | 技术决策记录 D01–D27 |
| [docs/known-issues.md](docs/known-issues.md) | 已知问题与规避方案 |
| [docs/research/](docs/research/) | 早期产品调研、API 实测与避坑指南 |
| [HANDOVER.md](HANDOVER.md) | 交接文档 |
| [PROJECT_MEMORY.md](PROJECT_MEMORY.md) | 逐次开发会话的经验沉淀 |
