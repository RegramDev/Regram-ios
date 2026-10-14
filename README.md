# Regram

[English](README.en.md) · 简体中文

Regram 是基于 Telegram iOS 源码维护的非官方客户端，提供消息管理、隐私控制、翻译与语音识别和界面定制。

## 功能

### 消息与聊天管理

- 不限数量的聊天置顶，支持普通列表与归档的本机排序；超过 Telegram 账户额度的部分仅保存在本机。
- 最近会话：按账号记录最近打开的聊天，支持快速返回与清空记录。
- 群聊备注：在群资料页设置本机显示名称，按账号保存，用于聊天列表、标题及本地搜索；可清空恢复原群名。
- 消息书签与标签：长按消息添加书签及标签，按账号保存，在书签页筛选、编辑并跳回原消息。
- 双击消息动作：回应、查看回应、回复、复读、无引用复读、翻译、编辑或关闭；无法编辑的消息可以单独设置。
- 消息菜单管理：隐藏、启用和调整真实可用操作的顺序，按消息类型与账户权限展示。
- 查看发送者在当前会话或话题中的所有消息：长按头像进入独立分页页面，并可跳回原消息。
- 保存已收到消息的编辑历史，记录文本、说明、实体变化及图片替换前的版本；支持图片预览和放大。
- 自动显示剧透文字、图片和视频，可在消息动作与显示中开启，默认关闭。
- 显示群组／频道消息 ID、消息时间秒数、转发消息的原始时间。
- 加入群组或频道后选择分组，记住上次使用的分组，调整分组标签和聊天列表显示。

### 过滤与隐私

- 关键词与正则过滤，支持隐藏／保留规则、全局或会话范围、规则管理和导入导出。
- 隐藏指定发送者，按会话关闭过滤，临时显示已隐藏内容。
- 防撤回及撤回记录、会话独立防撤回、部分自动删除与媒体保存控制。
- 幽灵模式：控制动态已读、在线状态和输入状态的上报。
- 提及用户时使用用户 ID 链接，隐藏设置中的手机号，显示资料 ID、数据中心与注册日期估算。
- 通知过滤、置顶通知及提及／回复通知策略。

防撤回和编辑历史只能保存本机已经收到或观察到的内容，不能恢复此前未收到的消息版本。客户端选项不会提供 Telegram 服务端尚未授予的权限。

### 翻译与语音识别

- Telegram、Apple 与外部翻译路径；支持 Google、Google CN、Microsoft、Yandex、腾讯 TranSmart。
- LLM 翻译：OpenAI Chat Completions／Anthropic Messages 格式，自定义地址、模型列表、模型测试、提示词、温度和可选聊天上下文。
- 单条消息、聊天内容和发送前翻译；保留链接、代码及文字格式。
- 应用内网页翻译：在浏览器菜单选择翻译网页，沿用当前翻译服务及应用语言；支持取消和恢复原文。
- 语音转文字可选择 Telegram、Apple 或自定义 OpenAI-compatible Transcriptions API。
- 自定义语音识别支持语音消息和圆视频音轨；可设置接口、模型、语言及提示词，并使用内置音频测试。
- 识别文字显示在原消息中，可复制、继续翻译、取消或重新识别。

自定义识别仅上传用户主动选择的消息，排除秘密聊天和一次性媒体；音频先转成 M4A，上传上限为 25 MB。API Key 保存在本机钥匙串，不进入设置备份。第三方 API 的可用性与费用由所选服务商决定。

### 媒体与链接

- 链接预览修复：支持 X／Twitter、Instagram、TikTok、Reddit、Bluesky、Pixiv 等域名规则，支持规则缓存与更新。
- 修复仅改变预览请求，保留消息里的原链接；X／Instagram 可配置预览服务域名。
- 静态贴纸保存为 PNG，动画／视频贴纸转为 GIF 后保存到相册。
- 查看媒体分辨率、格式／编码、码率、帧率、时长及文件大小。
- 照片质量与大图发送选项；粘贴图片默认使用 HD 和最高 JPEG 质量，保留最高 2560px 的照片尺寸。
- 贴纸大小与最近贴纸数量、录制与摄像头选项。
- 下载、上传及播放设置，默认视频画质和媒体加载试验开关。
- 视频播放器底部集中显示后退 15 秒、播放／暂停和快进 15 秒；小窗、倍速及画质从右上角菜单进入。

链接预览的最终效果还取决于 Telegram 和第三方预览服务；未读取到的媒体字段显示为未知。

### 外观与输入

