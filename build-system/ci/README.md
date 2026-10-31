# Regram CI 构建与发布

`master` 用于侧载参考 IPA；`regram-beta` 用于 TestFlight。TestFlight 的签名、上传、送审脚本及[使用说明](https://github.com/RegramDev/Regram-ios/blob/regram-beta/build-system/ci/TESTFLIGHT.md)位于 `regram-beta`。

GitHub 要求手动工作流入口存在于默认分支，因此 `master` 保留同名 `TestFlight` 入口，但只提示选择 `regram-beta`，不读取签名 Secret、构建或上传。操作路径为 Actions → TestFlight → Run workflow → 选择 `regram-beta`。日常发布选择 `publish`，`build_number` 留空；上传后的分发重试选择 `distribute` 并填写已上传的构建号。

TestFlight 的签名构建、上传、外部测试分组与重试方式见 [TestFlight](TESTFLIGHT.md)。

版本和构建号由根目录 versions.json 的 app/build 声明。Actions 与本地构建均通过 versioning.py 读取，工作流重跑不会递增。

Build Regram 在 macOS/Xcode 27 作业内构建 Regram，保留主应用与六个扩展，输出一份 IPA 和验证报告。

仓库 Secret `REGRAM_BUILD_CONFIGURATION` 使用 prepare.py 的 VARIABLES 完整配置结构，沿用现有 Bundle ID、App Group 和 API 配置。凭据仅写入忽略的 build-input/ci，结束时清除。不得把真实 API 凭据、证书或生成的配置加入提交。

安装包使用 `Regram-version-bbuild.ipa` 文件名，原始下载、签名、版本和校验信息继续验证；不再生成多身份包。

Publish confirmed IPA 选择成功的 master 构建、准确 IPA 文件名和发布确认；工作流只下载并校验这一份文件后发布，不因代码推送自动发布 Release。

离线检查：python3 build-system/ci/test_versioning.py、python3 build-system/ci/test_release.py。
