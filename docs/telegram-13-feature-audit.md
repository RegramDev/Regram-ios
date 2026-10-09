# Telegram 13.0 功能兼容审查

审查日期：2026-10-09。官方基准：`f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838`，Regram 同步基准：`27b5bc05e8296d8fd8d98042c25cdcf4e56e2f86`。

审查覆盖 Regram 设置、Pro 设置、资料页与消息菜单，以及 Telegram 原设置中的定制项；逐项追踪原有 109 个持久化键的入口、赋值、辅助函数和现行消费路径，另加 4 个新的外观键。对旧修复逐段对照本次官方源码。源码接入、编译成功、自动检查和真机验收分开记录：找到消费者不代表服务端或真实设备上的行为已经全部通过。

## 本次修正

| 项目 | 发现与处理 |
| --- | --- |
| Search Button | 官方根控制器已不再发布底栏搜索状态。移除无效设置入口和旧开关造成的宽度扣减；未来真正存在搜索按钮时按实际组件预留空间。保留旧存储键，不影响旧用户设置数据。 |
| Wide Tab Bar | 改为“底栏宽度”二级页面；自动模式或 50–100%，显示百分比与实际 pt，使用生产底栏组件预览。100% 使用可用宽度，上限 500 pt。旧开启值迁移为 100%，旧关闭值迁移为自动。窄屏及多标签保留点击空间，因此最小百分比可能被有效布局下限提高，实际 pt 如实显示。 |
| 标签文字 | 纳入组件相等性；设置通知立即触发布局；关闭时移除残留文字视图，同步更新当前页面底部留白，不再要求重启。 |
| 字体 | Pro → 更改字体：系统默认、JetBrains Mono、JetBrains Mono NL、Inter、Poppins、Lora、IBM Plex Sans／Serif／Mono／Sans SC、Source Sans 3、Source Serif 4、系统圆体、系统衬线体。分别勾选聊天内容与主要界面文字；取消全部范围时保留选择但不应用。支持正文、粗斜体、引用、翻译与富文本正文，保留代码和大表情独立字体；缺字走系统后备字体。 |
| 字体即时刷新 | 字体族加入字体缓存键，主要界面便利字体工厂也接入；通过已有 appearance/presentation 数据流重新生成开放页面的文字。单会话／强制主题也刷新字体；颜色、壁纸、主题名称不改变。 |
| 旧分组样式 | 没有设置入口，setter 已为空，官方玻璃底栏不使用它。清理无效处理分支与预缓存，旧存储兼容保留。 |
| ChatPresentationData.withTheme | 原实现忽略传入主题，重新使用旧 theme；改为使用参数，以正确传播聊天展示刷新。 |

## 旧补丁取舍

| 补丁 | 对照结果 |
| --- | --- |
| iOS 14 Swift concurrency backport | 最低版本已统一为 iOS 15。删除未使用的 FixConcurrencyBackport 模块，移除 StripFramework 中将系统 runtime 重写为 @rpath 的旧逻辑。使用 iOS 15+ 系统 runtime。 |
| 扩展最低版本改写 | 删除旧 PatchMinOSVersion 脚本及其生成规则。SGActionRequestHandler 仍会把 plist 改为 14，而其 Mach-O 实际按 15 编译；现在随主 App 保持 15。其他已停用的改写规则一起清理。 |
| 旧底栏高度减量 | RGTabBarHeightModifier 已无调用者；新 TabBarComponent 自己返回实际高度。删除旧模块和 TabBarUI 的多余源码依赖。 |
| ThemeSettingsChatPreviewItem 主线程 | 官方 13 已使用主队列；删除重复的本地修复说明。节点数量检查与缺失同步回调的防护官方仍未覆盖，保留。 |
| ThemeCarouselThemeItem 主线程 | 官方仍在 caller 的 async 中创建包含 UIKit scroller 的节点，保留主队列修复。 |
| 动画速度 | CAAnimationUtils 和 ListView 的官方路径仍直接除以 duration；保留有限值、正 duration 防护。 |
| 已读状态同步 | 官方已经处理缺失 read state 的确认，但本地状态领先时仍返回 retry。保留 localStateAhead → pushPeerReadState(willValidate:false) 的有限兜底，避免历史状态陷入重试。 |
| 通知容错 | 官方未包含 Regram 的冷启动有限重试、24 秒交付期限、一次性交付归属、空控制提醒清理、重签名 entitlement 检查。保留；真实推送、角标、CallKit 仍需设备验收。旧 debug 强制兼容开关仍有实际消费者，并会关闭 CallKit，不作为通用通知修复推荐。 |
| locale / 翻译语言码 / URL 转义 | 官方没有等价的 -raw 清理、所接入后端的语言码归一化或白名单 URL canonical-escape 处理，保留。 |
| 撤回属性旧编码 | 属于旧数据库兼容，不是上游 bug；保持旧编码注册，不能因版本更新删除。 |
| App Group / Siri / CloudKit / 重签名 | 运行时检查实际签名权限以及共享容器回退仍适用于第三方签名包，与 Telegram 版本升级无关，保留。 |
| rules_apple 本机 Xcode 补丁 | 当前跟踪补丁仍用于工具链路径及 actool，保持原状态；本次未修改子模块。 |

