# 已知问题

> 开发过程中发现的坑、待修复项、限制。每条含优先级、状态、负责人。
> 新发现问题追加到末尾，不要删除已修复的。
>
> **阅读提示**：早期条目（ISSUE-001～010）写在 drift / Riverpod / 三源词典 / TTS 方案时期，
> 其中部分「缓解措施」已随方案调整失效（词典服务整体移除、只保留 dictvoice 发音）。
> 已就地标注当前真实状态，`decisions.md` 中保留原始决策。

---

## HIGH · 必须解决

### ISSUE-001 · 有道 dictvoice 是灰色接口

| 项 | 内容 |
|---|---|
| 发现日期 | 2026-11-02 |
| 影响 | 有道可能随时封这个接口；目前发音**只有这一个来源**，失效则完全无音 |
| 当前实际 | 播放链路已加固：本地缓存 → 下载落盘（4s 超时）→ 在线播放（3s 超时）→ 设备 TTS 兜底；连续 3 次网络失败后**熔断 60s**，期间跳过网络直接走 TTS，避免逐词卡超时。FD fallback 未接入（D04 三源方案已弃用，见 decisions）。 |
| 长期方案 | 接入有道智云正式 API（付费但便宜，约 ¥0.001/次），或打包离线音频 |
| 状态 | 🟡 已有超时 + 熔断 + TTS 兜底缓解；长期仍依赖单一灰色接口 |

### ISSUE-002 · CloudBase 免费额度 6 个月后过期

| 项 | 内容 |
|---|---|
| 发现日期 | 2026-11-02 |
| 影响 | 免费环境到期后服务中断 |
| 缓解 | 到期前导出数据换免费环境；或按量付费（¥10-30/月） |
| 长期方案 | 自建 Postgres + MinIO（Docker 一台小机器） |
| 状态 | 🟡 已知，到时处理 |

### ISSUE-003 · Free Dictionary API 英音缺失率高

| 项 | 内容 |
|---|---|
| 实测 | "predict" 只返回美式音频；多个词同样情况 |
| 影响 | 若将来接回 FD，英音仍可能拿不到 |
| 当前实际 | FD **未接入**，`DictionaryService` 与 `flutter_tts` 依赖均已删除；条目仅作历史记录 |
| 状态 | ⚪ 不适用（方案已移除） |

---

## MEDIUM · 应该解决

### ISSUE-004 · Riverpod v2 和 drift 生命周期管理待细化

| 项 | 内容 |
|---|---|
| 问题 | drift Database 实例的 dispose 在 Riverpod 里怎么写还没验证 |
| 当前实际 | Riverpod 与 drift 均未采用（D11 / D12），该问题不存在 |
| 状态 | ⚪ 不适用（方案未采用） |

### ISSUE-005 · Flutter Windows 上 shared_preferences 行为差异

| 项 | 内容 |
|---|---|
| 问题 | Windows 上不支持部分 iOS/Android 的系统 API（如 App 间数据共享） |
| 当前实际 | `shared_preferences` 已不在依赖中；配置全部走 `sqlite3` / `localStorage` |
| 影响 | 我们不再依赖它，无风险 |
| 状态 | ⚪ 不适用 |

### ISSUE-006 · 自建词库 Excel 导入格式要严格

| 项 | 内容 |
|---|---|
| 问题 | 用户可能上传格式不对的文件导致导入崩 |
| 当前实际 | 暂不支持文件上传，只有「粘贴文本导入」；解析在 `lib/domain/custom_word_parser.dart`，非法行会被忽略并汇总提示 |
| 缓解 | 将来支持 Excel/CSV 时，导入前做严格校验 + 错误提示 |
| 状态 | ⚪ 待实现（文本导入已有） |

### ISSUE-007 · 词典缓存清理策略

| 项 | 内容 |
|---|---|
| 问题 | 所有查过的词都缓存本地，长期下来 SQLite 膨胀 |
| 当前实际 | 不做在线查词，也没有词典缓存表；SQLite 只存学习状态 / 笔记 / 自建词 |
| 状态 | ⚪ 不适用（若接回在线词典再重开） |

---

## LOW · 有空再说

