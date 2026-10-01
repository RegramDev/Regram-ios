# Regram

Regram 是基于 [Telegram for iOS](https://github.com/TelegramMessenger/Telegram-iOS) 的非官方 iOS 客户端。本仓库提供源码与构建说明；构建时请使用自己的 Telegram API 凭据、Bundle ID 和 Apple 签名材料。Regram 与 Telegram 官方没有隶属关系。

## 功能

- 消息过滤：正则与内容匹配、会话级开关、规则导入导出。
- 隐私与消息操作：防撤回、隐藏指定用户的消息、幽灵模式、可调整的消息菜单。
- 翻译与转写：可选翻译后端、聊天翻译和语音转写。
- 界面定制：图标、贴纸显示与最近贴纸数量、聊天列表及标签栏选项。

功能可用性受 Telegram 服务端权限、iOS 版本及所选翻译后端影响。部分界面和数据处理仍在上游模块中；Regram 自有模块位于 **Regram/**，对上游源码的改动标有 **MARK: Regram**。

## 构建准备

需要 macOS、Xcode、Python 3、Git。项目要求的工具版本见 [versions.json](versions.json)。安装 Xcode 后，确认 xcode-select 指向完整的 Xcode，而非仅 Command Line Tools。构建系统由 **build-system/Make/Make.py** 驱动。

~~~sh
git clone --recursive https://github.com/RegramDev/Regram-ios.git
cd Regram-ios
git submodule update --init --recursive
~~~

当前 rules_apple 子模块还需要仓库内的兼容补丁；用途和维护方式见[补丁说明](build-system/patches/README.md)。

~~~sh
git -C build-system/bazel-rules/rules_apple apply ../../patches/rules_apple-local.patch
~~~

复制开发配置模板到被 Git 忽略的 **build-input/**，填写自己的 bundle_id、api_id、api_hash 和 team_id。API 凭据可从 [Telegram 的申请页面](https://core.telegram.org/api/obtaining_api_id)获取。不要修改并提交模板本身，也不要把本地配置、证书或描述文件加入 Git。

~~~sh
cp build-system/template_minimal_development_configuration.json build-input/regram-development.json
~~~

### 在模拟器运行

生成 Xcode 项目后，在 Xcode 中选择可用的 iOS 模拟器和 Regram scheme。下面的配置仅用于模拟器，不用于真机安装。

~~~sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir="$PWD/build-input/bazel-cache" \
  generateProject \
  --configurationPath=build-input/regram-development.json \
  --xcodeManagedCodesigning \
  --disableProvisioningProfiles
~~~

如果本机 Xcode 与 versions.json 一致，可以省略 --overrideXcodeVersion。该选项只跳过版本检查，不能解决 SDK 或编译器不兼容。

### 构建真机 IPA

真机完整构建需要与主 App **及 6 个扩展**的 Bundle ID 和 entitlements 匹配的证书、描述文件。将材料放入本地目录，目录结构参考 **build-system/fake-codesigning/**，但不要将示例签名材料用于正式分发。

~~~sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir="$PWD/build-input/bazel-cache" \
  build \
  --configurationPath=build-input/regram-development.json \
  --codesigningInformationPath=build-input/codesigning \
  --buildNumber=10001 \
  --configuration=release_arm64 \
  --target=//Telegram:Regram
~~~

输出为 **bazel-bin/Telegram/Regram.ipa**。如果需要生成供其他签名工具处理的 ad-hoc 参考包，请按 [LCSign 兼容打包说明](docs/lcsign-reference-packaging.md)操作；它不能代替 Apple 签名和匹配的描述文件。

## 开发文档

- [文档索引](docs/README.md)
- [上游同步方案](docs/regram-upstream-sync.md)
- [UI 测试](docs/ui-testing.md)
- [富文本输入与消息渲染](docs/richtext-composer.md)

欢迎提交问题与补丁，详见[贡献指南](.github/CONTRIBUTING.md)。分发修改版时，请遵守 Telegram 源码及第三方依赖的许可与品牌要求，并明确标识客户端为非官方版本。
