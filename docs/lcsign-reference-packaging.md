# Regram LCSign 参考包兼容打包规范

本项目以后需要制作可覆盖安装、由 LCSign 识别为“未签名”的真机 IPA 时，统一按本文操作。

## 固定标准

签名与容器配置参考包：

```text
/Users/yuki/Library/Mobile Documents/com~apple~CloudDocs/Regram-12.9.2-b34551.ipa
```

b34557 打包时，原始 b34551 已不在上述路径。本轮直接对照的是用户移动后的 b34556：

```text
/Users/yuki/Library/Mobile Documents/com~apple~CloudDocs/Regram-12.9.2-b34556.ipa
SHA-256: 6ec9f881f45d7f0234e53bfd90a86a2d73f5084ffe09d44b9df3f9e06797c119
```

该 SHA 与上一轮已经直接同 b34551 完整比对通过的 b34556 交付包一致，因此 b34557 使用的是链式已验证基准，不能表述为本轮直接读取并比对了 b34551。

必须保持以下配置：

- 主程序 Bundle ID：`app.swiftgram.ios`
- 数据容器权限：`group.app.swiftgram.ios`
- Telegram 数据目录：App Group 容器中的 `telegram-data`
- 扩展数量：6 个，不能为了生成“未签名”包而禁用扩展
- 最终 IPA：不包含任何 `embedded.mobileprovision`
- 所有 Mach-O：保留 `LC_CODE_SIGNATURE`，使用 ad-hoc 签名，不包含证书 Authority 和 TeamIdentifier
- 架构：iPhoneOS arm64

这里的数据仍然位于 iOS 沙盒中，但属于由 entitlement 授权的 App Group 沙盒。系统会决定 App Group 容器的实际绝对路径，代码只应通过 `containerURL(forSecurityApplicationGroupIdentifier:)` 获取容器，再追加 `telegram-data`，不能写死文件系统路径。

“LCSign 显示未签名”在这里表示没有开发者/发布证书身份和描述文件，但 Mach-O 仍有 ad-hoc 代码签名。不要使用 `codesign --remove-signature`；彻底删除代码签名会破坏真机安装所需的包结构。

## 正式构建

在仓库根目录运行。每次只递增 `regram_build`，其余开关保持不变：

```sh
regram_build=34555

build-input/bazel-8.4.2-darwin-arm64 build //Telegram:Regram \
  --ios_signing_cert_name=- \
  --define=buildNumber="$regram_build" \
  -c opt \
  --ios_multi_cpus=arm64 \
  --watchos_cpus=armv7k,arm64_32 \
  --features=swift.use_global_module_cache \
  --features=swift.opt_uses_wmo \
  --features=swift.opt_uses_osize \
  --features=dead_strip \
  --objc_enable_binary_stripping \
  --verbose_failures \
  --remote_cache_async \
  --//Telegram:disableExtensions=false \
  --//Regram/RGAppGroupIdentifier:sandboxOnly=false
```

构建输出：

```text
bazel-bin/Telegram/Regram.ipa
```

两个布尔开关必须显式写出，防止沿用终端或旧命令中的错误配置：

- `disableExtensions=false`：保留全部 6 个扩展。
- `sandboxOnly=false`：使用 `group.app.swiftgram.ios/telegram-data`，保证与参考包的数据容器一致。

不要使用 `--//Telegram:disableProvisioningProfiles` 生成真机目标；当前构建规则在设备构建阶段需要描述文件。正确做法是在 Bazel 完成 IPA 后，只从临时副本中移除描述文件，再逐个 ad-hoc 重签。

## 去描述文件并 ad-hoc 重签

下面的脚本只修改临时解包目录，不修改 Bazel 原始产物。设置新的构建号和输出路径后运行：

```sh
regram_build=34555
artifact_dir="$PWD/build/artifacts-lcsign-reference-$regram_build"
final_ipa="$artifact_dir/Regram-12.9.2-b${regram_build}-LCSign-reference-compatible.ipa"

test ! -e "$final_ipa"
mkdir -p "$artifact_dir"

package_root=$(mktemp -d "/tmp/regram-lcsign-${regram_build}.XXXXXX")
unzip -q bazel-bin/Telegram/Regram.ipa -d "$package_root"
app_path=$(find "$package_root/Payload" -mindepth 1 -maxdepth 1 \
  -type d -name '*.app' -print -quit)
test -n "$app_path"

find "$app_path" -type f -name embedded.mobileprovision -delete

while IFS= read -r appex_path; do
  codesign --force --sign - \
    --preserve-metadata=identifier,entitlements,flags \
    "$appex_path"
done < <(find "$app_path/PlugIns" -depth -type d -name '*.appex' -print)

codesign --force --sign - \
  --preserve-metadata=identifier,entitlements,flags \
  "$app_path"

codesign --verify --deep --strict --verbose=2 "$app_path"

(
  cd "$package_root"
  zip -qry "$final_ipa" Payload
)
```

