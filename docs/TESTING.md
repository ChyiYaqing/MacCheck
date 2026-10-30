# MacCheck 测试清单

**中文** | [English](TESTING.en.md)

本文档用于发布前自测和门店验机流程复核。自动检测可以通过构建和 App 启动完成，交互测试需要真实 Mac 硬件配合。

## 发布前基础验证

```bash
xcodebuild -project MacCheck.xcodeproj -scheme MacCheck -configuration Release -destination 'generic/platform=macOS' -derivedDataPath build_release CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
./scripts/build_and_notarize.sh
hdiutil verify ~/Desktop/MacCheck-1.3.dmg
```

验证项：

- App 能正常启动，首页自动扫描结束
- 左侧导航所有页面能打开，无明显布局挤压或空白
- “保存到历史”可以生成历史记录
- “导出报告”可以导出 PNG 和 PDF
- DMG 可以挂载，包含 `MacCheck.app` 与 Applications 快捷方式

## 自动检测项目

iPhone / iPad 检测回归测试：`bash scripts/test_ios_device.sh`。用数据线连接已信任且已解锁的设备时，可加 `--live` 读取真机（只输出机型与各项状态，不输出序列号）；连接的 iPhone 若配对了 Apple Watch，也会经由内嵌辅助程序 `MacCheckWatchHelper` 读取手表。发布包需由脚本分别签名主 App 与辅助程序，确保辅助程序保留「关闭库验证」entitlement，否则无法加载 Homebrew 的 libimobiledevice。

账户检测回归测试：`bash scripts/test_management.sh`。在已登录 Apple 账户的开发机上，可加 `--live` 验证实际登录状态、账号及姓名的读取（测试不输出个人资料）。

Apple ID 详情读取兼容旧版 `MobileMeAccounts`，并结合当前用户的账户状态缓存和只读 `Accounts4.sqlite` 查询。数据库联查方式参考 [Kolide 的公开方案](https://github.com/kolide/launcher/issues/1748)；仅选择 `com.apple.account.AppleAccount` 类型的活动账户，排除 App Store、邮件等其他账户。缺少读取权限或系统结构变化时，显示资料不可用；缓存并非在线认证结果，交易前仍需在系统设置核对。截图及导出报告会包含已读取的账号、姓名，分享前请脱敏。

必须通过 Finder/Launch Services 启动新构建进行 GUI 验证；终端测试成功不代表 App 获得同样的 TCC 权限。若 GUI 显示“读取被 macOS 隐私权限阻止”，由用户决定是否在“系统设置 > 隐私与安全性 > 完整磁盘访问权限”添加并启用当前 MacCheck，授权后退出并重新打开。未授权时仍应显示姓名（若可读）和明确的权限提示，不能误报未登录。重新构建不会更新已经运行的进程，必须退出旧进程后再启动。

| 模块 | 期望结果 |
| --- | --- |
| 硬件规格 | 显示机型、序列号、芯片、内存、架构、macOS 版本 |
| 电池 | 笔记本显示循环次数与健康信息，台式机显示不适用或无数据 |
| 安全与锁定 | 显示安全芯片、MDM、Apple ID / 激活锁相关提示 |
| 存储 | 显示容量、可用空间、SMART 或磁盘状态 |
| 网络 | 显示 Wi-Fi / 蓝牙状态 |
| 接口 | 显示检测到的 USB / Thunderbolt 控制器或设备 |
| AI 大模型 | 根据内存给出本地模型可跑性建议 |

## 交互测试项目

| 模块 | 操作 | 通过标准 |
| --- | --- | --- |
| 键盘 | 进入全屏，逐个按下实体按键 | 按下按键高亮，无失灵、连击、卡键 |
| 屏幕 | 切换纯色、灰阶、棋盘格画面 | 无明显坏点、亮点、漏光、色带 |
| 扬声器 / 耳机 | 播放测试音 | 左右声道与耳机输出正常 |
| 麦克风 | 授权后录音或观察电平 | 有稳定输入，无异常底噪 |
| 摄像头 | 授权后查看预览 | 画面清晰，无遮挡、坏点、闪烁 |
| Touch ID | 按页面提示确认 | 可用或明确显示不支持 |
| 触控板 | 点击、滑动、手势测试 | 点击、移动、滚动响应正常 |
| 性能压测 | 开始短时压力测试 | 无异常卡死或温度/性能红旗 |
| 硬盘测速 | 开始读写采样 | 读写结果可显示，未出现异常失败 |
| 接口逐口实测 | 插拔外设并记录 | 目标接口均可识别外设 |

## 隐私与截图

真实截图和报告通常包含序列号、设备名称、系统版本等信息。发布到 GitHub、官网或社交平台前，请先脱敏。

本仓库 `docs/assets` 中的图片为真机测试截图，已对序列号等敏感信息做打码处理。
