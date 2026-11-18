# LumiaKey coding agent handoff

> 本文件保留原始 WIP 交接背景。后续用户确认以完整版 **12 键、固定横屏** 为准；新的实现与实际验证记录见 [完成记录](2026-11-17-completion-validation.md)。

## 接手目标

继续现有 LumiaKey 项目，完成“电脑配置、手机展示的 Launcher Pad”、App 图标服务，以及完整版 / Android 蓝牙精简版拆分。当前是开发中的 WIP，不是完成版。先读取工作区 diff 与下述日志，再继续实现和验证。

- 仓库：`/Volumes/SSD/Projects/SmartKeys`
- 当前分支：`feature/mobile-launcher-and-editions`
- HEAD / 基线：`0f6717804340da4db3db2bf912930900c6b3b42a`
- 远程：`git@github.com:sunyych/SmartKeys.git`
- 本轮修改：未提交、未推送；包含大量新文件，不能只查看 tracked diff。
- 交付目录：`/Users/ssun/Documents/Codex/2026-11-17/referenced-chatgpt-conversation-this-is-an/outputs`
- 本轮日志与临时测试：同级 `work/`。
- 原来的独立 Electron/Orbit 尝试已废弃，在 `work/abandoned-orbit/`，不要继续开发或作为成果交付。完整版必须继续使用现有 Flutter LumiaKey。

## 用户已确认的要求

### 1. 完整版：启动台在手机，配置在电脑

- 电脑端 LumiaKey Desktop 配置启动台；手机端显示配置结果。
- 沿用本次原有 8 个可配置启动位；不强制所有屏幕使用固定 2×4 排列，随窗口尺寸合理适配。
- 打开完整版手机 App，默认进入 Launcher Pad，而不是直接进入键盘或某个 App 的快捷键。
- 点击启动位：通过电脑伴侣启动/激活该 App，进入对应 App 的快捷键页面。
- 保留已有“目标 App 激活确认后才能发送快捷键”的保护，避免误发到错误窗口。
- 系统前台 App 的变化、旧的激活通知不能把用户从首页启动台自动带走。
- 返回启动台应当有清晰入口；不能在返回后又被旧通知跳回 App 页面。
- 手机横屏时，将顶部应用/功能导航移到左侧短边，第一项为 Launcher Pad；保留键盘、App/配置等入口。竖屏合理适配。
- 首次未配对、未配置、掉线时仍提供有意义的启动台与连接/设置入口；不要卡住、空白或悄悄启动错误目标。
- 保留时钟、播放/暂停、静音，以及现有功能；手机上的启动位不提供本地编辑，配置来源是电脑。

### 2. App 图标完整性与下载

- 不能只靠目前七个不完整的图标或通用占位符。
- 优先使用电脑上已安装 App 的原始图标，作为比网上下载更准确的来源。
- 软件预置常见 App 图标，离线可用；缺失时允许按规范 App ID 从集中图标服务下载并缓存。
- 在现有 Rust 网页 dashboard 中提供图标集中展示、按 App ID 搜索/请求和下载页面；不是另建无关产品。
- 维护 canonical ID 和别名，例如旧 codex 与当前 chatgpt 的兼容；不要把不同品牌随便映射为同一个标志。
- 未知 ID、下载失败、离线、无图标均有清晰降级；不得影响启动与快捷键主流程。
- 记录真实图标来源/许可信息；不能把 Simple Icons 项目的 CC0 自动当成所有品牌标志的许可。
- 下载接口不接受任意外部 URL 当代理。使用已登记来源、超时、大小和图片类型限制。

### 3. 拆为两个独立产品

**完整版 LumiaKey Full**

- 手机端支持 iOS、Android。
- 电脑端支持 Windows、macOS、Linux。
- 包含电脑伴侣、手机启动台、App 同步、快捷配置、各种原有完整功能。
- 保留键盘与快捷键控制。

**LumiaKey Bluetooth Lite（用户明确确认的边界）**

- 仅 Android。
- 保留蓝牙 HID 键盘、鼠标/触控板、媒体控制、手动编辑并保存在手机的本地快捷键。
- 移除电脑伴侣、Launcher Pad、App 同步、快捷配置向导、在线 dashboard。
- 不携带账号/云服务、语音识别/录音等完整版依赖；不申请网络或麦克风权限。
- 必须是真正独立的入口、依赖和构建产物，不是把完整版界面隐藏。
- 具有不同 Android applicationId，能与完整版共存。

