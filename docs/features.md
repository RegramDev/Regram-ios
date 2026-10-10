# Regram 已加入功能清单

核对日期：2026-10-10。代码基准：`a2da331979`。本清单汇总当前源码中的 Regram 定制功能，并补充仓库已经接入的富文本能力；Telegram 原有的聊天、群组、频道、通话等通用功能不逐项展开。

“已加入”表示已找到界面入口及对应实现，或已经接入运行路径。实际可用性仍可能取决于系统版本、账户权限、远端配置与网络。本文是源码盘点，不代表所有功能均已完成真机验收。

**主要入口**

| 入口 | 内容 |
| --- | --- |
| 设置 → Regram 设置 | 界面、分组、资料、动态、翻译、媒体、消息菜单、加载优化；支持搜索设置项 |
| 设置 → Regram Pro | 过滤器、字体、隐藏用户、输入增强、防删除、幽灵模式、通知、配置备份、聊天独立设置、撤回记录及诊断 |
| 用户／群组／频道资料页 | 会话过滤开关、会话防撤回、隐藏发送者及扩展资料信息 |
| 消息长按菜单／选中文字菜单 | 复读、转发、收藏、规则快捷添加与导入等 |
| Telegram 原有设置页 | 代理 DNS、自动锁定、浏览器、存储和设备会话等补充选项 |

当前构建的 **Regram Pro 功能已在本地开放**。下面的“本地 Premium”是另一个独立开关，Telegram 服务端校验的订阅能力仍需要真实权限。依据：[Pro 状态](../Regram/RGStatus/Sources/RGStatus.swift)、[设置首页](../Regram/RGSettingsUI/Sources/RGSettingsController.swift)、[Pro 页面](../Regram/RGProUI/Sources/RGProUI.swift)。

**1. 消息过滤与隐藏用户**

| 已加入功能 | 当前行为 |
| --- | --- |
| 普通关键词过滤 | 按不区分大小写的子串匹配隐藏收到的消息 |
| 正则表达式过滤 | 使用 ICU 正则；添加时校验，无法编译的规则不执行 |
| 规则管理 | 添加、编辑、删除、单条启停，以及普通文本／正则和隐藏／保留动作切换 |
| 规则适用范围 | 每条规则可应用于所有对话或限定到指定对话 |
| 会话过滤开关 | 资料页可关闭当前会话的关键词／正则过滤 |
| 快捷添加规则 | 从消息或选中文字菜单添加过滤内容，支持复制并添加 |
| 导入与导出 | JSON 规则文件；导入合并并去重，保留原有规则；聊天中的规则文件也有快捷导入入口 |
| 隐藏指定发送者 | 在本机隐藏指定用户或机器人的消息，覆盖其出现的不同对话 |
| 已屏蔽用户管理 | 查看列表、打开资料、左滑解除隐藏 |
| 对话列表预览联动 | 隐藏内容不会继续充当列表预览，回查可见消息；规则变更会刷新相关界面 |
| 过滤性能处理 | 无命中扫描快路径、Unicode 兼容匹配、正则及消息判定缓存；消息编辑和规则变更会使结果失效；异常正则有协作式进度超时 |
| 规则测试与临时恢复 | 输入样例查看匹配、禁用、非法正则与超时结果；按聊天临时显示被过滤内容，最长五分钟自动恢复 |

会话过滤开关只影响关键词／正则规则；按发送者隐藏仍生效。临时恢复覆盖该聊天的本机隐藏显示，不改变通知过滤。通知扩展另有默认关闭的过滤开关，见通知一节。

依据：[规则模型](../Regram/RGSimpleSettings/Sources/MessageFilter.swift)、[管理界面](../Regram/RGProUI/Sources/MessageFilterController.swift)、[统一过滤判定](../submodules/AccountContext/Sources/RGContentFilter.swift)、[列表预览](../submodules/ChatListUI/Sources/Node/RGChatListPreviewFilter.swift)、[隐藏用户列表](../Regram/RGProUI/Sources/RGHiddenUsersController.swift)。

