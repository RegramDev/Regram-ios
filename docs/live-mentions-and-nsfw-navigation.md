# 输入时昵称提及、NSFW 网页导航与品牌字体

后续 b34583 已按要求删除 NSFW 功能，并修正字体导入与设置界面，见[设置修正](settings-fixes-34583.md)。以下 NSFW 内容为历史版本记录。


b34582 修正 b34581 的两个交互问题，并增加五款按需字体。

## 输入时转换昵称

开启 Regram Pro 的“按昵称提及”后，在聊天输入框输入完整 `@username`，短暂停顿（650 ms）后解析用户，并在草稿中替换为昵称及 Telegram 原生用户提及引用。输入框中能看到转换效果，昵称可引用该用户，普通消息与富文本消息沿用原生发送路径。点选用户名建议也使用昵称引用，与长按用户“提及”的名称和实体类型一致。

此前 b34581 只在普通消息发送阶段改写，输入框没有转换效果；用户名建议列表也绕开了此设置。另一个检测问题是上游扫描器会跳过与任何已有文字实体重叠的用户名，包括粗体。现在先独立检测，再仅排除链接、邮箱、代码、已有用户引用等语义实体，允许保留粗体／斜体等格式。

解析每批最多 16 个不同用户名，单个解析最多 4 秒。只有精确匹配账号用户名或别名的用户才会替换，频道、不存在的用户名和失败解析保留原文。继续输入、改变光标、撤销草稿、发送或清空后，旧解析结果不能覆盖新草稿；中文输入法尚未提交的组合文本也不会被替换。

替换使用结构化 `ChatTextInputState.replacingFlatRange`，保留标题、列表、引用、表格和媒体块，并以 UTF-16 调整光标。昵称后的空格不包含用户引用属性。b34581 的发送队列改写已移除，发送不再等待此转换。

实现：[输入解析与昵称实体](../submodules/TelegramUI/Sources/RGNicknameMentions.swift)、[草稿更新接入](../submodules/TelegramUI/Sources/Chat/UpdateChatPresentationInterfaceState.swift)、[建议列表](../submodules/TelegramUI/Sources/MentionChatInputContextPanelNode.swift)。

## NSFW 网站列表与网页历史

NSFW 首屏改为入口列表：推荐、Nv、MissAV、黄果、JAV Ranking。点选后推入独立网页界面，去掉横向标签栏。

网页界面保留 WebKit 的前进／后退右滑手势，并在整个网页视图禁用 Telegram 父级返回手势，包括屏幕边缘。网页右滑不会弹出界面进入设置。顶部网页工具栏提供后退／前进，导航栏返回优先返回网页上一页；没有网页历史时，点击导航栏返回回到网站列表。“返回网站列表”按钮可直接退出当前网页。刷新作用于当前网页，新窗口链接在同一 WebView 内打开。原年龄确认保留，未确认时不加载远程内容。

实现：[入口及浏览器](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/RGNSFWController.swift)。

## 新增字体

新增独立的 Anthropic 和 Google 字体组：

- Anthropic Sans、Anthropic Serif：来自 Anthropic 官网当前引用的原始 Web 字体，包含独立的正体和斜体。
- Google Sans、Google Sans Flex、Google Sans Code：来自 Google 官方固定发行版本，保留原始字体和 OFL／商标说明。

这五款均按需下载，不将字体二进制放入安装包。Anthropic 字体直接从原官方站点下载；仓库仅记录来源、大小和校验值，不保存或镜像其二进制。Google 字体在仓库中保留测试夹具，但不进入发行资源。新增字体可独立覆盖英文字体，中英混排继续由中文选择负责汉字和中文标点。

可变字重映射 Regular／Medium／Semibold／Bold，光学尺寸按实际字号限制在支持范围内。独立斜体使用实际斜体文件，Google Sans Flex 使用其 slnt 轴。下载后保存离线缓存，选择状态及应用范围沿用既有设置。

实现：[字体目录](../Regram/RGTypography/RGFontCatalog.json)、[存储与字体选择标识](../Regram/RGTypography/Sources/RGFontStore.swift)、[变量轴加载](../Regram/RGTypography/Sources/RGTypography.swift)、[字体设置](../Regram/RGProUI/Sources/RGFontSettingsController.swift)。

## 验证边界

[输入主机检查](../submodules/TelegramUI/Tests/RGNicknameMentionInputTests.py)使用生产用户名扫描器及昵称构造器，配合确定性账号模型；覆盖用户名、粗体、代码／链接／邮箱／命令排除、UTF-16 与用户引用属性。字体存储主机检查新增目录字体的选择标识及正体／斜体路由。五款新增字体的九个文件均通过 CoreText 解析、400／500／600／700 字重和斜体检查；全部 92 个字体文件的大小及 SHA-256 匹配目录。

按要求未使用模拟器或真机；实际账号解析、输入框点击效果、网页右滑及 iOS 设备上的字体呈现仍需真机确认。编译和最终包校验记录在构建产物的 `BUILD-MANIFEST.json`。

最终 b34582 参考 IPA 检查通过：主程序和六个扩展，12 个 arm64 Mach-O 严格 ad-hoc 签名，12 份 dSYM 匹配，最低 iOS 15.0，0 个描述文件。身份及 App Group／entitlements 匹配 b34581。92 个按需字体二进制均未进入安装包，字体目录及许可原文与源码哈希一致。

参考 IPA：88,755,545 字节（88.76 MB）；SHA-256：`0ba50ced65024409267d7332706f698d1ee5f9c08823158810769e61c0e76922`。
