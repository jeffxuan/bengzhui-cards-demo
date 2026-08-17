extends SceneTree

const ContentCatalogScript = preload("res://scripts/core/content_catalog.gd")
const EventDeckScript = preload("res://scripts/core/event_deck.gd")
const AIControllerScript = preload("res://scripts/core/ai_controller.gd")
const MatchCommandScript = preload("res://scripts/core/match_command.gd")
const MatchStateScript = preload("res://scripts/core/match_state.gd")
const SaveServiceScript = preload("res://scripts/core/save_service.gd")

var failures: Array[String] = []
var catalog: RefCounted
var rules: Dictionary


func _init() -> void:
	catalog = ContentCatalogScript.new()
	rules = _load_rules()
	_test_content_contract()
	_test_event_deck_no_repeat()
	_test_event_deck_boundaries()
	_test_orthogonal_move_path()
	_test_single_response_window()
	_test_piercing_ignores_armor()
	_test_event_choice_has_fallback()
	_test_elimination_driven_collapse()
	_test_atomic_multi_elimination_and_wipe()
	_test_duel_pressure_boundaries()
	_test_duel_pressure_exclusions_and_action_wipe()
	_test_turn_start_defeat_finishes_cleanly()
	_test_deterministic_seed()
	_test_replay_recovery_and_compatibility()
	_test_replay_structure_validation()
	_test_empty_resource_boundaries()
	_test_round_limit_tiebreak_order()
	_test_active_skill_once_per_turn()
	_test_maddy_wealth_bonus_once_per_match()
	_test_status_contract_and_resolution()
	if failures.is_empty():
		print("RULE_TESTS_OK: 20 test groups passed.")
		quit(0)
		return
	for failure: String in failures:
		push_error("TEST FAILURE: %s" % failure)
	quit(1)

func _test_content_contract() -> void:
	_expect(bool(catalog.call("is_valid")), "Content catalog should pass validation: %s" % str(catalog.get("validation_errors")))
	_expect((catalog.get("cards") as Array).size() == 80, "Launch catalog must contain 80 cards.")
	_expect((catalog.get("characters") as Array).size() == 8, "Launch catalog must contain 8 characters.")
	_expect((catalog.get("events") as Array).size() == 16, "Public event deck must contain 16 events.")


func _test_event_deck_no_repeat() -> void:
	var cards: Array[Dictionary] = catalog.get("events") as Array[Dictionary]
	var deck: RefCounted = EventDeckScript.new(cards, 99)
	var seen: Dictionary = {}
	for _index: int in cards.size():
		var event_card: Dictionary = deck.call("draw") as Dictionary
		var event_id: String = String(event_card.get("id", ""))
		_expect(not seen.has(event_id), "Event %s repeated before recycle." % event_id)
		seen[event_id] = true
	_expect(int(deck.call("remaining_count")) == 0, "Event draw pile should be empty after 16 unique draws.")
	_expect(int(deck.call("discard_count")) == 16, "All drawn events should be in the discard pile.")


func _test_event_deck_boundaries() -> void:
	var cards: Array[Dictionary] = catalog.get("events") as Array[Dictionary]
	var deck: RefCounted = EventDeckScript.new(cards, 101)
	for _index: int in cards.size():
		deck.call("draw")
	var recycled: Dictionary = deck.call("draw") as Dictionary
	_expect(not recycled.is_empty(), "The event discard pile should recycle only after exhaustion.")
	_expect(int(deck.call("remaining_count")) == cards.size() - 1, "Recycling should leave fifteen events in the new draw pile.")
	_expect(int(deck.call("discard_count")) == 1, "Only the recycled event should enter the new discard pile.")
	var empty_deck: RefCounted = EventDeckScript.new([], 102)
	_expect((empty_deck.call("draw") as Dictionary).is_empty(), "An empty event deck should return an empty definition without crashing.")
	_expect(int(empty_deck.call("remaining_count")) == 0 and int(empty_deck.call("discard_count")) == 0, "An empty event deck should remain empty after a draw attempt.")


func _test_orthogonal_move_path() -> void:
	var state: RefCounted = _new_state(7)
	var commands: Array[Dictionary] = state.call("legal_commands", 0) as Array[Dictionary]
	var move_command: Dictionary = _find_move(commands, [2, 1])
	_expect(not move_command.is_empty(), "Adjacent orthogonal move should be legal.")
	_expect(state.call("submit_command", move_command), "Legal move command should be accepted.")
	var moved_player: Dictionary = state.call("player", 0) as Dictionary
	var moved_position: Vector2i = moved_player.get("position", Vector2i.ZERO) as Vector2i
	_expect(moved_position == Vector2i(2, 1), "Move should end at the commanded cell.")
	var illegal_diagonal: Dictionary = MatchCommandScript.make(MatchCommandScript.MOVE, 0, {"path": [[2, 2]]})
	_expect(not state.call("submit_command", illegal_diagonal), "Diagonal one-step movement must be rejected.")


