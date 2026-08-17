extends SceneTree

const SaveServiceScript = preload("res://scripts/core/save_service.gd")
const TEST_DIRECTORY := "user://save_service_tests"
const TEST_PATH := TEST_DIRECTORY + "/document.json"

var failures: Array[String] = []


func _init() -> void:
	_prepare_directory()
	_test_transactional_replacement()
	_test_malformed_document_preserved()
	_test_interrupted_write_recovery()
	_test_damaged_target_rollback()
	_test_invalid_settings_contract()
	_cleanup_directory()
	if failures.is_empty():
		print("SAVE_TESTS_OK: transactional writes, corruption preservation, and recovery passed.")
		quit(0)
		return
	for failure: String in failures:
		push_error("SAVE FAILURE: %s" % failure)
	quit(1)


func _test_transactional_replacement() -> void:
	_expect(SaveServiceScript._write_json(TEST_PATH, {"value": 1}), "Initial transactional write should succeed.")
	_expect(SaveServiceScript._write_json(TEST_PATH, {"value": 2}), "Replacing an existing document should succeed.")
	var result: Dictionary = SaveServiceScript._load_json_result(TEST_PATH, "测试文件")
	_expect(bool(result.get("ok", false)) and int((result.get("document", {}) as Dictionary).get("value", 0)) == 2, "Replacement should expose only the new document.")
	_expect(not FileAccess.file_exists(_absolute(TEST_PATH) + ".tmp"), "Successful writes must remove the temporary file.")
	_expect(not FileAccess.file_exists(_absolute(TEST_PATH) + ".bak"), "Successful writes must remove the rollback file.")


func _test_malformed_document_preserved() -> void:
	_remove_test_files()
	_write_raw(TEST_PATH, "{broken json")
	var original: String = FileAccess.get_file_as_string(TEST_PATH)
	var result: Dictionary = SaveServiceScript._load_json_result(TEST_PATH, "测试文件")
	_expect(not bool(result.get("ok", true)) and bool(result.get("exists", false)), "Malformed JSON should return an explicit load failure.")
	_expect(String(result.get("error", "")).contains("已损坏"), "Malformed JSON should return a readable corruption message.")
	_expect(FileAccess.get_file_as_string(TEST_PATH) == original, "Loading malformed JSON must not modify the source file.")
	_expect(_matching_preserved_copy(original), "Malformed JSON should be copied to a stable .invalid file.")


func _test_interrupted_write_recovery() -> void:
	_remove_test_files()
	_write_raw(TEST_PATH + ".bak", JSON.stringify({"turn": 7}))
	_write_raw(TEST_PATH + ".tmp", "partial")
	var result: Dictionary = SaveServiceScript._load_json_result(TEST_PATH, "测试存档")
	_expect(bool(result.get("ok", false)) and int((result.get("document", {}) as Dictionary).get("turn", 0)) == 7, "A missing target should recover its valid rollback file.")
	_expect(String(result.get("error", "")).contains("已恢复"), "Interrupted-write recovery should be reported to the player.")
	_expect(FileAccess.file_exists(TEST_PATH), "Recovery should restore the canonical document path.")
	_expect(not FileAccess.file_exists(_absolute(TEST_PATH) + ".tmp") and not FileAccess.file_exists(_absolute(TEST_PATH) + ".bak"), "Recovery should remove transaction residue.")


func _test_damaged_target_rollback() -> void:
	_remove_test_files()
	_write_raw(TEST_PATH, "damaged replacement")
	_write_raw(TEST_PATH + ".bak", JSON.stringify({"turn": 4}))
	var result: Dictionary = SaveServiceScript._load_json_result(TEST_PATH, "测试存档")
	_expect(bool(result.get("ok", false)) and int((result.get("document", {}) as Dictionary).get("turn", 0)) == 4, "A damaged replacement should roll back to its valid backup.")
	_expect(String(result.get("error", "")).contains("已恢复"), "Rollback from a damaged target should be reported.")
	_expect(_matching_preserved_copy("damaged replacement"), "The damaged replacement should remain available as an .invalid copy.")


func _test_invalid_settings_contract() -> void:
	var invalid: Dictionary = {
		"version": 1,
		"master_volume": "loud",
		"text_scale": 1.0,
		"reduced_motion": false,
		"tutorial_seen": false
	}
	_expect(not SaveServiceScript._settings_types_are_valid(invalid), "Settings with a non-numeric volume must be rejected.")
	var sanitized: Dictionary = SaveServiceScript._sanitize_settings({"master_volume": 4.0, "text_scale": 0.1, "reduced_motion": true})
	_expect(is_equal_approx(float(sanitized.get("master_volume", 0.0)), 1.0), "Master volume should clamp to one.")
	_expect(is_equal_approx(float(sanitized.get("text_scale", 0.0)), 0.85), "Text scale should clamp to its supported minimum.")
	_expect(bool(sanitized.get("reduced_motion", false)), "Boolean accessibility settings should survive sanitization.")


func _matching_preserved_copy(contents: String) -> bool:
	var directory: DirAccess = DirAccess.open(TEST_DIRECTORY)
	if directory == null:
		return false
	for file_name: String in directory.get_files():
		if file_name.begins_with("document.json.invalid") and FileAccess.get_file_as_string(TEST_DIRECTORY.path_join(file_name)) == contents:
			return true
	return false


func _prepare_directory() -> void:
	DirAccess.make_dir_recursive_absolute(_absolute(TEST_DIRECTORY))
	_remove_test_files()


func _remove_test_files() -> void:
	var directory: DirAccess = DirAccess.open(TEST_DIRECTORY)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		DirAccess.remove_absolute(_absolute(TEST_DIRECTORY.path_join(file_name)))


func _cleanup_directory() -> void:
	_remove_test_files()
	DirAccess.remove_absolute(_absolute(TEST_DIRECTORY))


func _write_raw(path: String, contents: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "Test fixture should be writable: %s" % path)
	if file == null:
		return
	file.store_string(contents)
	file.close()


func _absolute(path: String) -> String:
	return ProjectSettings.globalize_path(path)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
