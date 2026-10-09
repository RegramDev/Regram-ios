# 构建子模块补丁

本仓库通过 Git submodule 固定 Bazel 规则版本。**rules_apple-local.patch** 是当前工具链兼容补丁，作为普通文件提交在主仓库中；单纯运行 git submodule update 不会自动应用它。

克隆仓库并初始化 submodule 后，在仓库根目录检查并应用：

~~~sh
git -C build-system/bazel-rules/rules_apple apply --check ../../patches/rules_apple-local.patch
git -C build-system/bazel-rules/rules_apple apply ../../patches/rules_apple-local.patch
~~~

补丁主要处理以本机 Xcode 路径指定工具链时，Bazel 对 Xcode 版本的比较和资源处理。它只修改已检出的 rules_apple 工作树，不改变主仓库记录的 submodule 提交。应用后 submodule 显示为有本地改动是预期结果；不要把这些改动误当作需要更新的 submodule 指针。

Telegram 13.0 使用的 rules_apple 提交为 `485016eb5b0948cc17307064e7977a6d68e94046`。当前补丁已适配该版本，只修改 AppIntents aspect 和 actool；新的 metadata bundle 实现已不需要旧补丁中的版本比较修复。

如果第一条检查失败，先用 **git -C build-system/bazel-rules/rules_apple status --short** 查看补丁是否已经应用，或当前 submodule 版本是否已经包含对应修复。维护者更新补丁时，应从目标 submodule 的已知提交重新生成并测试，随后更新本文件和主仓库中的补丁。长期方案是将修复提交到可追踪的 rules_apple fork，再更新 .gitmodules 指向。