func _test_single_response_window() -> void:
	var state: RefCounted = _new_state(11)
	_prepare_adjacent_combat(state)
	var source: Dictionary = state.call("player", 0) as Dictionary
	var target: Dictionary = state.call("player", 1) as Dictionary
	source["hand"] = ["slash"]
	target["hand"] = ["heavenly_sense"]
	source["stamina"] = 3
	source["actions"] = 2
	var target_health: int = int(target.get("health", 0))
	var play: Dictionary = MatchCommandScript.make(MatchCommandScript.PLAY_CARD, 0, {"card_id": "slash", "target_id": 1})
	_expect(state.call("submit_command", play), "Attack should open a response window.")
	_expect(not (state.get("pending_action") as Dictionary).is_empty(), "Eligible target should have one pending response window.")
	var response: Dictionary = MatchCommandScript.make(MatchCommandScript.RESPOND, 1, {"card_id": "heavenly_sense"})
	_expect(state.call("submit_command", response), "Valid response should resolve.")
	_expect((state.get("pending_action") as Dictionary).is_empty(), "Response must close the window without a second stack.")
	_expect(int((state.call("player", 1) as Dictionary).get("health", 0)) == target_health, "Negated attack must deal no damage.")


func _test_piercing_ignores_armor() -> void:
	var state: RefCounted = _new_state(13)
	_prepare_adjacent_combat(state)
	var source: Dictionary = state.call("player", 0) as Dictionary
	var target: Dictionary = state.call("player", 1) as Dictionary
	source["hand"] = ["precise_thrust"]
	source["stamina"] = 3
	source["actions"] = 2
	target["hand"] = []
	target["armor"] = 3
	var health_before: int = int(target.get("health", 0))
	var play: Dictionary = MatchCommandScript.make(MatchCommandScript.PLAY_CARD, 0, {"card_id": "precise_thrust", "target_id": 1})
	_expect(state.call("submit_command", play), "Piercing attack should be legal in range.")
	target = state.call("player", 1) as Dictionary
	_expect(int(target.get("health", 0)) == health_before - 2, "Piercing damage should reduce health directly.")
	_expect(int(target.get("armor", 0)) == 3, "Piercing damage should not consume armor.")

	var na1_state: RefCounted = MatchStateScript.new(rules, catalog, ["q", "na1", "ginger", "signal"], 14)
	var na1: Dictionary = na1_state.call("player", 1) as Dictionary
	na1["coins"] = 2
	health_before = int(na1.get("health", 0))
	na1_state.call("_deal_damage", 1, 2, "piercing", 0, true)
	na1 = na1_state.call("player", 1) as Dictionary
	_expect(int(na1.get("health", 0)) == health_before - 2, "Na1's gold guard must not block piercing damage.")
	_expect(int(na1.get("coins", 0)) == 2, "Na1's gold guard must spend coins only on normal damage.")


func _test_event_choice_has_fallback() -> void:
	var state: RefCounted = _new_state(17)
	var cult_event: Dictionary = {}
	for event_value: Variant in catalog.get("events") as Array:
		var event_definition: Dictionary = event_value as Dictionary
		if String(event_definition.get("id", "")) == "cult_of_madmen":
			cult_event = event_definition.duplicate(true)
			break
	state.set("pending_event", cult_event)
	var active: Dictionary = state.call("current_player") as Dictionary
	active["stamina"] = 0
	active["mana"] = 0
	var commands: Array[Dictionary] = state.call("legal_commands", 0) as Array[Dictionary]
	_expect(commands.size() == 1, "Unaffordable event should still expose exactly one fallback.")
	_expect(int((commands[0].get("payload", {}) as Dictionary).get("choice_index", -1)) == 1, "Fallback choice should remain legal.")