## 功能组核查

| 功能组 | 当前判断与边界 |
| --- | --- |
| 消息过滤、正则、范围、导入导出、隐藏用户 | 规则 v2、缓存版本失效、后台准备、聊天条目及列表可见预览仍接入；单会话关闭只关闭规则，不取消隐藏发送者。推送不使用同一套显示过滤。 |
| 防撤回、TTL、秘密聊天、保护内容、广告 | 普通全局／per-peer 删除、历史校验、秘密聊天删除、本地 autoremove 和内容保存权限路径仍接入。仅保护本机已收到内容；主动删除、服务端历史回收及临时 AI 中间消息不承诺保留。 |
| 幽灵与快拍 | readStories、incrementStoryViews、updateStatus、普通／秘密聊天输入活动路径仍受开关控制。没有普通消息已读回执屏蔽；旧快拍隐身入口仍受远端 storiesAvailable 控制，不等于失效。 |
| 消息菜单、复读、无引用转发、收藏、选择、JSON | 使用 contextMenuItemIsEnabled 与排序表间接消费开关，不能因直接引用为零判定失效。操作仍受消息类型和群组管理权限限制。 |
| 输入工具栏、返回键、默认格式、盘古、昵称、网页预览 | 旧输入节点及新版 MessageInputPanelComponent 都有格式工具栏；返回键已接入富文本输入适配；发送格式与盘古处理保留保护片段，链接预览开关在发送链路消费。 |
| 翻译与语音转写 | quick translate、整聊／置顶翻译、发送前翻译、后端枚举和语言码处理仍接入。系统翻译需要 iOS 18；Apple 转写依赖系统语言支持与权限；第三方网络后端本次未作线上服务验收。 |
| 底栏、分组、列表与聊天外观 | 搜索／宽度／标签已修正；联系人与通话设置继续使用官方 CallListSettings。底部分组、隐藏 All Chats、标题、紧凑间距、分组记忆、侧滑、频道宽气泡、秒数、反应及删除特效仍有消费者。两行预览仍是底层值，界面只提供紧凑／默认切换。 |
| 资料、日期与通话 | ID、DC、创建日期、注册时间、共同群组、隐藏号码和呼叫确认仍接入。估算注册时间带 ~，不能作为精确日期；DC 资源可缺失。 |
| 照片、贴纸、录制、麦克风、分享、传输 | 大图和压缩质量覆盖现行选图／上传路径；贴纸尺寸、时间、最近列表上限仍接入。相机与预览独立，内置麦克风／后置圆视频／系统分享仍有消费者。上传下载开关只是分块和并发策略，不承诺固定加速倍数。 |
| 媒体加载试验、默认画质 | 可见优先级、短期保留、播放器准入、HLS 片段拥有者、首帧交接、消息版本缓存与翻译冷却仍接入；画质来自播放器实际版本。策略回归通过不代表已经证明设备性能收益。 |
| 通知、图标、截图 Badge、会话、存储、锁定 | 通知策略继续使用 App Group；应用图标及截图 Badge 入口有效。API ID／IP、1GB 缓存、1 小时清理、5 秒离开锁定、内置 Safari 仍接入。真实推送与重签名权限需设备覆盖。 |
| Pro、本地 Premium、敏感内容、NSFW、节日、清除数据 | Pro 本地开放保持原设计。本地 Premium 只改变本机权限显示／Emoji Status；服务端限制仍存在。敏感内容、节日与特定图标受远端配置；NSFW 是网络网页入口。本次未执行清除真实数据。 |
| 富文本编辑和气泡 | 发送／编辑／草稿／复制粘贴、InstantPage V2、表格／引用／代码／任务项及媒体仍接入并随新版编译。字体作用域新增传到富文本气泡；专有代码及图标字体保持独立。所有复杂组合与跨设备还原仍需单独验收。 |
| WebApp 用户脚本 | 当前仍有 TODO；没有可用脚本管理／注入入口，不能列为已完成能力。本次未新增此功能。 |