### ISSUE-008 · 听力音频全部在线拉取

| 项 | 内容 |
|---|---|
| 问题 | 发音音频每次实时从有道拉取，离线时无音 |
| 缓解 | 首次播放先下载到应用缓存目录 `pronunciation/word_type.mp3`，命中直接播本地；网络失败回退设备 TTS；设置页可清理缓存（D35） |
| 状态 | ✅ 已实现（Web 端由浏览器管理 HTTP 缓存） |

### ISSUE-009 · Flutter 桌面端 MSIX 打包（Windows Store）

| 项 | 内容 |
|---|---|
| 问题 | Windows Store 打包有已知 crashpad_handler 名字问题 |
| 影响 | 个人项目可能不急着上 Store |
| 状态 | ⚪ 暂不处理 |

### ISSUE-010 · 考纲词表手工整理工作量大

| 项 | 内容 |
|---|---|
| 估计 | 手动整理 CET-4 4500 + CET-6 6000 + 考研 5500 = 16000 词 |
| 当前实际 | 不适用：内置词库已下线（2026-11-20），词条全部由用户自建词单导入 |
| 缓解 | M3B 已接入离线词典（qwerty-learner 词书，13,958 词），查不到时手填 |
| 状态 | ⚪ 已关闭（需求改为只使用自建词书） |

---

## 已修复（保留历史）

### FIXED-001 · 最初选了 Supabase 但国内太慢

| 项 | 内容 |
|---|---|
| 时间 | 2026-11-02 |
| 决策 | D02：放弃 Supabase → CloudBase |
| 状态 | ✅ 已解决 |

### FIXED-002 · 最初打算 Free Dictionary 做主力源

| 项 | 内容 |
|---|---|
| 实测 | 1.6s/词，10 词串行 16s |
| 决策 | D04：三源组合（有道主 + FD fallback + TTS 兜底） |
| 状态 | ✅ 已解决 |

---

# 执行阶段发现（2026-11-02 实机环境）

### ISSUE-011 · Windows 未开启开发者模式，无法构建带插件的应用 ✅

| 项 | 内容 |
|---|---|
| 现象 | `flutter build windows` 报错：`Building with plugins requires symlink support. Please enable Developer Mode` |
| 原因 | Flutter 的插件机制在 Windows 上依赖符号链接 |
| 解决 | 用**目录连接（Junction）**预建插件链接，无需开发者模式（见 D19） |
| 自动化 | `scripts/fix_plugin_links.ps1`（新增 Windows 插件后重跑一次即可） |
| 实测 | 构建 ✅ 83 秒；单元测试 ✅ 8/8；桌面程序启动正常，SQLite 表结构正确 |
| 状态 | ✅ 已解决 |

### ISSUE-012 · Flutter 3.47.9 `shared.bat` 的 `$git` 缺陷 ✅

| 项 | 内容 |
|---|---|
| 现象 | `flutter` 命令无输出、CPU 100% 空转，多个进程堆积，累计 CPU 数千秒 |
| 根因 | `D:\flutter_sdk\flutter\bin\internal\shared.bat` 第 75 行写的是 `$git rev-parse HEAD`（未定义变量），导致版本戳校验失败 → 反复重建快照 → `:acquire_lock` 无限重试 |
| 修复 | 改为 `git rev-parse HEAD` |
| 验证 | `flutter --version` 从"永久卡死"变为 4.5 秒返回 |
| 附带经验 | 一旦出现该症状，先 `Stop-Process` 清理所有 `cmd.exe /c flutter.bat` 残留进程并删除 `bin\cache\flutter.bat.lock` |
| 状态 | ✅ 已修复 |

### ISSUE-013 · Google 存储在中国网络下不稳定 ✅

| 项 | 内容 |
|---|---|
| 现象 | 从 `storage.googleapis.com` 下载 SDK 多次中断/连接被关闭 |
| 解决 | 改用官方中国镜像 `https://storage.flutter-io.cn`，并设置 `PUB_HOSTED_URL=https://pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn` |
| 效果 | 1.85 GB SDK 41 秒下载完成（约 44 MB/s） |
| 状态 | ✅ 已解决（环境变量已写入用户级） |

