# Regram 上游同步与合并方案

## 1. 目标

本方案用于长期同步官方 `TelegramMessenger/Telegram-iOS`，同时保留 Regram 功能，并把每次升级的冲突从“整个产品一次性冲突”拆分为“按功能处理的有限冲突”。

核心目标：

- 官方 Telegram 是唯一活跃上游。
- 不直接把新上游合并进当前高度修改的 legacy 工作树。
- Regram 改动按功能形成可重放、可测试、可删除的补丁序列。
- 每次发布都保留不可变的源码、IPA、dSYM 和回滚点。
- 上游结构发生变化时，优先适配新结构，不长期保留旧 Telegram 实现。

非目标：

- 不追求与 Telegram 每个提交实时同步。
- 不继续同时跟踪 Telegram 和 Swiftgram 两个活跃上游。
- 不把所有 Regram 改动重新压成一个五万行的大提交。

## 2. Swiftgram 的实际更新方式

Swiftgram GitHub 历史表明，它并不是持续将 Telegram merge 到产品分支中，而是在每个版本重新建立产品树：

1. 选择新的官方 Telegram 提交作为基线。
2. 在该基线上应用一个完整的 Swiftgram 差异快照。
3. 提交一个 `Swiftgram Version X` 大提交。
4. 在其后追加少量修复。
5. 使用 `release/*` 分支保存旧版本。

以当前公开的 Swiftgram master 为例：

- 官方 Telegram 基线：`6ad963e5b62d354da79040f388ae2b9132fb17b8`
- 第一个 Swiftgram 提交：`5ed59da88839fb8cd802e5bf181ce4293044c8c1`
- Swiftgram master：`cf8b23beaaac4126a396337ac2d5be13f9f76b66`
- master 只比官方 Telegram 多 6 个提交。
- 第一个 Swiftgram 提交修改约 1,035 个文件，约 `+53,465/-2,798` 行。
- Swiftgram 独有历史中没有正常的 Telegram 上游 merge commit。

这证明“在新上游基线上重新应用产品差异”是可行的，但单个巨大快照难以审查、定位和独立回滚。Regram 采用相同的重建方向，但将快照拆成有边界的功能补丁。

## 3. 上游和分支模型

### 3.1 远端职责

- `telegram`：官方 `TelegramMessenger/Telegram-iOS`，唯一活跃上游。
- `origin`：Regram 自有仓库。
- `swiftgram`：只用于历史追溯和行为对照，不再参与日常同步。

### 3.2 推荐分支

- `regram/main`：当前集成版本。允许在新上游版本发布时重放补丁并更新提交历史。
- `sync/telegram-<version>-<sha>`：一次上游同步的工作分支。
- `release/regram-<version>-<build>`：已发布版本，只允许紧急修复，不重写历史。
- `archive/legacy-<date>`：迁移前旧架构的冻结分支。

### 3.3 历史策略

- `release/*` 永远不可变，是正式发布和回滚依据。
- `regram/main` 是集成指针，不作为长期发布凭证。
- 如果需要重写 `regram/main`，只能在创建 release/archive 回滚点、CI 全部通过并通知协作者后使用 `--force-with-lease`。
- 禁止对 `release/*` 使用 force push。

## 4. Regram 补丁序列

Regram 改动应按以下顺序组织。每一组可以包含多个小提交，但不能与其他组混合。

1. `00-build-branding`
   - App target、Bundle ID、图标、资源、Info.plist、Watch、扩展和构建产物名称。
2. `01-platform`
   - App Group、重签名兼容、entitlement 检测、日志和共享容器定位。
3. `02-settings-storage`
   - `RGSimpleSettings`、设置迁移、共享 UserDefaults 和账号级配置。
4. `03-settings-ui`
   - Regram 设置入口、设置页面、功能开关和本地化。
5. `04-notifications`
   - Notification Service 策略、空通知、置顶消息、mention/reply 和外部 session。
6. `05-message-policy`
   - 消息过滤、已读位置推进、反撤回和删除状态展示。
7. `06-translation-and-metadata`
   - 翻译后端、注册日期、消息 JSON 和相关数据服务。
8. `07-privacy-and-pro`
   - Ghost Mode、NSFW、本地 Premium、IAP 和 Paywall。
