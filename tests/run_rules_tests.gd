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
	_test_profession_switch_and_opening_draw()
	_test_turn_resources_and_free_character_skills()
	_test_response_window_resources()
	_test_discard_phase_and_replay_continuation()
	_test_extra_action_and_round_pressure()
	_test_targeting_and_public_history()
	_test_purchased_cards_persist()
	_test_thunderstorm_skill_discard()
	if failures.is_empty():
		print("RULE_TESTS_OK: v4 resources, discard continuations, responses, pressure, targeting, and public history passed.")
		quit(0)
		return
	for failure: String in failures:
		push_error("TEST FAILURE: %s" % failure)
	quit(1)


func _test_content_contract() -> void:
	_expect(bool(catalog.call("is_valid")), "Content catalog must validate.")
	var instances: Array = catalog.get("card_instances") as Array
	_expect(instances.size() == (catalog.get("cards") as Array).size(), "Legacy logical cards must each receive one instance.")
	var slash_instance: Dictionary = catalog.call("card_instance", "slash#001") as Dictionary
	_expect(String(slash_instance.get("card_id", "")) == "slash", "Card instances must retain their logical card ID.")
	var resolved_instance: Dictionary = catalog.call("card", "slash#001") as Dictionary
	_expect(String(resolved_instance.get("id", "")) == "slash", "Card lookup must resolve instance IDs.")
	_expect(String(catalog.call("logical_card_id", "slash#001")) == "slash", "Logical card ID lookup must resolve instances.")
	_expect(String(slash_instance.get("suit", "")) == "none" and int(slash_instance.get("rank", -1)) == 0, "Legacy cards must normalize neutral suit metadata.")
	_expect((catalog.call("provisional_report") as Array).size() == 200, "Provisional report must include staged cards, events, and characters.")
	_expect((catalog.get("staged_characters") as Array).size() == 8, "新版首发角色暂存清单应包含8名角色。")
	var q_staged: Dictionary = catalog.call("staged_character", "q") as Dictionary
	_expect((q_staged.get("professions", []) as Array).size() == 2, "Q must expose both revised professions.")
	var q_skill: Dictionary = catalog.call("staged_skill", "q", "q_thunderstorm") as Dictionary
	_expect(not q_skill.is_empty() and bool(q_skill.get("source_text", "") != ""), "Staged character skills must be addressable by stable ID.")
	var q_runtime: Dictionary = catalog.call("executable_staged_skill", "q", "q_thunderstorm") as Dictionary
	_expect(String(q_runtime.get("target", "")) == "all_enemies_in_range" and (q_runtime.get("effects", []) as Array).size() == 2, "Q Thunderstorm must expose a provisional executable effect chain.")
	_expect(int((q_runtime.get("discard_requirement", {}) as Dictionary).get("rank_sum", 0)) == 23, "Thunderstorm must expose its rank-sum discard requirement.")
	_expect(int(catalog.call("staged_skill", "k", "k_brain").get("uses_per_turn", 0)) == 1, "Explicit once-per-turn skill limits must be structured.")
	_expect(not (catalog.call("staged_skill", "ginger", "ginger_waist") as Dictionary).has("uses_per_turn"), "Skills without explicit limits must remain reusable.")
	_expect((catalog.call("staged_instance_ids_for_suit", "spades") as Array).size() > 0, "Suit query must return staged card instances.")
	_expect((catalog.call("staged_instance_ids_for_color", "red") as Array).size() > 0, "Color query must return staged card instances.")
	_expect((catalog.call("staged_instance_ids_for_rank", 13) as Array).size() > 0, "Rank query must return staged card instances.")
	_expect(int(catalog.call("staged_rank_sum", ["slash_new#001", "slash_new#002"])) == 3, "Rank sum must resolve staged instance IDs.")
	var staged_hand: Array = ["slash_new#001", "slash_new#002", "tusk_new#001", "crossfire_new#001"]
	_expect(String(catalog.call("validate_rank_sum_selection", staged_hand, ["slash_new#001", "tusk_new#001"], 2, 1)) == "", "Rank-sum selection should accept an exact valid selection.")
	_expect(not String(catalog.call("validate_rank_sum_selection", staged_hand, ["slash_new#001"], 2, 1)).is_empty(), "Rank-sum selection should reject an incorrect sum.")
	_expect(not String(catalog.call("validate_rank_sum_selection", staged_hand, ["slash_new#001", "slash_new#001"], 2, 1)).is_empty(), "Rank-sum selection should reject duplicate instances.")
	_expect((catalog.get("staged_events") as Array).size() == 27, "新版事件暂存清单应包含文档中的27个事件。")
	_expect((catalog.get("staged_cards") as Array).size() == 165, "新版通用牌及六个职业牌暂存清单应包含165种牌。")
	var staged_instance: Dictionary = catalog.call("staged_card_instance", "slash_new", 0) as Dictionary
	_expect(String(staged_instance.get("instance_id", "")) == "slash_new#001" and String(staged_instance.get("suit", "")) == "spades", "Staged card instances must resolve suit and ID.")
	_expect((catalog.call("staged_card_ids_for_profession", "berserker") as Array).size() == 21, "Berserker staged pool must expose 21 definitions.")
	_expect((catalog.call("staged_instance_ids_for_profession", "shooter") as Array).size() == 75, "Shooter staged pool must expose 75 instances.")
	var shooter_pool: Array = catalog.call("staged_draw_pool_for_profession", "shooter") as Array
	_expect(shooter_pool.has("slash_new#001") and shooter_pool.has("sniper_new#001"), "Profession draw pool must include common and current-profession cards.")
	_expect(not shooter_pool.has("berserker_blow_new#001"), "Profession draw pool must exclude other professions.")
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


