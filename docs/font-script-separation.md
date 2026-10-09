# 独立的中文与英文字体

b34580 修正了 b34579 只提供一个字体族、中文依赖隐式回退的问题。

Regram Pro → 更改字体现在有两个独立选择区：

- **英文字体**：13 个选项，包括系统、JetBrains Mono／NL、Inter、Poppins、Lora、IBM Plex 的拉丁字族、Source Sans／Serif、系统圆体和衬线体。
- **中文字体**：系统中文字体、IBM Plex Sans SC 黑体、Noto Serif SC 衬线体。Noto 使用未修改的可变字体文件，wght 轴应用 Regular／Medium／Semibold／Bold；两个自带中文族的斜体使用倾斜描述符。

英文选择负责拉丁字母、ASCII 数字与标点；中文选择负责汉字、中文标点与全角形式。选择其中一套不会替换另一套。两套字体都按“聊天内容／主要界面文字”的勾选范围即时更新，预览始终显示当前组合。代码、大表情及图标的独立字体路径保持原有规则；所选字体缺少的字形使用系统后备。

CoreText 的字符集限制与 cascade list 合成一个字体对象，供 UIKit、SwiftUI、普通消息、富文本气泡和界面文字共同使用。中文字体的英文字符被排除出 cascade，主字体中的 CJK 标点也被排除，避免混排串用字体。字体缓存键包含两套选择，因此只改中文也会刷新；原有 presentation 刷新信号同样包含中文选择。

旧设置迁移：原 Latin 字族留在英文栏，中文默认系统；原 IBM Plex Sans SC 选择移到中文栏，英文恢复系统。已经保存了独立中文选项的用户不会被迁移覆盖。

实现入口：[选择与范围](../Regram/RGSimpleSettings/Sources/FontSettings.swift)、[持久化和迁移](../Regram/RGSimpleSettings/Sources/SimpleSettings.swift)、[字符集与合成](../Regram/RGTypography/Sources/RGFontCascade.swift)、[字体加载](../Regram/RGTypography/Sources/RGTypography.swift)、[设置界面](../Regram/RGProUI/Sources/RGFontSettingsController.swift)。Noto Serif SC 的 OFL 原文和上游提交／文件 SHA-256 随资源记录保留。

验证：Foundation 范围／迁移／缓存键检查通过。主机上的 CoreText 检查使用生产合成代码，覆盖 12 组 Latin／Chinese／字重组合、中文与全角标点、ASCII 数字、彩色表情、扩展汉字字符集和可变字体轴；检查通过。按用户要求未运行模拟器或真机验证。

b34580 的 `//Telegram:Regram` arm64 release 构建通过（主程序和六个扩展）。最终参考 IPA 已重新解包检查：12 个 Mach-O 严格 ad-hoc 签名通过、12 份 dSYM 匹配、0 个描述文件；身份与 App Group／entitlements 匹配 b34579，最低 iOS 均为 15.0。83 个字体文件、11 份许可文件的包内 SHA-256 匹配来源记录。

参考 IPA SHA-256：`0575277f3ab9cb329f64e612ceadaa9f528fced28b8504596377fb55fdfc50cd`。
