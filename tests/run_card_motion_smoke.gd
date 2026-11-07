extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const MATCH_STATE := preload("res://scripts/core/match_state.gd")
const MATCH_COMMAND := preload("res://scripts/core/match_command.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main: Control = MAIN_SCENE.instantiate() as Control
	root.add_child(main)
	await process_frame
	var settings: Dictionary = main.get("settings") as Dictionary
	settings["reduced_motion"] = false
	var match_state: RefCounted = MATCH_STATE.new(main.get("rules") as Dictionary, main.get("catalog") as RefCounted, ["k", "q", "shya", "ginger"], 4603)
	match_state.call("drain_events")
	main.set("state", match_state)
	main.call("_build_match_screen")
	main.call("_refresh_match_ui")
	await process_frame
	if not bool(match_state.call("submit_command", MATCH_COMMAND.make(MATCH_COMMAND.SWITCH_PROFESSION, 0, {"profession": ""}))):
		push_error("Cannot complete opening profession choice.")
		quit(1)
		return
	match_state.call("drain_events")
	main.call("_refresh_match_ui")
	await process_frame
	await process_frame
	await process_frame
	var motion_layer: Control = main.get("card_motion_layer") as Control
	var hand_scroll: ScrollContainer = main.get("hand_scroll") as ScrollContainer
	var hand_box: HBoxContainer = main.get("hand_box") as HBoxContainer
	if hand_box.size.x > hand_scroll.size.x and hand_scroll.scroll_horizontal <= 0:
		push_error("Draw animation must scroll new cards into view.")
		quit(1)
		return
	if motion_layer.get_child_count() < 1:
		push_error("Draw animation did not create a flying card.")
		quit(1)
		return
	await _capture("draw")
	await create_timer(0.35).timeout
	var card: Control = hand_box.get_child(0) as Control
	var card_id: String = String(card.get_meta("card_id", ""))
	main.call("_queue_play_visual", {"type": "card_played", "payload": {"player_id": 0, "target_id": 1, "card_id": card_id}})
	main.call("_animate_played_cards")
	if motion_layer.get_child_count() < 1:
		push_error("Play animation did not create a flying card.")
		quit(1)
		return
	await create_timer(0.09).timeout
	await _capture("play")
	await create_timer(0.28).timeout
	var board: BoardView3D = main.get("board_view") as BoardView3D
	board.show_match_event({"type": "damage", "payload": {"source_id": 0, "target_id": 1, "amount": 2}})
	var debris_count: int = 0
	for child: Node in board.world_root.get_children():
		if child is RigidBody3D:
			debris_count += 1
	if debris_count < 8:
		push_error("Damage impact must create physics-driven debris.")
		quit(1)
		return
	await create_timer(0.08).timeout
	await _capture("impact")
	board.show_match_event({"type": "skill_used", "payload": {"player_id": 0, "skill_id": "q_thunderstorm"}})
	var storm_found := false
	for child: Node in board.world_root.get_children():
		if child.name == "StormCloud":
			storm_found = true
			break
	if not storm_found:
		push_error("Lightning impact must create a storm cloud feedback layer.")
		quit(1)
		return
	await _capture("storm-cloud")
	await create_timer(0.48).timeout
	for child: Node in board.world_root.get_children():
		if child is RigidBody3D:
			push_error("Impact debris must be removed after feedback completes.")
			quit(1)
			return
	settings["reduced_motion"] = true
	board.set_reduced_motion(true)
	board.show_match_event({"type": "damage", "payload": {"source_id": 0, "target_id": 1, "amount": 2}})
	for child: Node in board.world_root.get_children():
		if child is RigidBody3D:
			push_error("Reduced motion must not create physics debris.")
			quit(1)
			return
	main.call("_queue_play_visual", {"type": "card_played", "payload": {"player_id": 0, "target_id": 1, "card_id": card_id}})
	main.call("_animate_played_cards")
	if motion_layer.get_child_count() != 0:
		push_error("Reduced motion must not leave visual card clones.")
		quit(1)
		return
	print("CARD_MOTION_OK: draw, play, physical impact and reduced motion passed.")
	main.queue_free()
	quit(0)


func _capture(name: String) -> void:
	var directory: String = OS.get_environment("BENGZHUI_CARD_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await process_frame
	root.get_texture().get_image().save_png(directory.path_join("%s.png" % name))
