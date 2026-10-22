# Regram 图标与截图标记

默认图标为「絮语」（`RGConversation`），沿用已确认的相叠气泡轮廓。原默认人物图保留为「Regram 经典」（`RGClassic`）备用图标。

| 轮廓 | 样式 |
| --- | --- |
| 相叠气泡 | 絮语、晴空、鸢尾、薄荷 |
| 四块几何 | 合流、琥珀、星河、青岚 |
| 原 Regram 人物图 | Regram 经典 |

- 每套提供明确的默认／深色 App Icon 资源槽，主屏幕外观由 iOS 选择，不通过额外图标切换请求实现。所有尺寸与深浅版本均由同一份轮廓或原图生成，无需维护两套设计。
- 矢量样式浅色背景为米色 `#F3EADC`；深色改为深灰底 `#242426`、米白图形及文字 `#F8F1E5`。气泡前景保留橙色或各款原有点缀色，几何配色款在底部一块保留彩色；图标、预览、产品入口及截图标记同步派生。原人物图保留原白色纸面，深色版本仍为原有灰色纸面。
- 应用内图标预览、Regram Pro 入口、更新图标同步提供深浅资源。默认图标仍为 `RGConversation`，安装身份不变。
- 八款矢量样式各有对应截图标记，另保留原 `RegramAppBadge` 和 `ZhiqiuAppBadge` 原图。每个样式只保存一个 `customAppBadge` 选择，深浅由应用主题决定；旧标记沿用原画。
- 标记的实际外观不依赖窗口的系统主题。保存的应用深色主题、手动切换及独立覆盖窗口均通过 `Window1.updateAppBadgeAppearance` 同步；不修改主窗口的系统外观，也不增加弹窗。

资源源文件为 `Artwork/Geometry.json` 和 `Artwork/RGClassic-original.png`。两款旧截图标记保留历史资源，生成器不会覆盖它们。

```sh
swift Regram/RGBranding/Tools/generate-assets.swift
python3 build-system/check-regram-branding.py
```

检查脚本可传入 `--compiled-icons-plist` 和 `--compiled-catalog`，核对实际编译结果的 iPhone／iPad 主图标、备用图标和每套默认／深色 rendition。

系统外观槽位参考 Apple 的[图标资源配置](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)。普通图片采用[外观资源变体](https://developer.apple.com/documentation/uikit/providing-images-for-different-appearances)。本轮交付及设备验证范围见[图标与备份记录](../../docs/icon-backup-rendering-audit.md)。
