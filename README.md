# 崩坠牌局

Godot 4.6.3 的单人公开试玩版 v0.1.0-dev.8。默认模式为 1 名玩家对 3 名 AI：15x15 棋盘只在淘汰发生后崩坠（15→11→7），没有回合上限，只有最后存活者获胜；同一次结算全灭时按既定决胜序列裁定。

这是面向外部试玩者的开发版构建：规则和内容已经可以完整开局、结束并保存，但仍会有少量复杂牌面和角色流程标记为 provisional，试玩时请通过调试信息面板记录种子和复现步骤。

最新试玩包在 GitHub Release `v0.1.0-dev.8`：下载 Windows 或 macOS 压缩包，并查看同目录的 SHA-256 校验文件。

## 运行

支持简体中文和 English。在主菜单或对局内打开「设置 → 语言 / Language」，选择 English；语言选择会自动保存。菜单、165 张新版卡牌、8 名角色技能、事件、教程及战斗记录均已接入英文。

```bash
/Users/jeff.jiang/Desktop/Godot.app/Contents/MacOS/Godot --editor --path .
```

点击高亮玩家三格内的空格移动；攻击或技能会显示方形切比雪夫范围与合法目标（距离 1 包含对角相邻格）。停在神异格会从公共事件牌堆抽取事件。商店购买的普通牌会标记为“商店保留”，跨回合保存直到打出；回合结束时若普通手牌超过生命值-2，必须自行选择弃牌。

English: Open **Settings → Language / 语言 → English**. The game remembers your choice. See [English playtest guide](docs/PLAYTEST_EN.md). Developers can launch with `godot --path . -- --language=en`.

## 验证

```bash
GODOT_BIN=/Users/jeff.jiang/Desktop/Godot.app/Contents/MacOS/Godot scripts/ci/verify.sh
```

试玩反馈请使用 [GitHub 试玩反馈模板](https://github.com/jeffxuan/bengzhui-cards-demo/issues/new?template=playtest_feedback.yml)；崩溃或无法继续请使用 [Bug 模板](https://github.com/jeffxuan/bengzhui-cards-demo/issues/new?template=bug_report.yml)。请附上对局信息面板复制的种子、版本、阵容和胜因。

发布候选版还需运行 10000 局模拟、检查两个平台导出物，并完成 `docs/RELEASE_CHECKLIST.md` 中的真人与真实 Windows 验证。最新本地结果记录在 `docs/VERIFICATION.md`。

当前实现以 `docs/RULES.md` 的 v10 规则合同为准；旧 v2-v9 中途对局不兼容，程序会保留原文件并提示重新开始。Q「雷佑」、K「巨脑/奇策」、Shya「闪佑/碎光」与 Ginger「腰裂/强攻」均使用规则层驱动的多步选择流程，不会回退到旧版技能效果。公开源码采用 MIT，第三方素材仍以 `THIRD_PARTY_NOTICES.md` 中的原许可证为准。