**2. 防删除、内容保存与幽灵模式**

| 已加入功能 | 当前行为或边界 |
| --- | --- |
| 全局防撤回 | 保留本机已经收到、随后被撤回的消息，并显示撤回标记 |
| 单会话防撤回 | 从资料页开启，并在“防撤回的对话”列表集中管理 |
| 忽略自动删除计时 | 跳过已接入的普通聊天本地 TTL 清除路径 |
| 忽略阅后即焚计时 | 跳过已接入的秘密聊天本地计时清除路径 |
| 截图通知控制 | 抑制已接入路径中的截图通知上报 |
| 受保护内容保存 | 提供允许保存受保护消息内容的本地开关 |
| 受保护快拍保存 | 提供允许保存受保护快拍的本地开关 |
| 隐藏赞助消息 | 覆盖聊天赞助消息及全局搜索中的赞助结果 |
| 本地撤回记录 | 按聊天分页查看已保留记录、搜索已加载内容、定位消息及清理；清理时再次核对撤回标记 |
| 不上报快拍浏览 | 抑制浏览／查看数上报，本机浏览状态继续更新 |
| 不上报在线状态 | 本机主动状态上报按离线处理；发送消息仍可能被服务端判为在线 |
| 不发送输入状态 | 抑制普通与秘密聊天的输入活动上报 |

防删除只覆盖本机已有内容，用户主动删除仍会执行。幽灵模式当前三项为快拍浏览、在线状态和输入状态，未加入普通聊天已读回执屏蔽。

依据：[隐私工具入口](../Regram/RGProUI/Sources/RGPrivacyToolsController.swift)、[撤回标记](../submodules/TelegramCore/Sources/SyncCore/SyncCore_RGRevokedMessageAttribute.swift)、[本地计时清除](../submodules/TelegramCore/Sources/State/ManagedAutoremoveMessageOperations.swift)、[幽灵模式](../submodules/TelegramCore/Sources/Utils/RGGhostMode.swift)。

**3. 消息菜单与操作**

- 消息菜单项目可拖拽排序，并选择放在主菜单或 Regram 子菜单中。
- 复读：把消息转发回当前对话，保留转发来源。
- 无引用复读：把内容作为自己的消息重新发送到当前对话。
- 无引用转发：选择目标对话，隐藏发送者名称后转发。
- 保存到收藏夹、选择此人所有消息、保存媒体、查看消息回复、回复、置顶、限制用户、举报、查看消息 JSON，均已纳入可配置菜单项目。
- 双击自己发出的消息进入编辑。

菜单操作仍按消息类型及当前权限决定是否出现；例如置顶和限制用户不会赋予额外的服务端管理权限。

依据：[可配置项目](../Regram/RGSimpleSettings/Sources/ContextMenuItemId.swift)、[排序界面](../Regram/RGSettingsUI/Sources/RGContextMenuOrderController.swift)、[消息操作接入](../submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift)、[双击操作](../Regram/RGDoubleTapMessageAction/Sources/RGDoubleTapMessageAction.swift)。

**4. 输入与发送增强**

- 格式面板：引用、剧透、粗体、斜体、等宽、链接、下划线、删除线、代码块、清除格式及换行操作。
- 发送消息默认格式：关闭／加粗／斜体／下划线／删除线／剧透；保留已有手动格式，跳过代码、引用与自定义表情等受保护片段。
- “盘古之白”：发送时在中日韩文字与相邻拉丁字母、数字之间补空格，保留代码块与引用块。
- 按昵称提及：长按头像插入完整昵称；开启后，手动输入的 `@用户名` 在输入阶段尝试解析并替换为同样的可点击昵称实体。解析受用户名可用性与网络影响。
- 可按账号／聊天覆盖全局默认格式与盘古之白选项，或选择继承全局设置。
- 发送链接时关闭网页预览；输入时仍可查看预览。
- 使用返回键发送消息。
- 隐藏录音按钮、控制“以……身份发送”按钮显示。
- 表情键盘默认展示表情页，以及标准表情优先于高级表情。

