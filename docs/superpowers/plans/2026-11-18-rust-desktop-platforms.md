# Rust Desktop 三平台实施计划

**目标**　让 Windows、macOS 和 Linux 的桌面发布包都包含可运行的 Rust 后端。第一批跨平台入口是进程、前台状态和鼠标批次。

**架构**　Flutter 负责界面、状态和手机通信。Rust 库提供版本化 C ABI，平台实现各自使用系统输入能力。`LUMIAKEY_DESKTOP_BACKEND=rust` 选择候选后端。Windows 原有两个开关仍可用。

## 实施任务

1. 扩展 `desktop_companion/native/windows_shortcuts/`。Windows 发行包保留原 DLL 与 ABI。macOS 使用当前进程的系统授权，Linux 仅在 X11 会话启用输入。对鼠标批次先校验再投递，已开始的批次失败后直接返回结果。
2. Dart 在对应平台发布包目录加载 Rust 动态库，以原有 `DesktopActions` 和 `PlatformApplicationDiscovery` 入口接入。后台工作执行本机调用。只读失败使用现有探针，平台权限拒绝保留明确状态。
3. macOS Xcode 将动态库放入 `Contents/Frameworks`，按目标架构构建和签名。Linux CMake 将共享库放入 bundle `lib`。Windows CMake 延续原有 DLL。三个平台的 CI 验证本机编译和包内 ABI。
4. 两名测试开发者并行补 macOS 和 Linux 契约。覆盖权限、X11 与 Wayland、只读结果和错误回退、成功及失败的批次路由、ABI 加载与非法输入。三线冻结后统一执行。手机、实际鼠标投递、签名安装和端到端延迟属于系统级验收。

各平台已有的应用清单、图标、托盘、听写和系统控制由各自适配器提供。已迁移的 Windows 注册表和快捷键继续走原有 Rust 实现。

## 本地验证结果

- Windows x64 的 Rust 22 项通过，Flutter 129 项通过、13 项按平台条件跳过，静态分析通过。
- Linux x64 在 WSL 构建出 Release bundle。Rust 22 项和包内共享库的 17 项 Flutter 定向测试通过。在单独的 Xvfb 会话中验证了连续相对移动和按钮释放。
- macOS ARM64 的 Rust 目标检查通过。Xcode 动态库打包、签名校验和只读 ABI 冒烟接入 Apple CI。物理 Mac 的 Accessibility 授权和真实输入留待系统级验收。
