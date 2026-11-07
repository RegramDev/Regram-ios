# 相机崩溃、分组标签颜色与本地语音导入

本轮基于已发布的 **13.2 / b34648** 源码 `85edf2a61398fc865c44aa8ed1278ae678422e3a`，工作树为 `telegram-13-2-ui-cache/Telegram-iOS`，修复分支为 `fix/camera-folder-colors-voice`。原项目目录中的既有图标、命名和窗口改动未参与本轮修改。

## 相机

用户提供的 2026-11-08 崩溃日志显示 iOS 27.0.1 上发生 `SIGABRT`，异常由 `AVCapturePhotoOutput.setMaxPhotoDimensions` 抛出。使用 b34648 的 `TelegramUIFramework` dSYM（UUID `C3DFAEF2-1BCC-3236-8FDD-F910F95CFE04`）确认调用链为 `CameraOutput.configureHighResolutionPhoto` → `CameraDeviceContext.configure` → `CameraContext.setDualCameraEnabled` → 相机初始化。

旧代码在会话配置尚未提交时设置高分辨率照片尺寸。修正将尺寸应用放到 `commitConfiguration` 之后，重新读取当前连接支持的尺寸；输出未连接时跳过。尺寸设置由 Regram 自有 Objective-C 边界验证连接、设备和尺寸并捕获系统异常，失败时保留系统默认尺寸，不将失败状态带入单次拍照设置。相机切换、模式切换和双摄配置都经过同一入口。

Apple 的 [`maxPhotoDimensions` 文档](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput/maxphotodimensions)要求尺寸属于当前 active format 的 `supportedMaxPhotoDimensions`。会话时序是结合本次调用栈和源码作出的修复判断；无真实相机执行结果时，不将适配器测试表述为设备问题已复现。

## 标签颜色

此前只单独保存了标签显隐开关，颜色仍会被冷启动同步或实时文件夹更新覆盖。现在每个账号的 Postbox 文件夹状态保存按文件夹 ID 索引的本机颜色选择，同时区分「尚无覆盖」和用户明确选择的「无标签」。

- 交互修改与首次启用时分配的颜色都会保存；同步和实时推送恢复本机选择。
- 旧状态中已有的颜色在首次读取时迁移；后续未在本机修改的文件夹仍使用服务器颜色。
- 显隐开关不清空颜色；选择无标签后重新开关也不随机分配。
- 删除文件夹会清理相应覆盖，避免同 ID 的新文件夹继承旧颜色；不同账号相互隔离。

## 本地语音包

从聊天附件的「文件」或「音频」入口选择一个本地音频后，提供「以语音消息发送」及「以文件发送」。支持 MP3、M4A、AAC、WAV、OGG、Opus、FLAC 和 AIFF 的常见音频编码；多选及编辑既有消息继续走原有文件流程。

语音模式在后台用 FFmpeg 解码并重采样为 48 kHz 单声道，复用 Telegram 的 OGG/Opus 写入器和波形格式，随后进入原生语音草稿预览。试听、裁剪、删除、发送、回复及定时使用现有录音草稿路径，导入本身不发送消息。保留普通文件发送选项；尊重会话发言、语音及媒体权限，不覆盖已有录音草稿。转换可取消，无效音频报错；单个音频限制为 60 分钟。语音预览草稿包含恢复元数据，可复用上游重新打开录音的流程。

补齐发行 FFmpeg 的 Vorbis、PCM S16BE 解码器，使 OGG/Vorbis 与常见 AIFF 输入在 iOS 包内可用；不调用外部服务，不需要识别接口或 API Key。

## 验证

- 生产文件夹状态、实际 `PeerNameColor` 类型及同步赋值的 17 项隔离回归；旧源码在服务器空颜色覆盖本机颜色时失败。
- 生产 Objective-C 异常边界的 7 项检查，覆盖未连接、无效／不支持的尺寸、系统抛异常、成功写入、避免重复配置和格式切换；生产会话配置入口验证先提交再设置主／副相机，覆盖重复配置及缺失上下文，旧源码在该回归中失败。
- 生产语音转换器、FFmpeg Objective-C 绑定及 Opus 写入器处理 9 个实际文件，包括 8 种格式和短片段；检查输出可解码、Opus、48 kHz、单声道及近似时长。另检查原生写入器重新打开语音草稿、无效文件、缺失文件、远程 URL、转换前／中途取消及扩展名分流。主机使用本机 FFmpeg／Opus 库，不能代替 iOS 发行库的设备播放验收。
- 三种语言资源及本地化检查通过。

构建及最终检查结果在完成后补记。本轮没有在真机或真实账号中执行相机、标签重启和实际语音发送；完整设备流程仍需验证。崩溃日志、调试符号和本轮日志只保存在被忽略的 `build-input/camera-folders-voice/`。
