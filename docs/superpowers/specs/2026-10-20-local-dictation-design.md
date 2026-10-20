# SmartKeys 本地快速听写设计

后续要求已将手机听写传输改为蓝牙 HID，不再依赖电脑接收程序。本文末尾的
“Bluetooth transport and installer follow-up”说明覆盖早期 LAN 传输设计。

用户已要求完成全部实现、功能测试、全量单元测试和覆盖率测试，全部检查通过后提交并推送。现有应用语音输入与新增本地听写必须使用不同图标，并在首次使用时说明区别。

## 目标与范围

在 LumiaKeys Android 和 LumiaKeys Desktop（Windows、macOS）中提供快速听写，将当前讲话转换为电脑当前输入位置的文字。手机麦克风在手机识别，电脑麦克风在电脑识别。音频不离开采集设备，不写入音频文件；不添加录音、录音列表、归档或历史转写功能。

## 现状

- SmartKeys 当前分支为 `main`，远端为 `origin`；工作区初始干净。
- 手机应用使用 Flutter，现有 Companion 通过局域网发现电脑并交换清单与动作。
- `desktop_companion/lib/desktop_actions.dart` 的 `voiceInput()` 目前仅发送 `Ctrl+Shift+D`，并非离线 ASR。
- mobile_transcribe 当前源码包含 `LocalAsrWorker`、校验模型下载的 `ModelManager`、PCM 分段器、流式麦克风适配器，以及 Windows/macOS 文字注入适配器。
- 原识别器支持 SenseVoice 和 Cohere；SenseVoice 语言变化时必须重建识别器。

## 方案选择

1. **推荐：采集设备本地识别，手机只向电脑发送文字。** 满足音频不出设备，并可复用现有连接和模型实现。
2. 手机向电脑传音频、电脑识别：减少手机模型资源消耗，但不符合音频不出设备的要求。
3. 调用系统听写：接入较少，但无法统一控制模型和离线行为，不采用。

## 界面与使用流程

### Android

- 主页提供独立的“快速输出”麦克风按钮，不占用已有的 15 个快捷键位置。
- 点击打开紧凑听写面板，首次使用先选择并下载或导入模型；模型已就绪且电脑可用时可直接开始。
- 面板提供开始/停止、识别语言、模型、加载/下载状态、当前文字及投递状态。
- 语言首批支持中文、英文；界面语言和识别语言分别处理。模型列表展示两个真正可运行的本地模型：SenseVoice（默认）和 Cohere（较大）。
- 切换语言或模型时停止采集、清空尚未处理的音频、释放旧识别器，再加载并启动新配置；禁止旧会话结果进入新会话。
- 只在听写期间保持屏幕唤醒；停止、退出或应用进入后台时释放麦克风和唤醒锁。
- 未连接电脑时不采集；连接断开时停止听写并提示重新连接。

### Windows / macOS Desktop

- 托盘/菜单栏增加快速听写开始/停止入口，设置中增加听写页以及语言、模型和模型管理。
- 提供可配置的全局开始/停止快捷键；注册冲突应明确提示。
- 电脑麦克风无需手机连接即可在电脑本地听写。
- 从设置窗口开始时隐藏设置窗口，让用户回到目标输入框；开始采集前和投递时检查外部目标窗口，禁止向本应用输入。
- 使用原生 Unicode 文字注入；不通过拼接脚本执行识别文字，不覆盖系统剪贴板，不自动发送回车。
- macOS 显式处理麦克风和辅助功能权限；缺少权限时明确提示。
- 手机来的文字与本机听写共用串行投递入口，避免两条输入流交错。
- 保留已有 Codex 专用快捷动作含义；新增独立的 SmartKeys 快速听写动作，不把所有旧 `voiceInput` 动作无条件重定向。
- 现有应用语音输入采用应用语音/声波图标；本地快速听写采用麦克风搭配离线/设备标记。两者名称、工具提示及辅助功能标签不同。首次触发任一入口先展示区别说明，用户明确确认后持久记住，说明界面不打开麦克风。

## 模型与隐私

- 新增仓库内部共享的 `packages/local_dictation`，封装模型元数据/校验下载/本地导入/删除、工作 isolate、PCM 分段和听写生命周期。
- 从 mobile_transcribe 提取相关实现并保留适用的来源/许可证信息；不依赖原仓库的绝对路径，不引入其录音、项目、Vault 或搜索模块。
- 模型按应用私有目录持久缓存；已下载模型可离线加载，可查看占用并删除。删除活动模型前先停止并释放识别器。
- 保留原模型的固定 revision、文件大小及 SHA-256 校验；未完成的下载不得标记为可用。
- 只在模型安装操作中访问模型下载地址。听写音频仅存在有界内存缓冲中，不进入网络、日志或磁盘。
- 临时显示最近一次识别结果及状态，不持久化听写文本历史。