### ISSUE-014 · 后台 Shell 无法写入项目目录以外的路径

| 项 | 内容 |
|---|---|
| 现象 | 后台执行的下载/解压对 `E:\`、`D:\` 写入报 Permission denied，前台同样命令正常 |
| 原因 | 工具后台任务运行在受限沙箱中 |
| 应对 | 大文件下载/解压一律用**前台**命令，或先下载到允许写入的目录 |
| 状态 | ✅ 已知，规避即可 |

### ISSUE-015 · CloudBase Flutter SDK 包名易混淆 ✅

| 项 | 内容 |
|---|---|
| 现象 | pub.dev 上 `cloudbase_core` 停留在 0.0.11（2020 年），极易误判为"SDK 已废弃" |
| 事实 | 现行包名是 `cloudbase_flutter`（1.2.2，六端支持） |
| 另一个坑 | 该 SDK 不含 `watch()` 实时监听能力 |
| 状态 | ✅ 已澄清（见 decisions D14） |

### ISSUE-016 · 初始词库的授权风险 ✅

| 项 | 内容 |
|---|---|
| 现状 | `assets/data/words.json` 已随 M1 删除；离线词典 `dict_core.json` 取 qwerty-learner（MIT）整理的公开词书，仅个人自用 |
| 风险 | 词条来源较多，公开分发前仍需核验授权 |
| 建议 | 保持自建词单 + 开源授权词典 |
| 状态 | ✅ 已解决（内置词库下线，2026-11-20） |

### ISSUE-017 · Web 端进度不持久化 ✅

| 项 | 内容 |
|---|---|
| 现状 | 已改为 `localStorage` 持久化（D17）：复习状态、笔记、自建单词本三类数据均落盘 |
| 存储键 | `es_review_v1` / `es_notes_v1` / `es_books_v1`（旧版 `es_favorites_v1`、`es_custom_v1` 启动时自动清理/迁移） |
| 残留限制 | 隐私模式下 localStorage 不可用时会静默降级为内存；清浏览器数据会丢失 |
| 状态 | ✅ 已解决 |

### ISSUE-018 · `flutter test` 同样受开发者模式限制 ✅

| 项 | 内容 |
|---|---|
| 现象 | 加入插件后，`flutter test` 也报 `Building with plugins requires symlink support` |
| 解决 | 与 ISSUE-011 同一方案（Junction），实测 8/8 测试通过 |
| 经验 | 纯业务逻辑尽量抽成无 Flutter 依赖的函数（如 `parseCustomWords`），可用 `dart run` 单独验证 |
| 状态 | ✅ 已解决 |

---

# 云同步接入阶段（2026-11-03）

### ISSUE-019 · Publishable Key 与环境 project_id 不一致 ✅

| 项 | 内容 |
|---|---|
| 现象 | 所有接口返回 400，`oidc: token project_id does not match the requested env` |
| 根因 | Key 的 payload 里 `project_id` 为 `splen**g**id-...`，而环境是 `splen**d**id-...` |
| 排查方法 | 解码 JWT 第二段，比对 `project_id` 与 `aud` |
| 解决 | 重新复制正确的 Publishable Key |
| 状态 | ✅ 已解决 |

### ISSUE-020 · PG 模式下文档数据库接口不可用 ✅

| 项 | 内容 |
|---|---|
| 现象 | `db.collection().add()` 返回 `DATABASE_COLLECTION_NOT_EXIST` |
| 真实原因 | 环境是 PostgreSQL 模式，提示语明确写了 `provisioned with PostgreSQL instance [postgres-nb27zage]` |
| 解决 | 改用 `/v1/rdb/rest/{table}`（PostgREST），不再使用文档数据库 API |
| 状态 | ✅ 已解决（见 D20） |

### ISSUE-021 · anon 角色默认可读不可写 ✅

| 项 | 内容 |
|---|---|
| 现象 | 用 Publishable Key 写入报 `DATABASE_42501 permission denied for table` |
| 解决 | 执行 `grant select, insert, update, delete on table ... to anon;` |
| 编辑器误报 | 执行时编辑器提示"检测到 Supabase 内置角色"——误报，CloudBase PG 模式官方即使用 `anon/authenticated/service_role` |
| 状态 | ✅ 已解决 |

### ISSUE-022 · 内置预览面板访问 localhost 报 522 🟡

| 项 | 内容 |
|---|---|
| 现象 | 通过 IDE 预览打开应用返回 `522 Connection Timed Out` |
| 原因 | 预览走远程代理，回不到本机服务；服务本身正常（日志显示 200） |
| 规避 | 用系统浏览器直接打开 `http://localhost:8080`，或直接运行桌面 exe |
| 状态 | 🟡 已知，绕开即可 |

