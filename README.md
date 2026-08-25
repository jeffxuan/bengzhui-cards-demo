# 崩坠牌局

Godot 4.6.3 的单人公开试玩版 v0.1.0-dev.2。默认模式为 1 名玩家对 3 名 AI：15x15 棋盘只在淘汰发生后崩坠（15→11→7），没有回合上限，只有最后存活者获胜；同一次结算全灭时按既定决胜序列裁定。

## 运行

```bash
/Users/jeff.jiang/Desktop/Godot.app/Contents/MacOS/Godot --editor --path .
```

点击高亮玩家三格内的空格移动；攻击或技能会显示曼哈顿范围与合法目标。停在神异格会从公共事件牌堆抽取事件。商店购买的普通牌会标记为“商店保留”，跨回合保存直到打出；回合结束时若普通手牌超过生命值-2，必须自行选择弃牌。

## 验证

```bash
GODOT_BIN=/Users/jeff.jiang/Desktop/Godot.app/Contents/MacOS/Godot scripts/ci/verify.sh
```

发布候选版还需运行 10000 局模拟、检查两个平台导出物，并完成 `docs/RELEASE_CHECKLIST.md` 中的真人与真实 Windows 验证。最新本地结果记录在 `docs/VERIFICATION.md`。

当前实现以 `docs/RULES.md` 的 v4 规则合同为准；旧 v2/v3 中途对局不兼容，程序会保留原文件并提示重新开始。公开源码采用 MIT，第三方素材仍以 `THIRD_PARTY_NOTICES.md` 中的原许可证为准。
