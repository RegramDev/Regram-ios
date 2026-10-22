# 文档导航

先阅读根目录的[中文 README](../README.md)／[English README](../README.en.md)。当前功能与流程按 **13.0 / b34626** 整理，构建要求以 [versions.json](../versions.json)、现行 BUILD 文件及根 README 为准。

## 功能与使用

- [手势、设置清理与顶部标记修复](navigation-community-badge-fixes.md)：2026-10-22 的未发布源码修复与编译边界。
- [设置横栏、图标与控件](settings-controls-34626.md)：b34626 的原生文件夹横栏、图标取舍和居中、深色开关与操作按钮颜色，包含构建与交付记录。
- [过滤提及与设置层级](settings-navigation-34625.md)：b34625 的逐条隐藏提及处理、分类内设置与页内标签，包含构建及跳过测试的记录。
- [完整功能清单](features.md)：九类设置、入口、默认行为、本机存储、容量和权限边界。
- [近期更新记录](changelog.md)：未发布修复、b34626 及旧版本记录。
- [b34624 界面与构建验证](settings-appearance.md)：设置与新增功能页样式、原生底栏搜索、构建来源、校验值及设备验收边界。
- [翻译、语音、链接与设置](speech-links-settings.md)：独立总结接口、语音／圆视频识别、网页翻译、预览规则及设置导航。
- [自动更新与安装](app-updates.md)：GitHub 来源、系统网络范围、后台下载、证书／TrollStore、灵动岛及安装后清理。
- [设置与兼容清理](settings-cleanup-34622.md)：b34622 的聊天功能移除、Inline 页面、盘古设置归组与 Swiftgram 兼容移除。
- [聊天与界面增强](chat-and-interface-tools.md)：b34621 功能入口、逐项实现与验证记录，格式工具栏保持原样。
- [分组、手势、设置定位与导入](settings-fixes-34623.md)：b34623 的修正范围、审查结论及验证边界。

## 构建与维护

- [GitHub Actions](github-actions-build.md)：读取版本、构建一份 IPA、校验报告与确认发布流程。
- [LCSign 兼容打包](lcsign-reference-packaging.md)：从构建 IPA 生成可重新签名的 ad-hoc 参考包，并核对结构、权限及调试符号。
- [UI 测试](ui-testing.md)：测试环境与 XCUITest 使用方式，不能替代真实账号和设备验收。
- [富文本输入](richtext-composer.md)及[富文本消息渲染](instantpage-richtext.md)：数据流、现有能力和维护边界。
- [媒体加载试验](media-loading-experiment.md)：预取、播放准入、播放器复用、首帧交接和性能验证边界。
- [兼容补丁](../build-system/patches/README.md)：rules_apple 工作树修改的来源与应用方式。

## 通知实验与诊断

- [实验性通知恢复](notification-recovery.md)：调试开关、通知专用读取与资源预算、缓存清理及一／二行预览修正，包含验证边界。

## 历史分析与设计资料

- [Nagram 历史功能缺口（2026-10-20）](nagram-feature-gaps-2026-10-20.md)：追溯早期增强，列出 Regram 缺少的入口／功能与细分配置，附固定版本源码证据。
- [Nagram 更新对照与置顶排查（2026-10-20）](nagram-review-2026-10-20.md)：本地置顶重建丢失修正、验证范围，以及适合后续吸收的修复与功能。

[二维码与证书导入修正](qr-login-and-certificate-import.md)、[13.0 功能审查](telegram-13-feature-audit.md)、带构建号的问题分析，以及其他专项记录，保留当时的排查背景。与当前功能文档冲突时，按现行源码、功能清单及更新说明判断。

[上游同步方案](regram-upstream-sync.md)属于设计建议，不代表仓库已经全面采用其中的分支模型。`superpowers/` 保存早期设计与实施笔记，不是现行发布或构建说明。

本地凭据、证书、描述文件、生成配置及真实账号数据不得提交。示例路径需要替换为读者自己的环境，生成物保存在被忽略的 `build-input/` 或 `build/`。
