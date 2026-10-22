# Regram 图标与截图标记

当前只提供「双气泡」和「汇点」两套。默认图标为双气泡，另一套以系统备用图标 `RGGathering` 提供。

- 双气泡沿用最初确认原稿的圆润轮廓、橙色与浅桃色重叠色块和大写 `REGRAM` 字标。
- 汇点沿用最初确认的四块轮廓、角度、间距和 `Regram` 字标。
- `Artwork/Geometry.json` 保存原稿提取的轮廓和字标，`Artwork/*-light.svg` 为可查看的默认图标矢量输出。图标和标记共用同一份轮廓。
- App Icon 每套只提供一张 1024×1024 默认图，背景统一为米色 `#F3EADC`，不提供自定义深色或着色槽，由支持的 iOS 自动补全其他桌面外观。完整方形图片不预烘焙圆角，由 iOS 裁切。应用内预览和其他产品入口使用同一份默认图，不模拟桌面的自动处理。
- 截图标记每套保留浅色、深色两份外观：浅色使用米色 `#F3EADC`，深色使用浅灰色 `#E5E5EA`，搭配清晰的深色图形和字标。每个样式对应一个资源名称，只保存一个 `customAppBadge` 选择；窗口及设置预览随界面外观读取对应版本，无需分别选择深浅样式。
- 两份标记外观各自动导出 1x／2x／3x，逻辑尺寸均为 112×28pt，圆角外透明。

在仓库根目录重新导出：

```sh
swift Regram/RGBranding/Tools/generate-assets.swift
python3 build-system/check-regram-branding.py
```

原始设计稿的文件标识保存在 Geometry.json 中。导出只依赖已保存的轮廓，不依赖本机生成图片目录，不会触发应用构建。

本次按用户要求未构建应用，也没有执行 SpringBoard 深浅色切换、覆盖升级或真机截图标记验收。资源槽位检查与偏好／迁移回归不能替代这些设备验证。

2026-10-22 的旧系统图标问题、跨设备备份与渲染复查见[专项记录](../../docs/icon-backup-rendering-audit.md)。图标切换失败时保留原选择，不显示应用失败提醒；iOS 18.2.1 真机切换失败尚未复现确认。

系统补全规则参考 Apple 的[图标资源配置](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)；普通界面图片使用[外观资源变体](https://developer.apple.com/documentation/uikit/providing-images-for-different-appearances)。

已通过资源检查、Swift 语法检查，以及以下现有回归：

- `Regram/RGSimpleSettings/Tests/run-app-icon-checks.py`：切换队列、系统读值延迟、成功／失败回调和强制回落。
- `Regram/RGAppIconSelection/Tests/run-selection-checks.py`：冷启动保存、旧图标回落、过期读值不覆盖新选择、旧标记回落。
- `Regram/RGSimpleSettings/Tests/run-settings-runtime-checks.py`：真实设置存取和旧备份标记归一化，使用隔离偏好。
- `Regram/RGAppGroupIdentifier/Tests/run-storage-checks.py`：配置存取和启动清理回归，未读取或擦除实际账号数据。