**仓库与版本标记**

- 优先同仓库两个可独立构建的产品。
- Tag 只区分版本发布，不能用 tag 假装已经剔除依赖。
- 当前方案是 Full 保留现有 `vMAJOR.MINOR.PATCH`，Lite 使用 `bluetooth-vMAJOR.MINOR.PATCH`。
- 用户补充：如果同仓库不能干净隔离，可以拆成两个 separate repo，之后由用户在 GitHub 调整仓库。
- 已开始实现安全源码导出：Full 与 Lite 各导出为独立目录，不含 `.git`、构建产物、密钥和本机配置；独立 Lite 不得依赖父仓库路径。
- 不创建 GitHub 仓库、不推 tag、不自动发布 Release。当前新增工作流走构建 artifact。此前修改发布型工作流的方案被自动审批拒绝，现改为独立的 artifact-only 工作流，不需要重新尝试扩大写权限。

## 开发与交付规则

- 用户要求开发交给子智能体，Luna 为 coder；主 agent 做检查、测试和 review 后汇报。
- 每个新增/修改界面应有截图测试；只保留当前版本截图，汇总为一个大的 `index.html`。
- 不逐张读取/分析图片，不进行耗费 token 的图像 review；通过测试和截图索引供用户查看。
- 本轮源码任务已停止写入。接手时不要假定旧 agent 仍会继续工作。
- 保留工作区所有已有改动，不要 reset、clean 或重做整个项目。
- 仓库在 `/Volumes/SSD/Projects/SmartKeys`，可能不在工具默认可写范围；按环境要求申请针对性的写权限。不要因此另建无关项目。

## 当前实现与代码入口

### 手机版与同步协议（已实现一部分，仍需回归）

- `lib/ui/home_screen.dart`：新增默认 Launcher Pad、横屏左侧 rail、设置/连接 CTA、激活通知处理；开始接入原生图标缓存。
- `lib/controllers/app_controller.dart`：图标请求/缓存入口。
- `lib/services/companion_service.dart`：开始加入已认证的 App 图标获取。
- `lib/data/private_image_store.dart`：图标落盘缓存相关改动。
- `packages/lumiakeys_protocol/lib/lumiakeys_protocol.dart`：新增可选 `launcherApplicationIds`，旧 manifest 默认八个空位；校验长度和引用，关闭 App 同步时按设置隐藏数据。
- `desktop_companion/lib/desktop_controller.dart`：将电脑端八个启动位发布给手机，维护持久化 revision。
- `desktop_companion/lib/companion_server.dart`：`launcher-pad-v1` 能力；已开始加入 `GET /icons/{appId}`（电脑伴侣接口，需已有认证）。
- 图标不内嵌进每次 manifest；计划/当前实现为单独资源请求，PNG 上限 64 KiB，避免轮询重复传大图。
- 需继续核查 slots 保存与 revision 保存失败时的一致性、重启后版本变化、多电脑切换时图标缓存是否正确隔离、syncIcons 设置是否正确生效。

### 图标服务与 Linux

- `community_server/src/icons.rs`：集中图标 catalog / PNG 下载。
- `community_server/src/main.rs`、`web.rs`、`web/icons.{html,css,js}`：`/icons` 网页和同源资源；现有 dashboard 已增加入口。
- API：`GET /v1/icons/catalog` 与 `GET /v1/icons/{appId}`。
- `--icons-preview` 可以不接 PostgreSQL 运行同一图标网页/API。
- `community_server/assets/app_icons/`：原样收录当前已有七个 PNG；Dockerfile 已包含这些资源，构建不依赖服务器目录以外的图片。
- **未完成重点**：服务器下载 catalog 仍只有七个已有资产；虽然客户端登记约 17 个 managed ID，但那不等于新增图标齐全。必须补足新品牌实际图标或可信的登记来源下载/缓存，不能把 alias 数量当成图标覆盖数。
- `lib/icons/app_icon_catalog.dart`：开始加入目录客户端、RAM 缓存和 artwork 组件，需集成验证，不保证最终完成。
- `desktop_companion/lib/app_icon_service.dart`：`NativeAppIconService`，支持本地 Mac 图标、Windows 固定来源 PowerShell 图标提取、Linux .desktop/icon theme PNG 查找；需核查异常、缓存、超时与真实输出。
- `desktop_companion/lib/desktop_actions.dart`：`getApplicationIcon(RemoteApplication) -> Future<Uint8List?>`；增加 Linux xdotool / pactl / playerctl 路线。
- macOS `Runner/MainFlutterWindow.swift`：`lumiakeys/app_icon` channel，NSWorkspace 图标读取。
- **Linux 待验证**：目前重点是 X11。Wayland 输入自动化不支持时必须明确说明，不得称为无条件全功能支持。检查 pointer capability 是否在 X11 下正确对手机宣告；`pactl` 解析应固定 locale；VibeSystemTools 的固定动作尚需核实 Linux 路径，不能落到未实现 channel。
- **Linux CI 待修**：`.github/workflows/linux-validation.yml` 当前安装库可能不完整。tray_manager 明确需要 `libayatana-appindicator3-dev` / appindicator；继续检查 record、JNI、其他 plugin 的 Linux CMake 依赖和运行依赖。尚无本机 Linux 构建证明。