func _test_elimination_driven_collapse() -> void:
	var state: RefCounted = _new_state(19)
	for _turn: int in 4:
		var active_id: int = int((state.call("current_player") as Dictionary).get("id", -1))
		var end_turn: Dictionary = MatchCommandScript.make(MatchCommandScript.END_TURN, active_id)
		_expect(state.call("submit_command", end_turn), "Normal turn should end during elimination-collapse test.")
	_expect(int(state.get("completed_rounds")) == 1, "Four turns should complete one round.")
	_expect(int(state.get("collapse_count")) == 0, "Completing a round must not collapse the board.")
	_expect((state.call("active_bounds") as Rect2i).size == Vector2i(15, 15), "Four survivors should keep the full 15x15 board.")
	var snapshot: Array[Dictionary] = state.call("_capture_tiebreak_snapshot", state.call("_alive_player_ids")) as Array[Dictionary]
	state.call("_defeat_player", 1, 0)
	state.call("_settle_eliminations", snapshot)
	_expect(int(state.get("collapse_count")) == 1, "The first elimination should trigger one collapse.")
	_expect((state.call("active_bounds") as Rect2i).size == Vector2i(11, 11), "Three survivors should use an 11x11 board.")
	snapshot = state.call("_capture_tiebreak_snapshot", state.call("_alive_player_ids")) as Array[Dictionary]
	state.call("_defeat_player", 2, 0)
	state.call("_settle_eliminations", snapshot)
	_expect(int(state.get("collapse_count")) == 2, "The second elimination should trigger the final collapse.")
	_expect((state.call("active_bounds") as Rect2i).size == Vector2i(7, 7), "Two survivors should use a 7x7 board.")
	snapshot = state.call("_capture_tiebreak_snapshot", state.call("_alive_player_ids")) as Array[Dictionary]
	state.call("_defeat_player", 3, 0)
	state.call("_settle_eliminations", snapshot)
	_expect(bool(state.get("finished")) and int(state.get("winner_id")) == 0, "The last survivor should win immediately without an objective-token tiebreak.")
	_expect(String(state.get("win_reason_id")) == "last_survivor", "Last-survivor wins need a stable reason id.")


func _test_atomic_multi_elimination_and_wipe() -> void:
	var state: RefCounted = MatchStateScript.new(rules, catalog, ["k", "q", "ginger", "signal"], 21)
	var source: Dictionary = state.call("player", 0) as Dictionary
	source["position"] = Vector2i(7, 7)
	source["hand"] = ["sweep"]
	source["stamina"] = 3
	source["actions"] = 2
	for target_id: int in [1, 2]:
		var target: Dictionary = state.call("player", target_id) as Dictionary
		target["position"] = Vector2i(8, 7) if target_id == 1 else Vector2i(7, 8)
		target["health"] = 1
		state.get("players")[target_id] = target
	var sweep: Dictionary = MatchCommandScript.make(MatchCommandScript.PLAY_CARD, 0, {"card_id": "sweep", "target_id": -1})
	_expect(state.call("submit_command", sweep), "A multi-target attack should resolve as one command.")
	_expect(int(state.get("collapse_count")) == 2, "Two eliminations in one action should collapse from 15 to 7 only after the action resolves.")

	state = _new_state(22)
	state.set("collapse_count", 1)
	for defeated_id: int in [2, 3]:
		var defeated: Dictionary = state.call("player", defeated_id) as Dictionary
		defeated["alive"] = false
		defeated["health"] = 0
		state.get("players")[defeated_id] = defeated
	for survivor_id: int in [0, 1]:
		var survivor: Dictionary = state.call("player", survivor_id) as Dictionary
		survivor["position"] = Vector2i(2, 2) if survivor_id == 0 else Vector2i(12, 12)
		survivor["health"] = 1
		state.get("players")[survivor_id] = survivor
	var wipe_snapshot: Array[Dictionary] = state.call("_capture_tiebreak_snapshot", state.call("_alive_player_ids")) as Array[Dictionary]
	state.call("_settle_eliminations", wipe_snapshot)
	_expect(bool(state.get("finished")), "A simultaneous collapse wipe must still finish the match.")
	_expect(int(state.get("winner_id")) == 0 and String(state.get("win_reason_id")) == "simultaneous_wipe", "A collapse wipe should use the pre-collapse tiebreak snapshot.")


