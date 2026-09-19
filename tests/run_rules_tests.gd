extends SceneTree

const ContentCatalogScript = preload("res://scripts/core/content_catalog.gd")
const AIControllerScript = preload("res://scripts/core/ai_controller.gd")
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
	_test_revised_skill_usage_limits()
	_test_k_brain_and_ginger_waist()
	_test_zc_frenzy_flow()
	_test_ai_revised_skill_choices()
	_test_named_revised_card_effects()
	_test_first_wave_formal_cards()
	_test_rummage_draw_then_discard()
	_test_ritual_dagger_kill_reward()
	_test_confirmed_card_batch_one()
	_test_ai_duel_damage_priority()
	_test_response_window_resources()
	_test_discard_phase_and_replay_continuation()
	_test_no_action_points_and_round_pressure()
	_test_targeting_and_public_history()
	_test_purchased_cards_persist()
	_test_na1_purchased_card_bonuses()
	_test_thunderstorm_skill_discard()
	_test_dead_q_skips_end_turn_thunder_guard()
	_test_endgame_barrier_and_durability()
	_test_k_strategy_medium_recovery()
	_test_shya_flash_rules()
	_test_maddy_explore_rules()
	_test_maddy_reclaim_rules()
	_test_na1_gold_passive()
	_test_signal_limit_and_q_end_turn_guard()
	_test_signal_collapsed_area_passive()
	_test_revised_decks_and_equipment_installation()
	_test_profession_attack_ranges()
	if failures.is_empty():
		print("RULE_TESTS_OK: v10 revised skills, no action points, durability, suits/ranks, responses, and continuations passed.")
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
	var staged_resolved: Dictionary = catalog.call("resolve_card", "slash_new#001") as Dictionary
	_expect(String(staged_resolved.get("instance_id", "")) == "slash_new#001", "Catalog resolve_card must support staged instance IDs.")
	_expect(String(staged_resolved.get("description", "")) == String(staged_resolved.get("source_text", "")), "Staged card instances must expose source text as their UI description.")
	var resolved_instance: Dictionary = catalog.call("card", "slash#001") as Dictionary
	_expect(String(resolved_instance.get("id", "")) == "slash", "Card lookup must resolve instance IDs.")
	_expect(String(catalog.call("logical_card_id", "slash#001")) == "slash", "Logical card ID lookup must resolve instances.")
	_expect(String(slash_instance.get("suit", "")) == "none" and int(slash_instance.get("rank", -1)) == 0, "Legacy cards must normalize neutral suit metadata.")
	var provisional_report: Array = catalog.call("provisional_report") as Array
	var provisional_ids: Array[String] = []
	for entry_value: Variant in provisional_report:
		var entry: Dictionary = entry_value as Dictionary
		if String(entry.get("kind", "")) == "staged_card":
			provisional_ids.append(String(entry.get("id", "")))
	_expect(provisional_ids.is_empty(), "All staged cards must be fully mapped before the complete-card baseline is accepted.")
	_expect((catalog.get("staged_characters") as Array).size() == 8, "新版首发角色暂存清单应包含8名角色。")
	var q_staged: Dictionary = catalog.call("staged_character", "q") as Dictionary
	_expect((q_staged.get("professions", []) as Array).size() == 2, "Q must expose both revised professions.")
	var q_skill: Dictionary = catalog.call("staged_skill", "q", "q_thunderstorm") as Dictionary
	_expect(not q_skill.is_empty() and bool(q_skill.get("source_text", "") != ""), "Staged character skills must be addressable by stable ID.")
	var q_runtime: Dictionary = catalog.call("executable_staged_skill", "q", "q_thunderstorm") as Dictionary
	_expect(String(q_runtime.get("target", "")) == "all_enemies_in_range" and (q_runtime.get("effects", []) as Array).size() == 2, "Q Thunderstorm must expose a provisional executable effect chain.")
	_expect(int((q_runtime.get("discard_requirement", {}) as Dictionary).get("rank_sum", 0)) == 23, "Thunderstorm must expose its rank-sum discard requirement.")
	_expect(not (q_runtime.get("provisional_notes", []) as Array).has("弃牌点数和为23的前置条件尚未接入"), "Thunderstorm provisional notes must not claim its implemented discard requirement is missing.")
	_expect(int(catalog.call("staged_skill", "k", "k_brain").get("uses_per_turn", 0)) == 1, "Explicit once-per-turn skill limits must be structured.")
	_expect(int(catalog.call("staged_skill", "k", "k_strategy").get("uses_per_profession_per_match", 0)) == 1, "K Strategy must encode its once-per-profession-per-match limit.")
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
	var readiness: Dictionary = catalog.call("staged_execution_readiness") as Dictionary
	_expect(int(readiness.get("total", 0)) == 165 and (readiness.get("ready_ids", []) as Array).size() == 165 and (readiness.get("provisional_ids", []) as Array).is_empty(), "All staged cards must be ready at the complete-card baseline.")
	var staged_instance: Dictionary = catalog.call("staged_card_instance", "slash_new", 0) as Dictionary
	_expect(String(staged_instance.get("instance_id", "")) == "slash_new#001" and String(staged_instance.get("suit", "")) == "spades", "Staged card instances must resolve suit and ID.")
	_expect((catalog.call("staged_card_ids_for_profession", "berserker") as Array).size() == 21, "Berserker staged pool must expose 21 definitions.")
	_expect((catalog.call("staged_instance_ids_for_profession", "shooter") as Array).size() == 75, "Shooter staged pool must expose 75 instances.")
	var shooter_pool: Array = catalog.call("staged_draw_pool_for_profession", "shooter") as Array
	_expect(shooter_pool.has("slash_new#001") and shooter_pool.has("sniper_new#001"), "Profession draw pool must include common and current-profession cards.")
	_expect(not shooter_pool.has("berserker_blow_new#001"), "Profession draw pool must exclude other professions.")
	_expect(int(rules.get("version", 0)) == 10, "Rules must be v10.")
	_expect(not rules.has("round_limit"), "Round limit must be removed.")
	_expect(not rules.has("promoted_staged_cards"), "v10 must not retain a partial revised-card promotion list.")
	_expect(not rules.has("action_points"), "v10 must not retain the retired action-point setting.")
	var armor_break_definition: Dictionary = catalog.call("resolve_card", "armor_break_new#001") as Dictionary
	_expect(String(armor_break_definition.get("target", "")) == "enemy" and int(armor_break_definition.get("range", 0)) == 1, "Armor Break must use an adjacent enemy target.")
	var weapon_definition: Dictionary = catalog.call("resolve_card", "crowbar_new#001") as Dictionary
	var armor_definition: Dictionary = catalog.call("resolve_card", "thorn_armor_new#001") as Dictionary
	var accessory_definition: Dictionary = catalog.call("resolve_card", "strong_shell_new#001") as Dictionary
	_expect(int((weapon_definition.get("cost", {}) as Dictionary).get("stamina", -1)) == 0 and int((weapon_definition.get("cost", {}) as Dictionary).get("mana", -1)) == 0, "Revised weapons must not spend stamina or mana to equip.")
	_expect(int((armor_definition.get("cost", {}) as Dictionary).get("stamina", -1)) == 0 and int((armor_definition.get("cost", {}) as Dictionary).get("mana", -1)) == 0, "Revised armor must not spend stamina or mana to equip.")
	_expect(int((accessory_definition.get("cost", {}) as Dictionary).get("stamina", -1)) == 0 and int((accessory_definition.get("cost", {}) as Dictionary).get("mana", -1)) == 0, "Revised accessories must not spend stamina or mana to equip.")
	var k_strategy: Dictionary = catalog.call("staged_skill", "k", "k_strategy") as Dictionary
	_expect(String(k_strategy.get("skill_type", "")) == "ability" and k_strategy.has("exhaust"), "K Strategy must expose ability and exhaust metadata.")
	var ginger_power: Dictionary = catalog.call("staged_skill", "ginger", "ginger_power") as Dictionary
	_expect(String(ginger_power.get("skill_type", "")) == "breakthrough_skill" and ginger_power.has("breakthrough_goal"), "Ginger Power must expose breakthrough metadata and its documented goal.")
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
	var initial_player: Dictionary = keep_state.call("player", 0) as Dictionary
	_expect(String((initial_player.get("common_deck", []) as Array).back()).contains("#"), "A promoted suit/rank card must be at the common draw end.")
	_expect(String((initial_player.get("profession_deck", []) as Array).back()).contains("#"), "A promoted suit/rank card must be at the profession draw end.")
	keep_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SWITCH_PROFESSION, 0, {"profession": ""}))
	var opening_player: Dictionary = keep_state.call("player", 0) as Dictionary
	_expect(opening_player.get("hand", []).size() == 7, "Keeping profession on round one draws three cards.")
	_expect(String((keep_state.get("pending_skill_choice") as Dictionary).get("kind", "")) == "q_thunder_guard_offer", "Q must receive a Thunder Guard choice after the normal draw completes.")
	var hand_after_normal_draw: Array = (opening_player.get("hand", []) as Array).duplicate()
	var offer: Dictionary = keep_state.get("pending_skill_choice") as Dictionary
	keep_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(offer.get("request_id", "")), "value": "skip"}))
	_expect((keep_state.call("player", 0) as Dictionary).get("hand", []) == hand_after_normal_draw, "Skipping Thunder Guard after the normal draw must not change Q's hand.")
	_expect(_find_command(keep_state, MatchCommandScript.USE_SKILL, "q_thunder_guard").is_empty(), "Thunder Guard must not remain available as a pre-draw skill command.")
	var visible_identity_count := 0
	for card_value: Variant in opening_player.get("hand", []) as Array:
		var definition: Dictionary = catalog.call("resolve_card", String(card_value)) as Dictionary
		if String(definition.get("suit", "none")) != "none" and int(definition.get("rank", 0)) in range(1, 14):
			visible_identity_count += 1
	_expect(visible_identity_count >= 3, "The opening draw must immediately expose suit/rank card instances.")
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
	_expect(snapshot_player.has("stamina") and snapshot_player.has("mana") and not snapshot_player.has("actions"), "Deterministic snapshots must include resources without the retired action-point field.")
	_expect(resource_snapshot.has("pending_action") and resource_snapshot.has("pending_event"), "Deterministic snapshots must include pending action and event state.")
	_expect(int((state.call("player", 1) as Dictionary).get("stamina", -1)) == 0 and int((state.call("player", 1) as Dictionary).get("mana", -1)) == 0, "Off-turn resources must be zero.")
	var target: Dictionary = state.call("player", 1) as Dictionary
	target["position"] = Vector2i(3, 2)
	state.players[1] = target
	active["hand"] = ["rally_new#003", "crossfire_new#003"]
	active["stamina"] = 0
	active["mana"] = 0
	state.players[0] = active
	var command: Dictionary = _find_command(state, MatchCommandScript.USE_SKILL, "q_thunderstorm")
	_expect(not command.is_empty(), "A character skill must remain usable at zero resources.")
	if not command.is_empty():
		_expect(bool(state.call("submit_command", command)), "Free character skill should resolve.")
		_expect(not (state.call("player", 0) as Dictionary).has("actions"), "Character skills must not create the retired action-point field.")
		var repeated: Dictionary = _find_command(state, MatchCommandScript.USE_SKILL, "q_thunderstorm")
		_expect(repeated.is_empty(), "Q Thunderstorm must be unavailable after its once-per-turn use.")


func _test_revised_skill_usage_limits() -> void:
	var k_state: RefCounted = _state(["k", "ginger", "maddy", "signal"], 113)
	var brain_policy: Dictionary = k_state.call("skill_usage_policy", 0, "k_megamind") as Dictionary
	_expect(int(brain_policy.get("uses_per_turn", 0)) == 1 and int(brain_policy.get("remaining_this_turn", -1)) == 1, "K Brain must expose one remaining use at turn start.")
	var brain_command := _find_command(k_state, MatchCommandScript.USE_SKILL, "k_megamind")
	_expect(not brain_command.is_empty() and bool(k_state.call("submit_command", brain_command)), "K Brain must be legal before its first use.")
	var brain_request: Dictionary = k_state.get("pending_skill_discard") as Dictionary
	_expect(String(brain_request.get("selection_mode", "")) == "count" and int(brain_request.get("required_count", 0)) == 1, "K Brain must request exactly one discarded card.")
	var brain_hand: Array = (k_state.call("player", 0) as Dictionary).get("hand", []) as Array
	if not brain_hand.is_empty():
		var brain_discard := MatchCommandScript.make(MatchCommandScript.SKILL_DISCARD, 0, {"request_id": brain_request.get("request_id", ""), "card_ids": [String(brain_hand[0])]})
		_expect(bool(k_state.call("submit_command", brain_discard)), "K Brain's one-card discard must resolve.")
	brain_policy = k_state.call("skill_usage_policy", 0, "k_megamind") as Dictionary
	_expect(int(brain_policy.get("remaining_this_turn", -1)) == 0, "K Brain must report zero remaining uses after use.")
	_expect(_find_command(k_state, MatchCommandScript.USE_SKILL, "k_megamind").is_empty(), "K Brain must be unavailable after one use in the same turn.")

	var strategy_policy: Dictionary = k_state.call("skill_usage_policy", 0, "k_brainstorm") as Dictionary
	_expect(int(strategy_policy.get("uses_per_profession_per_match", 0)) == 1, "K Strategy must expose its per-profession match limit.")
	_expect(bool(strategy_policy.get("executable", false)), "K Strategy must be executable through the new deterministic choice flow.")
	var strategy_command := _find_command(k_state, MatchCommandScript.USE_SKILL, "k_brainstorm")
	_expect(not strategy_command.is_empty() and bool(k_state.call("submit_command", strategy_command)), "K Strategy must open its arbitrary strange-card choice.")
	_expect(String((k_state.get("pending_skill_choice") as Dictionary).get("kind", "")) == "k_strategy_card", "K Strategy must first select one strange card.")
	var k_player: Dictionary = k_state.call("player", 0) as Dictionary
	k_player["profession"] = "ambitionist"
	k_state.players[0] = k_player
	strategy_policy = k_state.call("skill_usage_policy", 0, "k_brainstorm") as Dictionary
	_expect(int(strategy_policy.get("remaining_for_profession", -1)) == 1, "K Strategy must have a separate use in the second profession.")
	_expect(int(strategy_policy.get("remaining_for_profession", -1)) == 1, "Changing profession must preserve a separate displayed profession limit.")
	var staged_strategy: Dictionary = catalog.call("staged_skill", "k", "k_strategy") as Dictionary
	k_player = k_state.call("player", 0) as Dictionary
	k_player["mana"] = int(k_player.get("max_mana", 0))
	k_state.players[0] = k_player
	_expect(bool(k_state.call("_can_pay_skill", 0, staged_strategy, "normal")), "K Strategy normal resource payment must be valid with available mana.")
	var paid: Dictionary = k_state.call("_pay_skill_resources", 0, staged_strategy, "normal") as Dictionary
	_expect(int(paid.get("mana", 0)) == 2 and int((k_state.call("player", 0) as Dictionary).get("mana", -1)) == 0, "K Strategy normal payment must consume all current mana.")
	k_player = k_state.call("player", 0) as Dictionary
	k_player["stamina"] = int(k_player.get("max_stamina", 0))
	k_player["mana"] = maxi(0, int(k_player.get("max_mana", 0)) - 1)
	k_state.players[0] = k_player
	_expect(not bool(k_state.call("_can_pay_skill", 0, staged_strategy, "exhaust")), "Exhaust must be illegal unless both stamina and mana are full.")
	k_player["mana"] = int(k_player.get("max_mana", 0))
	k_state.players[0] = k_player
	_expect(bool(k_state.call("_can_pay_skill", 0, staged_strategy, "exhaust")), "Exhaust must be legal when both resources are full.")
	var exhaust_paid: Dictionary = k_state.call("_pay_skill_resources", 0, staged_strategy, "exhaust") as Dictionary
	k_player = k_state.call("player", 0) as Dictionary
	_expect(int(exhaust_paid.get("stamina", 0)) == int(k_player.get("max_stamina", 0)) and int(exhaust_paid.get("mana", 0)) == int(k_player.get("max_mana", 0)), "Exhaust must pay the character's full stamina and mana values.")
	_expect(int(k_player.get("stamina", -1)) == 0 and int(k_player.get("mana", -1)) == 0, "Exhaust payment must leave both resources at zero.")

	var maddy_state: RefCounted = _state(["maddy", "q", "ginger", "signal"], 114)
	for skill_id: String in ["maddy_prospect", "maddy_reclamation"]:
		var maddy_policy: Dictionary = maddy_state.call("skill_usage_policy", 0, skill_id) as Dictionary
		_expect(int(maddy_policy.get("uses_per_turn", 0)) == 1, "%s must retain its documented once-per-turn limit." % skill_id)
	var signal_state: RefCounted = _state(["signal", "q", "ginger", "maddy"], 115)
	var signal_policy: Dictionary = signal_state.call("skill_usage_policy", 0, "signal_frequency") as Dictionary
	_expect(int(signal_policy.get("uses_per_turn", 0)) == 1, "Signal Frequency must retain its documented once-per-turn limit.")
	var q_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 116)
	var q_policy: Dictionary = q_state.call("skill_usage_policy", 0, "q_thunder_call") as Dictionary
	_expect(int(q_policy.get("uses_per_turn", 0)) == 1 and int(q_policy.get("remaining_this_turn", -1)) == 1, "Q Thunderstorm must expose its documented once-per-turn limit.")


