# Regram

[English](README.en.md) · 简体中文

Regram 是基于 Telegram iOS 源码维护的非官方客户端，提供消息管理、隐私控制、翻译与语音识别和界面定制。

当前分支为 **regram-beta / 13.1.1 / b34638**。Beta 安装包见 [Actions 构建](https://github.com/RegramDev/Regram-ios/actions/workflows/build.yml?query=branch%3Aregram-beta)。本轮同步主线 b34631–b34638 的适用功能，包括本地礼物与资料定制、消息搜索、每日首次启动任务、启动与网络崩溃修正、引用选区和频道备注，并加入 XChat 可选应用图标。同步范围与检查见 [Beta 同步记录](docs/beta-sync-20261028.md)、[功能清单](docs/features.md)及[更新记录](docs/changelog.md)。

## 功能

### 消息与聊天管理

- 不限数量的聊天置顶，支持普通列表与归档的本机排序；超过 Telegram 账户额度的部分仅保存在本机。
- 最近会话：按账号保存最近 50 个打开过的聊天，支持快速返回与清空记录。
- 群聊与频道备注：从资料页设置本机显示名称，按账号保存，用于聊天列表、标题及本地搜索；清空后恢复原名。
- 消息书签与标签：长按消息添加，在设置首页「我的收藏」下方管理，支持标签筛选、编辑及返回原消息。
- 双击消息动作：回应、查看回应、回复、复读、无引用复读、翻译、编辑或关闭；无法编辑的消息可以单独设置。
- 消息菜单管理：启用、隐藏和排序真实可用的操作，按消息类型与账户权限展示。
- 查看此人在当前会话或话题中的所有消息：长按头像进入独立分页页面，支持关键词搜索、清空恢复全部消息及返回原消息。
- 共同群组发言：从个人资料页「更多」进入，汇总对方在共同群组内的可搜索消息，支持按群筛选、分页及返回原消息。
- 编辑历史：保存本机观察到的文本、说明、实体、结构化富文本和图片替换前的版本；补齐富文本缓存不产生虚假编辑，支持图片预览与持久存储。
- 自动显示剧透文字、图片和视频，默认关闭；显示群组／频道消息 ID、时间秒数及转发消息原始时间。
- 加入群组／频道后选择分组，记住上次分组，调整分组位置、标签及聊天列表显示；分组标签的本机开关跨重启保留。
- 独立的「每日首次启动」任务：在定时发送的重复菜单选择一次，从所选日期起每天首次打开时静默发送，当天不重复；按账号保存在本机，支持编辑、删除和立即发送。会员原生每日／每周等服务端定时保持原有行为。

本轮聊天、分组、搜索与界面增强的入口及逐项状态见[实现清单](docs/chat-and-interface-tools.md)。新增分享文件夹、群资料管理项、批量撤销邀请、搜索链接与独立隐私选项。格式工具栏保留原样。

### 过滤与隐私

- 关键词及正则过滤，支持隐藏／保留规则、全局或会话范围、规则测试、导入与导出。
- 隐藏指定发送者，按会话关闭规则过滤，或临时显示被隐藏内容。
- 全局／会话独立防撤回及本地撤回记录，部分自动删除和媒体保存控制。
- 已撤回消息标记可选图标、文字或隐藏，自定义文字及颜色，并实时刷新已显示消息。
- 幽灵模式：控制动态浏览、在线状态及输入状态上报。
- 用户 ID 提及链接、设置页手机号隐藏、资料 ID、DC 地区及注册日期估算。
- 通知内容过滤，置顶及提及／回复通知策略，空提醒容错与过滤权限诊断。
- Regram Pro → 通知与提醒提供实验性通知恢复，默认关闭并保留旧配置；`tg://rg/rgdebug` 仍提供缓存清理，保留账号、数据库、设置。

防撤回和编辑历史只能保留本机已经收到或观察到的内容。幽灵模式不包含普通聊天已读回执屏蔽；客户端选项不能授予 Telegram 服务端或 iOS 尚未授权的能力。

### 翻译、总结与语音识别

- Telegram、Apple、Google、Google CN、Microsoft、Yandex、腾讯 TranSmart 等翻译路径。
- LLM 翻译：OpenAI Chat Completions／Anthropic Messages 格式，自定义接口、模型列表、模型测试、提示词、温度及可选聊天上下文。
- 单条消息、聊天内容、发送前及应用内网页翻译，保护链接、代码和文字格式；网页可取消翻译或恢复原文。
- 消息总结默认关闭，使用独立接口、模型、提示词及密钥；支持最近一小时、今天、最近一天、自定义时间范围，以及单条或多选文字，提交前确认上传内容。
- 总结时间范围最多 5000 条、64,000 字节文字；单条／多选最多 100 条，超出范围要求调整，不静默截断。不上传媒体，排除秘密聊天、一次性及受保护内容。
- 语音转文字可选 Telegram、Apple 或自定义 OpenAI-compatible Transcriptions API；支持语音消息和圆视频音轨、接口测试、语言及提示词。
- 转写结果显示在原消息中，可复制、继续翻译、取消或重新识别。

自定义识别由用户主动发起，排除秘密聊天和一次性媒体；音频转为 M4A，上传上限 25 MB。API Key 保存在本机钥匙串，不进入设置备份。第三方 API 的连通性、额度和费用由所选服务商决定。

### 媒体与链接

- 链接预览修复：X／Twitter、Instagram、TikTok、Reddit、Bluesky、Pixiv 等域名规则，支持缓存、更新及自定义 X／Instagram 预览服务域名；保留消息原链接。
- 静态贴纸保存为 PNG，动画／视频贴纸转为 GIF 后保存到相册。
- 贴纸包 ZIP 备份：原始 WebP／PNG、TGS、WebM 文件及顺序、表情元数据；最多 500 个文件、32 MiB／文件、256 MiB／包。
- 单条消息截图：头像在左，名字与正文在右侧上下排列，保留媒体，不带气泡背景，避免名字重复或缺失；通过系统分享保存或发送。
- 媒体信息：分辨率、格式／编码、码率、帧率、时长及大小，缺失字段显示未知。
- 照片质量与大图发送；粘贴图片默认 HD、最高 JPEG 质量，照片尺寸上限 2560px。
- 贴纸大小与最近贴纸数量、相机和录制、上传／下载及默认视频画质选项。
- 视频播放器底部集中显示后退 15 秒、播放／暂停、快进 15 秒；小窗、倍速及画质从右上角菜单进入。
- 普通全屏视频在回桌面或锁屏后暂停并保留进度，底部播放／暂停图标随实际状态切换；已开启的画中画保留播放行为。
- 可选媒体加载试验：预取、播放准入、播放器复用及首帧交接，可使用同一安装包对照。

预览效果取决于 Telegram 和第三方服务。贴纸备份不等于恢复已删除的服务端贴纸包；媒体加载试验的实际收益需要设备对照。

### 外观与输入

- 设置及 Regram 新增功能页统一使用 Telegram 主题、分组列表与玻璃导航，保留原有返回手势；旧系统沿用上游回退样式。
- 应用图标、截图 App Badge；Regram Pro 入口跟随当前 App 图标，登录欢迎页使用 Regram 图片。
- 图标切换成功后同步并保存选中项，冷启动恢复 Pro 入口与外观页图标，延后校对系统读值；切换失败及过期回调不覆盖已有选择。
- 底栏沿用上游 Telegram 的组件、动画与手势，支持实时预览、拖动排序、标签显隐、独立按钮及自动／手动宽度。
- 聊天与设置必须保留，底栏整体居中，自动宽度随导航项数量收紧。搜索开关位于「显示项目」，默认关闭；使用 Swiftgram 原生右侧按钮与展开输入框，搜索当前页，通话页打开新通话选择器。隐藏后仍可进入设置，从内容区域右滑返回聊天，过渡跟随手指并支持取消回弹；取消隐藏即时恢复。
- 聊天列表分隔线开关、紧凑显示、一／二行正文预览及配色选项；旧三行配置与备份自动归为两行。
- 拉丁与中日韩字体分别选择，支持下载、导入 TTF／OTF／TTC、预览、管理及缺字回退。
- 输入工具栏、默认文字格式、盘古空格、回车发送及会话独立输入设置；盘古之白集中为接收、发送、编辑三个独立开关。
- 富文本编辑与渲染：标题、引用、代码、列表、表格、链接、媒体和草稿；关键词过滤、总结、翻译、无引用复读及本机预览使用完整正文，发送仍遵循账户权限。
- 「显摆一下」提供本地会员、星币／TON、礼物与装扮、手机号、正负评级和 TON 资料卡。普通礼物保持直接结算；本地限定礼物可在原生详情中升级，引用名称与首页礼物状态同步本机装扮。
- 用户资料角色徽章：开发者、核心测试及赞助者。

### 网络与诊断

- DC1–DC5 连接测试位于独立二级页面：首次连接请求、三次时延采样、平均／最低时延、波动及失败次数，显示当前连接方式和所属 DC。
- DC 地区标签：DC1／3 Miami、DC2／4 Amsterdam、DC5 Singapore；复制只输出五个 DC 的平均 Ping，并立即反馈。
- 三种解析方式：内置 HTTPS DNS、系统 DNS、自定义 DoH；自定义默认关闭，系统 DNS 与 DoH 使用同一设置，避免冲突。
- 五种 IP 策略：自动、仅 IPv4、优先 IPv4、优先 IPv6、仅 IPv6；优先模式允许回退，仅模式严格限制地址族。
- 内置 Google／Cloudflare HTTPS 解析；自定义支持 DNS JSON 及地址查询的 DNS 报文兼容，也用于备用 DC 配置 TXT 查询，保留签名和有效期校验。
- 域名代理保留多个地址，按策略尝试；失败或四秒未响应时轮换，重新握手，短时缓存成功地址。
- 独立 A／AAAA 测试页显示解析地址、策略筛选及耗时，可取消，不读取应用内 DNS 缓存；保留媒体传输统计和过滤性能测试。

IP 策略约束原生 Telegram DC 和 SOCKS5／MTProto 代理连接；网页、HTTP 接口和 Web 代理仍使用系统网络。自定义 DoH 失败不降级到系统解析，解析服务自身域名仍由系统引导。DNS 耗时不等于 DC Ping，地区标签不代表用户所在地。

### 登录与备份

- 彩色二维码登录：令牌刷新、数据中心迁移、两步验证与失败重试；仍需能够连接 Telegram。
- 不设本机登录账号数量上限；服务端登录及风控规则仍适用。
- 按类别备份／恢复 JSON 设置，支持导入预览；不包含登录会话、聊天数据库、证书、API Key 或字体文件。
- 本地 Premium 显示、缓存管理、离开 5 秒自动锁定及清除全部本地数据；清除前确认，避免启动阶段白屏和弹窗提前消失。

## 设置入口

功能配置集中在 **设置 → Regram Pro**，首页按九个分类与「显摆一下」专区组织：

| 分类 | 内容 |
| --- | --- |
| 聊天与消息 | 消息总结接口、消息动作、聊天列表、分组 |
| 输入与发送 | 输入工具、默认格式、发送方式、会话独立输入设置 |
| 翻译与语音 | 翻译服务、LLM、自定义识别、转写方式 |
| 隐私与过滤 | 规则、隐藏用户、防撤回、撤回记录、幽灵模式、动态 |
| 媒体与链接 | 预览修复、照片、贴纸、录制、播放 |
| 外观与界面 | 字体、图标、截图标记、底栏、资料显示 |
| 通知与提醒 | 实验性通知恢复、内容过滤、置顶、提及与回复 |
| 网络与传输 | DNS／IP、传输参数、通话连接、性能及 DC 测试 |
| 显摆一下 | 本地会员、星币／TON 礼物模拟、手机号、评级和资料卡 |
| 管理与工具 | 备份、数据清理 |

分类内直接展示基础设置，聊天与消息、媒体与链接通过文件夹式原生横栏切换相关选项；底栏路径为「Regram Pro → 外观与界面 → 底栏布局」。复杂编辑器保留独立页面。

Pro 内的全局设置搜索放在首页，覆盖分类与高级页面，点击结果打开并定位对应项；分类页不重复放置搜索或常用区。长按设置项可复制设置深链，链接只包含页面和控件标识，不包含保存值。书签管理入口独立放在设置首页「我的收藏」下方。

设置页右下角原生搜索与 Pro 首页共用设置目录、别名和页面定位；支持无结果、清空恢复及输入法组合文字。共同群组分页、拖动预览与顶部标记修正见[本轮记录](docs/groups-settings-search-drag-fixes.md)。

## 构建与校验

本分支同步主线 **13.1.1 / b34638** 的适用功能，保留 `com.regram.app`／`group.com.regram.app` 和无应用内更新安装的分支约定。本轮仅同步源码及相关检查，未构建 Beta 安装包或进行真机验收，也未触发 CI 构建；主线的包校验与发布记录不代表 Beta 包验收。详见 [Beta 同步记录](docs/beta-sync-20261028.md)。

## 构建

需要 macOS、完整 Xcode 27.1、Python 3 和 Git。版本要求见 [versions.json](versions.json)，构建目标为 **//Telegram:Regram**。13.1.1 上游同步及兼容检查范围见[同步记录](docs/upstream-sync-20261023.md)。

```sh
git clone --branch regram-beta --recursive https://github.com/RegramDev/Regram-ios.git
cd Regram-ios
git submodule update --init --recursive
```

按[兼容补丁说明](build-system/patches/README.md)检查并应用 rules_apple 补丁：

```sh
git -C build-system/bazel-rules/rules_apple apply --check ../../patches/rules_apple-local.patch
git -C build-system/bazel-rules/rules_apple apply ../../patches/rules_apple-local.patch
```

复制模板到被 Git 忽略的 `build-input/`，保留本分支的 Bundle ID `com.regram.app`，填写自己的 Telegram API 凭据和 Team ID。Telegram API 凭据可从 [my.telegram.org](https://my.telegram.org/apps) 申请。

```sh
mkdir -p build-input
cp build-system/template_minimal_development_configuration.json build-input/regram-development.json
```

生成模拟器项目：

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir="$PWD/build-input/bazel-cache" \
  generateProject \
  --configurationPath=build-input/regram-development.json \
  --xcodeManagedCodesigning --disableProvisioningProfiles
```

构建真机 IPA，使用与主应用和六个扩展匹配的签名材料：

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir="$PWD/build-input/bazel-cache" \
  build \
  --configurationPath=build-input/regram-development.json \
  --codesigningInformationPath=build-input/codesigning \
  --buildNumber=10001 --configuration=release_arm64 \
  --target=//Telegram:Regram
```

输出为 `bazel-bin/Telegram/Regram.ipa`。需要给 LCSign 等工具处理的 ad-hoc 参考包时，按[参考包说明](docs/lcsign-reference-packaging.md)打包。覆盖升级需保留相同的应用身份和数据容器。

`--overrideXcodeVersion` 只跳过版本检查，不保证工具链兼容。不要提交 API 凭据、证书、描述文件、IPA 或真实账号数据。

## 文档与贡献

- [完整功能、入口及限制](docs/features.md)
- [近期更新记录](docs/changelog.md)
- [文档导航](docs/README.md)
- [富文本输入](docs/richtext-composer.md)
- [UI 测试](docs/ui-testing.md)
- [贡献指南](.github/CONTRIBUTING.md)

Regram 与 Telegram 官方没有隶属关系。分发修改版请遵守仓库及第三方依赖的许可证，并明确标识为非官方客户端。

本分支使用 `com.regram.app` 和 `group.com.regram.app`，主应用与六个扩展共享声明的 App Group，不包含应用更新下载、证书导入和 IPA 安装功能。

源码基线采用 [Telegram 官方主线 master](https://github.com/TelegramMessenger/Telegram-iOS/tree/master) 的 `fb0e62ba8a147f0821da6aa63c09da7d79a10111`（13.1.1），在此基础上维护 Regram 功能；本仓库的 `regram-beta` 是独立产品分支名称。
