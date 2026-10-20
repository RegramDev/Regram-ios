# Nagram-iOS 更新对照与本地置顶丢失排查

审查日期：2026-10-20。Regram 基线为 `bc99591dd9`（13.0 / b34620）；Nagram 对照到 `fa29656a2427`，最新发行版为 [13.0.1 / 33357](https://github.com/NextAlone/Nagram-iOS/releases/tag/v13.0.1-33357)。检查了近期提交的实际补丁和 Regram 对应实现，下面的优先级是本次源码对照的判断，不表示 Nagram 的设备测试已在 Regram 上通过。

本篇记录的首轮修正只修改置顶保留逻辑并补充回归；当时其他条目列为后续候选。b34621 已进一步接入聊天与界面增强，并通过完整 arm64 Release 构建，当前范围与验证记录见[实现清单](chat-and-interface-tools.md)。

后续已向前追查早期功能，参见[历史功能缺口对照](nagram-feature-gaps-2026-10-20.md)。该清单重点区分 Regram 缺少的增强、已有能力的细分差异与不应重复移植的功能。

## 置顶过一两天后减少

用户反馈：添加超过六个置顶时立即显示正常，一至两天后只剩六个。代码中没有按天清理置顶的定时器；已重现的是**账号状态重置触发的聊天列表重建丢失**，与这种延后出现的现象一致，但仍需用户设备确认是否为实际触发路径。

原有路径：

1. 本机保留超过账号服务端额度的置顶，只同步额度内的部分。额度取账号真实 Premium 标志及服务端配置，不固定为六个。
2. `ResetState.swift` 重建聊天列表时，先把云端会话标为未包含，并清掉普通／归档列表。
3. 随后调用 `rgSetServerPinnedItemIds`。原实现将已保存的超额置顶与此时的可见置顶取交集；列表刚被清掉，交集为空，于是同时删除超额置顶记录。
4. 归档列表另行拉取，原流程也没有在重建后恢复归档的本地置顶。

另一个薄弱点是记录原先写入 `UserDefaults.standard`：主应用和通知／分享等扩展有各自的偏好域，不能依赖它作为共享账号数据库中置顶状态的依据。

本次修正：

- 超额置顶顺序存入账号 Postbox preferences，与本机置顶操作同一事务提交，各进程随账号数据库读取。
- 兼容读取旧偏好记录；扩展先运行且读不到旧偏好时，可从仍存在的完整置顶列表推导超额部分。显式取消置顶保存空记录，避免旧偏好再次恢复它。
- 重建前保留普通及归档列表的本地记录，重建后恢复；没有旧排序锚点时，将本地部分接在服务器置顶之后。
- 服务器完整列表不删除秘密聊天置顶；普通刷新排除已移到其他列表或已移除的聊天。

旧逻辑回归失败，新逻辑通过：普通／归档重建、归档后续拉取、50 次重复同步、数据库适配器重新打开、扩展偏好为空、旧记录迁移、主动取消、账号隔离、移组／移除、秘密聊天及真实 Premium 额度。测试编译真实策略源码，账号数据库和进程环境使用适配器；不是实际 iOS 扩展或真实账号验收。

验证命令：

```sh
python3 Regram/RGSimpleSettings/Tests/run-local-pinned-chats-checks.py --baseline
python3 Regram/RGSimpleSettings/Tests/run-local-pinned-chats-checks.py
python3 build-system/check-regram-features.py --output build-input/pin-fix-checks
```

第一条专门验证旧版失败，预期非零退出；第二条验证修正后行为。完整本地检查共 37 项通过，五个变动 Swift 文件通过语法检查。尚未完整编译 `//Telegram:Regram`，未生成新版 IPA，也未在真机持续一至两天验收。已被旧版彻底删除的本地记录无法由服务端补回，升级后可能需要重新置顶一次。

Nagram 最近的[文件夹置顶未读数修复](https://github.com/NextAlone/Nagram-iOS/commit/9acb93bae0cd)解决重复计数，与本次丢失不同；其[本地突破置顶上限需求](https://github.com/NextAlone/Nagram-iOS/issues/63)也不能作为已有修复引用。本次修正依据 Regram 自己的数据路径实现。

## 建议优先吸收的修复

以下均已检查对应源码；“仍有”表示 Regram 存在相同或相关代码路径，不表示已在用户设备重现。

| 顺序 | 候选与来源 | Regram 对照结果 | 建议与验收重点 |
| --- | --- | --- | --- |
| 1 | [文件夹置顶未读数重复](https://github.com/NextAlone/Nagram-iOS/commit/9acb93bae0cd) | `TabBarChatListFilterController.swift` 在无秘密聊天时直接返回原数组，随后遍历 `includePeers.peers + pinnedPeers`，仍有重复计数条件 | 优先做窄修复并测试去重，避免整段替换；覆盖手动包含、分类、静音、归档与秘密聊天 |
| 2 | [LLM 接口路径无效导致崩溃](https://github.com/NextAlone/Nagram-iOS/commit/fe0634f64286) | `RGLLMTranslate.swift` 仍直接向 `percentEncodedPath` 写入用户输入，空格、非 ASCII 或查询参数可能触发 Foundation 断言 | 优先修 URL 解析，覆盖自定义翻译与总结接口、重复 `/v1`、查询参数及错误反馈 |
| 3 | [缺少 access hash 时已读同步空转](https://github.com/NextAlone/Nagram-iOS/commit/763eb69317bc) | `SynchronizePeerReadState.swift` 仍在无法生成 `Api.InputPeer` 时立刻 `.fail(.retry)` | 改为等待 peer 数据补齐；覆盖取消、账号切换、秘密聊天，以及补齐后能够继续同步 |
| 4 | [图片尺寸未知时布局崩溃](https://github.com/NextAlone/Nagram-iOS/commit/1cce0e13e0a3) | `TGMediaPickerGalleryPhotoItemView.m` 对原图／裁剪尺寸未作此校验，后续用于比例计算 | 补零尺寸与非有限值保护，覆盖 iCloud 未下载、粘贴图及编辑覆盖层 |
| 5 | [后台事务排空期间保留执行时间](https://github.com/NextAlone/Nagram-iOS/commit/10475eead4f9) | `SharedWakeupManager.swift` 没有对应 drain task，且还存在仅凭延时计时器允许事务继续的旧分支 | 价值高，但需连同该提交之前的后台事务门控修改审查；不能只摘这 31 行。需真机后台、来电、上传及多账号验证 |
| 6 | [引用保留空行与完整块](https://github.com/NextAlone/Nagram-iOS/commit/c20f34ca7ad7)／[普通折叠引用走消息实体](https://github.com/NextAlone/Nagram-iOS/commit/c239a9823d44) | 转换仍逐段添加引用属性、跳过空段；模型仍以 `guard !bq.collapsed` 将折叠引用排除在普通实体路径外 | 作为一组处理，覆盖发送、编辑、草稿、复制粘贴及非 Premium 账号；保留复杂富文本的上游约束 |
| 7 | [粘贴图片预览填满可见区域](https://github.com/NextAlone/Nagram-iOS/commit/2d718e9a8524) | 预览列表没有 `fitsContentToVisibleArea` 及对应可见区域计算 | 适合改善大块留白，覆盖单图、拼图、键盘、横竖屏及附件面板 |
| 8 | [自定义语言包不再被推荐语言覆盖](https://github.com/NextAlone/Nagram-iOS/commit/be9fbfb85f5b) | 聊天列表的语言推荐没有识别自定义语言包 | 可单独吸收提示抑制，检查官方语言、第三方包及首次登录；不等同于引入 iCloud 同步 |
| 9 | [多行设置输入框高度](https://github.com/NextAlone/Nagram-iOS/commit/86979cbd7d0d) | 尚无测量器与实际编辑器行高一致的处理；本地测量实现与对方提交基线也有差异 | 先复现长提示词、模型配置、中文及大字体截断，再适配测量路径 |
| 10 | [iPad 资料头像展开空间判断](https://github.com/NextAlone/Nagram-iOS/commit/5a1c34783564) | 本地仍主要依赖宽高判断，不能判断分栏中展开后还剩多少内容空间 | 推荐后续适配；覆盖横屏分栏、窄窗口及返回头像大图 |

建议第一批做 1–4，第二批集中处理 5–6；界面修复另成一批，便于回归与定位。

## 可加入后续功能计划

| 功能 | 来源 | 在 Regram 中的接入判断 |
| --- | --- | --- |
| 在聊天列表搜索框粘贴链接后直接打开 | [980b88c7a036](https://github.com/NextAlone/Nagram-iOS/commit/980b88c7a036) | 实用性较高，新增可解析链接的结果行，沿用 Regram 现有路由；需要防止误判普通关键词并校验邀请、私有频道与消息链接 |
| 单手搜索：聊天内搜索框置底、结果从底部开始 | [9faf62288045](https://github.com/NextAlone/Nagram-iOS/commit/9faf62288045)、[779b0e4e2545](https://github.com/NextAlone/Nagram-iOS/commit/779b0e4e2545) | 与现有底部搜索配置有关但并不相同；应保留独立开关，验证键盘、成员筛选、分页、结果跳转及 VoiceOver |
| 常驻格式条、选中文字菜单直接放常用格式 | [fd69df90784f](https://github.com/NextAlone/Nagram-iOS/commit/fd69df90784f)、[ef8f7e6663df](https://github.com/NextAlone/Nagram-iOS/commit/ef8f7e6663df)、[深色／壁纸可读性修正](https://github.com/NextAlone/Nagram-iOS/commit/e9e7b1d3dda2) | Regram 已有输入工具栏和默认格式，新增交互应复用现有设置与富文本入口，并同时处理主题及中文输入法 |
| 列表停在顶部时保持新消息会话可见 | [cb6ab819d93b](https://github.com/NextAlone/Nagram-iOS/commit/cb6ab819d93b) | 适合与超额置顶场景一起试用；需保证读旧会话、滚动中及大量置顶时不强制拉动列表 |

## 暂不直接照搬

- [列表事务限制嵌套深度](https://github.com/NextAlone/Nagram-iOS/commit/aa5f5aa04ad7)：Regram 当前 `endTransaction` 仍异步排到主队列，不能仅凭提交标题判断存在同样的递归栈溢出。对方补丁同时改变执行时序，先做队列顺序与性能实验。
- [iCloud 不再同步语言包](https://github.com/NextAlone/Nagram-iOS/commit/6c6f49aa0ef4)：Regram 没有对应的 Nagram iCloud 设置同步模块，没有相同接入点。语言推荐提示则有，已单独列入候选。
- 四页设置分类：Regram 已有九分类、全局搜索和设置深链；可以借鉴命名与位置，不宜整体替换。
- TestFlight 审核与分组发布流程：与当前 Regram 的 Actions IPA 分发流程不同。
- 13.0 钱包、网络及富文本基线：两边已基于 Telegram 13.0 维护，不按 Nagram 更新记录中的名称重复计为新增。Rust 引擎与第二动画后端属于独立工程，需要兼容与性能评估。
