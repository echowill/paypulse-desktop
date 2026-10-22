# 薪跳 PayPulse

输入月薪和工作时段，看着今天的收入逐秒增长。原生 macOS 菜单栏应用，以及原生 Windows 桌面小工具。

<img src="docs/mac-preview.png" width="400" alt="薪跳 Mac 版，使用演示数据" />

## 下载

请到 [GitHub Releases](https://github.com/echowill/paypulse-desktop/releases/latest) 下载。

| 平台 | 文件 | 使用 |
| --- | --- | --- |
| macOS 13+，Apple Silicon / Intel | `PayPulse-macOS-Universal.zip` | 解压，双击「薪跳.app」，可移入「应用程序」 |
| Windows 11 x64，Intel / AMD | `PayPulse-Windows11-x64.zip` | 解压，双击 `PayPulse.exe`，免安装 |

两个版本都没有商业开发者签名；Mac 使用本地临时签名。下载来源和 SHA-256 可与 Release 附件核对。无需关闭系统安全保护。

正在准备申请 SignPath Foundation 开源项目免费签名，尚未获批、尚未提供 SignPath 签名的版本。详见 [Code signing policy](CODE_SIGNING_POLICY.md) 和 [Privacy policy](PRIVACY.md)。

## 功能

- 月薪、上下班、休息时间和每周工作日配置，支持跨夜班次。
- 今日收入逐秒增长，午休和休息日自动停止计薪。
- 时薪、下班/休息结束倒计时、今日进度和本月预估收入。
- 可自由拖动的置顶悬浮窗，一键隐藏金额，支持四位小数。
- 本月排班工时 / 固定月计薪天数两种折算口径。
- 本地保存设置，可选登录启动，无账号、无网络请求、无分析追踪。

Mac 菜单栏直接显示收入。Windows 托盘图标悬停显示收入，点击打开详情，悬浮窗常驻显示金额。

## 计算口径

默认 `秒薪 = 月薪 ÷ 本月排班计薪秒数`，`今日收入 = 今日已流逝的计薪秒数 × 秒薪`。固定天数模式下，分母为 `固定天数 × 每班计薪秒数`，因此月累计可能与月薪不同。

定时器只刷新显示，收入按真实日历区间计算，睡眠、退出和重启后会自动补齐排班收入。跨夜班次按上班当天判断排班，收入按自然日拆分。修改设置会回算当月，暂不保留历史工资版本。

金额是基于用户输入的估算，税前/税后取决于所填月薪。暂不自动识别法定节假日和调休，也不计算加班倍率、扣税或考勤。21.75 只是固定计薪天数的可修改示例。

## 源码与构建

- [`macos/`](macos/)：Swift + SwiftUI + AppKit，Universal 应用，无第三方依赖。运行 `swift run SalaryEngineChecks` 验证计薪逻辑，`./build.sh /absolute/output/path` 打包。
- [`windows/`](windows/)：C++17 + Win32 + GDI+，静态链接编译器运行库。支持 MinGW-w64 或 Visual Studio 2022 / MSVC 构建，详见该目录说明。
- [`docs/product-research.zh-CN.md`](docs/product-research.zh-CN.md)：同类产品调研。

Mac 版经过本机运行和界面检查；Windows 提供交叉编译二进制，并由 GitHub Actions 执行 Windows 构建、计薪检查与原生窗口启动检查。CI 不代替人工视觉验收。

## 数据

Mac 配置使用本机 UserDefaults；Windows 配置位于 `%LOCALAPPDATA%\PayPulse\settings.ini`。配置未加密。公开仓库和 Release 不包含用户的个人薪资配置。

MIT License，详见 [LICENSE](LICENSE)。
