# 崩坠牌局公开试玩版

《崩坠牌局》是一款四人棋盘卡牌乱斗游戏。当前公开试玩版为 1 名玩家对 3 名 AI，支持 64 位 Windows 10/11，以及 Intel 和 Apple Silicon Mac。

## 下载

[下载 Windows 公开试玩版 0.1.0-dev.1](https://github.com/jeffxuan/bengzhui-cards-demo/releases/download/v0.1.0-dev.1/BengzhuiCards-Windows-0.1.0-dev.1.zip)

[下载 macOS 公开试玩版 0.1.0-dev.1](https://github.com/jeffxuan/bengzhui-cards-demo/releases/download/v0.1.0-dev.1/BengzhuiCards-macOS-0.1.0-dev.1.zip)

本仓库只用于分发试玩构建和收集反馈，不包含项目源码。

## Windows 运行方法

1. 完整解压 ZIP，不要直接在压缩包预览中运行。
2. 双击 `BengzhuiCards.exe`，无需安装 Godot 或其他运行库。
3. 当前构建没有商业数字签名。确认文件来自本仓库且校验值一致后，若 Windows 显示“Windows 已保护你的电脑”，可选择“更多信息”再选择“仍要运行”。
4. 不要为了运行游戏关闭杀毒软件。如果文件被拦截或隔离，请停止测试并提交提示截图。

Windows ZIP SHA-256：

```text
fbd22c1dc97580b08496ccf369045bec0544fc96a7e808ba5a096b4654df964c
```

## macOS 运行方法

1. 完整解压 ZIP，不要直接在压缩包预览中运行。
2. 在 Finder 中右键点击 `BengzhuiCards.app`，选择“打开”，再在确认窗口中选择“打开”。
3. 当前构建经过 ad-hoc 签名，但没有 Apple Developer ID 公证。若系统仍然阻止运行，请先尝试打开一次，再进入“系统设置 → 隐私与安全性”，确认应用名称和来源后选择“仍要打开”。
4. 不要关闭 Gatekeeper，也不要运行来源不明的终端命令。如果系统报告应用损坏或无法验证，请停止测试并提交提示截图。

macOS ZIP SHA-256：

```text
3007a963fce617e3a94d842982fbeb929184beaf92e2204522fd6b415f08c4ea
```

## 反馈

- [提交完整试玩反馈](https://github.com/jeffxuan/bengzhui-cards-demo/issues/new?template=playtest_feedback.yml)
- [报告无法启动、崩溃或规则问题](https://github.com/jeffxuan/bengzhui-cards-demo/issues/new?template=bug_report.yml)

反馈前请打开游戏右上角“对局信息”，点击“复制调试信息”。请同时提供系统版本、设备型号、分辨率、实际对局时长和复现步骤。

## 当前验证状态

- Godot 4.6.3 编译、规则测试、存档测试、三分辨率 UI 测试及 1000 局自动模拟通过。
- Windows 文件确认为独立的 x86-64 PE 程序，资源已内嵌，仅依赖 Windows 系统组件。
- macOS 应用经过 ad-hoc 重签名并通过严格签名检查，同时包含 `arm64` 与 `x86_64`；从最终 ZIP 解包后已完成本机整局冒烟。
- Windows 真实环境整局验证正通过本轮测试完成。

游戏不联网、不上传遥测，也不需要账号。
