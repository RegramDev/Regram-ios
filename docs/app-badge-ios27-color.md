# b34586 顶部配色与 badge 合成范围

用户确认 b34585 遮罩消失，并反馈顶部颜色差异，要求对齐 Telegram 官方实现。

已核对最新官方 master（`f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838`）：聊天列表的 ChatListNavigationBar 及 EdgeEffect 与官方完全一致。普通 NavigationBarImpl 的本地差异仅为返回按钮的无障碍标签，未修改颜色或模糊效果。官方顶部颜色会根据置顶会话的显示比例，在 plainBackgroundColor 和 pinnedItemBackgroundColor 之间混色；左右切换文件夹时也会插值两侧比例。

截图采样显示顶部及置顶会话区域同为约 `#2F2F2F`，普通会话区域约 `#242424`。这与官方置顶区域配色一致，不能仅凭该截图认定色差由 badge 窗口引起。

b34585 的 badge 窗口使用了整个主窗口的 frame，虽然内容透明，但渲染表面覆盖整屏。b34586 将窗口限制到 badge 图片的矩形，并裁剪窗口边界、同步主窗口的界面样式，避免装饰窗口参与其他区域的合成；同一张图片在小窗口内使用局部坐标，回退到主视图时恢复主窗口坐标。保留用户确认有效的高层级显示，不更改官方顶部混色、置顶背景或玻璃效果。

验证：窗口代码通过 iOS 类型检查（warnings-as-errors），完整 `//Telegram:Regram` arm64 Release 构建通过，包含全部六个扩展及 dSYM；官方顶部源码的字节对比通过。

按用户要求未使用模拟器。实际顶部颜色、badge 清晰度、切换不同宽度 badge、横竖屏、前后台及灵动岛活动仍需用户的 iPhone 16 Pro / iOS 27.0.1 确认。
