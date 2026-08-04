extends SceneTree

const AIControllerScript = preload("res://scripts/core/ai_controller.gd")
const ContentCatalogScript = preload("res://scripts/core/content_catalog.gd")
const MatchStateScript = preload("res://scripts/core/match_state.gd")

var match_count: int = 100


func _init() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--matches="):
			match_count = maxi(1, int(argument.trim_prefix("--matches=")))
	var catalog: RefCounted = ContentCatalogScript.new()
	if not bool(catalog.call("is_valid")):
		push_error("SIMULATION_FAILED: invalid content catalog")
		quit(1)
		return
	var parsed_rules: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://rules/match_rules.json"))
	var rules: Dictionary = parsed_rules as Dictionary if parsed_rules is Dictionary else {}
	var character_ids: Array[String] = []
	for character_value: Variant in catalog.get("characters") as Array:
		character_ids.append(String((character_value as Dictionary).get("id", "")))
	var wins: Dictionary = {}
	var appearances: Dictionary = {}
	var total_commands: int = 0
	var total_rounds: int = 0
	var total_eliminations: int = 0
	var total_single_target_damage: int = 0
	var total_area_damage: int = 0
	var total_pressure_damage: int = 0
	var finish_reasons: Dictionary = {}
	var failed_matches: int = 0
	var failure_details: Array[String] = []
	for match_index: int in match_count:
		var roster: Array[String] = _balanced_roster(character_ids, match_index)
		for character_id: String in roster:
			appearances[character_id] = int(appearances.get(character_id, 0)) + 1
		var state: RefCounted = MatchStateScript.new(rules, catalog, roster, 1000 + match_index)
		var ai: RefCounted = AIControllerScript.new()
		var command_count: int = 0
		while not bool(state.get("finished")) and command_count < 500:
			var actor_id: int
			var pending_action: Dictionary = state.get("pending_action") as Dictionary
			if not pending_action.is_empty():
				actor_id = int(pending_action.get("responder_id", -1))
			else:
				actor_id = int((state.call("current_player") as Dictionary).get("id", -1))
			var command: Dictionary = ai.call("choose_command", state, actor_id) as Dictionary
			if command.is_empty():
				failure_details.append("seed=%d empty_command actor=%d snapshot=%s" % [1000 + match_index, actor_id, JSON.stringify(state.call("deterministic_snapshot"))])
				break
			if not bool(state.call("submit_command", command)):
				failure_details.append("seed=%d rejected=%s error=%s" % [1000 + match_index, JSON.stringify(command), String(state.get("last_error"))])
				break
			command_count += 1
		total_commands += command_count
		total_rounds += int(state.get("completed_rounds"))
		if not bool(state.get("finished")):
			failed_matches += 1
			failure_details.append("seed=%d command_cap snapshot=%s" % [1000 + match_index, JSON.stringify(state.call("deterministic_snapshot"))])
		else:
			var winner_id: int = int(state.get("winner_id"))
			if winner_id < 0 or winner_id >= 4:
				failed_matches += 1
				failure_details.append("seed=%d invalid_winner=%d" % [1000 + match_index, winner_id])
				continue
			var winner_character: String = String((state.call("player", winner_id) as Dictionary).get("character_id", ""))
			wins[winner_character] = int(wins.get(winner_character, 0)) + 1
			var reason_id: String = String(state.get("win_reason_id"))
			finish_reasons[reason_id] = int(finish_reasons.get(reason_id, 0)) + 1
			for player_value: Variant in state.get("players") as Array:
				var player_state: Dictionary = player_value as Dictionary
				total_eliminations += int((player_state.get("stats", {}) as Dictionary).get("eliminations", 0))
			var metrics: Dictionary = state.get("match_metrics") as Dictionary
			total_single_target_damage += int(metrics.get("single_target_damage", 0))
			total_area_damage += int(metrics.get("area_damage", 0))
			total_pressure_damage += int(metrics.get("pressure_damage", 0))
	if failed_matches > 0:
		push_error("SIMULATION_FAILED: %d matches did not finish. %s" % [failed_matches, " | ".join(failure_details)])
		quit(1)
		return
	var balance_index: Dictionary = {}
	var balance_failures: Array[String] = []
	for character_id: String in character_ids:
		var index: float = 200.0 * float(wins.get(character_id, 0)) / float(maxi(1, int(appearances.get(character_id, 0))))
		balance_index[character_id] = snappedf(index, 0.01)
		if match_count >= 1000 and (index < 42.0 or index > 58.0):
			balance_failures.append("%s=%.2f" % [character_id, index])
	var average_commands: float = float(total_commands) / float(match_count)
	var last_survivor_rate: float = 100.0 * float(finish_reasons.get("last_survivor", 0)) / float(match_count)
	var round_limit_rate: float = 100.0 * float(finish_reasons.get("round_limit", 0)) / float(match_count)
	var gate_failures: Array[String] = balance_failures.duplicate()
	if match_count >= 1000 and last_survivor_rate < 55.0:
		gate_failures.append("last_survivor_rate=%.2f%%" % last_survivor_rate)
	if match_count >= 1000 and round_limit_rate > 45.0:
		gate_failures.append("round_limit_rate=%.2f%%" % round_limit_rate)
	if match_count >= 1000 and average_commands > 125.0:
		gate_failures.append("average_commands=%.2f" % average_commands)
	if not gate_failures.is_empty():
		push_error("SIMULATION_FAILED: release gates failed: %s balance=%s finish_reasons=%s" % [", ".join(gate_failures), JSON.stringify(balance_index), JSON.stringify(finish_reasons)])
		quit(1)
		return
	print("SIMULATION_OK: matches=%d average_commands=%.2f average_rounds=%.2f average_eliminations=%.2f finish_reasons=%s damage={single:%d,area:%d,pressure:%d} wins=%s balance_index=%s" % [match_count, average_commands, float(total_rounds) / float(match_count), float(total_eliminations) / float(match_count), JSON.stringify(finish_reasons), total_single_target_damage, total_area_damage, total_pressure_damage, JSON.stringify(wins), JSON.stringify(balance_index)])
	quit(0)


func _balanced_roster(character_ids: Array[String], match_index: int) -> Array[String]:
	var patterns: Array[Array] = [
		[0, 1, 3, 6],
		[0, 2, 5, 7],
		[0, 1, 4, 6]
	]
	var start: int = match_index % character_ids.size()
	var pattern: Array = patterns[(match_index / character_ids.size()) % patterns.size()]
	var rotation: int = (match_index / (character_ids.size() * patterns.size())) % 4
	var roster: Array[String] = []
	for seat: int in 4:
		var offset: int = int(pattern[(seat + rotation) % 4])
		roster.append(character_ids[(start + offset) % character_ids.size()])
	return roster
