extends SceneTree

const SaveServiceScript = preload("res://scripts/core/save_service.gd")
const VIEWPORT_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440)
]

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_replay_exists: bool = FileAccess.file_exists(ProjectSettings.globalize_path(SaveServiceScript.REPLAY_PATH))
	var original_replay_contents: String = FileAccess.get_file_as_string(ProjectSettings.globalize_path(SaveServiceScript.REPLAY_PATH)) if original_replay_exists else ""
	var packed_scene: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	_expect(packed_scene != null, "Main scene must load.")
	if packed_scene == null:
		_finish()
		return
	for viewport_size: Vector2i in VIEWPORT_SIZES:
		root.size = viewport_size
		var main: Control = packed_scene.instantiate() as Control
		root.add_child(main)
		await process_frame
		await process_frame
		var original_settings: Dictionary = (main.get("settings") as Dictionary).duplicate(true)
		main.call("_set_text_scale", 1.35)
		main.call("_show_character_select", "对局存档已损坏，无法读取。 副本已保留为 resume_match.json.invalid。")
		await process_frame
		await process_frame
		var notice_label: Label = _find_label_containing(main, "resume_match.json.invalid")
		var scaled_start_button: Button = main.get("start_button") as Button
		_expect(notice_label != null and notice_label.is_visible_in_tree() and _inside_viewport(notice_label, viewport_size), "Corrupt-save feedback must remain visible at maximum text scale at %s." % str(viewport_size))
		_expect(scaled_start_button != null and _inside_viewport(scaled_start_button, viewport_size), "Recovery feedback must leave the start command on-screen at %s (rect %s)." % [str(viewport_size), str(scaled_start_button.get_global_rect() if scaled_start_button != null else Rect2())])
		main.call("_set_text_scale", float(original_settings.get("text_scale", 1.0)))
		main.call("_show_character_select")
		await process_frame
		await process_frame
		_expect(main.get("screen_root") != null, "Character selection must render at %s." % str(viewport_size))
		_expect(_count_buttons(main) >= 10, "Character selection must expose the roster and commands at %s." % str(viewport_size))
		_expect(_is_visible_enabled_button(root.gui_get_focus_owner()), "Character selection must give keyboard focus to a visible enabled button at %s." % str(viewport_size))
		var start_button: Button = main.get("start_button") as Button
		_expect(start_button != null, "Start command must exist at %s." % str(viewport_size))
		(main.get("settings") as Dictionary)["tutorial_seen"] = true
		start_button.pressed.emit()
		await process_frame
		await process_frame
		var board: Control = main.get("board_view") as Control
		var hand_band: Control = main.get("hand_band") as Control
		var end_turn: Button = main.get("end_turn_button") as Button
		var audio_feedback: Node = main.get("audio_feedback") as Node
		_expect(board != null and board.size.x >= 360.0 and board.size.y >= 360.0, "Board must remain usable at %s." % str(viewport_size))
		_expect(hand_band != null and hand_band.size.y >= 140.0, "Hand band must keep its height at %s (actual %s)." % [str(viewport_size), str(hand_band.size if hand_band != null else Vector2.ZERO)])
		_expect(hand_band != null and hand_band.get_global_rect().end.y <= float(viewport_size.y), "Hand band must remain inside %s (rect %s)." % [str(viewport_size), str(hand_band.get_global_rect() if hand_band != null else Rect2())])
		_expect(end_turn != null and end_turn.is_visible_in_tree(), "End-turn command must remain visible at %s." % str(viewport_size))
		_expect(audio_feedback != null and audio_feedback.get_child_count() == 6, "Audio feedback channels must be ready at %s." % str(viewport_size))
		_expect(_is_visible_enabled_button(root.gui_get_focus_owner()), "Match HUD must retain a usable keyboard focus target at %s." % str(viewport_size))
		main.call("_unhandled_key_input", _key_event(KEY_ESCAPE))
		await process_frame
		await process_frame
		var modal_layer: ColorRect = main.get("modal_layer") as ColorRect
		_expect(bool(main.get("settings_open")) and modal_layer != null and modal_layer.is_visible_in_tree(), "Escape must open settings at %s." % str(viewport_size))
		_expect(root.gui_get_focus_owner() is HSlider, "Settings must focus the first keyboard-adjustable control at %s." % str(viewport_size))
		main.call("_unhandled_key_input", _key_event(KEY_ESCAPE))
		await process_frame
		await process_frame
		_expect(not bool(main.get("settings_open")), "A second Escape must close settings at %s." % str(viewport_size))
		main.call("_set_text_scale", 1.35)
		main.call("_set_reduced_motion", true)
		main.call("_build_match_screen")
		main.call("_refresh_match_ui")
		await process_frame
		await process_frame
		board = main.get("board_view") as Control
		hand_band = main.get("hand_band") as Control
		end_turn = main.get("end_turn_button") as Button
		_expect(is_equal_approx(float((main.get("settings") as Dictionary).get("text_scale", 0.0)), 1.35), "Maximum text scale must remain applied at %s." % str(viewport_size))
		_expect(bool((main.get("settings") as Dictionary).get("reduced_motion", false)), "Reduced-motion mode must remain enabled at %s." % str(viewport_size))
		_expect(board != null and board.size.x >= 360.0 and board.size.y >= 360.0, "Board must remain usable at maximum text scale at %s." % str(viewport_size))
		_expect(hand_band != null and _inside_viewport(hand_band, viewport_size), "Hand band must remain on-screen at maximum text scale at %s (rect %s)." % [str(viewport_size), str(hand_band.get_global_rect() if hand_band != null else Rect2())])
		_expect(end_turn != null and end_turn.is_visible_in_tree() and _inside_viewport(end_turn, viewport_size), "End-turn control must remain on-screen at maximum text scale at %s (rect %s)." % [str(viewport_size), str(end_turn.get_global_rect() if end_turn != null else Rect2())])
		main.call("_open_debug_info")
		await process_frame
		var modal_description: Label = main.get("modal_description") as Label
		_expect(modal_description != null and modal_description.text.contains("种子"), "Debug panel must expose the match seed at %s." % str(viewport_size))
		main.call("_close_debug_info")
		await process_frame
		main.call("_open_tutorial")
		await process_frame
		var modal_actions: VBoxContainer = main.get("modal_actions") as VBoxContainer
		var tutorial_close: Button = modal_actions.get_child(0) as Button
		tutorial_close.pressed.emit()
		await process_frame
		var skill_box: VBoxContainer = main.get("skill_box") as VBoxContainer
		var skill_button: Button = _first_enabled_button(skill_box)
		_expect(skill_button != null, "At least one starting skill must be usable at %s." % str(viewport_size))
		if skill_button != null:
			skill_button.pressed.emit()
			await process_frame
		SaveServiceScript.save_settings(original_settings)
		main.queue_free()
		await process_frame
	_restore_replay(original_replay_exists, original_replay_contents)
	_finish()


