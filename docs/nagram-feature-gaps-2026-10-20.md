# Nagram 历史功能缺口对照（2026-10-20）

本次重点是 **Nagram 仍然具备、Regram 当前缺少的增强功能或配置入口**。对照固定到 Nagram [`fa29656a2427`](https://github.com/NextAlone/Nagram-iOS/tree/fa29656a242731407c8de02ae52996b40b663080)（13.0.1 / 33357）和 Regram `bc99591dd9`（13.0 / b34620）。本地置顶修复不改变本表的功能判断；Beta 与主线的更新安装差异不纳入本次缺口。

历史检索覆盖 2026 年 5 月底至 10 月 20 日：检查 Nagram 目录的 138 条提交历史、446 条 `feat` 检索结果，其中 339 条已经是 Regram 基线的祖先；保存当前 63 份 Nagram Swift／说明文件和 76 份上游接入 Swift 文件，按配置入口及消费路径对照。提交数不等于功能数，非祖先提交也不等于 Regram 缺少该功能。以下结论结合当前入口、消费代码和本地语义对照，过滤了改名、已有能力、旧实现和单纯修复。

整理出 **36 条产品对照项：26 条缺少相应增强，9 条已有相关能力但缺少细分交互或独立配置，1 条经实施复核确认已有**。这些不是完全独立的 36 项新产品功能，也不是本轮已经移植的列表。

用户已授权实施除 F30／F33／F34 外的其余条目，进度与验证范围见[实现记录](chat-and-interface-tools.md)。

## 建议先做的内容

先做分享面板文件夹、聊天顶部工具栏、群资料页管理项、双向联系人标记、取消置顶确认和固定启动文件夹。这批入口清楚，能复用现有能力。群管理用户较多时，将批量撤销邀请链接提前；它会修改服务端状态，应单独验证分页、取消和部分失败。

之后做隐藏收藏夹／归档预览、隐藏对方活动状态、搜索框打开链接和单手搜索。自动 inline bot 查询也有实用价值，但会把匹配的输入交给选定机器人查询，需要在开关说明中说清实际行为。

iCloud 同步和账号会话备份属于独立项目：前者涉及签名能力与同步冲突，后者涉及登录授权、钥匙串和跨 DC 恢复，不能当作普通 JSON 设置备份的小改动。当前只列为候选，没有操作真实账号或读取个人会话。

## 缺少的功能和交互

“缺少”指缺少表述中的增强，不表示 Telegram 原生没有相近基础功能。来源列链接到首次或相关实现提交；证据索引链接到本次实际检查的 Nagram 固定版本和本地对应文件。

| 编号 | 功能 | Regram 差异 | 来源 |
| --- | --- | --- | --- |
| F01 | **分享面板按聊天文件夹筛选**（缺少） | 应用内转发／分享选聊天时可切换文件夹；我们已有文件夹，但分享选人面板没有这层筛选。 | [a39b3fb](https://github.com/NextAlone/Nagram-iOS/commit/a39b3fb4afcf) |
| F02 | **聊天顶部快捷工具栏**（缺少） | 一排入口包括搜索、媒体、置顶、会话开头、静音／取消静音和缓存；我们这些能力分散在其他入口，没有可选的顶部横栏。 | [77669b1](https://github.com/NextAlone/Nagram-iOS/commit/77669b19c731) |
| F03 | **自选群资料页直显管理项**（缺少） | 可选择把邀请链接、权限、管理员、历史、话题等管理项直接显示在群资料页；我们没有逐项直显的配置。不是给普通成员增加管理权限。 | [01950aa](https://github.com/NextAlone/Nagram-iOS/commit/01950aac70b7) |
| F04 | **批量撤销邀请链接**（缺少） | 可批量撤销有效链接，并按不可用条件筛选、串行执行及反馈结果；我们有逐条撤销和删除已撤销链接，没有这套批量撤销流程。 | [0f204c7](https://github.com/NextAlone/Nagram-iOS/commit/0f204c7d2850) |
| F05 | **粘贴链接自动查询 inline bot**（缺少） | 输入链接时按规则查询 Twitter、Pixiv、网易云等对应机器人，保留输入框中的原链接；我们有预览修复，没有自动生成 inline 查询。对方规则页主要展示规则，不应说成完整的用户规则编辑器。 | [92a6df9](https://github.com/NextAlone/Nagram-iOS/commit/92a6df9d9221) |
| F06 | **图库菜单直接复制图片**（已有，实施复核更正） | Regram 已有直接复制图片、取消和清理逻辑，本轮保留。原审查仅按命名检索的判断不准确。 | [6fca864](https://github.com/NextAlone/Nagram-iOS/commit/6fca864874bd) |
| F07 | **点链接预览图直接看大图**（缺少） | 普通网页预览中的图片可直接进图库，不必先打开网站；我们没有对应的图库媒体提取和预览图点击分流。 | [a8fe296](https://github.com/NextAlone/Nagram-iOS/commit/a8fe296ee166) |
| F08 | **从群／频道资料页手动选择文件夹**（部分差异） | 我们已有加入成功后选分组和其他文件夹操作；对方在已加入群／频道的资料页更多菜单中另有常驻入口。 | [edda5ec](https://github.com/NextAlone/Nagram-iOS/commit/edda5ec305c1) |
| F09 | **隐藏收藏夹与归档的消息预览**（缺少） | 保留收藏夹／归档入口，但隐藏聊天列表中的具体消息预览；我们没有独立的隐私显示开关。 | [04a744e](https://github.com/NextAlone/Nagram-iOS/commit/04a744e1da3e) |
| F10 | **隐藏对方的私聊活动状态**（缺少） | 隐藏收到的正在输入、上传、选贴纸等状态；我们幽灵模式控制自己的状态上报，方向不同。 | [43059c2](https://github.com/NextAlone/Nagram-iOS/commit/43059c2df360) |
| F11 | **单击消息行打开菜单**（缺少） | 新增单击手势开关，覆盖普通气泡、贴纸、动画贴纸和圆视频；我们已有长按和可配双击，不包含这个单击模式。 | [1f6d9ab](https://github.com/NextAlone/Nagram-iOS/commit/1f6d9abdd3cf) |
| F12 | **双向联系人标记**（缺少） | 联系人列表给双方均已添加的联系人显示双向箭头并提供说明；我们能读取联系人状态，但没有该列表标记。 | [e8f2402](https://github.com/NextAlone/Nagram-iOS/commit/e8f2402602b4) |
| F13 | **取消消息置顶前确认**（缺少） | 可为单条取消置顶和取消全部增加统一确认；不是聊天列表置顶数量设置，也不是上游部分入口原有的确认。 | [c1e39df](https://github.com/NextAlone/Nagram-iOS/commit/c1e39df7c661) |
| F14 | **隐藏文件夹未读数**（缺少） | 独立关闭文件夹标签上的未读数字；我们仍生成并显示相应标签角标。 | [eb2c35c](https://github.com/NextAlone/Nagram-iOS/commit/eb2c35c463c6) |
| F15 | **启动固定进入指定文件夹**（部分差异） | 我们支持记住上次分组；对方还可选择固定的指定分组，并按账号保存，与记住上次不是同一种行为。 | [6aecc84](https://github.com/NextAlone/Nagram-iOS/commit/6aecc842f783) |
| F16 | **文件夹标签纯图标／文字／图文**（部分差异） | 我们有紧凑分组、标题长度、标签调整，但没有这三种显示模式的独立选择。 | [b4d9004](https://github.com/NextAlone/Nagram-iOS/commit/b4d900436160) |
| F17 | **自定义文件夹中也显示归档入口**（缺少） | 在非全部会话的文件夹中显示归档入口；我们没有对应设置与列表插入分支。 | [6f61713](https://github.com/NextAlone/Nagram-iOS/commit/6f617136d08f) |
| F18 | **下拉露出归档后自动进入**（缺少） | 归档从隐藏状态被下拉展示后可自动打开；我们保留原生展示及点按进入行为，没有该增强开关。 | [6f61713](https://github.com/NextAlone/Nagram-iOS/commit/6f617136d08f) |
| F19 | **刷新时继续跟随最新消息**（缺少） | 刷新／补洞开始时若位于最新消息边缘，刷新后仍跟随最新消息；我们没有这个可选策略。和列表中新消息会话位置是两件事。 | [09b8df1](https://github.com/NextAlone/Nagram-iOS/commit/09b8df1c98a0) |
| F20 | **接收／编辑／发送分别控制盘古空格**（部分差异） | 我们有发送时盘古空格和会话覆盖；对方还在接收展示与编辑入口分别处理，并提供独立设置。 | [551d5a5](https://github.com/NextAlone/Nagram-iOS/commit/551d5a5b7508) |
| F21 | **顶部动态条与头像动态入口分开控制**（部分差异） | 我们已有隐藏动态与禁用侧滑拍摄；对方另可只隐藏顶部条、只禁用列表头像打开动态，保留其他动态功能。 | [086c95c](https://github.com/NextAlone/Nagram-iOS/commit/086c95c45cdb) |
| F22 | **隐藏权限提醒角标**（部分差异） | 可抑制联系人／设置中的权限警告提示；我们有通知诊断和系统授权流程，没有用户侧统一隐藏选项。隐藏提醒不会授予权限。 | [2d50b23](https://github.com/NextAlone/Nagram-iOS/commit/2d50b23a05e5) |
| F23 | **关闭 Community 多会话合并**（缺少） | 可把 Community 下的多个聊天分开列出；我们沿用上游分组逻辑。只对启用了该 Telegram 服务端能力的账号有意义。 | [246f493](https://github.com/NextAlone/Nagram-iOS/commit/246f493db9e4) |
| F24 | **Community 头像点击行为选择**（缺少） | 可选进入聊天、进入社区，或通过箭头区分操作；我们没有该偏好。需与普通头像动态入口区分。 | [5f48c3b](https://github.com/NextAlone/Nagram-iOS/commit/5f48c3b4dd1d) |
| F25 | **用户控制视频上滑画中画手势**（部分差异） | 我们有播放器菜单中的画中画与上游服务端手势控制；对方额外提供上滑开启／禁用的本机选项。 | [4b23f2a](https://github.com/NextAlone/Nagram-iOS/commit/4b23f2abe071) |
| F26 | **裁剪框抵住屏幕边缘时自动缩小照片**（缺少） | 裁剪边拖到边缘并保持时自动缩小图像，扩大可调整范围；我们没有这套边缘保持反馈。 | [96ae08c](https://github.com/NextAlone/Nagram-iOS/commit/96ae08ca80ff) |
| F27 | **聊天内搜索框置底单手模式**（缺少） | 搜索框放到键盘上方，成员搜索候选从底部展开；我们底栏搜索设置不等于聊天内部搜索框置底。 | [9faf622](https://github.com/NextAlone/Nagram-iOS/commit/9faf62288045) |
| F28 | **搜索结果从底部开始排列**（缺少） | 全局搜索和聊天内搜索分别提供开关；我们没有翻转结果排列的设置与容器。 | [779b0e4](https://github.com/NextAlone/Nagram-iOS/commit/779b0e4e2545) |
| F29 | **搜索框粘贴链接直接打开**（缺少） | 识别 t.me、tg:// 及简写消息／邀请路径，出现明确的打开链接结果；我们没有该搜索结果类型。 | [980b88c](https://github.com/NextAlone/Nagram-iOS/commit/980b88c7a036) |
| F30 | **常驻文字格式条模式**（部分差异） | Regram 原工具栏已经常驻显示；差异是四模式及样式选中反馈。用户要求此处不改，保留原有开关、布局与行为。 | [fd69df9](https://github.com/NextAlone/Nagram-iOS/commit/fd69df90784f) |
| F31 | **选中文字菜单直接放常用样式**（缺少） | 可配置样式、顺序及插入位置，放到选中文字菜单第一层；我们没有该菜单定制。 | [ef8f7e6](https://github.com/NextAlone/Nagram-iOS/commit/ef8f7e6663df) |
| F32 | **列表顶部保持新消息会话可见**（缺少） | 停在列表顶部时，收到新消息的会话进入可见顶部；我们没有这个可选列表更新策略。 | [cb6ab81](https://github.com/NextAlone/Nagram-iOS/commit/cb6ab819d93b) |
| F33 | **iCloud 自动同步增强与原生设置**（缺少） | 可同步增强设置及白名单内的主题、通知、下载等原生设置；我们只有手动 JSON 导入导出。当前 Nagram 已排除整份语言包。移植需配置 Regram 自己的 iCloud 能力。 | [84557f3](https://github.com/NextAlone/Nagram-iOS/commit/84557f3475ce) |
| F34 | **登录会话备份与导入恢复**（缺少） | 包含 Mithka／Pyrogram 兼容记录、钥匙串中保存的账号、文件／字符串导入及首次登录入口；我们设置备份明确不含登录会话，也没有这些服务和页面。不是聊天消息备份。 | [269d4b1](https://github.com/NextAlone/Nagram-iOS/commit/269d4b112a66) |
| F35 | **隐藏联系人底栏后在设置中补入口**（缺少） | 联系人底栏不可见时，设置页增加可直接打开的联系人入口；我们保留系统联系人页，但设置页没有对等补位入口。 | [5d473b5](https://github.com/NextAlone/Nagram-iOS/commit/5d473b552db2) |
| F36 | **列表横滑行为四种模式**（部分差异） | 对方可分别选择分组切换、快捷操作、两者或全部关闭；我们主要提供禁用侧滑和禁用删除的开关，没有等价的四模式设置。 | [aea55ba](https://github.com/NextAlone/Nagram-iOS/commit/aea55bae4250) |

## 已有功能，避免重复列入

| Nagram 历史功能 | Regram 当前依据 |
| --- | --- |
| 最近会话、长按发送者查看消息、消息菜单排序、双击动作 | 已有独立记录／页面／菜单配置，不按命名差异重复列入 |
| 单条与多选消息直接存入收藏 | `ChatMessageSelectionInputPanelNode` 已有 `cloudButtonPressed`，通过 `forwardSelectedMessages("toCloud")` 执行；不是只有单条菜单 |
| 离线注册日期估算 | `Regram/RGRegDate/Sources/RGRegDateLocal.swift` 已有本地估算表，并由 `RGRegDate.swift` 调用 |
| 链接预览修复与自定义 X／Instagram 域名 | 已有 `RGLinkMetadata`；F05 自动 bot 查询、F07 点击预览图进图库是另外的交互 |
| LLM 翻译、模型测试、提示词、上下文；自定义 STT／圆视频识别 | 已有对应设置、服务和原消息结果，不重复作为缺口 |
| 发送前翻译、翻译保留格式 | 已有翻译及消息处理路径，后续需要的是已知边界修复与验收 |
| 加入群组／频道后选文件夹 | 已有 `RGJoinedChatFolderPicker`；缺口 F08 是已加入后的资料页入口 |
| 记住上次文件夹、隐藏全部会话、紧凑列表、分隔线及标签标题设置 | 已有；F15 是固定启动文件夹，F16 是纯图标／图文模式 |
| 受保护内容的复制／保存及截图控制 | `allowSavingProtectedContent` 通过 `Message.isCopyProtected()` 等统一判断影响图库保存和截图保护，不能只因图库没有同名 Nagram 开关就判定缺失；秘密、一次性、付费等媒体限制需分别保留 |
| 图标、截图 App Badge、圆视频默认摄像头、贴纸保存／数量、媒体信息、盘古发送空格 | 已有同类能力。F20 只计接收／编辑及独立配置差异 |
| 13.0 钱包、富文本、网络／动画框架 | 两边的上游基线已有大量共同代码；服务端开放条件仍适用，不按 Nagram 的历史提交标题重复计数 |

## 工程用途及不优先照搬的差异

- **离线中英演示模式**：Nagram 的 [`Demo`](https://github.com/NextAlone/Nagram-iOS/tree/fa29656a242731407c8de02ae52996b40b663080/Nagram/Demo) 会初始化一次性演示数据，适合商店截图和 UI 回归；Regram 没有对应模式。可单独做测试工具，不与真实账号数据混用。
- **控件玻璃高亮开关**：当前 Nagram 将 `controlHighlightEnabled` 接到玻璃组件交互，Regram 没有独立开关。属于可选外观差异，价值低于上述操作入口。
- **Liquid Glass 色调／透明度**：对方有系统／自定义及百分比控制；Regram b34610–b34612 已主动移除独立色调调节，属于已有设计选择，不能当作忘记实现。
- **下载最高档与底栏完整隐藏／对齐**：两边设置策略不同。Regram 已主动收敛下载档位，并要求保留聊天／设置、底栏居中；不建议作为新增功能直接搬回。
- **Nagram 名称、图标、四页设置结构、TestFlight 分发**：品牌和分发选择，不计入 Regram 产品能力缺口。
- **崩溃、后台事务、重复未读数、引用格式等修复**：保留在[上一份修复对照](nagram-review-2026-10-20.md)，不与这份功能缺口混算。

## 源码证据索引

每条同时记录对方当前仍有的消费／设置代码，以及我们对照的位置。“本地对照”不只是检查同名字符串，还结合调用方向和入口；F08、F15、F20 等因此明确标为部分差异。

| 编号 | Nagram 固定版本证据 | Regram 本地对照 |
| --- | --- | --- |
| F01 | [ShareController.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/ShareController/Sources/ShareController.swift#L2514)：`showFoldersInShareSheet` | [SharePeersContainerNode.swift](../submodules/ShareController/Sources/SharePeersContainerNode.swift) |
| F02 | [ChatControllerNode.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/TelegramUI/Sources/ChatControllerNode.swift#L910)：`chatToolsEnabled` | [ChatControllerNode.swift](../submodules/TelegramUI/Sources/ChatControllerNode.swift) |
| F03 | [PeerInfoScreen.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift#L5661)：`isGroupProfileSettingItemVisible` | [PeerInfoScreen.swift](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift) |
| F04 | [InviteLinkListController.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/InviteLinksUI/Sources/InviteLinkListController.swift#L117)：`revokeInviteLinksSerially` | [InviteLinkListController.swift](../submodules/InviteLinksUI/Sources/InviteLinkListController.swift) |
| F05 | [ChatInterfaceInputContexts.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/TelegramUI/Sources/ChatInterfaceInputContexts.swift#L92)：`autoInlineBotEnabled` | [ChatInterfaceInputContexts.swift](../submodules/TelegramUI/Sources/ChatInterfaceInputContexts.swift) |
| F06 | [ChatImageGalleryItem.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/GalleryUI/Sources/Items/ChatImageGalleryItem.swift#L758)：`nagramCopyImage` | [ChatImageGalleryItem.swift](../submodules/GalleryUI/Sources/Items/ChatImageGalleryItem.swift) |
| F07 | [ChatMessageWebpageBubbleContentNode.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/TelegramUI/Components/Chat/ChatMessageWebpageBubbleContentNode/Sources/ChatMessageWebpageBubbleContentNode.swift#L695)：`isPointInInlineMedia` | [GalleryData.swift](../submodules/GalleryData/Sources/GalleryData.swift) |
| F08 | [PeerInfoScreenPerformButtonAction.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenPerformButtonAction.swift#L448)：`nagramPresentChatFolderPicker` | [PeerInfoScreenPerformButtonAction.swift](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenPerformButtonAction.swift) |
| F09 | [ChatListItem.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/ChatListUI/Sources/Node/ChatListItem.swift#L1595)：`hideSavedAndArchivedMessagesInList` | [ChatListItem.swift](../submodules/ChatListUI/Sources/Node/ChatListItem.swift) |
| F10 | [ChatControllerLoadDisplayNode.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift#L5238)：`hidePrivateChatActivities` | [ChatControllerLoadDisplayNode.swift](../submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift) |
| F11 | [ChatMessageBubbleItemNode.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift#L5909)：`tapMessageRowToOpenContextMenu` | [ChatMessageBubbleItemNode.swift](../submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift) |
| F12 | [ContactsPeerItem.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/ContactsPeerItem/Sources/ContactsPeerItem.swift#L102)：`mutualContact` | [ContactsPeerItem.swift](../submodules/ContactsPeerItem/Sources/ContactsPeerItem.swift) |
| F13 | [ChatControllerLoadDisplayNode.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift#L3517)：`confirmUnpin` | [ChatControllerLoadDisplayNode.swift](../submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift) |
| F14 | [ChatListController.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/ChatListUI/Sources/ChatListController.swift#L812)：`hideFolderUnreadCount` | [ChatListController.swift](../submodules/ChatListUI/Sources/ChatListController.swift) |
| F15 | [ChatListController.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/ChatListUI/Sources/ChatListController.swift#L4175)：`chatListStartupSpecificFolderId` | [ChatListController.swift](../submodules/ChatListUI/Sources/ChatListController.swift) |
| F16 | [ChatListControllerNode.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/ChatListUI/Sources/ChatListControllerNode.swift#L1640)：`chatListFolderTabDisplayMode` | [ChatListControllerNode.swift](../submodules/ChatListUI/Sources/ChatListControllerNode.swift) |
| F17 | [ChatListNodeEntries.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/ChatListUI/Sources/Node/ChatListNodeEntries.swift#L704)：`showArchiveInFolders` | [ChatListNodeEntries.swift](../submodules/ChatListUI/Sources/Node/ChatListNodeEntries.swift) |
| F18 | [ChatListControllerNode.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/ChatListUI/Sources/ChatListControllerNode.swift#L2378)：`openArchiveOnPull` | [ChatListControllerNode.swift](../submodules/ChatListUI/Sources/ChatListControllerNode.swift) |
| F19 | [ChatHistoryListNode.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/TelegramUI/Sources/ChatHistoryListNode.swift#L2648)：`stayAtLatestMessageAfterRefresh` | [ChatHistoryListNode.swift](../submodules/TelegramUI/Sources/ChatHistoryListNode.swift) |
| F20 | [ChatMessageTextBubbleContentNode.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift#L516)：`enablePanguOnReceiving` | [ChatControllerNode.swift](../submodules/TelegramUI/Sources/ChatControllerNode.swift) |
| F21 | [ChatListItem.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/ChatListUI/Sources/Node/ChatListItem.swift#L516)：`disableChatAvatarStoriesEffective` | [RGSettingsController.swift](../Regram/RGSettingsUI/Sources/RGSettingsController.swift) |
| F22 | [ContactsController.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/ContactListUI/Sources/ContactsController.swift#L221)：`hideTabBarPermissionWarnings` | [ContactsController.swift](../submodules/ContactListUI/Sources/ContactsController.swift) |
| F23 | [CommunityChatListSummary.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/TelegramCore/Sources/TelegramEngine/Messages/CommunityChatListSummary.swift#L202)：`disableCommunityChatGrouping` | [CommunityChatListSummary.swift](../submodules/TelegramCore/Sources/TelegramEngine/Messages/CommunityChatListSummary.swift) |
| F24 | [ChatListItem.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/ChatListUI/Sources/Node/ChatListItem.swift#L521)：`communityAvatarTapActionValue` | [ChatListItem.swift](../submodules/ChatListUI/Sources/Node/ChatListItem.swift) |
| F25 | [UniversalVideoGalleryItem.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/GalleryUI/Sources/Items/UniversalVideoGalleryItem.swift#L2986)：`videoPIPSwipeDirection` | [UniversalVideoGalleryItem.swift](../submodules/GalleryUI/Sources/Items/UniversalVideoGalleryItem.swift) |
| F26 | [TGPhotoCropAreaView.m](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/LegacyComponents/Sources/TGPhotoCropAreaView.m#L75)：`edgesMovedByControl` | [TGPhotoCropAreaView.m](../submodules/LegacyComponents/Sources/TGPhotoCropAreaView.m) |
| F27 | [ChatControllerNode.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/TelegramUI/Sources/ChatControllerNode.swift#L250)：`chatSearchFieldAtBottom` | [ChatControllerNode.swift](../submodules/TelegramUI/Sources/ChatControllerNode.swift) |
| F28 | [ChatSearchResultsContollerNode.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/TelegramUI/Sources/ChatSearchResultsContollerNode.swift#L204)：`bottomUpChatSearchResults` | [ChatSearchResultsContollerNode.swift](../submodules/TelegramUI/Sources/ChatSearchResultsContollerNode.swift) |
| F29 | [NagramSearchLink.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/Nagram/SearchLink/Sources/NagramSearchLink.swift#L39)：`nagramSearchLink(query:` | [ChatListSearchListPaneNode.swift](../submodules/ChatListUI/Sources/ChatListSearchListPaneNode.swift) |
| F30 | [ChatTextInputPanelNode.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift#L4782)：`textStyleToolbarMode.showsBar` | [RGInputToolbar.swift](../Regram/RGInputToolbar/Sources/RGInputToolbar.swift) |
| F31 | [ChatTextInputPanelNode.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift#L6091)：`enabledTextStyleMenuItems` | [RGInputToolbar.swift](../Regram/RGInputToolbar/Sources/RGInputToolbar.swift) |
| F32 | [ChatListNode.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/ChatListUI/Sources/Node/ChatListNode.swift#L3335)：`keepNewChatsVisibleAtTop` | [ChatListNode.swift](../submodules/ChatListUI/Sources/Node/ChatListNode.swift) |
| F33 | [NagramTelegramSettingsCloudSync.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/Nagram/TelegramSettingsCloudSync/Sources/NagramTelegramSettingsCloudSync.swift#L62)：`public func start` | [SettingsBackup.swift](../Regram/RGSimpleSettings/Sources/SettingsBackup.swift) |
| F34 | [NagramSessionBackupService.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/Nagram/SessionBackupUI/NagramSessionBackupService.swift#L118)：`nagramImportSessionString` | [SettingsBackup.swift](../Regram/RGSimpleSettings/Sources/SettingsBackup.swift) |
| F35 | [PeerInfoSettingsItems.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift#L240)：`nagramContacts` | [PeerInfoSettingsItems.swift](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift) |
| F36 | [NagramSettings.swift](https://github.com/NextAlone/Nagram-iOS/blob/fa29656a242731407c8de02ae52996b40b663080/Nagram/Settings/NagramSettings.swift#L46)：`allowsFolderSwitch` | [SimpleSettings.swift](../Regram/RGSimpleSettings/Sources/SimpleSettings.swift) |

本次属于源码功能对照，没有编译应用、安装设备或声称这些候选已经在 Regram 真机运行。对方存在实现也不等于当前 Regram 签名、账号或服务端环境可直接使用；移植时按各项接入点分别验证。
