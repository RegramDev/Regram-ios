# 按需字体、昵称提及与图库拷贝

后续 b34582 已将昵称转换移到输入过程，NSFW 改为网站列表及独立网页，并增加 Anthropic Sans／Serif 和 Google 字体。现行行为见[输入与网页导航修正](live-mentions-and-nsfw-navigation.md)。以下保留 b34581 的实现及验证记录。

b34581 延续 b34580 的中文／英文字体独立选择，改为按需下载或本地导入。

## 字体

Regram Pro → 更改字体保留英文、中文两个列表和“聊天内容／主要界面文字”勾选。带云图标的字体选中后开始下载，显示进度，支持取消；完整下载和校验成功后才应用。失败或取消会保留当前选择。已下载的字体可以离线使用，重启后无需重复下载。系统、圆体和系统衬线体不需要下载。

[下载目录](../Regram/RGTypography/RGFontCatalog.json)包含 83 个字体文件的固定来源、大小、SHA-256 和 Inter ZIP 成员信息。Inter 归档和每个解压成员分别校验；下载只解压指定成员。完整字体族通过临时目录一次发布，临时文件在完成、失败或取消后清理。字体从原官方仓库／发行版本获取，没有另行部署下载服务器。Git 中的字体文件作为离线测试夹具保留，发行包不包含这些字体二进制，只包含目录和许可原文。

“从文件导入字体”支持 TTF、OTF、TTC，最多 64 MB。文件离开文档提供者之前复制到本机，以内容校验值去重；通过 CoreText 检查后才加入列表。检测中文／英文覆盖范围，分别出现在可用的选择区。TTC 使用第一个字型。导入后需在对应列表选中，应用范围沿用已有勾选。导入文件不会上传。下载缓存不进入系统备份，用户导入的字体保存在应用支持目录。

字体缓存键包含下载版本及两套导入选择，下载完成后已显示的系统后备字体会刷新。中文字符集、英文字符集和系统 emoji 后备仍分开；代码、图标、大表情的独立字体路径延续已有规则。

实现：[存储与下载](../Regram/RGTypography/Sources/RGFontStore.swift)、[字体加载](../Regram/RGTypography/Sources/RGTypography.swift)、[设置界面](../Regram/RGProUI/Sources/RGFontSettingsController.swift)、[配置](../Regram/RGSimpleSettings/Sources/FontSettings.swift)。

## 手动输入昵称提及

开启 Regram Pro 的“按昵称提及”后，手动输入 `@username` 的普通消息及媒体说明也会在发送时尝试转换为昵称与 Telegram 原生 `TextMention(peerId:)`，点击可打开该用户资料。展示名称沿用现有提及选择器的姓名组合规则。不开启此设置时保持原行为。

仅转换可解析到的用户；频道、解析失败、超时或会超过消息／说明长度上限的替换保留原文。单批最多解析 16 个不同用户名，每个解析最多等待 4 秒。发送队列按顺序处理，处理保存的待发内容，不更改正在编辑的输入框。转发、机器人命令、代码块、已有昵称提及、链接、邮箱与自定义 emoji 保持原有内容。替换以 UTF-16 重算其他文字实体，保留格式、回复、排程、媒体及分组参数。

实现：[发送转换](../submodules/TelegramUI/Sources/RGNicknameMentions.swift)、[UTF-16 策略](../Regram/RGSimpleSettings/Sources/MentionReplacementPolicy.swift)、[发送接入](../submodules/TelegramUI/Sources/ChatController.swift)。

## NSFW 与图片

NSFW 页面添加“黄果”和“JAV Ranking”入口，使用用户指定的两个网址。源切换栏可横向滚动；其左侧返回按钮按网页历史返回，与导航栏退出页面分开。新窗口链接在当前网页视图内打开，已有年龄确认继续生效。

聊天图片的右上角更多菜单新增“拷贝”。使用完整图片资源；未下载完成时显示可取消的等待提示，成功写入图片剪贴板后提示完成。沿用图库已有的付费／禁止拷贝内容条件，阅后即焚图片不提供该操作。

## 验证

- Foundation 主机检查覆盖中文、emoji、多个昵称、格式和实体偏移、字体下载版本的缓存失效以及应用范围。
- [字体存储检查](../Regram/RGTypography/Tests/run-store-checks.py)使用生产存储源码、真实 ZipArchive 与本地 HTTP 夹具；仅替换测试目录、资源 Bundle 和设置通知适配器。覆盖直接下载、ZIP 下载、哈希不符、HTTP 404、取消、本地导入、重复导入、无效字体与中文覆盖检测，无需模拟器。
- 83 个源字体均由 CoreText 解析；导入后的文件仍可解析。使用生产字体合成代码检查了 Latin、中文和 emoji 的独立字体选择。
- 完整 `//Telegram:Regram` arm64 Release 构建与最终 IPA 检查结果在本次构建产物的 `BUILD-MANIFEST.json` 中记录。按用户要求跳过模拟器；未在真机验证网页返回、字体选择、实际账号提及通知和跨应用图片粘贴。

发布包检查：b34581 参考 IPA 为 88,732,067 字节（88.73 MB），比 b34580 的 134,950,360 字节减少 46.22 MB。最终包已重新解包验证：主程序和六个扩展、12 个 arm64 Mach-O 的严格 ad-hoc 签名、12 份 dSYM、最低 iOS 15.0、0 个描述文件；安装身份与 App Group／entitlements 匹配 b34580。83 个可下载字体不在发行包中，下载目录及 11 份许可文件的哈希匹配源码。

参考 IPA SHA-256：`faeb4792e0bb34adb7a2f1ada78d13b3596b395959dbcb376f6bfe07e68f1594`。