func _test_k_brain_and_ginger_waist() -> void:
	var k_state: RefCounted = _state(["k", "ginger", "maddy", "signal"], 118)
	var k: Dictionary = k_state.call("player", 0) as Dictionary
	k["hand"] = ["rally_new#001"]
	k["discard"] = ["slash_new#001"]
	k["common_discard"] = ["slash_new#001"]
	k["profession_discard"] = []
	k["last_card_id"] = "slash_new#001"
	k["armor"] = 0
	k_state.players[0] = k
	var brain := _find_command(k_state, MatchCommandScript.USE_SKILL, "k_megamind")
	_expect(not brain.is_empty() and bool(k_state.call("submit_command", brain)), "K Brain must open its one-card payment request.")
	var request: Dictionary = k_state.get("pending_skill_discard") as Dictionary
	var invalid := MatchCommandScript.make(MatchCommandScript.SKILL_DISCARD, 0, {"request_id": request.get("request_id", ""), "card_ids": []})
	_expect(not bool(k_state.call("submit_command", invalid)), "K Brain must reject a selection that is not exactly one card.")
	var payment := MatchCommandScript.make(MatchCommandScript.SKILL_DISCARD, 0, {"request_id": request.get("request_id", ""), "card_ids": ["rally_new#001"]})
	_expect(bool(k_state.call("submit_command", payment)), "K Brain must resolve after exactly one card is discarded.")
	k = k_state.call("player", 0) as Dictionary
	_expect((k.get("hand", []) as Array).has("slash_new#001") and not (k.get("discard", []) as Array).has("slash_new#001"), "K Brain's Recursion step must transfer the previous card back to hand without duplicating its instance.")
	_expect(int((k.get("modifiers", {}) as Dictionary).get("repeat_next_card", 0)) == 1, "K Brain's Echo step must repeat the next card.")
	_expect(int((k.get("modifiers", {}) as Dictionary).get("free_cast", 0)) == 1, "K Brain's Prayer step must make the next card free.")
	_expect(bool((k.get("flags", {}) as Dictionary).get("cannot_deal_damage", false)), "K Brain must prevent K from dealing damage for the rest of the turn.")
	_expect(int(k.get("armor", -1)) == 0, "K Brain must not retain the removed legacy armor effect.")
	var enemy_before := int((k_state.call("player", 1) as Dictionary).get("health", 0))
	_expect(int(k_state.call("_deal_damage", 1, 5, "true", 0, false)) == 0, "K Brain must reduce every K-attributed damage instance to zero.")
	_expect(int((k_state.call("player", 1) as Dictionary).get("health", 0)) == enemy_before, "K Brain damage prevention must leave the target's health unchanged.")
	var snapshot: Dictionary = k_state.call("deterministic_snapshot") as Dictionary
	var k_snapshot: Dictionary = (snapshot.get("players", []) as Array)[0] as Dictionary
	_expect(bool((k_snapshot.get("flags", {}) as Dictionary).get("cannot_deal_damage", false)) and (k_snapshot.get("active_breakthroughs", {}) as Dictionary).is_empty(), "Turn skill flags and breakthrough state must be present in deterministic snapshots.")

	var ai_state: RefCounted = _state(["k", "ginger", "maddy", "signal"], 119)
	var ai_brain := _find_command(ai_state, MatchCommandScript.USE_SKILL, "k_megamind")
	ai_state.call("submit_command", ai_brain)
	var ai := AIControllerScript.new()
	var ai_payment: Dictionary = ai.call("choose_command", ai_state, 0) as Dictionary
	_expect(String(ai_payment.get("type", "")) == MatchCommandScript.SKILL_DISCARD and ((ai_payment.get("payload", {}) as Dictionary).get("card_ids", []) as Array).size() == 1, "AI must satisfy count-based skill discard requests.")
	_expect(bool(ai_state.call("submit_command", ai_payment)), "AI's count-based skill payment must validate.")
	var replay_state: RefCounted = MatchStateScript.new(rules, catalog, ["k", "ginger", "maddy", "signal"], 119)
	for replay_command: Dictionary in ai_state.get("command_log") as Array[Dictionary]:
		_expect(bool(replay_state.call("submit_command", replay_command)), "K Brain replay commands must remain legal.")
	_expect(replay_state.call("deterministic_snapshot") == ai_state.call("deterministic_snapshot"), "K Brain's count discard and turn modifiers must replay to the same deterministic snapshot.")

	var ginger_state: RefCounted = _state(["ginger", "q", "maddy", "signal"], 120)
	var ginger: Dictionary = ginger_state.call("player", 0) as Dictionary
	var target: Dictionary = ginger_state.call("player", 1) as Dictionary
	ginger["health"] = 8
	ginger["hand"] = ["slash_new#001"]
	ginger["position"] = Vector2i(2, 2)
	target["health"] = 5
	target["max_health"] = 10
	target["position"] = Vector2i(3, 2)
	target["hand"] = []
	ginger_state.players[0] = ginger
	ginger_state.players[1] = target
	var attack := _find_command(ginger_state, MatchCommandScript.PLAY_CARD, "slash_new#001")
	_expect(not attack.is_empty() and bool(ginger_state.call("submit_command", attack)), "Ginger must be able to attack an adjacent half-health target.")
	_expect(int((ginger_state.call("player", 1) as Dictionary).get("health", 0)) == 3, "Ginger's half-health bonus must be applied exactly once.")
	_expect(int((ginger_state.call("player", 0) as Dictionary).get("health", 0)) == 6, "Ginger Waist must lose exactly two health after damaging a lower-health target and must not recurse.")
	var lethal_state: RefCounted = _state(["ginger", "q", "maddy", "signal"], 123)
	var lethal_ginger: Dictionary = lethal_state.call("player", 0) as Dictionary
	var lethal_target: Dictionary = lethal_state.call("player", 1) as Dictionary
	lethal_ginger["health"] = 8
	lethal_target["health"] = 1
	lethal_state.players[0] = lethal_ginger
	lethal_state.players[1] = lethal_target
	lethal_state.call("_deal_damage", 1, 1, "normal", 0, true)
	_expect(int((lethal_state.call("player", 0) as Dictionary).get("health", 0)) == 8, "Ginger Waist must not trigger when the damage defeats its target.")

	var breakthrough_state: RefCounted = _state(["ginger", "q", "maddy", "signal"], 124)
	var breakthrough_ginger: Dictionary = breakthrough_state.call("player", 0) as Dictionary
	breakthrough_ginger["health"] = 2
	breakthrough_ginger["max_health"] = 8
	breakthrough_ginger["turn_healing"] = 2
	breakthrough_ginger["active_breakthroughs"] = {"ginger_power": true}
	breakthrough_ginger["breakthrough_losses"] = {"ginger_power": {"health": 6}}
	breakthrough_state.players[0] = breakthrough_ginger
	breakthrough_state.call("_heal", 0, 1)
	_expect(int((breakthrough_state.call("player", 0) as Dictionary).get("health", 0)) == 3, "Ginger's breakthrough cost must not restore immediately when its goal is met.")
	breakthrough_state.call("_handle_end_turn")
	_expect(int((breakthrough_state.call("player", 0) as Dictionary).get("health", 0)) == 8, "Ginger must restore only the breakthrough's recorded health cost at turn end.")


func _test_ai_duel_damage_priority() -> void:
	var state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 117)
	var q: Dictionary = state.call("player", 0) as Dictionary
	var ginger: Dictionary = state.call("player", 1) as Dictionary
	q["position"] = Vector2i(5, 5)
	q["hand"] = ["slash_new#001"]
	q["purchased_hand"] = []
	q["moves_remaining"] = 1
	ginger["position"] = Vector2i(7, 5)
	state.players[0] = q
	state.players[1] = ginger
	for player_id: int in [2, 3]:
		var eliminated: Dictionary = state.call("player", player_id) as Dictionary
		eliminated["alive"] = false
		eliminated["health"] = 0
		state.players[player_id] = eliminated
	var ai: RefCounted = AIControllerScript.new()
	var command: Dictionary = ai.call("choose_command", state, 0) as Dictionary
	_expect(String(command.get("type", "")) == MatchCommandScript.PLAY_CARD and String((command.get("payload", {}) as Dictionary).get("card_id", "")) == "slash_new#001", "AI must prefer an immediately damaging legal card over repositioning in the final duel.")


func _test_zc_frenzy_flow() -> void:
	var state: RefCounted = _state(["zc", "q", "maddy", "signal"], 122)
	var zc: Dictionary = state.call("player", 0) as Dictionary
	var target: Dictionary = state.call("player", 1) as Dictionary
	zc["hand"] = ["slash_new#001", "iron_body_new#001"]
	zc["position"] = Vector2i(2, 2)
	target["position"] = Vector2i(12, 12)
	target["hand"] = []
	target["purchased_hand"] = []
	state.players[0] = zc
	state.players[1] = target
	var frenzy := _find_command(state, MatchCommandScript.USE_SKILL, "zc_madness")
	_expect(not frenzy.is_empty() and bool(state.call("submit_command", frenzy)), "Z&C must expose one executable Frenzy skill.")
	var category_request: Dictionary = state.get("pending_skill_choice") as Dictionary
	_expect(String(category_request.get("kind", "")) == "zc_frenzy_category" and (category_request.get("options", []) as Array).has("attack"), "Frenzy must request one existing hand category.")
	var category_choice := MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": category_request.get("request_id", ""), "value": "attack"})
	_expect(bool(state.call("submit_command", category_choice)), "Frenzy must accept the selected category.")
	zc = state.call("player", 0) as Dictionary
	_expect(not (zc.get("hand", []) as Array).has("slash_new#001") and (zc.get("discard", []) as Array).has("slash_new#001"), "Frenzy must discard every card of the selected category.")
	var target_request: Dictionary = state.get("pending_skill_choice") as Dictionary
	_expect(String(target_request.get("kind", "")) == "zc_frenzy_target" and (target_request.get("options", []) as Array).has(1), "Frenzy must ignore distance when selecting a target.")
	var before_health := int(target.get("health", 0))
	var target_choice := MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": target_request.get("request_id", ""), "value": 1})
	_expect(bool(state.call("submit_command", target_choice)), "Frenzy's simulated Poisoned Strike must resolve.")
	zc = state.call("player", 0) as Dictionary
	_expect(int((state.call("player", 1) as Dictionary).get("health", 0)) < before_health, "Frenzy must deal Poisoned Strike damage.")
	_expect((((zc.get("flags", {}) as Dictionary).get("zc_frenzy_hit_targets", []) as Array).has(1)), "A damaged target must be unavailable to Frenzy for the rest of the turn.")
	var poisoned_target: Dictionary = state.call("player", 1) as Dictionary
	var poisoned_statuses: Dictionary = poisoned_target.get("statuses", {}) as Dictionary
	_expect(int(poisoned_statuses.get("poison", 0)) == 2, "Z&C's first applied poison each turn must gain one extra stack from Insect Mark.")
	_expect((state.get("poison_mists") as Array).size() == 1, "Z&C's first applied poison each turn must create one poison mist.")
	state.active_player_index = 1
	state.call("_begin_turn")
	poisoned_target = state.call("player", 1) as Dictionary
	poisoned_statuses = poisoned_target.get("statuses", {}) as Dictionary
	_expect(int(poisoned_statuses.get("poison", 0)) >= 1, "A character beginning a turn inside Z&C's poison mist must receive poison.")
	poisoned_statuses.erase("poison")
	poisoned_target["statuses"] = poisoned_statuses
	state.players[1] = poisoned_target
	state.completed_rounds = 2
	state.call("_begin_turn")
	poisoned_target = state.call("player", 1) as Dictionary
	poisoned_statuses = poisoned_target.get("statuses", {}) as Dictionary
	_expect(int(poisoned_statuses.get("poison", 0)) == 0 and (state.get("poison_mists") as Array).is_empty(), "Z&C's poison mist must expire before the third round begins.")


func _test_ai_revised_skill_choices() -> void:
	var state: RefCounted = _state(["zc", "q", "maddy", "signal"], 129)
	state.players[0]["hand"] = ["slash_new#001", "iron_body_new#001", "rally_new#001"]
	state.players[1]["health"] = 5
	state.players[2]["health"] = 2
	state.players[3]["health"] = 4
	var frenzy := _find_command(state, MatchCommandScript.USE_SKILL, "zc_madness")
	_expect(bool(state.call("submit_command", frenzy)), "Z&C Frenzy must open its category choice for AI policy verification.")
	var ai: RefCounted = AIControllerScript.new()
	var category_choice: Dictionary = ai.call("choose_command", state, 0) as Dictionary
	_expect(String((category_choice.get("payload", {}) as Dictionary).get("value", "")) == "attack", "Z&C AI must discard the smallest available category for Frenzy.")
	_expect(bool(state.call("submit_command", category_choice)), "Z&C AI category choice must be legal.")
	var target_choice: Dictionary = ai.call("choose_command", state, 0) as Dictionary
	_expect(int((target_choice.get("payload", {}) as Dictionary).get("value", -1)) == 2, "Z&C AI must target the lowest-health enemy with Frenzy.")

	var k_state: RefCounted = _state(["k", "ginger", "maddy", "signal"], 130)
	k_state.players[0]["hand"] = ["slash_new#001", "calm_mind_new#001"]
	k_state.players[0]["mana"] = 2
	var strategy := _find_command(k_state, MatchCommandScript.USE_SKILL, "k_brainstorm")
	_expect(bool(k_state.call("submit_command", strategy)), "K Strategy must open its card choice for AI policy verification.")
	var strategy_choice: Dictionary = ai.call("choose_command", k_state, 0) as Dictionary
	_expect(String((strategy_choice.get("payload", {}) as Dictionary).get("value", "")) == "soul_drain_new#001", "K AI must prefer repeatable card theft over draw-heavy Strategy copies.")


func _test_named_revised_card_effects() -> void:
	var tusk_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 125)
	var q: Dictionary = tusk_state.call("player", 0) as Dictionary
	var far_target: Dictionary = tusk_state.call("player", 1) as Dictionary
	q["hand"] = ["tusk_new#001"]
	q["position"] = Vector2i(1, 1)
	far_target["position"] = Vector2i(13, 13)
	far_target["hand"] = ["heavenly_sense_new#001"]
	far_target["purchased_hand"] = []
	var far_target_health_max_before := int(far_target.get("max_health", 0))
	tusk_state.players[0] = q
	tusk_state.players[1] = far_target
	var tusk := _find_command(tusk_state, MatchCommandScript.PLAY_CARD, "tusk_new#001")
	_expect(not tusk.is_empty() and bool(tusk_state.call("submit_command", tusk)), "TUSK must be usable without distance restriction.")
	_expect((tusk_state.get("pending_action") as Dictionary).is_empty(), "TUSK must not open a response window.")
	_expect(int((tusk_state.call("player", 1) as Dictionary).get("max_health", -1)) == maxi(1, far_target_health_max_before - 2), "TUSK must reduce the target's health maximum by two.")

	var bloodbath_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 126)
	var bloodbath_q: Dictionary = bloodbath_state.call("player", 0) as Dictionary
	var bloodbath_target: Dictionary = bloodbath_state.call("player", 1) as Dictionary
	bloodbath_q["hand"] = ["bloodbath_new#001"]
	bloodbath_q["health"] = int(bloodbath_q.get("max_health", 7)) - 3
	bloodbath_q["stamina"] = 2
	bloodbath_q["position"] = Vector2i(2, 2)
	bloodbath_target["position"] = Vector2i(3, 2)
	bloodbath_target["hand"] = []
	bloodbath_target["purchased_hand"] = []
	var bloodbath_target_before := int(bloodbath_target.get("health", 0))
	var bloodbath_source_before := int(bloodbath_q.get("health", 0))
	bloodbath_state.players[0] = bloodbath_q
	bloodbath_state.players[1] = bloodbath_target
	var bloodbath := _find_command(bloodbath_state, MatchCommandScript.PLAY_CARD, "bloodbath_new#001")
	_expect(not bloodbath.is_empty() and bool(bloodbath_state.call("submit_command", bloodbath)), "Bloodbath must resolve its documented dynamic damage.")
	_expect(int((bloodbath_state.call("player", 1) as Dictionary).get("health", 0)) == bloodbath_target_before - 3, "Bloodbath damage must equal missing health up to four.")
	_expect(int((bloodbath_state.call("player", 0) as Dictionary).get("health", 0)) == bloodbath_source_before - 1, "Bloodbath must deal one true self-damage after resolving.")

	var sleepless_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 127)
	var sleepless_q: Dictionary = sleepless_state.call("player", 0) as Dictionary
	sleepless_q["hand"] = ["sleepless_new#001"]
	sleepless_q["mana"] = 1
	sleepless_state.players[0] = sleepless_q
	var sleepless := _find_command(sleepless_state, MatchCommandScript.PLAY_CARD, "sleepless_new#001")
	_expect(not sleepless.is_empty() and bool(sleepless_state.call("submit_command", sleepless)), "Sleepless must be playable with one mana.")
	_expect(not (sleepless_state.get("last_event") as Dictionary).is_empty(), "Sleepless must immediately draw and begin resolving a random event.")


