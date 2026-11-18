# Launcher 与独立版本交接完成记录

状态：开发、整合、测试、五组云端验证及当前 Windows/Moto 安装已完成。交付版本为 Full/Desktop `1.5.0+7`、Bluetooth Lite `1.0.0+1`。

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
| Desktop Flutter 全量 | 97 通过，1 项 Linux 音频条件检查在 Windows 跳过 |
| 共享协议 | 25 通过 |
| 原有听写模块 | 24 通过，1 项需要原生模型的检查跳过 |
| 独立 Lite Flutter | 12 通过 |
| Full Android 原生 | 16 通过 |
| 独立 Lite Android 原生 | 14 通过 |
| Rust | 服务 23、example 1 通过；2 项 PostgreSQL 专用检查留给有数据库的 CI |
| 导出工具安全测试 | 5 通过 |
| 静态检查 | 整仓 Flutter analyze 无问题；Rust fmt 与 clippy `-D warnings` 通过 |

独立 Lite 在源工程和仓库外导出工程都由官方 Flutter 命令成功构建。导出工程完成离线依赖解析、分析和全部测试，package_config 不引用父仓库。APK 实际权限只有四项 Bluetooth 权限与 AndroidX 私有 receiver 权限，无 INTERNET、RECORD_AUDIO 或 Full 的账号、ASR、录音、Desktop 资源。CI 还使用仅含 Lite 的 sparse checkout，断言父工程不存在。

Full Android release 与 Windows release 从干净 NTFS 源导出构建，避免本机旧 Desktop installer 缓存进入 APK。Windows 使用经校验的临时 U: 映射规避 exFAT 与路径长度限制，结束后移除映射。两个默认 Android 安装包均为 release 优化编译，并实际验签为 Android Debug 开发证书。Lite 优化包为 50,429,973 字节（约 48.1 MiB），也重新通过实际 APK 权限与依赖隔离检查；原 debug 构建保留作本机验证资料。

真实 Windows NTFS junction 也已验证被导出器拒绝：目标、旁侧及源文件保持原样，输出目录未创建，仅清理本次 staging。该证据补充五项自动安全测试。

Windows 真实进程验证覆盖图标 App ID 参数、亮度管道参数（不改显示器）及本机 Chrome PNG 提取。网页真实浏览器验证覆盖 17 ID 下载、alias、搜索、未知 ID、390px 无横向溢出、503 重试恢复和无 JavaScript 错误。

## 截图与本机证据

本轮统一索引：`build/handoff-1.5.0/screenshots/index.html`，共 **52 张**：Full 8、Desktop 29、独立 Lite 10、网页 5。没有逐张读取图片。旧 Home/Lite 组件回归截图单独保留在 `component-regressions`，不混入产品索引。

构建、测试、浏览器报告及原生 Chrome 图标位于本机 `build/handoff-1.5.0`。安装包汇总目录为 `build/artifacts/1.5.0`。这些构建和设备证据不提交到 Git。

## 云端构建与安装

以下最终验证均已终态成功。本机 Android 与 Windows 目标的运行时代码已与各自构建镜像逐文件核对；CI 按表列提交检出并构建。验证工作流和文档的后续修正不改变已构建 Android 源码。

| 验证 | 源提交 | 成功运行 |
| --- | --- | --- |
| Full Android 全套分析/测试/构建/原生测试、Windows 安装器 | `9c8aed9` | [44209590152](https://github.com/sunyych/SmartKeys/actions/runs/44209590152) |
| 独立 Lite sparse-checkout 分析/截图/构建/原生/权限隔离 | `d96b862` | [44207201277](https://github.com/sunyych/SmartKeys/actions/runs/44207201277) |
| iOS unsigned、macOS DMG | `9c8aed9` | [44209590162](https://github.com/sunyych/SmartKeys/actions/runs/44209590162) |
| Linux Ubuntu 24.04 x86_64 构建、95 测试通过/3 Windows 专属跳过、真实 PulseAudio locale | `def377e` | [44213861355](https://github.com/sunyych/SmartKeys/actions/runs/44213861355) |
| Rust 全套含 PostgreSQL、Docker、真实浏览器 | `4aa9db1` | [44206196829](https://github.com/sunyych/SmartKeys/actions/runs/44206196829) |

干净环境会先初始化各子包的开发依赖；截图使用官方字体文件名大小写和显式 CJK 字体；Linux 测试使用 Xvfb 和隔离的虚拟 PulseAudio sink。Linux 产物按 Ubuntu 24.04/X11 边界交付，其他发行版需要独立验证。项目仍保留编译告警检查，仅对第三方 tray_manager 的已知弃用诊断保留 warning、解除其 fatal 属性。

当前电脑已经由安装器升级到 `1.5.0+7`，安装退出码为 0，程序及监听服务均在运行。旧的两份 Roaming 配置已先行备份。安装后的实际服务验证：无认证 403、认证信息与 manifest 200、十二槽、未知图标 404、本机 Chrome 原生 PNG 200（32×32、1958 字节）、ETag 304。

连接的 Moto G Play 2024 已成功安装 Full `1.5.0+7` 和独立 Lite `1.0.0+1`；Full 采用保留数据的升级安装，旧 Lite 保持原样。独立 Lite 仅启用 Bluetooth Connect/Advertise 权限，两个新版本均实际启动。Full 连接新 Desktop 后，物理手机界面核对为十二个启用按键、四列三行。设备截图/XML保留在本机 `build/handoff-1.5.0/device`，不提交 Git。

最终制品及逐文件 SHA-256 位于 `build/artifacts/1.5.0`，包含 Android、Windows Setup/portable、macOS、Linux、iOS unsigned、当前截图和独立源码导出。`BUILD-MANIFEST.json` 记录各目标来源、测试、CI 和安装范围，`SHA256SUMS.txt` 可校验传输完整性。

本次没有创建仓库、tag 或 Release，没有覆盖 main。Android 使用开发证书；Windows 安装器未作 Authenticode 签名，macOS DMG 未公证。iOS 的 unsigned `.app` ZIP 需要 Apple 签名及分发配置才能安装。物理快捷键、Bluetooth HID 投递、其他实体平台和听写模型/准确率仍属于后续设备验收范围。