func _test_duel_pressure_boundaries() -> void:
	for case_value: Variant in [[3, 1], [4, 2], [6, 3]]:
		var test_case: Array = case_value as Array
		var state: RefCounted = _new_state(40 + int(test_case[0]))
		state.set("completed_rounds", int(test_case[0]))
		_prepare_adjacent_combat(state)
		var source: Dictionary = state.call("player", 0) as Dictionary
		var target: Dictionary = state.call("player", 1) as Dictionary
		source["hand"] = ["slash"]
		source["stamina"] = 3
		source["actions"] = 2
		target["hand"] = []
		var health_before: int = int(target.get("health", 0))
		var play: Dictionary = MatchCommandScript.make(MatchCommandScript.PLAY_CARD, 0, {"card_id": "slash", "target_id": 1})
		_expect(state.call("submit_command", play), "Single-target pressure boundary attack should be legal.")
		_expect(int((state.call("player", 1) as Dictionary).get("health", 0)) == health_before - int(test_case[1]), "Round %d should deal %d single-target damage." % [int(test_case[0]) + 1, int(test_case[1])])

	var area_state: RefCounted = MatchStateScript.new(rules, catalog, ["k", "q", "ginger", "signal"], 49)
	area_state.set("completed_rounds", 6)
	var area_source: Dictionary = area_state.call("player", 0) as Dictionary
	var area_target: Dictionary = area_state.call("player", 1) as Dictionary
	area_source["position"] = Vector2i(7, 7)
	area_target["position"] = Vector2i(8, 7)
	area_source["hand"] = ["sweep"]
	area_source["stamina"] = 3
	area_source["actions"] = 2
	area_target["hand"] = ["heavenly_sense"]
	var area_health: int = int(area_target.get("health", 0))
	var area_play: Dictionary = MatchCommandScript.make(MatchCommandScript.PLAY_CARD, 0, {"card_id": "sweep", "target_id": -1})
	_expect(area_state.call("submit_command", area_play), "Area attack should be legal during duel pressure.")
	_expect(int((area_state.call("player", 1) as Dictionary).get("health", 0)) == area_health - 1, "Area damage must not receive duel pressure bonuses.")
	_expect((area_state.get("pending_action") as Dictionary).is_empty(), "Area actions must resolve without opening a response window.")

	var pressure_event_state: RefCounted = _new_state(50)
	pressure_event_state.set("completed_rounds", 3)
	for _turn: int in 4:
		var actor_id: int = int((pressure_event_state.call("current_player") as Dictionary).get("id", -1))
		pressure_event_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.END_TURN, actor_id))
	var pressure_events: Array[Dictionary] = []
	for event: Dictionary in pressure_event_state.get("event_history") as Array[Dictionary]:
		if String(event.get("type", "")) == "duel_pressure_changed":
			pressure_events.append(event)
	_expect(pressure_events.size() == 1, "Entering round five should emit one duel_pressure_changed event.")
	if not pressure_events.is_empty():
		var payload: Dictionary = pressure_events[0].get("payload", {}) as Dictionary
		_expect(int(payload.get("round", 0)) == 5 and int(payload.get("single_target_damage_bonus", 0)) == 1, "Duel pressure event payload must expose round five and +1 damage.")


func _test_duel_pressure_exclusions_and_action_wipe() -> void:
	var status_state: RefCounted = _new_state(52)
	status_state.set("completed_rounds", 6)
	var status_target: Dictionary = status_state.call("player", 1) as Dictionary
	var health_before: int = int(status_target.get("health", 0))
	status_state.call("_apply_status", 1, "bleed", 1, 0)
	status_state.call("_tick_start_statuses", 1)
	_expect(int((status_state.call("player", 1) as Dictionary).get("health", 0)) == health_before - 1, "Status damage must not receive duel pressure bonuses.")

	var trap_state: RefCounted = _new_state(53)
	trap_state.set("completed_rounds", 6)
	var trap_actor: Dictionary = trap_state.call("player", 0) as Dictionary
	trap_actor["position"] = Vector2i(5, 6)
	health_before = int(trap_actor.get("health", 0))
	var trap_move: Dictionary = MatchCommandScript.make(MatchCommandScript.MOVE, 0, {"path": [[6, 6]]})
	_expect(trap_state.call("submit_command", trap_move), "Moving through a trap should remain legal during duel pressure.")
	_expect(int((trap_state.call("player", 0) as Dictionary).get("health", 0)) == health_before - 1, "Trap damage must not receive duel pressure bonuses.")

	var collapse_state: RefCounted = _new_state(54)
	collapse_state.set("completed_rounds", 6)
	var collapse_target: Dictionary = collapse_state.call("player", 0) as Dictionary
	collapse_target["position"] = Vector2i(0, 0)
	health_before = int(collapse_target.get("health", 0))
	collapse_state.call("_collapse_board")
	_expect(int((collapse_state.call("player", 0) as Dictionary).get("health", 0)) == health_before - 1, "Collapse damage must not receive duel pressure bonuses.")
	var collapse_events: Array[Dictionary] = []
	for event: Dictionary in collapse_state.get("event_history") as Array[Dictionary]:
		if String(event.get("type", "")) == "board_collapsed":
			collapse_events.append(event)
	_expect(collapse_events.size() == 1, "A collapse should emit one board_collapsed event.")
	if not collapse_events.is_empty():
		var collapse_payload: Dictionary = collapse_events[0].get("payload", {}) as Dictionary
		_expect(int(collapse_payload.get("from_size", 0)) == 15 and int(collapse_payload.get("size", 0)) == 11 and String(collapse_payload.get("cause", "")) == "elimination", "Collapse events must expose their sizes and elimination cause.")

	var retaliation_state: RefCounted = _new_state(55)
	retaliation_state.set("completed_rounds", 6)
	_prepare_adjacent_combat(retaliation_state)
	var retaliation_source: Dictionary = retaliation_state.call("player", 0) as Dictionary
	var retaliation_target: Dictionary = retaliation_state.call("player", 1) as Dictionary
	retaliation_source["hand"] = ["slash"]
	retaliation_source["stamina"] = 3
	retaliation_source["actions"] = 2
	retaliation_target["hand"] = []
	(retaliation_target.get("equipment", {}) as Dictionary)["armor"] = "thorn_armor"
	health_before = int(retaliation_source.get("health", 0))
	var retaliation_play: Dictionary = MatchCommandScript.make(MatchCommandScript.PLAY_CARD, 0, {"card_id": "slash", "target_id": 1})
	_expect(retaliation_state.call("submit_command", retaliation_play), "An attack against thorn armor should resolve during duel pressure.")
	_expect(int((retaliation_state.call("player", 0) as Dictionary).get("health", 0)) == health_before - 1, "Retaliation damage must not receive duel pressure bonuses.")

	var wipe_state: RefCounted = _new_state(56)
	wipe_state.set("completed_rounds", 6)
	_prepare_adjacent_combat(wipe_state)
	for defeated_id: int in [2, 3]:
		var defeated: Dictionary = wipe_state.call("player", defeated_id) as Dictionary
		defeated["alive"] = false
		defeated["health"] = 0
	var wipe_source: Dictionary = wipe_state.call("player", 0) as Dictionary
	var wipe_target: Dictionary = wipe_state.call("player", 1) as Dictionary
	wipe_source["health"] = 1
	wipe_source["hand"] = ["slash"]
	wipe_source["stamina"] = 3
	wipe_source["actions"] = 2
	wipe_target["health"] = 3
	wipe_target["hand"] = []
	(wipe_target.get("equipment", {}) as Dictionary)["armor"] = "thorn_armor"
	var wipe_play: Dictionary = MatchCommandScript.make(MatchCommandScript.PLAY_CARD, 0, {"card_id": "slash", "target_id": 1})
	_expect(wipe_state.call("submit_command", wipe_play), "A mutually lethal action should resolve atomically.")
	_expect(bool(wipe_state.get("finished")) and String(wipe_state.get("win_reason_id")) == "simultaneous_wipe", "A mutually lethal action must finish with a stable simultaneous-wipe reason.")
	_expect(int(wipe_state.get("winner_id")) == 0, "Action-wipe tiebreaks must include damage dealt by the resolving action.")