func _test_first_wave_formal_cards() -> void:
	var formal_ids: Array[String] = [
		"rapid_healing_new", "antidote_new", "hearty_meal_new", "calm_mind_new", "rally_new", "soul_drain_new", "armor_break_new",
		"berserker_charge_new", "blood_guard_new", "sacrifice_new", "feast_new", "swift_attack_new", "ghost_step_new",
		"holy_spring_guardian_new", "blazing_blast_new", "chaos_wave_new", "vampire_bite_new", "blood_surge_new", "poisoned_strike_new",
		"scout_new", "trek_new", "digging_new", "one_dollar_new", "recursion_new", "prayer_new", "echo_new", "greedy_grip_new",
		"strong_shell_new", "velvet_ring_new", "unyielding_heart_new", "tusk_new", "bloodbath_new", "sleepless_new"
		, "relentless_assault_new", "gold_pick_new", "berserker_blow_new", "armor_piercing_shot_new", "living_wood_new", "hell_armor_new", "hell_collar_new", "crimson_cape_new", "rummage_new"
	]
	for card_id: String in formal_ids:
		var definition: Dictionary = catalog.call("resolve_card", "%s#001" % card_id) as Dictionary
		_expect(not bool(definition.get("provisional", true)), "%s must be formal once its complete effect sequence is implemented." % card_id)

	var resource_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 151)
	resource_state.players[0]["hand"] = ["rapid_healing_new#001", "one_dollar_new#001"]
	resource_state.players[0]["stamina"] = 0
	resource_state.players[0]["mana"] = 2
	resource_state.players[0]["statuses"] = {"bleed": 1}
	resource_state.players[1]["position"] = Vector2i(3, 2)
	resource_state.players[1]["hand"] = []
	var rapid_healing := _find_command(resource_state, MatchCommandScript.PLAY_CARD, "rapid_healing_new#001")
	_expect(not rapid_healing.is_empty() and bool(resource_state.call("submit_command", rapid_healing)), "Rapid Healing must play as a formal self-defense card.")
	_expect(not (resource_state.players[0].get("statuses", {}) as Dictionary).has("bleed") and int(resource_state.players[0].get("stamina", 0)) == 1, "Rapid Healing must remove bleed and restore one stamina.")
	var target_health := int(resource_state.players[1].get("health", 0))
	var coins_before := int(resource_state.players[0].get("coins", 0))
	var one_dollar := _find_command(resource_state, MatchCommandScript.PLAY_CARD, "one_dollar_new#001")
	_expect(not one_dollar.is_empty() and bool(resource_state.call("submit_command", one_dollar)), "One Dollar must play as a formal multi-hit attack.")
	_expect(int(resource_state.players[1].get("health", 0)) == target_health - 2 and int(resource_state.players[0].get("coins", 0)) == coins_before + 2, "One Dollar must deal two sequential damage instances and grant two coins.")

	var status_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 152)
	status_state.players[0]["hand"] = ["blazing_blast_new#001", "chaos_wave_new#001", "blood_surge_new#001", "poisoned_strike_new#001"]
	status_state.players[0]["stamina"] = 4
	status_state.players[0]["mana"] = 4
	status_state.players[1]["position"] = Vector2i(3, 2)
	status_state.players[1]["hand"] = []
	for card_id: String in ["blazing_blast_new#001", "chaos_wave_new#001", "blood_surge_new#001", "poisoned_strike_new#001"]:
		var command := _find_command(status_state, MatchCommandScript.PLAY_CARD, card_id)
		_expect(not command.is_empty() and bool(status_state.call("submit_command", command)), "%s must resolve through the formal status-card path." % card_id)
	var target_statuses: Dictionary = status_state.players[1].get("statuses", {}) as Dictionary
	_expect(int(target_statuses.get("scorch", 0)) == 1 and int(target_statuses.get("confusion", 0)) == 1 and int(target_statuses.get("bleed", 0)) == 1 and int(target_statuses.get("poison", 0)) == 1, "Formal elemental cards must apply their documented statuses.")

	var trek_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 153)
	trek_state.players[0]["hand"] = ["trek_new#001"]
	trek_state.players[0]["moves_remaining"] = 0
	var trek := _find_command(trek_state, MatchCommandScript.PLAY_CARD, "trek_new#001")
	_expect(not trek.is_empty() and bool(trek_state.call("submit_command", trek)), "Trek must play as a formal extra-move card.")
	_expect(int(trek_state.players[0].get("moves_remaining", 0)) == 1, "Trek must grant exactly one additional movement.")

	for accessory_id: String in ["strong_shell_new#001", "velvet_ring_new#001", "unyielding_heart_new#001"]:
		var equipment_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 154)
		equipment_state.players[0]["stamina"] = 0
		equipment_state.players[0]["mana"] = 0
		equipment_state.players[0]["health"] = int(equipment_state.players[0].get("max_health", 1)) - 2
		equipment_state.call("_equip", 0, accessory_id)
		equipment_state.call("_apply_start_turn_equipment", 0)
		if accessory_id == "strong_shell_new#001":
			_expect(int(equipment_state.players[0].get("stamina", 0)) == 1, "Strong Shell must grant one stamina at turn start.")
		elif accessory_id == "velvet_ring_new#001":
			_expect(int(equipment_state.players[0].get("mana", 0)) == 1, "Velvet Ring must grant one mana at turn start.")
		else:
			_expect(int(equipment_state.players[0].get("health", 0)) == int(equipment_state.players[0].get("max_health", 1)) - 1, "Unyielding Heart must heal one health at turn start.")

	var assault_state: RefCounted = _state(["ginger", "q", "maddy", "signal"], 155)
	assault_state.players[0]["hand"] = ["relentless_assault_new#001"]
	assault_state.players[0]["stamina"] = 2
	assault_state.players[0]["position"] = Vector2i(2, 2)
	assault_state.players[1]["position"] = Vector2i(3, 2)
	assault_state.players[1]["hand"] = []
	var assault_target_health := int(assault_state.players[1].get("health", 0))
	var assault := _find_command(assault_state, MatchCommandScript.PLAY_CARD, "relentless_assault_new#001")
	_expect(not assault.is_empty() and bool(assault_state.call("submit_command", assault)), "Relentless Assault must resolve as a formal multi-hit attack.")
	_expect(int(assault_state.players[1].get("health", 0)) == assault_target_health - 3, "Relentless Assault must deal three separate one-point damage instances.")

	var pick_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 156)
	pick_state.players[0]["hand"] = ["slash_new#001"]
	pick_state.players[0]["stamina"] = 1
	pick_state.players[0]["position"] = Vector2i(2, 2)
	pick_state.players[1]["position"] = Vector2i(3, 2)
	pick_state.players[1]["hand"] = []
	pick_state.call("_equip", 0, "gold_pick_new#001")
	var pick_coins := int(pick_state.players[0].get("coins", 0))
	var pick_attack := _find_command(pick_state, MatchCommandScript.PLAY_CARD, "slash_new#001")
	_expect(not pick_attack.is_empty() and bool(pick_state.call("submit_command", pick_attack)), "A player with Gold Pick must be able to damage an adjacent target.")
	_expect(int(pick_state.players[0].get("coins", 0)) == pick_coins + 1, "Gold Pick must grant one coin only after damage is actually dealt.")

	for card_id: String in ["berserker_blow_new#001", "armor_piercing_shot_new#001"]:
		var armor_state: RefCounted = _state(["ginger", "q", "maddy", "signal"], 157)
		armor_state.players[0]["hand"] = [card_id]
		armor_state.players[0]["stamina"] = 2
		armor_state.players[0]["position"] = Vector2i(2, 2)
		armor_state.players[1]["position"] = Vector2i(3, 2)
		armor_state.players[1]["armor"] = 1
		armor_state.players[1]["hand"] = []
		var health_before := int(armor_state.players[1].get("health", 0))
		var armor_command := _find_command(armor_state, MatchCommandScript.PLAY_CARD, card_id)
		_expect(not armor_command.is_empty() and bool(armor_state.call("submit_command", armor_command)), "%s must be playable against an armored target." % card_id)
		var expected_damage := 2 if card_id == "berserker_blow_new#001" else 1
		_expect(int(armor_state.players[1].get("health", 0)) == health_before - expected_damage, "%s must gain one damage against armor before armor reduces the hit." % card_id)

	var living_wood_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 158)
	living_wood_state.call("_equip", 0, "living_wood_new#001")
	living_wood_state.call("_apply_status", 0, "poison", 1, 1)
	living_wood_state.call("_apply_status", 0, "bleed", 1, 1)
	_expect((living_wood_state.players[0].get("statuses", {}) as Dictionary).is_empty(), "Living Wood must prevent both poison and bleed.")

	var hell_armor_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 159)
	hell_armor_state.call("_equip", 0, "hell_armor_new#001")
	hell_armor_state.call("_deal_damage", 0, 2, "true", 1, false)
	_expect(int(hell_armor_state.players[0].get("armor", 0)) == 2, "Hell Armor must gain one armor for each actual health lost.")

	var cape_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 160)
	cape_state.call("_equip", 0, "crimson_cape_new#001")
	var cape_health := int(cape_state.players[0].get("health", 0))
	cape_state.call("_deal_damage", 0, 2, "true", 1, false)
	_expect(int(cape_state.players[0].get("health", 0)) == cape_health - 1, "Crimson Cape must reduce damage by one during its owner's turn.")

	var collar_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 161)
	collar_state.players[0]["hand"] = []
	collar_state.players[0]["health"] = int(collar_state.players[0].get("max_health", 1)) - 2
	collar_state.call("_equip", 0, "hell_collar_new#001")
	var collar_health := int(collar_state.players[0].get("health", 0))
	collar_state.call("_apply_start_turn_equipment", 0)
	_expect(int(collar_state.players[0].get("health", 0)) == collar_health - 1 and (collar_state.players[0].get("hand", []) as Array).size() == 2, "Hell Collar must deal one self-damage then draw two cards at turn start.")


func _test_rummage_draw_then_discard() -> void:
	var state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 162)
	var active: Dictionary = state.call("player", 0) as Dictionary
	active["hand"] = ["rummage_new#001", "calm_mind_new#001"]
	active["common_deck"] = []
	active["profession_deck"] = ["ghost_step_new#002", "ghost_step_new#001"]
	active["common_discard"] = []
	active["profession_discard"] = []
	state.players[0] = active
	for player_id: int in range(1, state.players.size()):
		state.players[player_id]["hand"] = []
	var rummage := _find_command(state, MatchCommandScript.PLAY_CARD, "rummage_new#001")
	_expect(not rummage.is_empty() and bool(state.call("submit_command", rummage)), "Rummage must be playable as a formal card.")
	var request: Dictionary = state.get("pending_discard") as Dictionary
	_expect(int(request.get("required_count", 0)) == 2, "Rummage must request exactly two player-selected discards after drawing.")
	var hand: Array = (state.call("player", 0) as Dictionary).get("hand", []) as Array
	_expect(hand.has("calm_mind_new#001") and hand.has("ghost_step_new#001") and hand.has("ghost_step_new#002"), "Rummage must add both drawn cards before selection.")
	var discard := MatchCommandScript.make(MatchCommandScript.DISCARD_CARDS, 0, {"request_id": String(request.get("request_id", "")), "card_ids": ["calm_mind_new#001", "ghost_step_new#002"]})
	_expect(bool(state.call("submit_command", discard)), "Rummage must accept an exact valid discard selection.")
	var resolved: Dictionary = state.call("player", 0) as Dictionary
	_expect((resolved.get("hand", []) as Array) == ["ghost_step_new#001"], "Rummage must retain only unselected cards after its discard resolves.")
	_expect((resolved.get("discard", []) as Array).has("rummage_new#001") and (resolved.get("discard", []) as Array).has("calm_mind_new#001") and (resolved.get("discard", []) as Array).has("ghost_step_new#002"), "Rummage and selected cards must enter the discard pile.")
	_expect((state.get("pending_discard") as Dictionary).is_empty(), "Rummage discard continuation must fully resolve.")


func _test_ritual_dagger_kill_reward() -> void:
	var state: RefCounted = _state(["ginger", "q", "maddy", "signal"], 163)
	state.players[0]["hand"] = ["slash_new#001"]
	state.players[0]["stamina"] = 1
	state.players[0]["position"] = Vector2i(2, 2)
	state.players[1]["hand"] = []
	state.players[1]["position"] = Vector2i(4, 2)
	state.players[1]["health"] = 1
	state.call("_equip", 0, "ritual_dagger_new#001")
	var dagger: Dictionary = state.call("equipped_definition", 0, "weapon") as Dictionary
	_expect(int(dagger.get("attack_range_bonus", 0)) == 1, "Ritual Dagger must grant one additional attack range.")
	var health_limit_before := int(state.players[0].get("max_health", 0))
	var attack := _find_command(state, MatchCommandScript.PLAY_CARD, "slash_new#001")
	_expect(not attack.is_empty() and bool(state.call("submit_command", attack)), "Ritual Dagger must make a distance-two attack legal for a base-range-one profession.")
	var durability: Dictionary = state.players[0].get("equipment_durability", {}) as Dictionary
	var weapon_durability: Dictionary = durability.get("weapon", {}) as Dictionary
	_expect(not bool(state.players[1].get("alive", true)), "The Ritual Dagger test attack must defeat its target.")
	_expect(int(state.players[0].get("max_health", 0)) == health_limit_before + 1, "Ritual Dagger must grant one maximum health after its owner defeats a character.")
	_expect(int(weapon_durability.get("current", -1)) == int(weapon_durability.get("maximum", -2)), "Ritual Dagger must reset its weapon durability after a defeat.")