### 独立蓝牙版与导出

- `apps/bluetooth/`：独立 Flutter pubspec、Android Gradle 工程、自己的原生 HID controller/encoder、UI、设置和测试。
- applicationId：`com.lumiaiq.bluetoothlite`。
- 主入口：`apps/bluetooth/lib/main.dart`；测试在该项目自己的 `test/`。
- `analysis_options.yaml` 已排除嵌套 Lite，由 Lite 自己运行 analyzer，避免 Full CI 误解析未初始化的子项目。
- `.github/workflows/bluetooth-lite.yml`：仅 Lite 验证/APK artifact；与 Full 桌面构建无依赖。
- `scripts/build-full.sh`、`scripts/build-bluetooth-lite.sh`、`scripts/export-editions.sh`。
- `apps/bluetooth/scripts/check-isolation.sh`：依赖、权限、applicationId 检查；要在独立导出目录也可运行。
- 最新 export 脚本已改为：要求仓库外的新路径；拒绝已有路径；使用 staging；排除构建、密钥和本机文件。仍需实际执行并验证独立目录可构建。
- 版本边界说明：`docs/EDITIONS.md`；图标说明：`docs/APP_ICON_SOURCES.md`；这些是 WIP，不可仅根据文档宣称功能完成。

## 已知验证状态（不要混淆旧版与新版）

1. 上一版已推 main 的 `0f67178` 有 61 项桌面测试、7 项原有截图测试、静态检查和 macOS 构建通过。这只能证明旧基线。
2. 本轮 protocol 测试：16 项通过，包含启动位字段的兼容/同步测试。
3. 本轮手机版针对性测试：14 通过、16 失败。多数旧测试仍假设首页是键盘，或寻找旧导航 key；需要显式进入键盘后再测试原功能，而不是删除测试或恢复错误首页。
4. 对应日志：`work/mobile-launcher-review.log`。失败涉及 `home_application_selection_test.dart`、`widget_test.dart`、`ui_screenshot_test.dart`。
5. 本轮 Lite analyzer 在修复缺 import/unused 字段后通过。
6. Lite 三项基本/输入/本地快捷键测试在最后一次跑测中通过；截图测试曾挂起，因字体文件读取在 fakeAsync 内直接 await。已改 `tester.runAsync(prepareFonts)`，但还没完整复测。
7. Lite 编辑器曾出现 `TextEditingController was used after being disposed`；已改为独立 StatefulWidget 对话框生命周期，修正后仍需完整测试确认。
8. Lite APK 构建：Gradle 实际产生 APK，但 Flutter 命令报告找不到产物，**不能宣称构建通过**。产物在 `apps/bluetooth/android/build/app/outputs/flutter-apk/app-debug.apk`；应修 `apps/bluetooth/android/build.gradle.kts` 的 buildDirectory，使产物位于 Flutter 期望的 `apps/bluetooth/build/app/outputs/flutter-apk/`。当前 `.dir("../build")` 很可能应依照标准模板调整。日志：`work/lite-apk-build.log`。
9. Rust 图标服务 agent 报告：20 个测试通过、2 个 PostgreSQL 专用测试忽略；最终源码还需父 agent 复跑确认。
10. 父 agent 实际浏览器验证通过：图标搜索、PNG 下载、未知 ID 空结果、390px 无横向溢出、503 错误界面。5 张截图在 `work/review-shots/web/`。测试脚本：`work/web-icon-review.cjs`。这时服务仍是七图标版本，扩充后需重跑。
11. Linux/icon agent 报告中途桌面 61 tests 通过；当前本轮全部改动尚未统一跑完整套回归，也没有新版 macOS/iOS/Windows/Linux 构建结论。
12. 当前 `outputs/LumiaKey-macOS-arm64.zip`、`outputs/screenshots/index.html` 是上一版交付。不要将它们当成本轮新版结果。最终应干净重新生成截图与索引，替换旧版本。

