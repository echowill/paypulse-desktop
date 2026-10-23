# 薪跳 PayPulse

输入月薪和工作时段，看着今天的收入逐秒增长。持续维护 Mac 原生应用和 Chrome 网页版；Windows 原生版保留历史下载，停止后续维护。

<img src="docs/mac-preview.png" width="400" alt="薪跳 Mac 版，使用演示数据" />

## 下载

**[打开 Chrome 网页版 →](https://paypulse-echowill.decenthill26.chatgpt.site)** 无需安装，支持跨应用置顶小窗；工资只在当前浏览器本地保存，详见 [`web/`](web/)。

请到 [GitHub Releases](https://github.com/echowill/paypulse-desktop/releases/latest) 下载。

| 平台 | 文件 | 使用 |
| --- | --- | --- |
| macOS 13+，Apple Silicon / Intel | `PayPulse-macOS-Universal.zip` | 解压，双击「薪跳.app」，可移入「应用程序」 |
| Windows 历史版 1.0.3（停止维护） | `PayPulse-Windows11-x64.zip` | 解压，双击 `PayPulse.exe`；新用户建议使用 Chrome 网页版 |

两个版本都没有商业开发者签名；Mac 使用本地临时签名。下载来源和 SHA-256 可与 Release 附件核对。无需关闭系统安全保护。

SignPath Foundation 签名申请未获批，相关工作暂时搁置，当前版本没有 SignPath 签名。详见 [Code signing policy](CODE_SIGNING_POLICY.md) 和 [Privacy policy](PRIVACY.md)。

## 功能

- 月薪、上下班、休息时间和每周工作日配置，支持跨夜班次。
- 今日收入逐秒增长，午休和休息日自动停止计薪。
- 时薪、下班/休息结束倒计时、今日进度和本月预估收入。
- 可自由拖动的置顶悬浮窗，一键隐藏金额，支持四位小数。
- 中国大陆计薪日历 / 本月排班工时 / 固定折算天数三种口径。
- 本地保存设置，可选登录启动，无账号、无网络请求、无分析追踪。

Mac 菜单栏直接显示收入。Windows 托盘图标悬停显示收入，点击打开详情，悬浮窗常驻显示金额。

### Mac 1.2.0 / Web 1.1.0

新增「中国大陆计薪日历」，按全国双休与调休安排计算工作日、法定带薪节日和当月计薪日。当前内置已核对的 2025、2026 年数据，离线计算，手动排班优先。详见 [日历数据与计算说明](docs/china-calendar.md)。原有用户不会被自动切换口径。

### Mac 1.1.0 新功能

- 浮窗支持三种大小、三种数字字体、浅色 / 深色 / 跟随系统主题、背景透明度，以及收入与倒计时组合；保存位置，双击打开设置。
- 每日收入小目标：咖啡、午饭或自定义目标，显示计薪时间和预计达成时刻，达成时可在应用内庆祝。
- 计薪说明分别显示本月实际排班天数、工时和固定折算天数，修改折算天数不会改动实际排班。
- 可选下班提醒、发薪日倒计时和当天提醒。系统提醒默认关闭，首次开启需要通知权限；短月发薪日取月末，不自动顺延周末。
- 按日期临时修改上下班、休息时段或改为休息，支持恢复常规排班；跨夜班次仍归上班日期，拒绝相邻班次时间重叠。

这些新增功能也已提供 Chrome 网页版；Windows 桌面版停留在 1.0.3，不再维护。

<img src="docs/mac-settings-appearance.png" width="520" alt="Mac 浮窗外观设置，使用演示数据" />

<img src="docs/mac-floating-dark.png" width="370" alt="Mac 深色浮窗，显示收入和下班倒计时，使用演示数据" />

## 计算口径

默认 `秒薪 = 月薪 ÷ 本月排班计薪秒数`，`今日收入 = 今日已流逝的计薪秒数 × 秒薪`。固定天数模式下，分母为 `固定天数 × 每班计薪秒数`，因此月累计可能与月薪不同。

定时器只刷新显示，收入按真实日历区间计算，睡眠、退出和重启后会自动补齐排班收入。跨夜班次按上班当天判断排班，收入按自然日拆分。修改设置会回算当月，暂不保留历史工资版本。

金额是基于用户输入的估算，税前/税后取决于所填月薪。中国大陆计薪日历识别已收录年份的全国节假日和补班，法定带薪节日按常规时段（包括休息扣除）分摊收入，不发下班提醒。它按当月计薪时长分摊月薪，区别于日工资折算使用的平均 21.75 天；应用保留固定天数的可修改估算选项。不计算加班倍率、扣税或考勤。固定口径的每班时长取常规班计薪时长，临时班次按其实际时长累计。

## 源码与构建

- [`macos/`](macos/)：Swift + SwiftUI + AppKit，Universal 应用，无第三方依赖。运行 `swift run SalaryEngineChecks` 验证计薪逻辑，`./build.sh /absolute/output/path` 打包。
- [`web/`](web/)：无框架静态网页，Chrome 原生画中画小窗，浏览器本地保存；Sites 提供公开网址，GitHub Actions 检查静态构建。
- [`windows/`](windows/)：停止维护的历史 C++17 + Win32 + GDI+ 源码，保留原有构建方式。
- [`docs/product-research.zh-CN.md`](docs/product-research.zh-CN.md)：同类产品调研。

Mac 版经过本机运行和界面检查；网页版在真实桌面 Chrome 验证置顶小窗。GitHub Actions 持续检查 Mac 与网页计薪核心及构建；Windows 1.0.3 保留此前检查记录，不再运行后续维护工作流。CI 不代替人工视觉验收。

## 数据

Mac 配置使用本机 UserDefaults；Windows 配置位于 `%LOCALAPPDATA%\PayPulse\settings.ini`。配置未加密。公开仓库和 Release 不包含用户的个人薪资配置。

MIT License，详见 [LICENSE](LICENSE)。
