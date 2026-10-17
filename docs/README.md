# 文档导航

先阅读根目录的[中文 README](../README.md)／[English README](../README.en.md)。当前功能与流程按 **13.0 / b34620** 整理，构建要求以 [versions.json](../versions.json)、现行 BUILD 文件及根 README 为准。

## 功能与使用

- [完整功能清单](features.md)：九类设置、入口、默认行为、本机存储、容量和权限边界。
- [近期更新记录](changelog.md)：消息、界面、网络、更新与图标的主要改动，区分历史修正与当前行为。
- [翻译、语音、链接与设置](speech-links-settings.md)：独立总结接口、语音／圆视频识别、网页翻译、预览规则及设置导航。
- [自动更新与安装](app-updates.md)：GitHub 来源、系统网络范围、后台下载、证书／TrollStore、灵动岛及安装后清理。

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

[二维码与证书导入修正](qr-login-and-certificate-import.md)、[13.0 功能审查](telegram-13-feature-audit.md)、带构建号的问题分析，以及其他专项记录，保留当时的排查背景。与当前功能文档冲突时，按现行源码、功能清单及更新说明判断。

[上游同步方案](regram-upstream-sync.md)属于设计建议，不代表仓库已经全面采用其中的分支模型。`superpowers/` 保存早期设计与实施笔记，不是现行发布或构建说明。

本地凭据、证书、描述文件、生成配置及真实账号数据不得提交。示例路径需要替换为读者自己的环境，生成物保存在被忽略的 `build-input/` 或 `build/`。