---

# 环境重建阶段（2026-11-19，SDK 迁到 E: + Flutter 3.50）

### ISSUE-023 · 当前 SDK：Flutter 3.50.0 装于 E:，含一行 shared.bat 补丁 🟢

| 项 | 内容 |
|---|---|
| 事实 | SDK 从旧的 `D:\flutter_sdk\flutter`（3.47.9）重装到 `E:\flutter_sdk\flutter`（3.50.0 / Dart 3.14.0），全程走 `flutter-io.cn` 中国镜像，sha256 校验通过 |
| 补丁 | `bin\internal\shared.bat` 第 109 行（"Everything is up-to-date" 成功路径）`EXIT /B` → `EXIT /B 0`。仅改这一行，用户已确认；`update_engine_version.ps1` 保持上游原样，勿动 |
| 区别 | 与 ISSUE-012 是两回事：ISSUE-012 是**旧 SDK** 的 `$git` 笔误，旧 SDK 已删除；本补丁针对**当前 SDK** 在非交互 shell 下的退出码问题（见 ISSUE-024） |
| 环境变量 | 用户级已设：`PATH` 追加 `E:\flutter_sdk\flutter\bin`；`PUB_HOSTED_URL=https://pub.flutter-io.cn`；`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn` |
| 状态 | 🟢 生效，勿随意还原补丁 |

### ISSUE-024 · Trae 非交互 shell 中 flutter.bat 启动卡死（100% CPU）🟡

| 项 | 内容 |
|---|---|
| 现象 | 在 Trae 后台/非交互 shell 直接调用 `flutter.bat`，无输出、CPU 100% 空转，进程堆积，`:acquire_lock` 无限重试 |
| 根因 | `update_engine_version.ps1` 内部一次 git 调用在此 shell 上下文返回非零，泄漏 `$LASTEXITCODE` → `:do_ensure_engine_version` 返回非零 → `EXIT 1` → `\|\| GOTO acquire_lock` 死循环 |
| 规避（agent 用） | 用 detached 干净控制台启动，重定向输出后前台等待；需 `dangerouslyDisableSandbox: true`（SDK 目录与 Pub 缓存 `%LOCALAPPDATA%\Pub\Cache` 在沙箱可写白名单外） |
| 规避示例 | `Start-Process -FilePath 'E:\flutter_sdk\flutter\bin\flutter.bat' -ArgumentList '<cmd>','--no-pub' -PassThru -WindowStyle Hidden -RedirectStandardOutput out.txt -RedirectStandardError err.txt` 然后 `$p.WaitForExit(600000)` |
| 重要 | 这只是 **agent shell 的限制**——用户自己的 PowerShell 窗口里 `flutter` 正常工作。`dart pub get` / `dart run` 可直接调用，无需此规避 |
| 状态 | 🟡 已知，按规避方案执行 |

### ISSUE-025 · Trae 文件监视器每次运行 flutter 都回收 engine.stamp 🟢

| 项 | 内容 |
|---|---|
| 现象 | 每次 `flutter` 运行，`bin\cache\engine.stamp` 被 Trae 文件监视器移入回收站 |
| 影响 | 无。Flutter 会自动重建该 stamp；实测 analyze / test / build 均正常完成 |
| 禁止 | 不要用工具/shell/脚本从回收站恢复（平台规则）。如遇异常，让用户手动在桌面回收站右键还原 |
| 状态 | 🟢 无害，Flutter 自建 |

### ISSUE-026 · material.dart 弃用 → 已迁移到 material_ui ✅

