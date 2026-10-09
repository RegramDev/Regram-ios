# GitHub Actions 自动构建

`.github/workflows/build.yml` 在每次 `push` 以及手动 `workflow_dispatch` 时构建 `//Telegram:Regram`。不同分支独立排队；同一分支的推送不会取消上一轮构建。工作流使用官方 `xcode-27` arm64 托管 runner，与当前已验证的本地 Xcode 27 构建代际一致。

每次运行保留主程序和六个扩展，生成 arm64 Release 的可重新签名 IPA。对外只上传一个文件，命名为 **Regram-13.0-b40001.ipa**（版本来自 versions.json，构建号为 `40000 + github.run_number`）。上传使用 `archive: false`，下载得到 IPA 本身，不再额外包一层 ZIP。下载入口在该次 Actions 页面底部的 Artifacts，保存 14 天。

调试符号用于构建时 UUID 校验，不打包上传；校验报告保存在忽略的 build-input/ci 中，文件名、源码提交和 SHA-256 写入该次构建的 Summary。推送构建不会创建 Release。

## 确认后发布 Release

只有 **Publish confirmed IPA** 工作流可以发布 Release，且仅支持在 master 上手动运行。先下载并确认构建的 IPA，然后在 Run workflow 中填写成功的 Build Regram 运行 ID、完整 IPA 文件名，并勾选 **I confirm publishing this IPA filename and build to Releases**。不勾选确认时，发布任务不执行。

发布流程会核对来源是成功的 master 构建、artifact 精确名称、SHA-256、IPA 内的版本和构建号，下载时设置 `skip-decompress: true`，保留 IPA 本体。Release 标签为 **v13.0-b40001**，标题为 **Regram 13.0 (b40001)**，只有一个同名 IPA 附件。已存在的标签不会被覆盖。收到明确确认后，流程才创建草稿、上传 IPA，核对唯一附件后公开发布；未确认时不会创建草稿或公开 Release。

## 构建参数

仓库的加密 Secret **REGRAM_BUILD_CONFIGURATION** 保存一个 JSON 对象，键对应当前 `variables.bzl` 中的构建参数（不含 `telegram_bazel_path`）。该 Secret 包含 Telegram API 参数和应用身份。工作流只将它写入忽略的 `build-input/ci/configuration.json`，不会输出内容或上传到 artifacts，结束时删除明文配置与生成的配置仓库。

可从自己已生成的本地配置中提取 JSON，并通过 stdin 写入 GitHub Secret；不要把真实值添加到仓库。所需键和严格类型校验在 [prepare.py](../build-system/ci/prepare.py) 的 `VARIABLES` 中。

此工作流不上传或使用个人证书、Apple 私钥和真实设备 UDID。`prepare.py` 使用临时自签名证书生成七份合成 CMS 描述文件，用于满足 Bazel 的构建时元数据要求。它们不是 Apple 签发的安装授权，最终参考 IPA 会删除所有描述文件并保留完整 ad-hoc Mach-O 签名。安装前需用自己的合法签名材料重新签名，流程见 [LCSign 参考打包](lcsign-reference-packaging.md)。

## 缓存及校验

Actions 缓存仅包含 Bazel 的输出缓存，生成配置目录不在缓存路径中。标准托管 runner 的内存较小，因此限制 Bazel 并行任务与 Swift 编译线程。构建前应用仓库跟踪的 rules_apple 兼容补丁，并下载 Xcode 27 镜像中未预装的 MetalToolchain。Bazel 从固定发行版本下载并核对 `versions.json` 中的 SHA-256，Actions 依赖固定到完整提交 SHA。

[package.py](../build-system/ci/package.py) 会重新解包最终 IPA，检查七个 Bundle 的身份、版本、构建号、最低 iOS 15.0、arm64 架构、严格签名、12 个 dSYM UUID、字体目录与许可文件，并确认没有内置按需字体二进制。验证失败不会上传半成品。

工作流不运行模拟器，也不代替实际账号、网络、推送与真机界面验证。