9. `08-chat-and-ui`
   - 上下文菜单、聊天列表、输入栏、图库、Badge 和其他界面增强。
10. `09-localization-assets`
    - Regram 字符串、图标和非代码资源。

约束：

- 一个提交只实现一个可描述的行为。
- 功能提交必须同时包含必要的 Bazel 依赖。
- 纯重命名、格式化和功能变化不得混在同一提交。
- 每个功能需要记录上游接触点和验证场景。
- 如果上游已经原生实现相同功能，应删除对应补丁，而不是继续覆盖上游实现。

## 5. 首次迁移：从 legacy 树建立补丁序列

首次迁移是一次性成本，不应直接对当前分支执行大规模 rebase。

### 5.1 冻结现状

1. 完成或单独保存当前未提交的工作。
2. 创建 `archive/legacy-<date>`。
3. 为最近可发布构建创建 tag。
4. 保存对应 IPA、dSYM、构建配置和版本号。
5. 建立功能清单，标明保留、重写或删除。

### 5.2 建立新集成树

1. 从选定的官方 Telegram SHA 创建新的集成分支。
2. 不直接 cherry-pick Swiftgram 的 `Swiftgram Version X` 巨型提交。
3. 按第 4 节顺序，从 legacy 树逐组迁移功能。
4. 每完成一组立即构建和验证，再迁移下一组。
5. 旧分支始终保持可构建，用于行为对照和回滚。

当前 Regram 与官方 Telegram 仍共享 `6ad963e5b6` 基线，因此应优先在下一次官方大版本出现前完成补丁拆分。

## 6. 常规上游同步流程

### 6.1 准备

同步前必须满足：

- 工作树干净。
- 所有 submodule 干净且指向已提交 SHA。
- 当前 `regram/main` 已有可回滚的 release/archive 引用。
- 当前版本的关键行为测试已通过。
- 已记录当前 Telegram 基线 SHA。

只获取上游，不立即改动产品分支：

```bash
git fetch telegram master
git log --oneline --decorate <old-telegram-sha>..telegram/master
git diff --stat <old-telegram-sha>..telegram/master
```

### 6.2 创建同步分支

从当前产品分支创建临时同步分支，并把 Regram 补丁重放到新 Telegram 基线上：

```bash
git switch regram/main
git switch -c sync/telegram-<version>-<short-sha>
git rebase --rebase-merges --onto telegram/master <old-telegram-sha>
```

只有在首次补丁拆分完成后才使用上述 rebase。legacy 巨型快照不适合直接重放。

建议启用 Git 的冲突复用：

```bash
git config rerere.enabled true
git config rerere.autoupdate true
```

### 6.3 冲突处理顺序

按以下顺序解决冲突：

1. 构建系统、target 和依赖。
2. TelegramCore、Postbox 和数据类型。
3. AccountContext、SharedAccountContext 和设置。
4. TelegramUI 接入点。
5. Notification、Share、Widget 等扩展。
6. 资源、本地化、图标和产物脚本。

每完成一个补丁组就运行该组验证，不要等所有冲突解决后才第一次构建。

### 6.4 冲突处理原则

- 结构冲突默认保留上游新结构，再把 Regram 的最小行为重新接入。
- 禁止对大型冲突文件整体选择 `ours` 或 `theirs`。
- 不复制已经被上游删除的旧实现。
- 如果函数签名或数据流改变，应更新 Regram 适配层，而不是恢复旧签名。
- BUILD 冲突先保留上游依赖，再添加仍然必要的 Regram 依赖。
- 数据结构和持久化 key 的修改必须验证旧版本数据能否升级。
- Notification Service、Share Extension 等必须作为独立进程验证，不能只验证主 App。
- 每个非平凡冲突都记录：上游变化、保留的 Regram 行为、验证方式。

## 7. 接入面控制

长期目标不是让 Regram 没有上游修改，而是让修改集中且可枚举。

推荐规则：

