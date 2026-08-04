class_name SaveService
extends RefCounted

const SETTINGS_PATH := "user://settings.json"
const REPLAY_PATH := "user://resume_match.json"
const SETTINGS_VERSION := 1
const DEFAULT_SETTINGS: Dictionary = {
	"version": SETTINGS_VERSION,
	"master_volume": 0.8,
	"text_scale": 1.0,
	"reduced_motion": false,
	"tutorial_seen": false
}


static func load_settings() -> Dictionary:
	var loaded: Dictionary = _load_json(SETTINGS_PATH)
	if loaded.is_empty() or int(loaded.get("version", 0)) != SETTINGS_VERSION:
		return DEFAULT_SETTINGS.duplicate(true)
	var result: Dictionary = DEFAULT_SETTINGS.duplicate(true)
	for key: Variant in loaded.keys():
		if result.has(key):
			result[key] = loaded[key]
	result["master_volume"] = clampf(float(result["master_volume"]), 0.0, 1.0)
	result["text_scale"] = clampf(float(result["text_scale"]), 0.85, 1.35)
	return result


static func save_settings(settings: Dictionary) -> bool:
	var sanitized: Dictionary = DEFAULT_SETTINGS.duplicate(true)
	sanitized["master_volume"] = clampf(float(settings.get("master_volume", 0.8)), 0.0, 1.0)
	sanitized["text_scale"] = clampf(float(settings.get("text_scale", 1.0)), 0.85, 1.35)
	sanitized["reduced_motion"] = bool(settings.get("reduced_motion", false))
	sanitized["tutorial_seen"] = bool(settings.get("tutorial_seen", false))
	return _write_json(SETTINGS_PATH, sanitized)


static func save_replay(replay: Dictionary) -> bool:
	return _write_json(REPLAY_PATH, replay)


static func load_replay() -> Dictionary:
	return _load_json(REPLAY_PATH)


static func clear_replay() -> void:
	if FileAccess.file_exists(REPLAY_PATH):
		DirAccess.remove_absolute(REPLAY_PATH)


static func rebuild_match(match_state_script: Script, rules: Dictionary, catalog: RefCounted, replay: Dictionary) -> Dictionary:
	if int(replay.get("version", 0)) != 1:
		return {"ok": false, "error": "无法读取不同版本的对局存档。"}
	if int(replay.get("content_version", -1)) != int(catalog.get("version")):
		return {"ok": false, "error": "内容版本已经变化，旧对局仍保留但不能继续。"}
	if int(replay.get("rules_version", -1)) != int(rules.get("version", 1)):
		return {"ok": false, "error": "规则版本已经变化，旧对局仍保留但不能继续。"}
	var roster: Array[String] = []
	for item: Variant in replay.get("roster", []) as Array:
		roster.append(String(item))
	var state: RefCounted = match_state_script.new(rules, catalog, roster, int(replay.get("seed", 114))) as RefCounted
	for command_value: Variant in replay.get("commands", []) as Array:
		if not command_value is Dictionary or not bool(state.call("submit_command", command_value as Dictionary)):
			return {"ok": false, "error": "存档中的命令无法重放，原文件未修改。"}
	return {"ok": true, "state": state}


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


static func _write_json(path: String, document: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(document, "  "))
	file.close()
	return true