func _test_profession_switch_and_opening_draw() -> void:
	var keep_state: RefCounted = MatchStateScript.new(rules, catalog, ["q", "ginger", "maddy", "signal"], 100)
	_expect(bool(keep_state.get("profession_choice_pending")), "Turn must begin with profession choice.")
	keep_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SWITCH_PROFESSION, 0, {"profession": ""}))
	_expect((keep_state.call("player", 0) as Dictionary).get("hand", []).size() == 7, "Keeping profession on round one draws three cards.")
	var switch_state: RefCounted = MatchStateScript.new(rules, catalog, ["q", "ginger", "maddy", "signal"], 100)
	switch_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SWITCH_PROFESSION, 0, {"profession": "shooter"}))
	var switched_player: Dictionary = switch_state.call("player", 0) as Dictionary
	_expect(String(switched_player.get("profession", "")) == "shooter", "Q must switch to the documented secondary profession.")
	_expect((switched_player.get("hand", []) as Array).size() == 6, "Switching profession on round one draws two cards.")
	var ginger_state: RefCounted = MatchStateScript.new(rules, catalog, ["ginger", "q", "maddy", "signal"], 101)
	var ginger: Dictionary = ginger_state.call("player", 0) as Dictionary
	_expect((ginger.get("professions", []) as Array).size() == 1, "Ginger must remain single-profession.")


func _test_turn_resources_and_free_character_skills() -> void:
	var state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 101)
	var active: Dictionary = state.call("player", 0) as Dictionary
	_expect(int(active.get("stamina", 0)) == int(active.get("max_stamina", 0)), "Active player restores stamina.")
	var resource_snapshot: Dictionary = state.call("deterministic_snapshot") as Dictionary
	var snapshot_player: Dictionary = (resource_snapshot.get("players", []) as Array)[0] as Dictionary
	_expect(snapshot_player.has("stamina") and snapshot_player.has("mana") and snapshot_player.has("actions"), "Deterministic snapshots must include player resources and actions.")
	_expect(resource_snapshot.has("pending_action") and resource_snapshot.has("pending_event"), "Deterministic snapshots must include pending action and event state.")
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
		_expect(int((state.call("player", 0) as Dictionary).get("actions", 0)) == 2, "Character skills must not be limited by action points.")
		var repeated: Dictionary = _find_command(state, MatchCommandScript.USE_SKILL, "q_thunder_call")
		_expect(not repeated.is_empty(), "Skills without an explicit uses_per_turn limit must be reusable.")
		if not repeated.is_empty():
			_expect(bool(state.call("submit_command", repeated)), "A reusable skill should resolve a second time.")


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
	_expect(int((state.call("player", 0) as Dictionary).get("actions", 0)) == 3, "Extra action feedback must still increase the action counter.")
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
	target["position"] = Vector2i(3, 3)
	state.players[1] = target
	var diagonal_preview: Dictionary = state.call("targeting_preview", 0, MatchCommandScript.PLAY_CARD, "slash") as Dictionary
	_expect(diagonal_preview.get("cells", []).has(Vector2i(3, 3)), "Range preview must use square Chebyshev distance.")
	target["position"] = Vector2i(3, 2)
	state.players[1] = target
	var command: Dictionary = _find_command(state, MatchCommandScript.PLAY_CARD, "slash")
	_expect(bool(state.call("submit_command", command)), "Previewed attack should resolve.")
	var history: Array = (state.call("player", 0) as Dictionary).get("public_card_history", []) as Array
	_expect(history.size() == 1 and String((history[0] as Dictionary).get("card_id", "")) == "slash", "Played cards must be publicly recorded.")
	var ginger_state: RefCounted = _state(["ginger", "q", "maddy", "signal"], 108)
	var ginger_target: Dictionary = ginger_state.call("player", 1) as Dictionary
	ginger_target["position"] = Vector2i(3, 2)
	ginger_target["health"] = 4
	ginger_target["max_health"] = 8
	ginger_state.players[1] = ginger_target
	var ginger_active: Dictionary = ginger_state.call("player", 0) as Dictionary
	ginger_active["hand"] = ["slash"]
	ginger_state.players[0] = ginger_active
	var ginger_attack: Dictionary = _find_command(ginger_state, MatchCommandScript.PLAY_CARD, "slash")
	_expect(not ginger_attack.is_empty(), "Ginger should have a legal attack for passive boundary test.")
	if not ginger_attack.is_empty():
		_expect(bool(ginger_state.call("submit_command", ginger_attack)), "Ginger boundary attack should resolve.")
		_expect((ginger_state.get("pending_action") as Dictionary).is_empty(), "Ginger attacks at half health must be unanswerable.")