- Telegram 源码只能直接依赖一个轻量的 `RegramIntegration` 层。
- Telegram 模块不得直接依赖具体的 `RGProUI`、`RGGTranslate`、`RGPayWall` 等功能实现。
- 菜单、设置、消息可见性、通知和生命周期通过有限 Hook 接入。
- 新增上游修改必须加入 allowlist，并说明为什么现有 Hook 无法满足。
- 第一阶段将直接修改的上游文件控制在 40 个以内，长期目标为 20 个左右。
- `MARK: Regram` 只用于定位，不能代替模块边界和测试。

建议的集成接口：

- `MessageVisibilityPolicy`
- `MessageMutationPolicy`
- `ContextMenuContributor`
- `SettingsSectionContributor`
- `NotificationPolicy`
- `OpenURLInterceptor`
- `AppLifecyclePlugin`

## 8. 验证门禁

同步分支合入前必须完成以下检查。

### 8.1 仓库完整性

- 全新 clone + recursive submodule 能复现构建。
- `git submodule status --recursive` 无 `+`、`-` 或 dirty 状态。
- 不存在依赖手工修改但未提交的 submodule。
- 不存在失效 symlink。
- 构建脚本查找的 IPA、dSYM 和 target 名称与实际产物一致。

### 8.2 构建

- 官方 Telegram 基线在相同工具链下可构建。
- Regram simulator Debug 构建通过。
- Regram device Release 构建通过。
- Notification Service、Share、Widget 和 Watch 配置至少完成编译验证。
- IPA、dSYM、版本号和 UUID 收集正确。

### 8.3 自动测试

- 设置默认值和迁移。
- App Group 和 entitlement 降级行为。
- 消息过滤和已读位置。
- 反撤回和删除状态。
- 翻译后端选择与 fallback。
- 通知静音、空通知、置顶消息和 mention/reply。
- Postbox 自定义数据向前兼容。

### 8.4 手工冒烟测试

- 登录和账号切换。
- 消息收发、回复、转发、删除和编辑。
- 聊天列表、文件夹和搜索。
- Story 查看和 Ghost Mode。
- 前台、后台、锁屏通知。
- 设置页、Pro 状态和购买入口。
- Share Extension 和深链。
- 升级安装，不清除旧数据。

## 9. 同步报告

每次同步应新增一份 `docs/upstream-sync/<version>.md`，至少包含：

- 旧 Telegram SHA 和新 Telegram SHA。
- Regram 同步分支和最终提交。
- 上游主要功能变化。
- 发生冲突的文件和对应补丁组。
- 被删除、替换或暂时关闭的 Regram 功能。
- 已执行的自动和手工测试。
- 未验证场景与已知风险。
- 回滚 release/tag。

## 10. 发布与回滚

同步完成后：

1. 保留旧 `release/*` 分支和 tag。
2. 从验证通过的同步分支创建新的 release 分支。
3. 保存 IPA、dSYM、构建配置和符号 UUID 清单。
4. 经过内部升级安装和通知场景验证后再推广。
5. 观察期结束前不得删除旧构建产物。

如果新版本出现严重问题：

- 停止推广新 release。
- 回退到旧 release 构建，而不是在错误的新基线上继续叠加临时补丁。
- 数据迁移不可逆时，禁止直接安装旧版本；必须先提供兼容迁移或修复版本。
- 修复完成后重新执行完整同步门禁。

## 11. 禁止事项

- 禁止直接在有未提交改动的工作树中同步上游。
- 禁止把 Telegram、Swiftgram 同时作为活跃上游进行双向 merge。
- 禁止继续生成类似 `Swiftgram Version X` 的单个巨大产品快照提交。
- 禁止仅以“编译通过”作为同步完成标准。
- 禁止隐藏或丢弃无法理解的冲突。
- 禁止在没有 release/tag 回滚点时重写 `regram/main`。
- 禁止发布没有对应 dSYM 的构建。

## 12. 执行顺序

建议按以下顺序落地：

1. 修复仓库可复现性问题：submodule、CI 产物路径、失效 symlink。
2. 建立 legacy 冻结分支和发布回滚点。
3. 建立功能与上游接触点清单。
4. 将现有改动拆分为第 4 节的补丁序列。
5. 为高风险功能补充最低限度测试。
6. 在当前 Telegram 基线上完成一次无版本升级的演练重建。
7. 使用下一次 Telegram 更新执行完整同步流程。
8. 根据实际冲突结果继续缩小上游接触面。