func _test_turn_start_defeat_finishes_cleanly() -> void:
	var state: RefCounted = _new_state(51)
	for defeated_id: int in [2, 3]:
		var defeated: Dictionary = state.call("player", defeated_id) as Dictionary
		defeated["alive"] = false
		defeated["health"] = 0
		state.get("players")[defeated_id] = defeated
	var active: Dictionary = state.call("player", 0) as Dictionary
	active["health"] = 1
	active["statuses"] = {"bleed": 1}
	active["status_sources"] = {"bleed": 1}
	state.get("players")[0] = active
	state.call("_begin_turn")
	_expect(bool(state.get("finished")), "A lethal turn-start status must finish instead of recursively searching for a living player.")
	_expect(int(state.get("winner_id")) == 1 and String(state.get("win_reason_id")) == "last_survivor", "The surviving player should win after lethal turn-start damage.")


func _test_deterministic_seed() -> void:
	var state_one: RefCounted = _new_state(23)
	var state_two: RefCounted = _new_state(23)
	_expect(state_one.call("deterministic_snapshot") == state_two.call("deterministic_snapshot"), "Equal seeds should create equal initial states.")
	var command: Dictionary = MatchCommandScript.make(MatchCommandScript.END_TURN, 0)
	state_one.call("submit_command", command)
	state_two.call("submit_command", command)
	_expect(state_one.call("deterministic_snapshot") == state_two.call("deterministic_snapshot"), "Equal command logs should preserve deterministic state.")
	_expect(state_one.get("event_history") == state_two.get("event_history"), "Equal seed and commands must emit identical MatchEvents.")


