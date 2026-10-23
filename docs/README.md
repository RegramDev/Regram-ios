# 文档导航

先阅读根目录的[中文 README](../README.md)／[English README](../README.en.md)。当前功能与流程按 **13.1.1 / b34633** 整理，构建要求以 [versions.json](../versions.json)、现行 BUILD 文件及根 README 为准。

## 功能与使用

- [b34633 装扮同步、礼物升级与通知入口](profile-notifications-34633.md)：引用名称颜色与顶部礼物状态联动、保留普通结算、本地限定礼物升级，以及实验性通知恢复迁移。

- [现有功能修复（2026-10-24）](functional-fixes-20261024.md)：三轮排查中富文本工具、本地礼物、消息保留、翻译、分享、回车发送及状态刷新的 18 项修正。
- [b34632 本地个人资料扩展](local-profile-customization-34632.md)：礼物置顶与头像装饰、正负评级、TON 资料卡、手机号双输入框、键盘避让及隐藏底栏时的导航图标颜色，包含正式发布记录。
- [本地定制、礼物与链接分享](local-gifts-and-link-sharing.md)：“显摆一下”专区、手机号显示、原生礼物购买与详情、余额及资料装扮联动，包含 b34631 正式发布、历史测试包与验证边界。

- [图标、跨设备备份与标记渲染复查](icon-backup-rendering-audit.md)：取消图标切换失败提醒、统一设置恢复状态、减少重复布局及修正外观同步；包含深灰配色 b34629 正式发布、历史本地测试包、包校验与缓存保留记录。
- [共同群组、设置搜索与拖动预览复查](groups-settings-search-drag-fixes.md)：b34628 的分页、搜索状态与入口整合、原生开关拖动预览及顶部标记修正，包含构建、正式发布和验证边界。
- [归档、手势与设置显示修复](navigation-community-badge-fixes.md)：b34627 的源码修复、编译、包校验及用户测试反馈，包含正式发布和公开下载核验记录。
- [社群关联会话归档排查](community-archive-audit-20261022.md)：归档后回到主列表的原因，汇总、展开及异步补齐的修正和源码核对范围。
- [设置横栏、图标与控件](settings-controls-34626.md)：b34626 的原生文件夹横栏、图标取舍和居中、深色开关与操作按钮颜色，包含构建与交付记录。
- [过滤提及与设置层级](settings-navigation-34625.md)：b34625 的逐条隐藏提及处理、分类内设置与页内标签，包含构建及跳过测试的记录。
- [完整功能清单](features.md)：九类设置、入口、默认行为、本机存储、容量和权限边界。
- [近期更新记录](changelog.md)：b34631、b34630 及旧版本记录。
- [b34624 界面与构建验证](settings-appearance.md)：设置与新增功能页样式、原生底栏搜索、构建来源、校验值及设备验收边界。
- [翻译、语音、链接与设置](speech-links-settings.md)：独立总结接口、语音／圆视频识别、网页翻译、预览规则及设置导航。
- [自动更新与安装](app-updates.md)：GitHub 来源、系统网络范围、后台下载、证书／TrollStore、灵动岛及安装后清理。
- [设置与兼容清理](settings-cleanup-34622.md)：b34622 的聊天功能移除、Inline 页面、盘古设置归组与 Swiftgram 兼容移除。
- [聊天与界面增强](chat-and-interface-tools.md)：b34621 功能入口、逐项实现与验证记录，格式工具栏保持原样。
- [分组、手势、设置定位与导入](settings-fixes-34623.md)：b34623 的修正范围、审查结论及验证边界。

## 构建与维护

- [Telegram 13.1.1 上游同步](upstream-sync-20261023.md)：同步范围、现有 UI 保留、功能兼容修正及 b34630 构建与交付记录。
- [图标与截图标记](../Regram/RGBranding/README.md)：絮语、合流及各配色从同一源派生明确的深浅资源，原默认图标改为备用；截图标记跟随应用主题，保留 Regram、知秋原图。
- [GitHub Actions](github-actions-build.md)：读取版本、构建一份 IPA、校验报告与确认发布流程。
- [LCSign 兼容打包](lcsign-reference-packaging.md)：从构建 IPA 生成可重新签名的 ad-hoc 参考包，并核对结构、权限及调试符号。
- [UI 测试](ui-testing.md)：测试环境与 XCUITest 使用方式，不能替代真实账号和设备验收。
- [富文本输入](richtext-composer.md)及[富文本消息渲染](instantpage-richtext.md)：数据流、现有能力和维护边界。
- [媒体加载试验](media-loading-experiment.md)：预取、播放准入、播放器复用、首帧交接和性能验证边界。
- [兼容补丁](../build-system/patches/README.md)：rules_apple 工作树修改的来源与应用方式。

## 通知实验与诊断

- [实验性通知恢复](notification-recovery.md)：通知设置入口、通知专用读取与资源预算、缓存清理及一／二行预览修正，包含验证边界。

## 历史分析与设计资料

- [Nagram 历史功能缺口（2026-10-20）](nagram-feature-gaps-2026-10-20.md)：追溯早期增强，列出 Regram 缺少的入口／功能与细分配置，附固定版本源码证据。
- [Nagram 更新对照与置顶排查（2026-10-20）](nagram-review-2026-10-20.md)：本地置顶重建丢失修正、验证范围，以及适合后续吸收的修复与功能。

[二维码与证书导入修正](qr-login-and-certificate-import.md)、[13.0 功能审查](telegram-13-feature-audit.md)、带构建号的问题分析，以及其他专项记录，保留当时的排查背景。与当前功能文档冲突时，按现行源码、功能清单及更新说明判断。

[上游同步方案](regram-upstream-sync.md)属于设计建议，不代表仓库已经全面采用其中的分支模型。`superpowers/` 保存早期设计与实施笔记，不是现行发布或构建说明。

本地凭据、证书、描述文件、生成配置及真实账号数据不得提交。示例路径需要替换为读者自己的环境，生成物保存在被忽略的 `build-input/` 或 `build/`。
