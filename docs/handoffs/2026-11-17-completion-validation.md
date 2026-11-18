# Launcher 与独立版本交接完成记录

本次在 `feature/mobile-launcher-and-editions` 上复用 WIP `08993e6`，合入已交付的 main `791b022`。主分支保持原状。本记录覆盖新的整合结果；原交接文档中的中间测试、旧安装包和 Mac 工作目录不作为本轮验收证据。

用户最后确认以 **12 个启动位、完整版固定横屏** 为准，覆盖旧 handoff 的 8 位和竖屏描述。Full 为 `1.5.0+7`；独立 Android Bluetooth Lite 为 `1.0.0+1`。

## 已完成的产品边界

- Full 默认进入电脑配置的启动台，左侧导航、四列三行、右侧触控板。旧八位迁移到十二位；主动清空保持为空。应用须有同一电脑的新激活确认才启用快捷键，返回启动台、断线和换电脑会撤销旧确认。
- 独立 Lite 位于 `apps/bluetooth`，使用 `com.lumiaiq.bluetoothlite`，只有 Flutter 与 shared_preferences 两项直接生产依赖。保留本地 General、ChatGPT、Chrome、编辑器、键盘、触控板和媒体控制。不会替换或读取旧 `com.lumiaiq.smartkey.lite` 的私有数据。
- 16 项实际品牌资源、17 个兼容 ID；`codex` 是历史 alias。原生图标、离线资源、可配置的中央服务均有明确降级。认证资源接口、PNG 边界、跨电脑缓存、应用身份失效及 24 小时过期已验证。来源与权利边界见 `docs/APP_ICON_SOURCES.md`，客户端配置见 `docs/APP_ICON_CLIENT.md`。
- Desktop 配置使用单条 manifest 原子持久化槽位和 revision；队列内按最新状态局部更新，避免并发覆盖。旧配置读取失败不会通过编辑、刷新或监测器覆盖磁盘数据。
- Windows 原生图标与亮度参数改为明确的 PowerShell 作用域；Linux X11 的能力探测、滚轮方向、Teams 前台识别、固定媒体与工具命令已修正。Wayland 输入、Linux 原生听写及区域截图没有被宣称为已支持。
- 安全导出拒绝覆盖和路径链接，排除 Git、缓存、构建产物、本机配置和签名材料；两项已公开 Rust 测试 PEM fixture 为精确白名单。Full 导出不含独立 Lite 工程。

## 当前本地验证

| 范围 | 实际结果 |
| --- | --- |
| Full Flutter 全量 | 293 通过 |
| Desktop Flutter 全量 | 96 通过，1 项 Linux 音频条件检查在 Windows 跳过 |
| 共享协议 | 25 通过 |
| 原有听写模块 | 24 通过，1 项需要原生模型的检查跳过 |
| 独立 Lite Flutter | 12 通过 |
| Full Android 原生 | 16 通过 |
| 独立 Lite Android 原生 | 14 通过 |
| Rust | 服务 23、example 1 通过；2 项 PostgreSQL 专用检查留给有数据库的 CI |
| 导出工具安全测试 | 5 通过 |
| 静态检查 | 整仓 Flutter analyze 无问题；Rust fmt 与 clippy `-D warnings` 通过 |

独立 Lite 在源工程和仓库外导出工程都由官方 Flutter 命令成功构建。导出工程完成离线依赖解析、分析和全部测试，package_config 不引用父仓库。APK 实际权限只有四项 Bluetooth 权限与 AndroidX 私有 receiver 权限，无 INTERNET、RECORD_AUDIO 或 Full 的账号、ASR、录音、Desktop 资源。CI 还使用仅含 Lite 的 sparse checkout，断言父工程不存在。

Full Android release 与 Windows release 从干净 NTFS 源导出构建，避免本机旧 Desktop installer 缓存进入 APK。Windows 使用经校验的临时 U: 映射规避 exFAT 与路径长度限制，结束后移除映射。两份 Android 交付 APK 均实际验签为 Android Debug 开发证书；Full 使用 release 编译配置，Lite 使用 debug 配置，不冒充正式生产签名包。

Windows 真实进程验证覆盖图标 App ID 参数、亮度管道参数（不改显示器）及本机 Chrome PNG 提取。网页真实浏览器验证覆盖 17 ID 下载、alias、搜索、未知 ID、390px 无横向溢出、503 重试恢复和无 JavaScript 错误。

## 截图与本机证据

本轮统一索引：`build/handoff-1.5.0/screenshots/index.html`，共 **52 张**：Full 8、Desktop 29、独立 Lite 10、网页 5。没有逐张读取图片。旧 Home/Lite 组件回归截图单独保留在 `component-regressions`，不混入产品索引。

构建、测试、浏览器报告及原生 Chrome 图标位于本机 `build/handoff-1.5.0`。安装包汇总目录为 `build/artifacts/1.5.0`。这些构建和设备证据不提交到 Git。

## 云端构建与安装

代码通过本地验证后提交推送功能分支，再等待 artifact-only 的 Android、独立 Lite、Windows、macOS、iOS、Linux、Rust/PostgreSQL/Docker/browser 检查。具体构建提交、终态运行链接、交付校验值和当前电脑/手机安装结果将在检查完成后补记。

本次不创建仓库、tag 或 Release，不覆盖 main。iOS 的无签名 `.app` ZIP 需要 Apple 签名和分发配置才能安装；macOS 包与 Windows 安装器的签名状态以最终交付说明为准。模拟输入测试、构建成功和窗口显示不等同于所有物理平台的快捷键、Bluetooth HID 或听写实测。
