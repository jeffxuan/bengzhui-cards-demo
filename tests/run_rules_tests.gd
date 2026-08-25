extends SceneTree

const ContentCatalogScript = preload("res://scripts/core/content_catalog.gd")
const MatchCommandScript = preload("res://scripts/core/match_command.gd")
const MatchStateScript = preload("res://scripts/core/match_state.gd")

var failures: Array[String] = []
var rules: Dictionary
var catalog: RefCounted


func _init() -> void:
	rules = JSON.parse_string(FileAccess.get_file_as_string("res://rules/match_rules.json")) as Dictionary
	catalog = ContentCatalogScript.new()
	_test_content_contract()
	_test_turn_resources_and_free_character_skills()
	_test_response_window_resources()
	_test_discard_phase_and_replay_continuation()
	_test_extra_action_and_round_pressure()
	_test_targeting_and_public_history()
	if failures.is_empty():
		print("RULE_TESTS_OK: v4 resources, discard continuations, responses, pressure, targeting, and public history passed.")
		quit(0)
		return
	for failure: String in failures:
		push_error("TEST FAILURE: %s" % failure)
	quit(1)


func _test_content_contract() -> void:
	_expect(bool(catalog.call("is_valid")), "Content catalog must validate.")
	_expect(int(rules.get("version", 0)) == 4, "Rules must be v4.")
	_expect(not rules.has("round_limit"), "Round limit must be removed.")
	for character_value: Variant in catalog.get("characters") as Array:
		for skill_value: Variant in (character_value as Dictionary).get("skills", []) as Array:
			var cost: Dictionary = (skill_value as Dictionary).get("cost", {}) as Dictionary
			_expect(int(cost.get("stamina", -1)) == 0 and int(cost.get("mana", -1)) == 0, "Character skills must be free.")
	for card_value: Variant in catalog.get("cards") as Array:
		var card: Dictionary = card_value as Dictionary
		if String(card.get("category", "")) == "response":
			_expect(["heavenly_sense", "shrug_off"].has(String(card.get("id", ""))), "Only two response cards may remain.")


func _test_turn_resources_and_free_character_skills() -> void:
	var state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 101)
	var active: Dictionary = state.call("player", 0) as Dictionary
	_expect(int(active.get("stamina", 0)) == int(active.get("max_stamina", 0)), "Active player restores stamina.")
	_expect(int((state.call("player", 1) as Dictionary).get("stamina", -1)) == 0 and int((state.call("player", 1) as Dictionary).get("mana", -1)) == 0, "Off-turn resources must be zero.")
	var target: Dictionary = state.call("player", 1) as Dictionary
	target["position"] = Vector2i(3, 2)
	state.players[1] = target
	active["stamina"] = 0
	active["mana"] = 0
	state.players[0] = active
	var command: Dictionary = _find_command(state, MatchCommandScript.USE_SKILL, "q_thunder_call")
	_expect(not command.is_empty(), "A character skill must remain usable at zero resources.")
	if not command.is_empty():
		_expect(bool(state.call("submit_command", command)), "Free character skill should resolve.")
		_expect(int((state.call("player", 0) as Dictionary).get("actions", 0)) == 1, "Character skill still consumes one action.")


func _test_response_window_resources() -> void:
	var state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 102)
	var source: Dictionary = state.call("player", 0) as Dictionary
	var target: Dictionary = state.call("player", 1) as Dictionary
	source["position"] = Vector2i(2, 2)
	target["position"] = Vector2i(3, 2)
	(target.get("hand", []) as Array).append("heavenly_sense")
	(target.get("hand", []) as Array).append("iron_body")
	state.players[0] = source
	state.players[1] = target
	var attack: Dictionary = _find_command(state, MatchCommandScript.PLAY_CARD, "slash")
	_expect(bool(state.call("submit_command", attack)), "Attack should open a response window.")
	var legal: Array[Dictionary] = state.call("legal_commands", 1) as Array[Dictionary]
	var response_ids: Array[String] = []
	for command: Dictionary in legal:
		var card_id: String = String((command.get("payload", {}) as Dictionary).get("card_id", ""))
		if not card_id.is_empty():
			response_ids.append(card_id)
	_expect(response_ids == ["heavenly_sense"], "Off-turn zero resources must leave only Heavenly Sense for attacks.")


