# Reza 图标与截图标记

| 应用图标 | 资源名 |
| --- | --- |
| 橘猫（默认） | `RGCatOrange` |
| 三花猫 | `RGCatCalico` |
| 暹罗猫 | `RGCatSiamese` |
| 黑白猫 | `RGCatTuxedo` |

四款图标从用户选定的 `Artwork/RGCat*-original.png` 生成。iPhone 和 iPad 使用相同的 1024px 图标，外观设置使用 256px 预览。每款在浅色和深色外观下都保留原图配色。

- 四款猫图标与原有十一款图标共同打包在 `AppIcons.xcassets` 和 `Images.xcassets` 中。升级沿用已选择的旧备用图标，使用系统默认图标时显示橘猫。
- Reza Pro 入口跟随所选图标。登录欢迎页、更新实时活动和手表使用橘猫。
- 默认截图标记是一只从边缘探头、双爪搭在边上的橘猫（`RGRezaBadge`，48 × 28 pt 透明图，原稿在 `Artwork/PeekingTabby.svg`）。原有十款截图标记保留其画面、字标与已选状态。「隐藏」即时清除标记，也可随外观设置备份。截图标记的深浅由应用主题决定。
- 标记的实际外观不依赖窗口的系统主题。保存的应用深色主题、手动切换及独立覆盖窗口均通过 `Window1.updateAppBadgeAppearance` 同步；不修改主窗口的系统外观，也不增加弹窗。

旧款截图标记的矢量轮廓来自 `Artwork/Geometry.json`。

```sh
swift Reza/RGBranding/Tools/generate-assets.swift
python3 build-system/check-reza-branding.py
```

检查脚本可传入 `--compiled-icons-plist` 和 `--compiled-catalog`，核对实际编译结果的 iPhone／iPad 主图标、备用图标和每套默认／深色 rendition。

系统外观槽位参考 Apple 的[图标资源配置](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)。普通图片采用[外观资源变体](https://developer.apple.com/documentation/uikit/providing-images-for-different-appearances)。旧版图标与备份的验证范围见[历史记录](../../docs/icon-backup-rendering-audit.md)。
