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
	return load_settings_result().get("settings", DEFAULT_SETTINGS.duplicate(true)) as Dictionary


static func load_settings_result() -> Dictionary:
	var loaded_result: Dictionary = _load_json_result(SETTINGS_PATH, "设置文件")
	if not bool(loaded_result.get("exists", false)) or not bool(loaded_result.get("ok", false)):
		return {
			"settings": DEFAULT_SETTINGS.duplicate(true),
			"error": String(loaded_result.get("error", ""))
		}
	var loaded: Dictionary = loaded_result.get("document", {}) as Dictionary
	if int(loaded.get("version", 0)) != SETTINGS_VERSION or not _settings_types_are_valid(loaded):
		var preserved_path: String = _preserve_file(SETTINGS_PATH)
		return {
			"settings": DEFAULT_SETTINGS.duplicate(true),
			"error": _preserved_error("设置文件版本不兼容或内容无效，已使用默认设置。", preserved_path)
		}
	return {
		"settings": _sanitize_settings(loaded),
		"error": String(loaded_result.get("error", ""))
	}


static func save_settings(settings: Dictionary) -> bool:
	return _write_json(SETTINGS_PATH, _sanitize_settings(settings))


static func save_replay(replay: Dictionary) -> bool:
	return _write_json(REPLAY_PATH, replay)


static func load_replay() -> Dictionary:
	return load_replay_result().get("document", {}) as Dictionary


static func load_replay_result() -> Dictionary:
	return _load_json_result(REPLAY_PATH, "对局存档")


static func clear_replay() -> void:
	_remove_if_exists(ProjectSettings.globalize_path(REPLAY_PATH))
	_remove_if_exists(ProjectSettings.globalize_path(REPLAY_PATH) + ".tmp")
	_remove_if_exists(ProjectSettings.globalize_path(REPLAY_PATH) + ".bak")


static func rebuild_match(match_state_script: Script, rules: Dictionary, catalog: RefCounted, replay: Dictionary) -> Dictionary:
	for version_key: String in ["version", "content_version", "rules_version", "seed"]:
		if not _is_number(replay.get(version_key)):
			return {"ok": false, "error": "对局存档结构不完整，原文件未修改。"}
	if int(replay.get("version", 0)) != 1:
		return {"ok": false, "error": "无法读取不同版本的对局存档。"}
	if int(replay.get("content_version", -1)) != int(catalog.get("version")):
		return {"ok": false, "error": "内容版本已经变化，旧对局仍保留但不能继续。"}
	if int(replay.get("rules_version", -1)) != int(rules.get("version", 1)):
		return {"ok": false, "error": "规则版本已经变化，旧对局仍保留但不能继续。"}
	var roster_value: Variant = replay.get("roster")
	var commands_value: Variant = replay.get("commands")
	if not roster_value is Array or (roster_value as Array).size() != 4 or not commands_value is Array:
		return {"ok": false, "error": "对局存档结构不完整，原文件未修改。"}
	var roster: Array[String] = []
	for item: Variant in roster_value as Array:
		if not item is String or (catalog.call("character", String(item)) as Dictionary).is_empty():
			return {"ok": false, "error": "对局存档包含无效角色，原文件未修改。"}
		roster.append(String(item))
	var state: RefCounted = match_state_script.new(rules, catalog, roster, int(replay.get("seed", 114))) as RefCounted
	for command_value: Variant in commands_value as Array:
		if not command_value is Dictionary or not bool(state.call("submit_command", command_value as Dictionary)):
			return {"ok": false, "error": "存档中的命令无法重放，原文件未修改。"}
	return {"ok": true, "state": state}


static func _sanitize_settings(settings: Dictionary) -> Dictionary:
	var sanitized: Dictionary = DEFAULT_SETTINGS.duplicate(true)
	sanitized["master_volume"] = clampf(float(settings.get("master_volume", 0.8)), 0.0, 1.0)
	sanitized["text_scale"] = clampf(float(settings.get("text_scale", 1.0)), 0.85, 1.35)
	sanitized["reduced_motion"] = bool(settings.get("reduced_motion", false))
	sanitized["tutorial_seen"] = bool(settings.get("tutorial_seen", false))
	return sanitized


