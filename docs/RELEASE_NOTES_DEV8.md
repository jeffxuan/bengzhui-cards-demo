# v0.1.0-dev.8 · 中英文试玩版

这是一个面向真人反馈的公开试玩版本。

## 这版新增

- 新增简体中文 / English 切换，语言选择会保存。
- 英文覆盖菜单、教程、8 名角色、卡牌、事件、状态和战斗记录。
- 修复英文长文本在 1280×720 和 1.35 倍文字下的界面溢出。
- 修复 Godot 4.6.3 退出时脚本翻译对象未释放造成的崩溃。
- 增加本地化自动检查，确保语言切换不改变对局快照、随机数或回放命令。
- 增加中英文三分辨率 UI 冒烟测试和反馈指南。

## 已知情况

- 少量复杂牌面仍标记为 `provisional`，试玩时请优先反馈规则是否清楚、是否卡死或无法继续。
- Windows 构建需要在真实 Windows 电脑上验证；macOS 构建可能显示未签名开发者提示。
- 这是开发版，不保证旧版本中途对局与当前内容版本兼容。

## 反馈方式

- [提交试玩反馈](https://github.com/jeffxuan/bengzhui-cards-demo/issues/new?template=playtest_feedback.yml)
- [报告 Bug](https://github.com/jeffxuan/bengzhui-cards-demo/issues/new?template=bug_report.yml)

反馈时请写明：系统、版本、语言、角色阵容、种子、对局时长、最爽的时刻、最无聊或最困惑的时刻，以及复现步骤。我们会根据可复现的反馈调整规则、UI、AI 和牌面强度。
