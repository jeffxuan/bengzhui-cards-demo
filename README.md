# 崩坠牌局

Godot 4.6.3 的单人公开试玩原型。默认模式为 1 名玩家对 3 名 AI：15x15 棋盘只在淘汰发生后崩坠，最多进行 8 轮，并使用独立公共事件牌堆。

## 运行

```bash
/Users/jeff.jiang/Desktop/Godot.app/Contents/MacOS/Godot --editor --path .
```

点击高亮玩家三格内的空格移动；停在神异格会从公共事件牌堆抽取事件。事件选择完成后可结束回合。

## 验证

```bash
GODOT_BIN=/Users/jeff.jiang/Desktop/Godot.app/Contents/MacOS/Godot scripts/ci/verify.sh
```

发布候选版还需运行 10000 局模拟、检查两个平台导出物，并完成 `docs/RELEASE_CHECKLIST.md` 中的真人与真实 Windows 验证。最新本地结果记录在 `docs/VERIFICATION.md`。

当前实现以 `docs/RULES.md` 的 v3 规则合同为准；最新产品决策覆盖早期 Word 文档中的旧版棋盘和胜利条件。
