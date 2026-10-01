# Turrit 1.5.4 视频与聊天加载实现对比

分析日期：2026-09-30。样本：用户提供的 Turrit 1.5.4 IPA，内部版本 **10382**。对照对象：同日媒体加载试验实施前的 Regram 工作树。后续实现见[聊天媒体加载试验](media-loading-experiment.md)；下文源码链接现在也包含试验分支，关闭开关仍可对照原有路径。

**本报告记录第一轮媒体预取与下载调度分析。后续[全链路审计](turrit-1.5.4-full-chain-audit.md)补充了此前遗漏的播放器保留、自动播放和 HLS 片段准入、首帧交接、串行消息处理队列。普通文字首屏的实际速度差和上传下载倍率仍未通过真机测速确认。**

本次只做静态分析和源码对照，没有修改 App 行为，没有编译或进行真机测速。

## 已确认的实现

| 环节 | Turrit 1.5.4 | 当前 Regram | 对体验的可能影响 |
| --- | --- | --- | --- |
| 聊天媒体预加载数量 | `TRPrefetchControl.chatMediaPreloadMessageCount = 6` | 聊天历史每个方向收集最多 3 个媒体候选 | 更早准备即将进入屏幕的媒体；不是预加载 6 个聊天会话 |
| 视频部分预加载时长 | `preloadVideoResource(..., duration: 4.0)` | 同样为 4.0 秒 | 此参数没有发现差异 |
| 预取任务离开窗口 | 延迟 1.5 秒释放，最多保留 3 个待释放任务；重新进入时撤销计时器、复用任务 | 离开候选集合后立即 `dispose()` | 减少来回滑动时的取消、重建和重复排队 |
| 预取输入去重 | 比较包含 messageId、mediaId、resourceId 的输入快照，相同输入直接跳过更新 | `updateMessages` 每次赋值并调用 `update()` | 降低滚动和列表更新带来的重复调度 |
| 聊天内视频播放器 | `chatMaxActiveVideoPlayers = 2`，配合可见媒体管理 | 没有对应的集中控制接口 | 可能减少同时解码多个视频的竞争；实际帧率需真机验证 |
| 媒体下载优先级 | 新增 `setChatMediaPriority(owner:visibleResourceIds:preloadResourceIds:streamingResourceId:)` 和 `foregroundStreamingPriority(resourceId:)` | 沿用前台预取、后台预取、用户发起下载等通用优先级 | 提供按当前屏幕和正在播放资源调整下载调度的能力 |
| 视频信息流 | 缓存播放器节点；保留当前、前一条、后一条；NativeVideoContent 路径会主动获取后面两条视频的资源 | 当前仓库没有对应的 Turrit 视频信息流模块 | 下一条的下载与播放器准备可以提前发生 |
| FetchV2 普通资源初始参数 | 128 KiB 分片、6 个并发；Story 为 512 KiB，CDN 为 128 KiB | 默认相同；加速中档 512 KiB / 8 并发，最高档 1 MiB / 12 并发，大分片对不超过 1 MiB 的文件保留默认值 | 没有证据表明 Turrit 在这条路径依靠更大的分片或更多并发取胜 |

这些是编译参数和已追踪的分支；实际预加载是否启动仍受开关、自动下载策略、页面状态和网络条件约束。最后一列是对机制的解释，没有声称实测收益。

## 聊天预取的具体调用链

Turrit 的 `InChatPrefetchManager` 相对当前源码新增了 `messageInput`、`pendingRemovalIds`、`removalGraceInterval`、`maximumPendingRemovalCount`，以及活跃状态、手动下载状态和任务准入状态。

从 ARM64 指令及绑定符号可还原以下行为：

