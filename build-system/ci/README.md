# Regram CI 构建与发布

应用版本和构建号统一在根目录 `versions.json` 的 `app` 与 `build` 字段声明。当前为 `13.0`、`34588`。开始新的安装包版本时先递增 `build`；单纯重跑工作流或修改文档不会改变构建号。

Actions 和 `build.sh` 都通过 `versioning.py` 读取构建号。若环境中残留了与声明不同的 `REGRAM_BUILD_NUMBER`，构建会在读取凭据、下载工具或编译前失败。构建号不再依赖 `GITHUB_RUN_NUMBER` 或 Git 提交数量。

本地使用 Make 驱动构建时，将以下命令的输出作为 `--buildNumber` 参数，保证与 CI 使用同一数值：

```sh
python3 build-system/ci/versioning.py
```

分支推送和手动运行会构建，发布标签不会额外触发构建。输出为 `Regram-13.0-b34588.ipa` 这样的单个 IPA 文件。发布工作流仍需选择成功的 master 构建和具体 IPA，并明确确认发布；不会因推送自动创建 Release。

离线检查：

```sh
python3 build-system/ci/test_versioning.py
python3 build-system/ci/test_release.py
```
