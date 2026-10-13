# Regram 自动更新与 LCSign 安装

入口：**Regram 设置 → 其他 → Regram 更新**。更新源固定为 [RegramDev/Regram-ios 的 GitHub Releases](https://github.com/RegramDev/Regram-ios/releases)。读取最新正式发布，比较版本号及构建号；不会安装更旧的版本，也不会选择草稿、预发布或名称不匹配的 IPA。

## 安装流程

1. 首次使用时，导入 LCSign 安装当前 Regram 所用的同一份 P12，并填写密码。自动提取当前安装版中未过期、包含该证书的描述文件，去重后保存在本机钥匙串，页面显示已保存数量。已有描述文件自动复用；如已过期，可导入主应用和扩展对应的新描述文件。多次导入会合并保存并去重，保留之前导入的文件；每次最多选择 16 份，总计最多保存 64 份。导入时检查文件是否可读取及是否已过期。
2. 下载前检查证书与所有已安装应用、扩展的描述文件匹配情况。同一通配符描述文件可以复用于它允许的多个 Bundle ID。匹配失败时区分缺失、读取失败、过期、证书、应用标识及权限问题，显示对应应用或扩展和不匹配的权限名称。不会在匹配失败后继续下载 IPA。
3. 下载 Release 的 IPA，校验 GitHub 提供的 SHA-256、文件大小及包内版本。发布资产需要提供 `digest: sha256:...`；缺少校验值的发布不会用于自动更新。使用 URLSession 下载任务的委托回调更新线性进度条，同时显示百分比和已下载／总大小；校验证书、签名及准备安装显示等待指示。校验后的下载包与签名包分别保存在不参与系统备份的 Application Support 目录；重新启动时校验并恢复。签名失败、取消或更换签名材料时保留原始下载包，界面提供“签名已下载的更新”。发布说明修改不会使缓存失效；目标资产改变或更新已安装后清理旧缓存。
4. 使用嵌入的开源 [zsign](https://github.com/zhlynn/zsign) 在手机上签名。证书必须与当前主应用及扩展一致，保留安装后的 Bundle ID、URL Scheme、App Group、钥匙串权限及全部已安装扩展；结构不匹配或缺少合适描述文件时停止。权限允许值按描述文件的标量、列表及通配符规则匹配，参考 [Apple TN2415](https://developer.apple.com/library/archive/technotes/tn2415/_index.html)。

   Bundle ID 与签名中的 `application-identifier` 分开保存：更新按实际 Bundle ID 定位每个主应用／扩展的签名材料，保留当前安装版的实际 `application-identifier`，再与描述文件匹配，不通过字符串后缀猜测二者关系。合成检查覆盖两者不同的情形，但这不代表任意新安装包可以跳过 iOS 的安装资格校验。
5. 点击安装时，启动只绑定 `127.0.0.1` 的临时下载通道，为本机 iOS 安装器提供 IPA，支持 HEAD 和 Range 请求。
6. 读取 [LCSign 安装节点列表](https://support.lcsignx.com/install/services)，调用选中节点的 `POST /ota/manifest`，仅提交应用标识、构建号、标题及临时本机下载地址。取得令牌后在**同一节点**构造 `/ota/m/{token}` 地址并核对清单。节点不可用时尝试下一个节点。
7. 按 LCSign 的格式，以 `itms-services://?action=download-manifest&url=...` 打开 iOS 安装提示。URLComponents 必须同时设置 scheme 和空 host，避免生成 `itms-services:?…`。打开链接只表示系统接收了请求；本机服务收到针对 IPA 的实际 GET 请求后显示系统正在读取更新包，HEAD 检查不计作安装开始。三十秒未收到 IPA 请求时提示重试，保留签名包；通道结束或系统拒绝链接时显示对应状态。新版启动后的构建号才可确认安装结果。

不需要自建服务器或 LCSign 存取码。证书私钥和密码保存在本机 Keychain，禁用同步，未加入设置备份。IPA、证书和密码均不上传给 LCSign。临时签名材料操作结束后删除；已校验的更新文件跨重启保留，缓存元数据只记录发布信息、文件校验值及签名身份指纹，不记录 P12 或密码。签名缓存绑定当前证书、描述文件、应用标识和安装构建号；安装前再次检查证书与描述文件有效性。

自动检查默认在证书安装版启用，启动及回到前台时检查，每六小时最多一次。自动下载及签名默认关闭，导入证书后可以开启。安装由用户发起并确认系统提示。安装通道使用系统允许的有限后台时间，最长保留五分钟；期限结束、取消或进程退出后关闭，可回到更新页重试。

## LCSign 参考证据

参考 LCSign 1.4-1 IPA 的静态接口分析，并验证公开服务的节点列表、`POST /ota/manifest`、`GET /ota/m/{token}`。服务测试仅使用虚构标识和不存在的回环 IPA 地址。

接口的 `manifest_url` 可能指向 `support.lcsignx.com`，实测该地址返回 404，而创建令牌的 CF 节点返回正确清单；客户端按 LCSign 自身的做法，在实际节点上构造地址。

`loadcontroller://import` 只负责下载和导入，不能代替自动签名安装。`/ota/sign-and-host` 签名服务端 LCSign 底包；Regram 使用本地签名和清单接口。

zsign 修订及适配见 [UPSTREAM.md](../Regram/RGUpdateSigner/Vendor/zsign/UPSTREAM.md)，MIT 许可随资源打包。不使用 LCSign 内置证书、私钥或私有安装 API。

## 验证边界

主机检查覆盖版本比较、发布来源和校验值、清单的应用/构建/下载地址，以及回环服务完整下载、并发、HEAD、Range 和错误路由。彩色二维码另有离线渲染和解码检查。

下载进度回归入口为 `Regram/RGAppUpdate/Tests/run-download-progress-checks.py`，用本机限速 HTTP 服务检查中间进度、无 Content-Length 的下载、大小限制、错误状态、重定向和取消。签名合成检查同时覆盖一份通配符描述文件匹配主应用及六个扩展、标量与允许值列表匹配，以及每类失败原因。真实证书与设备上的具体失败原因仍以更新页显示的诊断为准。

缓存检查为 `Regram/RGAppUpdate/Tests/UpdateCacheTests.swift`，覆盖新进程对象恢复下载与签名、临时无法读取钥匙串、签名身份变化时保留下载、发布说明修改、文件损坏、不完整文件及已安装版本清理。安装 URL 检查要求完整的 `itms-services://?` 形式；本机服务检查同时验证 GET 只上报一次安装开始、HEAD 不误报，以及文件大小、并发和 Range 行为。

这些检查不代表真机完成了覆盖安装。证书信任、设备准入、iOS 安装确认、后台期限和数据保留，需要在实际证书安装的设备上验证。二维码登录也需要真实 Telegram 网络验证令牌导出、扫码接受、跨 DC 和二步验证；图片解码通过不等于登录成功。

b34591 的构建检查记录（后续发现并修复了加密符号冲突，见下文）：b34591 已通过 `//Telegram:Regram` arm64 Release 完整构建；参考 IPA 保留六个扩展，与 b34590 的标识及权限一致，附有匹配的 dSYM。七个合成签名目标的 CodeDirectory 页哈希、Info.plist／资源／权限槽及 CMS 校验通过。合成 CA 不具备 Apple 签名信任，不能作为真机安装准入验证；本轮没有连接真机。

可复现的签名检查为 `Regram/RGUpdateSigner/Tests/check_signer.py`，需要完整 Xcode 和通过 pkg-config 提供的 OpenSSL。它仅生成临时合成密钥，在被忽略的 `build-input/update-signer-checks/` 中运行，不读取正式证书。版本／清单和本机下载检查位于 `Regram/RGAppUpdate/Tests/`。


## b34591 连接阶段闪退与修复

用户提供的 b34591 闪退日志与对应 dSYM 的 UUID 匹配。崩溃链路为 `MTCreateSafariClientHello → get_y2 → MTBignumContextImpl.modAddInto → BN_mod_add → BN_div`，异常是 `EXC_BAD_ACCESS`。新增签名库使用 OpenSSL 1.1.1d，而 Telegram 网络的 `OpenSSLEncryptionProvider` 实际使用 BoringSSL；将两个未隔离的静态库链接进同一个 TelegramUIFramework，会将同名 BN 函数混用。两者的大整数及上下文 ABI 不兼容，因此即使不进入更新页面也会在建立连接时闪退。

修复将签名用的 OpenSSL 放进 `Regram/RGUpdateOpenSSL/`，所有全局符号增加 `RGUpdateSSL_` 前缀，头文件使用独立路径。构建保留 OpenSSL 原有的预处理逻辑，随后统一重命名对象中的定义和引用，避免函数名条件编译或宏拼接造成缺失定义，并检查没有未加前缀的加密导出。Telegram 的 BoringSSL 接口保留原符号。

回归检查 `CryptoCoexistenceTests` 在同一程序内连接实际网络加密提供器和更新签名模块，执行一万轮两套大整数运算，以及一千组完整位数的连接握手曲线多项式，并检查结果、摘要及签名入口。完整合成证书签名检查也使用隔离后的库。b34591 已生成的 IPA 保留作为问题版本参考，新修复包使用 b34592。

b34592 的并存回归、隔离库的七个合成目标签名检查及 arm64 Release 完整构建均已通过。最终二进制内的原始 `BN_div`／`BN_mod_add` 和 `RGUpdateSSL_BN_div`／`RGUpdateSSL_BN_mod_add` 各自具有独立地址；网络函数由 BoringSSL 提供。参考包保留六个扩展，十二个 arm64 Mach-O 的 ad-hoc 签名及对应 dSYM 校验通过，安装标识和权限与 b34591 一致。本轮尚未在真机验证运行和覆盖安装。