func _count_buttons(node: Node) -> int:
	var count: int = 1 if node is Button else 0
	for child: Node in node.get_children():
		count += _count_buttons(child)
	return count


func _first_enabled_button(node: Node) -> Button:
	for child: Node in node.get_children():
		if child is Button and not (child as Button).disabled:
			return child as Button
	return null


func _find_label_containing(node: Node, needle: String) -> Label:
	if node is Label and (node as Label).text.contains(needle):
		return node as Label
	for child: Node in node.get_children():
		var match_label: Label = _find_label_containing(child, needle)
		if match_label != null:
			return match_label
	return null


func _key_event(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _is_visible_enabled_button(node: Control) -> bool:
	return node is Button and not (node as Button).disabled and node.is_visible_in_tree()


func _inside_viewport(control: Control, viewport_size: Vector2i) -> bool:
	var rect: Rect2 = control.get_global_rect()
	return rect.position.x >= -0.5 and rect.position.y >= -0.5 and rect.end.x <= float(viewport_size.x) + 0.5 and rect.end.y <= float(viewport_size.y) + 0.5


func _restore_replay(existed: bool, contents: String) -> void:
	var absolute_path: String = ProjectSettings.globalize_path(SaveServiceScript.REPLAY_PATH)
	if not existed:
		SaveServiceScript.clear_replay()
		return
	var file: FileAccess = FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		failures.append("UI smoke could not restore the original replay file.")
		return
	file.store_string(contents)
	file.close()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("UI_SMOKE_OK: keyboard, accessibility settings, and layout passed at three target resolutions.")
		quit(0)
		return
	for failure: String in failures:
		push_error("UI FAILURE: %s" % failure)
	quit(1)