static func _settings_types_are_valid(settings: Dictionary) -> bool:
	return _is_number(settings.get("master_volume")) \
		and _is_number(settings.get("text_scale")) \
		and settings.get("reduced_motion") is bool \
		and settings.get("tutorial_seen") is bool


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _load_json_result(path: String, label: String) -> Dictionary:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	var recovery_message: String = _recover_interrupted_write(absolute_path, label)
	if not FileAccess.file_exists(absolute_path):
		return {"ok": true, "exists": false, "document": {}, "error": recovery_message}
	var parsed: Dictionary = _read_dictionary(absolute_path)
	if bool(parsed.get("ok", false)):
		_remove_if_exists(absolute_path + ".tmp")
		_remove_if_exists(absolute_path + ".bak")
		return {
			"ok": true,
			"exists": true,
			"document": parsed.get("document", {}) as Dictionary,
			"error": recovery_message
		}

	var backup_path: String = absolute_path + ".bak"
	var backup: Dictionary = _read_dictionary(backup_path)
	if bool(backup.get("ok", false)):
		var damaged_copy: String = _preserve_file(absolute_path)
		_remove_if_exists(absolute_path)
		if DirAccess.rename_absolute(backup_path, absolute_path) == OK:
			_remove_if_exists(absolute_path + ".tmp")
			return {
				"ok": true,
				"exists": true,
				"document": backup.get("document", {}) as Dictionary,
				"error": _preserved_error("检测到%s写入中断，已恢复上一份可用数据。" % label, damaged_copy)
			}
	var preserved_path: String = _preserve_file(absolute_path)
	return {
		"ok": false,
		"exists": true,
		"document": {},
		"error": _preserved_error("%s已损坏，无法读取。" % label, preserved_path)
	}


static func _write_json(path: String, document: Dictionary) -> bool:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	_recover_interrupted_write(absolute_path, "文件")
	var temporary_path: String = absolute_path + ".tmp"
	var backup_path: String = absolute_path + ".bak"
	_remove_if_exists(temporary_path)
	var file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(document, "  "))
	file.flush()
	file.close()
	if not bool(_read_dictionary(temporary_path).get("ok", false)):
		_remove_if_exists(temporary_path)
		return false

	var had_target: bool = FileAccess.file_exists(absolute_path)
	if had_target:
		_remove_if_exists(backup_path)
		if DirAccess.rename_absolute(absolute_path, backup_path) != OK:
			_remove_if_exists(temporary_path)
			return false
	if DirAccess.rename_absolute(temporary_path, absolute_path) != OK:
		if had_target:
			DirAccess.rename_absolute(backup_path, absolute_path)
		_remove_if_exists(temporary_path)
		return false
	_remove_if_exists(backup_path)
	return true


static func _recover_interrupted_write(absolute_path: String, label: String) -> String:
	if FileAccess.file_exists(absolute_path):
		return ""
	var backup_path: String = absolute_path + ".bak"
	if bool(_read_dictionary(backup_path).get("ok", false)) and DirAccess.rename_absolute(backup_path, absolute_path) == OK:
		_remove_if_exists(absolute_path + ".tmp")
		return "检测到%s写入中断，已恢复上一份可用数据。" % label
	var temporary_path: String = absolute_path + ".tmp"
	if bool(_read_dictionary(temporary_path).get("ok", false)) and DirAccess.rename_absolute(temporary_path, absolute_path) == OK:
		return "检测到%s写入中断，已完成未结束的写入。" % label
	if FileAccess.file_exists(temporary_path):
		var preserved_path: String = _preserve_file(temporary_path)
		return _preserved_error("检测到无法恢复的%s临时文件。" % label, preserved_path)
	return ""


static func _read_dictionary(absolute_path: String) -> Dictionary:
	if not FileAccess.file_exists(absolute_path):
		return {"ok": false, "document": {}}
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(absolute_path)) != OK:
		return {"ok": false, "document": {}}
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		return {"ok": false, "document": {}}
	return {"ok": true, "document": parsed as Dictionary}


static func _preserve_file(path: String) -> String:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute_path):
		return ""
	var contents: String = FileAccess.get_file_as_string(absolute_path)
	var candidate: String = absolute_path + ".invalid"
	var suffix: int = 1
	while FileAccess.file_exists(candidate):
		if FileAccess.get_file_as_string(candidate) == contents:
			return candidate
		candidate = "%s.invalid.%d" % [absolute_path, suffix]
		suffix += 1
	var source: FileAccess = FileAccess.open(absolute_path, FileAccess.READ)
	var destination: FileAccess = FileAccess.open(candidate, FileAccess.WRITE)
	if source == null or destination == null:
		if source != null:
			source.close()
		if destination != null:
			destination.close()
		return ""
	destination.store_buffer(source.get_buffer(source.get_length()))
	destination.flush()
	source.close()
	destination.close()
	return candidate


static func _preserved_error(message: String, preserved_path: String) -> String:
	if preserved_path.is_empty():
		return "%s 原文件仍保留在存档目录。" % message
	return "%s 副本已保留为 %s。" % [message, preserved_path.get_file()]


static func _remove_if_exists(absolute_path: String) -> void:
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)
