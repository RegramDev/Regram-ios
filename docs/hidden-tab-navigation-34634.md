# b34634：隐藏底栏后的返回与二维码响应

2026-10-24，基于 b34633 的发布源码 `5e9676027ce7b1eda197087e77640d2733409812`，修复隐藏底栏后设置首页的返回和二维码按钮点击无响应的问题。版本为 **13.1.1 / b34634**。

`RGSettingsLeadingButtonsNode` 继承 `HighlightableButtonNode`，其底层 `ASControlNode` 在没有自身 target 时默认关闭触摸。返回与二维码的 target 注册在两个子按钮上，组合容器本身没有 target，因而 UIKit 命中测试无法到达子按钮。修复显式开启组合容器交互，并保持容器不作为单个辅助功能元素；子按钮仍各自处理动作与高亮。

修复保留现有 Telegram 导航组件、玻璃外观、88 × 44 点布局、两个 44 × 44 点点击区、图标着色和返回／二维码动作。应用逻辑修改仅位于 `Regram/`。

## 回归和编译

新增 `//Regram/RGSettingsUI:RGSettingsLeadingButtonsTests`，直接编译生产控件，与真实 `NavigationButtonComponent`、AsyncDisplayKit 和 UIKit 一起在 iPhone 17／iOS 26.5 模拟器运行。旧生产代码在同一组 4 项测试中全部因无法命中子按钮失败；修复后 4 项全部通过，覆盖两个动作独立触发、点击区边缘与辅助功能、主题更新、取消触摸及重新挂载。

这些测试执行真实 UIKit 命中测试及合成触摸序列；没有登录真实账号，也没有执行完整应用真机、真实扫码或覆盖升级验收。现有 `check-regram-features.py` 的 70 项检查通过，包含底栏、根设置手势、返回转场、设置运行时和导航颜色。旧 `run-hidden-tab-checks.py` 仍依赖上游 13.1.1 之前的 getter 签名，提取失败，本轮不计为通过；本次生产触摸路径由新增 UIKit 回归覆盖。

Xcode 27.1（27A9275）完成 `//Telegram:Regram` 的完整 arm64 Release；构建前后已跟踪文件、构建配置与 rules_apple 兼容补丁摘要一致。主应用和六扩展、arm64、零描述文件、严格 ad-hoc 签名、资源及 12 份匹配 dSYM 校验通过；七个 bundle 的标识和完整 entitlements 与 b34633 一致。

构建源码及 Release 目标：`741d3d90801345db5d4b0288f29d7a2b000c732a`。后续文档提交只更新介绍和本轮记录，不改变应用源码或交付包。

复用的 Bazel 输出和模块缓存跨版本保留，模拟器与发行构建的闲置服务均已关闭。安装包、匹配符号、manifest、源码摘要、构建日志与发布核验记录保存在忽略的 `build-input/hidden-tab-navigation-34634/`。

## 发布与下载校验

发布：[Regram 13.1.1（b34634）](https://github.com/RegramDev/Regram-ios/releases/tag/v13.1.1-b34634)，已设为最新稳定版。

文件：`Regram-13.1.1-b34634.ipa`

大小：77,946,253 字节

SHA-256：`aec017f3ddf7a2912d488c3d9deea9ef6bf4555d3c4250a57c820217daf9d79a`

Release 只附 IPA 与 `.ipa.sha256`，匹配 dSYM 保留本地。草稿附件、正式 tag、目标提交、Latest、GitHub digest、完整公开下载与 SHA-256 附件核对通过；生产 `RGUpdateRelease.parseGitHub` 可解析实际公开 JSON 并将 b34633 识别为可更新版本，同时核对缓存元数据及当前／较新版的比较结果。