## 手机文字传输与故障处理

- 扩展现有 Companion 能力协商和受认证入口，不再引入独立 QR 配对流程。
- 增加听写会话标识及语句序号；电脑端去重、串行处理，只有完整注入成功后确认成功。
- 限制请求字节数、文字长度和控制字符，旧电脑不具备新能力时明确提示升级。
- 只发送当前会话的最终语句，不发送音频或未定稿文字。
- 超时、断线、权限失败或部分注入均明确显示失败，不自动重试文字；去重状态防止重复请求再次注入。
- 停止时先结束采集并处理停止前剩余的当前语句；强制取消/退出时使旧会话失效并丢弃未处理结果。停止完成后不再产生新输入。
- 目标窗口变化、系统修饰键仍被按住、目标权限较高等情况下拒绝或报告部分失败，不虚报投递成功。

## 验证与交付

- 单元测试覆盖语言切换重建、模型缓存校验/删除、切换/停止竞态、分段上限与资源释放。
- 传输测试覆盖认证、能力协商、请求限制、重复投递、断线不补发，以及注入失败不返回成功。
- 手机与电脑界面测试覆盖按钮、语言/模型切换、首次模型安装、麦克风权限拒绝及停止。
- 执行共享包、手机和桌面端分析/测试，构建 Android APK 与 Windows Release。
- 对所有 Dart 包执行全量单元/组件测试并收集 LCOV；报告每包和合并行覆盖率以及未覆盖的原生/硬件边界，不将行覆盖率等同于端到端通过。
- 用户追加要求：为手机和桌面端全部主要页面、编辑/连接/听写状态以及关键横竖屏/窄屏布局增加确定性截屏测试。使用真实 Flutter 界面与可控外部依赖渲染 PNG，检查预期内容、尺寸及布局异常，并自动生成离线 HTML Index。图片、元数据、HTML 和报告压缩包仅存入忽略的 `build/` 输出目录，全部不提交。没有实体手机或 Mac 时明确标注为 Flutter 测试渲染，不冒充真实设备截屏。
- 在可用硬件上验证手机麦克风到电脑当前输入框、电脑麦克风到外部输入框、中英文切换及离线识别；没有对应硬件时明确列出未验证项。
- macOS 原生构建与权限/输入验收需要 Mac；Windows 的通过结果不替代 macOS 验收。
- 编码由 Luna 子智能体承担，主智能体审查实现、执行验证并处理交付。仅提交本功能相关文件，提交到当前 `main`，推送 `origin/main` 并确认远端提交。

## 实施顺序

1. 提取共享本地听写包，先完成模型与识别生命周期验证。
2. 扩展手机文字投递协议及 Windows/macOS 原生文字注入。
3. 集成 Android 快速输出与电脑本机听写、模型管理、全局快捷键。
4. 审查隐私与停止/切换行为，运行分析、测试、构建及可用硬件验证，提交并推送。
# Bluetooth transport and installer follow-up

The subsequent user requirement supersedes the Android-to-Companion dictation
transport described below: phone dictation must work with a standard Bluetooth
keyboard connection and no computer receiver. Android output validates complete
phrases, pins one host/session, serializes bounded reports and never retries an
uncertain partial delivery. US ASCII is the default; Windows HexNumpad is an
explicit optional profile with system-setup and BMP compatibility guidance.
Recognition language/model selection remains independent of keyboard encoding.
The user accepted the one-time Windows HexNumpad system setup for BMP Unicode
output; the application never changes that setting automatically.

Install the Windows desktop application for the current user with a Start Menu
entry. Tagged release jobs build Windows/macOS installers before Android,
embed exactly those same-run packages with version/commit/size/hash metadata,
and verify their presence and hashes inside the resulting APK. Android can
verify and export packages to an explicitly selected local SAF folder for USB
file transfer. The accepted Android delivery path is a user-selected local
shared-storage folder followed by MTP. It does not expose a USB mass-storage
drive or Windows drive letter; a true-drive implementation is outside the
accepted scope, with no pending deployment choice.

Validation includes full package suites and coverage, native HID encoding,
transactional install/uninstall and bundle failure tests, and generated UI
screenshots with an offline HTML index. Generated images, catalogs, installer
binaries and reports remain outside Git. Native macOS and live Bluetooth target
acceptance must be reported separately from Windows-hosted automated evidence.