## b34580：中英文独立字体

增加独立中文选择：系统中文、IBM Plex Sans SC、Noto Serif SC；英文字母／数字／ASCII 标点保留英文选择。汉字、中文标点、全角形式使用中文选择，Emoji 保持系统回退，代码保留独立等宽字体。两项都使用原有聊天内容／主要界面的勾选范围。旧 Latin 选择保留；旧 Plex SC 选择迁到中文栏。新增 fontChineseFamily 后，现行持久化键共 114 项。详情见 [字体分脚本说明](font-script-separation.md)。

## 逐键追踪

下面的“接入”仅表示当前生产源码存在消费路径。内部状态、旧迁移键和有条件入口单独标注。机器可读列表见 [telegram-13-settings-audit.json](telegram-13-settings-audit.json)。

| 持久化键 | 对应功能 | 当前状态 | 生产路径示例 |
| --- | --- | --- | --- |
| `hidePhoneInSettings` | 隐藏设置页号码 | 源码仍接入 | [PeerInfoProfileItems.swift](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoProfileItems.swift) |
| `showTabNames` | 底栏标签文字 | 源码仍接入 | [ChatListSearchContainerNode.swift](../submodules/ChatListUI/Sources/ChatListSearchContainerNode.swift) |
| `startTelescopeWithRearCam` | 圆形视频后置相机 | 源码仍接入 | [CameraOutput.swift](../submodules/Camera/CameraLegacy/Sources/CameraOutput.swift) |
| `accountColorsSaturation` | 账户颜色饱和度 | 源码仍接入 | [PeerNameColors.swift](../submodules/AccountContext/Sources/PeerNameColors.swift) |
| `uploadSpeedBoost` | 上传分块与并发 | 源码仍接入；依赖服务、媒体或网络能力 | [MultipartUpload.swift](../submodules/TelegramCore/Sources/Network/MultipartUpload.swift) |
| `downloadSpeedBoost` | 下载分块与并发 | 源码仍接入；依赖服务、媒体或网络能力 | [FetchV2.swift](../submodules/TelegramCore/Sources/Network/FetchV2.swift) |
| `mediaLoadingExperiment` | 媒体加载试验 | 源码仍接入 | [FetchManagerImpl.swift](../submodules/FetchManagerImpl/Sources/FetchManagerImpl.swift) |
| `defaultVideoQuality` | 默认视频画质 | 源码仍接入；依赖服务、媒体或网络能力 | [UniversalVideoNode.swift](../submodules/AccountContext/Sources/UniversalVideoNode.swift) |
| `bottomTabStyle` | 旧底部分组样式 | 旧存储兼容；无入口／无有效消费者，已删死分支 | [SimpleSettings.swift](../Regram/RGSimpleSettings/Sources/SimpleSettings.swift) |
| `rememberLastFolder` | 记住分组 | 源码仍接入 | [ChatListController.swift](../submodules/ChatListUI/Sources/ChatListController.swift) |
| `lastAccountFolders` | 各账户上次分组 | 内部状态／缓存；现行路径接入 | [ChatListController.swift](../submodules/ChatListUI/Sources/ChatListController.swift) |
| `localDNSForProxyHost` | 代理系统DNS | 源码仍接入 | [ProxyListSettingsController.swift](../submodules/SettingsUI/Sources/Data%20and%20Storage/ProxyListSettingsController.swift) |
| `sendLargePhotos` | 发送大尺寸照片 | 源码仍接入 | [TGMediaEditingContext.m](../submodules/LegacyComponents/Sources/TGMediaEditingContext.m) |
| `outgoingPhotoQuality` | 照片压缩质量 | 源码仍接入 | [LegacyMediaPickers.swift](../submodules/LegacyMediaPickerUI/Sources/LegacyMediaPickers.swift) |
| `storyStealthMode` | 旧快拍隐身 | 源码仍接入；入口受远端配置限制 | [TelegramEngineMessages.swift](../submodules/TelegramCore/Sources/TelegramEngine/Messages/TelegramEngineMessages.swift) |
| `canUseStealthMode` | 隐身远端入口条件 | 源码仍接入；入口受远端配置限制 | [File.swift](../Regram/RGAPIWebSettings/Sources/File.swift) |
| `disableSwipeToRecordStory` | 禁止侧滑拍快拍 | 源码仍接入 | [ChatListControllerNode.swift](../submodules/ChatListUI/Sources/ChatListControllerNode.swift) |
| `quickTranslateButton` | 消息快速翻译 | 源码仍接入 | [ChatMessageItemImpl.swift](../submodules/TelegramUI/Components/Chat/ChatMessageItemImpl/Sources/ChatMessageItemImpl.swift) |
| `outgoingLanguageTranslation` | 各账户会话发送前翻译 | 源码仍接入；依赖服务、媒体或网络能力 | [RGDebugUI.swift](../Regram/RGDebugUI/Sources/RGDebugUI.swift) |
| `hideReactions` | 隐藏回应 | 源码仍接入 | [ChatMessageDateAndStatusNode.swift](../submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode/Sources/ChatMessageDateAndStatusNode.swift) |
| `showRepostToStory` | 旧转发快拍键 | 仅旧共享设置迁移到v2 | [SimpleSettings.swift](../Regram/RGSimpleSettings/Sources/SimpleSettings.swift) |
| `showRepostToStoryV2` | 转发到快拍 | 源码仍接入 | [SharePeersContainerNode.swift](../submodules/ShareController/Sources/SharePeersContainerNode.swift) |
| `contextShowSelectFromUser` | 选择此人消息 | 源码仍接入 | [ChatInterfaceStateContextMenus.swift](../submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift) |
| `contextShowSaveToCloud` | 收藏消息 | 源码仍接入 | [ChatInterfaceStateContextMenus.swift](../submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift) |
| `contextShowRestrict` | 限制用户 | 源码仍接入 | [ChatInterfaceStateContextMenus.swift](../submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift) |
| `contextShowHideForwardName` | 无引用转发 | 源码仍接入 | [ChatInterfaceStateContextMenus.swift](../submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift) |
| `contextShowReport` | 举报菜单 | 源码仍接入 | [ChatInterfaceStateContextMenus.swift](../submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift) |
| `contextShowReply` | 回复菜单 | 源码仍接入 | [ChatInterfaceStateContextMenus.swift](../submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift) |
| `contextShowPin` | 置顶菜单 | 源码仍接入 | [ChatInterfaceStateContextMenus.swift](../submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift) |
| `contextShowSaveMedia` | 保存媒体菜单 | 源码仍接入 | [ChatInterfaceStateContextMenus.swift](../submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift) |
| `contextShowMessageReplies` | 查看回复菜单 | 源码仍接入 | [ChatInterfaceStateContextMenus.swift](../submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift) |
| `contextShowJson` | 消息JSON菜单 | 源码仍接入 | [ChatInterfaceStateContextMenus.swift](../submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift) |
| `contextShowRepeatForward` | 复读转发 | 源码仍接入 | [ChatInterfaceStateContextMenus.swift](../submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift) |
| `contextShowRepeatCopy` | 无引用复读 | 源码仍接入 | [ChatInterfaceStateContextMenus.swift](../submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift) |
| `contextMenuOrder` | 菜单排序与主菜单分配 | 源码仍接入 | [ChatInterfaceStateContextMenus.swift](../submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift) |
| `profileDefaultTabGroupsInCommon` | 默认共同群组 | 源码仍接入 | [PeerInfoData.swift](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoData.swift) |
| `mentionAsUserIdLink` | 按完整昵称提及 | 源码仍接入 | [ChatTextFormat.swift](../submodules/ChatPresentationInterfaceState/Sources/ChatTextFormat.swift) |
| `localPremium` | 本地Premium显示 | 源码仍接入 | [RGLocalPremium.swift](../submodules/TelegramCore/Sources/Utils/RGLocalPremium.swift) |
| `localPremiumEmojiStatus` | 本地EmojiStatus缓存 | 内部状态／缓存；现行路径接入 | [RGLocalPremium.swift](../submodules/TelegramCore/Sources/Utils/RGLocalPremium.swift) |
| `nsfwEnabled` | NSFW网页入口 | 源码仍接入；依赖服务、媒体或网络能力 | [PeerInfoSettingsItems.swift](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift) |
| `nsfwAgeConfirmed` | 网页年龄确认 | 内部状态／缓存；现行路径接入 | [RGNSFWController.swift](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/RGNSFWController.swift) |
| `disableLinkPreview` | 发送时关闭链接预览 | 源码仍接入 | [TGDatabaseMessageDraft.m](../submodules/LegacyComponents/Sources/TGDatabaseMessageDraft.m) |
| `disableScrollToNextChannel` | 禁止下一频道 | 源码仍接入 | [ChatControllerContentData.swift](../submodules/TelegramUI/Sources/ChatControllerContentData.swift) |
| `disableScrollToNextTopic` | 禁止下一主题 | 源码仍接入 | [ChatControllerContentData.swift](../submodules/TelegramUI/Sources/ChatControllerContentData.swift) |
| `disableChatSwipeOptions` | 对话侧滑 | 源码仍接入 | [ChatListControllerNode.swift](../submodules/ChatListUI/Sources/ChatListControllerNode.swift) |
| `disableDeleteChatSwipeOption` | 对话侧滑删除 | 源码仍接入 | [ChatListItem.swift](../submodules/ChatListUI/Sources/Node/ChatListItem.swift) |
| `disableGalleryCamera` | 图库相机 | 源码仍接入 | [MediaPickerScreen.swift](../submodules/MediaPickerUI/Sources/MediaPickerScreen.swift) |
| `disableGalleryCameraPreview` | 图库相机预览 | 源码仍接入 | [MediaPickerScreen.swift](../submodules/MediaPickerUI/Sources/MediaPickerScreen.swift) |
| `disableSendAsButton` | 发送身份按钮 | 源码仍接入 | [ChatPresentationInterfaceState.swift](../submodules/ChatPresentationInterfaceState/Sources/ChatPresentationInterfaceState.swift) |
| `disableSnapDeletionEffect` | 删除特效 | 源码仍接入 | [ChatHistoryListNode.swift](../submodules/TelegramUI/Sources/ChatHistoryListNode.swift) |
| `stickerSize` | 贴纸大小 | 源码仍接入 | [ChatMessageItemImpl.swift](../submodules/TelegramUI/Components/Chat/ChatMessageItemImpl/Sources/ChatMessageItemImpl.swift) |
| `stickerTimestamp` | 贴纸时间 | 源码仍接入 | [ChatMessageItemImpl.swift](../submodules/TelegramUI/Components/Chat/ChatMessageItemImpl/Sources/ChatMessageItemImpl.swift) |
| `recentStickerLimit` | 最近贴纸上限 | 源码仍接入 | [AccountStateManagementUtils.swift](../submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift) |
| `defaultOutgoingFormatting` | 发送默认格式 | 源码仍接入 | [ChatControllerNode.swift](../submodules/TelegramUI/Sources/ChatControllerNode.swift) |
| `hideRecordingButton` | 录音按钮 | 源码仍接入 | [ChatTextInputPanelNode.swift](../submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift) |
| `hideTabBar` | 隐藏底栏 | 源码仍接入 | [ChatListController.swift](../submodules/ChatListUI/Sources/ChatListController.swift) |
| `showDC` | 资料数据中心 | 源码仍接入 | [PeerInfoProfileItems.swift](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoProfileItems.swift) |
| `showCreationDate` | 群组频道创建日期 | 源码仍接入 | [PeerInfoProfileItems.swift](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoProfileItems.swift) |
| `showRegDate` | 注册时间 | 源码仍接入；依赖服务、媒体或网络能力 | [RGRegDate.swift](../Regram/RGRegDate/Sources/RGRegDate.swift) |
| `regDateCache` | 注册时间缓存 | 内部状态／缓存；现行路径接入 | [RGDebugUI.swift](../Regram/RGDebugUI/Sources/RGDebugUI.swift) |
| `compactChatList` | 紧凑列表 | 源码仍接入 | [ChatListItem.swift](../submodules/ChatListUI/Sources/Node/ChatListItem.swift) |
| `chatListLines` | 列表预览行数 | 源码仍接入 | [RGCompactMessagePreviewLayout.swift](../Regram/RGChatListSimpleSettingsSignal/Sources/RGCompactMessagePreviewLayout.swift) |
| `compactFolderNames` | 分组间距 | 源码仍接入 | [ChatListFilterTabContainerNode.swift](../submodules/TelegramUI/Components/ChatList/ChatListFilterTabContainerNode/Sources/ChatListFilterTabContainerNode.swift) |
| `allChatsTitleLengthOverride` | 所有对话标题 | 源码仍接入 | [ChatListControllerNode.swift](../submodules/ChatListUI/Sources/ChatListControllerNode.swift) |
| `allChatsHidden` | 隐藏所有对话 | 源码仍接入 | [ChatListController.swift](../submodules/ChatListUI/Sources/ChatListController.swift) |
| `defaultEmojisFirst` | 标准表情优先 | 源码仍接入 | [EntityKeyboard.swift](../submodules/TelegramUI/Components/EntityKeyboard/Sources/EntityKeyboard.swift) |
| `messageDoubleTapActionOutgoing` | 双击本人消息编辑 | 源码仍接入 | [RGDoubleTapMessageAction.swift](../Regram/RGDoubleTapMessageAction/Sources/RGDoubleTapMessageAction.swift) |
| `wideChannelPosts` | 频道气泡加宽 | 源码仍接入 | [ChatMessageBubbleItemNode.swift](../submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift) |
| `forceEmojiTab` | 默认表情页 | 源码仍接入 | [ChatEntityKeyboardInputNode.swift](../submodules/TelegramUI/Components/ChatEntityKeyboardInputNode/Sources/ChatEntityKeyboardInputNode.swift) |
| `forceBuiltInMic` | 内置麦克风 | 源码仍接入 | [ManagedAudioSession.swift](../submodules/TelegramAudio/Sources/ManagedAudioSession.swift) |
| `secondsInMessages` | 消息时间秒数 | 源码仍接入 | [DateFormat.swift](../submodules/TextFormat/Sources/DateFormat.swift) |
| `hideChannelBottomButton` | 频道底部按钮 | 源码仍接入 | [ChatControllerNode.swift](../submodules/TelegramUI/Sources/ChatControllerNode.swift) |
| `forceSystemSharing` | 系统分享 | 源码仍接入 | [RGDebugUI.swift](../Regram/RGDebugUI/Sources/RGDebugUI.swift) |
| `confirmCalls` | 呼叫前确认 | 源码仍接入 | [AccountContext.swift](../submodules/TelegramUI/Sources/AccountContext.swift) |
| `legacyNotificationsFix` | 旧通知强制兼容 | 源码仍接入 | [RGDebugUI.swift](../Regram/RGDebugUI/Sources/RGDebugUI.swift) |
| `messageFilterKeywords` | 旧关键词数据 | 仅旧数据迁移到规则v2 | [SimpleSettings.swift](../Regram/RGSimpleSettings/Sources/SimpleSettings.swift) |
| `messageFilterRules` | 关键词正则规则 | 源码仍接入 | [RGContentFilter.swift](../submodules/AccountContext/Sources/RGContentFilter.swift) |
| `blockedPeerIds` | 隐藏发送者 | 源码仍接入 | [RGContentFilter.swift](../submodules/AccountContext/Sources/RGContentFilter.swift) |
| `messageFilterDisabledPeerIds` | 单会话规则关闭 | 源码仍接入 | [RGContentFilter.swift](../submodules/AccountContext/Sources/RGContentFilter.swift) |
| `antiRevokePeerIds` | 单会话防撤回 | 源码仍接入 | [AccountStateManagementUtils.swift](../submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift) |
| `inputToolbar` | 格式工具栏 | 源码仍接入 | [RGDebugUI.swift](../Regram/RGDebugUI/Sources/RGDebugUI.swift) |
| `pinnedMessageNotifications` | 置顶通知策略 | 源码仍接入 | [NotificationService.swift](../Telegram/NotificationService/Sources/NotificationService.swift) |
| `mentionsAndRepliesNotifications` | 提及回复通知策略 | 源码仍接入 | [NotificationService.swift](../Telegram/NotificationService/Sources/NotificationService.swift) |
| `primaryUserId` | Pro主账户标识 | 内部状态／缓存；现行路径接入 | [RGDebugUI.swift](../Regram/RGDebugUI/Sources/RGDebugUI.swift) |
| `status` | 本地Pro状态 | 内部状态／缓存；现行路径接入 | [RGStatus.swift](../Regram/RGStatus/Sources/RGStatus.swift) |
| `dismissedSGSuggestions` | 关闭的客户端提示 | 内部状态／缓存；现行路径接入 | [Suggestions.swift](../submodules/TelegramCore/Sources/Suggestions.swift) |
| `duckyAppIconAvailable` | 图标远端条件 | 源码仍接入；入口受远端配置限制 | [File.swift](../Regram/RGAPIWebSettings/Sources/File.swift) |
| `transcriptionBackend` | 语音转写后端 | 源码仍接入；依赖服务、媒体或网络能力 | [ChatMessageInteractiveFileNode.swift](../submodules/TelegramUI/Components/Chat/ChatMessageInteractiveFileNode/Sources/ChatMessageInteractiveFileNode.swift) |
| `translationBackend` | 翻译后端 | 源码仍接入；依赖服务、媒体或网络能力 | [TelegramEngineMessages.swift](../submodules/TelegramCore/Sources/TelegramEngine/Messages/TelegramEngineMessages.swift) |
| `customAppBadge` | 截图AppBadge | 源码仍接入 | [WindowContent.swift](../submodules/Display/Source/WindowContent.swift) |
| `canUseNY` | 节日效果远端条件 | 源码仍接入；入口受远端配置限制 | [File.swift](../Regram/RGAPIWebSettings/Sources/File.swift) |
| `nyStyle` | 节日效果样式 | 源码仍接入；入口受远端配置限制 | [RGNY.swift](../Regram/RGNY/Sources/RGNY.swift) |
| `wideTabBar` | 旧宽底栏选择 | 旧选择迁移到宽度百分比；存储键兼容保留 | [SimpleSettings.swift](../Regram/RGSimpleSettings/Sources/SimpleSettings.swift) |
| `tabBarSearchEnabled` | 旧搜索按钮开关 | 已移除入口与布局影响；存储键兼容保留 | [SimpleSettings.swift](../Regram/RGSimpleSettings/Sources/SimpleSettings.swift) |
| `hideStories` | 隐藏快拍 | 源码仍接入 | [SharedAccountContext+RGUISettingsMigration.swift](../Regram/RGSharedAccountContextMigration/Sources/SharedAccountContext+RGUISettingsMigration.swift) |
| `disableAllAds` | 隐藏赞助消息 | 源码仍接入 | [AdMessages.swift](../submodules/TelegramCore/Sources/TelegramEngine/Messages/AdMessages.swift) |
| `antiRevoke` | 全局防撤回 | 源码仍接入 | [AccountStateManagementUtils.swift](../submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift) |
| `antiAutoDelete` | 跳过普通聊天本地TTL | 源码仍接入 | [ManagedAutoremoveMessageOperations.swift](../submodules/TelegramCore/Sources/State/ManagedAutoremoveMessageOperations.swift) |
| `antiSelfDestruct` | 跳过秘密聊天本地计时 | 源码仍接入 | [ManagedAutoremoveMessageOperations.swift](../submodules/TelegramCore/Sources/State/ManagedAutoremoveMessageOperations.swift) |
| `antiScreenshotNotification` | 截图上报开关 | 源码仍接入 | [TelegramEngineMessages.swift](../submodules/TelegramCore/Sources/TelegramEngine/Messages/TelegramEngineMessages.swift) |
| `allowSavingProtectedContent` | 受保护内容保存 | 源码仍接入 | [MessageUtils.swift](../submodules/TelegramCore/Sources/Utils/MessageUtils.swift) |
| `allowDownloadingStories` | 受保护快拍保存 | 源码仍接入 | [Stories.swift](../submodules/TelegramCore/Sources/TelegramEngine/Messages/Stories.swift) |
| `ghostDontReadStories` | 不上报快拍浏览 | 源码仍接入 | [ManagedSynchronizeViewStoriesOperations.swift](../submodules/TelegramCore/Sources/State/ManagedSynchronizeViewStoriesOperations.swift) |
| `ghostDontSendOnline` | 不上报主动在线状态 | 源码仍接入 | [ManagedAccountPresence.swift](../submodules/TelegramCore/Sources/State/ManagedAccountPresence.swift) |
| `ghostDontSendTyping` | 不上报输入状态 | 源码仍接入 | [ManagedLocalInputActivities.swift](../submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift) |
| `panguSpacing` | 盘古空格 | 源码仍接入 | [ChatControllerNode.swift](../submodules/TelegramUI/Sources/ChatControllerNode.swift) |
| `warnOnStoriesOpen` | 快拍打开确认 | 源码仍接入 | [SharedAccountContext+RGUISettingsMigration.swift](../Regram/RGSharedAccountContextMigration/Sources/SharedAccountContext+RGUISettingsMigration.swift) |
| `showProfileId` | 资料ID | 源码仍接入 | [SharedAccountContext+RGUISettingsMigration.swift](../Regram/RGSharedAccountContextMigration/Sources/SharedAccountContext+RGUISettingsMigration.swift) |
| `sendWithReturnKey` | 返回键发送 | 源码仍接入 | [SharedAccountContext+RGUISettingsMigration.swift](../Regram/RGSharedAccountContextMigration/Sources/SharedAccountContext+RGUISettingsMigration.swift) |
| `tabBarWidthPercent` | 可调节底栏宽度 | 新增并接入 | [TabBarComponent.swift](../submodules/TelegramUI/Components/TabBarComponent/Sources/TabBarComponent.swift) |
| `fontFamily` | 英文字体选择 | 新增并接入 | [Font.swift](../submodules/Display/Source/Font.swift) |
| `fontApplyToMessages` | 聊天内容字体范围 | 新增并接入 | [Font.swift](../submodules/Display/Source/Font.swift) |
| `fontApplyToInterface` | 主要界面字体范围 | 新增并接入 | [Font.swift](../submodules/Display/Source/Font.swift) |
| `fontChineseFamily` | 独立中文字体选择 | b34580 新增并接入 | [RGTypography.swift](../Regram/RGTypography/Sources/RGTypography.swift) |

