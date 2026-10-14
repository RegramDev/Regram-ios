# Regram CI 构建与发布

版本和构建号由根目录 versions.json 的 app/build 声明。Actions 与本地构建均通过 versioning.py 读取，工作流重跑不会递增。

Build Regram 在 macOS/Xcode 27 作业内构建 Regram，保留主应用与六个扩展，输出一份 IPA 和验证报告。

仓库 Secret `REGRAM_BUILD_CONFIGURATION` 使用 prepare.py 的 VARIABLES 完整配置结构，沿用现有 Bundle ID、App Group 和 API 配置。凭据仅写入忽略的 build-input/ci，结束时清除。不得把真实 API 凭据、证书或生成的配置加入提交。

安装包使用 `Regram-version-bbuild.ipa` 文件名，原始下载、签名、版本和校验信息继续验证；不再生成多身份包。

Publish confirmed IPA 选择成功的 master 构建、准确 IPA 文件名和发布确认；工作流只下载并校验这一份文件后发布，不因代码推送自动发布 Release。

离线检查：python3 build-system/ci/test_versioning.py、python3 build-system/ci/test_release.py。
