# 图标库与错误诊断：Coding agent handoff

## 任务与分支

- 工作分支：`feature/app-icon-library`。
- 干净起点：`791b022ccf1c3329009ab1b8df18ecdc20faf0ea`，来自最新 main。
- 本分支目前只交付需求、图标清单和实现交接，不表示功能已经开发完成。
- 不要合并整个旧 WIP 分支。最新 main 已有 Regular / Lite 拆分和手机版 Launchpad，保留这些实现。
- 先读 [图标需求](ICONS_REQUIREMENTS.md)、[错误日志与可选分享](ERROR_DIAGNOSTICS.md)、[首批 50 App 清单](BUILTIN_APPS_50.json)。

## 用户授权范围

1. 现有网页 dashboard 增加应用图标库，能按 App ID 搜索、预览、下载。
2. 手机 App 预置首批 50 个常用 App 的完整图标；其他图标可从网站下载并缓存。
3. 手机提供仅记录错误的运行日志；记录错误发生时间和触发模块，不记录按键、具体快捷键或输入内容。
4. 首次使用明确询问是否分享匿名错误诊断。允许后才发送到中心服务器；拒绝则仅本机保存。
5. 用户要求交接写完必须 commit 并 push；本次只提交 handoff。接手实现后同样应在已授权功能分支保存提交与推送，并如实汇报验证结果。

## 当前架构入口

- `docs/MOBILE_EDITIONS.md`、`docs/MOBILE_EDITIONS_VALIDATION.md`：当前 main 产品边界与已有验证记录，不要重新做版本拆分。
- `lib/ui/regular_home_screen.dart`：Regular 的 Launchpad / 左侧导航 / 应用快捷键。
- `lib/ui/home_screen.dart`、`lib/app.dart`、`lib/app_edition.dart`：现有移动端路由与 Lite 入口。
- `lib/icons/icon_catalog.dart`、`assets/app_icons/`、`docs/APP_ICON_SOURCES.md`：已有图标处理及七个 PNG。
- `desktop_companion/lib/desktop_ui.dart`、`desktop_controller.dart`：现有电脑端界面和 App 配置。
- `community_server/src/main.rs`、`web.rs`、`web/index.html`、`dashboard.js`、`dashboard.css`：现有 Rust 网页服务与 dashboard；在这里扩展，不另建无关网站。
- `lib/ui/community_setup_screen.dart`、`lib/data/community_setup_repository.dart`：首次社区设置。现有提示并不等同于新错误诊断授权。
- `lib/data/shortcut_usage_repository.dart`、`lib/ui/settings_screen.dart`：现有统计与分享入口；本任务的新诊断通道只允许错误数据。
- `scripts/generate_screenshot_index.dart`：统一截图索引。

旧分支 `feature/mobile-launcher-and-editions` 的 `08993e6` 保存了未完成图标网页、原始图标读取/缓存等尝试。仅作参考，需逐文件 review / 有选择地复用；旧分支还包含另一套版本拆分和 Linux 改动，不在本任务中整批合入。不要把其未验证代码当成完成实现。

## 建议实施顺序

1. 核查当前 main 与图标/日志入口，保持现有 Regular/Lite 与快捷键行为。
2. 固定 canonical App ID、别名、目录格式和资源来源，取得并打包首批 50 个真实图标。
3. 在现有 dashboard 中实现图标页面、目录与下载接口，再接入 App 的下载缓存与离线降级。
4. 实现有容量限制的本地错误日志、查看/清除入口和输入脱敏。
5. 实现独立、默认关闭的错误分享授权与中心服务器接收；补撤销授权、网络失败和重试边界。
6. 跑回归、资源打包检查、API 与浏览器交互测试、当前界面截图；review 后 commit/push。

## 用户的开发约定

- 开发由子智能体承担，Luna 为 coder；主 agent 负责检测、测试与 review。若当前环境没有该模型，应明确告知，不能假称使用了它。
- 修改/新增的每个界面加入截图测试，只保留当前版本。
- 不要求模型逐张读取或分析图片；集中生成一个大的 `index.html` 供用户查看。
- 不改主分支、不自行发布 Release 或创建 GitHub 仓库；本任务不重新设计键盘布局或拆分版本。

## 最终交付

- 干净可 review 的功能分支提交和 GitHub 链接。
- 首批 50 个图标的真实资源与来源记录、App 离线验证证据。
- 可访问的网页图标库与 App ID 下载 API，以及额外在线图标的演示。
- 错误日志/授权/仅本地/允许分享四条路径的测试证据。
- 所有新增界面的当前截图索引；实际执行的测试与构建结果，未验证平台须说明。

## Suggested skills

- `handoff`：保持交接状态与事实准确。
- `diagnose`：用于错误复现、日志边界、图标请求失败和缓存问题。
- `review`：完成后的正确性与隐私边界检查。
- 现有源码修改即可完成本任务，不需新建独立桌面程序或新部署的网站。