func _test_confirmed_card_batch_one() -> void:
	for card_id: String in ["fallen_power_new", "assassination_new", "hasten_new", "fortify_new", "iron_wall_new", "blood_river_new", "mountain_still_new", "rapier_new", "piercing_lance_new", "sulfur_fire_new", "sniper_new", "rapid_fire_new", "aim_new", "overdraft_new", "armament_new", "close_shot_new", "assassinate_new", "thunderstorm_new", "dragon_breath_new", "momentum_new", "hand_repel_new", "precision_stab_new", "body_slam_new", "overlimit_pistol_new", "mad_thought_new", "annihilate_new", "gaze_new", "trench_coat_new", "heavy_blade_new", "shield_axe_guardian_new", "mana_flow_new", "a_plus_new", "assassin_dagger_new", "serpent_blade_new", "poison_bottle_new", "rock_bottom_new", "catapult_new", "element_lens_new", "lost_path_new"]:
		var definition: Dictionary = catalog.call("resolve_card", "%s#001" % card_id) as Dictionary
		_expect(not bool(definition.get("provisional", true)), "%s must be formal after its confirmed rule is implemented." % card_id)

	var trench_state: RefCounted = _state(["maddy", "q", "ginger", "signal"], 190)
	trench_state.players[0]["position"] = Vector2i(2, 2)
	trench_state.players[0]["hand"] = []
	trench_state.players[0]["common_deck"] = ["slash_new#001"]
	trench_state.players[0]["profession_deck"] = []
	trench_state.trap_tiles.append(Vector2i(3, 2))
	trench_state.call("_equip", 0, "trench_coat_new#001")
	var trench_health := int(trench_state.players[0].get("health", 0))
	trench_state.call("_handle_move", {"path": [[3, 2]]})
	_expect(int(trench_state.players[0].get("health", 0)) == trench_health and (trench_state.players[0].get("hand", []) as Array).has("slash_new#001"), "Trench Coat must prevent trap damage and draw one card on trap entry.")

	var heavy_blade_state: RefCounted = _state(["ginger", "q", "maddy", "signal"], 191)
	heavy_blade_state.players[0]["position"] = Vector2i(2, 2)
	heavy_blade_state.players[1]["position"] = Vector2i(3, 2)
	heavy_blade_state.players[0]["hand"] = ["slash_new#001"]
	heavy_blade_state.players[0]["stamina"] = 1
	heavy_blade_state.players[1]["hand"] = []
	heavy_blade_state.call("_equip", 0, "heavy_blade_new#001")
	var heavy_target_health := int(heavy_blade_state.players[1].get("health", 0))
	_expect(bool(heavy_blade_state.call("submit_command", _find_command(heavy_blade_state, MatchCommandScript.PLAY_CARD, "slash_new#001"))) and int(heavy_blade_state.players[1].get("health", 0)) == heavy_target_health - 2, "Heavy Blade must add one damage to attacks.")
	var status_health := int(heavy_blade_state.players[1].get("health", 0))
	heavy_blade_state.call("_deal_damage", 1, 1, "true", 0, false)
	_expect(int(heavy_blade_state.players[1].get("health", 0)) == status_health - 1, "Heavy Blade must not add damage to non-attack damage.")

	var shield_axe_state: RefCounted = _state(["maddy", "q", "ginger", "signal"], 192)
	shield_axe_state.players[0]["position"] = Vector2i(2, 2)
	shield_axe_state.players[1]["position"] = Vector2i(3, 2)
	shield_axe_state.players[0]["hand"] = ["slash_new#001"]
	shield_axe_state.players[0]["stamina"] = 1
	shield_axe_state.players[1]["hand"] = []
	shield_axe_state.players[1]["armor"] = 1
	shield_axe_state.call("_equip", 0, "shield_axe_guardian_new#001")
	var axe_target_health := int(shield_axe_state.players[1].get("health", 0))
	_expect(bool(shield_axe_state.call("submit_command", _find_command(shield_axe_state, MatchCommandScript.PLAY_CARD, "slash_new#001"))) and int(shield_axe_state.players[1].get("health", 0)) == axe_target_health - 1 and int(shield_axe_state.players[0].get("armor", 0)) == 1, "Shield Axe must add one damage against existing armor and gain armor after actual damage.")

	var mana_flow_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 193)
	mana_flow_state.players[0]["hand"] = ["mana_flow_new#001", "blazing_blast_new#001"]
	mana_flow_state.players[0]["mana"] = 0
	mana_flow_state.players[0]["common_deck"] = ["slash_new#001"]
	mana_flow_state.players[0]["profession_deck"] = []
	_expect(bool(mana_flow_state.call("submit_command", _find_command(mana_flow_state, MatchCommandScript.PLAY_CARD, "mana_flow_new#001"))), "Mana Flow must open an elemental-card discard request.")
	var mana_flow_request: Dictionary = mana_flow_state.get("pending_skill_discard") as Dictionary
	_expect(not bool(mana_flow_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_DISCARD, 0, {"request_id": String(mana_flow_request.get("request_id", "")), "card_ids": ["slash_new#001"]}))), "Mana Flow must reject a non-elemental discard selection.")
	var mana_flow_resolved := bool(mana_flow_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_DISCARD, 0, {"request_id": String(mana_flow_request.get("request_id", "")), "card_ids": ["blazing_blast_new#001"]})))
	_expect(mana_flow_resolved and int(mana_flow_state.players[0].get("mana", 0)) == 1 and (mana_flow_state.players[0].get("hand", []) as Array).size() == 1 and not (mana_flow_state.players[0].get("hand", []) as Array).has("mana_flow_new#001"), "Mana Flow must discard a selected elemental card, restore mana, and draw one card.")

	var a_plus_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 194)
	a_plus_state.players[0]["hand"] = ["slash_new#001", "slash_new#002"]
	a_plus_state.players[0]["stamina"] = 2
	a_plus_state.players[0]["position"] = Vector2i(2, 2)
	a_plus_state.players[1]["position"] = Vector2i(3, 2)
	a_plus_state.players[1]["hand"] = []
	a_plus_state.call("_equip", 0, "a_plus_new#001")
	var a_plus_health := int(a_plus_state.players[1].get("health", 0))
	_expect(bool(a_plus_state.call("submit_command", _find_command(a_plus_state, MatchCommandScript.PLAY_CARD, "slash_new#001"))) and int(a_plus_state.players[1].get("health", 0)) == a_plus_health - 4, "A+ must add three damage to the first attack each turn.")
	a_plus_state.players[0]["stamina"] = 1
	a_plus_health = int(a_plus_state.players[1].get("health", 0))
	_expect(bool(a_plus_state.call("submit_command", _find_command(a_plus_state, MatchCommandScript.PLAY_CARD, "slash_new#002"))) and int(a_plus_state.players[1].get("health", 0)) == a_plus_health - 1, "A+ must not increase later attacks in the same turn.")
	a_plus_state.call("_deal_damage", 0, 1, "true", 1, false)
	_expect(String((a_plus_state.players[0].get("equipment", {}) as Dictionary).get("weapon", "")).is_empty(), "A+ must be destroyed after its owner actually loses health.")

	var dagger_state: RefCounted = _state(["shya", "q", "maddy", "signal"], 195)
	dagger_state.players[0]["hand"] = ["slash_new#001", "slash_new#002"]
	dagger_state.players[0]["stamina"] = 2
	dagger_state.players[0]["position"] = Vector2i(2, 2)
	dagger_state.players[1]["position"] = Vector2i(3, 3)
	dagger_state.players[1]["hand"] = ["heavenly_sense_new#001"]
	dagger_state.call("_equip", 0, "assassin_dagger_new#001")
	dagger_state.call("_handle_move", {"path": [[2, 3]]})
	_expect(bool(dagger_state.call("submit_command", _find_command(dagger_state, MatchCommandScript.PLAY_CARD, "slash_new#001"))) and (dagger_state.get("pending_action") as Dictionary).is_empty(), "Assassin Dagger must make the first attack after movement unanswerable.")
	dagger_state.players[0]["stamina"] = 1
	_expect(bool(dagger_state.call("submit_command", _find_command(dagger_state, MatchCommandScript.PLAY_CARD, "slash_new#002"))) and not (dagger_state.get("pending_action") as Dictionary).is_empty(), "Assassin Dagger must leave later attacks answerable.")

	var serpent_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 196)
	serpent_state.players[0]["position"] = Vector2i(2, 2)
	serpent_state.players[1]["position"] = Vector2i(3, 2)
	serpent_state.players[0]["hand"] = ["slash_new#001"]
	serpent_state.players[0]["stamina"] = 1
	serpent_state.players[1]["hand"] = []
	serpent_state.call("_equip", 0, "serpent_blade_new#001")
	_expect(bool(serpent_state.call("submit_command", _find_command(serpent_state, MatchCommandScript.PLAY_CARD, "slash_new#001"))) and int((serpent_state.players[1].get("statuses", {}) as Dictionary).get("poison", 0)) == 1, "Serpent Blade must poison after actual damage.")

	var bottle_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 197)
	bottle_state.players[0]["position"] = Vector2i(2, 2)
	bottle_state.players[1]["position"] = Vector2i(3, 3)
	bottle_state.players[2]["position"] = Vector2i(5, 5)
	bottle_state.call("_equip", 0, "poison_bottle_new#001")
	bottle_state.call("_finish_end_turn", 0)
	_expect(int((bottle_state.players[1].get("statuses", {}) as Dictionary).get("poison", 0)) == 1 and int((bottle_state.players[2].get("statuses", {}) as Dictionary).get("poison", 0)) == 0, "Poison Bottle must poison only other characters in its 3x3 area at turn end.")

	var rock_state: RefCounted = _state(["ginger", "q", "maddy", "signal"], 198)
	rock_state.call("_equip", 0, "rock_bottom_new#001")
	var rock_max_health := int(rock_state.players[0].get("max_health", 0))
	rock_state.call("_change_max_health", 0, -1, "test")
	_expect(int(rock_state.players[0].get("max_health", 0)) == rock_max_health, "Rock Bottom must prevent maximum-health reduction.")
	rock_state.players[0]["position"] = Vector2i(0, 0)
	rock_state.call("_collapse_board")
	_expect(int(rock_state.players[0].get("health", 0)) < rock_max_health, "Rock Bottom must not incorrectly prevent collapse damage.")

	var catapult_state: RefCounted = _state(["signal", "q", "ginger", "maddy"], 199)
	catapult_state.players[0]["profession"] = "shooter"
	catapult_state.call("_equip", 0, "catapult_new#001")
	var catapult_attack: Dictionary = catalog.call("resolve_card", "slash_new#001") as Dictionary
	_expect(int(catapult_state.call("_definition_range", 0, catapult_attack)) == 9, "Catapult must add six attack range to the shooter's base range.")

	var lens_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 200)
	lens_state.call("_equip", 0, "element_lens_new#001")
	lens_state.call("_apply_status", 1, "poison", 1, 0)
	lens_state.call("_apply_status", 1, "scorch", 1, 0)
	_expect(int((lens_state.players[1].get("statuses", {}) as Dictionary).get("poison", 0)) == 2 and int((lens_state.players[1].get("statuses", {}) as Dictionary).get("scorch", 0)) == 1, "Element Lens must add exactly one stack to the first negative status it applies each turn.")

	var lost_path_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 201)
	lost_path_state.call("_equip", 0, "lost_path_new#001")
	var lost_path_health := int(lost_path_state.players[0].get("health", 0))
	lost_path_state.call("_deal_damage", 0, 2, "true", -1, false)
	_expect(int(lost_path_state.players[0].get("health", 0)) == lost_path_health, "Lost Path must prevent non-card damage.")
	lost_path_state.players[0]["hand"] = ["slash_new#001"]
	lost_path_state.players[0]["position"] = Vector2i(2, 2)
	lost_path_state.players[1]["position"] = Vector2i(3, 2)
	lost_path_state.players[1]["hand"] = []
	lost_path_state.players[1]["stamina"] = 1
	_expect(bool(lost_path_state.call("submit_command", _find_command(lost_path_state, MatchCommandScript.PLAY_CARD, "slash_new#001"))) and int(lost_path_state.players[1].get("health", 0)) < int(lost_path_state.players[1].get("max_health", 0)), "Lost Path must not prevent ordinary card damage.")

	var defensive_line_state: RefCounted = _state(["maddy", "q", "ginger", "signal"], 202)
	defensive_line_state.players[0]["hand"] = ["defensive_line_new#001", "slash_new#001"]
	defensive_line_state.players[0]["stamina"] = 2
	var original_rightmost: Dictionary = catalog.call("resolve_card", "slash_new#001") as Dictionary
	_expect(bool(defensive_line_state.call("submit_command", _find_command(defensive_line_state, MatchCommandScript.PLAY_CARD, "defensive_line_new#001"))), "Defensive Line must be playable.")
	var transformed: Dictionary = defensive_line_state.call("_card_definition_for_player", 0, "slash_new#001") as Dictionary
	_expect(String(transformed.get("card_id", "")) == "iron_body_new" and String(transformed.get("suit", "")) == String(original_rightmost.get("suit", "")) and int(transformed.get("rank", 0)) == int(original_rightmost.get("rank", 0)), "Defensive Line must permanently transform the rightmost physical card while preserving suit and rank.")
	var armor_before := int(defensive_line_state.players[0].get("armor", 0))
	_expect(bool(defensive_line_state.call("submit_command", _find_command(defensive_line_state, MatchCommandScript.PLAY_CARD, "slash_new#001"))) and int(defensive_line_state.players[0].get("armor", 0)) == armor_before + 1, "The transformed card must resolve as Iron Body.")

	var hunt_state: RefCounted = _state(["shya", "q", "ginger", "signal"], 203)
	hunt_state.players[0]["hand"] = ["hunt_new#001"]
	hunt_state.players[0]["position"] = Vector2i(2, 2)
	hunt_state.players[1]["position"] = Vector2i(3, 2)
	hunt_state.players[1]["last_action_direction"] = [1, 0]
	hunt_state.players[1]["hand"] = []
	var hunt_health := int(hunt_state.players[1].get("health", 0))
	_expect(bool(hunt_state.call("submit_command", _find_command(hunt_state, MatchCommandScript.PLAY_CARD, "hunt_new#001"))) and hunt_state.players[0].get("position", Vector2i.ZERO) == Vector2i(2, 2) and int(hunt_state.players[1].get("health", 0)) == hunt_health - 1, "Hunt must move directly behind a target's last action direction, then deal one damage.")

	var demolition_state: RefCounted = _state(["maddy", "q", "ginger", "signal"], 204)
	demolition_state.players[0]["hand"] = ["demolition_new#001"]
	demolition_state.players[0]["mana"] = 1
	var demolition_command: Dictionary = _find_command(demolition_state, MatchCommandScript.PLAY_CARD, "demolition_new#001")
	_expect(bool(demolition_state.call("submit_command", demolition_command)) and String(demolition_state.call("tile_kind", demolition_state.call("_payload_position", (demolition_command.get("payload", {}) as Dictionary).get("position", [])))) == "collapsed" and int(demolition_state.players[0].get("coins", 0)) == 1, "Demolition must permanently collapse a selected empty tile and grant one coin.")

	var thorn_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 205)
	thorn_state.call("_equip", 1, "thorn_armor_new#001")
	var thorn_source_health := int(thorn_state.players[0].get("health", 0))
	thorn_state.call("_deal_damage", 1, 2, "true", 0, false)
	_expect(int(thorn_state.players[0].get("health", 0)) == thorn_source_health - 1, "Thorn Armor must deal one ordinary damage back to a known source after actual damage.")

	var charm_state: RefCounted = _state(["shya", "q", "ginger", "signal"], 206)
	charm_state.call("_equip", 0, "shadow_charm_new#001")
	charm_state.call("_apply_status", 0, "hidden", 1, 0)
	var charm_health := int(charm_state.players[0].get("health", 0))
	charm_state.call("_deal_damage", 0, 2, "true", 1, false)
	_expect(int(charm_state.players[0].get("health", 0)) == charm_health, "Shadow Charm must prevent the first damage after becoming hidden.")
	charm_state.call("_deal_damage", 0, 1, "true", 1, false)
	_expect(int(charm_state.players[0].get("health", 0)) == charm_health - 1, "Shadow Charm must consume its hidden-damage prevention after one use.")

	var fallen_state: RefCounted = _state(["ginger", "q", "maddy", "signal"], 164)
	fallen_state.players[0]["hand"] = ["fallen_power_new#001", "slash_new#001", "slash_new#002"]
	fallen_state.players[0]["mana"] = 1
	fallen_state.players[0]["stamina"] = 2
	fallen_state.players[0]["position"] = Vector2i(2, 2)
	fallen_state.players[1]["position"] = Vector2i(3, 2)
	fallen_state.players[1]["hand"] = []
	var fallen_health := int(fallen_state.players[0].get("health", 0))
	_expect(bool(fallen_state.call("submit_command", _find_command(fallen_state, MatchCommandScript.PLAY_CARD, "fallen_power_new#001"))), "Fallen Power must be playable.")
	_expect(int(fallen_state.players[0].get("health", 0)) == fallen_health - 2, "Fallen Power must immediately cost two health.")
	var target_health := int(fallen_state.players[1].get("health", 0))
	_expect(bool(fallen_state.call("submit_command", _find_command(fallen_state, MatchCommandScript.PLAY_CARD, "slash_new#001"))), "The first Fallen Power boosted attack must resolve.")
	_expect(int(fallen_state.players[1].get("health", 0)) == target_health - 2, "Fallen Power must add one damage to the first attack.")
	fallen_state.players[0]["stamina"] = 1
	target_health = int(fallen_state.players[1].get("health", 0))
	_expect(bool(fallen_state.call("submit_command", _find_command(fallen_state, MatchCommandScript.PLAY_CARD, "slash_new#002"))), "The second Fallen Power boosted attack must resolve.")
	_expect(int(fallen_state.players[1].get("health", 0)) == target_health - 2 and int((fallen_state.players[0].get("modifiers", {}) as Dictionary).get("next_attack_damage_bonus", 0)) == 0, "Fallen Power must consume exactly two attack bonuses.")

	var assassination_state: RefCounted = _state(["shya", "q", "maddy", "signal"], 165)
	assassination_state.players[0]["hand"] = ["assassination_new#001", "slash_new#001"]
	assassination_state.players[0]["stamina"] = 4
	assassination_state.players[0]["position"] = Vector2i(2, 2)
	assassination_state.players[1]["position"] = Vector2i(3, 2)
	assassination_state.players[1]["hand"] = []
	_expect(bool(assassination_state.call("submit_command", _find_command(assassination_state, MatchCommandScript.PLAY_CARD, "assassination_new#001"))), "Assassination must resolve its damage and discount setup.")
	_expect(int((assassination_state.call("_effective_cost", 0, catalog.call("resolve_card", "slash_new#001") as Dictionary) as Dictionary).get("stamina", -1)) == 0, "Assassination must reduce the next attack stamina cost by one.")

	var hasten_state: RefCounted = _state(["shya", "q", "maddy", "signal"], 166)
	hasten_state.players[0]["hand"] = ["slash_new#001", "slash_new#002", "hasten_new#001"]
	hasten_state.players[0]["stamina"] = 2
	hasten_state.players[0]["mana"] = 1
	hasten_state.players[0]["position"] = Vector2i(2, 2)
	hasten_state.players[1]["position"] = Vector2i(3, 2)
	hasten_state.players[1]["hand"] = []
	hasten_state.players[0]["common_deck"] = []
	hasten_state.players[0]["profession_deck"] = ["ghost_step_new#003", "ghost_step_new#002", "ghost_step_new#001"]
	_expect(bool(hasten_state.call("submit_command", _find_command(hasten_state, MatchCommandScript.PLAY_CARD, "slash_new#001"))) and bool(hasten_state.call("submit_command", _find_command(hasten_state, MatchCommandScript.PLAY_CARD, "slash_new#002"))), "Hasten setup must record two previous attacks.")
	_expect(bool(hasten_state.call("submit_command", _find_command(hasten_state, MatchCommandScript.PLAY_CARD, "hasten_new#001"))), "Hasten must play after two attacks.")
	_expect((hasten_state.players[0].get("hand", []) as Array).size() == 3, "Hasten must draw three cards when two attacks were already used this turn.")

	var fortify_state: RefCounted = _state(["maddy", "q", "ginger", "signal"], 167)
	fortify_state.players[0]["hand"] = ["fortify_new#001"]
	fortify_state.players[0]["stamina"] = 2
	fortify_state.players[0]["mana"] = 2
	fortify_state.players[0]["armor"] = 3
	_expect(bool(fortify_state.call("submit_command", _find_command(fortify_state, MatchCommandScript.PLAY_CARD, "fortify_new#001"))) and int(fortify_state.players[0].get("armor", 0)) == 6, "Fortify must double armor beyond the ordinary cap.")

	var wall_state: RefCounted = _state(["maddy", "q", "ginger", "signal"], 168)
	wall_state.players[0]["hand"] = ["iron_wall_new#001"]
	wall_state.players[0]["stamina"] = 1
	wall_state.players[0]["armor"] = 1
	wall_state.players[0]["common_deck"] = []
	wall_state.players[0]["profession_deck"] = ["ghost_step_new#001"]
	_expect(bool(wall_state.call("submit_command", _find_command(wall_state, MatchCommandScript.PLAY_CARD, "iron_wall_new#001"))) and int(wall_state.players[0].get("armor", 0)) == 3 and (wall_state.players[0].get("hand", []) as Array).has("ghost_step_new#001"), "Iron Wall must check armor before use, then gain one extra armor and draw one card.")

	var wings_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 170)
	wings_state.call("_equip", 0, "hermes_wings_new#001")
	_expect(int(wings_state.call("_move_range", 0)) == 3, "Hermes Wings must replace free movement with a 7x7, three-step orthogonal path instead of increasing it to 9x9.")

	var mountain_state: RefCounted = _state(["maddy", "q", "ginger", "signal"], 171)
	mountain_state.players[0]["hand"] = ["mountain_still_new#001"]
	mountain_state.players[0]["mana"] = 2
	mountain_state.players[0]["position"] = Vector2i(7, 7)
	mountain_state.players[1]["position"] = Vector2i(8, 7)
	_expect(bool(mountain_state.call("submit_command", _find_command(mountain_state, MatchCommandScript.PLAY_CARD, "mountain_still_new#001"))), "Mountain Still must grant armor and the current-round movement immunity.")
	var mountain_position: Vector2i = mountain_state.players[0].get("position", Vector2i.ZERO) as Vector2i
	mountain_state.call("_push_target", 1, 0, 1)
	_expect((mountain_state.players[0].get("position", Vector2i.ZERO) as Vector2i) == mountain_position, "Mountain Still must prevent card-driven movement during the current round.")

	var rapier_state: RefCounted = _state(["ginger", "q", "maddy", "signal"], 172)
	rapier_state.players[0]["hand"] = ["slash_new#001", "slash_new#002"]
	rapier_state.players[0]["stamina"] = 2
	rapier_state.players[0]["position"] = Vector2i(2, 2)
	rapier_state.players[1]["position"] = Vector2i(3, 2)
	rapier_state.players[1]["hand"] = []
	rapier_state.call("_equip", 0, "rapier_new#001")
	rapier_state.call("_handle_move", {"path": [[2, 3]]})
	var rapier_target_health := int(rapier_state.players[1].get("health", 0))
	_expect(bool(rapier_state.call("submit_command", _find_command(rapier_state, MatchCommandScript.PLAY_CARD, "slash_new#001"))) and int(rapier_state.players[1].get("health", 0)) == rapier_target_health - 2, "Rapier must add one damage to the first attack after movement.")
	rapier_state.players[0]["stamina"] = 1
	rapier_target_health = int(rapier_state.players[1].get("health", 0))
	_expect(bool(rapier_state.call("submit_command", _find_command(rapier_state, MatchCommandScript.PLAY_CARD, "slash_new#002"))) and int(rapier_state.players[1].get("health", 0)) == rapier_target_health - 1, "Rapier must not add damage to later attacks in the same turn.")

	var lance_state: RefCounted = _state(["ginger", "q", "maddy", "signal"], 173)
	lance_state.players[0]["hand"] = ["slash_new#001"]
	lance_state.players[0]["stamina"] = 1
	lance_state.players[0]["position"] = Vector2i(2, 2)
	lance_state.players[1]["position"] = Vector2i(3, 2)
	lance_state.players[2]["position"] = Vector2i(5, 2)
	lance_state.players[1]["hand"] = []
	lance_state.players[2]["hand"] = []
	lance_state.call("_equip", 0, "piercing_lance_new#001")
	var lance_targets: Array[int] = []
	for command: Dictionary in lance_state.call("legal_commands", 0) as Array[Dictionary]:
		if String(command.get("type", "")) == MatchCommandScript.PLAY_CARD and String((command.get("payload", {}) as Dictionary).get("card_id", "")) == "slash_new#001":
			lance_targets.append(int((command.get("payload", {}) as Dictionary).get("target_id", -1)))
	_expect(lance_targets.has(2), "Piercing Lance must allow an attack to target a character behind another character.")

	var sulfur_state: RefCounted = _state(["ginger", "q", "maddy", "signal"], 174)
	sulfur_state.players[0]["hand"] = ["slash_new#001"]
	sulfur_state.players[0]["stamina"] = 1
	sulfur_state.players[0]["position"] = Vector2i(2, 2)
	sulfur_state.players[1]["position"] = Vector2i(2, 10)
	sulfur_state.players[2]["position"] = Vector2i(4, 4)
	sulfur_state.call("_equip", 0, "sulfur_fire_new#001")
	var sulfur_targets: Array[int] = []
	for command: Dictionary in sulfur_state.call("legal_commands", 0) as Array[Dictionary]:
		if String(command.get("type", "")) == MatchCommandScript.PLAY_CARD and String((command.get("payload", {}) as Dictionary).get("card_id", "")) == "slash_new#001":
			sulfur_targets.append(int((command.get("payload", {}) as Dictionary).get("target_id", -1)))
	_expect(sulfur_targets.has(1) and not sulfur_targets.has(2), "Sulfur Fire must target unlimited same-row or same-column enemies only.")
	var sulfur_preview: Dictionary = sulfur_state.call("targeting_preview", 0, MatchCommandScript.PLAY_CARD, "slash_new#001") as Dictionary
	_expect((sulfur_preview.get("legal_target_ids", []) as Array).has(1) and not (sulfur_preview.get("legal_target_ids", []) as Array).has(2), "Sulfur Fire targeting preview must match its straight-line legal targets.")

	var sniper_state: RefCounted = _state(["signal", "q", "ginger", "maddy"], 175)
	sniper_state.players[0]["hand"] = ["sniper_new#001"]
	sniper_state.players[0]["profession"] = "shooter"
	sniper_state.players[0]["stamina"] = 2
	sniper_state.players[0]["position"] = Vector2i(2, 2)
	sniper_state.players[1]["position"] = Vector2i(5, 2)
	sniper_state.players[1]["hand"] = ["heavenly_sense_new#001"]
	var sniper_health := int(sniper_state.players[1].get("health", 0))
	_expect(bool(sniper_state.call("submit_command", _find_command(sniper_state, MatchCommandScript.PLAY_CARD, "sniper_new#001"))), "Sniper must fire at its actual maximum attack distance.")
	_expect((sniper_state.get("pending_action") as Dictionary).is_empty() and int(sniper_state.players[1].get("health", 0)) == sniper_health - 3, "Sniper must be unanswerable and add one damage at the actual range boundary.")

	var rapid_fire_state: RefCounted = _state(["signal", "q", "ginger", "maddy"], 176)
	rapid_fire_state.players[0]["hand"] = ["slash_new#001", "rapid_fire_new#001"]
	rapid_fire_state.players[0]["stamina"] = 1
	rapid_fire_state.players[0]["position"] = Vector2i(2, 2)
	rapid_fire_state.players[1]["position"] = Vector2i(3, 2)
	rapid_fire_state.players[1]["hand"] = ["heavenly_sense_new#001"]
	_expect(bool(rapid_fire_state.call("submit_command", _find_command(rapid_fire_state, MatchCommandScript.PLAY_CARD, "slash_new#001"))), "Rapid Fire setup attack must open its response window.")
	_expect(bool(rapid_fire_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.RESPOND, 1, {"card_id": "heavenly_sense_new#001"}))), "The setup attack must be cancelable for Rapid Fire's previous-card rule.")
	var rapid_target_health := int(rapid_fire_state.players[1].get("health", 0))
	_expect(bool(rapid_fire_state.call("submit_command", _find_command(rapid_fire_state, MatchCommandScript.PLAY_CARD, "rapid_fire_new#001"))), "Rapid Fire must be playable at zero stamina when the canceled previous card was an attack.")
	_expect(int(rapid_fire_state.players[0].get("stamina", -1)) == 0 and int(rapid_fire_state.players[1].get("health", 0)) == rapid_target_health - 1, "Rapid Fire must spend no stamina and still deal its normal damage after a canceled attack.")

	var aim_state: RefCounted = _state(["signal", "q", "ginger", "maddy"], 177)
	aim_state.players[0]["hand"] = ["aim_new#001", "slash_new#001"]
	aim_state.players[0]["mana"] = 1
	aim_state.players[0]["stamina"] = 1
	aim_state.players[0]["position"] = Vector2i(2, 2)
	aim_state.players[1]["position"] = Vector2i(3, 2)
	aim_state.players[1]["hand"] = ["heavenly_sense_new#001"]
	_expect(bool(aim_state.call("submit_command", _find_command(aim_state, MatchCommandScript.PLAY_CARD, "aim_new#001"))), "Aim must arm the next attack response lock.")
	var aim_target_health := int(aim_state.players[1].get("health", 0))
	_expect(bool(aim_state.call("submit_command", _find_command(aim_state, MatchCommandScript.PLAY_CARD, "slash_new#001"))), "The attack after Aim must be playable.")
	_expect((aim_state.get("pending_action") as Dictionary).is_empty() and int(aim_state.players[1].get("health", 0)) == aim_target_health - 1 and not bool((aim_state.players[0].get("flags", {}) as Dictionary).get("next_attack_unanswerable", false)), "Aim must make exactly the next attack unanswerable and then consume its mark.")

	var overdraft_state: RefCounted = _state(["ginger", "q", "maddy", "signal"], 178)
	overdraft_state.players[0]["hand"] = ["overdraft_new#001", "slash_new#001"]
	overdraft_state.players[0]["health"] = 1
	overdraft_state.players[0]["max_health"] = 8
	overdraft_state.players[0]["common_deck"] = ["slash_new#003", "slash_new#002"]
	overdraft_state.players[0]["profession_deck"] = []
	_expect(bool(overdraft_state.call("submit_command", _find_command(overdraft_state, MatchCommandScript.PLAY_CARD, "overdraft_new#001"))), "Overdraft must be playable with fewer than two discardable cards.")
	var overdraft_request: Dictionary = overdraft_state.get("pending_discard") as Dictionary
	_expect(int(overdraft_request.get("required_count", 0)) == 1, "Overdraft must request every available hand card when fewer than two are available.")
	_expect(bool(overdraft_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.DISCARD_CARDS, 0, {"request_id": String(overdraft_request.get("request_id", "")), "card_ids": ["slash_new#001"]}))), "Overdraft's partial discard must resume its remaining effects.")
	_expect(int(overdraft_state.players[0].get("health", 0)) == 3 and (overdraft_state.players[0].get("hand", []) as Array).size() == 2, "Overdraft must heal before checking post-resolution half health and draw two when still below half.")

	var armament_state: RefCounted = _state(["maddy", "q", "ginger", "signal"], 179)
	armament_state.players[0]["hand"] = ["armament_new#001", "slash_new#001"]
	armament_state.players[0]["stamina"] = 1
	var armament_preview: Dictionary = armament_state.call("targeting_preview", 0, MatchCommandScript.PLAY_CARD, "armament_new#001") as Dictionary
	_expect((armament_preview.get("legal_target_ids", []) as Array).has(0), "Armament must permit selecting its user as the armor recipient.")
	_expect(bool(armament_state.call("submit_command", _find_command(armament_state, MatchCommandScript.PLAY_CARD, "armament_new#001"))), "Armament must be playable when another hand card can be discarded.")
	var armament_request: Dictionary = armament_state.get("pending_discard") as Dictionary
	_expect(bool(armament_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.DISCARD_CARDS, 0, {"request_id": String(armament_request.get("request_id", "")), "card_ids": ["slash_new#001"]}))) and int(armament_state.players[0].get("armor", 0)) == 1, "Armament must discard the selected second card before granting its target armor.")
	var armament_empty_state: RefCounted = _state(["maddy", "q", "ginger", "signal"], 180)
	armament_empty_state.players[0]["hand"] = ["armament_new#001"]
	armament_empty_state.players[0]["stamina"] = 1
	_expect(_find_command(armament_empty_state, MatchCommandScript.PLAY_CARD, "armament_new#001").is_empty(), "Armament must be unavailable without a second hand card to discard.")

	var close_shot_state: RefCounted = _state(["signal", "q", "ginger", "maddy"], 181)
	close_shot_state.players[0]["hand"] = ["close_shot_new#001"]
	close_shot_state.players[0]["stamina"] = 1
	close_shot_state.players[0]["position"] = Vector2i(2, 2)
	close_shot_state.players[1]["position"] = Vector2i(3, 3)
	close_shot_state.players[1]["hand"] = ["heavenly_sense_new#001"]
	var close_health := int(close_shot_state.players[1].get("health", 0))
	_expect(bool(close_shot_state.call("submit_command", _find_command(close_shot_state, MatchCommandScript.PLAY_CARD, "close_shot_new#001"))), "Close Shot must be playable against a target inside its 3x3 range.")
	_expect((close_shot_state.get("pending_action") as Dictionary).is_empty() and int(close_shot_state.players[1].get("health", 0)) == close_health - 3, "Close Shot must add two damage and prevent responses inside its 3x3 range.")

	var assassinate_state: RefCounted = _state(["shya", "q", "ginger", "maddy"], 182)
	assassinate_state.players[0]["hand"] = ["assassinate_new#001", "assassinate_new#002"]
	assassinate_state.players[0]["stamina"] = 2
	assassinate_state.players[0]["position"] = Vector2i(2, 2)
	assassinate_state.players[1]["position"] = Vector2i(3, 2)
	assassinate_state.players[1]["hand"] = []
	var assassinate_health := int(assassinate_state.players[1].get("health", 0))
	_expect(bool(assassinate_state.call("submit_command", _find_command(assassinate_state, MatchCommandScript.PLAY_CARD, "assassinate_new#001"))) and int(assassinate_state.players[1].get("health", 0)) == assassinate_health - 3, "Assassinate must add two damage on the target's first actual damage in a complete round.")
	assassinate_state.players[0]["stamina"] = 1
	assassinate_state.players[0]["flash"] = 0
	var assassinate_flags: Dictionary = assassinate_state.players[0].get("flags", {}) as Dictionary
	assassinate_flags.erase("flash_attack_used")
	assassinate_state.players[0]["flags"] = assassinate_flags
	assassinate_health = int(assassinate_state.players[1].get("health", 0))
	var second_assassinate := _find_command(assassinate_state, MatchCommandScript.PLAY_CARD, "assassinate_new#002")
	var second_assassinate_ok := bool(assassinate_state.call("submit_command", second_assassinate))
	_expect(second_assassinate_ok and int(assassinate_state.players[1].get("health", 0)) == assassinate_health - 1, "Assassinate must deal only base damage after the target was already hurt this complete round.")

	var thunderstorm_state: RefCounted = _state(["zc", "ginger", "maddy", "signal"], 183)
	thunderstorm_state.players[0]["profession"] = "arcanist"
	thunderstorm_state.players[0]["hand"] = ["thunderstorm_new#001"]
	thunderstorm_state.players[0]["stamina"] = 1
	thunderstorm_state.players[0]["mana"] = 2
	thunderstorm_state.players[0]["position"] = Vector2i(7, 7)
	thunderstorm_state.players[1]["position"] = Vector2i(6, 6)
	thunderstorm_state.players[2]["position"] = Vector2i(5, 5)
	thunderstorm_state.players[3]["position"] = Vector2i(9, 9)
	thunderstorm_state.players[1]["hand"] = ["heavenly_sense_new#001"]
	var thunderstorm_health := int(thunderstorm_state.players[1].get("health", 0))
	_expect(bool(thunderstorm_state.call("submit_command", _find_command(thunderstorm_state, MatchCommandScript.PLAY_CARD, "thunderstorm_new#001"))), "Thunderstorm must open a quadrant selection after being played.")
	var thunderstorm_choice: Dictionary = thunderstorm_state.get("pending_skill_choice") as Dictionary
	_expect(bool(thunderstorm_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(thunderstorm_choice.get("request_id", "")), "value": "northwest"}))) and (thunderstorm_state.get("pending_action") as Dictionary).is_empty() and int(thunderstorm_state.players[1].get("health", 0)) == thunderstorm_health - 2 and int((thunderstorm_state.players[1].get("statuses", {}) as Dictionary).get("paralyze", 0)) == 1 and int(thunderstorm_state.players[2].get("health", 0)) < int(thunderstorm_state.players[2].get("max_health", 0)) and int(thunderstorm_state.players[3].get("health", 0)) == int(thunderstorm_state.players[3].get("max_health", 0)), "Thunderstorm must resolve only the selected 2x2 quadrant without a response window.")

	var dragon_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 184)
	dragon_state.players[0]["profession"] = "arcanist"
	dragon_state.players[0]["hand"] = ["dragon_breath_new#001"]
	dragon_state.players[0]["stamina"] = 2
	dragon_state.players[0]["mana"] = 1
	dragon_state.players[0]["position"] = Vector2i(7, 7)
	dragon_state.players[1]["position"] = Vector2i(12, 7)
	dragon_state.players[2]["position"] = Vector2i(7, 3)
	dragon_state.players[3]["position"] = Vector2i(9, 9)
	var dragon_health := int(dragon_state.players[1].get("health", 0))
	_expect(bool(dragon_state.call("submit_command", _find_command(dragon_state, MatchCommandScript.PLAY_CARD, "dragon_breath_new#001"))), "Dragon Breath must open a row-or-column selection after being played.")
	var dragon_choice: Dictionary = dragon_state.get("pending_skill_choice") as Dictionary
	_expect(bool(dragon_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(dragon_choice.get("request_id", "")), "value": "row"}))) and int(dragon_state.players[1].get("health", 0)) == dragon_health - 2 and int((dragon_state.players[1].get("statuses", {}) as Dictionary).get("scorch", 0)) == 1 and int(dragon_state.players[2].get("health", 0)) == int(dragon_state.players[2].get("max_health", 0)), "Dragon Breath must damage only the chosen unlimited row or column and exclude its user.")

	var momentum_state: RefCounted = _state(["maddy", "q", "ginger", "signal"], 185)
	momentum_state.players[0]["hand"] = ["momentum_new#001"]
	momentum_state.players[0]["mana"] = 1
	momentum_state.players[0]["position"] = Vector2i(2, 2)
	momentum_state.players[1]["position"] = Vector2i(5, 5)
	momentum_state.players[2]["position"] = Vector2i(8, 5)
	var momentum_command: Dictionary = {}
	for command: Dictionary in momentum_state.call("legal_commands", 0) as Array[Dictionary]:
		var payload: Dictionary = command.get("payload", {}) as Dictionary
		if String(command.get("type", "")) == MatchCommandScript.PLAY_CARD and String(payload.get("card_id", "")) == "momentum_new#001" and int(payload.get("target_id", -1)) == 1:
			momentum_command = command
			break
	_expect(bool(momentum_state.call("submit_command", momentum_command)), "Momentum must open a direction choice after selecting a target.")
	var momentum_choice: Dictionary = momentum_state.get("pending_skill_choice") as Dictionary
	var momentum_ok := bool(momentum_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(momentum_choice.get("request_id", "")), "value": "right"})))
	_expect(momentum_ok and (momentum_state.players[1].get("position", Vector2i.ZERO) as Vector2i) == Vector2i(7, 5), "Momentum must move its target up to two orthogonal cells in the selected direction.")

	var repel_state: RefCounted = _state(["maddy", "q", "ginger", "signal"], 186)
	repel_state.players[0]["hand"] = ["hand_repel_new#001"]
	repel_state.players[0]["stamina"] = 1
	repel_state.players[0]["position"] = Vector2i(4, 4)
	repel_state.players[1]["position"] = Vector2i(5, 4)
	repel_state.players[1]["hand"] = []
	_expect(bool(repel_state.call("submit_command", _find_command(repel_state, MatchCommandScript.PLAY_CARD, "hand_repel_new#001"))) and (repel_state.players[0].get("position", Vector2i.ZERO) as Vector2i) == Vector2i(3, 4) and (repel_state.players[1].get("position", Vector2i.ZERO) as Vector2i) == Vector2i(7, 4), "Hand Repel must push the target two cells away and its user one cell back along their line.")

	var precision_state: RefCounted = _state(["shya", "q", "ginger", "maddy"], 187)
	precision_state.players[0]["hand"] = ["precision_stab_new#001"]
	precision_state.players[0]["stamina"] = 2
	precision_state.players[0]["position"] = Vector2i(2, 2)
	precision_state.players[1]["position"] = Vector2i(5, 2)
	precision_state.players[1]["hand"] = []
	_expect(bool(precision_state.call("submit_command", _find_command(precision_state, MatchCommandScript.PLAY_CARD, "precision_stab_new#001"))), "Precision Stab must open its movement direction selection.")
	var precision_direction: Dictionary = precision_state.get("pending_skill_choice") as Dictionary
	_expect(bool(precision_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(precision_direction.get("request_id", "")), "value": "right"}))), "Precision Stab must resolve its selected movement.")
	var precision_target: Dictionary = precision_state.get("pending_skill_choice") as Dictionary
	var precision_health := int(precision_state.players[1].get("health", 0))
	_expect(bool(precision_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(precision_target.get("request_id", "")), "value": 1}))) and (precision_state.players[0].get("position", Vector2i.ZERO) as Vector2i) == Vector2i(4, 2) and int(precision_state.players[1].get("health", 0)) == precision_health - 2, "Precision Stab must select its target after moving and deal two piercing damage.")

	var slam_state: RefCounted = _state(["maddy", "q", "ginger", "signal"], 188)
	slam_state.players[0]["hand"] = ["body_slam_new#001"]
	slam_state.players[0]["stamina"] = 2
	slam_state.players[0]["armor"] = 3
	slam_state.players[0]["position"] = Vector2i(2, 2)
	slam_state.players[1]["position"] = Vector2i(5, 2)
	slam_state.players[1]["hand"] = []
	_expect(bool(slam_state.call("submit_command", _find_command(slam_state, MatchCommandScript.PLAY_CARD, "body_slam_new#001"))), "Body Slam must open its movement direction selection.")
	var slam_direction: Dictionary = slam_state.get("pending_skill_choice") as Dictionary
	slam_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(slam_direction.get("request_id", "")), "value": "right"}))
	var slam_target: Dictionary = slam_state.get("pending_skill_choice") as Dictionary
	var slam_health := int(slam_state.players[1].get("health", 0))
	_expect(bool(slam_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(slam_target.get("request_id", "")), "value": 1}))) and int(slam_state.players[1].get("health", 0)) == slam_health - 3, "Body Slam must deal damage equal to armor after completing its movement selection.")

	var blood_river_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 169)
	blood_river_state.players[0]["hand"] = ["blood_river_new#001"]
	blood_river_state.players[0]["mana"] = 2
	blood_river_state.players[0]["position"] = Vector2i(7, 7)
	blood_river_state.players[1]["position"] = Vector2i(8, 8)
	blood_river_state.players[2]["position"] = Vector2i(6, 7)
	blood_river_state.players[3]["position"] = Vector2i(9, 7)
	_expect(bool(blood_river_state.call("submit_command", _find_command(blood_river_state, MatchCommandScript.PLAY_CARD, "blood_river_new#001"))), "Blood River must resolve as a centered area card.")
	_expect(int(((blood_river_state.players[1].get("statuses", {}) as Dictionary).get("bleed", 0))) == 2 and int(((blood_river_state.players[2].get("statuses", {}) as Dictionary).get("bleed", 0))) == 2 and int(((blood_river_state.players[3].get("statuses", {}) as Dictionary).get("bleed", 0))) == 0, "Blood River must apply two bleed stacks to other characters only inside its 3x3 area.")


