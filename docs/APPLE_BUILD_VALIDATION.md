# Apple 构建与支持范围

更新日期：2026-10-22。

## 构建记录

验证基线：源码 `2469b3a`，Flutter 3.47.2 / Dart 3.13.2，Xcode 27.0
(`27A266a`)。以下结果来自 macOS 本机；它们证明构建、链接和打包，
不等同于完整功能验收。

- iOS Release 无签名构建成功，产物约 53 MB。
- 使用 Apple Development 身份与开发团队 `UXQMR4GU6P` 完成 archive，
  并以 `debugging` 导出开发版 IPA：`LumiaKey.ipa`。这是仅供已登记设备
  安装的开发配置，不是 TestFlight 或 App Store 发布包。
- macOS Release 构建成功，产物约 106.4 MB。主程序和
  `libsherpa-onnx-c-api.dylib` 均包含 `arm64`、`x86_64` 架构；应用通过
  严格深度签名验证（当前为 ad hoc 签名），DMG 校验成功。
- iOS Simulator Debug build 成功；在 iPhone 16 Pro / iOS 18.5 Simulator
  上通过 `simctl` 安装并启动。进程在启动数秒后仍为 PID 17285、状态 0。
  截图保存在 `build/ui_screenshots/ios/ios-startup.png`（1206×2622，纵向），
  已加入当前截图索引。该验证只覆盖 Simulator 安装/启动，不代表实体设备或
  麦克风、ASR、网络、文字插入功能通过。
- macOS Release app 进程 PID 13961 持续运行；Companion TCP 端口 54419 的
  `/info` 在无 token 请求时返回 HTTP 403，验证了启动及基础认证拒绝路径，
  不代表 ASR、键盘注入或其他端到端功能已通过。
- macOS app/DMG 未公证；实体 iPhone/iPad 安装启动、麦克风采集、桌面配对及
  目标应用文本插入仍未验收。

## 构建命令与交付

以下是可复现相应构建类型的主要 Flutter 命令；签名开发包使用本机已有的
Apple Development identity/provisioning profile，通过 Xcode archive 与
export 流程完成，没有改写仓库中的签名团队配置。

```sh
flutter build ios --release --no-codesign
flutter build ios --debug --simulator
(cd desktop_companion && flutter build macos --release)
```

签名 IPA 使用开发导出配置（`debugging`），目标为已登记设备；这不是
TestFlight/App Store 发行。交付文件放在主仓库的
`/Volumes/SSD/Projects/SmartKeys/build/artifacts/`：
`LumiaKey-macOS-v1.3.0.dmg` 与 `LumiaKey-iOS-v1.3.0-development.ipa`。

## 最低系统与设备范围

- iOS/iPadOS：项目构建设置和导出应用 `Info.plist` 的最低版本均为
  **iOS 15.0**。按 Apple 对 iOS 15 的设备支持范围，系统层面包括
  **iPhone 6s 及更新机型、所有 iPad Pro、iPad Air 2 及更新机型、
  iPad 第 5 代及更新机型、iPad mini 4 及更新机型**。这是操作系统层面
  可安装范围，不是 ASR 在老设备上的速度、内存或耗电保证。
- macOS：最低版本为 **macOS 12.0**。
- Android：最低 API 为 **28（Android 9）**。

最低版本以当前 Runner 工程和构建产物为准；Xcode/Flutter 升级后的工程设置
可能比上游原始模板要求更高。Apple 的 iOS 15 设备范围可见
[iOS 15 安全性更新适用设备列表](https://support.apple.com/en-us/103160)。

## 本地语音识别与验收边界

SenseVoice 默认模型在设备本地识别中文和英文。首次使用需要下载约
**239 MB** 的模型文件；模型未就绪时，识别不可用。可选的 Cohere 模型数据
约 **2.7 GB**，需额外评估存储、内存、推理速度和耗电。

虽然 iOS/macOS 原生插件已成功参与上述构建，构建成功不等于真实音频链路
已验证。仍需在目标设备上检查麦克风授权、模型下载与加载、中文/英文识别
质量、延迟和内存表现，以及 iPad 到同一局域网 Desktop 的文本交付。

## 自动化验证摘要

四个 Dart package 的静态分析通过；root 186 项、Desktop 30 项、Protocol
6 项、Engine 24 项通过，另有 1 项因模型/中文英文 WAV/native environment
依赖缺失而跳过。当前截图索引汇集 74 张 Flutter widget 截图及 1 张
iOS Simulator 启动截图，共 75 张；图库截图不是实体手机截图。