依据：[格式面板](../Regram/RGInputToolbar/Sources/RGInputToolbar.swift)、[自动空格](../Regram/RGPangu/Sources/Pangu.swift)、[发送处理](../submodules/TelegramUI/Sources/ChatControllerNode.swift)、[输入面板](../submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift)。

**5. 翻译与语音转写**

| 已加入功能 | 当前范围 |
| --- | --- |
| 翻译服务选择 | Telegram、GTranslate、Google、系统翻译；系统翻译选项需要 iOS 18 或更新版本 |
| 单条消息快速翻译 | 可显示快速翻译按钮 |
| 整个聊天翻译 | 接入语言设置、消息翻译及置顶消息翻译；非 Premium 可走文本／外部服务路径 |
| 发送前翻译 | 长按发送按钮的选项中翻译待发内容，可按账户与对话记住目标语言 |
| 翻译容错 | 服务回退、长文本分段和语言代码归一化；外部及系统翻译路径保护链接、代码、提及等实体，恢复嵌套格式、空白和 UTF-16 范围 |
| 语音转写 | Telegram／Apple 后端选择及可用性回退 |

翻译和转写取决于所选服务、语言、网络、系统能力与权限。“不需要 Premium”的文本翻译路径不能理解为服务端所有翻译能力均已解除限制。

依据：[设置与系统版本判断](../Regram/RGSettingsUI/Sources/RGSettingsController.swift)、[外部翻译](../Regram/RGGTranslate/Sources/RGGTranslate.swift)、[聊天翻译](../submodules/TranslateUI/Sources/ChatTranslation.swift)、[发送前翻译](../submodules/TelegramUI/Sources/Chat/ChatMessageDisplaySendMessageOptions.swift)。

**6. 导航、分组与聊天外观**

- 底栏：隐藏整个底部导航栏，控制联系人标签、通话标签和标签名称；宽度在二级页面按百分比调节并显示当前值，适配上游取消独立搜索按钮后的布局。
- 分组：将分组放到底部、隐藏“所有对话”、缩小分组间距、选择“所有对话”长／短／默认标题、记住上次使用的分组。
- 对话列表：紧凑列表、1／2／3 行消息预览、对话侧滑操作开关、侧滑删除开关。
- 设置搜索：Regram 主设置可进入匹配的 Pro 设置，支持中英文别名；SwiftUI 设置页随主题、语言与界面字体更新。
- 聊天：频道消息加宽、消息时间显示秒数、频道底部面板显示控制、回应显示控制、删除消息特效控制。
- 导航动作：控制上滑进入下一未读频道、上滑进入下一主题。
- 账户颜色：调整饱和度，设为 0 可关闭账户颜色效果。
- 应用外观：切换应用图标、自定义截图中显示的 App Badge。

“底部分组样式”保留旧枚举与处理逻辑，当前设置列表没有样式选择入口。隐藏“所有对话”需要还有其他可用分组。

依据：[设置界面](../Regram/RGSettingsUI/Sources/RGSettingsController.swift)、[预览布局](../Regram/RGChatListSimpleSettingsSignal/Sources/RGCompactMessagePreviewLayout.swift)、[App Badge](../Regram/RGProUI/Sources/AppBadgeSelectorController.swift)。

**7. 资料页与快拍**

- 显示用户／群组／频道 ID，支持长按复制。
- 显示数据中心信息；可获得时附带电话号码所属国家／地区信息。
- 显示群组或频道创建日期、可获得的入群日期。
- 显示注册时间：优先采用服务端提供的年月，否则使用本地估算并加 `~` 标记。
- 打开用户或机器人资料时优先展示共同群组。
- 在设置页隐藏自己的电话号码。
- 拨打语音／视频通话前确认。
- 隐藏动态、禁用侧滑拍摄、查看动态前询问、控制“转发到动态”入口。
- 原有快拍隐身开关仍有接入，入口受 `canUseStealthMode` 配置控制；幽灵模式另有独立的“不上报快拍浏览”。

