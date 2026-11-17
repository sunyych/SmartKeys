# 界面核对记录

核对日期：2026-10-28。依据：产品源码
`2469b3af6b2abad6a5ff5a8976d83e33f8ae0a04` 与重新生成的 Flutter 界面截图。
本次工作制作说明书及可复用截图，不修改产品界面行为。

## 建议修改的两处文案

1. **账户备份入口名称不准确。**
   `lib/ui/settings_screen.dart` 的入口显示 `Google Drive backup`，但
   `lib/ui/account_backup_screen.dart` 和 `docs/GOOGLE_BACKUP.md` 明确采用
   Google 登录认证的独立备份服务，不使用 Google Drive 范围或存储。
   建议统一改为 `Google account backup`，与备份页面标题一致。说明书保留
   当前入口原文以便用户定位，并明确解释实际存储行为。
2. **Android 连接说明错误地指向 iPad。**
   `lib/ui/desktop_connection_panel.dart` 的未连接说明在 Android 中也显示
   `Your microphone audio and speech recognition stay on this iPad`。
   建议将通用说明改为 `this device`，或按平台显示 phone/iPad。当前说明书
   使用准确的平台描述；截图保留真实界面，不修图掩盖该问题。

以上为可独立处理的小范围文案修正建议，尚未实施。

## 当前产品条件

- App 没有完整的中文界面切换。中文说明书不代表 App 已本地化；ASR 的
  Recognition language 是识别语言，不是界面语言。
- iPad 仅通过 Desktop 路线发送支持的快捷键和最终识别文字，不具备
  Android HID 的鼠标和持键行为。
- 排行榜需要服务端配置，Google 账户备份还需要 OAuth；未配置状态按真实
  条件说明，不能据此宣称服务已上线。
- 文档已包括 Desktop 的 Local Dictation，第七个导航项在旧 Desktop
  README 的六项导航摘要中尚未列出。主 README 中配置 schema 的版本摘要
  存在历史差异，用户说明书不依赖该内部版本描述。

## 验收范围

截图检查与 widget 测试只覆盖界面渲染和示例状态。蓝牙无线传输、麦克风与
真实模型识别、目标程序输入、系统权限和 iPad 安装操作需要对应设备验收。