| 项 | 内容 |
|---|---|
| 背景 | Flutter 3.50 起 `package:flutter/material.dart` 被 `@Deprecated`，指向官方后继 `package:material_ui/material_ui.dart`（flutter/packages，要求 flutter >=3.47.0） |
| 决策 | 直接迁移，**不在** analysis_options 里压 `deprecated_member_use`。理由：material_ui 是官方钦定后继、与 3.50 兼容、import 替换机械且 API 兼容；压警告会掩盖未来真实弃用 |
| 动作 | `pubspec.yaml` 加 `material_ui: ^1.11.0`（解析到 1.11.1，连带 cupertino_ui / flutter_localizations / intl），10 个文件 import 替换 |
| 验证 | `flutter analyze` → 0 issue（迁移前 10 条 info 全部消除）；`flutter test` → 23/23 通过 |
| 状态 | ✅ 已完成 |

### ISSUE-027 · Windows 桌面端当前在本环境无法构建 🔴

| 项 | 内容 |
|---|---|
| 现状 | 未安装 Visual Studio / VS Build Tools 的 C++ 工作负载（vswhere 无结果，仅有 SSMS）；未开启开发者模式（注册表 `HKLM\...\AppModelUnlock\AllowDevelopmentWithoutDevLicense` 未设，需管理员） |
| 额外阻碍 | `flutter pub get` 的插件符号链接创建被沙箱 + Trae 文件监视器拦截（junction 也被回收），且项目在 E: / Pub 缓存在 C:，跨盘符符号链接本就不支持 |
| 规避 | 依赖解析一律用 `dart pub get`；所有 flutter 命令加 `--no-pub` 跳过符号链接检查 |
| 影响范围 | 仅 Windows 桌面构建受阻。**Web 构建、analyze、单元测试均不受影响**，已验证通过 |
| 恢复条件 | 需 UAC 安装 VS Build Tools C++ 工作负载 + 开启开发者模式，并在用户自己的终端（非 agent shell）里构建 |
| 状态 | 🔴 本环境受阻，Web 端可正常交付 |

---

# Android 真机落地阶段（2026-11-19）

### ISSUE-028 · release APK 缺少 INTERNET 权限，联网功能全部静默失效 ✅

| 项 | 内容 |
|---|---|
| 现象 | App 能正常打开，但词典、发音、云同步全部不可用，且**没有任何报错** |
| 根因 | Flutter 只为 debug 包自动注入 `android.permission.INTERNET`（`android/app/src/debug/AndroidManifest.xml`），release 包以主 manifest 为准，其中没有该权限 |
| 判定 | `aapt2 dump permissions app-release.apk` 只能看到 `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` |
| 修复 | 在 `android/app/src/main/AndroidManifest.xml` 显式声明 `<uses-permission android:name="android.permission.INTERNET"/>` |
| 验证 | 重新打包后 `aapt2 dump permissions` 可见 `android.permission.INTERNET`，真机联网功能恢复正常 |
| 教训 | 凡「debug 正常、release 不正常」且涉及网络，先查 manifest 权限 |
| 状态 | ✅ 已修复 |

### ISSUE-029 · 在工作区直接构建 APK 会被文件监视器打断 🟢

| 项 | 内容 |
|---|---|
| 现象 | `:audioplayers_android:compileReleaseKotlin` 失败：`Could not close incremental caches ... caches-jvm`；一次构建回收 100+ 个 `build/` 文件 |
| 根因 | Trae 文件监视器把工作区 `build/` 下的 Kotlin 增量缓存 `.tab` 文件移入回收站，而 Gradle 正在写这些文件 |
| 规避 | `scripts/build_apk.cmd` 把源码同步到 `%TEMP%\english_build`，在副本目录里构建；产物不会落进被监视的工作区 |
| 注意 | 不要试图用「把 build 放进 .gitignore」解决——监视器不看 gitignore |
| 状态 | 🟢 已规避 |

### ISSUE-030 · jni / sqlite3 原生构建需要写 Pub 缓存，默认路径不可写 🟢