func _test_discard_phase_and_replay_continuation() -> void:
	var state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 103)
	var active: Dictionary = state.call("player", 0) as Dictionary
	active["health"] = 5
	active["hand"] = ["slash", "heavy_slash", "calm_mind", "heavenly_sense"]
	active["deck"] = []
	active["discard"] = []
	state.players[0] = active
	var end_turn := MatchCommandScript.make(MatchCommandScript.END_TURN, 0)
	_expect(bool(state.call("submit_command", end_turn)), "Ending a turn should request discard when over the life-based limit.")
	var request: Dictionary = state.get("pending_discard") as Dictionary
	_expect(int(request.get("required_count", 0)) == 1, "Five health must leave a three-card hand limit.")
	var discard_command := MatchCommandScript.make(MatchCommandScript.DISCARD_CARDS, 0, {"request_id": request.get("request_id", ""), "card_ids": ["calm_mind"]})
	_expect(bool(state.call("submit_command", discard_command)), "A valid discard selection should resolve.")
	_expect((state.call("player", 0) as Dictionary).get("hand", []).size() == 3, "Selected card should leave the hand.")
	_expect((state.get("pending_discard") as Dictionary).is_empty(), "Discard request must clear after resolution.")
	var invalid_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 104)
	var invalid_active: Dictionary = invalid_state.call("player", 0) as Dictionary
	invalid_active["health"] = 5
	invalid_active["hand"] = ["slash", "heavy_slash", "calm_mind", "heavenly_sense"]
	invalid_state.players[0] = invalid_active
	invalid_state.call("submit_command", end_turn)
	var invalid_request: Dictionary = invalid_state.get("pending_discard") as Dictionary
	var invalid := MatchCommandScript.make(MatchCommandScript.DISCARD_CARDS, 0, {"request_id": invalid_request.get("request_id", ""), "card_ids": ["missing"]})
	_expect(not bool(invalid_state.call("submit_command", invalid)), "A card outside the hand must be rejected.")


func _test_extra_action_and_round_pressure() -> void:
	var state: RefCounted = _state(["k", "ginger", "maddy", "signal"], 105)
	var active: Dictionary = state.call("player", 0) as Dictionary
	active["actions"] = 2
	state.players[0] = active
	var command: Dictionary = _find_command(state, MatchCommandScript.USE_SKILL, "k_brainstorm")
	_expect(bool(state.call("submit_command", command)), "Brainstorm should resolve.")
	_expect(int((state.call("player", 0) as Dictionary).get("actions", 0)) == 2, "An extra action must offset the skill action cost.")
	state.completed_rounds = 7
	_expect(not bool(state.get("finished")), "The eighth round must not finish the match.")
	_expect(int(state.call("_duel_pressure_bonus")) == 2, "Round seven and later must retain +2 single-target pressure.")


func _test_targeting_and_public_history() -> void:
	var state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 106)
	var source: Dictionary = state.call("player", 0) as Dictionary
	var target: Dictionary = state.call("player", 1) as Dictionary
	source["position"] = Vector2i(2, 2)
	target["position"] = Vector2i(3, 2)
	source["hand"] = ["slash"]
	state.players[0] = source
	state.players[1] = target
	var preview: Dictionary = state.call("targeting_preview", 0, MatchCommandScript.PLAY_CARD, "slash") as Dictionary
	_expect(int(preview.get("range", 0)) == 1, "Slash preview must report distance one.")
	var command: Dictionary = _find_command(state, MatchCommandScript.PLAY_CARD, "slash")
	_expect(bool(state.call("submit_command", command)), "Previewed attack should resolve.")
	var history: Array = (state.call("player", 0) as Dictionary).get("public_card_history", []) as Array
	_expect(history.size() == 1 and String((history[0] as Dictionary).get("card_id", "")) == "slash", "Played cards must be publicly recorded.")


func _state(roster: Array[String], seed: int) -> RefCounted:
	return MatchStateScript.new(rules, catalog, roster, seed)


func _find_command(state: RefCounted, command_type: String, definition_id: String) -> Dictionary:
	for command: Dictionary in state.call("legal_commands", 0) as Array[Dictionary]:
		if String(command.get("type", "")) != command_type:
			continue
		var payload: Dictionary = command.get("payload", {}) as Dictionary
		if String(payload.get("card_id", payload.get("skill_id", ""))) == definition_id:
			return command
	return {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
