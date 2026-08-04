# 资源与许可政策

## 可接受来源

- 代码参考：Godot Demo Projects、经逐项审核的 MIT/ISC/BSD/Apache-2.0 项目。
- 美术与音频：Kenney CC0、OpenGameArt 的 CC0/CC-BY、Freesound 的 CC0/CC-BY。
- 字体：SIL Open Font License；图标：Lucide ISC。
- GPL、AGPL、CC-BY-SA、CC-BY-NC、来源不明或无法保留原许可证的资源不得进入仓库。

参考项目只用于研究接口、场景组织和 Godot 惯例，不复制玩法、美术或无法明确追溯的代码。已核验的参考包括 [Godot Demo Projects](https://github.com/godotengine/godot-demo-projects) 与 [OpenCards](https://github.com/dustland/OpenCards)，二者均为 MIT。

## 纳入流程

1. 在 `assets/third_party/manifest.json` 记录名称、作者、来源、版本或获取日期、许可证、用途、修改及原始归档 SHA-256。
2. 在资源目录保留原始许可证文本，只纳入游戏实际使用的文件。
3. 更新 `THIRD_PARTY_NOTICES.md`，运行 Godot 导入与完整验证。
4. 发布前逐项确认清单、文件路径和构建产物中的资源一致。

当前音效来自 Kenney UI Audio 与 Impact Sounds 1.0，均为 CC0；项目不包含背景音乐。
