# b34636 崩溃修复（2026-10-25）

本轮是基于 `fb098e9c583c6cea6560ec8e8f8790e7be95affc` 的源码修复，未调整发行版本。三份用户日志均来自 13.1.1 / b34636；使用该版本留存的匹配 dSYM 定位，日志及符号文件仅保存在本机忽略目录。

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

本轮未构建完整 `//Telegram:Regram` IPA，未在真机或真实账号执行覆盖升级、VPN／飞行模式和冷启动验收，也未上传 Release。模拟器的压力测试不能替代原设备验收。没有修改安装身份或清除任何账号、数据库、设置及可复用构建缓存。

复验入口：

```sh
# 先选择完整 Xcode，并准备一个已启动的 iOS 模拟器。
python3 submodules/MtProtoKit/Tests/run-cfstream-checks.py --simulator <SIMULATOR_UUID>
python3 Regram/RGChatListPlacement/Tests/run-placement-checks.py
python3 submodules/MtProtoKit/Tests/run-proxy-connection-checks.py
python3 submodules/MtProtoKit/Tests/run-dns-policy-checks.py
python3 build-system/check-regram-retention.py
```
