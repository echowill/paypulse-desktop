# 薪跳 Windows 11 版

原生 Win32 + GDI+，C++17。免安装、无网络请求，不需要安装 .NET、Java、Python 或 Visual C++ 运行库。

## 使用

将整个压缩包解压到固定文件夹，双击 `PayPulse.exe`。填写月薪、上下班、休息时间和每周工作日，点击「保存并开始计薪」。保存后打开详情和悬浮窗。

- 托盘图标左键打开详情，右键打开菜单，悬停显示实时金额。图标可能被 Windows 收进托盘的隐藏图标区域。
- 悬浮窗显示实时收入。双击金额、图标或空白区域打开设置；按住可自由拖动，右上角 × 收起。
- 详情窗口的 × 会隐藏窗口并在后台继续运行。完全退出请用详情页或托盘菜单「退出」。
- 「隐藏金额」同时作用于详情、悬浮窗和托盘提示。支持四位小数。
- 屏幕高度不足时，设置页可用鼠标滚轮或右侧滚动条滚动，保存和取消始终位于底部。
- 自动启动为可选项，保存时才写入当前用户的登录启动项；请将程序放在固定位置后再开启。

## 计算和保存

默认秒薪 = 月薪 ÷ 本月排班计薪总秒数；也可切换固定月计薪天数。午休不增长，休息日不计薪；跨夜班次按上班当天排班、按自然日拆分收入。固定天数为可配置的估算参数。

计时器每秒刷新，但收入由实际日历区间推导，退出、睡眠和重启后会补齐已过去的排班收入。修改设置会回算本月，暂不保留历史规则。节假日和调休、加班倍率、扣税、考勤不在第一版范围。

配置保存在 `%LOCALAPPDATA%\PayPulse\settings.ini`，明文本地存储，不上传。删除该文件可恢复初始配置。

## 兼容性和验证范围

产物为 Windows x64 图形程序，目标为 Windows 11（Intel/AMD x64）。包含应用图标、版本信息、Common Controls v6 和 DPI aware 清单。

已在 macOS 上使用 MinGW-w64 交叉编译；计薪核心在本机编译运行检查通过，PE 结构与依赖已检查。仓库的 GitHub Actions 在 Windows 环境执行 MSVC 构建、核心检查和原生窗口启动检查，并可额外检验 Release 二进制。当前没有人工 Windows 界面验收；自动检查不覆盖视觉排版。`EngineChecks.exe` 可在 Windows 上运行相同核心检查。

程序没有商业代码签名，下载时可能出现系统信誉提示；核对 GitHub Release 的来源和 SHA-256 后自行决定是否打开，不必关闭系统安全保护。

更新前先在托盘右键选择「退出」，再运行新版本。窗口标题和托盘提示均显示版本号；检测到其他版本仍在后台时会提示。

Windows 压缩包只使用英文文件名，中文说明在 `README.txt` 中使用 UTF-8 编码，不包含 macOS 的 `._` 元数据文件。

## 从源码编译

Windows：安装 MSYS2 的 UCRT64 GCC 工具链，在对应环境运行 `build-windows.cmd`。

也可以使用 Visual Studio 2022 的 C++ 桌面开发工具，运行 `msbuild PayPulse.vcxproj /p:Configuration=Release /p:Platform=x64`。核心检查项目为 `EngineChecks.vcxproj`。

macOS：安装 Xcode Command Line Tools 和 MinGW-w64 后运行：

```sh
./build.sh /absolute/output/path
python3 package.py --input /absolute/output/path --output PayPulse-Windows11-x64.zip
```

源码采用 MIT License。静态链接的 GCC 运行库适用 GCC Runtime Library Exception；GUI 使用 Windows 系统组件。