注册时间的本地估算不是精确注册日期；DC 信息来自可用资源，也不代表用户所在地。隐藏设置页号码只改变本机界面。

依据：[资料项目](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoProfileItems.swift)、[注册时间](../Regram/RGRegDate/Sources/RGRegDate.swift)、[默认资料标签](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoData.swift)、[快拍浏览界面](../submodules/TelegramUI/Components/Stories/StoryContainerScreen/Sources/StoryContainerScreen.swift)。

**8. 照片、贴纸、音视频与网络**

- 发送照片质量滑杆；大尺寸照片开关把压缩图片尺寸上限提高到 2560px。
- 贴纸显示尺寸、贴纸时间显示、最近贴纸数量上限可调。
- 最近贴纸档位：20、30、40、50、60、80、100、120、150、200。
- 图库中的相机入口与实时相机预览可分别控制。
- 圆形视频默认使用后置摄像头。
- 强制使用设备内置麦克风。
- 通话 Force TCP 选项。
- 上传加速：接入较大分块及并发上传选项。
- 下载加速：开关形式，开启即采用中等档位；旧最大档位会归一为中等。
- 默认视频画质：自动／最高可用／最低可用；与媒体加载试验独立，单个视频仍可手动选择。
- 代理设置支持使用系统 DNS 解析代理域名。

加速档位是传输参数调整，实际吞吐量取决于网络和服务器；不能据此承诺固定倍数。画质只能从播放器实际提供的版本中选择。

依据：[设置与档位](../Regram/RGSimpleSettings/Sources/SimpleSettings.swift)、[上传接入](../submodules/TelegramCore/Sources/Network/MultipartUpload.swift)、[下载接入](../submodules/TelegramCore/Sources/Network/FetchV2.swift)、[视频画质](../Regram/RGSimpleSettings/Sources/VideoQualityPolicy.swift)、[代理设置](<../submodules/SettingsUI/Sources/Data and Storage/ProxyListSettingsController.swift>)。

**9. 媒体加载优化（实验）**

入口：设置 → Regram 设置 → 其他 → 媒体加载优化（实验）。可即时切换，用同一安装包对照。

- 扩大聊天前后媒体预取窗口，避免相同资源重复调度。
- 延迟释放刚离开窗口的预取任务，回滑时可以复用。
- 可见媒体、预加载媒体与播放资源采用不同下载优先级，保留手动下载机会。
- 消息快照在后台串行队列预处理，复用过滤缓存并预热翻译资格判定。
- 自动翻译批次去重、取消、失败冷却及消息版本失效处理。
- 限制聊天内同时自动播放的视频数量，结合可见比例、位置和播放状态选择。
- 播放器短暂保留与复用；后台、内存警告、严重热状态及关闭开关时释放相应资源。
- HLS 片段加载与播放准入联动，暂停保留期间的加载并管理取消。
- 解码首帧就绪后再交接封面，协调聊天与画廊之间的切换。
- 同方向持续滚动也会刷新可见资源窗口及播放准入。

常规构建默认关闭；实验构建可设为首次默认开启，已保存的用户选择优先。本地 b34587 参考构建采用首次默认开启。代码和策略测试已接入，真实首屏、首帧、帧率、内存及流量收益尚待真机对照；没有新增独立视频信息流页面。

依据：[完整实现与验证记录](media-loading-experiment.md)。

**10. 通知与空提醒容错**

