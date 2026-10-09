# GitHub Actions 自动构建

`.github/workflows/build.yml` 在每次 `push` 以及手动 `workflow_dispatch` 时构建 `//Telegram:Regram`。不同分支独立排队；同一分支的推送不会取消上一轮构建。工作流使用官方 `xcode-27` arm64 托管 runner，与当前已验证的本地 Xcode 27 构建代际一致。

每次运行保留主程序和六个扩展，生成 arm64 Release 的 LCSign 参考 IPA、12 份匹配的调试符号及 `BUILD-MANIFEST.json`。下载入口在该次 Actions 页面底部的 Artifacts。保存 14 天；工作流不自动创建 GitHub Release。构建号为 `40000 + github.run_number`，重新运行会使用相同构建号和不同的 artifact 名称。

## 构建参数

仓库的加密 Secret **REGRAM_BUILD_CONFIGURATION** 保存一个 JSON 对象，键对应当前 `variables.bzl` 中的构建参数（不含 `telegram_bazel_path`）。该 Secret 包含 Telegram API 参数和应用身份。工作流只将它写入忽略的 `build-input/ci/configuration.json`，不会输出内容或上传到 artifacts，结束时删除明文配置与生成的配置仓库。

可从自己已生成的本地配置中提取 JSON，并通过 stdin 写入 GitHub Secret；不要把真实值添加到仓库。所需键和严格类型校验在 [prepare.py](../build-system/ci/prepare.py) 的 `VARIABLES` 中。

此工作流不上传或使用个人证书、Apple 私钥和真实设备 UDID。`prepare.py` 使用临时自签名证书生成七份合成 CMS 描述文件，用于满足 Bazel 的构建时元数据要求。它们不是 Apple 签发的安装授权，最终参考 IPA 会删除所有描述文件并保留完整 ad-hoc Mach-O 签名。安装前需用自己的合法签名材料重新签名，流程见 [LCSign 参考打包](lcsign-reference-packaging.md)。

## 缓存及校验

Actions 缓存仅包含 Bazel 的输出缓存，生成配置目录不在缓存路径中。标准托管 runner 的内存较小，因此限制 Bazel 并行任务与 Swift 编译线程。构建前应用仓库跟踪的 rules_apple 兼容补丁。Bazel 从固定发行版本下载并核对 `versions.json` 中的 SHA-256，Actions 依赖固定到完整提交 SHA。

[package.py](../build-system/ci/package.py) 会重新解包最终 IPA，检查七个 Bundle 的身份、构建号、最低 iOS 15.0、arm64 架构、严格签名、12 个 dSYM UUID、字体目录与许可文件，并确认没有内置按需字体二进制。验证失败不会上传半成品。

工作流不运行模拟器，也不代替实际账号、网络、推送与真机界面验证。
