# 中英文界面维护

显示语言为 `zh_CN` 或 `en`，通过设置菜单切换，保存在现有 settings v1 的可选 `language` 字段中。旧设置未包含该字段时继续使用简体中文。开发启动参数为 `-- --language=en`。

翻译表按展示用途维护：

- `localization/en_ui.json`：菜单、HUD、交互提示、教程和存档错误。
- `localization/en_content.json`：卡牌、角色、事件和状态的名称与说明。
- `localization/en_messages.json`：规则层产生的公开战斗记录和动态提示。

中文原文仍是查找键。不得修改规则中的中文类别标识、稳定内容 ID、命令载荷、种子或回放来实现翻译。运行时由 Godot TranslationServer 翻译 Control 文本；手工绘制的棋盘文字、动态 tooltip、截短摘要及复制的反馈文本显式调用 `Localization.text()`。

动态格式串保留占位符数量及顺序。整句优先翻译，组合标签中的数字模板和卡牌名称在显示边界处理。添加新文案时同步添加英文条目。保留 `provisional` 标记，避免英文描述掩盖尚未确认的规则。

脚本 Translation 对象必须在场景树退出前从 TranslationServer 移除，避免 Godot 4.6.3 关闭时晚于 GDScript 生命周期释放对象而崩溃。

验证入口：

```bash
godot --headless --path . --script res://tests/run_localization_tests.gd
godot --headless --path . --script res://tests/run_ui_smoke.gd -- --language=en
```

完整 CI 同时验证中英文 UI。语言测试检查所有新版内容展示字段、格式串、动态文本、语言偏好兼容，以及切换语言后确定性快照和待处理选择保持不变。三分辨率 UI 测试覆盖实时切换、1.35 倍文字及可见英文文本残留检查。