重签顺序不能改变：先逐个扩展，最后主 App。`--deep` 只用于最终验证，不用于重签。

## 必须完成的校验

所有校验都要针对最终 IPA 的一次全新解包，不能只检查打包前的临时目录。

```sh
verify_root=$(mktemp -d "/tmp/regram-verify-${regram_build}.XXXXXX")
unzip -tq "$final_ipa"
unzip -q "$final_ipa" -d "$verify_root"
app_path=$(find "$verify_root/Payload" -mindepth 1 -maxdepth 1 \
  -type d -name '*.app' -print -quit)

codesign --verify --deep --strict --verbose=2 "$app_path"
find "$app_path/PlugIns" -mindepth 1 -maxdepth 1 -type d -name '*.appex' | wc -l
find "$app_path" -type f -name embedded.mobileprovision | wc -l
main_executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app_path/Info.plist")
test -x "$app_path/$main_executable"
find "$app_path" -type l -exec sh -c \
  'for path do printf "%s -> %s\n" "$path" "$(readlink "$path")"; done' sh {} +
codesign -d --entitlements :- "$app_path" 2>/dev/null
codesign -dvvv "$app_path" 2>&1
shasum -a 256 "$final_ipa"
```

验收值：

- `CFBundleIdentifier` 为 `app.swiftgram.ios`
- `CFBundleVersion` 等于本次 `regram_build`
- 扩展数量为 6
- `embedded.mobileprovision` 数量为 0
- 主 App entitlement 包含：
  - `application-identifier = RGRM000000.app.swiftgram.ios`
  - `com.apple.security.application-groups = [group.app.swiftgram.ios]`
  - `aps-environment = production`
- 主 App 和 6 个扩展的 Bundle ID、entitlements 应逐项与 b34551 参考包一致
- 每个 Mach-O 的 `codesign -dvvv` 输出都应包含 `Signature=adhoc` 和 `TeamIdentifier=not set`，且不得出现 `Authority=`
- 全部 Mach-O 都应保留可执行权限；符号链接的路径和目标应与参考包一致
- 主程序应为 `Mach-O 64-bit executable arm64`，最低系统版本为 iOS 13.0

## 覆盖安装验收

1. 不要卸载旧版本，直接覆盖安装。
2. LCSign/安装工具不能改写 Bundle ID、App Group 或 application-identifier。
3. 安装后启动 Regram，确认原账号仍登录、聊天数据库可读。
4. 完全退出并再次启动，确认登录态仍保留。
5. 再测试分享扩展、通知扩展和 Widget 是否可启动。

静态校验只能证明新旧包声明了相同的数据容器权限。设备上的最终容器访问仍由 iOS 和实际安装方式决定，所以每次发布前必须做一次真实覆盖安装测试。

## 禁止事项

- 不得把 `sandboxOnly` 设为 `true`。这会改用主 App 私有 `Library/Application Support/Regram/telegram-data`，无法读取参考包的原登录数据。
- 不得把 `disableExtensions` 设为 `true`。
- 不得改变 `app.swiftgram.ios` 或 `group.app.swiftgram.ios`。
- 不得先卸载再安装，否则 iOS 可能删除旧容器。
- b34554 私有沙盒包不适用于复用 b34551 数据的本打包流程，不能作为该流程的覆盖升级包发布。
- 不得用 `codesign --remove-signature` 或 `codesign --deep --force` 重签整棵 bundle。

## 当前交付产物

```text
build/artifacts-lcsign-reference-34559/Regram-12.9.2-b34559-LCSign-reference-compatible.ipa
SHA-256: 5bd8640c22aaf38744a415ec7bef4fb281f37c415e830bf0642c23ec8275263a
```

b34559 使用 Xcode 26.6 和 iOS 26.5 SDK 构建。最终 IPA 已全新解包验证：6 个扩展、0 个描述文件、13 个 ad-hoc 签名的 Mach-O；主程序及扩展的 Bundle ID 和 entitlements 与 b34558 一致。