## 建议接手顺序

1. 保存/审阅当前所有 tracked + untracked 源码；确认分支和范围，保持旧功能。
2. 修 Lite Gradle 产物路径，完成其独立 analyzer、测试、debug APK、权限/依赖隔离检查；核查 Shift 不能发送多余字母、快捷键保存失败提示、后台释放按键和连接状态。
3. 完成手机版 pad → app shortcuts 以及左侧 rail 的测试迁移，补首次启动、未配置、掉线、返回 pad、旧激活消息、App 激活失败与跨电脑切换回归。
4. 完成原始图标 → 认证资源接口 → 手机持久化缓存/展示的端到端连接，补 syncIcons 关闭、未知 App、过大/非 PNG 数据、缓存失效、下载失败测试。
5. 补全集中图标服务，核查图片来源与 Docker 自包含构建。
6. 完善 Linux X11 能力与 CI 依赖，准确记录 Wayland/各平台未实现能力；不要用模拟测试当成硬件实测。
7. 实际执行安全导出，证明导出的 Lite 在父仓库不存在时仍可 pub get/analyze/test/build。检查 Full 不包含 Lite、Lite 不包含任何 desktop/ASR/cloud 代码依赖与安装包。
8. 跑相关完整测试、平台构建与最终截图，再 review diff。未经用户进一步要求，不自动创建远程仓库、发布 tag/Release 或覆盖 main。

## 参考验证命令

在各项目内顺序运行 Flutter 命令，避免共享 SDK/构建锁和截图目录竞争。当前本机 Flutter 3.47.2 stable / Dart 3.13.2；JDK/Android SDK 已有缓存。命令可能需要当前环境的针对性权限。

```sh
# Full mobile
cd /Volumes/SSD/Projects/SmartKeys
flutter pub get --offline
flutter analyze
flutter test

# Protocol
(cd packages/lumiakeys_protocol && dart test && dart analyze)

# Desktop
(cd desktop_companion && flutter analyze && flutter test)
(cd desktop_companion && flutter build macos --debug --no-pub)
flutter build ios --debug --no-codesign

# Lite must build independently
(cd apps/bluetooth && flutter pub get --offline && flutter analyze && flutter test)
(cd apps/bluetooth && flutter build apk --debug --no-pub)
./apps/bluetooth/scripts/check-isolation.sh

# Rust
(cd community_server && cargo test --locked --all-targets)
LISTEN_ADDR=127.0.0.1:18741 cargo run --manifest-path community_server/Cargo.toml --locked -- --icons-preview
```

截图生成使用现有 `SMARTKEYS_SCREENSHOT_DIR` 和 `scripts/generate_screenshot_index.dart`。本机中文测试字体可设置 `SMARTKEYS_SCREENSHOT_FONT='/System/Library/Fonts/Supplemental/Arial Unicode.ttf'`。最终统一输出完整手机端、桌面端、Lite、网页的当前截图，生成一个 index；不用逐张读图片。

## Suggested skills

- `handoff`：读取此文并继续维护交接状态。
- `diagnose`：用于 Lite Gradle 产物路径、截图等待和集成失败；使用前检查其项目上下文要求。
- `review` / `simplify`：实现完成后做正确性和必要清理 review。
- 不需要创建新独立桌面 App、另建网站或生成新品牌图片；也不需要把本任务当数据分析 dashboard 重建。

## 完成条件

- 用户要求的两个产品边界真实成立，独立构建与导出可验证。
- 手机默认首页是电脑配置的启动台，横屏首个左侧入口为启动台，点击 App 后才能进入对应快捷键。
- 原始/内置/下载图标路线可用，网页按 App ID 查找和下载可用，覆盖常见 App，未知和失败可恢复。
- 现有快捷键、连接、输入保护与重要原功能通过回归；没有通过删测试或屏蔽错误制造“通过”。
- 平台支持与实际验证结果如实报告；不把 Linux X11 当 Wayland、不把未执行的 Windows/iOS 构建说成成功。
- 每个界面有当前版本截图并统一到一个 index，交付包与最终源码一致。
