# LCSign 兼容参考包

本文面向已经完成 Regram 真机 IPA 构建、需要交给第三方签名工具重新签名的维护者。它描述如何从 Bazel 原始产物生成**不包含 Apple 描述文件、保留 ad-hoc 代码签名**的 IPA，并检查升级所需的包声明。普通开发者请先阅读[构建说明](../README.md)。

这里的 ad-hoc 是 codesign 的无证书签名（Signature=adhoc），不是 Apple 的 Ad Hoc 分发证书。生成的参考包并不等于已经用开发者证书签好的可分发应用；真机安装仍取决于后续签名工具、相匹配的描述文件及设备信任状态。

## 构建前确认

1. 使用你自己的 Bundle ID、Telegram API 凭据和签名材料，按 README 构建 **//Telegram:Regram**。原始 IPA 位于 **bazel-bin/Telegram/Regram.ipa**。
2. 构建时保留主 App 和 6 个扩展。当前构建规则在真机目标上需要描述文件；不要为绕过配置而启用 **//Telegram:disableProvisioningProfiles** 或关闭扩展。
3. 如需覆盖安装并保留原账号，必须保持与旧包相同的 Bundle ID、App Group 和数据目录。当前默认构建设置 **//Regram/RGAppGroupIdentifier:sandboxOnly=false** 使用 App Group 中的 **telegram-data**；切换到私有沙盒会让旧数据不可见。
4. 准备一份已能正常使用的旧 IPA 作对照。它应来自相同应用身份和数据容器配置，不能拿其他 Bundle ID 的变体作升级基准。

本仓库不存放个人证书、描述文件、真实 API 凭据或已签名的发布包。

## 生成参考包

在仓库根目录运行以下命令。输出路径位于 Git 忽略的 **build/** 目录；如果该文件已存在，命令会中止，不会覆盖旧包。

~~~sh
set -e
raw_ipa="$PWD/bazel-bin/Telegram/Regram.ipa"
output_dir="$PWD/build/artifacts"
output_ipa="$output_dir/Regram-LCSign-reference.ipa"

test -f "$raw_ipa"
mkdir -p "$output_dir"
test ! -e "$output_ipa"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
unzip -q "$raw_ipa" -d "$work_dir"
app_path=$(find "$work_dir/Payload" -mindepth 1 -maxdepth 1 -type d -name '*.app' -print -quit)
test -n "$app_path"
test "$(find "$app_path/PlugIns" -mindepth 1 -maxdepth 1 -type d -name '*.appex' | wc -l | tr -d '[:space:]')" -eq 6

find "$app_path" -type f -name embedded.mobileprovision -delete

# 先签扩展，再签主 App。不要用 codesign --deep --force 重签整棵目录。
find "$app_path/PlugIns" -depth -type d -name '*.appex' -print | while IFS= read -r appex_path; do
  codesign --force --sign - \
    --preserve-metadata=identifier,entitlements,flags \
    "$appex_path"
done
codesign --force --sign - \
  --preserve-metadata=identifier,entitlements,flags \
  "$app_path"

codesign --verify --deep --strict "$app_path"
(cd "$work_dir" && zip -qry "$output_ipa" Payload)
shasum -a 256 "$output_ipa"
~~~

**不要使用 codesign --remove-signature。** 后续签名工具需要正常的 Mach-O 签名结构。打包只处理临时解包目录，不改动 Bazel 原始产物。

## 验收最终 IPA

必须对**最终 IPA 再次解包**检查，而不是只看打包前的工作目录。下面的命令检查归档、主 App、扩展、描述文件及代码签名；例子中的临时目录由命令单独创建。

~~~sh
output_ipa="$PWD/build/artifacts/Regram-LCSign-reference.ipa"
verify_dir=$(mktemp -d)
unzip -tq "$output_ipa"
unzip -q "$output_ipa" -d "$verify_dir"
verified_app=$(find "$verify_dir/Payload" -mindepth 1 -maxdepth 1 -type d -name '*.app' -print -quit)
test -n "$verified_app"

codesign --verify --deep --strict --verbose=2 "$verified_app"
find "$verified_app/PlugIns" -mindepth 1 -maxdepth 1 -type d -name '*.appex' | wc -l
find "$verified_app" -type f -name embedded.mobileprovision | wc -l
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$verified_app/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$verified_app/Info.plist"
codesign -d --entitlements :- "$verified_app"
codesign -dvvv "$verified_app" 2>&1
~~~

期望有 6 个扩展、0 个描述文件。主 App 和扩展的 Bundle ID、App Group、application-identifier、推送 entitlement 应与所选旧包逐项比对；主程序及扩展都应能通过 codesign 验证。代码签名详情应显示 **Signature=adhoc**、**TeamIdentifier=not set**，且不包含证书 Authority。主程序的架构和最低 iOS 版本也应与计划交付的设备一致。

验证完成后可删除自己创建的临时验收目录。记录最终 IPA 的 SHA-256、源码提交、Xcode/SDK 版本和所用旧包的标识，便于问题回溯；不要把这些机器上的 IPA 路径或个人签名信息写回本文。

## 覆盖安装检查

静态检查只能证明两个包声明了相同的数据容器权限。正式交付前，请在测试设备上**直接覆盖安装**旧版，检查登录状态、聊天数据库、通知、分享扩展、Widget，以及退出后再次启动。不要先卸载旧版：卸载可能删除旧数据容器。若升级需要改变 Bundle ID、Team ID 或 App Group，应把它当作独立的数据迁移，而不是普通覆盖安装。
