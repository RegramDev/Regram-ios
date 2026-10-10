# 文档导航

从仓库根目录的 [README](../README.md) 开始：它介绍 Regram、构建要求和源码结构。此目录按用途分为：

- [已加入功能清单](features.md)：按模块汇总当前功能、入口、可用条件、实验状态和已移除项目。
- [LCSign 兼容打包](lcsign-reference-packaging.md)：从已构建的 IPA 生成供后续签名的 ad-hoc 参考包，并检查包结构。
- [上游同步方案](regram-upstream-sync.md)：迁移与版本升级的设计方案；其中的分支模型是建议，不代表当前仓库已全面实施。
- [UI 测试](ui-testing.md)：测试环境、测试账号和 XCUITest 的使用方式。
- [富文本输入](richtext-composer.md)与[富文本消息渲染](instantpage-richtext.md)：相关模块的数据流和维护约束。
- [Turrit 1.5.4 性能实现对比](turrit-1.5.4-performance-analysis.md)：视频与聊天媒体预加载、下载调度的静态分析证据及验证边界。
- [Turrit 1.5.4 全链路审计](turrit-1.5.4-full-chain-audit.md)：补充消息处理队列、播放器保留、HLS 片段准入与首帧交接，并核对上传下载限额线索及试验版缺口。
- [Turrit 1.5.4 补充机制调查](turrit-1.5.4-additional-mechanisms.md)：统一画质选择、滚动方向扩展、共有连接/数据库参数，以及仍待追踪的请求队列线索。
- [聊天加载试验](media-loading-experiment.md)：消息后台处理、媒体预取、播放器保留、首帧交接与全局画质的开关、实现范围及构建验证记录。
- [通知启动与偶发空提醒](notification-startup-and-empty-alerts.md)：Nagram 源码与 IPA 对照、通知重试与处理期限、推送注册顺序及真实设备验证边界。

**superpowers/** 保存早期设计、实施计划和重构记录，属于历史资料。其版本号、命令输出和当时的构建环境不应当作当前发布说明。构建时请以 README、versions.json 和现行 BUILD 文件为准。

文档中的本地配置、签名文件和产物路径均应使用读者自己的环境；不要把含有 API 凭据、证书或真实用户数据的文件提交到仓库。
