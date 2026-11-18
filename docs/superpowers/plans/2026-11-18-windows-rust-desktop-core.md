# Windows Desktop Rust 核心实施计划

**目标**　补齐现有 Desktop 关键行为的自动化覆盖，完成进程、前台窗口、App 识别、图标和鼠标的 Windows Rust 执行路径。

**架构**　Flutter 保持现有界面、配对协议、动作路由和配置写入。Windows 通过进程级开关选择 Rust。读取失败可以回到兼容的读取路径。鼠标一旦提交给系统，失败直接报告，避免重复事件。

## 三条并行任务

1. 在 `desktop_companion/test/desktop_legacy_*_test.dart` 补现有接口、状态与容错覆盖。用 loopback 和替身验证，记录现有覆盖及仍需系统验收的功能。
2. 在 `desktop_companion/native/windows_shortcuts/` 实现 Windows 原生进程、前台窗口与应用注册表查询、鼠标批次校验和投递。通过 Dart 接入 `PlatformApplicationDiscovery`、已安装应用与图标和 `DesktopActions`，保持应用标识、图标上限、窗口权限与鼠标顺序。Windows CMake 一并打包。
3. 为 Rust 实现添加独立测试。验证注册表路径、进程和窗口过滤、缓冲区边界、鼠标校验和事件顺序、部分投递不回放。用模拟 Win32 或只读 ABI 调用，确保自动化验证不向活跃窗口发输入。

## 集成顺序

- 三组完成文件交付后，统一审阅并运行定向 Dart 与 Rust 测试。
- 先提交现有行为的补测，再提交 Rust 实现与对应测试。核对远端分支中的两次提交。
- Windows 系统级全量、安装覆盖与手机端到端延迟以后验收。保留现有默认后端，单独验证 Rust 开关及兼容路径。

## Desktop 自动化覆盖索引

| 能力 | 测试文件 | 后续系统验收 |
| --- | --- | --- |
| 发现、配对和二维码 | `desktop_pairing_qr_test.dart`、`manual_connection_server_test.dart`、`desktop_legacy_companion_contract_test.dart`，以及手机版 `desktop_connection_scanner_test.dart` | 同一 LAN 的 UDP 发现、扫码、防火墙和跨主机重连 |
| 快捷键、鼠标与应用启动 | `windows_shortcut_contract_test.dart`、`windows_rust_shortcut_test.dart`、`pointer_endpoint_test.dart`、`installed_app_endpoint_test.dart`、`linux_actions_test.dart` | 真实窗口投递、输入权限、物理修饰键和键盘布局 |
| 托盘与设置 | `desktop_legacy_tray_test.dart`、`widget_test.dart`、`ui_screenshot_test.dart` | 系统托盘或菜单栏、缩放、退出与窗口前后台 |
| 配置、Profile 和 Launcher | `desktop_legacy_preferences_test.dart`、`launcher_atomic_test.dart`、`launcher_keys_test.dart`、`regular_defaults_test.dart` | 实际旧数据的升级、回退和重启恢复 |
| 应用库与图标 | `app_library_install_test.dart`、`app_library_page_test.dart`、`app_icon_service_test.dart`、`icon_endpoint_test.dart`、`desktop_legacy_companion_contract_test.dart` | 真实应用库存、原生图标和重装后的 ID |
| Vibe 和 ChatGPT/Codex | `vibe_controller_test.dart`、`vibe_system_tools_test.dart`、`desktop_legacy_actions_test.dart` | ChatGPT 主窗口和浮层、Cursor/Claude 和前台切换 |
| 本地及手机听写 | `desktop_dictation_test.dart`、`dictation_receiver_test.dart`、`dictation_native_sink_test.dart`，以及共享听写包的 `controller_test.dart` | 麦克风、模型、热键及实际目标应用投递 |
| 媒体、音量、亮度与网址 | `linux_actions_test.dart`、`windows_parameter_binding_test.dart`、`desktop_legacy_actions_test.dart` | 真实音频设备、亮度恢复、默认浏览器与平台策略 |
| 导入、导出与安装 | `shortcut_transfer_test.dart`、`desktop_legacy_preferences_test.dart`、`regular_defaults_test.dart`，以及 `scripts/test_install_windows.ps1` | 原生文件选择器、签名与真实安装升级 |

## 本轮定向验证

- 三条开发线交付后统一运行验证。新增 24 项现有行为、13 项 Rust 契约和 17 项 Flutter 接入测试。
- Flutter 111 项定向测试及静态分析通过。Rust 20 项测试、格式检查和 Clippy 通过，Windows x64 Release DLL 构建成功。
- Windows 上的只读 DLL 验证确认进程快照和注册表应用清单可以读取。真实鼠标动作、手机联调、安装与端到端延迟留待系统级验收。