- 置顶消息通知：默认／静音／停用。
- @提及与回复通知：默认／静音／停用。
- 可选消息通知过滤：默认关闭，需要共享容器；将关键词、保留规则、隐藏发送者与会话开关应用于扩展能解析出内容的消息。未解析的推送及系统不启动扩展的情况不能保证覆盖。
- 通知扩展初始化失败、共享容器或账户快照暂未就绪时有限重试。
- 注册加密推送 token 前先完成通知路由元数据写入。
- 日志配置改为异步，移除通知处理队列的同步等待。
- 解密成功后先保存可用通知内容，增加 24 秒主动完成期限。
- 已读、删除同步和重复控制消息保留明确的清理标记，避免后续又补回媒体或声音。
- 请求归属和一次性完成保护，避免旧回调影响新推送。
- 保留静音、角标及空提醒清理兜底，并校验异常加密载荷长度。

这些是已经实现的容错措施。仓库尚未记录真机复现和验证，不能表述为已彻底消除所有 `You have a new message` 占位提醒；过滤权限与系统是否启动扩展也会影响结果。

依据：[通知实现与验证边界](notification-startup-and-empty-alerts.md)。

**11. 本地 Premium 与应用管理**

- 本地 Premium：本机将已登录账户按 Premium 状态展示，并保留本地选择的 Emoji Status；其他人看到的状态、真实额度及服务端能力仍取决于账户权限。
- 敏感内容设置入口：受远端 `canEditSettings` 配置控制。
- 节日视觉效果：雪花／闪电效果已经接入，设置入口受 `canUseNY` 配置控制，常规默认值为关闭。
- 内置 Safari 浏览方式，可在原有浏览器设置中选择。
- 自动锁定新增“离开 5 秒后”。
- 设备会话详情补充 API ID／客户端识别信息及 IP 展示。
- 存储管理增加较低缓存上限（包括 1 GB）及 1 小时自动清理选项。
- 清除全部本地数据：退出本机账户并清理数据库、缓存、设置和相关 Keychain 数据，执行前有确认。

依据：[Pro 设置](../Regram/RGProUI/Sources/RGProUI.swift)、[本地 Premium](../submodules/TelegramCore/Sources/Utils/RGLocalPremium.swift)、[远端配置接入](../Regram/RGAPIWebSettings/Sources/File.swift)、[数据清除](../Regram/RGDBReset/Sources/File.swift)、[会话信息](../Regram/RGRecentSessionApiId/Sources/RGRecentSessionApiId.swift)、[存储设置](../submodules/TelegramUI/Components/StorageUsageScreen/Sources/StorageUsageScreen.swift)。

**12. 仓库已经接入的富文本编辑与消息渲染**

这一部分来自当前仓库的富文本基础能力，也包含上游／此前分支的工作，不能全部归为最近的 Regram 定制提交。

- 所见即所得编辑器、附件菜单文章编辑入口、输入框与扩展编辑器之间的内容传递。
- 标题、正文、引用与折叠引用、代码块、有序／无序列表、任务列表。
- 表格编辑，包括单元格表头／高亮及跨行、跨列。
- 链接编辑、自定义表情、文字格式、原生拼写检查与纠正。
- 文内图片／视频、组合媒体、单项剧透遮罩；文章编辑器可切换拼贴与轮播。
- 富文本草稿持久化，发送、编辑、复制、粘贴和 Markdown 转换链路。
- InstantPage 富文本气泡：公式、嵌套引用、表格、媒体、音频、锚点跳转和长内容展开。
- AI 流式内容渐进显示及思考块渲染；具体 AI 服务可用性仍依赖服务端。
- 可编辑富文本消息中的任务复选框可以点按更新；他人消息、翻译结果等不适用。
- 富文本媒体接入画廊、共享媒体和预览链路，以及相应的自动下载／播放处理。

当前输入模式由 `ios_rich_input_mode` 与 `forceNewTextInput` 控制；附件菜单已经加入富文本入口，输入框扩展按钮还受 AI 配置影响。旧文档开头的 `debugRichText` 描述与当前代码有差异，应以当前入口实现为准。