func _test_response_window_resources() -> void:
	var state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 102)
	var source: Dictionary = state.call("player", 0) as Dictionary
	var target: Dictionary = state.call("player", 1) as Dictionary
	source["position"] = Vector2i(2, 2)
	target["position"] = Vector2i(3, 2)
	(source.get("hand", []) as Array).append("slash_new#001")
	(target.get("hand", []) as Array).append("heavenly_sense_new#001")
	(target.get("hand", []) as Array).append("iron_body_new#001")
	state.players[0] = source
	state.players[1] = target
	var attack: Dictionary = _find_command(state, MatchCommandScript.PLAY_CARD, "slash_new#001")
	_expect(bool(state.call("submit_command", attack)), "Attack should open a response window.")
	var legal: Array[Dictionary] = state.call("legal_commands", 1) as Array[Dictionary]
	var response_ids: Array[String] = []
	for command: Dictionary in legal:
		var card_id: String = String((command.get("payload", {}) as Dictionary).get("card_id", ""))
		if not card_id.is_empty():
			response_ids.append(card_id)
	_expect(response_ids == ["heavenly_sense_new#001"], "Off-turn zero resources must leave only revised Heavenly Sense for attacks.")


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


func _test_no_action_points_and_round_pressure() -> void:
	var state: RefCounted = _state(["k", "ginger", "maddy", "signal"], 105)
	var active: Dictionary = state.call("player", 0) as Dictionary
	active["coins"] = 10
	state.players[0] = active
	state.call("set_market_for_testing", ["slash"] as Array[String])
	var command: Dictionary = {}
	for candidate: Dictionary in state.call("legal_commands", 0) as Array[Dictionary]:
		if String(candidate.get("type", "")) == MatchCommandScript.BUY:
			command = candidate
			break
	_expect(not command.is_empty(), "A market purchase must be legal without action points.")
	if not command.is_empty():
		_expect(bool(state.call("submit_command", command)), "Market purchase should resolve without action points.")
		_expect(bool((state.call("player", 0) as Dictionary).get("market_bought", false)), "The market must retain its independent once-per-turn purchase limit.")
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
	_expect(int(preview.get("range", 0)) == 2, "Q's arcanist profession must give attacks a 5x5 range.")
	var staged_preview: Dictionary = state.call("targeting_preview", 0, MatchCommandScript.PLAY_CARD, "slash_new#001") as Dictionary
	_expect(int(staged_preview.get("range", 0)) == 2 and not staged_preview.get("cells", []).is_empty(), "Targeting preview must resolve staged card instances with profession range.")
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