func _test_replay_recovery_and_compatibility() -> void:
	var state: RefCounted = _new_state(2026)
	var ai: RefCounted = AIControllerScript.new()
	for _step: int in 20:
		if bool(state.get("finished")):
			break
		var pending_action: Dictionary = state.get("pending_action") as Dictionary
		var actor_id: int = int((state.call("current_player") as Dictionary).get("id", -1)) if pending_action.is_empty() else int(pending_action.get("responder_id", -1))
		var command: Dictionary = ai.call("choose_command", state, actor_id) as Dictionary
		_expect(not command.is_empty(), "Replay fixture AI should always find a legal command.")
		if command.is_empty():
			break
		_expect(bool(state.call("submit_command", command)), "Replay fixture commands should resolve successfully.")
	var replay: Dictionary = state.call("replay_document") as Dictionary
	var original_replay: Dictionary = replay.duplicate(true)
	var rebuilt: Dictionary = SaveServiceScript.rebuild_match(MatchStateScript, rules, catalog, replay)
	_expect(bool(rebuilt.get("ok", false)), "A compatible replay should rebuild successfully: %s" % String(rebuilt.get("error", "")))
	if bool(rebuilt.get("ok", false)):
		var rebuilt_state: RefCounted = rebuilt.get("state") as RefCounted
		_expect(rebuilt_state.call("deterministic_snapshot") == state.call("deterministic_snapshot"), "Replay recovery must reproduce the deterministic snapshot.")
		_expect(rebuilt_state.get("event_history") == state.get("event_history"), "Replay recovery must reproduce the complete MatchEvent history.")
	_expect(replay == original_replay, "Rebuilding a match must not mutate the replay document.")

	var old_rules_replay: Dictionary = replay.duplicate(true)
	old_rules_replay["rules_version"] = 2
	var old_rules_before: Dictionary = old_rules_replay.duplicate(true)
	var rejected: Dictionary = SaveServiceScript.rebuild_match(MatchStateScript, rules, catalog, old_rules_replay)
	_expect(not bool(rejected.get("ok", false)) and String(rejected.get("error", "")).contains("规则版本"), "Rules-v2 mid-match saves must be rejected with a readable error.")
	_expect(old_rules_replay == old_rules_before, "Rejecting a rules-incompatible replay must preserve the input document.")

	var old_content_replay: Dictionary = replay.duplicate(true)
	old_content_replay["content_version"] = int(catalog.get("version")) + 1
	var old_content_before: Dictionary = old_content_replay.duplicate(true)
	rejected = SaveServiceScript.rebuild_match(MatchStateScript, rules, catalog, old_content_replay)
	_expect(not bool(rejected.get("ok", false)) and String(rejected.get("error", "")).contains("内容版本"), "Content-incompatible saves must be rejected with a readable error.")
	_expect(old_content_replay == old_content_before, "Rejecting a content-incompatible replay must preserve the input document.")

	var invalid_replay: Dictionary = replay.duplicate(true)
	var invalid_commands: Array = invalid_replay.get("commands", []) as Array
	invalid_commands.append(MatchCommandScript.make(MatchCommandScript.MOVE, 99, {"path": [[1, 1]]}))
	var invalid_before: Dictionary = invalid_replay.duplicate(true)
	rejected = SaveServiceScript.rebuild_match(MatchStateScript, rules, catalog, invalid_replay)
	_expect(not bool(rejected.get("ok", false)) and String(rejected.get("error", "")).contains("命令无法重放"), "A replay containing an invalid command must be rejected.")
	_expect(invalid_replay == invalid_before, "Rejecting an invalid command sequence must preserve the input document.")


func _test_replay_structure_validation() -> void:
	var state: RefCounted = _new_state(2027)
	var replay: Dictionary = state.call("replay_document") as Dictionary
	var malformed_commands: Dictionary = replay.duplicate(true)
	malformed_commands["commands"] = {"not": "an array"}
	var rejected: Dictionary = SaveServiceScript.rebuild_match(MatchStateScript, rules, catalog, malformed_commands)
	_expect(not bool(rejected.get("ok", false)) and String(rejected.get("error", "")).contains("结构不完整"), "A replay with a non-array command sequence must be rejected without a runtime error.")

	var short_roster: Dictionary = replay.duplicate(true)
	short_roster["roster"] = ["q"]
	rejected = SaveServiceScript.rebuild_match(MatchStateScript, rules, catalog, short_roster)
	_expect(not bool(rejected.get("ok", false)) and String(rejected.get("error", "")).contains("结构不完整"), "A replay without four roster entries must be rejected.")

	var unknown_character: Dictionary = replay.duplicate(true)
	unknown_character["roster"] = ["q", "ginger", "maddy", "missing_character"]
	rejected = SaveServiceScript.rebuild_match(MatchStateScript, rules, catalog, unknown_character)
	_expect(not bool(rejected.get("ok", false)) and String(rejected.get("error", "")).contains("无效角色"), "A replay with an unknown character id must be rejected instead of silently substituting Q.")

	var invalid_seed: Dictionary = replay.duplicate(true)
	invalid_seed["seed"] = "not-a-number"
	rejected = SaveServiceScript.rebuild_match(MatchStateScript, rules, catalog, invalid_seed)
	_expect(not bool(rejected.get("ok", false)) and String(rejected.get("error", "")).contains("结构不完整"), "A replay with a non-numeric seed must be rejected.")