func _test_purchased_cards_persist() -> void:
	var state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 107)
	var active: Dictionary = state.call("player", 0) as Dictionary
	active["coins"] = 10
	active["actions"] = 2
	state.players[0] = active
	state.call("set_market_for_testing", ["slash", "heavy_slash", "precise_thrust"] as Array[String])
	var buy: Dictionary = {}
	for command: Dictionary in state.call("legal_commands", 0) as Array[Dictionary]:
		if String(command.get("type", "")) == MatchCommandScript.BUY:
			buy = command
			break
	_expect(not buy.is_empty(), "A funded player should be able to buy from the market.")
	if not buy.is_empty():
		_expect(bool(state.call("submit_command", buy)), "Market purchase should resolve.")
		var purchased: Array = (state.call("player", 0) as Dictionary).get("purchased_hand", []) as Array
		_expect(purchased.size() == 1, "Purchased card must enter the protected purchase reserve.")
		var end_turn := MatchCommandScript.make(MatchCommandScript.END_TURN, 0)
		_expect(bool(state.call("submit_command", end_turn)), "Player should be able to end turn with a purchased card reserved.")
		_expect(((state.call("player", 0) as Dictionary).get("purchased_hand", []) as Array).size() == 1, "Purchased card must persist across turns until played.")


func _test_thunderstorm_skill_discard() -> void:
	var state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 109)
	var q: Dictionary = state.call("player", 0) as Dictionary
	var enemy: Dictionary = state.call("player", 1) as Dictionary
	q["hand"] = ["rally_new#003", "crossfire_new#003"]
	q["position"] = Vector2i(2, 2)
	enemy["position"] = Vector2i(3, 2)
	state.players[0] = q
	state.players[1] = enemy
	var thunderstorm := _find_command(state, MatchCommandScript.USE_SKILL, "q_thunderstorm")
	_expect(not thunderstorm.is_empty(), "Q must expose Thunderstorm as a legal staged skill.")
	if thunderstorm.is_empty():
		return
	_expect(bool(state.call("submit_command", thunderstorm)), "Thunderstorm should open a discard request.")
	var request: Dictionary = state.get("pending_skill_discard") as Dictionary
	_expect(int(request.get("required_rank_sum", 0)) == 23, "Thunderstorm discard request must require rank sum 23.")
	var invalid := MatchCommandScript.make(MatchCommandScript.SKILL_DISCARD, 0, {"request_id": request.get("request_id", ""), "card_ids": ["rally_new#003"]})
	_expect(not bool(state.call("submit_command", invalid)), "Thunderstorm must reject an incorrect rank sum.")
	var valid := MatchCommandScript.make(MatchCommandScript.SKILL_DISCARD, 0, {"request_id": request.get("request_id", ""), "card_ids": ["rally_new#003", "crossfire_new#003"]})
	_expect(bool(state.call("submit_command", valid)), "Thunderstorm should resolve after a valid rank-sum discard: %s" % String(state.get("last_error")))
	_expect((state.get("pending_skill_discard") as Dictionary).is_empty(), "Skill discard request must clear after payment.")
	var enemy_after: Dictionary = state.call("player", 1) as Dictionary
	_expect(int(enemy_after.get("health", 0)) < 7 and int((enemy_after.get("statuses", {}) as Dictionary).get("paralyze", 0)) > 0, "Thunderstorm must damage and paralyze enemies in its area.")
	var blocked_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 110)
	var blocked_q: Dictionary = blocked_state.call("player", 0) as Dictionary
	blocked_q["hand"] = ["rally_new#003", "crossfire_new#003"]
	blocked_state.players[0] = blocked_q
	var blocked_skill := _find_command(blocked_state, MatchCommandScript.USE_SKILL, "q_thunderstorm")
	blocked_state.call("submit_command", blocked_skill)
	blocked_q = blocked_state.call("player", 0) as Dictionary
	blocked_q["alive"] = false
	blocked_q["health"] = 0
	blocked_state.players[0] = blocked_q
	blocked_state.call("_settle_eliminations", [] as Array[Dictionary])
	_expect((blocked_state.get("pending_skill_discard") as Dictionary).is_empty(), "A dead skill owner must not leave a blocking skill discard request.")
	var unavailable_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 111)
	var unavailable_q: Dictionary = unavailable_state.call("player", 0) as Dictionary
	unavailable_q["hand"] = ["slash_new#001"]
	unavailable_state.players[0] = unavailable_q
	_expect(_find_command(unavailable_state, MatchCommandScript.USE_SKILL, "q_thunderstorm").is_empty(), "Thunderstorm must not be legal when its discard requirement cannot be paid.")


func _state(roster: Array[String], seed: int) -> RefCounted:
	var state: RefCounted = MatchStateScript.new(rules, catalog, roster, seed)
	if bool(state.get("profession_choice_pending")):
		state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SWITCH_PROFESSION, 0, {"profession": ""}))
	return state


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