已有能力不等于所有组合均完整：文档记录的轮播渲染存在视频页限制，部分日期创建、代码语言选择和跨设备还原细节仍有限制。详细数据流和边界见[富文本输入](richtext-composer.md)与[富文本渲染](instantpage-richtext.md)。入口依据：[聊天输入面板](../submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift)、[附件菜单](../submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift)。

**13. 字体管理**

入口：设置 → Regram Pro → 字体。拉丁字母与中日韩文字可分别选择字体，应用范围可勾选聊天内容和主要界面。

- 云端下载字体，支持 JetBrains、Anthropic Sans／Serif、Google Sans 等目录中的字体；下载字体不内嵌在 IPA。
- 本地导入 TTF／OTF／TTC；字体集合中的不同字体面分别管理，共用同一份文件。
- 实际字体预览、搜索、重命名、删除、查看存储占用和清除下载缓存。
- 删除正在使用的字体会使对应文字类别恢复系统字体；清除下载保留用户导入文件。
- 字符覆盖不足时使用字体级联回退，图标、表情与代码保留专用显示。

依据：[字体设置](../Regram/RGProUI/Sources/RGFontSettingsController.swift)、[导入选择器](../Regram/RGProUI/Sources/RGFontDocumentPickerController.swift)、[字体存储](../Regram/RGTypography/Sources/RGFontStore.swift)、[字体应用](../Regram/RGTypography/Sources/RGTypography.swift)。

**14. 配置备份与诊断**

- 按外观、消息、隐私、翻译、媒体和通知类别导出 JSON；导入前预览，可选择类别恢复或重置。
- 仅导出允许的 Regram 设置，不包含账号、登录会话、凭据、聊天数据库或字体文件；恢复后更新相关设置缓存。
- 诊断页显示本次运行收到的媒体负载字节、近期估算速率、下载加速状态和规则合成测试耗时。
- 数据量不包含所有协议流量；速率与测试耗时不是固定加速倍数或手机帧率测量。

依据：[备份格式](../Regram/RGSimpleSettings/Sources/SettingsBackup.swift)、[备份界面](../Regram/RGProUI/Sources/RGSettingsBackupController.swift)、[聊天设置](../Regram/RGProUI/Sources/RGChatPreferencesController.swift)、[诊断](../Regram/RGProUI/Sources/RGDiagnosticsController.swift)。

**已移除或不应列为当前可用功能的项目**

| 项目 | 当前状态 |
| --- | --- |
| 会话备份页面与 Keychain 备份模块 | 已在最近的媒体加载改动中移除；通知路由使用的上游账户元数据仍存在，二者不同 |
| 外部视频播放器入口 | 已移除，媒体界面恢复使用上游路径 |
| 滑动自动隐藏底栏 | 已移除；手动“隐藏底部导航栏”设置仍在 |
| WebApp 用户脚本管理 | 当前接入位置仍是 TODO，不能算完成 |
| 底部分组样式选择 | 有旧类型／文案／处理逻辑，当前设置列表没有对应选择入口 |
| NSFW 内置网站入口 | 已移除 |
| 全量 Telegram Premium 服务端解锁 | 当前本地 Premium 不提供这项能力 |

移除记录可对应 `61c8a38bd6`、`d12a81f57a` 与 `b33d711f3c`；其余状态依据当前设置界面及 [WebApp 接入](../submodules/WebUI/Sources/WebAppController.swift)。

**验证记录**

b34587 已通过 24 项本地检查、41 个过滤器场景和 `//Telegram:Regram` arm64 Release 完整构建；主 App、六个扩展、签名、调试符号及升级权限已验收。统一入口：[本地检查脚本](../build-system/check-regram-features.py)。

按要求未使用模拟器，没有连接真机。文件提供器实际点选、代理服务连通与系统网络切换、真实推送、翻译后端、界面手势和覆盖安装仍需设备验证。主机上的性能数值不等同于手机表现。