| 项 | 内容 |
|---|---|
| 现象 | `:jni:configureCMakeRelWithDebInfo` 失败：`hash_key.txt` 访问被拒绝；此前 `flutter pub get` 也报 `active_roots` 拒绝访问 |
| 根因 | `jni` 插件把 CMake 中间产物（`.cxx/`）写在自己的包目录内，而包目录位于 `%LOCALAPPDATA%\Pub\Cache`，该路径不可写 |
| 规避 | 脚本内设 `PUB_CACHE=%LOCALAPPDATA%\Temp\pub-cache`，让插件在可写位置生成中间产物 |
| 连带问题 | 换缓存后 `pub get` 会为桌面端创建插件符号链接 → 报「requires symlink support / Developer Mode」。脚本同步时排除 `windows/macos/ios/linux` 目录即可，Android 构建不需要它们 |
| 状态 | 🟢 已规避 |

### ISSUE-031 · Windows 桌面端在本环境无法构建 🔴（补充说明）

| 项 | 内容 |
|---|---|
| 结论 | 与 ISSUE-027 同一根因（缺 VS C++ 工作负载 + 未开开发者模式）。首次构建时 `windows/flutter/ephemeral` 会被生成出约 262 MB 的中间产物，该目录已在清理时删除，属可再生文件 |
| 影响 | 本轮验证以 **Android 真机 + Web** 为准 |

### ISSUE-036 · release APK 构建被内存、GitHub 与 R8 三处卡住 ✅

| 项 | 内容 |
|---|---|
| 现象 | v0.22 打包依次失败三次：① Gradle JVM `Native memory allocation (mmap) failed`；② 之后 Dart VM `Out of memory`；③ `:app:minifyReleaseWithR8` 报 `Missing class ...DevanagariTextRecognizerOptions` |
| 根因 | ① 原 `android/gradle.properties` 用 `-Xmx8G -XX:MaxMetaspaceSize=4G`，本机 15.5GB 内存、构建时系统 commit 空闲仅约 1.5GB；② `sqlite3` 3.9 的 native asset hook 从 `github.com` 下载预编译 `.so`，本机直连超时（`errno=121`）；③ ML Kit 只在运行时加载所需语言模型，梵文/日文/韩文类未打包，R8 按默认规则判为 Missing class |
| 修复 | ① 堆降到 `-Xmx2G`、Metaspace 768m，`org.gradle.workers.max=2`，Kotlin 改 `in-process` 编译；② `pubspec.yaml` 增加 `hooks.user_defines.sqlite3.url_pattern` 指向 `ghproxy.net` 镜像（hook 会替换 `$RELEASE_TAG`/`$FILENAME`），2026-11-22 实测可下且 sha256 校验通过；原 `ghfast.top` 对 release 大文件间歇性卡住（HEAD 返回 200 但下载 0 字节），已弃用；Windows 端（单测 / 桌面）另配 `source: system` + `name: winsqlite3`，直接用系统自带 `winsqlite3.dll`，完全离线不依赖下载；③ 新增 `android/app/proguard-rules.pro`（`-dontwarn com.google.mlkit.vision.text.{devanagari,japanese,korean}.**`）并在 `buildTypes.release` 接入 |
| 验证 | `scripts/build_apk.cmd` 成功产出 `E:\APK\app-release.apk`（OCR 移除前 87.1MB；移除后最终 19.6MB，v0.22.0+22） |
| 注意 | 构建前若系统 commit 余量不足 3GB，先关闭占用大的后台进程（本次结束了 6 个 redhat.java 语言服务器，释放约 5GB）；当前默认镜像为 `ghproxy.net`，若不可用可换 `gh-proxy.com` 等，改 `pubspec.yaml` 的 `url_pattern` 即可（文件名形如 `libsqlite3.arm64.android.so`，sha256 见 `asset_hashes.dart`） |
| 状态 | ✅ 已修复 |
| 备注 | 2026-11-22 拍照识别功能移除后，ML Kit 依赖与对应 R8 规则已删除，`proguard-rules.pro` 当前为空占位 |

### 打包环境（已就绪，可直接复用）

