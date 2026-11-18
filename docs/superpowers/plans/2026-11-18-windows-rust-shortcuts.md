# Windows 快捷键迁移实施计划

> Luna 负责开发。协调者在测试和 Rust 接入两个阶段分别复核变更、运行验证、提交并推送。

**目标**　以真实目标窗口收到的事件验证 Windows 快捷键兼容性，并为现有 PowerShell 路径提供可选择的 Rust 实现。

**架构**　Flutter `DesktopActions.sendShortcut` 负责输入归一化及现有策略。Windows 适配器以固定版本的 C ABI 调用同一安装目录中的 Rust 库。候选实施沿用原有手机协议、Desktop 配置和更新路径。

**技术栈**　Flutter/Dart、`dart:ffi`、Rust MSVC x64、Win32、CMake 和 Inno Setup。

## 1. 为现有实现建立测试基线

- [x] 在 `desktop_companion/test/fixtures/windows_shortcuts.json` 记录输入键、目标应用、预期普通键、修饰键、允许的前台进程和 ChatGPT 主窗口要求。
- [x] 在 `desktop_companion/test/windows_shortcut_contract_test.dart` 用捕获参数的假进程执行器调用公开的 `sendShortcut`。断言允许请求调用一次、非法请求调用零次、错误结果只投递一次。前台脚本断言覆盖实际前台检查和主窗口判定。测试期间用假进程接收快捷键。
- [x] 在旧实现上运行 `flutter test --no-pub test/windows_shortcut_contract_test.dart test/vibe_controller_test.dart test/windows_parameter_binding_test.dart`。Windows 本机 40 项通过，其中 33 项为新增契约。
- [x] 检查测试、fixture 和本计划，单独提交测试基线。

## 2. 接入可选 Rust 后端

- [ ] 用同一契约验证 Flutter 路由到候选后端的键与目标信息。覆盖 ABI 失败、前台拒绝、物理按键冲突和部分投递结果。用替身复核每个请求只交给一个后端。
- [ ] 在 `desktop_companion/native/windows_shortcuts/` 实现 Rust `cdylib`。为键转换、前台窗口规则和事件序列设置可注入的 Win32 测试替身。输入前复验窗口。保持已有目标进程与 ChatGPT 主窗口门槛。出现部分投递时，仅尝试释放本次调用已插入的按下事件，向调用方报告失败。
- [ ] 在 Windows CMake 发行目录布置库，将 Rust 模式设为显式启用。库缺失、版本异常和原生拒绝均向调用端报告。处于默认模式时使用现有 PowerShell 实现。将较重的本机调用放在 Flutter 主界面线程之外。
- [ ] 运行 `cargo fmt --check`、`cargo clippy --locked --all-targets -- -D warnings`、`cargo test --locked` 和 Flutter 回归。构建 Windows Release，检查 DLL 导出、发行目录和测试安装包。复核新增文件和 CI 路径，再提交并推送候选实现。

## 切换默认后端的验收

用同一台 Windows 机器和同一目标窗口对比两个发布构建。记录从手机手势到目标窗口收到事件的 p50、p95、p99、失败率，以及桌面处理段耗时。候选门槛为 p95 至少降低 30%，p99 和失败率持平或改善。实机验证 ChatGPT 主窗口及浮层、错误窗口零投递、常用布局和修饰键释放。验收通过后单独提交默认后端切换。
