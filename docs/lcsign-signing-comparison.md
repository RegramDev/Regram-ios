# LCSign 1.4-1 签名流程与 Regram 更新对照

本次针对用户提供的 LCSign 1.4-1 IPA 做静态分析。主程序为 `LoadController`，Bundle ID 为 `com.huami.LoadController`，版本为 1.4／1。复用的分析二进制与本次提供的 IPA 内主程序一致。本次未运行 LCSign、未使用其签名材料，也未上传用户的证书或描述文件。

## 已确认的本地签名流程

1. `CertificateStore.importProvision` 将描述文件与已导入的证书关联。界面错误明确指出以描述文件的 `DeveloperCertificates` 匹配 P12；证书条目持有多个 `SigningProvisionProfile`，可分别选择和删除。其合并及去重行为也有对应界面文字和日志常量。
2. `IPASigner.sign` 支持一份及多份描述文件，并调用 `lc_zsign_sign_ipa`、`lc_zsign_sign_ipa_multi` 或 `lc_zsign_sign_ipa_multi_with_entitlements`。桥接层调用嵌入的修改版 zsign。
3. `ZBundle::SignAssetForBundleId` 在只有一份签名材料时直接复用该材料；多份时按应用标识匹配。匹配评分函数优先精确匹配，再按通配符前缀长度选择更具体的规则。不需要机械地为每个扩展提供一份独立文件；同一份通配符文件可以用于多个 Bundle。
4. `ZSignAsset::Init` 解析描述文件的 `TeamIdentifier`、`Entitlements` 和 `application-identifier`。没有自定义权限文件时，将描述文件里的 `Entitlements` 序列化为签名权限；有自定义权限文件时使用该文件。该默认分支由二进制中的条件跳转和 `jvalue::style_write_plist` 调用确认。
5. 重新签名后，普通安装可以经本机 IPA 下载通道和 HTTPS 安装清单交给 iOS 安装器。最终描述文件、证书及权限是否允许安装，由设备系统检查。

## 与 Regram 的差异

| 项目 | LCSign 1.4-1 | Regram b34595 |
| --- | --- | --- |
| 描述文件存储 | 多份文件归属同一证书，支持合并和去重 | 再次导入会覆盖此前导入的文件 |
| 一份文件签多个 Bundle | 单份材料复用；多份按标识匹配 | 已会搜索导入和安装包内的文件，但要求满足全部旧权限 |
| 默认权限来源 | 描述文件；另有自定义权限文件入口 | 当前安装版的签名权限 |
| 匹配前置检查 | 与证书关联、按 Bundle ID 选择签名材料 | 逐个 Bundle 检查旧权限是否被描述文件允许 |
| 通配符／允许值列表 | 交给修改版 zsign 处理描述文件与目标标识 | `"*"` 及标量对允许值列表的匹配存在缺陷 |
| 失败提示 | 分步骤错误信息 | 多种原因统一显示为缺少匹配且未过期的描述文件 |

因此，Regram 的这一提示不能单独证明描述文件过期或未导入。还可能是之前导入的文件被覆盖、通配符或允许值列表误判、应用标识不匹配，或者旧签名中确有某个权限不在描述文件里。没有目标设备的具体诊断，无法确认最后一种情况对应哪个权限。

## LCSign 自身更新与普通 IPA 签名的区别

IPA 中还存在 `OTAClient.signAndHost`，参数包括 P12 数据、密码、描述文件、目标标识和 LCSign 发布文件名；其请求为 `/ota/sign-and-host`。这是另一路涉及服务端签名的流程。不能把它直接等同于接受任意 Regram GitHub IPA 的通用签名接口。

Regram 当前实现使用本机 zsign 签名，再调用 `/ota/manifest` 创建 HTTPS 安装清单，提交的是应用信息和回环下载地址。把它切换到远程签名会改变证书和密码的数据流，不能仅通过替换一个安装 URL 完成。

## 对此次修复的影响

已提交的 b34596 修改修复描述文件覆盖、`"*"` 和标量／列表匹配，增加下载前检查以及 Bundle／权限项诊断。合成检查已经验证一份通配符描述文件签名主应用和六个扩展，且保留各目标身份及权限。下载任务也改用进度委托回调，显示百分比和下载大小。

用户进一步确认使用快捷安装：导入证书后直接点击“签名并安装”，不手动选择描述文件。截图显示 LCSign 已为证书绑定一份描述文件。Regram 因此补充在导入 P12 时自动提取并保存当前安装版中包含同一证书的未过期描述文件；页面显示保存数量。签名时按实际 Bundle ID 选择目标，保留已安装签名中的 `application-identifier`，不使用后缀假设阻止更新。

后续签名策略应保持现有应用标识、App Group 和钥匙串访问组，才能验证覆盖更新后的账号与证书保留。直接采用描述文件的默认权限，并不能保证与当前安装版的数据容器一致；应在明确失败项后调整，不能用删除所有旧权限的方式代替匹配。

此前已启动的构建在研究阶段暂停时已结束，但其间源码仍有修改，该产物没有打包交付。后续交付安排为：本地 b34596 供 LCSign 覆盖安装，GitHub b34597 供应用内更新测试；两版使用相同修复代码。

## 静态证据位置

以下地址属于本次 IPA 的主程序，只用于复查该版本：

- `CertificateStore.importProvision`：`0x1007c3828`。
- `IPASigner.sign(... provisionURLs ...)`：`0x100831090`，对原生签名入口的调用见 `0x100835cc0` 等分支。
- `lc_zsign_sign_ipa_multi_with_entitlements`：`0x1009f37d8`。
- `ZBundle::SignAssetForBundleId`：`0x1009fec64`；单份复用分支 `0x1009fec98`。
- Bundle ID 匹配评分：`0x100a063f0`，精确匹配评分与尾部 `*` 匹配分别有独立分支。
- `ZSignAsset::Init`：`0x100a1ea90`；默认从描述文件生成权限的分支 `0x100a1ed34`–`0x100a1ed60`。

后续针对重复下载与没有系统安装提示的问题，进一步对照了 `IPAInstaller.itmsServicesURL(forManifestAt:)`（`0x100932314`）及 `ManifestBuilder.itmsServicesURL(for:)`（`0x100932a6c`）。后者设置 `itms-services` scheme 后还设置空 host，生成 `itms-services://?…`；Regram 原先只设置 scheme，主机复现为 `itms-services:?…`。LCSign 的 `InstallActionTracker` 还区分交出链接和观察到用户／安装器动作，公开状态接口有 `fetched`／`fetched_at` 字段。Regram 改为由本机 IPA 服务的实际 GET 请求确认系统开始读取，避免把打开链接的回调当作安装完成。

LCSign 的工作区和 `QuickInstallBatchSnapshot.sourcePath` 将签名产物作为磁盘文件引用；Regram 原先在初始化时删除更新目录并只用内存保存签名包路径，因此进程重新启动后无法复用。新的缓存独立保存已校验下载包和签名产物、发布元数据及签名身份指纹，恢复时验证大小与 SHA-256，并保留未签名原包供重试。

符号、反汇编及分析辅助文件保留在被 Git 忽略的本地工作目录。静态分析不能代替真实证书在 iOS 上的覆盖安装验证。