1. `updateMessages` 构建媒体输入快照；输入未变时跳过更新。
2. `update` 遇到已有任务时复用，并撤销待释放计时器。
3. 候选离开窗口时启动 **1.5 秒、非重复**计时器。
4. 待释放列表超过 **3 个**时进行清理，限制保留任务数量。
5. 部分视频预加载继续调用上游 `preloadVideoResource`，时长仍为 **4 秒**。

因此，“离开屏幕后立刻取消，再滑回来重新申请”的行为，是我们与该样本之间一个可以直接落到代码上的差异。

Regram 对照：

- [媒体候选数量](../submodules/TelegramUI/Sources/ChatHistoryListNode.swift#L3323)。
- [预取更新和立即取消](../submodules/TelegramUI/Sources/InChatPrefetchManager.swift#L58)。
- [部分视频预加载](../submodules/TelegramUI/Sources/InChatPrefetchManager.swift#L124)。

## 下载调度与视频信息流

Turrit 的 `FetchManagerImpl` 有 `visibleMediaPriorityOrderedResourceIds`、`preloadMediaPriorityResourceIds`、`selectedStreamingResourceId` 和 `activeStreamingResources`。分类调度上下文还包含 `visibleResourceRanks`、`deferNonVisibleDownloads`、`chatPriorityActive` 和合并调度状态。

这证明它增加了专门处理可见媒体、预加载媒体和流播放资源的调度实现。没有完全恢复所有分类的排序权重、并发限额及运行时状态，不能据此给出完整的调度伪代码。

Regram 的 [FetchManagerImpl](../submodules/FetchManagerImpl/Sources/FetchManagerImpl.swift#L307) 仍通过通用优先级选择下载任务，没有上述聊天媒体调度 API。

视频信息流复用 `UniversalVideoNode`、`NativeVideoContent` / `HLSVideoContent` 和 Telegram 的 MediaBox。`TRVideoTableView` 的缓存管理构建当前索引及相邻索引集合，删除窗口外的播放器。另一个预加载分支对后面两个 NativeVideoContent 调用 `fetchedMediaResource` 并启动 Signal，传入 `0 ..< Int64.max` 范围。这是主动获取整份资源的路径，不能直接等同于普通聊天中“预加载前 4 秒”的策略，也不能推广到所有 HLS 视频。

“切到下一条时已经准备了一部分数据和播放器”可以解释信息流切换更快；实际下载量、首帧时间和内存开销需要运行时验证。

## 下载加速与文字聊天的证据边界

下载加速界面存在，并按账户保存数值。样本界面的标签可恢复为 `0.5x`、`1x`、`3x`、`∞`。本次未追到该数值如何改变所有下载路径的最终吞吐参数，不能用这些标签推算实际倍速。[Turrit 官方频道](https://t.me/s/TurritTips?q=%23speed) 宣传可调节上传、下载加速至最高 20 倍；该宣传不能替代对这个 IPA 的测速或调用链证据。

已检查的 FetchV2 初始化仍直接传入 `maxPendingParts = 6`，FetchingState 构造函数直接保存该参数；普通资源初始分片为 128 KiB。旧的 MultipartFetch 路径也保留基于文件大小的固定参数分支。尚无证据支持此前“DownloadAcceleration 一定是它更快的直接原因”的判断。

我们已有明确的分片和并发调整：

- [分片与并发档位](../Regram/RGSimpleSettings/Sources/SimpleSettings.swift#L1094)。
- [FetchV2 接入](../submodules/TelegramCore/Sources/Network/FetchV2.swift#L391)。
- 默认档位为 `none`；FetchV2 默认启用，但可由网络设置和服务端 killswitch 关闭。

普通文字聊天首次加载涉及历史请求、Postbox 读盘、首个历史视图、附加数据和首屏布局。第一轮仅发现 `ChatHistoryPreloadManager`，未确认消息前处理差异；后续已追到独立 `SerialMessageQueue`、处理器和缓存，见[全链路审计](turrit-1.5.4-full-chain-audit.md#文字聊天新增队列缓存与首屏依赖)。默认历史窗口仍为 44，预加载补洞参数为 0.3 秒 / 60 条，与我们的对应路径一致；不能将实际速度差归因于这些相同参数或未经证实的数据库替换。

Regram 的消息过滤已使用后台队列和缓存；没有性能采样，不应把过滤功能直接认定为慢的原因。

另需修正此前的模块判断：Turrit 自有后端还包含 `/discovery/explore`、`/discovery/feed_recommend`、`/discovery/search_entities` 等发现、推荐和搜索接口，并非仅用于登录、支付。包内也存在 Alamofire、SDWebImage 等依赖。发现接口的存在不等于视频文件由自建 CDN 传输；已追踪的视频资源预取仍进入 Telegram MediaBox。

## 可复核的二进制位置

以下为文件内未加 ASLR slide 的虚拟地址，不是源码行号。

| 框架 | 地址 | 证据 |
| --- | --- | --- |
| UI | `0x031DAEF4` | 媒体预加载数量 getter 返回 6 |
| UI | `0x031DAF08` | 最大活跃视频播放器 getter 返回 2 |
| UI | `0x0041F83C` | 输入快照比较和跳过重复更新 |
| UI | `0x0041FFCC` | 预取管理器初始化，宽限时间 1.5 秒、待释放上限 3 |
| UI | `0x00422AF0` | 创建和启动 1.5 秒计时器、限制待释放队列 |
| UI | `0x00422940` | 撤销计时器并恢复已有预取任务 |
| UI | `0x00422498` | 调用 `preloadVideoResource`，duration 为 4.0 |
| UI | `0x0180BB8C` | `setChatMediaPriority` 的导出实现及队列调度 |
| UI | `0x0177EDCC` | 视频信息流播放器缓存，当前索引及前后相邻索引 |
| UI | `0x01780A74` | 预获取后面两条 NativeVideoContent 的资源 |
| Core | `0x0016EDB4` | 普通资源分片 128 KiB、CDN 分片 128 KiB |
| Core | `0x0016F0CC` | FetchV2 状态初始化，传入并发 6 |
| Core | `0x0016E65C` | FetchingState 直接保存并发参数 |

Core SHA-256：`ac7342a5918a0f65098115ee4f2a53d0caa8968cfbbb26d76d03285e96e81215`。

UI SHA-256：`2fb473f7a13bff11f66e66d9788fc70c9572388302a099013bd20dc73468c514`。

两个框架均为 `cryptid = 0`，已逐字节核对解包文件与原 IPA 中的成员一致。使用 Mach-O exports trie、lazy binding、Swift 类型/字段元数据及 ARM64 反汇编交叉核对；没有恢复完整 Swift 源码。

本地精简证据保存在被忽略的 `build-input/turrit-analysis/`；不包含 IPA、框架二进制、签名材料或真实账户数据。

## 建议落点与验收

优先改进聊天预取的生命周期和可见媒体调度，再评估将候选数从 3 增加到 6。数量增加应与任务限额、取消策略一起评估，避免更多预取抢占当前视频的数据请求。

建议顺序：

1. 在 `InChatPrefetchManager` 加输入快照去重，以及 1.5 秒、最多 3 项的延迟释放和复用。
2. 在 `FetchManagerImpl` 和聊天可见范围更新处接入可见资源、预加载资源、当前播放资源的调度关系。
3. 在资源调度可控后评估 6 个媒体候选和活跃播放器限额。
4. 如果要做视频信息流，单独实现相邻播放器复用及受网络/流量预算约束的预加载。

验收需使用同设备、同账户、同网络、同聊天和同视频，分别测冷缓存与热缓存：点击聊天到首屏文字、点击视频到真实首帧、滑到下一条视频的首帧、回滑任务复用、当前播放与后台下载并存时的表现，并记录下载量、内存和卡顿。播放首帧改善与文字首屏改善应分别报告。