func _test_na1_purchased_card_bonuses() -> void:
	var attack_state: RefCounted = _state(["na1", "q", "ginger", "signal"], 209)
	attack_state.players[0]["hand"] = []
	attack_state.players[0]["purchased_hand"] = ["slash_new#001"]
	attack_state.players[0]["position"] = Vector2i(2, 2)
	attack_state.players[1]["position"] = Vector2i(3, 2)
	attack_state.players[1]["hand"] = []
	var health_before := int(attack_state.players[1].get("health", 0))
	_expect(bool(attack_state.call("submit_command", _find_command(attack_state, MatchCommandScript.PLAY_CARD, "slash_new#001"))), "Na1 must be able to play a purchased attack card.")
	_expect(int(attack_state.players[1].get("health", 0)) == health_before - 2, "Na1 Foresight must resolve a purchased attack card twice.")

	var defense_state: RefCounted = _state(["na1", "q", "ginger", "signal"], 210)
	defense_state.players[0]["hand"] = []
	defense_state.players[0]["purchased_hand"] = ["iron_body_new#001"]
	defense_state.players[0]["common_deck"] = ["slash_new#002", "slash_new#003"]
	defense_state.players[0]["profession_deck"] = []
	defense_state.players[0]["stamina"] = 2
	_expect(bool(defense_state.call("submit_command", _find_command(defense_state, MatchCommandScript.PLAY_CARD, "iron_body_new#001"))), "Na1 must be able to play a purchased defense card.")
	_expect((defense_state.players[0].get("hand", []) as Array).size() == 2, "Na1 Foresight must draw two after a purchased defense card resolves.")

	var strange_state: RefCounted = _state(["na1", "q", "ginger", "signal"], 211)
	strange_state.players[0]["hand"] = []
	strange_state.players[0]["purchased_hand"] = ["soul_drain_new#001"]
	strange_state.players[0]["mana"] = 2
	strange_state.players[0]["position"] = Vector2i(2, 2)
	for target_id: int in [1, 2, 3]:
		strange_state.players[target_id]["position"] = Vector2i(2 + target_id, 2)
		strange_state.players[target_id]["hand"] = ["slash_new#00%d" % (target_id + 1)]
	_expect(bool(strange_state.call("submit_command", _find_command(strange_state, MatchCommandScript.PLAY_CARD, "soul_drain_new#001"))), "Na1 must be able to play a purchased targeted strange card.")
	var extra_request: Dictionary = strange_state.get("pending_skill_choice") as Dictionary
	_expect(String(extra_request.get("kind", "")) == "na1_foresight_extra_target", "Na1 Foresight must request an additional target after the first purchased strange target resolves.")
	_expect(bool(strange_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(extra_request.get("request_id", "")), "value": 2}))), "Na1 must be able to select a second strange-card target.")
	_expect((strange_state.players[0].get("hand", []) as Array).size() >= 2, "Na1 Foresight must resolve the strange card for an additional selected target.")


func _test_thunderstorm_skill_discard() -> void:
	var state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 109)
	var q: Dictionary = state.call("player", 0) as Dictionary
	var enemy: Dictionary = state.call("player", 1) as Dictionary
	q["hand"] = ["rally_new#003", "crossfire_new#003"]
	q["position"] = Vector2i(2, 2)
	enemy["position"] = Vector2i(3, 2)
	state.players[0] = q
	state.players[1] = enemy
	var q_skill_ids: Array[String] = []
	for legal_command: Dictionary in state.call("legal_commands", 0) as Array[Dictionary]:
		if String(legal_command.get("type", "")) == MatchCommandScript.USE_SKILL:
			q_skill_ids.append(String((legal_command.get("payload", {}) as Dictionary).get("skill_id", "")))
	_expect(q_skill_ids == ["q_thunderstorm"], "Q must expose exactly one revised Thunderstorm command and no active Thunder Guard command.")
	var thunderstorm := _find_command(state, MatchCommandScript.USE_SKILL, "q_thunderstorm")
	_expect(not thunderstorm.is_empty(), "Q must expose Thunderstorm as a legal staged skill.")
	if thunderstorm.is_empty():
		return
	_expect(bool(state.call("submit_command", thunderstorm)), "Thunderstorm should open a discard request.")
	var request: Dictionary = state.get("pending_skill_discard") as Dictionary
	_expect(int(request.get("required_rank_sum", 0)) == 23, "Thunderstorm discard request must require rank sum 23.")
	var invalid := MatchCommandScript.make(MatchCommandScript.SKILL_DISCARD, 0, {"request_id": request.get("request_id", ""), "card_ids": ["rally_new#003"]})
	_expect(not bool(state.call("submit_command", invalid)), "Thunderstorm must reject an incorrect rank sum.")
	var replay_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 109)
	var replay_q: Dictionary = replay_state.call("player", 0) as Dictionary
	replay_q["hand"] = ["rally_new#003", "crossfire_new#003"]
	replay_q["position"] = Vector2i(2, 2)
	replay_state.players[0] = replay_q
	var replay_enemy: Dictionary = replay_state.call("player", 1) as Dictionary
	replay_enemy["position"] = Vector2i(3, 2)
	replay_state.players[1] = replay_enemy
	var replay_skill := _find_command(replay_state, MatchCommandScript.USE_SKILL, "q_thunderstorm")
	replay_state.call("submit_command", replay_skill)
	var pending_a: Dictionary = (state.call("deterministic_snapshot") as Dictionary).get("pending_skill_discard", {}) as Dictionary
	var pending_b: Dictionary = (replay_state.call("deterministic_snapshot") as Dictionary).get("pending_skill_discard", {}) as Dictionary
	_expect(int(pending_a.get("player_id", -1)) == int(pending_b.get("player_id", -1)) and String(pending_a.get("skill_id", "")) == String(pending_b.get("skill_id", "")) and int(pending_a.get("required_rank_sum", 0)) == int(pending_b.get("required_rank_sum", 0)) and int(pending_a.get("target_id", -2)) == int(pending_b.get("target_id", -2)), "Same seed and command must produce identical skill discard requests: %s vs %s error=%s command=%s" % [JSON.stringify(pending_a), JSON.stringify(pending_b), String(replay_state.get("last_error")), JSON.stringify(replay_skill)])
	var valid := MatchCommandScript.make(MatchCommandScript.SKILL_DISCARD, 0, {"request_id": request.get("request_id", ""), "card_ids": ["rally_new#003", "crossfire_new#003"]})
	_expect(bool(state.call("submit_command", valid)), "Thunderstorm should resolve after a valid rank-sum discard: %s" % String(state.get("last_error")))
	_expect((state.get("pending_skill_discard") as Dictionary).is_empty(), "Skill discard request must clear after payment.")
	var enemy_after: Dictionary = state.call("player", 1) as Dictionary
	_expect(int(enemy_after.get("health", 0)) < int(enemy_after.get("max_health", 0)) and int((enemy_after.get("statuses", {}) as Dictionary).get("paralyze", 0)) > 0, "Thunderstorm must damage and paralyze enemies in its area.")
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


func _test_revised_decks_and_equipment_installation() -> void:
	var state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 112)
	for player_id: int in 4:
		var player_state: Dictionary = state.call("player", player_id) as Dictionary
		for zone_name: String in ["hand", "common_deck", "profession_deck"]:
			for card_value: Variant in player_state.get(zone_name, []) as Array:
				var instance_id := String(card_value)
				_expect(instance_id.contains("#") and String(catalog.call("logical_card_id", instance_id)).ends_with("_new"), "%s must contain revised card instances only." % zone_name)
	for market_value: Variant in state.get("market") as Array:
		var market_id := String(market_value)
		_expect(String(catalog.call("logical_card_id", market_id)).ends_with("_new"), "Market must contain revised card instances only.")

	var same_seed: RefCounted = _state(["q", "ginger", "maddy", "signal"], 112)
	var other_seed: RefCounted = _state(["q", "ginger", "maddy", "signal"], 113)
	var common_deck: Array = (state.call("player", 0) as Dictionary).get("common_deck", []) as Array
	var same_deck: Array = (same_seed.call("player", 0) as Dictionary).get("common_deck", []) as Array
	var other_deck: Array = (other_seed.call("player", 0) as Dictionary).get("common_deck", []) as Array
	_expect(common_deck == same_deck, "The same match seed must reproduce the revised deck order.")
	_expect(common_deck != other_deck, "Different match seeds must produce different revised deck orders.")
	var logical_names: Dictionary = {}
	var transitions := 0
	var previous_name := ""
	for card_value: Variant in common_deck:
		var logical_name := String(catalog.call("logical_card_id", String(card_value)))
		logical_names[logical_name] = true
		if not previous_name.is_empty() and logical_name != previous_name:
			transitions += 1
		previous_name = logical_name
	_expect(transitions > logical_names.size(), "The shuffled deck must interleave names instead of exhausting one name group at a time.")

	var q: Dictionary = state.call("player", 0) as Dictionary
	q["hand"] = ["crowbar_new#001"]
	q["purchased_hand"] = []
	q["stamina"] = 0
	q["mana"] = 0
	state.players[0] = q
	var equip_command := _find_command(state, MatchCommandScript.PLAY_CARD, "crowbar_new#001")
	_expect(not equip_command.is_empty() and bool(state.call("submit_command", equip_command)), "A weapon must be playable at zero stamina and mana.")
	var equipped_q: Dictionary = state.call("player", 0) as Dictionary
	_expect(not (equipped_q.get("hand", []) as Array).has("crowbar_new#001"), "Playing equipment must consume that exact card instance from hand.")
	_expect(String((equipped_q.get("equipment", {}) as Dictionary).get("weapon", "")) == "crowbar_new#001", "The consumed equipment card instance must move into its equipment slot.")
	var durability: Dictionary = (equipped_q.get("equipment_durability", {}) as Dictionary).get("weapon", {}) as Dictionary
	_expect(int(durability.get("current", 0)) == 6 and int(durability.get("maximum", 0)) == 6, "Equipping must initialize the weapon's documented durability.")
	_expect(int(equipped_q.get("stamina", -1)) == 0 and int(equipped_q.get("mana", -1)) == 0, "Equipping must not alter stamina or mana.")
	var attack_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 114)
	attack_state.players[0]["hand"] = ["slash_new#001"]
	attack_state.players[0]["stamina"] = 1
	attack_state.players[1]["position"] = Vector2i(3, 2)
	attack_state.players[1]["hand"] = []
	var attack_command := _find_command(attack_state, MatchCommandScript.PLAY_CARD, "slash_new#001")
	_expect(bool(attack_state.call("submit_command", attack_command)), "A normally drawn attack card must remain playable with its listed cost.")
	_expect(int((attack_state.call("player", 0) as Dictionary).get("stamina", -1)) == 0, "Playing a normal hand card must pay its stamina cost.")


