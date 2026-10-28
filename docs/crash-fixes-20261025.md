# b34637：启动与网络崩溃修复（2026-10-25）

本轮基于 `fb098e9c583c6cea6560ec8e8f8790e7be95affc` 完成源码修复，并按用户后续授权构建及发布 **13.1.1 / b34637**。三份用户日志均来自 13.1.1 / b34636；使用 b34636 留存的匹配 dSYM 定位，日志及符号文件仅保存在本机忽略目录。

## 网络连接清理

09:43 的日志在 iOS 27.0.1 的 `shared_tcpConnWorkQueue` 上终止，调用链为 `SocketStream::~SocketStream → CFSocketInvalidate → SocketStream::~SocketStream → CFSocketInvalidate → _os_unfair_lock_recursive_abort`。

普通 MTProto TCP 已通过 dispatch source 处理读写、EOF 和错误，但旧版 GCDAsyncSocket 仍为每条连接额外创建、打开 CFStream 观察流。大量连接清理可使 CFNetwork 的流析构再次进入持有全局锁的 `CFSocketInvalidate`。上游也有[同类问题报告](https://github.com/TelegramMessenger/Telegram-iOS/issues/2306)；[Apple 已废弃旧 VoIP stream 服务类型](https://developer.apple.com/documentation/cfnetwork/kcfstreamnetworkservicetypevoip)。

修正包括：

- iOS 9 起不再自动创建和打开这些观察流；Regram 支持的系统使用原有 dispatch TCP 路径。显式流访问和 CFStream TLS 仍保留各自的创建路径。
- 显式流的清理先断开字段、移除双方回调，保留整对流直到双方关闭，再释放各自的 Create-rule 引用；创建失败也使用同一清理方法。

检查中发现只调整成对关闭／释放顺序仍不足以避免问题：该中间实现曾在 iOS 26.5 模拟器的真实并发 loopback 连接中复现同一递归锁崩溃。因此最终修正同时移除了普通 TCP 的自动观察流。

## 启动时读取归档状态

04:25 与 07:33 的两份日志来自 iOS 18.7.8，故障线程均为 Postbox。两个故障栈的应用模块 UUID 和相对地址一致，符号化后的关键路径为：

```text
replayFinalState
  → rgResolveChatListGroup
  → rgPlacementState
  → RGChatPlacementState.init(from:)
  → Dictionary.init(from:)
  → _AdaptedPostboxDecoder.KeyedContainer.allKeys
  → preconditionFailure
```

`RGChatPlacementState.entries` 保存为 `[String: Entry]`。Postbox 适配解码器的 `allKeys` 原先直接触发断言，读取已保存的状态便会崩溃，空字典也受影响。

补齐二进制字段名枚举和 `allKeys`，复用现有值跳过逻辑，并检查键长度、UTF-8、值类型和缓冲区边界。枚举使用独立游标，不改变后续字段读取位置。旧状态的键名、二进制格式、归档位置、修订号和待确认标记均保持兼容。

原有归档回归夹具用 JSON 替代了真实存储，未覆盖这个缺口。本轮改为编译生产 `Coding.swift`、全部编码适配器和 `PreferencesEntry`，只隔离事务及存储接口。

## 检查与边界

- 原始网络源码在流生命周期检查中失败；最终源码通过 133 项生命周期场景，包括成对引用、部分创建失败、重复／错误清理及并发实例。
- 最终源码通过 iOS 26.5 模拟器上的 192 次真实 IPv4／IPv6 loopback 连接：回显、远端关闭、连接回调中取消及读取超时；确认普通 TCP 没有创建 CFStream 观察流，断开回调恰好一次。
- 原始 Postbox 解码器在真实二进制归档回归中触发 `SIGTRAP`；最终源码通过 32 项检查，包括旧状态重开、账号隔离、归档确认、64 位键、空／嵌套／整数键字典及键枚举边界。
- 生产 GCDAsyncSocket 已使用 Xcode 27.1 编译为 arm64 iOS 对象（`-O2 -Werror`）；生产 Postbox 编解码器及 PreferencesEntry 已通过 arm64 iOS 模块编译（`-warnings-as-errors`）。
- 现有代理连接、DNS 策略／报文及消息保留回归通过。

本轮已完成完整 `//Telegram:Regram` arm64 Release 构建与正式发布，交付信息见下节。未在真机或真实账号执行覆盖升级、VPN／飞行模式和冷启动验收；模拟器压力测试不能替代原设备验收。没有修改安装身份或清除任何账号、数据库、设置及可复用构建缓存。

复验入口：

```sh
# 先选择完整 Xcode，并准备一个已启动的 iOS 模拟器。
python3 submodules/MtProtoKit/Tests/run-cfstream-checks.py --simulator <SIMULATOR_UUID>
python3 Regram/RGChatListPlacement/Tests/run-placement-checks.py
python3 submodules/MtProtoKit/Tests/run-proxy-connection-checks.py
python3 submodules/MtProtoKit/Tests/run-dns-policy-checks.py
python3 build-system/check-regram-retention.py
```

## b34637 构建与正式发布

2026-10-25 发布 [v13.1.1-b34637](https://github.com/RegramDev/Regram-ios/releases/tag/v13.1.1-b34637)，Release ID 为 `423108434`，稳定版、非草稿并已设为 Latest。

- 构建源码及正式 tag 的目标提交：`613a41cb8e8e9aaa314fd885d15ad4021155dbaf`。后续发布记录提交仅修改文档，不代表另一份应用构建。
- Xcode 27.1（27A9275）完成 `//Telegram:Regram` 的完整 arm64 Release，退出码 0，构建前后源码与配置摘要一致。
- 70 项现有功能检查通过，前述专项回归的源码摘要与构建源码一致。
- 主程序及六扩展、严格 ad-hoc 签名、arm64、资源、三语文案及 12 份匹配 dSYM 校验通过；七个 bundle 的完整 entitlements 与已发布 b34636 一致。
- 文件：`Regram-13.1.1-b34637.ipa`，77,969,678 字节。
- SHA-256：`b00e3e523b986c65db534124905db02bdffbb6b8a4fca2f743d8b1dbedba10eb`。
- 草稿与公开附件均为唯一 IPA 及其 SHA-256 文件。公开完整下载的大小、摘要和校验附件一致；实际公开及 Latest JSON 通过生产更新解析，b34636 可识别本次更新。
- 匹配调试符号保存在本机；可复用构建缓存保留，闲置 Bazel 服务已关闭。

本轮构建日志、包与符号、manifest、源码摘要及发布核验记录保存在忽略的 `build-input/crash-fixes-release-34637/`。
