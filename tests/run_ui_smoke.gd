extends SceneTree

const VIEWPORT_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440)
]

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
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
		_expect(main.get("screen_root") != null, "Character selection must render at %s." % str(viewport_size))
		_expect(_count_buttons(main) >= 10, "Character selection must expose the roster and commands at %s." % str(viewport_size))
		var start_button: Button = main.get("start_button") as Button
		_expect(start_button != null, "Start command must exist at %s." % str(viewport_size))
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
		main.queue_free()
		await process_frame
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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("UI_SMOKE_OK: selection and match HUD passed at three target resolutions.")
		quit(0)
		return
	for failure: String in failures:
		push_error("UI FAILURE: %s" % failure)
	quit(1)
