# english_study

跨端英语学习工具：自建单词本、四选一学习卡、拼写练习、笔记与云同步。

## 功能

| 模块 | 说明 |
|---|---|
| 今日 | 签到卡、待复习 / 今日已学数字块、开始学习与拼写入口 |
| 学习 | 自建词四选一，答对答错自动评分，到期词按可配置上限分批，词池不足时降级自评四档 |
| 词单 | 自建单词本增删改查，导入 / 编辑 / 删除词条；支持词性与多释义；加词时离线词典自动带出音标与释义 |
| 拼写练习 | 发音与释义同时展示，编辑距离容错 + 四级提示（首字母 / 音节 / 词根 / 四选一） |
| 笔记 / 词根词缀 / 统计 | 时间线小记（标题 / 标签 / 可选关联单词）、词缀拆解、每日记录与连续天数 |
| 发音 | 有道 dictvoice，首次播放后本地缓存；网络失败用设备 TTS 兜底 |
| 设置 | 发音口音、每组新词数、每组复习数、拼写题量（本地持久化） |
| 数据 | 设置页导出完整 JSON 与笔记 Markdown，并可从 JSON 合并恢复 |
| 云同步 | 直连 PostgREST（可选）；启动与回到前台自动同步，也可手动立即同步 |

## 目录结构

```
English/
├── lib/
│   ├── main.dart                 入口与三 Tab 导航
│   ├── app_state.dart            全局状态（ChangeNotifier）+ 业务编排
│   ├── data/                     仓储与持久化
│   │   ├── affix_repository.dart 词缀库加载
│   │   ├── dictionary_repository.dart 离线词典加载（dict_core.json）
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
│   │   ├── learning_quiz.dart    四选一与自动评分
│   │   ├── export_builder.dart   JSON / Markdown 导出内容
│   │   └── custom_word_parser.dart
│   ├── services/
│   │   ├── audio_service.dart    dictvoice 播放 + 缓存 + TTS 兜底
│   │   ├── audio_cache.dart      发音缓存（条件导出）
│   │   └── export_service.dart   导出落盘（条件导出）
│   └── ui/                       页面（今日 / 学习 / 词单 / 拼写 / 我的 …）
├── assets/data/                  affixes.json、dict_core.json
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
dart pub get                  # 依赖解析（不要用 flutter pub get）
flutter analyze --no-pub
flutter test --no-pub
node scripts/build_dict_assets.js  # 重新生成离线词典 dict_core.json
preview_web.cmd               # 电脑端预览（Edge，端口 8091）
flutter run -d <设备ID>        # Android 真机
```

> Windows 桌面端在本机缺 VS C++ 工作负载与开发者模式，当前无法构建（见 `docs/known-issues.md` ISSUE-027），日常用 Web 预览。

## 打包 Android APK

双击 `build_apk.cmd`，产物输出到 `E:\APK\app-release.apk`。

脚本做三件事：把源码同步到 `%TEMP%\english_build` → 在该副本里直接调用 `flutter build apk --release` → 复制 APK 到输出目录。

> 为什么不在工作区直接构建：Trae 的文件监视器会在编译期间回收 `build/` 下的 Kotlin 增量缓存，导致构建随机失败；`jni` 插件还要往 Pub 缓存里写 `.cxx` 中间产物。脚本用独立的 `PUB_CACHE` 和副本目录规避了这两点。详见 `docs/known-issues.md`。

## 文档

| 文件 | 内容 |
|---|---|
| [docs/requirements-v1.md](docs/requirements-v1.md) | 需求与界面方案 v1（M1–M10 已实现） |
| [docs/architecture.md](docs/architecture.md) | 技术栈、代码结构、数据流 |
| [docs/api.md](docs/api.md) | 外部接口约定（dictvoice、PostgREST 同步、本地存储） |
| [docs/conventions.md](docs/conventions.md) | 编码 / 构建 / 测试 / Git 约定 |
| [docs/decisions.md](docs/decisions.md) | 技术决策记录 D01–D40 |
| [docs/known-issues.md](docs/known-issues.md) | 已知问题与规避方案 |
| [docs/research/](docs/research/) | 早期产品调研、API 实测与避坑指南 |
| [HANDOVER.md](HANDOVER.md) | 交接文档 |
| [PROJECT_MEMORY.md](PROJECT_MEMORY.md) | 逐次开发会话的经验沉淀 |
