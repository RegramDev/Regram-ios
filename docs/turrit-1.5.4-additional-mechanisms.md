# Turrit 1.5.4 补充机制调查

日期：2026-09-30。仍使用 Turrit 1.5.4（10382）样本，指纹见[全链路审计](turrit-1.5.4-full-chain-audit.md)。调查时对照 Regram b34576，分析二进制、源码和官方协议说明；用户随后授权接入已确认的画质偏好与额外滚动回调，见文末实施范围。没有进行账户操作或测速。

**新确认的是统一的视频画质偏好，以及额外的滚动方向回调。TCP Fast Open 和数据库 WAL 等底层能力两边已有相同实现，没有新增的服务端限额绕过证据。**“隐藏技术”不能只凭特殊名字、字段存在或观感下结论。

## 视频画质：统一偏好可影响比较结果

Turrit 增加了 `preferredVideoQualityOn`、`preferredVideoQuality` 和 `TRPreferredVideoQuality`，模式为 auto / max / min。

这次不只确认设置项，还恢复了选择逻辑：

1. `UniversalVideoContentNode.tr_getFixVideoQuality()` 读取开关和模式。
2. 开关关闭、模式无效或可用质量数量不超过一个时，返回自动。
3. max 模式遍历可用质量整数，选最大值；min 模式选最小值。
4. `UniversalVideoNode.tr_getFixVideoQuality()` 向实际 content node 转发。
5. 画廊回调取得该结果，再交给画质设置路径。另一个保存视频入口也读取同一设置，但保存路径的所有后续参数本轮未完整恢复。

这是此前报告没有覆盖的统一策略。b34576 已有[单播放器画质设置接口](../submodules/AccountContext/Sources/UniversalVideoNode.swift)，当时尚没有这套 Turrit 全局 auto / max / min 偏好的接口。

选择较低可用画质可能减少起播所需数据和解码负担，这是机制推断；没有证据证明用户比较时 Turrit 使用了 min 模式，更不能称为默认偷偷降低画质。本轮确认了画廊应用，尚不能将其推广为所有聊天内自动播放和视频信息流都按同一时序应用。

