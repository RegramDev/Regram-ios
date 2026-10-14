# Regram CI 构建与发布

版本和构建号由根目录 versions.json 的 app/build 声明，五种安装身份使用同一版本号。Actions 与本地构建均通过 versioning.py 读取，工作流重跑不会递增。

Build Regram 在同一 macOS/Xcode 27 作业内依次构建五种身份，复用 Bazel 缓存；各包保留主应用与六个扩展，输出五份独立 IPA 和验证报告。串行生成配置，避免多个作业同时改写共享的 configuration-repository。

仓库 Secret `REGRAM_BUILD_VARIANTS_CONFIGURATION` 是以五种身份名称为键的 JSON 对象，每项使用 prepare.py 的 VARIABLES 完整配置结构。凭据仅写入忽略的 build-input/ci，结束时清除。不得把真实 API 凭据、证书或生成的配置加入提交。

基础包保留 Regram-version-bbuild.ipa 文件名，额外身份使用 Regram-Identity-version-bbuild.ipa。包内身份标记与 Bundle ID／App Group 必须匹配，原始下载、签名、版本和校验信息按身份独立验证。

Publish confirmed five-identity release 选择成功的 master 构建、基础 IPA 文件名和发布确认；工作流下载并校验五个对应文件后统一发布，不因代码推送自动发布 Release。

离线检查：python3 build-system/ci/test_versioning.py、python3 build-system/ci/test_release.py。