func _test_profession_attack_ranges() -> void:
	var state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 121)
	var attack: Dictionary = catalog.call("resolve_card", "slash_new#001") as Dictionary
	var strange: Dictionary = catalog.call("resolve_card", "soul_drain_new#001") as Dictionary
	var q: Dictionary = state.call("player", 0) as Dictionary
	q["profession"] = "guardian"
	state.players[0] = q
	_expect(int(state.call("_definition_range", 0, attack)) == 1, "Guardian attacks must use a 3x3 profession range.")
	q["profession"] = "arcanist"
	state.players[0] = q
	_expect(int(state.call("_definition_range", 0, attack)) == 2, "Arcanist attacks must use a 5x5 profession range.")
	q["profession"] = "shooter"
	state.players[0] = q
	_expect(int(state.call("_definition_range", 0, attack)) == 3, "Shooter attacks must use a 7x7 profession range.")
	q["equipment"] = {"weapon": "crowbar_new#001", "armor": "", "accessory": ""}
	state.players[0] = q
	_expect(int(state.call("_definition_range", 0, attack)) == 5, "Weapon range bonuses must apply from equipped card instances.")
	q["equipment"] = {"weapon": "overlimit_pistol_new#001", "armor": "", "accessory": ""}
	q["equipment_copies"] = {"weapon": "overlimit_pistol_new#001", "armor": "", "accessory": ""}
	q["stamina"] = 1
	state.players[0] = q
	_expect(int(state.call("_definition_range", 0, attack)) == 9, "Overlimit Pistol must add six attack range.")
	_expect(int((state.call("_effective_cost", 0, attack) as Dictionary).get("stamina", -1)) == 0, "Overlimit Pistol must reduce every attack's stamina cost by one.")
	state.players[0]["position"] = Vector2i(2, 2)
	state.players[1]["position"] = Vector2i(3, 2)
	state.players[0]["hand"] = ["slash_new#001"]
	state.players[1]["hand"] = []
	var pistol_target_health := int(state.players[1].get("health", 0))
	_expect(bool(state.call("submit_command", _find_command(state, MatchCommandScript.PLAY_CARD, "slash_new#001"))) and int(state.players[1].get("health", 0)) == pistol_target_health - 2, "Overlimit Pistol must add one damage to an adjacent attack.")
	_expect(int(state.call("_definition_range", 0, strange)) == int(state.get("board_size")), "Strange cards must ignore distance limits.")

	var gaze_state: RefCounted = _state(["na1", "q", "maddy", "signal"], 189)
	gaze_state.players[0]["hand"] = ["gaze_new#001"]
	gaze_state.players[0]["mana"] = 1
	gaze_state.players[0]["position"] = Vector2i(2, 2)
	gaze_state.players[1]["position"] = Vector2i(3, 2)
	gaze_state.players[1]["hand"] = []
	_expect(bool(gaze_state.call("submit_command", _find_command(gaze_state, MatchCommandScript.PLAY_CARD, "gaze_new#001"))), "Gaze must target and mark another character.")
	_expect(bool(((gaze_state.players[1].get("match_flags", {}) as Dictionary).get("gaze_next_turn", false))), "Gaze must wait for the target's next turn.")
	gaze_state.active_player_index = 1
	gaze_state.call("_begin_turn")
	var gaze_slash: Dictionary = catalog.call("resolve_card", "slash_new#001") as Dictionary
	var gaze_equipment: Dictionary = catalog.call("resolve_card", "crowbar_new#001") as Dictionary
	_expect(int((gaze_state.call("_effective_cost", 1, gaze_slash) as Dictionary).get("stamina", -1)) == 2 and int((gaze_state.call("_effective_cost", 1, gaze_slash) as Dictionary).get("mana", -1)) == 1, "Gaze must add one to both resource costs for the target's first non-equipment card.")
	_expect(int((gaze_state.call("_effective_cost", 1, gaze_equipment) as Dictionary).get("stamina", -1)) == 0 and int((gaze_state.call("_effective_cost", 1, gaze_equipment) as Dictionary).get("mana", -1)) == 0, "Gaze must not affect equipment costs or consume the mark.")
	gaze_state.call("_pay_cost", 1, gaze_slash)
	_expect(not bool(((gaze_state.players[1].get("match_flags", {}) as Dictionary).get("gaze_first_card_pending", false))), "Gaze must expire after the target pays for the first non-equipment card.")

	var thought_state: RefCounted = _state(["ginger", "q", "maddy", "signal"], 187)
	thought_state.players[0]["hand"] = ["mad_thought_new#001"]
	thought_state.players[0]["common_deck"] = []
	thought_state.players[0]["profession_deck"] = ["slash_new#002"]
	thought_state.players[0]["stamina"] = 0
	thought_state.players[0]["position"] = Vector2i(2, 2)
	thought_state.players[1]["position"] = Vector2i(3, 2)
	thought_state.players[1]["hand"] = []
	_expect(bool(thought_state.call("submit_command", _find_command(thought_state, MatchCommandScript.PLAY_CARD, "mad_thought_new#001"))), "Mad Thought must draw a card when played.")
	var thought_attack: Dictionary = catalog.call("resolve_card", "slash_new#002") as Dictionary
	_expect(int((thought_state.call("_effective_cost", 0, thought_attack) as Dictionary).get("stamina", -1)) == 0 and int((thought_state.call("_effective_cost", 0, thought_attack) as Dictionary).get("mana", -1)) == 0, "Mad Thought must make only its drawn attack card free for this turn.")
	_expect(bool(thought_state.call("submit_command", _find_command(thought_state, MatchCommandScript.PLAY_CARD, "slash_new#002"))) and not ((thought_state.players[0].get("flags", {}) as Dictionary).get("free_card_ids", []) as Array).has("slash_new#002"), "Mad Thought's free cost must be consumed when that exact drawn card is played.")

	var annihilate_state: RefCounted = _state(["shya", "q", "maddy", "signal"], 188)
	annihilate_state.players[0]["hand"] = ["annihilate_new#001"]
	annihilate_state.players[0]["stamina"] = 0
	annihilate_state.players[0]["position"] = Vector2i(2, 2)
	annihilate_state.players[1]["position"] = Vector2i(3, 2)
	annihilate_state.players[1]["hand"] = []
	_expect(bool(annihilate_state.call("submit_command", _find_command(annihilate_state, MatchCommandScript.PLAY_CARD, "annihilate_new#001"))) and (annihilate_state.players[0].get("hand", []) as Array).has("annihilate_new#001"), "Annihilate must recover the same physical card after resolving.")
	var annihilate_definition: Dictionary = catalog.call("resolve_card", "annihilate_new#001") as Dictionary
	_expect(int((annihilate_state.call("_effective_cost", 0, annihilate_definition) as Dictionary).get("stamina", -1)) == 1, "Annihilate must add one stamina cost to its recovered instance.")
	annihilate_state.players[0]["stamina"] = 1
	_expect(bool(annihilate_state.call("submit_command", _find_command(annihilate_state, MatchCommandScript.PLAY_CARD, "annihilate_new#001"))) and int((annihilate_state.call("_effective_cost", 0, annihilate_definition) as Dictionary).get("stamina", -1)) == 2, "Annihilate must stack its instance-specific stamina cost within the turn.")


func _test_dead_q_skips_end_turn_thunder_guard() -> void:
	var state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 122)
	var q: Dictionary = state.call("player", 0) as Dictionary
	q["alive"] = false
	q["health"] = 0
	q["q_thunder_guard_end_available"] = true
	state.players[0] = q
	state.call("_handle_end_turn")
	_expect((state.get("pending_skill_choice") as Dictionary).is_empty(), "A defeated Q must not receive an end-turn Thunder Guard choice.")
	_expect(int(state.get("active_player_index")) == 1, "A defeated Q must immediately yield the turn to the next living player.")


func _test_endgame_barrier_and_durability() -> void:
	var endgame_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 123)
	var q: Dictionary = endgame_state.call("player", 0) as Dictionary
	q["hand"] = ["endgame_new#001"]
	q["purchased_hand"] = []
	q["stamina"] = 0
	q["mana"] = 0
	endgame_state.players[0] = q
	var target: Dictionary = endgame_state.call("player", 1) as Dictionary
	target["position"] = Vector2i(3, 2)
	target["hand"] = []
	endgame_state.players[1] = target
	endgame_state.players[2]["position"] = Vector2i(2, 3)
	endgame_state.players[3]["position"] = Vector2i(3, 3)
	var before_health := int(target.get("health", 0))
	var endgame_command := _find_command(endgame_state, MatchCommandScript.PLAY_CARD, "endgame_new#001")
	_expect(not endgame_command.is_empty() and bool(endgame_state.call("submit_command", endgame_command)), "Endgame must open its copy selection even at zero resources when it is the last hand card.")
	var endgame_request: Dictionary = endgame_state.get("pending_skill_choice") as Dictionary
	_expect(String(endgame_request.get("kind", "")) == "endgame_card", "Endgame must request a copied card.")
	var choose_slash := MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(endgame_request.get("request_id", "")), "value": "slash_new#001"})
	_expect(bool(endgame_state.call("submit_command", choose_slash)), "Endgame must accept an affordable copied attack.")
	var target_request: Dictionary = endgame_state.get("pending_skill_choice") as Dictionary
	var choose_target := MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(target_request.get("request_id", "")), "value": 1})
	_expect(bool(endgame_state.call("submit_command", choose_target)), "Endgame copied attack must accept a legal target.")
	_expect(int((endgame_state.call("player", 1) as Dictionary).get("health", 0)) < before_health, "Endgame must resolve the copied attack effect.")
	_expect(not ((endgame_state.call("player", 0) as Dictionary).get("hand", []) as Array).has("endgame_new#001"), "Endgame must consume its physical card instance.")

	var barrier_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 124)
	var barrier_owner: Dictionary = barrier_state.call("player", 0) as Dictionary
	barrier_owner["hand"] = ["barrier_break_new#001"]
	barrier_owner["stamina"] = 2
	barrier_state.players[0] = barrier_owner
	barrier_state.call("_equip", 1, "crowbar_new#001")
	var barrier_command := _find_command(barrier_state, MatchCommandScript.PLAY_CARD, "barrier_break_new#001")
	_expect(not barrier_command.is_empty() and bool(barrier_state.call("submit_command", barrier_command)), "Barrier Break must target a character with an equipment card.")
	var barrier_request: Dictionary = barrier_state.get("pending_skill_choice") as Dictionary
	var equipment_option := ""
	for option_value: Variant in barrier_request.get("options", []) as Array:
		if String(option_value).begins_with("equipment:weapon|"):
			equipment_option = String(option_value)
	var choose_equipment := MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(barrier_request.get("request_id", "")), "value": equipment_option})
	_expect(not equipment_option.is_empty() and bool(barrier_state.call("submit_command", choose_equipment)), "Barrier Break must allow selecting the target's exact weapon instance.")
	_expect(String(((barrier_state.call("player", 1) as Dictionary).get("equipment", {}) as Dictionary).get("weapon", "")).is_empty(), "Barrier Break must remove the selected equipment from its slot.")
	_expect(((barrier_state.call("player", 1) as Dictionary).get("discard", []) as Array).has("crowbar_new#001"), "Barrier Break must move removed equipment to its owner's discard pile.")

	var durability_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 125)
	durability_state.call("_equip", 0, "crowbar_new#001")
	durability_state.players[0]["equipment_durability"]["weapon"]["current"] = 1
	durability_state.players[0]["hand"] = ["slash_new#001"]
	durability_state.players[0]["stamina"] = 2
	durability_state.players[1]["position"] = Vector2i(3, 2)
	durability_state.players[1]["hand"] = []
	var attack_command := _find_command(durability_state, MatchCommandScript.PLAY_CARD, "slash_new#001")
	_expect(not attack_command.is_empty() and bool(durability_state.call("submit_command", attack_command)), "An equipped weapon must support an attack before turn-end durability is consumed.")
	_expect(not String(((durability_state.call("player", 0) as Dictionary).get("equipment", {}) as Dictionary).get("weapon", "")).is_empty(), "Normal weapon attacks must not consume durability.")
	durability_state.call("_handle_end_turn")
	_expect(String(((durability_state.call("player", 0) as Dictionary).get("equipment", {}) as Dictionary).get("weapon", "")).is_empty(), "A weapon at zero durability must be destroyed at its owner's turn end.")


func _test_k_strategy_medium_recovery() -> void:
	var state: RefCounted = _state(["k", "ginger", "maddy", "signal"], 126)
	var medium := ["slash_new#001", "calm_mind_new#001"]
	state.players[0]["hand"] = medium.duplicate()
	state.players[0]["mana"] = 2
	var strategy := _find_command(state, MatchCommandScript.USE_SKILL, "k_brainstorm")
	_expect(not strategy.is_empty() and bool(state.call("submit_command", strategy)), "K Strategy must be usable with a non-empty hand.")
	_expect((state.call("player", 0) as Dictionary).get("hand", []).is_empty(), "K Strategy must consume the whole hand as its medium before selecting a copied card.")
	var card_request: Dictionary = state.get("pending_skill_choice") as Dictionary
	var chosen_card := String((card_request.get("options", []) as Array)[0])
	state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(card_request.get("request_id", "")), "value": chosen_card}))
	var target_request: Dictionary = state.get("pending_skill_choice") as Dictionary
	var chosen_target: Variant = (target_request.get("options", []) as Array)[0]
	state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(target_request.get("request_id", "")), "value": chosen_target}))
	_expect(((state.call("player", 0) as Dictionary).get("discard", []) as Array).has(medium[0]), "K Strategy medium cards must enter the discard pile.")
	state.players[0]["hand"] = ["slash_new#002"]
	var brain := _find_command(state, MatchCommandScript.USE_SKILL, "k_megamind")
	_expect(not brain.is_empty() and bool(state.call("submit_command", brain)), "K Brain must remain usable after Strategy.")
	var discard_request: Dictionary = state.get("pending_skill_discard") as Dictionary
	state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_DISCARD, 0, {"request_id": String(discard_request.get("request_id", "")), "card_ids": ["slash_new#002"]}))
	var recovery_request: Dictionary = state.get("pending_skill_choice") as Dictionary
	_expect(String(recovery_request.get("kind", "")) == "k_brain_recover", "K Brain must offer the Strategy recovery branch after paying its discard.")
	state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(recovery_request.get("request_id", "")), "value": "medium"}))
	var recovered_hand: Array = (state.call("player", 0) as Dictionary).get("hand", []) as Array
	_expect(recovered_hand.has(medium[0]) and recovered_hand.has(medium[1]), "K Brain must recover every card consumed as the previous Strategy medium.")


func _test_shya_flash_rules() -> void:
	var state: RefCounted = _state(["shya", "ginger", "maddy", "signal"], 127)
	state.players[0]["hand"] = ["slash_new#001", "slash_new#002"]
	state.players[0]["stamina"] = 2
	state.players[1]["position"] = Vector2i(3, 2)
	state.players[1]["hand"] = []
	var first_attack := _find_command(state, MatchCommandScript.PLAY_CARD, "slash_new#001")
	state.call("submit_command", first_attack)
	_expect(int((state.call("player", 0) as Dictionary).get("flash", 0)) == 1, "Shya must gain one Flash whenever Shya deals damage.")
	state.call("_apply_status", 0, "confusion", 1, 1)
	_expect(not ((state.call("player", 0) as Dictionary).get("statuses", {}) as Dictionary).has("confusion"), "A character with Flash must be immune to confusion.")
	state.players[1]["flash"] = 2
	var before_second := int(state.players[1].get("health", 0))
	var second_attack := _find_command(state, MatchCommandScript.PLAY_CARD, "slash_new#002")
	state.call("submit_command", second_attack)
	var break_offer: Dictionary = state.get("pending_skill_choice") as Dictionary
	_expect(String(break_offer.get("kind", "")) == "shya_break_offer", "Shya must receive a Break Flash choice after playing a card on a target with Flash.")
	state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(break_offer.get("request_id", "")), "value": "use"}))
	var consequence: Dictionary = state.get("pending_skill_choice") as Dictionary
	state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 1, {"request_id": String(consequence.get("request_id", "")), "value": "damage"}))
	_expect(int(state.players[1].get("health", 0)) <= before_second - 4, "Shya's Flash-boosted attack and two-Flash consequence must both deal damage.")
	_expect(int(state.players[1].get("flash", -1)) == 0, "Break Flash must remove all selected target Flash counters.")
	_expect(_find_command(state, MatchCommandScript.USE_SKILL, "shya_dazzling_flash").is_empty(), "Shya must not expose the removed legacy active skill.")

	var negate_state: RefCounted = _state(["q", "shya", "maddy", "signal"], 128)
	negate_state.players[0]["hand"] = ["slash_new#001"]
	negate_state.players[0]["stamina"] = 2
	negate_state.players[2]["position"] = Vector2i(3, 2)
	negate_state.players[2]["hand"] = []
	negate_state.players[1]["flash"] = 2
	var victim_health := int(negate_state.players[2].get("health", 0))
	negate_state.call("submit_command", _find_command(negate_state, MatchCommandScript.PLAY_CARD, "slash_new#001"))
	var flash_response := MatchCommandScript.make(MatchCommandScript.RESPOND, 1, {"card_id": "shya_flash_negate"})
	_expect(bool(negate_state.call("submit_command", flash_response)), "Shya must be able to remove two field Flash counters to negate another character's card.")
	_expect(int(negate_state.players[2].get("health", 0)) == victim_health and int(negate_state.players[1].get("flash", -1)) == 0, "Shya Flash negate must cancel the card and consume exactly two Flash counters.")


