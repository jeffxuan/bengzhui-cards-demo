extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const MATCH_STATE := preload("res://scripts/core/match_state.gd")
const FPS := 24
const SEED := 4603
const ROSTER: Array[String] = ["q", "ginger", "maddy", "signal"]

var frame_index := 0
var output_dir := ""
var audio_cues: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	output_dir = OS.get_environment("BENGZHUI_RECORD_DIR")
	if output_dir.is_empty():
		push_error("Set BENGZHUI_RECORD_DIR to an existing directory.")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var main: Control = MAIN_SCENE.instantiate() as Control
	root.add_child(main)
	await process_frame
	var catalog: RefCounted = main.get("catalog") as RefCounted
	var rules: Dictionary = main.get("rules") as Dictionary
	var ai: RefCounted = main.get("ai_controller") as RefCounted
	var probe: RefCounted = MATCH_STATE.new(rules, catalog, ROSTER, SEED)
	probe.call("drain_events")
	var commands: Array[Dictionary] = []
	var hit_indices: Array[int] = []
	for _step: int in 250:
		if bool(probe.get("finished")) or hit_indices.size() >= 4:
			break
		var actor_id: int = _required_actor(probe)
		var command: Dictionary = ai.call("choose_command", probe, actor_id) as Dictionary
		if command.is_empty() or not bool(probe.call("submit_command", command)):
			push_error("Failed to prepare replay at command %d." % commands.size())
			quit(1)
			return
		commands.append(command)
		var events: Array[Dictionary] = probe.call("drain_events") as Array[Dictionary]
		for event: Dictionary in events:
			if String(event.get("type", "")) == "damage" and int((event.get("payload", {}) as Dictionary).get("amount", 0)) > 0:
				hit_indices.append(commands.size() - 1)
				break
	if hit_indices.is_empty():
		push_error("No real damage event found in the fixed-seed match.")
		quit(1)
		return
	var start_index: int = maxi(0, hit_indices[0] - 4)
	var end_index: int = mini(commands.size(), hit_indices[min(2, hit_indices.size() - 1)] + 1)
	var state: RefCounted = MATCH_STATE.new(rules, catalog, ROSTER, SEED)
	state.call("drain_events")
	for index: int in start_index:
		state.call("submit_command", commands[index])
		state.call("drain_events")
	main.set("ai_running", true)
	(main.get("settings") as Dictionary)["reduced_motion"] = false
	main.set("state", state)
	main.set("selected_character_id", "q")
	main.call("_build_match_screen")
	main.call("_refresh_match_ui")
	await _capture_seconds(1.0)
	# Dedicated Q showcase: the storm cloud is a skill cue, not a generic lightning hit.
	var board: BoardView3D = main.get("board_view") as BoardView3D
	board.show_match_event({"type": "skill_used", "payload": {"player_id": 0, "target_id": 1, "skill_id": "q_thunderstorm"}})
	board.call("_spawn_skeleton_flash", 1)
	await _capture_seconds(1.15)
	for index: int in range(start_index, end_index):
		if not bool(state.call("submit_command", commands[index])):
			push_error("Replay diverged at command %d." % index)
			quit(1)
			return
		var events: Array[Dictionary] = (state.get("recent_events") as Array[Dictionary]).duplicate(true)
		for event: Dictionary in events:
			var event_type: String = String(event.get("type", ""))
			if event_type in ["card_played", "skill_used", "damage", "defeated", "board_collapsed"]:
				audio_cues.append({"frame": frame_index, "type": event_type, "amount": int((event.get("payload", {}) as Dictionary).get("amount", 0))})
		main.call("_collect_events")
		main.call("_refresh_match_ui")
		var hold: float = 0.72 if _has_damage(events) else (0.40 if _has_card(events) else 0.18)
		await _capture_seconds(hold)
	await _capture_seconds(1.0)
	var metadata := {"fps": FPS, "frames": frame_index, "seed": SEED, "first_hit_command": hit_indices[0], "start_command": start_index, "end_command": end_index, "audio_cues": audio_cues}
	var metadata_file: FileAccess = FileAccess.open(output_dir.path_join("recording.json"), FileAccess.WRITE)
	metadata_file.store_string(JSON.stringify(metadata, "  "))
	metadata_file.close()
	print("RECORDING_OK: frames=%d hits=%d commands=%d-%d" % [frame_index, hit_indices.size(), start_index, end_index])
	quit(0)


func _capture_seconds(seconds: float) -> void:
	for _frame: int in maxi(1, int(ceil(seconds * FPS))):
		await create_timer(1.0 / float(FPS)).timeout
		await process_frame
		var image: Image = root.get_texture().get_image()
		if image == null or image.is_empty():
			push_error("Viewport capture failed at frame %d." % frame_index)
			quit(1)
			return
		image.save_png(output_dir.path_join("%05d.png" % frame_index))
		frame_index += 1


func _has_damage(events: Array[Dictionary]) -> bool:
	for event: Dictionary in events:
		if String(event.get("type", "")) == "damage":
			return true
	return false


func _has_card(events: Array[Dictionary]) -> bool:
	for event: Dictionary in events:
		if String(event.get("type", "")) in ["card_played", "skill_used"]:
			return true
	return false


func _required_actor(state: RefCounted) -> int:
	for field: String in ["pending_action", "pending_discard", "pending_skill_discard", "pending_skill_choice"]:
		var pending: Dictionary = state.get(field) as Dictionary
		if not pending.is_empty():
			return int(pending.get("responder_id", pending.get("player_id", -1)))
	return int((state.call("current_player") as Dictionary).get("id", -1))
