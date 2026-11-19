# Full 主机切换鼠标与手机侧栏：Mac 接力测试

日期：2026-11-18。工作分支：`codex/host-switch-pointer-and-sidebar`。
本轮不修改版本号、Lite、图标目录或 Launchpad 启动逻辑。

## 当前结论

用户确认第二台电脑的鼠标不能使用，Launchpad 启动、功能和图标正常。
**持续无法移动鼠标的根因尚未确认，也未完成第二台 Mac 的实机验收。**

已复现并修复两个手势生命周期问题：

- 切换主机的 pending 画面卸载触控板后，旧手指的迟到事件可能触发
  `setState after dispose`；卸载时现在清空手势状态。
- 输入 epoch 重置后，旧手指的迟到 cancel 曾吞掉新手指的点击；现在忽略
  不属于当前手势的 cancel。

这些修复有失败前/通过后的回归证据，但不能据此宣称已解决全部鼠标失效。
没有放宽主机认证、旧会话失效、前台保护或输入释放逻辑。

## 第二台 Mac 构建 Desktop

先拉取已推送的上述分支。若本机有未提交工作，先保留，不要强制覆盖。
使用项目 CI 同款 Flutter **3.44.2**，以及本机可用的 Xcode/macOS 构建工具。

```sh
git fetch origin
git switch codex/host-switch-pointer-and-sidebar
git pull --ff-only
flutter --version
(cd desktop_companion && flutter pub get)
bash scripts/build-full.sh macos --release
open desktop_companion/build/macos/Build/Products/Release/LumiaKey.app
```

`scripts/build-full.sh macos` 实际委托 `desktop_companion` 的
`flutter build macos`。本次 Windows 环境未执行这轮 macOS 构建。
启动新构建前正常退出旧 Desktop，避免手机仍连接旧进程；不要删除旧配置或清数据。

## macOS 输入权限与实测

macOS 原生鼠标发送要求 `AXIsProcessTrusted()` 和
`CGPreflightPostEventAccess()` 同时通过。`mouse-control-v1` 或 Launchpad
正常不等于鼠标注入权限已就绪。

在系统设置 → 隐私与安全性 → 辅助功能中，核对授权的是**本次启动的 LumiaKey**。
Desktop 的 macOS 输入权限卡片提供 `Request`、`Settings` 和刷新按钮；按系统
提示授权后刷新，必要时正常退出并重开本次构建。不要用终端批量重置 TCC 权限。
没有权限时原生通道会返回 `pointer_permission_missing`，由 HTTP 鼠标请求反馈失败。

手机 Full 用第二台 Mac Desktop 当前显示的配对信息连接，不公开配对码。
依次核对单指移动、单击、双指滚动、双指右击、右侧滚动条，再测 A → B → A
切换后重新抬起并落下手指。分别记录“移动失败”还是“仅点击失败”，不要仅凭
Launchpad 可以打开 App 判定鼠标通过。

## 可选 Full 手机诊断构建

仅在需要定位时启用，默认发布构建关闭：

```sh
flutter pub get
bash scripts/build-full.sh apk --release \
  --dart-define=LUMIAKEY_POINTER_DIAGNOSTICS=true
```

使用原签名正常升级安装，保留现有数据；不要为排查卸载、清数据或降低版本。
手机需要运行该诊断 APK，只有重建 Mac Desktop 不会打开手机诊断。

复现前启动以下过滤，**只保留固定前缀行，不保存未过滤的完整 logcat**：

```sh
adb logcat -v brief 'flutter:I' '*:S' | grep --line-buffered 'LUMIAKEY_POINTER '
```

多设备时给 `adb` 加 `-s <目标设备序列号>`。Android 日志 tag 是 `flutter`，
`LUMIAKEY_POINTER` 是消息正文的固定前缀。

日志每事件最多一条/秒，只包含门控布尔值、连接模式、input epoch、HTTP 状态和
固定错误类别；不记录 token、IP、主机名称、原始异常、坐标或按键内容。
观察 `moveGate/clickGate/scrollGate` 的 `routeDesktop/pinMatch/acceptedHost`，
以及 `queued → flushStarted → httpResponse`。`httpStatus=400` 表示服务端拒绝；
仅 `capability=true` 不能证明原生鼠标成功。没有这些行时，先确认安装的是带
define 的 Full，再区分手势未触发与发送路径失败。正常交付不要带该 define。

## Desktop 配置手机侧栏

Desktop 的 Launcher 页面 → **App Bar**，可添加、隐藏和上下移动已同步的
应用/已安装快捷键 profile。Launchpad 和 General 固定在顶部；**Restore default
list** 恢复默认列表。空列表仅保留这两个固定项；旧配置缺少该字段时沿用默认显示。
设置保存失败保留旧列表。隐藏当前选中/正在激活的项后，手机安全退回 Launchpad，
取消旧页面输入。该设置与十二格 Launchpad 槽位配置分别保存，不改变 App 启动能力。

## 当前自动化证据

- 推送前完整复测：Full **347 项通过**，Desktop **153 项通过、1 项 Linux 专用测试跳过**，共享协议 **35 项通过**；Full 与 Desktop 静态分析均无问题。
- 本分支已加入 Apple、Full Android/Windows 和 Linux 构建 CI 的 push 白名单；本地测试通过不代表第二台 Mac 的构建或鼠标实测已通过。
- 触控板新增生命周期 3 项加既有 4 项：**7/7 通过**；其中两项在修复前失败。
- Full 编号归一化后的鼠标路由、真实 loopback HTTP 旧请求挂起后切换新主机：
  **2/2 通过**，无蓝牙回退，也未跨主机串发。
- 诊断默认关闭与显式开启的白名单/限流测试均通过；相关静态分析无问题。
- Full 侧栏与既有 Regular/profile focused：**25 项通过**。
- Desktop `/pointer` 双主机认证、旧 token 拒绝及失败后恢复：**5 项通过**；
  使用 mock 原生通道，不代表 Mac Accessibility 或真实鼠标移动验收。
- Protocol 兼容性 focused：**23 项通过**。

Mac 实机交接请补充：源码 commit、实际启动的 app 路径/构建类型、权限卡片结果、
切换方向和失败手势、仅上述过滤后的诊断行。不要上传完整日志、配对码或用户内容。