- 应用图标、设置入口图标与截图标记；Regram Pro 入口同步当前选择的 App 图标。
- 拉丁与中日韩字体分别选择，支持下载字体和导入 TTF／OTF／TTC、预览、管理及缺字回退。
- 底栏布局：实际底栏组件预览、拖动排序、标签显隐、独立按钮、自动或手动宽度；聊天和设置必须保留，整体居中。
- 聊天列表行数、紧凑显示、分隔线开关及配色选项。
- 输入工具栏、默认文字格式、会话独立输入设置、盘古空格和回车发送。
- 富文本编辑与渲染：标题、引用、代码、列表、表格、链接、媒体及草稿。
- 用户资料角色徽章：开发者、核心测试和赞助者。

### 登录与备份

- 彩色二维码登录，支持令牌刷新、数据中心迁移、二步验证与失败重试。
- 不设本机登录账号数量上限；服务端登录与风控规则仍适用。
- 按类别导出和恢复 JSON 设置备份；不包含登录会话、聊天数据库、证书或 API Key。
- DC1–DC5 连接测试：独立二级页面显示首次连接请求、三次时延采样、平均／最低时延、波动和失败次数；可取消，复制只保留五个 DC 的平均 Ping。
- 媒体传输与过滤规则诊断、字体缓存管理和本地数据清理。

## 设置入口

所有 Regram 功能设置统一位于 **设置 → Regram Pro**，首页仅显示以下分类：

| 分类 | 内容 |
| --- | --- |
| 聊天与消息 | 书签与标签、消息动作、聊天列表及分组 |
| 输入与发送 | 输入工具、默认格式、发送方式及会话独立输入设置 |
| 翻译与语音 | 翻译服务、LLM、自定义语音识别及转写方式 |
| 隐私与过滤 | 过滤规则、隐藏用户、防撤回、撤回记录、幽灵模式及动态 |
| 媒体与链接 | 预览修复、照片、贴纸、录制及播放 |
| 外观与界面 | 字体、应用图标、截图标记、底栏与资料显示 |
| 通知与提醒 | 通知过滤、置顶通知及提及／回复策略 |
| 网络与传输 | 上传／下载参数、通话连接、性能与传输及 DC 测试 |
| 管理与工具 | 本地会员、配置备份与数据清理 |

每个功能只保留一个设置入口，功能较多的分类进入二级页面；仅 Regram Pro 首页提供覆盖全部设置的搜索，结果直接进入对应页面并定位设置项；分类页和子页不添加设置搜索框，不保留常用功能区。支持长按设置项复制深链，链接仅包含页面和设置标识。

语音识别位于 **翻译与语音 → 语音转文字**；LLM 位于 **翻译与语音 → 翻译 → LLM 翻译**；链接预览修复位于 **媒体与链接**。

## 构建

需要 macOS、完整 Xcode、Python 3 和 Git。版本要求见 [versions.json](versions.json)，构建目标为 **//Telegram:Regram**。

```sh
git clone --recursive https://github.com/RegramDev/Regram-ios.git
cd Regram-ios
git submodule update --init --recursive
```

按[兼容补丁说明](build-system/patches/README.md)检查并应用 rules_apple 补丁：

```sh
git -C build-system/bazel-rules/rules_apple apply --check ../../patches/rules_apple-local.patch
git -C build-system/bazel-rules/rules_apple apply ../../patches/rules_apple-local.patch
```

复制模板到被 Git 忽略的 `build-input/`，填写自己的 Bundle ID、Telegram API 凭据和 Team ID。Telegram API 凭据可从 [my.telegram.org](https://my.telegram.org/apps) 申请。

```sh
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

`--overrideXcodeVersion` 只跳过版本检查，不保证工具链兼容。不要提交 API 凭据、证书、描述文件、IPA 或真实账号数据。

## 文档与贡献

- [完整功能、入口及限制](docs/features.md)
- [文档导航](docs/README.md)
- [富文本输入](docs/richtext-composer.md)
- [UI 测试](docs/ui-testing.md)
- [贡献指南](.github/CONTRIBUTING.md)

Regram 与 Telegram 官方没有隶属关系。分发修改版请遵守仓库及第三方依赖的许可证，并明确标识为非官方客户端。

本分支使用 `com.regram.app` 和 `group.com.regram.app`，主应用与六个扩展共享声明的 App Group，不包含应用更新下载、证书导入和 IPA 安装功能。

源码基线采用 [Telegram 官方主线 master](https://github.com/TelegramMessenger/Telegram-iOS/tree/master) 的 `f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838`（13.0），在此基础上维护 Regram 功能；本仓库的 `beta` 是独立产品分支名称。