func _test_maddy_explore_rules() -> void:
	var normal_state: RefCounted = _state(["maddy", "q", "ginger", "signal"], 129)
	var maddy: Dictionary = normal_state.call("player", 0) as Dictionary
	maddy["position"] = Vector2i(7, 7)
	maddy["health"] = maxi(1, int(maddy.get("max_health", 1)) - 2)
	maddy["coins"] = 0
	normal_state.players[0] = maddy
	_expect(normal_state.call("tile_kind", Vector2i(7, 7)) == "normal", "Maddy's baseline explore test must use a normal tile.")
	var explore := _find_command(normal_state, MatchCommandScript.USE_SKILL, "maddy_prospect")
	_expect(not explore.is_empty() and bool(normal_state.call("submit_command", explore)), "Maddy Explore must open a reward choice on a normal tile.")
	var request: Dictionary = normal_state.get("pending_skill_choice") as Dictionary
	_expect(String(request.get("kind", "")) == "maddy_explore_choice", "Maddy Explore must use the dedicated reward choice request.")
	var before_health := int((normal_state.call("player", 0) as Dictionary).get("health", 0))
	_expect(bool(normal_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(request.get("request_id", "")), "value": "heal"}))), "Maddy must be able to choose Explore healing.")
	_expect(int((normal_state.call("player", 0) as Dictionary).get("health", 0)) == before_health + 1, "Maddy normal-tile Explore healing must restore exactly one health.")
	_expect(_find_command(normal_state, MatchCommandScript.USE_SKILL, "maddy_prospect").is_empty(), "Maddy Explore must be limited to one use per turn.")
	_expect(_find_command(normal_state, MatchCommandScript.USE_SKILL, "maddy_reclamation").is_empty(), "Legacy Maddy Reclamation must not remain available as a free piercing attack.")

	var wealth_state: RefCounted = _state(["maddy", "q", "ginger", "signal"], 130)
	var wealth_maddy: Dictionary = wealth_state.call("player", 0) as Dictionary
	var wealth_position: Vector2i = wealth_state.wealth_tiles[0]
	wealth_maddy["position"] = wealth_position
	wealth_maddy["coins"] = 0
	wealth_state.players[0] = wealth_maddy
	_expect(wealth_state.call("tile_kind", wealth_position) == "wealth", "Maddy wealth Explore test must use a wealth tile.")
	explore = _find_command(wealth_state, MatchCommandScript.USE_SKILL, "maddy_prospect")
	_expect(not explore.is_empty() and bool(wealth_state.call("submit_command", explore)), "Maddy Explore must be usable on a wealth tile.")
	request = wealth_state.get("pending_skill_choice") as Dictionary
	_expect(bool(wealth_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(request.get("request_id", "")), "value": "coins"}))), "Maddy must be able to choose Explore coins.")
	_expect(int((wealth_state.call("player", 0) as Dictionary).get("coins", 0)) == 4, "Maddy wealth-tile Explore must grant its normal two coins plus the documented two-coin wealth bonus.")

	var event_state: RefCounted = _state(["maddy", "q", "ginger", "signal"], 132)
	var event_maddy: Dictionary = event_state.call("player", 0) as Dictionary
	var event_position: Vector2i = event_state.event_tiles[0]
	event_maddy["position"] = event_position
	event_maddy["hand"] = []
	event_state.players[0] = event_maddy
	_expect(event_state.call("tile_kind", event_position) == "event", "Maddy event Explore test must use an event tile.")
	explore = _find_command(event_state, MatchCommandScript.USE_SKILL, "maddy_prospect")
	_expect(not explore.is_empty() and bool(event_state.call("submit_command", explore)), "Maddy Explore must be usable on an event tile.")
	request = event_state.get("pending_skill_choice") as Dictionary
	_expect((request.get("options", []) as Array) == ["draw_three"], "Maddy event-tile Explore must not incorrectly offer normal-tile rewards while event cancellation is provisional.")
	_expect(bool(event_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(request.get("request_id", "")), "value": "draw_three"}))), "Maddy must be able to take the implemented event-tile three-card draw.")
	_expect((event_state.call("player", 0) as Dictionary).get("hand", []).size() == 3, "Maddy event-tile Explore must draw exactly three cards.")

	var landing_state: RefCounted = _state(["maddy", "q", "ginger", "signal"], 131)
	var landing_maddy: Dictionary = landing_state.call("player", 0) as Dictionary
	landing_maddy["coins"] = 0
	landing_maddy["position"] = landing_state.wealth_tiles[0]
	landing_state.players[0] = landing_maddy
	landing_state.call("_resolve_landing", 0)
	_expect(int((landing_state.call("player", 0) as Dictionary).get("coins", 0)) == 2, "Maddy collecting a wealth tile must no longer receive the retired one-time bonus.")


func _test_maddy_reclaim_rules() -> void:
	var reclaim_state: RefCounted = _state(["maddy", "q", "ginger", "signal"], 143)
	reclaim_state.players[0]["position"] = Vector2i(7, 7)
	reclaim_state.players[0]["health"] = 5
	reclaim_state.players[0]["hand"] = []
	reclaim_state.players[1]["position"] = Vector2i(8, 7)
	var action := {
		"source_id": 0,
		"target_id": 1,
		"definition": {"target": "enemy", "effects": [{"op": "damage", "amount": 1, "kind": "normal"}]},
		"category": "attack",
		"card_id": ""
	}
	reclaim_state.call("_resolve_action", action)
	var offer: Dictionary = reclaim_state.get("pending_skill_choice") as Dictionary
	_expect(String(offer.get("kind", "")) == "maddy_reclaim_offer", "Maddy must receive an optional Reclaim offer after actually dealing damage.")
	_expect(bool(reclaim_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(offer.get("request_id", "")), "value": "use"}))), "Maddy must be able to accept the Reclaim offer.")
	var selected_tiles: Array[String] = []
	for _selection: int in 3:
		var tile_request: Dictionary = reclaim_state.get("pending_skill_choice") as Dictionary
		_expect(String(tile_request.get("kind", "")) == "maddy_reclaim_tile", "Reclaim must request each of its three tile choices in sequence.")
		var tile_options: Array = tile_request.get("options", []) as Array
		_expect(not tile_options.is_empty(), "Reclaim must retain a legal normal-tile fallback while selecting terrain.")
		if tile_options.is_empty():
			break
		var tile_key := String(tile_options.front())
		selected_tiles.append(tile_key)
		_expect(bool(reclaim_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(tile_request.get("request_id", "")), "value": tile_key}))), "Each Reclaim tile choice must be a legal command.")
	_expect(int(((reclaim_state.call("player", 0) as Dictionary).get("skill_uses", {}) as Dictionary).get("maddy_reclamation", 0)) == 1, "Reclaim must consume its documented once-per-turn use only after all three tiles are chosen.")
	reclaim_state.call("_finish_end_turn", 0)
	var reclaimed_tiles: Array = ((reclaim_state.call("player", 0) as Dictionary).get("match_flags", {}) as Dictionary).get("maddy_reclaimed_tiles", []) as Array
	_expect(reclaimed_tiles.size() == 3, "Reclaim must convert all three selected normal tiles at the end of Maddy's turn.")
	for tile_key: String in selected_tiles:
		var parts := tile_key.split(":", false)
		var position := Vector2i(int(parts[0]), int(parts[1]))
		_expect(reclaim_state.call("tile_kind", position) in ["wealth", "event"], "Each Reclaim tile must become either a wealth or event tile.")
	var landing_position_parts := String(selected_tiles.front()).split(":", false)
	var landing_position := Vector2i(int(landing_position_parts[0]), int(landing_position_parts[1]))
	reclaim_state.players[0]["position"] = landing_position
	reclaim_state.players[0]["health"] = 5
	reclaim_state.players[0]["hand"] = []
	reclaim_state.call("_resolve_landing", 0)
	_expect(int((reclaim_state.call("player", 0) as Dictionary).get("health", 0)) == 6 and (reclaim_state.call("player", 0) as Dictionary).get("hand", []).size() == 1, "Entering a Reclaim tile must restore one health and draw one card for Maddy.")


func _test_na1_gold_passive() -> void:
	var landing_state: RefCounted = _state(["na1", "q", "ginger", "signal"], 133)
	landing_state.players[0]["coins"] = 0
	landing_state.players[0]["position"] = Vector2i(7, 7)
	landing_state.call("_resolve_landing", 0)
	_expect(int((landing_state.call("player", 0) as Dictionary).get("coins", 0)) == 1, "Na1 must gain one coin whenever Na1 stops on a grid.")

	var damage_state: RefCounted = _state(["q", "na1", "ginger", "signal"], 134)
	damage_state.players[1]["coins"] = 3
	var health_before := int(damage_state.players[1].get("health", 0))
	damage_state.call("_deal_damage", 1, 2, "piercing", 0, true)
	_expect(int(damage_state.players[1].get("health", 0)) == health_before - 1 and int(damage_state.players[1].get("coins", 0)) == 2, "Na1 must spend one coin to prevent one damage as documented.")
	damage_state.call("_deal_damage", 1, 2, "true", -1, false)
	_expect(int(damage_state.players[1].get("health", 0)) == health_before - 3 and int(damage_state.players[1].get("coins", 0)) == 2, "Na1 Gold Tactician must only prevent the first damaging hit each complete round.")

	var income_state: RefCounted = MatchStateScript.new(rules, catalog, ["na1", "q", "ginger", "signal"], 135)
	income_state.players[0]["coins"] = 10
	income_state.call("_begin_turn")
	_expect(int(income_state.players[0].get("coins", 0)) == 11, "Na1 must gain at most one coin per turn when holding at least five coins.")
	income_state.call("_begin_turn")
	_expect(int(income_state.players[0].get("coins", 0)) == 12, "Na1 must apply the capped Gold Tactician income again on a later turn.")


func _test_signal_limit_and_q_end_turn_guard() -> void:
	var signal_state: RefCounted = _state(["signal", "q", "ginger", "maddy"], 136)
	var signal_player: Dictionary = signal_state.call("player", 0) as Dictionary
	signal_player["position"] = Vector2i(2, 2)
	signal_state.players[0] = signal_player
	signal_state.players[1]["position"] = Vector2i(3, 2)
	signal_state.players[1]["hand"] = []
	var signal_skill_ids: Array[String] = []
	for command: Dictionary in signal_state.call("legal_commands", 0) as Array[Dictionary]:
		if String(command.get("type", "")) == MatchCommandScript.USE_SKILL:
			signal_skill_ids.append(String((command.get("payload", {}) as Dictionary).get("skill_id", "")))
	_expect(signal_skill_ids == ["signal_frequency"], "Signal must expose only staged Frequency, not the retired legacy Navigation skill.")
	var frequency := _find_command(signal_state, MatchCommandScript.USE_SKILL, "signal_frequency")
	_expect(not frequency.is_empty() and bool(signal_state.call("submit_command", frequency)), "Signal Frequency must resolve once with a legal target.")
	_expect(_find_command(signal_state, MatchCommandScript.USE_SKILL, "signal_frequency").is_empty(), "Signal Frequency must be unavailable after its documented once-per-turn use.")

	var na1_state: RefCounted = _state(["na1", "q", "ginger", "signal"], 138)
	_expect(_find_command(na1_state, MatchCommandScript.USE_SKILL, "na1_free_spirit").is_empty(), "Na1 must not expose retired Free Spirit as an active skill; revised Endless is passive.")
	_expect(_find_command(na1_state, MatchCommandScript.USE_SKILL, "na1_foresight").is_empty(), "Na1 Foresight must resolve during the draw phase instead of appearing as a retired free active.")
	var foresight_state: RefCounted = MatchStateScript.new(rules, catalog, ["na1", "q", "ginger", "signal"], 139)
	_expect(bool(foresight_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SWITCH_PROFESSION, 0, {"profession": ""}))), "Na1 must select a profession before resolving the draw phase.")
	var foresight_request: Dictionary = foresight_state.get("pending_skill_choice") as Dictionary
	_expect(String(foresight_request.get("kind", "")) == "na1_foresight_draw", "Na1 must receive the Foresight draw-phase choice.")
	_expect(bool(foresight_state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(foresight_request.get("request_id", "")), "value": 2}))), "Na1 must be able to skip two opening draws with Foresight.")
	_expect((foresight_state.call("player", 0) as Dictionary).get("hand", []).size() == 5 and int((foresight_state.call("player", 0) as Dictionary).get("coins", 0)) == 4, "Na1 Foresight must trade two of three opening draws for two coins.")

	var q_state: RefCounted = _state(["q", "ginger", "maddy", "signal"], 137)
	q_state.players[0]["q_thunder_guard_end_available"] = false
	q_state.call("_resolve_q_thunder_guard_category", 0, "defense", {"revealed": [], "from_end_turn": true})
	_expect(not bool((q_state.call("player", 0) as Dictionary).get("q_thunder_guard_end_available", false)), "An end-turn Thunder Guard defense result must not re-arm another end-turn Thunder Guard.")


func _test_signal_collapsed_area_passive() -> void:
	var collapse_state: RefCounted = _state(["signal", "q", "ginger", "maddy"], 140)
	collapse_state.players[0]["position"] = Vector2i(0, 0)
	collapse_state.players[1]["position"] = Vector2i(1, 1)
	collapse_state.players[2]["position"] = Vector2i(13, 13)
	collapse_state.players[3]["position"] = Vector2i(7, 7)
	collapse_state.call("_collapse_board")
	_expect(collapse_state.get("collapse_count") == 1, "Signal collapsed-area test must reduce the board once.")
	_expect((collapse_state.call("player", 0) as Dictionary).get("position", Vector2i.ZERO) == Vector2i(0, 0), "Signal must remain in a collapsed area after board collapse.")
	_expect(collapse_state.call("active_bounds").has_point((collapse_state.call("player", 1) as Dictionary).get("position", Vector2i.ZERO)), "Non-Signal characters must still be moved into the active board after collapse.")
	var collapsed_moves: Array[Dictionary] = collapse_state.call("_legal_move_commands", 0) as Array[Dictionary]
	_expect(not collapsed_moves.is_empty(), "Signal must retain legal movement commands while in a collapsed area.")
	var collapsed_preview: Dictionary = collapse_state.call("targeting_preview", 0, MatchCommandScript.PLAY_CARD, "slash_new#001") as Dictionary
	_expect((collapsed_preview.get("cells", []) as Array).has(Vector2i(0, 0)), "Signal targeting previews must include collapsed-area cells while Signal is acting there.")

	var leave_state: RefCounted = _state(["signal", "q", "ginger", "maddy"], 141)
	leave_state.call("_collapse_board")
	leave_state.players[0]["position"] = Vector2i(1, 2)
	leave_state.players[0]["coins"] = 0
	leave_state.players[0]["hand"] = []
	var leave_command: Dictionary = {}
	for command: Dictionary in leave_state.call("_legal_move_commands", 0) as Array[Dictionary]:
		var path: Array = (command.get("payload", {}) as Dictionary).get("path", []) as Array
		if not path.is_empty() and _payload_to_position(path.back()) == Vector2i(2, 2):
			leave_command = command
			break
	_expect(not leave_command.is_empty() and bool(leave_state.call("submit_command", leave_command)), "Signal must be able to move from a collapsed area back into the active board.")
	_expect(int((leave_state.call("player", 0) as Dictionary).get("coins", 0)) == 2, "Signal's first exit from a collapsed area each turn must award exactly two coins.")
	_expect((leave_state.call("player", 0) as Dictionary).get("hand", []).size() == 2, "Signal's first exit from a collapsed area each turn must draw exactly two cards.")
	leave_state.call("_handle_move", {"path": [[3, 2]]})
	_expect(int((leave_state.call("player", 0) as Dictionary).get("coins", 0)) == 2 and (leave_state.call("player", 0) as Dictionary).get("hand", []).size() == 2, "Signal must not receive the collapsed-area exit reward twice in one turn.")

	var confusion_state: RefCounted = _state(["signal", "q", "ginger", "maddy"], 142)
	confusion_state.call("_collapse_board")
	confusion_state.players[0]["position"] = Vector2i(1, 2)
	for _turn: int in 3:
		confusion_state.call("_begin_turn")
	_expect(int(((confusion_state.call("player", 0) as Dictionary).get("statuses", {}) as Dictionary).get("confusion", 0)) == 1, "Signal must gain one confusion after starting three consecutive turns in a collapsed area.")
	confusion_state.players[0]["position"] = Vector2i(2, 2)
	confusion_state.call("_begin_turn")
	var signal_match_flags: Dictionary = (confusion_state.call("player", 0) as Dictionary).get("match_flags", {}) as Dictionary
	_expect(not signal_match_flags.has("signal_collapsed_turns") and not signal_match_flags.has("signal_collapsed_confusion_applied"), "Returning to the active board must reset Signal's collapsed-area stay tracking.")


func _state(roster: Array[String], seed: int) -> RefCounted:
	var state: RefCounted = MatchStateScript.new(rules, catalog, roster, seed)
	if bool(state.get("profession_choice_pending")):
		state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SWITCH_PROFESSION, 0, {"profession": ""}))
	var skill_choice: Dictionary = state.get("pending_skill_choice") as Dictionary
	if String(skill_choice.get("kind", "")) == "q_thunder_guard_offer":
		state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(skill_choice.get("request_id", "")), "value": "skip"}))
	elif String(skill_choice.get("kind", "")) == "na1_foresight_draw":
		state.call("submit_command", MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, 0, {"request_id": String(skill_choice.get("request_id", "")), "value": 0}))
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


func _payload_to_position(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Array and (value as Array).size() >= 2:
		var array_value: Array = value as Array
		return Vector2i(int(array_value[0]), int(array_value[1]))
	if not (value is Dictionary):
		return Vector2i.ZERO
	var payload: Dictionary = value as Dictionary
	return Vector2i(int(payload.get("x", 0)), int(payload.get("y", 0)))
