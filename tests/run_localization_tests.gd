extends SceneTree

const LocalizationScript = preload("res://scripts/ui/localization.gd")
const CatalogScript = preload("res://scripts/core/content_catalog.gd")
const StateScript = preload("res://scripts/core/match_state.gd")
const SaveScript = preload("res://scripts/core/save_service.gd")
var failures: Array[String] = []
var cjk := RegEx.create_from_string("[\\x{3400}-\\x{9fff}]")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	LocalizationScript.set_language("en")
	var catalog := CatalogScript.new()
	_expect(catalog.is_valid(), "Catalog must remain valid.")
	for file: String in ["cards_new", "characters_new", "events_new", "characters", "events", "statuses"]:
		_check_display_values(JSON.parse_string(FileAccess.get_file_as_string("res://rules/%s.json" % file)))
	_check_display_values(catalog.characters)
	_check_display_values(catalog.events)
	for definition: Dictionary in catalog.staged_cards:
		_check_display_values(catalog.resolve_card(String(definition["id"])))
	var format_pattern := RegEx.create_from_string("%[-+0-9.]*[sdf]")
	var entries: Dictionary = LocalizationScript.english.get("entries") as Dictionary
	for source: String in entries:
		var translated := String(entries[source])
		_expect(not translated.is_empty(), "Empty translation: " + source)
		_expect(format_pattern.search_all(source).size() == format_pattern.search_all(translated).size(), "Placeholder count: " + source)
	_expect(TranslationServer.translate("结束回合") == "End turn", "Native Controls must use the English translation.")
	_expect(LocalizationScript.text("Q 使用【斩击】。") == "Q played [Slash].", "Card logs must translate names and formatting.")
	var sample := "第 7 轮 · Q · 移动 1 · 存活 4/4 · 棋盘 15x15 · 决胜单体伤害 +2"
	_expect(cjk.search(LocalizationScript.text(sample)) == null, "Formatted HUD must be fully English: " + LocalizationScript.text(sample))
	_expect(LocalizationScript.text("[color=#e2706a]体力或法力不足[/color]") == "[color=#e2706a]Not enough Stamina or Mana[/color]", "BBCode must survive translation.")
	_expect(LocalizationScript.text("体1 法2 · 5x5攻击范围") == "STA 1  MP 2 · 5x5 attack area", "Joined cost/range chips must translate completely.")
	_expect(LocalizationScript.text("每回合限1次 · 剩余1 · 自身") == "1 per turn · 1 left · Self", "Joined use-limit chips must translate completely.")
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://rules/match_rules.json")) as Dictionary
	var state := StateScript.new(rules, catalog, ["q", "k", "ginger", "signal"], 81274)
	var before := state.deterministic_snapshot().duplicate(true)
	var commands := state.command_log.duplicate(true)
	LocalizationScript.set_language("zh_CN")
	_expect(TranslationServer.translate("结束回合") == "结束回合", "Switching back must restore Chinese.")
	LocalizationScript.set_language("en")
	_expect(state.deterministic_snapshot() == before and state.command_log == commands, "Switching language must preserve pending choices, RNG and replay.")
	_expect(SaveScript._sanitize_settings({"language": "en"})["language"] == "en", "English preference must persist.")
	_expect(SaveScript._sanitize_settings({})["language"] == "zh_CN", "Older settings must retain Chinese by default.")
	_expect(SaveScript._sanitize_settings({"language": "invalid"})["language"] == "zh_CN", "Unknown language must fall back to Chinese.")
	var old_settings := SaveScript.DEFAULT_SETTINGS.duplicate(true)
	old_settings.erase("language")
	_expect(SaveScript._settings_types_are_valid(old_settings), "Old settings without a language field must stay valid.")
	old_settings["language"] = 42
	_expect(not SaveScript._settings_types_are_valid(old_settings), "Malformed language preferences must produce a readable save recovery path.")
	LocalizationScript.set_language("zh_CN")
	if failures.is_empty():
		print("LOCALIZATION_OK: content, dynamic text, native Controls, language preference and rule isolation passed.")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _check_display_values(value: Variant) -> void:
	if value is Array:
		for item: Variant in value:
			_check_display_values(item)
	elif value is Dictionary:
		for key: String in value:
			var item: Variant = value[key]
			if key in ["name", "title", "description", "source_text", "label"] and item is String:
				var translated := LocalizationScript.text(String(item))
				_expect(cjk.search(translated) == null, "Untranslated display text: " + translated)
			else:
				_check_display_values(item)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