| 项 | 值 |
|---|---|
| JDK | `D:\Javadevelop\jdk-17.0.20.1+1` |
| Android SDK | `E:\Android\Sdk`（platform 36、build-tools 36.0.0、platform-tools 37.0.1、NDK 28.2.13676358、CMake 3.22.1） |
| Gradle 缓存 | `%LOCALAPPDATA%\Temp\gradle-home`（Gradle 9.5.0 + AGP 9.1.1） |
| 一键命令 | `scripts/build_apk.cmd`（产物 `E:\APK\app-release.apk`） |


### ISSUE-032 · flutter_tts 触发 WebAssembly dry-run 告警 🟢

| 项 | 内容 |
|---|---|
| 现象 | `flutter build web` 输出 3 条 `invalid_runtime_check_with_js_interop_types`，均来自 `flutter_tts-4.2.3/lib/flutter_tts_web.dart` |
| 影响 | 只影响 Wasm 目标检查，JS 构建正常完成，Android 端不涉及 |
| 规避 | 暂不处理；若将来迁移 Wasm，可给构建加 `--no-wasm-dry-run` 或替换/升级 flutter_tts |
| 状态 | 🟢 可忽略 |

### ISSUE-033 · 云同步旧库缺 note.title / note.tags 会导致推送失败 ✅（已归档）

| 项 | 内容 |
|---|---|
| 现象 | M6 起笔记新增 `title` / `tags`，同步 push 会带上这两列；未补列的 CloudBase 旧库会返回 `column does not exist`，整批笔记同步失败 |
| 影响 | 仅影响已建过 `note` 表的云端环境；本地 SQLite 已在启动时自动 `ALTER TABLE`，Web localStorage 缺字段自动降级 |
| 规避 | 在云端 SQL 编辑器执行 `docs/cloudbase_schema.sql` 中 `note` 段落下的两句 `ALTER TABLE note ADD COLUMN IF NOT EXISTS ...`（语句已取消注释，整段粘贴即可；幂等可重复运行），然后点设置页「立即同步」验证 |
| 处理记录 | 2026-11-21：云端补列前只读查询报 `DATABASE_42703`；执行取消注释后的两句 ALTER 并重跑，`note?select=title,tags` 返回 HTTP 200 |
| 状态 | ✅ 已解决（云端结构已补齐，笔记同步可用） |

### ISSUE-034 · 手写识别准确率与包体积限制 ✅（功能已移除）