## 验证与剩余范围

- 已通过：底栏百分比／迁移／1–4 标签／长文本／窄屏边界与字体范围策略回归；媒体预加载、播放器、HLS、翻译及通知的现有纯策略回归；82 个字体文件 PostScript 名、预览字符和上游 SHA-256；英文／简体／繁体 strings 语法检查。
- `//Telegram:Regram` arm64 release **b34579** 构建通过（Xcode 27.0 / iPhoneOS SDK 27.0），包含主程序与六个扩展。
- 最终 LCSign 参考 IPA 已重新解包验收：12 个 arm64 Mach-O 均通过严格 ad-hoc 签名校验；12 份 dSYM，主程序和扩展 UUID 匹配；0 个描述文件。Bundle ID／App Group／entitlements 与 b34578 相同，七个包的最低 iOS 均为 15.0；82 个字体文件与 10 份许可文件的包内 SHA-256 均匹配来源记录。
- 字体 UIKit 测试宿主及测试代码已编译。Xcode runner 未启动实际测试；按用户要求停止模拟器验证，不计为通过。
- 尚未执行：真机覆盖安装、实际 Telegram 账号的消息发送／撤回／TTL、系统推送与 CallKit、联网翻译和转写、网络性能对照。不能将本报告理解为所有条件性功能均已真机通过。

原有 README、docs/README 及未提交功能／桌面计划文档属于先前工作树内容，本次保持原样，审查结果写入独立文件。

参考 IPA SHA-256：`d96ec1aa9e31e8973dea7d2dbf374d6acc8a5477104a3c53eaf7bfb50c23c585`。
