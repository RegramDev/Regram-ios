# b34639：XChat 应用图标

## 范围与源码

- 从 b34638 发布后的 `be9ad1c4ff60e890b5252246c0b787864f14c5e7` 接入本次图标；构建源码为 `8460d48d4833c0e1a3f49c8000533ccb9493a69d`。
- 新增 XChat 黑底银色气泡图标，入口为「Regram Pro → 外观与界面 → 应用图标」。原始 512px 图片原样保存，派生 1024px 图标及 256px 预览；默认与深色槽位使用相同原画。
- 简体中文、繁体中文与英文显示名称均为 XChat，内部资源名使用 `RGXChat`、文案键使用 `AppIcon.Name.xchat`。
- 使用独立标识，继续将已移除的 `RGSilver` 等旧图标配置归为当前默认图标。首次回归发现重名后已修正，并重跑相关存储、设置及图标选择检查。
- 原工作树的其他未提交修改没有纳入本版；应用默认图标、Bundle ID、App Group、钥匙串组及完整安装权限保持现有发布身份。

## 构建与校验

- Xcode 27.1（27A9275）、Bazel 9.2.0，`//Telegram:Regram` 完整 arm64 Release 成功，构建前后源码与本地配置摘要一致。
- 74 项发行回归检查通过；图标选择持久化、独立 actool 资源编译与 iPhone／iPad 图标声明检查通过。
- 最终 IPA 的四个 XChat 图标 rendition 与独立源资源编译的摘要一致，默认与深色预览及三语 XChat 名称均存在。
- 主应用与六个扩展、12 个 arm64 Mach-O、12 份匹配 dSYM、严格 ad-hoc 签名、零描述文件、字体目录与许可证、通知过滤、分享权限及实时活动声明校验通过。
- 七个 bundle 的完整 entitlements 与 b34638 一致。
- 完整应用没有在真机或真实账号执行，也未执行设备上的图标切换、系统桌面刷新及覆盖升级验收；图标显示效果仍需设备确认。

## 产物与发布

- Release：[v13.1.1-b34639](https://github.com/RegramDev/Regram-ios/releases/tag/v13.1.1-b34639)，已公开并设为 Latest。
- 构建源码与 Release 指向：`8460d48d4833c0e1a3f49c8000533ccb9493a69d`。发布后的说明提交仅更改文档。
- 文件：`Regram-13.1.1-b34639.ipa`。
- 大小：78,773,915 字节。
- SHA-256：`9668133edd65c547fd6d7c9c9eb12b01f6aa2c4af180da7fbaac5728bd7d3b03`。
- 公开 IPA 完整下载、字节数、SHA-256 附件和 GitHub 资产 digest 核对通过。生产 `RGUpdateRelease.parseGitHub` 能解析公开发布与 Latest，识别相对 b34638 的更新，并拒绝当前及更高构建的更新提示。
- dSYM 保存在本机独立产物目录，Release 只上传 IPA 和 `.ipa.sha256`。

## 缓存与记录

- 继续复用现有 `upstream-13.1.1` 输出缓存及已配置的磁盘／模块缓存，没有执行 clean 或 expunge。
- 构建后关闭本轮空闲 Bazel 服务，最终 IPA、校验文件、dSYM 和 manifest 保存在缓存以外的本轮忽略目录。
- 本轮日志、源码摘要、包 manifest、首次及修正后的回归报告、图标编译与最终包核验、身份对比及发布核验均保存在忽略的 `build-input/xchat-icon-34639/`。
