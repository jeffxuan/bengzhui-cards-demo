# 《崩坠牌局》试玩招募与反馈投放包

版本：`v0.1.0-dev.8`  
仓库：<https://github.com/jeffxuan/bengzhui-cards-demo>  
下载：<https://github.com/jeffxuan/bengzhui-cards-demo/releases/tag/v0.1.0-dev.8>

## 推荐投放顺序

1. **GitHub Discussions**：作为长期反馈中心，适合记录版本、规则讨论和可复现问题。入口：<https://github.com/jeffxuan/bengzhui-cards-demo/discussions>。
2. **GitHub Issues**：只有崩溃、卡死、无法继续或明确的平衡问题才开 Issue；试玩者优先使用仓库已有的中英文模板。
3. **itch.io**：建立独立游戏试玩页，上传同一版 Windows/macOS 压缩包，把 GitHub Release 作为源码与反馈入口。页面需要账号登录后创建，不能用 GitHub 权限代替 itch.io 登录。
4. **Reddit `r/playtesters`、TIGSource、IndieDB、Godot Forum/Discord**：发布短招募帖，统一指向 Release 和反馈模板。
5. **国内渠道**：TapTap、Bilibili 独立游戏区和独游 QQ 群。每个平台只使用一条固定下载链接，避免测试者拿到旧包。

## 中文招募帖

### 标题

《崩坠牌局》公开试玩 v0.1.0-dev.8：15×15 四人乱斗卡牌，招募 Windows/macOS 试玩者

### 正文

你好，我们正在制作一款单人对 3 名 AI 的战术卡牌乱斗游戏《崩坠牌局》。棋盘会在淘汰发生后从 15×15 崩至 11×11、再至 7×7；没有回合上限，最后存活者获胜。当前试玩版包含 8 名角色、165 张新版卡牌、事件牌、装备、中文/英文界面和保存功能。

下载：<https://github.com/jeffxuan/bengzhui-cards-demo/releases/tag/v0.1.0-dev.8>

目前最想听到四类反馈：

- 第一局是否在 10 分钟内理解移动、攻击范围、事件和装备；
- 出牌时是否有“我做了一个聪明决定”的爽感，哪里会无聊或拖沓；
- 哪些角色、卡牌或技能过强、过弱、描述不清或让人卡住；
- 是否遇到崩溃、卡死、英文溢出或无法继续。

请在反馈中附上系统、版本、语言、角色阵容、种子、对局时长和复现步骤。游戏内调试信息面板可以一次复制这些信息。反馈入口：<https://github.com/jeffxuan/bengzhui-cards-demo/discussions>；崩溃或卡死请使用 <https://github.com/jeffxuan/bengzhui-cards-demo/issues/new?template=bug_report.yml>。

这是开发版，少量复杂牌面仍标记为 `provisional`。感谢试玩和指出问题！

## English recruitment post

### Title

`Bengzhui Cards v0.1.0-dev.8 — tactical 4-player card brawl, looking for Windows/macOS playtesters`

### Body

`Bengzhui Cards` is a solo tactical card brawl: one player fights three AI opponents on a 15×15 board. The board collapses only after an elimination (15×15 → 11×11 → 7×7); there is no round limit, and the last survivor wins. This build includes 8 characters, 165 cards, events, equipment, saves, and Chinese/English UI.

Download: <https://github.com/jeffxuan/bengzhui-cards-demo/releases/tag/v0.1.0-dev.8>

We are especially looking for feedback on onboarding, decision clarity, combat impact, card/character balance, confusing text, crashes, and soft locks. Please include your OS, build, language, roster, match seed, match length, and reproduction steps. The in-game debug panel can copy this information for you.

Feedback hub: <https://github.com/jeffxuan/bengzhui-cards-demo/discussions>  
Crashes and blockers: <https://github.com/jeffxuan/bengzhui-cards-demo/issues/new?template=bug_report.yml>

This is an early public build; a small number of complex card effects are explicitly marked `provisional`.

## 反馈整理规则

- `P0`：崩溃、存档损坏、无法开始或无法结束对局。收到后优先复现并暂停宣传。
- `P1`：卡死、非法胜者、核心规则错误、严重 UI 遮挡。下一个补丁前处理。
- `P2`：明显不平衡、描述与效果不一致、操作反馈不足。按复现数量和影响面排序。
- `P3`：美术、音效、文案和易用性建议。每周汇总一次。

每条有效反馈都记录：版本、平台、语言、种子、角色阵容、胜因、时长、复现步骤、截图/视频和预期行为。只把能复现的问题写入版本变更日志；无法复现的反馈保留原文并标注待验证。

## 发布节奏

- 每周只推广一个稳定构建，下载入口始终指向最新 GitHub Release。
- 收集至少 10 个独立试玩样本后再改平衡，避免被单局体验带偏。
- 修复 P0/P1 后更新 Release Notes、SHA-256 和试玩指南，再重新发布招募帖。
- 不在招募帖中承诺未实现的功能；`provisional` 内容必须保持公开标记。