| 项 | 内容 |
|---|---|
| 现象 | 端上 ML Kit 对书写规整的英文单词较稳，连笔英文与中文手写释义误识别率较高；中文模型随包，APK 体积约增加 20–40MB |
| 影响 | 仅 Android / iOS 显示「拍照识别手写」入口，Web / 桌面不提供；识别结果必须经候选校对页确认后才写入词书 |
| 规避 | 草稿尽量一行写「单词 + 释义」；拍照正对、光线均匀；错词在候选页点开，可用离线词典回填 |
| 处理记录 | 2026-11-22：接入 PaddleOCR PP-OCRv6 tiny（ONNX Runtime，端上离线，模型约 6MB，Apache-2.0）；APK 仅保留 arm64-v8a，产物 73MB（未裁剪时为 141MB）<br>2026-11-22 修识别完全失败：① 字典 `ppocr_keys_v6.txt` 生成时被 `trim()` 吃掉全角空格 U+3000（第 617 项），6904→6903 项，导致从该位起 6287 个类别全部错位，现已按 `inference.yml` 重建为 6904 项（+blank+末尾空格 = 模型输出 6906 类）；② 识别前用 `image` 包 `bakeOrientation` 修正 EXIF 方向（相机照片像素未旋转时整页横躺，检测必然失败）；③ `maxSideLen` 960/1280→1920；④ 丢弃置信度 <0.30 的行，平均置信度 <0.45 时回退 ML Kit<br>2026-11-22 二次修复：① ML Kit 报 TextRecognizerError，判断为 R8 裁掉 manifest/反射注册的识别器类，`proguard-rules.pro` 增加 `com.google.mlkit.**` / `mlkit_vision_text*` / `mlkit_common` 的 keep（+131KB）；② 改为三级回退「ML Kit 中文 → ML Kit 英文 → PaddleOCR」，任一环失败都继续下一个，全部失败时弹窗展示各引擎原始错误并支持一键复制；③ Paddle 召回调参：曾试 `useDilation: true` + `0.12/0.3/1.6` 的激进取值，实测反而更差（膨胀把相邻行粘成一块），已回滚为 `0.2/0.4/1.4`；`maxSideLen 2560`，置信度门槛 0.20（弱结果保留给校对页，平均 <0.55 仅提示不拦截）<br>2026-11-22 云端方案（档位 2）：① 新增百度手写识别为可选引擎，20s 超时 + 瞬时错误一次重试 + token 缓存；② 图片超 4MB / 长边超 4096 时自动重编码缩放；③ 请求开启 `detect_direction` 与 `probability`，返回逐行置信度与坐标；④ 无密钥/断网/额度用尽自动降级到 Paddle→ML Kit，warning 说明原因，不再直接报错；⑤ 解析层按坐标恢复阅读顺序，置信度贯通到校对页（<60% 标黄）；⑥ 设置页新增「测试连接」（只换 token 不耗次数）、保存后切换提示与本月用量 |
| 模型升级 | PP-OCRv6 tiny → v5 mobile（规格外）→ **PP-OCRv6 small**（det 9.9MB + rec 21.2MB + 字典 75KB）。插件官方仅声明支持 v6 tiny/small，v5 属规格外使用。核验：rec 输出 18710 类 = 字典 18708 + blank + 末尾空格，逐项对齐；预处理与 v6 tiny 一致。APK 92.8MB |
| 识别增强 | 用同一张手写样张在 PC 端（rapidocr + 同一套 v6 small 模型/字典）实测：26 行全部检出，13 个英文单词全对，中文释义 13 条中 11 条完全正确（`鞭子`→`革便子`、`公寓`→`么寓` 两处字形近似错），平均置信度 0.952，det 0.40s + rec 0.18s。带下划线的原图（0.952）略优于去线图（0.944），故移除「去下划线」预处理，只保留 EXIF 摆正 + 长边 2200。**根因确认：默认引擎为 ML Kit，其图片 OCR 面向印刷体，对照片手写几乎无输出；只要 ML Kit 返回非空就不再调用 PaddleOCR。** 现将默认引擎改为 PaddleOCR（存储键改为 `ocr_engine_v2`，强制旧设备回落） |
| 状态 | ✅ 已解决（2026-11-22 移除拍照识别：删除 ML Kit / PaddleOCR / 百度云端链路、模型资源、相机权限与设置项；实际流程改为「大模型输出 JSON → 粘贴导入」，APK 从 92.9MB 降至 19.6MB） |

### ISSUE-035 · v0.22 起默认 FSRS-6，云端 review_state 必须先补列 ✅（已归档）

| 项 | 内容 |
|---|---|
| 现象 | v0.22 起默认使用 FSRS-6，每次评分都会写入 `stability` / `difficulty` / `fsrs_state` / `fsrs_step` / `last_review` 并随 push 上传；未补列的 CloudBase 旧库会返回 `column does not exist`，导致进度同步失败 |
| 影响 | 影响所有升级到 v0.22 且开启云同步的环境；本地 SQLite 已在启动时自动 `ALTER TABLE`，Web localStorage 缺字段自动降级，仅云端需手工补列。设置页切回 SM-2 可临时规避（新评分不再带 FSRS 字段，已迁移的词仍会带） |
| 规避 | 在云端 SQL 编辑器执行 `docs/cloudbase_schema.sql` 中 `review_state` 段落下的五句 `ALTER TABLE ... ADD COLUMN IF NOT EXISTS ...`（语句已取消注释，整段粘贴即可；幂等可重复运行），然后点设置页「立即同步」验证。只执行 `CREATE TABLE` 的新库已自带这些列 |
| 处理记录 | 2026-11-21：初次执行时语句仍为注释导致未生效（报 `DATABASE_42703`）；取消注释后重跑，只读查询 `review_state?select=stability,...` 返回 HTTP 200，5 列均已存在 |
| 状态 | ✅ 已解决（云端结构已补齐，v0.22 默认 FSRS-6 可正常同步） |
