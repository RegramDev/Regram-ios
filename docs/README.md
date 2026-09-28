# 文档导航

从仓库根目录的 [README](../README.md) 开始：它介绍 Regram、构建要求和源码结构。此目录按用途分为：

- [LCSign 兼容打包](lcsign-reference-packaging.md)：从已构建的 IPA 生成供后续签名的 ad-hoc 参考包，并检查包结构。
- [上游同步方案](regram-upstream-sync.md)：迁移与版本升级的设计方案；其中的分支模型是建议，不代表当前仓库已全面实施。
- [UI 测试](ui-testing.md)：测试环境、测试账号和 XCUITest 的使用方式。
- [富文本输入](richtext-composer.md)与[富文本消息渲染](instantpage-richtext.md)：相关模块的数据流和维护约束。

**superpowers/** 保存早期设计、实施计划和重构记录，属于历史资料。其版本号、命令输出和当时的构建环境不应当作当前发布说明。构建时请以 README、versions.json 和现行 BUILD 文件为准。

文档中的本地配置、签名文件和产物路径均应使用读者自己的环境；不要把含有 API 凭据、证书或真实用户数据的文件提交到仓库。