func _test_empty_resource_boundaries() -> void:
	var state: RefCounted = _new_state(2030)
	var active: Dictionary = state.call("player", 0) as Dictionary
	active["hand"] = []
	active["deck"] = []
	active["discard"] = ["slash", "heavy_slash"]
	state.get("players")[0] = active
	state.call("_draw_cards", 0, 2)
	active = state.call("player", 0) as Dictionary
	_expect((active.get("hand", []) as Array).size() == 2, "Drawing should reshuffle the player's discard pile after the deck is exhausted.")
	_expect((active.get("deck", []) as Array).is_empty() and (active.get("discard", []) as Array).is_empty(), "A complete two-card reshuffle should consume both source piles.")

	active["hand"] = []
	active["deck"] = []
	active["discard"] = []
	state.get("players")[0] = active
	state.call("_draw_cards", 0, 2)
	active = state.call("player", 0) as Dictionary
	_expect((active.get("hand", []) as Array).is_empty(), "Drawing from empty deck and discard piles should be a no-op.")

	active["coins"] = 0
	active["actions"] = 2
	active["hand"] = []
	state.get("players")[0] = active
	var commands: Array[Dictionary] = state.call("legal_commands", 0) as Array[Dictionary]
	_expect(not _has_command_type(commands, MatchCommandScript.BUY), "A player with zero coins should have no market purchase command.")
	_expect(not _has_command_type(commands, MatchCommandScript.PLAY_CARD), "An empty hand should expose no play-card command.")

	active["hand"] = ["slash"]
	active["stamina"] = 3
	active["position"] = Vector2i(0, 0)
	state.get("players")[0] = active
	for target_id: int in [1, 2, 3]:
		var target: Dictionary = state.call("player", target_id) as Dictionary
		target["position"] = [Vector2i(14, 14), Vector2i(14, 13), Vector2i(13, 14)][target_id - 1]
		state.get("players")[target_id] = target
	commands = state.call("legal_commands", 0) as Array[Dictionary]
	_expect(not _has_card_command(commands, "slash"), "A targeted attack should not be offered when no enemy is in range.")


func _test_round_limit_tiebreak_order() -> void:
	var cases: Array[Dictionary] = [
		{"name": "eliminations", "winner": 1, "p0": {"eliminations": 0, "health": 8, "damage": 9, "armor": 3, "hand": 3}, "p1": {"eliminations": 1, "health": 1, "damage": 0, "armor": 0, "hand": 0}},
		{"name": "health ratio", "winner": 1, "p0": {"eliminations": 0, "health": 4, "damage": 9, "armor": 3, "hand": 3}, "p1": {"eliminations": 0, "health": 8, "damage": 0, "armor": 0, "hand": 0}},
		{"name": "damage dealt", "winner": 1, "p0": {"eliminations": 0, "health": 8, "damage": 1, "armor": 3, "hand": 3}, "p1": {"eliminations": 0, "health": 8, "damage": 2, "armor": 0, "hand": 0}},
		{"name": "armor", "winner": 1, "p0": {"eliminations": 0, "health": 8, "damage": 0, "armor": 0, "hand": 3}, "p1": {"eliminations": 0, "health": 8, "damage": 0, "armor": 1, "hand": 0}},
		{"name": "hand size", "winner": 1, "p0": {"eliminations": 0, "health": 8, "damage": 0, "armor": 0, "hand": 0}, "p1": {"eliminations": 0, "health": 8, "damage": 0, "armor": 0, "hand": 1}},
		{"name": "seat", "winner": 0, "p0": {"eliminations": 0, "health": 8, "damage": 0, "armor": 0, "hand": 0}, "p1": {"eliminations": 0, "health": 8, "damage": 0, "armor": 0, "hand": 0}}
	]
	for case_definition: Dictionary in cases:
		var state: RefCounted = _new_state(60 + cases.find(case_definition))
		for defeated_id: int in [2, 3]:
			var defeated: Dictionary = state.call("player", defeated_id) as Dictionary
			defeated["alive"] = false
			defeated["health"] = 0
		for player_id: int in [0, 1]:
			var values: Dictionary = case_definition.get("p%d" % player_id, {}) as Dictionary
			var player_state: Dictionary = state.call("player", player_id) as Dictionary
			player_state["max_health"] = 8
			player_state["health"] = int(values.get("health", 8))
			player_state["armor"] = int(values.get("armor", 0))
			player_state["hand"] = []
			for _card: int in int(values.get("hand", 0)):
				(player_state.get("hand", []) as Array).append("slash")
			player_state["stats"] = {"eliminations": int(values.get("eliminations", 0)), "damage_dealt": int(values.get("damage", 0))}
		state.call("_finish_by_tiebreak")
		_expect(int(state.get("winner_id")) == int(case_definition.get("winner", -1)), "Round-limit tiebreak should prioritize %s in the documented order." % String(case_definition.get("name", "unknown")))
		_expect(String(state.get("win_reason_id")) == "round_limit", "Round-limit tiebreaks need a stable reason id.")


func _test_active_skill_once_per_turn() -> void:
	var state: RefCounted = _new_state(29)
	var active: Dictionary = state.call("player", 0) as Dictionary
	active["hand"] = ["slash", "slash"]
	active["mana"] = 3
	active["actions"] = 2
	var first_use: Dictionary = MatchCommandScript.make(MatchCommandScript.USE_SKILL, 0, {"skill_id": "q_stargaze", "target_id": 0})
	_expect(state.call("submit_command", first_use), "A ready active skill should be usable once.")
	var second_use_is_legal: bool = false
	for command: Dictionary in state.call("legal_commands", 0) as Array[Dictionary]:
		if String(command.get("type", "")) == MatchCommandScript.USE_SKILL and String((command.get("payload", {}) as Dictionary).get("skill_id", "")) == "q_stargaze":
			second_use_is_legal = true
	_expect(not second_use_is_legal, "The same active skill must not be usable twice in one turn.")