Telegram 本身支持视频的多画质/格式版本，服务器可以在 `alt_documents` 中提供这些版本。选择替代资源属于协议能力，不等于自建加速服务器。[官方视频画质说明](https://core.telegram.org/api/files#video-qualities)

还有一个容易误判的参数：`minimizedHLSQuality` 虽然名字包含 minimized，却不保证永远选最小版本。Turrit 的分支先寻找质量键 **不低于 600** 的项，再使用最小项作回退；我们的[对应代码](../submodules/TelegramUniversalVideoContent/Sources/HLSVideoContent.swift#L150)相同。不能用这个函数名证明它比我们拉取更小的视频。

| 框架 | 地址 | 内容 |
| --- | --- | --- |
| Core | `0x00973CCC` / `0x00973D28` | 全局画质开关和模式 getter |
| Core | `0x0096F218` | rawValue 映射，0/1/2 有效，其他为无效 |
| UI | `0x0322940C` | content node 读取偏好、检查可用质量数量并选择 |
| UI | `0x005D7D00` / `0x005D7D4C` | 最大 / 最小整数选择 helper |
| UI | `0x0322BCB4` | UniversalVideoNode 转发 |
| UI | `0x026C60B8`，调用点 `0x026C6148` / `0x026C6168` | 画廊回调读取固定画质并进入设置路径 |
| UI | `0x016520F4` / `0x016520FC` | 保存视频入口读取同一偏好 |
| UI | `0x02C43E04`，比较点 `0x02C43EBC` | HLS 质量键与 600 比较 |

## 滚动方向：增加了独立的通知通道

Turrit 的 `ListViewImpl` 保留原有 `generalScrollDirectionUpdated`，同时新增 `tr_generalScrollDirectionUpdated`。在已检查的滚动分支中：

- 累积滚动距离超过 **14** 后判断方向，阈值与我们的[原有代码](../submodules/Display/Source/ListView.swift#L1041)相同。
- 原有回调仅在方向改变时调用。
- 新回调放在方向相同比较分支之后，因此超过阈值后，即使方向未变，也可以收到这一轮方向通知。
- 会话列表构造读取并替换该额外回调；尚未完整恢复它下游全部用途。

这说明它扩展了通知方式，但不能直接称为新的滚动渲染引擎、提前加载聊天，或保证更快的预取。我们[聊天历史的方向处理](../submodules/TelegramUI/Sources/ChatHistoryListNode.swift#L1123)已有按 up/down 切换预取候选的逻辑。

另有 `ListViewScroller.turritLastContentOffsetY` 和其他滚动代理对它的读取。字段本身只证明记录了位置；本轮未将这些额外代理的用途和性能效果完整恢复，因此不把它计入已证实的加速机制。

证据：UI `0x03513CC8`，14 的比较位于 `0x03513DAC`；原回调在 `0x03513E04`，额外回调在 `0x03513E2C`；会话列表注册位置 `0x01616E38`。这些位置与已有普通方向回调要分别辨认。

## 连接层：Fast Open、keepalive 与 noDelay 是共有配置

已从 Turrit 的 Network.framework TCP connect 函数恢复参数，并对照我们的[同一接口](../submodules/TelegramCore/Sources/Network/NetworkFrameworkTcpConnectionInterface.swift#L82)：

| 参数 | Turrit | Regram |
| --- | --- | --- |
| `noDelay` | true | true |
| `enableKeepalive` | true | true |
| `keepaliveIdle` | 5 | 5 |
| `keepaliveCount` | 2 | 2 |
| `keepaliveInterval` | 5 | 5 |
| `enableFastOpen` | true | true |

Apple 将 `enableFastOpen` 定义为启用 TCP Fast Open；它是系统网络栈提供的连接选项。[Apple 文档](https://developer.apple.com/documentation/network/nwprotocoltcp/options/enablefastopen)

配置存在与某次连接实际使用不同。我们的[接口选择](../submodules/TelegramCore/Sources/Network/Network.swift#L517)受网络设置、beta 开关及系统版本约束；Turrit 的对应运行时选择和用户实际设置本轮尚未完全恢复，不能说两边所有连接都走这条路径，也不能说 Turrit 默认打开而我们默认关闭。

检查到的这一 connect 路径未发现 multipath 设置调用。这仅是该路径的负向结果，不能证明整个程序或系统底层不可能使用其他传输方式。

证据：Core `0x001B3CFC` 的 connect 实现；上述 setter 的调用点为 `0x001B3EA4` 至 `0x001B3ECC`。

## 数据库：初始化配置相同

本轮接入 PostboxFramework 的 Mach-O 分析，从字符串引用追到数据库初始化的 `Database.execute` 调用，避免只凭字符串存在判断：

| PRAGMA | Turrit 已确认 | Regram |
| --- | --- | --- |
| `mmap_size` | 0 | 0 |
| `synchronous` | NORMAL | NORMAL |
| `temp_store` | MEMORY | MEMORY |
| `journal_mode` | WAL | WAL |
| `cache_size` | 特定分支为 32 | 特定分支为 32 |

Regram 对照：[SqliteValueBox 初始化](../submodules/Postbox/Sources/SqliteValueBox.swift#L448)。Turrit 证据为 Postbox `0x001B18F4` 初始化函数，其中 `0x001B2548`、`0x001B2568`、`0x001B2580`、`0x001B25A4` 引用相应参数并执行。

这不支持“它独有 WAL 或把 mmap 改大来提高聊天加载速度”的猜测。尚未逐条比较查询计划、消息/媒体内存缓存命中、磁盘状态及实际读写时延，不能由相同 PRAGMA 推出数据库全部行为完全一样。

## 仍待查明的线索

Network 多出 `turritQueue` 和 `trTokenRefreshHandler`。已经确认 `turritQueue` 为 `NSOperationQueue`，初始化设置 `maxConcurrentOperationCount = 4`：Core `0x0002E188`，调用点 `0x0002E1AC`，ObjC selector 为 `setMaxConcurrentOperationCount:`。同时存在 token 刷新回调及多处引用。

本轮没有把这些字段到所有任务的关联完整恢复，尤其不能由“4”推算上传/下载 socket 数或账号带宽。它们属于待追踪的请求/认证调度线索，尚无证据证明是取消 Premium 限速的实现。

播放器相关的 `ios_video_v2_reader2`、`ios_video_legacyplayer`、软硬件 AV1 配置键也存在。我们已有[相同配置入口](../submodules/TelegramUniversalVideoContent/Sources/NativeVideoContent.swift#L277)及[AV1 选择](../submodules/TelegramUniversalVideoContent/Sources/HLSVideoContent.swift#L28)。存在配置键不等于 Turrit 的默认值、服务端下发值、用户选择和设备解码能力与我们不同；这些需继续做运行时对照。

精简证据保存在被忽略的 `build-input/turrit-analysis/round3/`，包括反汇编、引用扫描及本轮参数表。二进制、IPA、凭据和账户数据不加入仓库。

## 对 b34576 的意义

b34576 已实现前轮确认的五块加载机制。后续对照首先应固定**实际播放的资源、画质和编码**，再看首帧、缓存命中和传输时间：同一条消息可能对应多个不同的视频资源，比较消息 ID 不足以保证下载量相同。

这轮补查找到了新的画质控制和通知扩展，也排除了几个把共有能力误认为独有技术的解释。没有新的运行时测速、服务端绕过验证或可证明全部隐藏实现都已恢复的结论。

## 授权后的实施范围（b34577）

Regram 增加自动/最高/最低可用画质偏好，默认自动，通过共享播放器节点应用，并保留单视频手动选择。额外滚动方向通知用于试验开启时刷新可见资源窗口及播放准入。这些是依据已确认机制做的 Regram 实现；应用范围和生命周期不能当成 Turrit 源码的完整复原。

共有 TCP 和数据库参数保持现有值。用途未完整恢复的四并发 operation queue、token 刷新回调和编码配置线索没有移植；上传/下载的服务端权限与限额没有更改。具体测试和构建记录见[加载试验文档](media-loading-experiment.md)。