func _test_maddy_wealth_bonus_once_per_match() -> void:
	var state: RefCounted = MatchStateScript.new(rules, catalog, ["maddy", "q", "ginger", "signal"], 31)
	var maddy: Dictionary = state.call("player", 0) as Dictionary
	maddy["position"] = Vector2i(4, 2)
	state.call("_resolve_landing", 0)
	_expect(int((state.call("player", 0) as Dictionary).get("coins", 0)) == 3, "Maddy's first wealth tile should grant one bonus coin.")
	for _turn: int in 4:
		var active_id: int = int((state.call("current_player") as Dictionary).get("id", -1))
		state.call("submit_command", MatchCommandScript.make(MatchCommandScript.END_TURN, active_id))
	maddy = state.call("player", 0) as Dictionary
	maddy["position"] = Vector2i(10, 2)
	state.call("_resolve_landing", 0)
	_expect(int((state.call("player", 0) as Dictionary).get("coins", 0)) == 5, "Maddy's wealth bonus must remain spent after a new turn begins.")


func _test_status_contract_and_resolution() -> void:
	var status_ids: Array[String] = []
	for status_value: Variant in catalog.get("statuses") as Array:
		var status_definition: Dictionary = status_value as Dictionary
		status_ids.append(String(status_definition.get("id", "")))
		for key: String in ["max_stacks", "timing", "duration", "clear"]:
			_expect(status_definition.has(key), "Status %s must define %s." % [String(status_definition.get("id", "")), key])
	_expect(status_ids == ["paralyze", "bleed", "poison", "confusion", "hidden", "scorch"], "Only the six launch statuses may be public content.")
	var state: RefCounted = _new_state(37)
	state.call("_apply_status", 0, "paralyze", 1)
	_expect(not ((state.call("player", 0) as Dictionary).get("statuses", {}) as Dictionary).has("paralyze"), "Q must remain immune to paralyze.")
	var target: Dictionary = state.call("player", 1) as Dictionary
	var health_before: int = int(target.get("health", 0))
	state.call("_apply_status", 1, "bleed", 5)
	state.call("_tick_start_statuses", 1)
	target = state.call("player", 1) as Dictionary
	_expect(int(target.get("health", 0)) == health_before - 1, "Bleed must deal one true damage at turn start.")
	_expect(int((target.get("statuses", {}) as Dictionary).get("bleed", 0)) == 2, "Bleed must cap at three and lose one stack after resolving.")
	health_before = int(target.get("health", 0))
	state.call("_apply_status", 1, "poison", 4)
	target = state.call("player", 1) as Dictionary
	_expect(int(target.get("health", 0)) == health_before - 3, "Four poison stacks must burst for three true damage immediately.")
	_expect(not (target.get("statuses", {}) as Dictionary).has("poison"), "Poison must clear after its four-stack burst.")
	state.call("_apply_status", 1, "hidden", 3)
	state.call("_apply_status", 1, "scorch", 3)
	target = state.call("player", 1) as Dictionary
	_expect(int((target.get("statuses", {}) as Dictionary).get("hidden", 0)) == 1, "Hidden must cap at one stack.")
	_expect(int((target.get("statuses", {}) as Dictionary).get("scorch", 0)) == 2, "Scorch must cap at two stacks.")


func _new_state(match_seed: int) -> RefCounted:
	return MatchStateScript.new(rules, catalog, ["q", "ginger", "maddy", "signal"], match_seed)


func _prepare_adjacent_combat(state: RefCounted) -> void:
	var source: Dictionary = state.call("player", 0) as Dictionary
	var target: Dictionary = state.call("player", 1) as Dictionary
	source["position"] = Vector2i(3, 3)
	target["position"] = Vector2i(4, 3)


func _find_move(commands: Array[Dictionary], destination: Array[int]) -> Dictionary:
	for command: Dictionary in commands:
		if String(command.get("type", "")) != MatchCommandScript.MOVE:
			continue
		var path: Array = (command.get("payload", {}) as Dictionary).get("path", []) as Array
		if not path.is_empty() and path.back() == destination:
			return command
	return {}


func _has_command_type(commands: Array[Dictionary], command_type: String) -> bool:
	for command: Dictionary in commands:
		if String(command.get("type", "")) == command_type:
			return true
	return false


func _has_card_command(commands: Array[Dictionary], card_id: String) -> bool:
	for command: Dictionary in commands:
		if String(command.get("type", "")) == MatchCommandScript.PLAY_CARD and String((command.get("payload", {}) as Dictionary).get("card_id", "")) == card_id:
			return true
	return false


func _load_rules() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://rules/match_rules.json"))
	return parsed as Dictionary if parsed is Dictionary else {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
