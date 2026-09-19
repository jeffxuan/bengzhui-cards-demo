class_name MatchState
extends RefCounted

const EventDeckScript = preload("res://scripts/core/event_deck.gd")
const MatchCommandScript = preload("res://scripts/core/match_command.gd")
const MatchEventScript = preload("res://scripts/core/match_event.gd")
const CARDINAL_DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const TARGET_EFFECTS: Array[String] = ["damage", "damage_missing_health", "assassinate_damage", "heal", "armor", "status", "status_if_damage", "remove_status", "break_armor", "push", "radial_push", "steal_card", "draw_target", "max_resource", "max_health", "gaze_next_turn", "guard_next_damage"]
const NEGATIVE_STATUSES: Array[String] = ["paralyze", "bleed", "poison", "confusion"]
const PROFESSION_ATTACK_RANGES: Dictionary = {
	"berserker": 1,
	"guardian": 1,
	"ambitionist": 1,
	"assassin": 1,
	"arcanist": 2,
	"adventurer": 2,
	"shooter": 3
}
const REVISED_SKILL_ALIASES: Dictionary = {
	"q_stargaze": "q_thunder_guard",
	"q_thunder_call": "q_thunderstorm",
	"k_megamind": "k_brain",
	"k_brainstorm": "k_strategy",
	"shya_dazzling_flash": "shya_break_flash",
	"shya_flash_break": "shya_break_flash",
	"ginger_fist_way": "ginger_waist",
	"ginger_guard_up": "ginger_power",
	"zc_madness": "zc_frenzy",
	"zc_poison_mist": "zc_frenzy",
	"na1_foresight": "na1_foresight",
	"na1_free_spirit": "na1_endless",
	"maddy_prospect": "maddy_explore",
	"maddy_reclamation": "maddy_reclaim",
	"signal_frequency": "signal_frequency"
}

var rules: Dictionary
var catalog: RefCounted
var seed: int
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var event_deck: RefCounted
var board_size: int
var max_collapses: int
var collapse_sizes: Array[int] = []
var hand_limit: int
var draw_per_turn: int
var armor_cap: int
var players: Array[Dictionary] = []
var active_player_index: int = 0
var completed_rounds: int = 0
var collapse_count: int = 0
var pending_action: Dictionary = {}
var pending_event: Dictionary = {}
var pending_discard: Dictionary = {}
var pending_skill_discard: Dictionary = {}
var pending_skill_choice: Dictionary = {}
var profession_choice_pending: bool = false
var discard_continuation: Dictionary = {}
var last_event: Dictionary = {}
var market: Array[String] = []
var market_deck: Array[String] = []
var spent_tiles: Dictionary = {}
var destroyed_tiles: Dictionary = {}
var command_log: Array[Dictionary] = []
var event_history: Array[Dictionary] = []
var recent_events: Array[Dictionary] = []
var match_metrics: Dictionary = {"single_target_damage": 0, "area_damage": 0, "pressure_damage": 0}
var finished: bool = false
var winner_id: int = -1
var win_reason: String = ""
var win_reason_id: String = ""
var last_error: String = ""
var start_positions: Array[Vector2i] = []
var wealth_tiles: Array[Vector2i] = []
var event_tiles: Array[Vector2i] = []
var trap_tiles: Array[Vector2i] = []
var poison_mists: Array[Dictionary] = []
var collapse_in_progress: bool = false
var planning_pending: Dictionary = {}


func _init(rule_values: Dictionary, content_catalog: RefCounted, roster: Array[String] = ["q", "ginger", "maddy", "signal"], match_seed: int = 114) -> void:
	rules = rule_values.duplicate(true)
	catalog = content_catalog
	seed = match_seed
	rng.seed = seed
	board_size = int(rules.get("board_size", 9))
	for size_value: Variant in rules.get("collapse_sizes", [board_size]) as Array:
		collapse_sizes.append(int(size_value))
	if collapse_sizes.is_empty() or collapse_sizes[0] != board_size:
		collapse_sizes = [board_size]
	max_collapses = collapse_sizes.size() - 1
	hand_limit = int(rules.get("hand_limit", 6))
	draw_per_turn = int(rules.get("draw_per_turn", 2))
	armor_cap = int(rules.get("armor_cap", 3))
	start_positions = _vector_array(rules.get("start_positions", []))
	wealth_tiles = _vector_array(rules.get("wealth_tiles", []))
	event_tiles = _vector_array(rules.get("event_tiles", []))
	trap_tiles = _vector_array(rules.get("trap_tiles", []))
	var catalog_events: Array[Dictionary] = catalog.get("events") as Array[Dictionary]
	event_deck = EventDeckScript.new(catalog_events, seed + 17)
	_create_players(roster)
	_setup_market()
	_begin_turn()


func current_player() -> Dictionary:
	if players.is_empty():
		return {}
	return players[active_player_index]


func player(player_id: int) -> Dictionary:
	if player_id < 0 or player_id >= players.size():
		return {}
	return players[player_id]


func targeting_preview(actor_id: int, command_type: String, definition_id: String) -> Dictionary:
	var definition: Dictionary
	if command_type == MatchCommandScript.PLAY_CARD:
		definition = catalog.call("resolve_card", definition_id) as Dictionary
	else:
		definition = _skill_definition(actor_id, definition_id)
	var source: Vector2i = players[actor_id].get("position", Vector2i.ZERO) as Vector2i
	var range_limit: int = _definition_range(actor_id, definition)
	var cells: Array[Vector2i] = []
	var legal_target_ids: Array[int] = []
	var target_rule := String(definition.get("target", "self"))
	if target_rule != "self":
		var line_attack: bool = String(definition.get("category", "")) == "attack" and bool(equipped_definition(actor_id, "weapon").get("line_attack", false))
		var preview_bounds := Rect2i(Vector2i.ZERO, Vector2i(board_size, board_size)) if String(players[actor_id].get("character_id", "")) == "signal" else active_bounds()
		for y: int in range(preview_bounds.position.y, preview_bounds.end.y):
			for x: int in range(preview_bounds.position.x, preview_bounds.end.x):
				var cell := Vector2i(x, y)
				if maxi(absi(cell.x - source.x), absi(cell.y - source.y)) <= range_limit and (not line_attack or cell.x == source.x or cell.y == source.y):
					cells.append(cell)
		for target_id: int in players.size():
			var target_position: Vector2i = players[target_id].get("position", Vector2i.ZERO) as Vector2i
			var includes_self := target_rule == "alive"
			if (includes_self or target_id != actor_id) and bool(players[target_id].get("alive", false)) and (includes_self or _distance(actor_id, target_id) <= range_limit) and (not line_attack or target_position.x == source.x or target_position.y == source.y):
				legal_target_ids.append(target_id)
	return {"range": range_limit, "cells": cells, "legal_target_ids": legal_target_ids}


func active_bounds() -> Rect2i:
	var side: int = collapse_sizes[mini(collapse_count, collapse_sizes.size() - 1)]
	var minimum: int = (board_size - side) / 2
	return Rect2i(minimum, minimum, side, side)


func tile_kind(position: Vector2i) -> String:
	if not active_bounds().has_point(position):
		return "collapsed"
	if destroyed_tiles.has(_tile_key(position)):
		return "collapsed"
	if spent_tiles.has(_tile_key(position)):
		return "normal"
	if wealth_tiles.has(position):
		return "wealth"
	if event_tiles.has(position):
		return "event"
	if trap_tiles.has(position):
		return "trap"
	return "normal"


func submit_command(command: Dictionary) -> bool:
	last_error = _validate_command(command)
	if not last_error.is_empty():
		_emit("command_rejected", {"message": last_error, "command": command.duplicate(true)})
		return false
	command_log.append(command.duplicate(true))
	var command_type: String = String(command.get("type", ""))
	if command_type in [MatchCommandScript.MOVE, MatchCommandScript.PLAY_CARD, MatchCommandScript.USE_SKILL, MatchCommandScript.BUY, MatchCommandScript.ACTIVATE_EQUIPMENT]:
		players[active_player_index]["turn_commands"] = int(players[active_player_index].get("turn_commands", 0)) + 1
	var payload: Dictionary = command.get("payload", {}) as Dictionary
	var tiebreak_snapshot: Array[Dictionary] = _capture_tiebreak_snapshot(_alive_player_ids())
	match command_type:
		MatchCommandScript.MOVE:
			_handle_move(payload)
		MatchCommandScript.PLAY_CARD:
			_handle_play_card(payload)
		MatchCommandScript.RESPOND:
			_handle_response(payload)
		MatchCommandScript.USE_SKILL:
			_handle_use_skill(payload)
		MatchCommandScript.ACTIVATE_EQUIPMENT:
			_handle_activate_equipment(payload)
		MatchCommandScript.BUY:
			_handle_buy(payload)
		MatchCommandScript.EVENT_CHOICE:
			_handle_event_choice(payload)
		MatchCommandScript.END_TURN:
			_handle_end_turn()
		MatchCommandScript.DISCARD_CARDS:
			_handle_discard_cards(payload)
		MatchCommandScript.SKILL_DISCARD:
			_handle_skill_discard(payload)
		MatchCommandScript.SKILL_CHOICE:
			_handle_skill_choice(payload)
		MatchCommandScript.SWITCH_PROFESSION:
			_handle_switch_profession(payload)
	_settle_eliminations(tiebreak_snapshot)
	if not finished and pending_action.is_empty() and pending_event.is_empty() and not bool(current_player().get("alive", false)):
		var followup_snapshot: Array[Dictionary] = _capture_tiebreak_snapshot(_alive_player_ids())
		_handle_end_turn()
		_settle_eliminations(followup_snapshot)
	return true


func legal_commands(actor_id: int = -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if finished or players.is_empty():
		return result
	if not pending_skill_choice.is_empty():
		var choice_actor: int = int(pending_skill_choice.get("player_id", -1))
		if actor_id < 0 or actor_id == choice_actor:
			for option_value: Variant in pending_skill_choice.get("options", []) as Array:
				result.append(MatchCommandScript.make(MatchCommandScript.SKILL_CHOICE, choice_actor, {"request_id": String(pending_skill_choice.get("request_id", "")), "value": option_value}))
		return result
	if not pending_skill_discard.is_empty():
		var skill_discard_actor: int = int(pending_skill_discard.get("player_id", -1))
		if actor_id < 0 or actor_id == skill_discard_actor:
			result.append(MatchCommandScript.make(MatchCommandScript.SKILL_DISCARD, skill_discard_actor, {
				"request_id": String(pending_skill_discard.get("request_id", "")),
				"selection_mode": String(pending_skill_discard.get("selection_mode", "rank_sum")),
				"required_rank_sum": int(pending_skill_discard.get("required_rank_sum", 0)),
				"minimum_count": int(pending_skill_discard.get("minimum_count", 1)),
				"required_count": int(pending_skill_discard.get("required_count", 0))
			}))
		return result
	if not pending_discard.is_empty():
		var discard_actor: int = int(pending_discard.get("player_id", -1))
		if actor_id < 0 or actor_id == discard_actor:
			result.append(MatchCommandScript.make(MatchCommandScript.DISCARD_CARDS, discard_actor, {
				"request_id": String(pending_discard.get("request_id", "")),
				"required_count": int(pending_discard.get("required_count", 0))
			}))
		return result
	if profession_choice_pending:
		if actor_id < 0 or actor_id == active_player_index:
			var options: Array = (current_player().get("professions", []) as Array).duplicate()
			options.append("")
			for profession_value: Variant in options:
				result.append(MatchCommandScript.make(MatchCommandScript.SWITCH_PROFESSION, active_player_index, {"profession": String(profession_value)}))
		return result
	if not pending_action.is_empty():
		var responder_id: int = int(pending_action.get("responder_id", -1))
		if actor_id >= 0 and actor_id != responder_id:
			return result
		if bool(pending_action.get("shya_flash_negate_offer", false)):
			result.append(MatchCommandScript.make(MatchCommandScript.RESPOND, responder_id, {"card_id": "shya_flash_negate"}))
			result.append(MatchCommandScript.make(MatchCommandScript.RESPOND, responder_id, {"card_id": ""}))
			return result
		for card_id: String in _valid_response_cards(responder_id, String(pending_action.get("category", ""))):
			result.append(MatchCommandScript.make(MatchCommandScript.RESPOND, responder_id, {"card_id": card_id}))
		result.append(MatchCommandScript.make(MatchCommandScript.RESPOND, responder_id, {"card_id": ""}))
		return result
	var active_id: int = int(current_player().get("id", -1))
	if actor_id >= 0 and actor_id != active_id:
		return result
	if not pending_event.is_empty():
		var choices: Array = pending_event.get("choices", []) as Array
		for choice_index: int in choices.size():
			var choice: Dictionary = choices[choice_index] as Dictionary
			if _event_choice_is_legal(current_player(), choice):
				result.append(MatchCommandScript.make(MatchCommandScript.EVENT_CHOICE, active_id, {"choice_index": choice_index}))
		return result
	var active: Dictionary = current_player()
	if bool((active.get("flags", {}) as Dictionary).get("play_phase_ended", false)):
		result.append(MatchCommandScript.make(MatchCommandScript.END_TURN, active_id))
		return result
	if int(active.get("moves_remaining", 0)) > 0:
		result.append_array(_legal_move_commands(active_id))
	# Cards and character skills are resource-driven. The market is controlled
	# separately by its once-per-turn purchase flag.
	result.append_array(_legal_card_commands(active_id))
	result.append_array(_legal_skill_commands(active_id))
	result.append_array(_legal_equipment_commands(active_id))
	result.append_array(_legal_buy_commands(active_id))
	result.append(MatchCommandScript.make(MatchCommandScript.END_TURN, active_id))
	return result


func drain_events() -> Array[Dictionary]:
	var drained: Array[Dictionary] = recent_events.duplicate(true)
	recent_events.clear()
	return drained


func set_market_for_testing(card_ids: Array[String]) -> void:
	market = card_ids.duplicate()


func _validate_discard_payload(payload: Dictionary) -> String:
	if String(payload.get("request_id", "")) != String(pending_discard.get("request_id", "")):
		return "弃牌请求已经失效。"
	var selected: Array = payload.get("card_ids", []) as Array
	var required_count: int = int(pending_discard.get("required_count", 0))
	if selected.size() != required_count:
		return "必须选择%d张牌。" % required_count
	var available: Array = players[int(pending_discard.get("player_id", -1))].get("hand", []) as Array
	var remaining: Array = available.duplicate()
	for card_value: Variant in selected:
		var card_id: String = String(card_value)
		var index: int = remaining.find(card_id)
		if index < 0:
			return "选择的牌不在当前手牌中。"
		remaining.remove_at(index)
	return ""


func _validate_skill_discard_selection(player_id: int, selected: Array) -> String:
	var hand: Array = players[player_id].get("hand", []) as Array
	var remaining: Array = hand.duplicate()
	for card_value: Variant in selected:
		var index := remaining.find(String(card_value))
		if index < 0:
			return "选择的牌不在当前手牌中。"
		remaining.remove_at(index)
	var selection_mode := String(pending_skill_discard.get("selection_mode", "rank_sum"))
	if String(pending_skill_discard.get("skill_id", "")) == "mana_flow_new":
		if selected.size() != 1:
			return "【魔力回流】必须弃置一张元素牌。"
		var definition: Dictionary = catalog.call("resolve_card", String(selected.front())) as Dictionary
		if not _is_elemental_card(definition):
			return "所选牌不是元素牌。"
		return ""
	if selection_mode == "count":
		var required_count := int(pending_skill_discard.get("required_count", 0))
		if selected.size() != required_count:
			return "必须选择%d张牌。" % required_count
		return ""
	return catalog.call("validate_rank_sum_selection", hand, selected, int(pending_skill_discard.get("required_rank_sum", 0)), int(pending_skill_discard.get("minimum_count", 1)))


func _request_discard(player_id: int, amount: int, reason_id: String, continuation: Dictionary = {}) -> bool:
	var hand: Array = players[player_id].get("hand", []) as Array
	var required_count: int = mini(maxi(0, amount), hand.size())
	if required_count <= 0:
		return false
	pending_discard = {
		"request_id": "%d:%d:%s" % [command_log.size(), player_id, reason_id],
		"player_id": player_id,
		"required_count": required_count,
		"reason_id": reason_id
	}
	discard_continuation = continuation.duplicate(true)
	_emit("discard_requested", {
		"player_id": player_id,
		"required_count": required_count,
		"reason_id": reason_id,
		"message": "%s 请选择%d张牌弃置。" % [String(players[player_id].get("name", "")), required_count]
	})
	return true


func _handle_discard_cards(payload: Dictionary) -> void:
	var player_id: int = int(pending_discard.get("player_id", -1))
	var reason_id: String = String(pending_discard.get("reason_id", "effect"))
	var selected: Array = payload.get("card_ids", []) as Array
	var discarded: Array[String] = []
	var hand: Array = players[player_id].get("hand", []) as Array
	var discard: Array = players[player_id].get("discard", []) as Array
	for card_value: Variant in selected:
		var card_id: String = String(card_value)
		var index: int = hand.find(card_id)
		if index >= 0:
			hand.remove_at(index)
			discard.append(card_id)
			_record_discard_origin(player_id, card_id)
			discarded.append(card_id)
	players[player_id]["hand"] = hand
	players[player_id]["discard"] = discard
	pending_discard.clear()
	_emit("cards_discarded", {
		"player_id": player_id,
		"card_ids": discarded.duplicate(),
		"reason_id": reason_id,
		"message": "%s 弃置了%d张牌。" % [String(players[player_id].get("name", "")), discarded.size()]
	})
	var continuation: Dictionary = discard_continuation.duplicate(true)
	discard_continuation.clear()
	if reason_id == "end_turn":
		_finish_end_turn(player_id)
		return
	var missing: int = int(continuation.get("discard_amount", 0)) - discarded.size()
	if bool(continuation.get("damage_shortfall", false)) and missing > 0:
		_deal_damage(player_id, missing, "true", -1, false)
	_apply_effects_from(
		int(continuation.get("source_id", player_id)),
		int(continuation.get("target_id", player_id)),
		continuation.get("effects", []) as Array,
		String(continuation.get("category", "effect")),
		int(continuation.get("damage_bonus", 0)),
		int(continuation.get("range_limit", 0)),
		int(continuation.get("pressure_bonus", 0)),
		bool(continuation.get("area_action", false)),
		int(continuation.get("effect_index", 0)) + 1
	)


func _handle_skill_discard(payload: Dictionary) -> void:
	var player_id: int = int(pending_skill_discard.get("player_id", -1))
	var selected: Array = payload.get("card_ids", []) as Array
	var hand: Array = players[player_id].get("hand", []) as Array
	var discard: Array = players[player_id].get("discard", []) as Array
	var discarded: Array[String] = []
	var skill_id := String(pending_skill_discard.get("skill_id", ""))
	for card_value: Variant in selected:
		var card_id := String(card_value)
		var index := hand.find(card_id)
		if index >= 0:
			hand.remove_at(index)
			discard.append(card_id)
			discarded.append(card_id)
			_record_discard_origin(player_id, card_id)
	players[player_id]["hand"] = hand
	players[player_id]["discard"] = discard
	var target_id := int(pending_skill_discard.get("target_id", player_id))
	pending_skill_discard.clear()
	if skill_id == "ginger_power":
		var targets := _enemies_in_range(player_id, 1)
		if targets.is_empty():
			_emit("skill_resolution_failed", {"player_id": player_id, "skill_id": skill_id, "message": "【强攻】在结算时失去所有合法目标，已结束结算。"})
			return
		_request_skill_choice(player_id, "ginger_power_target", skill_id, targets)
		return
	if skill_id == "mana_flow_new":
		_change_resource(player_id, "mana", 1)
		_draw_cards(player_id, 1)
		_emit("skill_effect_resolved", {"player_id": player_id, "card_ids": discarded.duplicate(), "card_id": "mana_flow_new", "message": "【魔力回流】弃置元素牌，回复1点法力并摸1张牌。"})
		return
	if String(REVISED_SKILL_ALIASES.get(skill_id, skill_id)) == "k_brain":
		var strategy_record: Dictionary = players[player_id].get("last_strategy_record", {}) as Dictionary
		if not strategy_record.is_empty():
			_request_skill_choice(player_id, "k_brain_recover", skill_id, ["virtual", "medium"], {"strategy_record": strategy_record.duplicate(true)})
			return
	_emit("cards_discarded", {"player_id": player_id, "card_ids": discarded, "reason_id": "skill:%s" % skill_id, "message": "%s 为技能【%s】弃置了%d张牌。" % [String(players[player_id].get("name", "")), skill_id, discarded.size()]})
	_emit("skill_discard_paid", {"player_id": player_id, "skill_id": skill_id, "card_ids": discarded, "message": "%s 已支付技能【%s】的弃牌条件。" % [String(players[player_id].get("name", "")), skill_id]})
	var skill: Dictionary = _skill_definition(player_id, skill_id)
	var action: Dictionary = {"source_id": player_id, "target_id": target_id, "definition": skill.duplicate(true), "category": "skill", "card_id": "", "damage_bonus": 0, "unanswerable": true}
	_resolve_action(action)
	if skill_id == "q_thunderstorm" and bool(players[player_id].get("alive", false)):
		_request_skill_choice(player_id, "q_thunderstorm_rank", skill_id, range(1, 14))


func _request_skill_choice(player_id: int, kind: String, skill_id: String, options: Array, extra: Dictionary = {}) -> void:
	pending_skill_choice = {"request_id": "%d:%d:%s" % [command_log.size(), player_id, kind], "player_id": player_id, "kind": kind, "skill_id": skill_id, "options": options.duplicate(true)}
	for key: Variant in extra:
		pending_skill_choice[String(key)] = extra[key]
	_emit("skill_choice_requested", {"player_id": player_id, "skill_id": skill_id, "kind": kind, "message": "%s 等待技能选择。" % String(players[player_id].get("name", ""))})


func _handle_skill_choice(payload: Dictionary) -> void:
	var request := pending_skill_choice.duplicate(true)
	pending_skill_choice.clear()
	var player_id := int(request.get("player_id", -1))
	var kind := String(request.get("kind", ""))
	var value: Variant = payload.get("value")
	match kind:
		"q_thunder_guard_offer":
			if String(value) == "use":
				_begin_q_thunder_guard(player_id)
			else:
				_emit("skill_choice_resolved", {"player_id": player_id, "skill_id": "q_thunder_guard", "message": "Q 本回合不发动【雷佑】。"})
		"q_thunderstorm_rank":
			players[player_id]["thunderstorm_rank"] = int(value)
			_draw_cards(player_id, int(value))
			_emit("skill_choice_resolved", {"player_id": player_id, "skill_id": "q_thunderstorm", "rank": int(value), "message": "【雷暴】点数改为%d，摸%d张牌并结束回合。" % [int(value), int(value)]})
			_handle_end_turn()
		"q_thunder_guard_category":
			_resolve_q_thunder_guard_category(player_id, String(value), request)
		"q_thunder_guard_transfer":
			var card_id := String(request.get("card_id", ""))
			var source_discard: Array = players[player_id].get("discard", []) as Array
			if _remove_first(source_discard, card_id):
				var definition: Dictionary = catalog.call("resolve_card", card_id) as Dictionary
				var origin_key := "profession_discard" if String(definition.get("profession", "neutral")) != "neutral" and String(definition.get("category", "")) != "equipment" else "common_discard"
				_remove_first(players[player_id].get(origin_key, []) as Array, card_id)
				(players[int(value)].get("hand", []) as Array).append(card_id)
				_emit("card_transferred", {"player_id": player_id, "target_id": int(value), "card_id": card_id, "message": "Q 将【%s】交给%s。" % [String(definition.get("name", card_id)), String(players[int(value)].get("name", ""))]})
		"q_thunder_guard_end_decision":
			if String(value) == "use":
				_begin_q_thunder_guard(player_id, true)
			else:
				_finish_end_turn(player_id)
		"k_strategy_card":
			var definition: Dictionary = catalog.call("resolve_card", String(value)) as Dictionary
			_request_skill_choice(player_id, "k_strategy_target", "k_strategy", _skill_target_options(player_id, definition), {"card_id": String(value), "resolution_count": int(request.get("resolution_count", 1)), "medium_cards": (request.get("medium_cards", []) as Array).duplicate()})
		"k_strategy_target":
			_resolve_k_strategy(player_id, String(request.get("card_id", "")), int(value), int(request.get("resolution_count", 1)), request.get("medium_cards", []) as Array)
		"k_brain_recover":
			_resolve_k_brain_recovery(player_id, String(value), request)
		"endgame_card":
			_begin_endgame_target_choice(player_id, String(value), request)
		"endgame_target":
			_resolve_endgame_copy(player_id, String(request.get("physical_card_id", "")), String(request.get("copied_card_id", "")), int(value), bool(request.get("was_last_card", false)))
		"last_resort_card":
			_begin_last_resort_target_choice(player_id, String(value))
		"last_resort_target":
			_resolve_last_resort(player_id, String(request.get("copied_card_id", "")), int(value))
		"crossfire_source_card":
			_request_skill_choice(int(request.get("target_id", -1)), "crossfire_target_card", "crossfire_new", _attack_hand_options(int(request.get("target_id", -1))), {"source_id": player_id, "source_card_id": String(value)})
		"crossfire_target_card":
			_resolve_crossfire(int(request.get("source_id", -1)), player_id, String(request.get("source_card_id", "")), String(value))
		"swap_source_card":
			_request_skill_choice(player_id, "swap_target_card", "swap_new", _barrier_break_options(int(request.get("target_id", -1))), {"target_id": int(request.get("target_id", -1)), "source_card_id": String(value)})
		"swap_target_card":
			_resolve_swap(player_id, int(request.get("target_id", -1)), String(request.get("source_card_id", "")), String(value))
		"strange_face_self_card":
			_resolve_strange_face_self(player_id, int(request.get("attacker_id", -1)), String(value))
		"strange_face_attacker_card":
			_resolve_strange_face_attacker(player_id, int(request.get("attacker_id", -1)), String(value))
		"consume_offer":
			if String(value) == "use":
				_request_skill_choice(player_id, "consume_target_card", "consume_new", (players[int(request.get("gainer_id", -1))].get("hand", []) as Array).duplicate(), {"gainer_id": int(request.get("gainer_id", -1)), "consume_card_id": String(request.get("consume_card_id", ""))})
		"consume_target_card":
			_resolve_consume(player_id, int(request.get("gainer_id", -1)), String(request.get("consume_card_id", "")), String(value))
		"sleeve_arrow_card":
			_request_skill_choice(player_id, "sleeve_arrow_target", "sleeve_arrow_new", _alive_enemy_ids(player_id), {"card_id": String(value)})
		"sleeve_arrow_target":
			_resolve_sleeve_arrow(player_id, String(request.get("card_id", "")), int(value))
		"element_resonance_element":
			_resolve_element_resonance(player_id, int(request.get("target_id", -1)), String(value))
		"barrier_break_card":
			_resolve_barrier_break(player_id, int(request.get("target_id", -1)), String(value))
		"shya_break_offer":
			if String(value) == "use":
				_begin_shya_break_consequence(player_id, int(request.get("target_id", -1)), int(request.get("flash_amount", 0)))
		"shya_break_consequence":
			var amount := int(request.get("flash_amount", 0))
			if String(value) == "discard":
				_request_discard(player_id, amount, "shya_break_flash")
			else:
				_deal_damage(player_id, amount, "true", int(request.get("source_id", -1)), false)
		"shya_response_offer":
			if String(value) == "use":
				_gain_flash(int(request.get("responder_id", -1)), 1, "shya_break_flash_response")
				_draw_cards(player_id, 1)
			_finish_response_resolution(request.get("response_action", {}) as Dictionary, bool(request.get("canceled", false)), bool(request.get("reflected", false)), int(request.get("responder_id", -1)), String(request.get("response_card_id", "")))
		"ginger_power_target":
			_resolve_ginger_power(player_id, int(value))
		"ginger_power_max_health":
			if String(value) == "reduce":
				_change_max_health(player_id, -1, "ginger_power")
			_request_ginger_power_cards(player_id)
		"ginger_power_reward":
			if String(value) == "heal":
				_heal(player_id, 1)
			else:
				_draw_cards(player_id, 1)
		"zc_frenzy_category":
			_resolve_zc_frenzy_category(player_id, String(value))
		"zc_frenzy_target":
			_resolve_zc_frenzy_target(player_id, int(value))
		"maddy_explore_choice":
			_resolve_maddy_explore(player_id, String(value), request)
		"maddy_reclaim_offer":
			if String(value) == "use":
				_begin_maddy_reclaim_selection(player_id, [])
			else:
				var maddy_flags: Dictionary = players[player_id].get("flags", {}) as Dictionary
				maddy_flags.erase("maddy_reclaim_ready")
				players[player_id]["flags"] = maddy_flags
				_emit("skill_choice_resolved", {"player_id": player_id, "skill_id": "maddy_reclaim", "message": "Maddy 本回合不发动【开垦】。"})
		"maddy_reclaim_tile":
			var chosen_tiles: Array = (request.get("chosen_tiles", []) as Array).duplicate()
			chosen_tiles.append(String(value))
			_begin_maddy_reclaim_selection(player_id, chosen_tiles)
		"na1_foresight_draw":
			_resolve_na1_foresight_draw(player_id, int(value), request)
		"old_map_choice":
			if String(value) == "draw":
				_draw_cards(player_id, 1)
			else:
				_change_coins(player_id, 1)
		"card_area_choice":
			_resolve_card_area_choice(player_id, String(request.get("card_id", "")), String(value))
		"scatter_direction":
			_resolve_scatter(player_id, String(request.get("card_id", "")), String(value))
		"momentum_direction":
			_resolve_momentum_direction(player_id, int(request.get("target_id", -1)), String(value))
		"wind_raise_direction":
			_resolve_momentum_direction(player_id, int(request.get("target_id", -1)), String(value))
		"skirmish_direction":
			_resolve_skirmish_followup(player_id, int(request.get("target_id", -1)), String(value))
		"precision_direction":
			_resolve_precision_direction(player_id, String(request.get("card_id", "")), String(value))
		"precision_target":
			_resolve_precision_target(player_id, String(request.get("card_id", "")), int(value))
		"body_slam_target":
			_resolve_body_slam_target(player_id, String(request.get("card_id", "")), int(value))
		"neutralize_target":
			_resolve_neutralize_target(player_id, int(request.get("source_id", -1)), int(value))
		"assassination_order_discard":
			var victim_id := int(request.get("target_id", -1))
			if victim_id >= 0 and victim_id < players.size():
				var victim_hand: Array = players[victim_id].get("hand", []) as Array
				var selected_card := String(value)
				if _remove_first(victim_hand, selected_card):
					(players[victim_id].get("discard", []) as Array).append(selected_card)
					_record_discard_origin(victim_id, selected_card)
					_emit("assassination_order_triggered", {"player_id": player_id, "target_id": victim_id, "card_id": selected_card, "message": "【刺杀令】弃置了目标一张手牌。"})
		"decoy_discard":
			var attacker_id := int(request.get("attacker_id", -1))
			if attacker_id >= 0 and attacker_id < players.size():
				var attacker_hand: Array = players[attacker_id].get("hand", []) as Array
				var decoy_card := String(value)
				if _remove_first(attacker_hand, decoy_card):
					(players[attacker_id].get("discard", []) as Array).append(decoy_card)
					_record_discard_origin(attacker_id, decoy_card)
		"wolf_fang_choice":
			if String(value) == "heal":
				_heal(player_id, 1)
			else:
				_apply_status(int(request.get("target_id", -1)), "bleed", 1, player_id)
		"burning_cape_discard":
			var cape_attacker_id := int(request.get("attacker_id", -1))
			var cape_card_id := String(value)
			if cape_attacker_id >= 0 and cape_attacker_id < players.size() and _remove_first(players[player_id].get("hand", []) as Array, cape_card_id):
				(players[player_id].get("discard", []) as Array).append(cape_card_id)
				_record_discard_origin(player_id, cape_card_id)
				var cape_definition: Dictionary = catalog.call("resolve_card", cape_card_id) as Dictionary
				var cape_status := _elemental_status_for_card(cape_definition)
				if not cape_status.is_empty():
					_apply_status(cape_attacker_id, cape_status, 1, player_id)
					_emit("burning_cape_triggered", {"player_id": player_id, "target_id": cape_attacker_id, "card_id": cape_card_id, "status": cape_status, "message": "【焚尽斗篷】弃置元素牌，使伤害来源获得%s。" % cape_status})
		"gold_panning_card":
			_resolve_gold_panning(player_id, String(value))


func _skill_target_options(player_id: int, definition: Dictionary) -> Array:
	if String(definition.get("target", "self")) == "self":
		return [player_id]
	if String(definition.get("target", "self")) == "all_enemies_in_range":
		return [-1] if not _enemies_in_range(player_id, _definition_range(player_id, definition)).is_empty() else []
	return _enemies_in_range(player_id, _definition_range(player_id, definition))


func _available_hand_count(player_id: int) -> int:
	return (players[player_id].get("hand", []) as Array).size() + (players[player_id].get("purchased_hand", []) as Array).size()


func _endgame_copy_options(player_id: int, physical_card_id: String) -> Array[String]:
	var result: Array[String] = []
	var free_copy := _available_hand_count(player_id) == 1
	for definition_value: Variant in catalog.get("staged_cards") as Array:
		var definition: Dictionary = definition_value as Dictionary
		var logical_id := String(definition.get("id", ""))
		if logical_id in ["endgame_new", "endgame_ambitionist_new"]:
			continue
		var instances: Array = definition.get("instances", []) as Array
		if instances.is_empty():
			continue
		var candidate_id := "%s#001" % logical_id
		var candidate: Dictionary = catalog.call("resolve_card", candidate_id) as Dictionary
		if not free_copy and not _can_pay(player_id, candidate):
			continue
		if _skill_target_options(player_id, candidate).is_empty():
			continue
		result.append(candidate_id)
	return result


func _last_resort_options(player_id: int) -> Array[String]:
	var result: Array[String] = []
	var profession: String = String(players[player_id].get("profession", "neutral"))
	for definition_value: Variant in catalog.get("staged_cards") as Array:
		var definition: Dictionary = definition_value as Dictionary
		if String(definition.get("category", "")) != "attack":
			continue
		if not ["neutral", profession].has(String(definition.get("profession", "neutral"))):
			continue
		var instances: Array = definition.get("instances", []) as Array
		if not instances.is_empty():
			result.append("%s#001" % String(definition.get("id", "")))
	return result


func _resolve_last_resort_discard(player_id: int) -> void:
	var active: Dictionary = players[player_id]
	for zone: String in ["hand", "purchased_hand"]:
		var cards: Array = active.get(zone, []) as Array
		while not cards.is_empty():
			var discarded_card: String = String(cards.pop_back())
			(active.get("discard", []) as Array).append(discarded_card)
			_record_discard_origin(player_id, discarded_card)
		active[zone] = cards
	players[player_id] = active
	_emit("cards_discarded", {"player_id": player_id, "reason_id": "card:last_resort_new", "message": "%s 弃置所有手牌发动【破釜沉舟】。" % String(active.get("name", ""))})


func _begin_last_resort_target_choice(player_id: int, copied_card_id: String) -> void:
	var definition: Dictionary = catalog.call("resolve_card", copied_card_id) as Dictionary
	var targets: Array = _skill_target_options(player_id, definition)
	if targets.size() == 1:
		_resolve_last_resort(player_id, copied_card_id, int(targets[0]))
		return
	if not targets.is_empty():
		_request_skill_choice(player_id, "last_resort_target", "last_resort_new", targets, {"copied_card_id": copied_card_id})


func _resolve_last_resort(player_id: int, copied_card_id: String, target_id: int) -> void:
	var definition: Dictionary = catalog.call("resolve_card", copied_card_id) as Dictionary
	if definition.is_empty():
		return
	_emit("card_played", {"player_id": player_id, "target_id": target_id, "card_id": "last_resort_new", "copied_card_id": copied_card_id, "message": "%s 将【破釜沉舟】视为【%s】免费使用。" % [String(players[player_id].get("name", "")), String(definition.get("name", copied_card_id))]})
	_open_response_or_resolve({"source_id": player_id, "target_id": target_id, "definition": definition, "category": "attack", "card_id": "", "damage_bonus": 0, "unanswerable": false})


func _resolve_balance(source_id: int, target_id: int) -> void:
	if target_id < 0 or target_id >= players.size() or not bool(players[target_id].get("alive", false)):
		return
	var source_count: int = _available_hand_count(source_id)
	var target_count: int = _available_hand_count(target_id)
	if target_count > source_count:
		_request_discard(target_id, target_count - source_count, "balance_new")
		_emit("balance_resolved", {"player_id": source_id, "target_id": target_id, "mode": "discard", "amount": target_count - source_count, "message": "【权衡】要求目标自行弃置%d张牌。" % (target_count - source_count)})
		return
	if target_count < source_count:
		_draw_profession_cards(target_id, source_count - target_count)
	_emit("balance_resolved", {"player_id": source_id, "target_id": target_id, "mode": "draw", "amount": maxi(0, source_count - target_count), "message": "【权衡】将目标手牌调整为%d张。" % source_count})


func _draw_profession_cards(player_id: int, amount: int) -> void:
	if amount <= 0:
		return
	var target: Dictionary = players[player_id]
	var profession_deck: Array[String] = _string_array(target.get("profession_deck", []))
	var profession_discard: Array[String] = _string_array(target.get("profession_discard", []))
	for _index: int in amount:
		if profession_deck.is_empty() and not profession_discard.is_empty():
			profession_deck = profession_discard.duplicate()
			profession_discard.clear()
			_shuffle_strings(profession_deck)
		if profession_deck.is_empty():
			break
		(target.get("hand", []) as Array).append(profession_deck.pop_back())
	target["profession_deck"] = profession_deck
	target["profession_discard"] = profession_discard
	players[player_id] = target


func _attack_hand_options(player_id: int) -> Array[String]:
	var result: Array[String] = [""]
	if player_id < 0 or player_id >= players.size():
		return result
	for card_value: Variant in players[player_id].get("hand", []) as Array:
		var card_id: String = String(card_value)
		if String((catalog.call("resolve_card", card_id) as Dictionary).get("category", "")) == "attack":
			result.append(card_id)
	return result


func _alive_enemy_ids(player_id: int) -> Array[int]:
	var result: Array[int] = []
	for target_id: int in players.size():
		if target_id != player_id and bool(players[target_id].get("alive", false)):
			result.append(target_id)
	return result


func _resolve_sleeve_arrow(owner_id: int, card_id: String, target_id: int) -> void:
	if owner_id < 0 or target_id < 0 or owner_id >= players.size() or target_id >= players.size():
		return
	if not _remove_first(players[owner_id].get("hand", []) as Array, card_id):
		return
	var definition: Dictionary = catalog.call("resolve_card", card_id) as Dictionary
	(players[owner_id].get("discard", []) as Array).append(card_id)
	_record_discard_origin(owner_id, card_id)
	_emit("sleeve_arrow_triggered", {"player_id": owner_id, "target_id": target_id, "card_id": card_id, "message": "【袖箭】免费无距离使用攻击牌。"})
	_open_response_or_resolve({"source_id": owner_id, "target_id": target_id, "definition": definition, "category": "attack", "card_id": card_id, "damage_bonus": 0, "unanswerable": false})


func _resolve_element_resonance(source_id: int, target_id: int, element_id: String) -> void:
	if target_id < 0 or target_id >= players.size() or not bool(players[target_id].get("alive", false)):
		return
	var kind: String = "lightning" if element_id == "lightning" else "fire" if element_id == "fire" else "normal"
	_deal_damage(target_id, 1, kind, source_id, false, {"single_target": true, "card_effect": true})
	_apply_status(target_id, element_id, 1, source_id)
	players[source_id]["match_flags"]["element_resonance_last"] = element_id
	_emit("element_resonance_resolved", {"player_id": source_id, "target_id": target_id, "element": element_id, "message": "【元素共鸣】造成1点伤害并施加对应状态。"})


func _crossfire_attack_value(card_id: String) -> int:
	if card_id.is_empty():
		return 0
	var definition: Dictionary = catalog.call("resolve_card", card_id) as Dictionary
	for effect_value: Variant in definition.get("effects", []) as Array:
		var effect: Dictionary = effect_value as Dictionary
		if String(effect.get("op", "")) == "damage":
			return int(effect.get("amount", 0))
	return 0


func _resolve_crossfire(source_id: int, target_id: int, source_card_id: String, target_card_id: String) -> void:
	if source_id < 0 or target_id < 0 or source_id >= players.size() or target_id >= players.size():
		return
	for entry: Dictionary in [{"player_id": source_id, "card_id": source_card_id}, {"player_id": target_id, "card_id": target_card_id}]:
		var card_id: String = String(entry.get("card_id", ""))
		var owner_id: int = int(entry.get("player_id", -1))
		if card_id.is_empty():
			continue
		if _remove_first(players[owner_id].get("hand", []) as Array, card_id):
			(players[owner_id].get("discard", []) as Array).append(card_id)
			_record_discard_origin(owner_id, card_id)
	var source_attack: int = _crossfire_attack_value(source_card_id)
	var target_attack: int = _crossfire_attack_value(target_card_id)
	if source_attack > target_attack:
		_deal_damage(target_id, 2, "normal", source_id, true, {"single_target": true, "card_effect": true})
	elif target_attack > source_attack:
		_deal_damage(source_id, 2, "normal", target_id, true, {"single_target": true, "card_effect": true})
	else:
		_deal_damage(source_id, 1, "normal", target_id, true, {"single_target": true, "card_effect": true})
		_deal_damage(target_id, 2, "normal", source_id, true, {"single_target": true, "card_effect": true})
	_emit("crossfire_resolved", {"player_id": source_id, "target_id": target_id, "source_card_id": source_card_id, "target_card_id": target_card_id, "source_attack": source_attack, "target_attack": target_attack, "message": "【交锋】双方比较攻击力：%d 对 %d。" % [source_attack, target_attack]})


func _resolve_swap(source_id: int, target_id: int, source_card_id: String, encoded_target: String) -> void:
	if source_id < 0 or target_id < 0 or source_id >= players.size() or target_id >= players.size():
		return
	var parts: PackedStringArray = encoded_target.split("|", false, 1)
	if parts.size() != 2:
		return
	var zone: String = String(parts[0])
	var target_card_id: String = String(parts[1])
	if not _remove_first(players[source_id].get("hand", []) as Array, source_card_id):
		return
	var removed_target := false
	if zone.begins_with("equipment:"):
		var slot: String = zone.trim_prefix("equipment:")
		if String((players[target_id].get("equipment", {}) as Dictionary).get(slot, "")) == target_card_id:
			_discard_equipment_slot(target_id, slot, "swap_new")
			_remove_first(players[target_id].get("discard", []) as Array, target_card_id)
			removed_target = true
	else:
		var target_zone: Array = players[target_id].get(zone, []) as Array
		removed_target = _remove_first(target_zone, target_card_id)
		players[target_id][zone] = target_zone
	if not removed_target:
		(players[source_id].get("hand", []) as Array).append(source_card_id)
		return
	(players[source_id].get("hand", []) as Array).append(target_card_id)
	(players[target_id].get("hand", []) as Array).append(source_card_id)
	_emit("swap_resolved", {"player_id": source_id, "target_id": target_id, "source_card_id": source_card_id, "target_card_id": target_card_id, "message": "%s 以【移花接木】交换了双方区域中的牌。" % String(players[source_id].get("name", ""))})


func _resolve_strange_face_self(player_id: int, attacker_id: int, card_id: String) -> void:
	if not _remove_first(players[player_id].get("hand", []) as Array, card_id):
		return
	(players[player_id].get("discard", []) as Array).append(card_id)
	_record_discard_origin(player_id, card_id)
	if attacker_id >= 0 and attacker_id < players.size() and not (players[attacker_id].get("hand", []) as Array).is_empty():
		_request_skill_choice(player_id, "strange_face_attacker_card", "strange_face_new", (players[attacker_id].get("hand", []) as Array).duplicate(), {"attacker_id": attacker_id})


func _resolve_strange_face_attacker(player_id: int, attacker_id: int, card_id: String) -> void:
	if attacker_id < 0 or attacker_id >= players.size() or not _remove_first(players[attacker_id].get("hand", []) as Array, card_id):
		return
	(players[attacker_id].get("discard", []) as Array).append(card_id)
	_record_discard_origin(attacker_id, card_id)
	_emit("strange_face_triggered", {"player_id": player_id, "target_id": attacker_id, "card_id": card_id, "message": "【诡面】以弃牌为代价弃置了伤害来源一张手牌。"})


func _resolve_consume(owner_id: int, gainer_id: int, consume_card_id: String, selected_card_id: String) -> void:
	if owner_id < 0 or gainer_id < 0 or owner_id >= players.size() or gainer_id >= players.size():
		return
	if not _remove_first(players[owner_id].get("hand", []) as Array, consume_card_id):
		return
	if not _remove_first(players[gainer_id].get("hand", []) as Array, selected_card_id):
		(players[owner_id].get("hand", []) as Array).append(consume_card_id)
		return
	(players[owner_id].get("discard", []) as Array).append(consume_card_id)
	_record_discard_origin(owner_id, consume_card_id)
	(players[owner_id].get("hand", []) as Array).append(selected_card_id)
	_emit("consume_resolved", {"player_id": owner_id, "target_id": gainer_id, "card_id": selected_card_id, "message": "【蚕食】获得了对方刚获得后的1张手牌。"})


func _begin_endgame_target_choice(player_id: int, copied_card_id: String, request: Dictionary) -> void:
	var definition: Dictionary = catalog.call("resolve_card", copied_card_id) as Dictionary
	var targets := _skill_target_options(player_id, definition)
	if targets.is_empty():
		return
	if targets.size() == 1:
		_resolve_endgame_copy(player_id, String(request.get("physical_card_id", "")), copied_card_id, int(targets[0]), bool(request.get("was_last_card", false)))
		return
	_request_skill_choice(player_id, "endgame_target", "endgame_new", targets, {
		"physical_card_id": String(request.get("physical_card_id", "")),
		"copied_card_id": copied_card_id,
		"was_last_card": bool(request.get("was_last_card", false))
	})


func _resolve_endgame_copy(player_id: int, physical_card_id: String, copied_card_id: String, target_id: int, was_last_card: bool) -> void:
	var definition: Dictionary = catalog.call("resolve_card", copied_card_id) as Dictionary
	if definition.is_empty():
		return
	var active: Dictionary = players[player_id]
	if not _remove_first(active.get("hand", []) as Array, physical_card_id):
		_remove_first(active.get("purchased_hand", []) as Array, physical_card_id)
	players[player_id] = active
	if not was_last_card:
		_pay_cost(player_id, definition)
	definition = definition.duplicate(true)
	definition["copied_by_endgame"] = copied_card_id
	if String(definition.get("category", "")) == "equipment":
		_equip(player_id, physical_card_id, definition)
		_record_public_card(player_id, physical_card_id, player_id, "equipment")
		_emit("card_played", {"player_id": player_id, "card_id": physical_card_id, "copied_card_id": copied_card_id, "message": "%s 将【终局】当作【%s】装备。" % [String(players[player_id].get("name", "")), String(definition.get("name", copied_card_id))]})
		return
	(players[player_id].get("discard", []) as Array).append(physical_card_id)
	_record_discard_origin(player_id, physical_card_id)
	_record_public_card(player_id, physical_card_id, target_id, "card")
	_emit("card_played", {"player_id": player_id, "target_id": target_id, "card_id": physical_card_id, "copied_card_id": copied_card_id, "message": "%s 将【终局】当作【%s】使用。" % [String(players[player_id].get("name", "")), String(definition.get("name", copied_card_id))]})
	_open_response_or_resolve({"source_id": player_id, "target_id": target_id, "definition": definition, "category": String(definition.get("category", "")), "card_id": physical_card_id, "damage_bonus": 0, "unanswerable": bool(definition.get("unanswerable", false))})


func _barrier_break_options(target_id: int) -> Array[String]:
	var result: Array[String] = []
	for zone_name: String in ["hand", "purchased_hand"]:
		for card_value: Variant in players[target_id].get(zone_name, []) as Array:
			result.append("%s|%s" % [zone_name, String(card_value)])
	for slot: String in ["weapon", "armor", "accessory"]:
		var card_id := String((players[target_id].get("equipment", {}) as Dictionary).get(slot, ""))
		if not card_id.is_empty():
			result.append("equipment:%s|%s" % [slot, card_id])
	return result


func _begin_barrier_break(player_id: int, physical_card_id: String, target_id: int, definition: Dictionary) -> void:
	var active: Dictionary = players[player_id]
	if not _remove_first(active.get("hand", []) as Array, physical_card_id):
		_remove_first(active.get("purchased_hand", []) as Array, physical_card_id)
	players[player_id] = active
	_pay_cost(player_id, definition)
	(players[player_id].get("discard", []) as Array).append(physical_card_id)
	_record_discard_origin(player_id, physical_card_id)
	_record_public_card(player_id, physical_card_id, target_id, "card")
	_emit("card_played", {"player_id": player_id, "target_id": target_id, "card_id": physical_card_id, "message": "%s 使用【壁垒拆除】，等待选择要弃置的牌。" % String(players[player_id].get("name", ""))})
	_request_skill_choice(player_id, "barrier_break_card", "barrier_break_new", _barrier_break_options(target_id), {"target_id": target_id})


func _resolve_barrier_break(player_id: int, target_id: int, encoded_selection: String) -> void:
	var parts := encoded_selection.split("|", false, 1)
	if parts.size() != 2:
		return
	var zone := String(parts[0])
	var card_id := String(parts[1])
	if zone.begins_with("equipment:"):
		_discard_equipment_slot(target_id, zone.trim_prefix("equipment:"), "barrier_break_new")
	else:
		var cards: Array = players[target_id].get(zone, []) as Array
		if not _remove_first(cards, card_id):
			return
		players[target_id][zone] = cards
		(players[target_id].get("discard", []) as Array).append(card_id)
		_record_discard_origin(target_id, card_id)
	_emit("card_zone_discarded", {"player_id": player_id, "target_id": target_id, "card_id": card_id, "zone": zone, "message": "【壁垒拆除】弃置了%s区域内的【%s】。" % [String(players[target_id].get("name", "")), String((catalog.call("resolve_card", card_id) as Dictionary).get("name", card_id))]})


func _gain_flash(player_id: int, amount: int = 1, source_id: String = "shya_flash") -> void:
	if player_id < 0 or player_id >= players.size() or not bool(players[player_id].get("alive", false)):
		return
	players[player_id]["flash"] = maxi(0, int(players[player_id].get("flash", 0)) + amount)
	_emit("flash_changed", {"player_id": player_id, "amount": amount, "flash": int(players[player_id].get("flash", 0)), "source_id": source_id, "message": "%s 获得%d个闪光，当前%d个。" % [String(players[player_id].get("name", "")), amount, int(players[player_id].get("flash", 0))]})


func _available_shya_negater(ignored_source_id: int = -1) -> int:
	var total_flash := 0
	for player_state: Dictionary in players:
		if bool(player_state.get("alive", false)):
			total_flash += int(player_state.get("flash", 0))
	if total_flash < 2:
		return -1
	for player_id: int in players.size():
		if player_id != ignored_source_id and String(players[player_id].get("character_id", "")) == "shya" and bool(players[player_id].get("alive", false)) and not bool((players[player_id].get("flags", {}) as Dictionary).get("shya_flash_negate_used", false)):
			return player_id
	return -1


func _consume_two_flashes(shya_id: int) -> void:
	var remaining := 2
	var order: Array[int] = [shya_id]
	for player_id: int in players.size():
		if player_id != shya_id:
			order.append(player_id)
	for player_id: int in order:
		if remaining <= 0:
			break
		var removed := mini(remaining, int(players[player_id].get("flash", 0)))
		if removed <= 0:
			continue
		players[player_id]["flash"] = int(players[player_id].get("flash", 0)) - removed
		remaining -= removed
		_emit("flash_changed", {"player_id": player_id, "amount": -removed, "flash": int(players[player_id].get("flash", 0)), "source_id": "shya_flash_negate", "message": "%s 移除%d个闪光。" % [String(players[player_id].get("name", "")), removed]})


func _offer_shya_break(source_id: int, target_id: int) -> void:
	if source_id < 0 or target_id < 0 or source_id >= players.size() or target_id >= players.size():
		return
	if String(players[source_id].get("character_id", "")) != "shya" or not bool(players[target_id].get("alive", false)):
		return
	var flash_amount := int(players[target_id].get("flash", 0))
	if flash_amount <= 0:
		return
	_request_skill_choice(source_id, "shya_break_offer", "shya_break_flash", ["use", "skip"], {"target_id": target_id, "flash_amount": flash_amount})


func _begin_shya_break_consequence(source_id: int, target_id: int, flash_amount: int) -> void:
	if not bool(players[target_id].get("alive", false)) or flash_amount <= 0:
		return
	players[target_id]["flash"] = maxi(0, int(players[target_id].get("flash", 0)) - flash_amount)
	var options: Array[String] = ["damage"]
	if (players[target_id].get("hand", []) as Array).size() >= flash_amount:
		options.push_front("discard")
	_emit("flash_changed", {"player_id": target_id, "amount": -flash_amount, "flash": int(players[target_id].get("flash", 0)), "source_id": "shya_break_flash", "message": "%s 被移除%d个闪光。" % [String(players[target_id].get("name", "")), flash_amount]})
	_request_skill_choice(target_id, "shya_break_consequence", "shya_break_flash", options, {"source_id": source_id, "flash_amount": flash_amount})


func _resolve_k_strategy(player_id: int, card_id: String, target_id: int, resolution_count: int, medium_cards: Array = []) -> void:
	var definition: Dictionary = catalog.call("resolve_card", card_id) as Dictionary
	if definition.is_empty():
		return
	definition["cost"] = {"stamina": 0, "mana": 0}
	var profession := String(definition.get("profession", "neutral"))
	var uses: Dictionary = players[player_id].get("skill_match_uses", {}) as Dictionary
	uses["k_strategy:%s" % profession] = 1
	players[player_id]["skill_match_uses"] = uses
	players[player_id]["last_card_id"] = ""
	players[player_id]["last_strategy_record"] = {
		"card_id": card_id,
		"medium_cards": medium_cards.duplicate(),
		"resolution_count": resolution_count
	}
	_emit("skill_choice_resolved", {"player_id": player_id, "skill_id": "k_strategy", "card_id": card_id, "resolution_count": resolution_count, "message": "【奇策】将整手牌视为【%s】，结算%d次。" % [String(definition.get("name", card_id)), resolution_count]})
	for _index: int in resolution_count:
		_apply_effects(player_id, target_id, definition.get("effects", []) as Array, "奇异", 0, _definition_range(player_id, definition), 0, target_id < 0)
		if not pending_discard.is_empty() or not bool(players[player_id].get("alive", false)):
			break


func _begin_maddy_explore(player_id: int) -> void:
	var position: Vector2i = players[player_id].get("position", Vector2i.ZERO) as Vector2i
	var location_kind := tile_kind(position)
	if location_kind == "event":
		# Event cancellation needs a pending-event interception point; do not silently substitute normal-tile rewards.
		_request_skill_choice(player_id, "maddy_explore_choice", "maddy_explore", ["draw_three"], {"location_kind": location_kind, "event_cancel_provisional": true})
		return
	var wealth_bonus := 2 if location_kind == "wealth" else 0
	_request_skill_choice(player_id, "maddy_explore_choice", "maddy_explore", ["heal", "coins", "draw"], {"location_kind": location_kind, "wealth_bonus": wealth_bonus})


func _resolve_maddy_explore(player_id: int, choice: String, request: Dictionary) -> void:
	match choice:
		"heal":
			_heal(player_id, 1)
		"coins":
			_change_coins(player_id, 2)
		"draw":
			_draw_cards(player_id, 2)
		"draw_three":
			_draw_cards(player_id, 3)
	var wealth_bonus := int(request.get("wealth_bonus", 0))
	if wealth_bonus > 0:
		_change_coins(player_id, wealth_bonus)
	_emit("skill_effect_resolved", {"player_id": player_id, "skill_id": "maddy_explore", "choice": choice, "wealth_bonus": wealth_bonus, "location_kind": String(request.get("location_kind", "normal")), "provisional": bool(request.get("event_cancel_provisional", false)), "message": "Maddy 通过【勘探】获得%s。" % {"heal": "1点生命", "coins": "2枚金币", "draw": "2张牌", "draw_three": "3张牌（事件抵消待实现）"}.get(choice, "奖励")})


func _begin_maddy_reclaim_selection(player_id: int, chosen_tiles: Array) -> void:
	if chosen_tiles.size() >= 3:
		var flags: Dictionary = players[player_id].get("flags", {}) as Dictionary
		flags.erase("maddy_reclaim_ready")
		flags["maddy_reclaim_pending_tiles"] = chosen_tiles.duplicate()
		players[player_id]["flags"] = flags
		var skill_uses: Dictionary = players[player_id].get("skill_uses", {}) as Dictionary
		skill_uses["maddy_reclamation"] = int(skill_uses.get("maddy_reclamation", 0)) + 1
		players[player_id]["skill_uses"] = skill_uses
		_emit("skill_effect_resolved", {"player_id": player_id, "skill_id": "maddy_reclaim", "tiles": chosen_tiles.duplicate(), "message": "Maddy 指定了3个格子；回合结束后它们将转化为神异格或财富格。"})
		return
	var candidates := _maddy_reclaim_candidates(player_id, chosen_tiles)
	if candidates.is_empty():
		_emit("skill_effect_resolved", {"player_id": player_id, "skill_id": "maddy_reclaim", "provisional": true, "message": "【开垦】没有足够的可指定普通格，本次不结算。"})
		return
	_request_skill_choice(player_id, "maddy_reclaim_tile", "maddy_reclaim", candidates, {"chosen_tiles": chosen_tiles.duplicate()})


func _maddy_reclaim_candidates(player_id: int, chosen_tiles: Array) -> Array[String]:
	var result: Array[String] = []
	for y: int in range(active_bounds().position.y, active_bounds().end.y):
		for x: int in range(active_bounds().position.x, active_bounds().end.x):
			var position := Vector2i(x, y)
			var key := _tile_key(position)
			if chosen_tiles.has(key) or tile_kind(position) != "normal" or _is_occupied(position, player_id):
				continue
			result.append(key)
	return result


func _finish_maddy_reclaim(player_id: int) -> void:
	if String(players[player_id].get("character_id", "")) != "maddy":
		return
	var flags: Dictionary = players[player_id].get("flags", {}) as Dictionary
	var pending_tiles: Array = flags.get("maddy_reclaim_pending_tiles", []) as Array
	if pending_tiles.is_empty():
		return
	var match_flags: Dictionary = players[player_id].get("match_flags", {}) as Dictionary
	var reclaimed_tiles: Array = match_flags.get("maddy_reclaimed_tiles", []) as Array
	var resolved_tiles: Array[String] = []
	for tile_value: Variant in pending_tiles:
		var position := _tile_key_to_position(String(tile_value))
		var tile_key := _tile_key(position)
		if not active_bounds().has_point(position):
			continue
		# A later selection never overwrites existing special or spent terrain.
		if tile_kind(position) != "normal":
			continue
		if rng.randi_range(0, 1) == 0:
			wealth_tiles.append(position)
		else:
			event_tiles.append(position)
		if not reclaimed_tiles.has(tile_key):
			reclaimed_tiles.append(tile_key)
		resolved_tiles.append(tile_key)
	flags.erase("maddy_reclaim_pending_tiles")
	players[player_id]["flags"] = flags
	match_flags["maddy_reclaimed_tiles"] = reclaimed_tiles
	players[player_id]["match_flags"] = match_flags
	_emit("terrain_reclaimed", {"player_id": player_id, "skill_id": "maddy_reclaim", "tiles": resolved_tiles, "message": "Maddy 的【开垦】将%d个格子转化为神异格或财富格。" % resolved_tiles.size()})


func _resolve_na1_foresight_draw(player_id: int, skipped: int, request: Dictionary) -> void:
	var draw_amount := int(request.get("draw_amount", 0))
	skipped = clampi(skipped, 0, draw_amount)
	_draw_cards(player_id, draw_amount - skipped)
	if skipped > 0:
		_change_coins(player_id, skipped)
	_emit("skill_choice_resolved", {"player_id": player_id, "skill_id": "na1_foresight", "skipped": skipped, "draw_amount": draw_amount - skipped, "message": "Na1 发动【远识】，少摸%d张并获得%d枚金币。" % [skipped, skipped]})
	_emit("turn_started", {"player_id": player_id, "message": "%s 开始回合。" % String(players[player_id].get("name", ""))})


func _resolve_k_brain_recovery(player_id: int, selection: String, request: Dictionary) -> void:
	var record: Dictionary = request.get("strategy_record", {}) as Dictionary
	if selection == "medium":
		var recovered: Array[String] = []
		for card_value: Variant in record.get("medium_cards", []) as Array:
			var card_id := String(card_value)
			if _recover_specific_card(player_id, card_id):
				recovered.append(card_id)
		_emit("cards_recovered", {"player_id": player_id, "card_ids": recovered, "source_id": "k_brain", "message": "K 通过【巨脑】取回上次【奇策】弃置的%d张媒介牌。" % recovered.size()})
	else:
		var virtual_card_id := String(record.get("card_id", ""))
		if not virtual_card_id.is_empty():
			(players[player_id].get("hand", []) as Array).append(virtual_card_id)
			var definition: Dictionary = catalog.call("resolve_card", virtual_card_id) as Dictionary
			_emit("card_recovered", {"player_id": player_id, "card_id": virtual_card_id, "source_id": "k_brain", "message": "K 通过【巨脑】获得上次【奇策】模拟的【%s】。" % String(definition.get("name", virtual_card_id))})
	players[player_id]["last_strategy_record"] = {}
	_apply_k_brain_followups(player_id)


func _apply_k_brain_followups(player_id: int) -> void:
	_apply_modifier(player_id, "repeat_next_card", 1)
	_apply_modifier(player_id, "free_cast", 1)
	var flags: Dictionary = players[player_id].get("flags", {}) as Dictionary
	flags["cannot_deal_damage"] = true
	players[player_id]["flags"] = flags
	_emit("skill_effect_resolved", {"player_id": player_id, "skill_id": "k_brain", "message": "【巨脑】已结算递归、回响与祷告：下张牌免费并额外结算，K本回合无法造成伤害。"})


func _resolve_ginger_power(player_id: int, target_id: int) -> void:
	var definition: Dictionary = catalog.call("resolve_card", "berserker_charge_new#001") as Dictionary
	var before := int(players[target_id].get("health", 0))
	_apply_effects(player_id, target_id, definition.get("effects", []) as Array, "attack", 0, 1)
	if before > int(players[target_id].get("health", 0)) and bool(players[player_id].get("alive", false)):
		_request_skill_choice(player_id, "ginger_power_reward", "ginger_power", ["heal", "draw"])


func _begin_zc_frenzy(player_id: int) -> void:
	var categories: Array[String] = []
	var available_cards: Array = (players[player_id].get("hand", []) as Array).duplicate()
	available_cards.append_array(players[player_id].get("purchased_hand", []) as Array)
	for card_value: Variant in available_cards:
		var category := String((catalog.call("resolve_card", String(card_value)) as Dictionary).get("category", ""))
		if not category.is_empty() and not categories.has(category):
			categories.append(category)
	if categories.is_empty():
		return
	_request_skill_choice(player_id, "zc_frenzy_category", "zc_frenzy", categories)


func _resolve_zc_frenzy_category(player_id: int, category: String) -> void:
	var active: Dictionary = players[player_id]
	var discarded: Array[String] = []
	for zone_name: String in ["hand", "purchased_hand"]:
		var zone: Array = active.get(zone_name, []) as Array
		for index: int in range(zone.size() - 1, -1, -1):
			var card_id := String(zone[index])
			var definition: Dictionary = catalog.call("resolve_card", card_id) as Dictionary
			if String(definition.get("category", "")) == category:
				discarded.push_front(card_id)
				zone.remove_at(index)
		active[zone_name] = zone
	(active.get("discard", []) as Array).append_array(discarded)
	players[player_id] = active
	for card_id: String in discarded:
		_record_discard_origin(player_id, card_id)
	_emit("cards_discarded", {"player_id": player_id, "card_ids": discarded, "reason_id": "skill:zc_frenzy", "message": "Z&C 为【狂极】弃置了全部%s牌（%d张）。" % [category, discarded.size()]})
	var targets := _zc_frenzy_targets(player_id)
	if targets.is_empty():
		_emit("skill_resolution_failed", {"player_id": player_id, "skill_id": "zc_frenzy", "message": "【狂极】没有可选目标，结算结束。"})
		return
	_request_skill_choice(player_id, "zc_frenzy_target", "zc_frenzy", targets)


func _resolve_zc_frenzy_target(player_id: int, target_id: int) -> void:
	var definition: Dictionary = catalog.call("resolve_card", "poisoned_strike_new#001") as Dictionary
	var action: Dictionary = {
		"source_id": player_id,
		"target_id": target_id,
		"definition": definition,
		"category": "attack",
		"card_id": "",
		"damage_bonus": 0,
		"unanswerable": false,
		"zc_frenzy": true,
		"zc_frenzy_owner": player_id,
		"target_health_before": int(players[target_id].get("health", 0))
	}
	if String(definition.get("category", "")) == "attack" and target_id >= 0 and target_id < players.size() and bool((players[target_id].get("flags", {}) as Dictionary).get("counterstrike_ready", false)):
		var counter_flags: Dictionary = players[target_id].get("flags", {}) as Dictionary
		counter_flags.erase("counterstrike_ready")
		players[target_id]["flags"] = counter_flags
		action["counterstrike_reflected"] = true
		action["counterstrike_owner"] = target_id
		action["unanswerable"] = true
	_emit("skill_used", {"player_id": player_id, "target_id": target_id, "skill_id": "zc_frenzy", "message": "Z&C 发动【狂极】，视为无消耗、无距离使用【带毒刺击】。"})
	_open_response_or_resolve(action)


func _zc_frenzy_targets(player_id: int) -> Array[int]:
	var result: Array[int] = []
	var hit_targets: Array = ((players[player_id].get("flags", {}) as Dictionary).get("zc_frenzy_hit_targets", []) as Array)
	for target_id: int in players.size():
		if target_id != player_id and bool(players[target_id].get("alive", false)) and not hit_targets.has(target_id):
			result.append(target_id)
	return result


func replay_document() -> Dictionary:
	var roster: Array[String] = []
	for player_state: Dictionary in players:
		roster.append(String(player_state.get("character_id", "")))
	return {
		"version": 1,
		"content_version": int(catalog.get("version")),
		"rules_version": int(rules.get("version", 1)),
		"seed": seed,
		"roster": roster,
		"commands": command_log.duplicate(true)
	}


func deterministic_snapshot() -> Dictionary:
	var player_states: Array[Dictionary] = []
	for player_state: Dictionary in players:
		player_states.append({
			"id": int(player_state["id"]),
			"health": int(player_state["health"]),
			"stamina": int(player_state.get("stamina", 0)),
			"mana": int(player_state.get("mana", 0)),
			"armor": int(player_state["armor"]),
			"coins": int(player_state["coins"]),
			"profession": String(player_state.get("profession", "")),
			"professions": (player_state.get("professions", []) as Array).duplicate(),
			"position": _position_payload(player_state["position"] as Vector2i),
			"hand": (player_state["hand"] as Array).duplicate(),
			"purchased_hand": (player_state.get("purchased_hand", []) as Array).duplicate(),
			"deck": (player_state["deck"] as Array).duplicate(),
			"discard": (player_state["discard"] as Array).duplicate(),
			"common_deck": (player_state.get("common_deck", []) as Array).duplicate(),
			"profession_deck": (player_state.get("profession_deck", []) as Array).duplicate(),
			"common_discard": (player_state.get("common_discard", []) as Array).duplicate(),
			"profession_discard": (player_state.get("profession_discard", []) as Array).duplicate(),
			"statuses": (player_state["statuses"] as Dictionary).duplicate(true),
			"modifiers": (player_state.get("modifiers", {}) as Dictionary).duplicate(true),
			"equipment": (player_state.get("equipment", {}) as Dictionary).duplicate(true),
			"equipment_copies": (player_state.get("equipment_copies", {}) as Dictionary).duplicate(true),
			"equipment_durability": (player_state.get("equipment_durability", {}) as Dictionary).duplicate(true),
			"flags": (player_state.get("flags", {}) as Dictionary).duplicate(true),
			"transformed_cards": (player_state.get("transformed_cards", {}) as Dictionary).duplicate(true),
			"skills_used": (player_state.get("skills_used", {}) as Dictionary).duplicate(),
			"skill_uses": (player_state.get("skill_uses", {}) as Dictionary).duplicate(),
			"skill_match_uses": (player_state.get("skill_match_uses", {}) as Dictionary).duplicate(),
			"turn_healing": int(player_state.get("turn_healing", 0)),
			"turn_eliminations": int(player_state.get("turn_eliminations", 0)),
			"active_breakthroughs": (player_state.get("active_breakthroughs", {}) as Dictionary).duplicate(true),
			"breakthrough_losses": (player_state.get("breakthrough_losses", {}) as Dictionary).duplicate(true),
			"last_card_id": String(player_state.get("last_card_id", "")),
			"last_action_direction": (player_state.get("last_action_direction", []) as Array).duplicate(),
			"last_strategy_record": (player_state.get("last_strategy_record", {}) as Dictionary).duplicate(true),
			"flash": int(player_state.get("flash", 0)),
			"turn_commands": int(player_state.get("turn_commands", 0)),
			"alive": bool(player_state["alive"])
		})
	return {
		"round": completed_rounds,
		"collapse": collapse_count,
		"active": active_player_index,
		"market": market.duplicate(),
		"metrics": match_metrics.duplicate(),
		"players": player_states,
		"finished": finished,
		"winner": winner_id,
		"win_reason_id": win_reason_id,
		"pending_discard": pending_discard.duplicate(true),
		"pending_skill_discard": pending_skill_discard.duplicate(true),
		"pending_skill_choice": pending_skill_choice.duplicate(true),
		"pending_action": pending_action.duplicate(true),
		"pending_event": pending_event.duplicate(true),
		"profession_choice_pending": profession_choice_pending,
		"poison_mists": _poison_mist_snapshot(),
		"destroyed_tiles": destroyed_tiles.duplicate(true),
		"played_history": _public_play_history_snapshot()
	}


func summary() -> String:
	if finished:
		var winner: Dictionary = player(winner_id)
		return "对局结束 · %s 获胜 · %s" % [String(winner.get("name", "未知")), win_reason]
	var pressure_bonus: int = _duel_pressure_bonus()
	var pressure_text: String = " · 决胜单体伤害 +%d" % pressure_bonus if pressure_bonus > 0 else ""
	return "第 %d 轮 · %s · 移动 %d · 存活 %d/4 · 棋盘 %dx%d%s" % [
		completed_rounds + 1,
		String(current_player().get("name", "")),
		int(current_player().get("moves_remaining", 0)),
		_alive_player_ids().size(),
		active_bounds().size.x,
		active_bounds().size.y,
		pressure_text
	]


func _validate_command(command: Dictionary) -> String:
	if finished:
		return "对局已经结束。"
	var actor_id: int = int(command.get("actor_id", -1))
	if actor_id < 0 or actor_id >= players.size():
		return "命令包含无效玩家。"
	if not bool(players[actor_id].get("alive", false)):
		return "被击败的玩家不能行动。"
	if not pending_skill_discard.is_empty():
		if String(command.get("type", "")) != MatchCommandScript.SKILL_DISCARD or actor_id != int(pending_skill_discard.get("player_id", -1)):
			return "请先完成技能弃牌选择。"
		var skill_payload: Dictionary = command.get("payload", {}) as Dictionary
		if String(skill_payload.get("request_id", "")) != String(pending_skill_discard.get("request_id", "")):
			return "技能弃牌请求已经失效。"
		return _validate_skill_discard_selection(actor_id, skill_payload.get("card_ids", []) as Array)
	if not pending_skill_choice.is_empty():
		if String(command.get("type", "")) != MatchCommandScript.SKILL_CHOICE or actor_id != int(pending_skill_choice.get("player_id", -1)):
			return "请先完成技能选择。"
		var choice_payload: Dictionary = command.get("payload", {}) as Dictionary
		if String(choice_payload.get("request_id", "")) != String(pending_skill_choice.get("request_id", "")):
			return "技能选择请求已经失效。"
		if not (pending_skill_choice.get("options", []) as Array).has(choice_payload.get("value")):
			return "该技能选择不合法。"
		return ""
	if not pending_discard.is_empty():
		if String(command.get("type", "")) != MatchCommandScript.DISCARD_CARDS or actor_id != int(pending_discard.get("player_id", -1)):
			return "请先完成弃牌选择。"
		return _validate_discard_payload(command.get("payload", {}) as Dictionary)
	if profession_choice_pending:
		if String(command.get("type", "")) != MatchCommandScript.SWITCH_PROFESSION or actor_id != active_player_index:
			return "请先选择本回合职业。"
		var selected_profession: String = String((command.get("payload", {}) as Dictionary).get("profession", ""))
		if not selected_profession.is_empty() and not (players[actor_id].get("professions", []) as Array).has(selected_profession):
			return "只能选择该角色的主职业或副职业。"
		return ""
	var candidates: Array[Dictionary] = legal_commands(actor_id)
	for candidate: Dictionary in candidates:
		if candidate == command:
			return ""
	return "该命令在当前状态下不合法。"


func _create_players(roster: Array[String]) -> void:
	for seat: int in 4:
		var character_id: String = roster[seat] if seat < roster.size() else ["q", "ginger", "maddy", "signal"][seat]
		var definition: Dictionary = catalog.call("character", character_id) as Dictionary
		if definition.is_empty():
			definition = catalog.call("character", "q") as Dictionary
		var staged_definition: Dictionary = catalog.call("staged_character", character_id) as Dictionary
		var runtime_professions: Array = (staged_definition.get("professions", []) as Array).duplicate() if not staged_definition.is_empty() else (definition.get("professions", [String(definition.get("profession", "neutral"))]) as Array).duplicate()
		var runtime_profession := String(runtime_professions[0]) if not runtime_professions.is_empty() else String(definition.get("profession", "neutral"))
		var position: Vector2i = start_positions[seat] if seat < start_positions.size() else Vector2i(1 + (seat % 2) * 6, 1 + (seat / 2) * 6)
		var common_deck: Array[String] = _build_common_deck()
		var profession_deck: Array[String] = _build_profession_deck(runtime_profession)
		_shuffle_strings(common_deck)
		_shuffle_strings(profession_deck)
		var max_health: int = int(staged_definition.get("health", definition.get("health", 7)))
		var max_stamina: int = int(staged_definition.get("stamina", definition.get("stamina", 2)))
		var max_mana: int = int(staged_definition.get("mana", definition.get("mana", 2)))
		var player_state: Dictionary = {
			"id": seat,
			"character_id": String(definition.get("id", "q")),
			"name": String(definition.get("name", "Q")),
			"profession": runtime_profession,
			"card_pool_profession": runtime_profession,
			"professions": runtime_professions,
			"ai_persona": String(definition.get("ai_persona", "control")),
			"health": max_health,
			"max_health": max_health,
			"stamina": 0,
			"max_stamina": max_stamina,
			"mana": 0,
			"max_mana": max_mana,
			"armor": 0,
			"coins": 2 if character_id == "na1" else 0,
			"moves_remaining": 0,
			"market_bought": false,
			"position": position,
			"hand": [],
			"purchased_hand": [],
			"deck": [],
			"discard": [],
			"common_deck": common_deck,
			"profession_deck": profession_deck,
			"common_discard": [],
			"profession_discard": [],
			"statuses": {},
			"status_sources": {},
			"modifiers": {},
			"status_rounds": {},
			"equipment": {"weapon": "", "armor": "", "accessory": ""},
			"equipment_copies": {},
			"equipment_durability": {},
			"stats": {"damage_dealt": 0, "eliminations": 0},
			"flags": {},
			"skills_used": {},
			"skill_uses": {},
			"skill_match_uses": {},
			"turn_category_uses": {},
			"turn_healing": 0,
			"turn_eliminations": 0,
			"active_breakthroughs": {},
			"breakthrough_losses": {},
			"turn_commands": 0,
			"match_flags": {},
			"last_card_id": "",
			"last_action_direction": [],
			"last_strategy_record": {},
			"flash": 0,
			"public_card_history": [],
			"alive": true
		}
		players.append(player_state)
		_draw_cards(seat, int(rules.get("starting_hand", 4)))


func _setup_market() -> void:
	market_deck = catalog.call("market_card_ids") as Array[String]
	_shuffle_strings(market_deck)
	_replenish_market()


func _begin_turn() -> void:
	if finished:
		return
	if _alive_player_ids().is_empty():
		return
	var active: Dictionary = current_player()
	if not bool(active.get("alive", false)):
		_advance_turn_index()
		_begin_turn()
		return
	if _equipped_logical_id(active_player_index, "accessory") == "zero_day_bomb_new":
		var bomb_flags: Dictionary = active.get("match_flags", {}) as Dictionary
		var bomb_turns := int(bomb_flags.get("zero_day_bomb_turns", 2)) - 1
		bomb_flags["zero_day_bomb_turns"] = bomb_turns
		active["match_flags"] = bomb_flags
		players[active_player_index] = active
		if bomb_turns <= 0:
			_explode_zero_day_bomb(active_player_index)
			active = current_player()
	active["flags"] = {
		"spell_discount_used": false,
		"flash_guard_used": false,
		"bastion_used": false,
		"thorn_used": false,
		"shield_axe_used": false,
		"thunderbird_used": false,
		"gold_magnet_bonus_count": 0,
		"shadow_blade_turn_damage": 0,
		"hell_forge_used": false,
		"flash_attack_used": false,
		"shya_flash_negate_used": false
	}
	active["skills_used"] = {}
	active["skill_uses"] = {}
	active["turn_healing"] = 0
	active["turn_eliminations"] = 0
	active["turn_commands"] = 0
	active["turn_attack_count"] = 0
	var gaze_match_flags: Dictionary = active.get("match_flags", {}) as Dictionary
	if bool(gaze_match_flags.get("gaze_next_turn", false)):
		gaze_match_flags.erase("gaze_next_turn")
		gaze_match_flags["gaze_first_card_pending"] = true
		active["match_flags"] = gaze_match_flags
		_emit("turn_effect_started", {"player_id": active_player_index, "effect": "gaze", "message": "%s 受【凝视】影响，本回合首张非装备牌的体力与法力消耗各加1。" % String(active.get("name", ""))})
	players[active_player_index] = active
	var status_snapshot: Array[Dictionary] = _capture_tiebreak_snapshot(_alive_player_ids())
	_tick_start_statuses(active_player_index)
	_tick_poison_mists(active_player_index)
	_settle_eliminations(status_snapshot)
	if finished:
		return
	active = current_player()
	if not bool(active.get("alive", false)):
		if not finished:
			_advance_turn_index()
			_begin_turn()
		return
	active["stamina"] = int(active.get("max_stamina", 0))
	active["mana"] = int(active.get("max_mana", 0))
	active["moves_remaining"] = 1
	active["market_bought"] = false
	profession_choice_pending = true
	var statuses: Dictionary = active.get("statuses", {}) as Dictionary
	if int(statuses.get("paralyze", 0)) > 0:
		active["moves_remaining"] = 0
		statuses.erase("paralyze")
	active["statuses"] = statuses
	players[active_player_index] = active
	if String(active.get("character_id", "")) == "signal":
		var signal_flags: Dictionary = active.get("match_flags", {}) as Dictionary
		var signal_outside_bounds := not active_bounds().has_point(active.get("position", Vector2i.ZERO) as Vector2i)
		if signal_outside_bounds:
			var collapsed_turns := int(signal_flags.get("signal_collapsed_turns", 0)) + 1
			signal_flags["signal_collapsed_turns"] = collapsed_turns
			active["match_flags"] = signal_flags
			players[active_player_index] = active
			if collapsed_turns > 2 and not bool(signal_flags.get("signal_collapsed_confusion_applied", false)):
				signal_flags["signal_collapsed_confusion_applied"] = true
				active["match_flags"] = signal_flags
				players[active_player_index] = active
				_apply_status(active_player_index, "confusion", 1, -1)
				_emit("passive_triggered", {"player_id": active_player_index, "skill_id": "signal_mix", "message": "Signal 在崩坠区域连续停留超过两回合，获得1层混乱。"})
		else:
			signal_flags.erase("signal_collapsed_turns")
			signal_flags.erase("signal_collapsed_confusion_applied")
			active["match_flags"] = signal_flags
			players[active_player_index] = active
	_apply_start_turn_equipment(active_player_index)
	if String(active.get("character_id", "")) == "na1":
		# 金纵按当前金币数每回合结算，而不是一次性的金币里程碑。
		var gold_income := 1 if int(active.get("coins", 0)) >= 5 else 0
		if gold_income > 0:
			_change_coins(active_player_index, gold_income)
			_emit("passive_triggered", {"player_id": active_player_index, "skill_id": "na1_gold", "coins": gold_income, "message": "Na1 的【金纵】按当前金币获得%d枚金币。" % gold_income})
	_emit("profession_choice_requested", {"player_id": active_player_index, "message": "%s 选择本回合职业。" % String(active.get("name", ""))})


func _handle_switch_profession(payload: Dictionary) -> void:
	var active: Dictionary = players[active_player_index]
	var selected: String = String(payload.get("profession", ""))
	var converted: bool = not selected.is_empty() and selected != String(active.get("profession", ""))
	if converted:
		active["profession"] = selected
		var next_profession_deck := _build_profession_deck(selected)
		_shuffle_strings(next_profession_deck)
		active["profession_deck"] = next_profession_deck
		active["profession_discard"] = []
		active["card_pool_profession"] = selected
	players[active_player_index] = active
	profession_choice_pending = false
	var statuses: Dictionary = active.get("statuses", {}) as Dictionary
	var draw_amount: int = 3 if completed_rounds == 0 else draw_per_turn
	if converted:
		draw_amount = 2 if completed_rounds == 0 else maxi(0, draw_per_turn - 1)
	if int(statuses.get("confusion", 0)) > 0:
		draw_amount = maxi(0, draw_amount - 2)
		statuses.erase("confusion")
	active["statuses"] = statuses
	players[active_player_index] = active
	_emit("profession_switched", {"player_id": active_player_index, "profession": String(active.get("profession", "")), "converted": converted, "draw_amount": draw_amount, "message": "%s 本回合职业：%s，基础摸%d张牌。" % [String(active.get("name", "")), String(active.get("profession", "")), draw_amount]})
	if String(active.get("character_id", "")) == "na1":
		var skip_options: Array = []
		for skipped: int in range(draw_amount + 1):
			skip_options.append(skipped)
		_request_skill_choice(active_player_index, "na1_foresight_draw", "na1_foresight", skip_options, {"draw_amount": draw_amount})
		return
	_draw_cards(active_player_index, draw_amount + (1 if _equipped_logical_id(active_player_index, "accessory") == "secret_letter_new" else 0))
	active = players[active_player_index]
	_emit("turn_started", {"player_id": active_player_index, "message": "%s 开始回合。" % String(active.get("name", ""))})
	if String(active.get("character_id", "")) == "q":
		_request_skill_choice(active_player_index, "q_thunder_guard_offer", "q_thunder_guard", ["use", "skip"])


func _begin_q_thunder_guard(player_id: int, from_end_turn: bool = false) -> void:
	var active: Dictionary = players[player_id]
	var revealed: Array[Dictionary] = []
	var common_deck: Array[String] = _string_array(active.get("common_deck", []))
	var profession_deck: Array[String] = _string_array(active.get("profession_deck", []))
	var common_discard: Array[String] = _string_array(active.get("common_discard", []))
	var profession_discard: Array[String] = _string_array(active.get("profession_discard", []))
	for _index: int in 6:
		if common_deck.is_empty() and not common_discard.is_empty():
			common_deck = common_discard.duplicate()
			common_discard.clear()
			_shuffle_strings(common_deck)
		if profession_deck.is_empty() and not profession_discard.is_empty():
			profession_deck = profession_discard.duplicate()
			profession_discard.clear()
			_shuffle_strings(profession_deck)
		var use_profession := not profession_deck.is_empty() and (common_deck.is_empty() or rng.randi_range(0, 1) == 1)
		if use_profession:
			revealed.append({"card_id": profession_deck.pop_back(), "deck": "profession"})
		elif not common_deck.is_empty():
			revealed.append({"card_id": common_deck.pop_back(), "deck": "common"})
		else:
			break
	active["common_deck"] = common_deck
	active["profession_deck"] = profession_deck
	active["common_discard"] = common_discard
	active["profession_discard"] = profession_discard
	players[player_id] = active
	var categories: Array[String] = []
	for entry: Dictionary in revealed:
		var category := String((catalog.call("resolve_card", String(entry.get("card_id", ""))) as Dictionary).get("category", ""))
		if not category.is_empty() and not categories.has(category):
			categories.append(category)
	if categories.is_empty():
		categories.append("none")
	var category_counts: Dictionary = {}
	for entry: Dictionary in revealed:
		var revealed_category := String((catalog.call("resolve_card", String(entry.get("card_id", ""))) as Dictionary).get("category", "none"))
		category_counts[revealed_category] = int(category_counts.get(revealed_category, 0)) + 1
	_request_skill_choice(player_id, "q_thunder_guard_category", "q_thunder_guard", categories, {"revealed": revealed, "from_end_turn": from_end_turn})
	_emit("cards_revealed", {"player_id": player_id, "skill_id": "q_thunder_guard", "categories": category_counts, "message": "Q 的【雷佑】展示了牌堆顶%d张牌：%s。" % [revealed.size(), "、".join(categories)]})


func _resolve_q_thunder_guard_category(player_id: int, category: String, request: Dictionary) -> void:
	var active: Dictionary = players[player_id]
	var hand: Array = active.get("hand", []) as Array
	var common_return: Array[String] = []
	var profession_return: Array[String] = []
	var attack_marks: Dictionary = active.get("thunder_guard_attack_cards", {}) as Dictionary
	var strange_marks: Dictionary = active.get("thunder_guard_strange_cards", {}) as Dictionary
	for entry_value: Variant in request.get("revealed", []) as Array:
		var entry: Dictionary = entry_value as Dictionary
		var card_id := String(entry.get("card_id", ""))
		var definition: Dictionary = catalog.call("resolve_card", card_id) as Dictionary
		if String(definition.get("category", "")) == category:
			hand.append(card_id)
			if category == "attack":
				attack_marks[card_id] = true
			elif category == "奇异":
				strange_marks[card_id] = true
		elif String(entry.get("deck", "")) == "profession":
			profession_return.append(card_id)
		else:
			common_return.append(card_id)
	# Cards were drawn from the end. Re-appending in reverse restores their exact original order.
	for index: int in range(common_return.size() - 1, -1, -1):
		(active.get("common_deck", []) as Array).append(common_return[index])
	for index: int in range(profession_return.size() - 1, -1, -1):
		(active.get("profession_deck", []) as Array).append(profession_return[index])
	active["hand"] = hand
	active["thunder_guard_attack_cards"] = attack_marks
	active["thunder_guard_strange_cards"] = strange_marks
	if category == "defense" and not bool(request.get("from_end_turn", false)):
		active["q_thunder_guard_end_available"] = true
	players[player_id] = active
	profession_choice_pending = false
	_emit("skill_choice_resolved", {"player_id": player_id, "skill_id": "q_thunder_guard", "category": category, "message": "Q 获得展示牌中的全部%s牌，其余牌按原顺序放回。" % category})
	_emit("turn_started", {"player_id": player_id, "message": "%s 开始回合。" % String(active.get("name", ""))})


func _tick_start_statuses(player_id: int) -> void:
	var target: Dictionary = players[player_id]
	var statuses: Dictionary = target.get("statuses", {}) as Dictionary
	var status_sources: Dictionary = target.get("status_sources", {}) as Dictionary
	if int(statuses.get("bleed", 0)) > 0:
		_deal_damage(player_id, 1, "true", int(status_sources.get("bleed", -1)), false)
		var bleed_stacks: int = int(statuses.get("bleed", 0)) - 1
		if bleed_stacks > 0:
			statuses["bleed"] = bleed_stacks
		else:
			statuses.erase("bleed")
			status_sources.erase("bleed")
	if bool(players[player_id].get("alive", false)) and int(statuses.get("poison", 0)) > 0:
		_deal_damage(player_id, 1, "true", int(status_sources.get("poison", -1)), false)
	target = players[player_id]
	target["statuses"] = statuses
	target["status_sources"] = status_sources
	players[player_id] = target


func _tick_poison_mists(player_id: int) -> void:
	var active_mists: Array[Dictionary] = []
	var position: Vector2i = players[player_id].get("position", Vector2i.ZERO) as Vector2i
	for mist: Dictionary in poison_mists:
		if completed_rounds > int(mist.get("expires_after_round", -1)):
			continue
		active_mists.append(mist)
		var center: Vector2i = _payload_position(mist.get("center", []))
		if bool(players[player_id].get("alive", false)) and maxi(absi(position.x - center.x), absi(position.y - center.y)) <= 1:
			_apply_status(player_id, "poison", 1, int(mist.get("source_id", -1)))
			_emit("poison_mist_triggered", {"player_id": player_id, "source_id": int(mist.get("source_id", -1)), "center": _position_payload(center), "message": "%s 在毒雾中停留一回合，获得1层中毒。" % String(players[player_id].get("name", ""))})
	poison_mists = active_mists


func _poison_mist_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mist: Dictionary in poison_mists:
		result.append({"center": (mist.get("center", []) as Array).duplicate(), "source_id": int(mist.get("source_id", -1)), "expires_after_round": int(mist.get("expires_after_round", -1))})
	return result


func _legal_move_commands(actor_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var source: Vector2i = players[actor_id].get("position", Vector2i.ZERO) as Vector2i
	var max_range: int = _move_range(actor_id)
	var movement_bounds := Rect2i(Vector2i.ZERO, Vector2i(board_size, board_size)) if String(players[actor_id].get("character_id", "")) == "signal" else active_bounds()
	var ignores_obstacles := _equipped_logical_id(actor_id, "accessory") == "flying_shoes_new"
	var queue_positions: Array[Vector2i] = [source]
	var queue_paths: Array = [[]]
	var visited: Dictionary = {_tile_key(source): true}
	while not queue_positions.is_empty():
		var current: Vector2i = queue_positions.pop_front()
		var path: Array = queue_paths.pop_front() as Array
		if path.size() >= max_range:
			continue
		for direction: Vector2i in CARDINAL_DIRECTIONS:
			var next: Vector2i = current + direction
			var key: String = _tile_key(next)
			if visited.has(key) or not movement_bounds.has_point(next) or _blocked_by_guard_unit(actor_id, next) or (not ignores_obstacles and _is_occupied(next, actor_id)):
				continue
			visited[key] = true
			var next_path: Array = path.duplicate()
			next_path.append(_position_payload(next))
			queue_positions.append(next)
			queue_paths.append(next_path)
			if not _is_occupied(next, actor_id):
				result.append(MatchCommandScript.make(MatchCommandScript.MOVE, actor_id, {"path": next_path}))
	return result


func _legal_card_commands(actor_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var active: Dictionary = players[actor_id]
	var seen: Dictionary = {}
	var available_cards: Array = (active.get("hand", []) as Array).duplicate()
	available_cards.append_array(active.get("purchased_hand", []) as Array)
	for card_value: Variant in available_cards:
		var card_id: String = String(card_value)
		if seen.has(card_id):
			continue
		seen[card_id] = true
		var definition: Dictionary = _card_definition_for_player(actor_id, card_id)
		var category: String = String(definition.get("category", ""))
		var logical_id := String(catalog.call("logical_card_id", card_id))
		if ["heavenly_sense_new", "shrug_off_new"].has(logical_id) or category == "response" or not _can_pay(actor_id, definition):
			continue
		if _available_hand_count(actor_id) - 1 < int(definition.get("required_other_hand_cards", 0)):
			continue
		if logical_id == "barrier_break_new":
			for target_id: int in players.size():
				if target_id != actor_id and bool(players[target_id].get("alive", false)) and not _barrier_break_options(target_id).is_empty():
					result.append(MatchCommandScript.make(MatchCommandScript.PLAY_CARD, actor_id, {"card_id": card_id, "target_id": target_id}))
			continue
		if ["endgame_new", "endgame_ambitionist_new"].has(logical_id):
			if not _endgame_copy_options(actor_id, card_id).is_empty():
				result.append(MatchCommandScript.make(MatchCommandScript.PLAY_CARD, actor_id, {"card_id": card_id, "target_id": actor_id}))
			continue
		if logical_id == "hunt_new":
			for target_id: int in _enemies_in_range(actor_id, _definition_range(actor_id, definition)):
				if _hunt_destination(actor_id, target_id) != Vector2i.ZERO:
					result.append(MatchCommandScript.make(MatchCommandScript.PLAY_CARD, actor_id, {"card_id": card_id, "target_id": target_id}))
			continue
		if logical_id == "gold_panning_new":
			if not _gold_panning_options(actor_id).is_empty():
				result.append(MatchCommandScript.make(MatchCommandScript.PLAY_CARD, actor_id, {"card_id": card_id, "target_id": actor_id}))
			continue
		if logical_id == "suppress_new":
			for y: int in range(active_bounds().position.y, active_bounds().end.y):
				for x: int in range(active_bounds().position.x, active_bounds().end.x):
					var center := Vector2i(x, y)
					if tile_kind(center) != "collapsed":
						result.append(MatchCommandScript.make(MatchCommandScript.PLAY_CARD, actor_id, {"card_id": card_id, "position": _position_payload(center)}))
			continue
		if logical_id == "last_resort_new":
			if not _last_resort_options(actor_id).is_empty():
				result.append(MatchCommandScript.make(MatchCommandScript.PLAY_CARD, actor_id, {"card_id": card_id, "target_id": actor_id}))
			continue
		if logical_id == "swap_new":
			if _available_hand_count(actor_id) > 1:
				for target_id: int in _enemies_in_range(actor_id, _definition_range(actor_id, definition)):
					if not _barrier_break_options(target_id).is_empty():
						result.append(MatchCommandScript.make(MatchCommandScript.PLAY_CARD, actor_id, {"card_id": card_id, "target_id": target_id}))
			continue
		if category == "attack" and _equipped_logical_id(actor_id, "weapon") == "broad_axe_new":
			definition = definition.duplicate(true)
			definition["target"] = "all_enemies_in_range"
			definition["local_range"] = _move_range(actor_id)
		result.append_array(_target_commands(MatchCommandScript.PLAY_CARD, actor_id, card_id, definition))
	return result


func _legal_skill_commands(actor_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var character_id := String(players[actor_id].get("character_id", ""))
	var character_definition: Dictionary = catalog.call("character", character_id) as Dictionary
	var staged_character: Dictionary = catalog.call("staged_character", character_id) as Dictionary
	var seen_revised_skills: Dictionary = {}
	for skill_value: Variant in character_definition.get("skills", []) as Array:
		if not skill_value is Dictionary:
			continue
		var source_skill: Dictionary = skill_value as Dictionary
		var source_skill_id := String(source_skill.get("id", ""))
		var revised_skill_id := String(REVISED_SKILL_ALIASES.get(source_skill_id, source_skill_id))
		# Do not allow an unmapped legacy skill to leak through a staged character kit.
		if not staged_character.is_empty() and (catalog.call("staged_skill", character_id, revised_skill_id) as Dictionary).is_empty():
			continue
		if revised_skill_id == "q_thunder_guard" or revised_skill_id == "q_thunderstorm" or seen_revised_skills.has(revised_skill_id):
			continue
		seen_revised_skills[revised_skill_id] = true
		var skill: Dictionary = _skill_definition(actor_id, source_skill_id)
		if skill.is_empty() or not bool(skill.get("executable", true)):
			continue
		var skill_id: String = String(skill.get("id", ""))
		if skill_id == "k_strategy" and (_available_k_strategy_cards(actor_id).is_empty() or (players[actor_id].get("hand", []) as Array).is_empty()):
			continue
		if skill_id == "ginger_power" and _enemies_in_range(actor_id, 1).is_empty():
			continue
		if String(skill.get("revised_skill_id", skill_id)) == "zc_frenzy":
			var available_cards: Array = (players[actor_id].get("hand", []) as Array).duplicate()
			available_cards.append_array(players[actor_id].get("purchased_hand", []) as Array)
			if available_cards.is_empty() or _zc_frenzy_targets(actor_id).is_empty():
				continue
		var policy := skill_usage_policy(actor_id, skill_id)
		var uses_per_turn := int(policy.get("uses_per_turn", skill.get("uses_per_turn", 0)))
		var skill_uses := int((players[actor_id].get("skill_uses", {}) as Dictionary).get(skill_id, 0))
		if uses_per_turn > 0 and skill_uses >= uses_per_turn:
			continue
		var uses_per_profession_per_match := int(policy.get("uses_per_profession_per_match", 0))
		var match_key := _skill_match_usage_key(actor_id, skill_id)
		var match_uses := int((players[actor_id].get("skill_match_uses", {}) as Dictionary).get(match_key, 0))
		if uses_per_profession_per_match > 0 and match_uses >= uses_per_profession_per_match:
			continue
		if not _skill_discard_requirement_possible(actor_id, skill):
			continue
		for variant: String in _legal_skill_variants(actor_id, skill):
			result.append_array(_target_commands(MatchCommandScript.USE_SKILL, actor_id, skill_id, skill, {"variant": variant}))
	if _equipped_logical_id(actor_id, "weapon") == "dragon_slayer_new":
		var dragon_power: Dictionary = catalog.call("executable_staged_skill", "ginger", "ginger_power") as Dictionary
		if not dragon_power.is_empty() and _enemies_in_range(actor_id, 1).size() > 0:
			dragon_power["id"] = "ginger_power"
			dragon_power["revised_skill_id"] = "ginger_power"
			dragon_power["category"] = "skill"
			for variant: String in _legal_skill_variants(actor_id, dragon_power):
				result.append_array(_target_commands(MatchCommandScript.USE_SKILL, actor_id, "ginger_power", dragon_power, {"variant": variant}))
	var staged_hand_available := false
	for staged_card_value: Variant in players[actor_id].get("hand", []) as Array:
		if String(staged_card_value).find("#") >= 0:
			staged_hand_available = true
			break
	if String(players[actor_id].get("character_id", "")) == "q" and staged_hand_available:
		var staged_thunderstorm: Dictionary = _skill_definition(actor_id, "q_thunderstorm")
		var requirement: Dictionary = staged_thunderstorm.get("discard_requirement", {}) as Dictionary
		var thunderstorm_uses := int((players[actor_id].get("skill_uses", {}) as Dictionary).get("q_thunderstorm", 0))
		if thunderstorm_uses < 1 and not staged_thunderstorm.is_empty() and _rank_sum_selection_possible(players[actor_id].get("hand", []) as Array, int(requirement.get("rank_sum", 0)), int(requirement.get("minimum_cards", 1))):
			result.append_array(_target_commands(MatchCommandScript.USE_SKILL, actor_id, "q_thunderstorm", staged_thunderstorm, {"variant": "normal"}))
	return result


func skill_usage_policy(player_id: int, skill_id: String) -> Dictionary:
	if player_id < 0 or player_id >= players.size():
		return {}
	var character_id := String(players[player_id].get("character_id", ""))
	var revised_skill_id := String(REVISED_SKILL_ALIASES.get(skill_id, skill_id))
	var revised_skill: Dictionary = catalog.call("staged_skill", character_id, revised_skill_id) as Dictionary
	if revised_skill.is_empty():
		return {}
	var uses_per_turn := int(revised_skill.get("uses_per_turn", 0))
	if revised_skill_id == "q_thunderstorm" or revised_skill_id == "ginger_power":
		uses_per_turn = 1
	var used_this_turn := int((players[player_id].get("skill_uses", {}) as Dictionary).get(skill_id, 0))
	var uses_per_profession_per_match := int(revised_skill.get("uses_per_profession_per_match", 0))
	var match_key := _skill_match_usage_key(player_id, skill_id)
	var used_for_profession := int((players[player_id].get("skill_match_uses", {}) as Dictionary).get(match_key, 0))
	return {
		"revised_skill_id": revised_skill_id,
		"revised_name": String(revised_skill.get("name", skill_id)),
		"skill_type": String(revised_skill.get("skill_type", "standard")),
		"resource_cost": (revised_skill.get("resource_cost", {}) as Dictionary).duplicate(true),
		"has_exhaust": revised_skill.has("exhaust"),
		"breakthrough_goal": (revised_skill.get("breakthrough_goal", {}) as Dictionary).duplicate(true),
		"restore_lost_resources": bool(revised_skill.get("restore_lost_resources", false)),
		"source_text": String(revised_skill.get("source_text", "")),
		"executable": not _skill_definition(player_id, skill_id).is_empty(),
		"blocked_reason": "需要新版多步选牌界面" if _skill_definition(player_id, skill_id).is_empty() else "",
		"uses_per_turn": uses_per_turn,
		"used_this_turn": used_this_turn,
		"remaining_this_turn": maxi(0, uses_per_turn - used_this_turn) if uses_per_turn > 0 else -1,
		"uses_per_profession_per_match": uses_per_profession_per_match,
		"used_for_profession": used_for_profession,
		"remaining_for_profession": maxi(0, uses_per_profession_per_match - used_for_profession) if uses_per_profession_per_match > 0 else -1
	}


func _legal_skill_variants(player_id: int, skill: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if _can_pay_skill(player_id, skill, "normal"):
		result.append("normal")
	if skill.has("exhaust") and _can_pay_skill(player_id, skill, "exhaust"):
		result.append("exhaust")
	return result


func _skill_discard_requirement_possible(player_id: int, skill: Dictionary) -> bool:
	var requirement: Dictionary = skill.get("discard_requirement", {}) as Dictionary
	if requirement.is_empty():
		return true
	var hand: Array = players[player_id].get("hand", []) as Array
	if String(requirement.get("mode", "rank_sum")) == "count":
		return hand.size() >= int(requirement.get("count", 0))
	return _rank_sum_selection_possible(hand, int(requirement.get("rank_sum", 0)), int(requirement.get("minimum_cards", 1)))


func _can_pay_skill(player_id: int, skill: Dictionary, variant: String) -> bool:
	var player_state: Dictionary = players[player_id]
	if variant == "exhaust":
		return int(player_state.get("stamina", 0)) == int(player_state.get("max_stamina", 0)) \
			and int(player_state.get("mana", 0)) == int(player_state.get("max_mana", 0))
	var resource_cost: Dictionary = skill.get("resource_cost", {}) as Dictionary
	match String(resource_cost.get("mode", "fixed")):
		"all_mana":
			return int(player_state.get("mana", 0)) > 0
		"all_stamina":
			return int(player_state.get("stamina", 0)) > 0
	var cost: Dictionary = skill.get("cost", {}) as Dictionary
	return int(player_state.get("stamina", 0)) >= int(cost.get("stamina", 0)) \
		and int(player_state.get("mana", 0)) >= int(cost.get("mana", 0))


func _pay_skill_resources(player_id: int, skill: Dictionary, variant: String) -> Dictionary:
	var player_state: Dictionary = players[player_id]
	var before_stamina := int(player_state.get("stamina", 0))
	var before_mana := int(player_state.get("mana", 0))
	if variant == "exhaust":
		player_state["stamina"] = 0
		player_state["mana"] = 0
	else:
		var resource_cost: Dictionary = skill.get("resource_cost", {}) as Dictionary
		match String(resource_cost.get("mode", "fixed")):
			"all_mana":
				player_state["mana"] = 0
			"all_stamina":
				player_state["stamina"] = 0
			_:
				var cost: Dictionary = skill.get("cost", {}) as Dictionary
				player_state["stamina"] = before_stamina - int(cost.get("stamina", 0))
				player_state["mana"] = before_mana - int(cost.get("mana", 0))
	players[player_id] = player_state
	var paid := {"stamina": before_stamina - int(player_state.get("stamina", 0)), "mana": before_mana - int(player_state.get("mana", 0))}
	if int(paid["stamina"]) > 0 or int(paid["mana"]) > 0:
		_emit("skill_resources_changed", {"player_id": player_id, "skill_id": String(skill.get("id", "")), "variant": variant, "paid": paid, "message": "%s 支付技能资源：体力%d、法力%d。" % [String(player_state.get("name", "")), int(paid["stamina"]), int(paid["mana"])]})
	return paid


func _skill_match_usage_key(player_id: int, skill_id: String) -> String:
	return "%s:%s" % [skill_id, String(players[player_id].get("profession", "neutral"))]


func _rank_sum_selection_possible(hand: Array, required_sum: int, minimum_count: int, index: int = 0, current_sum: int = 0, count: int = 0) -> bool:
	if current_sum == required_sum and count >= minimum_count:
		return true
	if current_sum >= required_sum or index >= hand.size():
		return false
	for next_index: int in range(index, hand.size()):
		var rank: int = int(catalog.call("staged_instance_rank", String(hand[next_index])))
		if rank <= 0:
			continue
		if _rank_sum_selection_possible(hand, required_sum, minimum_count, next_index + 1, current_sum + rank, count + 1):
			return true
	return false


func _target_commands(command_type: String, actor_id: int, definition_id: String, definition: Dictionary, extra_payload: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var payload_key: String = "card_id" if command_type == MatchCommandScript.PLAY_CARD else "skill_id"
	var base_payload: Dictionary = extra_payload.duplicate(true)
	base_payload[payload_key] = definition_id
	var target_rule: String = String(definition.get("target", "self"))
	if target_rule == "self":
		var self_payload := base_payload.duplicate(true)
		self_payload["target_id"] = actor_id
		result.append(MatchCommandScript.make(command_type, actor_id, self_payload))
		return result
	var range_limit: int = _definition_range(actor_id, definition)
	if target_rule == "enemy":
		var line_attack: bool = command_type == MatchCommandScript.PLAY_CARD and String(definition.get("category", "")) == "attack" and bool(equipped_definition(actor_id, "weapon").get("line_attack", false))
		var source_position: Vector2i = players[actor_id].get("position", Vector2i.ZERO) as Vector2i
		for target_id: int in players.size():
			var target_position: Vector2i = players[target_id].get("position", Vector2i.ZERO) as Vector2i
			var star_robe_protected := target_id != active_player_index and _equipped_logical_id(target_id, "armor") == "star_robe_new" and String(definition.get("category", "")) != "attack"
			var verdict_range := _equipped_logical_id(target_id, "accessory") == "verdict_new" and (players[actor_id].get("hand", []) as Array).size() > (players[target_id].get("hand", []) as Array).size()
			if target_id != actor_id and bool(players[target_id].get("alive", false)) and not star_robe_protected and (verdict_range or _distance(actor_id, target_id) <= range_limit) and (not line_attack or target_position.x == source_position.x or target_position.y == source_position.y):
				var enemy_payload := base_payload.duplicate(true)
				enemy_payload["target_id"] = target_id
				result.append(MatchCommandScript.make(command_type, actor_id, enemy_payload))
	elif target_rule == "all_enemies_in_range" and not _enemies_in_range(actor_id, range_limit).is_empty():
		var area_payload := base_payload.duplicate(true)
		area_payload["target_id"] = -1
		result.append(MatchCommandScript.make(command_type, actor_id, area_payload))
	elif target_rule == "alive":
		for target_id: int in players.size():
			if bool(players[target_id].get("alive", false)):
				var alive_payload := base_payload.duplicate(true)
				alive_payload["target_id"] = target_id
				result.append(MatchCommandScript.make(command_type, actor_id, alive_payload))
	elif target_rule == "empty_tile":
		for y: int in range(active_bounds().position.y, active_bounds().end.y):
			for x: int in range(active_bounds().position.x, active_bounds().end.x):
				var position := Vector2i(x, y)
				if tile_kind(position) != "collapsed" and not _is_occupied(position, -1):
					var tile_payload := base_payload.duplicate(true)
					tile_payload["target_id"] = actor_id
					tile_payload["position"] = _position_payload(position)
					result.append(MatchCommandScript.make(command_type, actor_id, tile_payload))
	elif target_rule == "map_tile":
		for y: int in range(active_bounds().position.y, active_bounds().end.y):
			for x: int in range(active_bounds().position.x, active_bounds().end.x):
				var position := Vector2i(x, y)
				if tile_kind(position) == "collapsed":
					continue
				var map_payload := base_payload.duplicate(true)
				map_payload["target_id"] = actor_id
				map_payload["position"] = _position_payload(position)
				result.append(MatchCommandScript.make(command_type, actor_id, map_payload))
	return result


func _legal_buy_commands(actor_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var active: Dictionary = players[actor_id]
	if bool(active.get("market_bought", false)):
		return result
	for market_index: int in market.size():
		var definition: Dictionary = catalog.call("resolve_card", market[market_index]) as Dictionary
		if int(active.get("coins", 0)) >= int(definition.get("price", 0)):
			result.append(MatchCommandScript.make(MatchCommandScript.BUY, actor_id, {"market_index": market_index}))
	return result


func _legal_equipment_commands(actor_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var weapon_id: String = _equipped_logical_id(actor_id, "weapon")
	if weapon_id == "cleaver_new":
		for direction_id: String in ["up", "right", "down", "left"]:
			result.append(MatchCommandScript.make(MatchCommandScript.ACTIVATE_EQUIPMENT, actor_id, {"equipment_id": weapon_id, "direction": direction_id}))
	if weapon_id == "crowbar_new" and bool((players[actor_id].get("flags", {}) as Dictionary).get("crowbar_ready", false)):
		for y: int in range(active_bounds().position.y, active_bounds().end.y):
			for x: int in range(active_bounds().position.x, active_bounds().end.x):
				var position := Vector2i(x, y)
				if tile_kind(position) != "collapsed":
					result.append(MatchCommandScript.make(MatchCommandScript.ACTIVATE_EQUIPMENT, actor_id, {"equipment_id": weapon_id, "position": _position_payload(position)}))
	return result


func _handle_activate_equipment(payload: Dictionary) -> void:
	var actor_id: int = active_player_index
	var equipment_id: String = String(payload.get("equipment_id", ""))
	if equipment_id != _equipped_logical_id(actor_id, "weapon"):
		return
	if equipment_id == "crowbar_new":
		var position: Vector2i = _payload_position(payload.get("position", []))
		if active_bounds().has_point(position) and tile_kind(position) != "collapsed":
			destroyed_tiles[_tile_key(position)] = true
			var crowbar_flags: Dictionary = players[actor_id].get("flags", {}) as Dictionary
			crowbar_flags.erase("crowbar_ready")
			players[actor_id]["flags"] = crowbar_flags
			_consume_equipment_durability(actor_id, "weapon", "crowbar_activate")
			_emit("equipment_activated", {"player_id": actor_id, "card_id": equipment_id, "position": _position_payload(position), "message": "【撬棍】令所选格子崩坏。"})
		return
	if equipment_id == "cleaver_new":
		var direction: Vector2i = {"up": Vector2i.UP, "right": Vector2i.RIGHT, "down": Vector2i.DOWN, "left": Vector2i.LEFT}.get(String(payload.get("direction", "")), Vector2i.ZERO) as Vector2i
		if direction == Vector2i.ZERO:
			return
		var position: Vector2i = players[actor_id].get("position", Vector2i.ZERO) as Vector2i
		var last_hit_id := -1
		while true:
			position += direction
			if not active_bounds().has_point(position):
				break
			for target_id: int in players.size():
				if target_id != actor_id and bool(players[target_id].get("alive", false)) and (players[target_id].get("position", Vector2i.ZERO) as Vector2i) == position:
					_deal_damage(target_id, 1, "normal", actor_id, true, {"single_target": false, "area": true, "card_effect": true})
					last_hit_id = target_id
		if last_hit_id >= 0 and bool(players[last_hit_id].get("alive", false)):
			var weapon_instance: String = String((players[actor_id].get("equipment", {}) as Dictionary).get("weapon", ""))
			players[actor_id]["equipment"]["weapon"] = ""
			players[last_hit_id]["equipment"]["weapon"] = weapon_instance
		_consume_equipment_durability(last_hit_id, "weapon", "cleaver_throw")
		_emit("equipment_activated", {"player_id": actor_id, "card_id": equipment_id, "target_id": last_hit_id, "message": "【一把菜刀】沿直线投掷并转移给最后命中的角色。"})


func _handle_move(payload: Dictionary) -> void:
	var path: Array = payload.get("path", []) as Array
	var actor_id: int = active_player_index
	var active: Dictionary = current_player()
	var previous_position: Vector2i = active.get("position", Vector2i.ZERO) as Vector2i
	var signal_started_collapsed := String(active.get("character_id", "")) == "signal" and not active_bounds().has_point(active.get("position", Vector2i.ZERO) as Vector2i)
	for step_value: Variant in path:
		var step: Vector2i = _payload_position(step_value)
		var step_direction: Vector2i = step - previous_position
		if step_direction != Vector2i.ZERO:
			active["last_action_direction"] = _position_payload(step_direction)
		active["position"] = step
		previous_position = step
		players[actor_id] = active
		if tile_kind(step) == "trap":
			if _equipped_logical_id(actor_id, "armor") == "trench_coat_new":
				_draw_cards(actor_id, 1)
				_emit("trap_triggered", {"player_id": actor_id, "position": _position_payload(step), "immune": true, "message": "%s 的【风衣】免疫陷阱伤害并摸1张牌。" % String(active.get("name", ""))})
			else:
				_deal_damage(actor_id, 1, "true", -1, false)
				_emit("trap_triggered", {"player_id": actor_id, "position": _position_payload(step), "message": "%s 穿过陷阱，受到1点伤害。" % String(active.get("name", ""))})
			if not bool(players[actor_id].get("alive", false)):
				break
	active = players[actor_id]
	active["moves_remaining"] = maxi(0, int(active.get("moves_remaining", 0)) - 1)
	var move_flags: Dictionary = active.get("flags", {}) as Dictionary
	move_flags["moved_this_turn"] = true
	active["flags"] = move_flags
	players[actor_id] = active
	_emit("moved", {"player_id": actor_id, "position": _position_payload(active.get("position", Vector2i.ZERO) as Vector2i), "message": "%s 完成移动。" % String(active.get("name", ""))})
	if bool(active.get("alive", false)):
		_resolve_landing(actor_id)
	if bool(players[actor_id].get("alive", false)) and signal_started_collapsed and active_bounds().has_point(players[actor_id].get("position", Vector2i.ZERO) as Vector2i):
		var signal_turn_flags: Dictionary = players[actor_id].get("flags", {}) as Dictionary
		if not bool(signal_turn_flags.get("signal_left_collapsed", false)):
			signal_turn_flags["signal_left_collapsed"] = true
			players[actor_id]["flags"] = signal_turn_flags
			_change_coins(actor_id, 2)
			_draw_cards(actor_id, 2)
			_emit("passive_triggered", {"player_id": actor_id, "skill_id": "signal_mix", "message": "Signal 首次脱离崩坠区域，获得2枚金币并摸2张牌。"})


func _handle_play_card(payload: Dictionary) -> void:
	var actor_id: int = active_player_index
	var card_id: String = String(payload.get("card_id", ""))
	var target_id: int = int(payload.get("target_id", actor_id))
	var definition: Dictionary = _card_definition_for_player(actor_id, card_id)
	var active: Dictionary = players[actor_id]
	active["last_strategy_record"] = {}
	players[actor_id] = active
	var logical_id := String(catalog.call("logical_card_id", card_id))
	if String(definition.get("category", "")) == "attack" and _equipped_logical_id(actor_id, "weapon") == "broad_axe_new":
		definition = definition.duplicate(true)
		definition["target"] = "all_enemies_in_range"
		definition["local_range"] = _move_range(actor_id)
	if String(definition.get("category", "")) == "attack" and _equipped_logical_id(actor_id, "weapon") == "warhammer_new" and target_id >= 0 and target_id < players.size():
		var hammer_flags: Dictionary = active.get("flags", {}) as Dictionary
		if not bool(hammer_flags.get("warhammer_used", false)):
			definition = definition.duplicate(true)
			for effect_value: Variant in definition.get("effects", []) as Array:
				var hammer_effect: Dictionary = effect_value as Dictionary
				if String(hammer_effect.get("op", "")) == "damage":
					hammer_effect["amount"] = int(players[target_id].get("armor", 0))
			hammer_flags["warhammer_used"] = true
			active["flags"] = hammer_flags
			players[actor_id] = active
			_emit("equipment_triggered", {"player_id": actor_id, "target_id": target_id, "card_id": "warhammer_new", "message": "【重锤】将本次攻击伤害改为目标当前护甲。"})
	if logical_id == "frenzy_new" and target_id >= 0 and target_id < players.size() and int((players[target_id].get("match_flags", {}) as Dictionary).get("damage_received_round", -1)) == completed_rounds:
		definition = definition.duplicate(true)
		var frenzy_cost: Dictionary = definition.get("cost", {}) as Dictionary
		frenzy_cost["stamina"] = maxi(0, int(frenzy_cost.get("stamina", 0)) - 1)
		definition["cost"] = frenzy_cost
		_emit("card_cost_changed", {"player_id": actor_id, "target_id": target_id, "card_id": card_id, "stamina": int(frenzy_cost.get("stamina", 0)), "mana": int(frenzy_cost.get("mana", 0)), "message": "【狂袭】目标本轮已受伤，体力消耗减1。"})
	if ["endgame_new", "endgame_ambitionist_new"].has(logical_id):
		_request_skill_choice(actor_id, "endgame_card", logical_id, _endgame_copy_options(actor_id, card_id), {"physical_card_id": card_id, "was_last_card": _available_hand_count(actor_id) == 1})
		return
	if logical_id == "barrier_break_new":
		_begin_barrier_break(actor_id, card_id, target_id, definition)
		return
	if logical_id == "mana_flow_new":
		var elemental_cards := _elemental_hand_cards(actor_id)
		if elemental_cards.is_empty():
			_emit("card_resolution_failed", {"player_id": actor_id, "card_id": card_id, "message": "【魔力回流】没有可弃置的元素牌，无法使用。"})
			return
		var mana_flow_hand: Array = (active.get("hand", []) as Array).duplicate()
		if not _remove_first(mana_flow_hand, card_id):
			_remove_first(active.get("purchased_hand", []) as Array, card_id)
		active["hand"] = mana_flow_hand
		(active.get("discard", []) as Array).append(card_id)
		players[actor_id] = active
		_record_discard_origin(actor_id, card_id)
		_pay_cost(actor_id, definition)
		pending_skill_discard = {"request_id": "%d:%d:mana_flow" % [command_log.size(), actor_id], "player_id": actor_id, "skill_id": "mana_flow_new", "target_id": actor_id, "selection_mode": "count", "required_rank_sum": 0, "minimum_count": 1, "required_count": 1}
		_emit("discard_requested", {"player_id": actor_id, "request_id": pending_skill_discard["request_id"], "selection_mode": "count", "required_count": 1, "reason_id": "card:mana_flow_new", "message": "请选择一张元素牌弃置以结算【魔力回流】。"})
		return
	var thunder_guard_attacks: Dictionary = active.get("thunder_guard_attack_cards", {}) as Dictionary
	var thunder_guard_strange: Dictionary = active.get("thunder_guard_strange_cards", {}) as Dictionary
	if bool(thunder_guard_attacks.get(card_id, false)):
		definition = definition.duplicate(true)
		(definition.get("effects", []) as Array).append({"op": "status_if_damage", "status": "paralyze", "stacks": 1})
		thunder_guard_attacks.erase(card_id)
		active["thunder_guard_attack_cards"] = thunder_guard_attacks
	var can_transfer_after := bool(thunder_guard_strange.get(card_id, false))
	if can_transfer_after:
		thunder_guard_strange.erase(card_id)
		active["thunder_guard_strange_cards"] = thunder_guard_strange
	var hand: Array = (active.get("hand", []) as Array).duplicate()
	var purchased_hand: Array = (active.get("purchased_hand", []) as Array).duplicate()
	var was_purchased: bool = purchased_hand.has(card_id)
	if not _remove_first(hand, card_id):
		_remove_first(purchased_hand, card_id)
	active["hand"] = hand
	active["purchased_hand"] = purchased_hand
	players[actor_id] = active
	_pay_cost(actor_id, definition)
	active = players[actor_id]
	active = players[actor_id]
	players[actor_id] = active
	if String(definition.get("category", "")) == "equipment":
		_equip(actor_id, card_id)
		_emit("card_played", {"player_id": actor_id, "card_id": card_id, "message": "%s 装备了【%s】。" % [String(active.get("name", "")), String(definition.get("name", card_id))]})
		_record_public_card(actor_id, card_id, actor_id, "equipment")
		return
	active = players[actor_id]
	(active.get("discard", []) as Array).append(card_id)
	players[actor_id] = active
	_record_discard_origin(actor_id, card_id)
	active = players[actor_id]
	active["last_card_id"] = card_id
	players[actor_id] = active
	var damage_bonus: int = 0
	var unanswerable: bool = false
	var statuses: Dictionary = active.get("statuses", {}) as Dictionary
	if logical_id in ["berserker_blow_new", "armor_piercing_shot_new"] and target_id >= 0 and target_id < players.size() and int(players[target_id].get("armor", 0)) > 0:
		damage_bonus += 1
	if logical_id == "sniper_new" and target_id >= 0 and target_id < players.size() and _distance(actor_id, target_id) == _definition_range(actor_id, definition):
		damage_bonus += 1
	if _equipped_logical_id(actor_id, "weapon") == "hunter_longbow_new" and String(definition.get("category", "")) == "attack" and target_id >= 0 and _distance(actor_id, target_id) == _definition_range(actor_id, definition):
		damage_bonus += 1
	if _equipped_logical_id(actor_id, "accessory") == "scope_new" and int(active.get("turn_commands", 0)) == 1:
		unanswerable = true
	if logical_id == "close_shot_new" and target_id >= 0 and target_id < players.size() and _distance(actor_id, target_id) <= 1:
		damage_bonus += 2
		unanswerable = true
	if String(definition.get("category", "")) == "attack" and _equipped_logical_id(actor_id, "weapon") == "overlimit_pistol_new" and target_id >= 0 and target_id < players.size() and _distance(actor_id, target_id) <= 1:
		damage_bonus += 1
	if String(definition.get("category", "")) == "attack" and _equipped_logical_id(actor_id, "weapon") == "rapier_new":
		var rapier_flags: Dictionary = active.get("flags", {}) as Dictionary
		if bool(rapier_flags.get("moved_this_turn", false)) and not bool(rapier_flags.get("rapier_after_move_used", false)):
			damage_bonus += 1
			rapier_flags["rapier_after_move_used"] = true
			active["flags"] = rapier_flags
			players[actor_id] = active
	if String(definition.get("category", "")) == "attack" and _equipped_logical_id(actor_id, "weapon") == "a_plus_new":
		var a_plus_flags: Dictionary = active.get("flags", {}) as Dictionary
		if not bool(a_plus_flags.get("a_plus_attack_used", false)):
			damage_bonus += 3
			a_plus_flags["a_plus_attack_used"] = true
			active["flags"] = a_plus_flags
			players[actor_id] = active
	if String(definition.get("category", "")) == "attack" and _equipped_logical_id(actor_id, "weapon") == "assassin_dagger_new":
		var dagger_flags: Dictionary = active.get("flags", {}) as Dictionary
		if bool(dagger_flags.get("moved_this_turn", false)) and not bool(dagger_flags.get("assassin_dagger_used", false)):
			unanswerable = true
			dagger_flags["assassin_dagger_used"] = true
			active["flags"] = dagger_flags
			players[actor_id] = active
	var flash_attack := false
	if String(definition.get("category", "")) == "attack" and int(active.get("flash", 0)) > 0:
		var flash_flags: Dictionary = active.get("flags", {}) as Dictionary
		if not bool(flash_flags.get("flash_attack_used", false)):
			flash_attack = true
			damage_bonus += 1
			flash_flags["flash_attack_used"] = true
			active["flags"] = flash_flags
			players[actor_id] = active
	if String(active.get("character_id", "")) == "ginger" and String(definition.get("category", "")) == "attack" and target_id >= 0 and target_id < players.size():
		var target_state: Dictionary = players[target_id]
		var target_health := int(target_state.get("health", 0))
		var target_max_health := maxi(1, int(target_state.get("max_health", 1)))
		if target_health * 2 >= target_max_health:
			unanswerable = true
	if String(definition.get("category", "")) == "attack" and int(statuses.get("hidden", 0)) > 0:
		if not flash_attack:
			damage_bonus += 1
			unanswerable = true
		statuses.erase("hidden")
		active["statuses"] = statuses
		players[actor_id] = active
	if String(definition.get("category", "")) == "attack" and bool((active.get("flags", {}) as Dictionary).get("next_attack_unanswerable", false)):
		unanswerable = true
		var aim_flags: Dictionary = active.get("flags", {}) as Dictionary
		aim_flags.erase("next_attack_unanswerable")
		active["flags"] = aim_flags
		players[actor_id] = active
	var action: Dictionary = {
		"source_id": actor_id,
		"target_id": target_id,
		"definition": definition.duplicate(true),
		"category": String(definition.get("category", "")),
		"card_id": card_id,
		"damage_bonus": damage_bonus,
		"unanswerable": unanswerable or bool(definition.get("unanswerable", false)),
		"na1_purchased": was_purchased and String(players[actor_id].get("character_id", "")) == "na1"
	}
	if _equipped_logical_id(actor_id, "accessory") == "verdict_new" and not bool((active.get("flags", {}) as Dictionary).get("verdict_first_card_used", false)) and target_id >= 0 and target_id < players.size() and (players[target_id].get("hand", []) as Array).size() < (active.get("hand", []) as Array).size():
		action["unanswerable"] = true
		var verdict_flags: Dictionary = active.get("flags", {}) as Dictionary
		verdict_flags["verdict_first_card_used"] = true
		players[actor_id]["flags"] = verdict_flags
	if logical_id == "hand_repel_new":
		action["hand_repel"] = true
	if logical_id == "skirmish_new":
		action["skirmish"] = true
		action["target_health_before"] = int(players[target_id].get("health", 0)) if target_id >= 0 and target_id < players.size() else 0
	if can_transfer_after:
		action["q_transfer_card"] = card_id
	_emit("card_played", {"player_id": actor_id, "target_id": target_id, "card_id": card_id, "message": "%s 使用【%s】。" % [String(active.get("name", "")), String(definition.get("name", card_id))]})
	_record_public_card(actor_id, card_id, target_id, "card")
	if logical_id == "mad_thought_new":
		var hand_before_draw: Array = (players[actor_id].get("hand", []) as Array).duplicate()
		_draw_cards(actor_id, 1)
		var hand_after_draw: Array = players[actor_id].get("hand", []) as Array
		if hand_after_draw.size() > hand_before_draw.size():
			var drawn_card_id := String(hand_after_draw.back())
			var drawn_definition: Dictionary = catalog.call("resolve_card", drawn_card_id) as Dictionary
			if String(drawn_definition.get("category", "")) == "attack":
				var thought_flags: Dictionary = players[actor_id].get("flags", {}) as Dictionary
				var free_card_ids: Array = (thought_flags.get("free_card_ids", []) as Array).duplicate()
				free_card_ids.append(drawn_card_id)
				thought_flags["free_card_ids"] = free_card_ids
				players[actor_id]["flags"] = thought_flags
				_emit("card_cost_changed", {"player_id": actor_id, "card_id": drawn_card_id, "stamina": 0, "mana": 0, "message": "【狂徒思维】令刚摸到的攻击牌【%s】本回合免费。" % String(drawn_definition.get("name", drawn_card_id))})
		return
	if logical_id == "exclusive_new":
		_resolve_exclusive(actor_id, card_id)
		return
	if logical_id == "last_resort_new":
		_resolve_last_resort_discard(actor_id)
		_request_skill_choice(actor_id, "last_resort_card", logical_id, _last_resort_options(actor_id))
		return
	if logical_id == "balance_new":
		_resolve_balance(actor_id, target_id)
		return
	if logical_id == "crossfire_new":
		_request_skill_choice(actor_id, "crossfire_source_card", logical_id, _attack_hand_options(actor_id), {"target_id": target_id})
		return
	if logical_id in ["planning_new", "planning_ambitionist_new"]:
		planning_pending[card_id] = true
		_emit("planning_placed", {"player_id": actor_id, "card_id": card_id, "message": "%s 将【运筹】置于所有抽牌堆顶。" % String(players[actor_id].get("name", ""))})
		return
	if logical_id == "swap_new":
		_request_skill_choice(actor_id, "swap_source_card", logical_id, (players[actor_id].get("hand", []) as Array).duplicate(), {"target_id": target_id})
		return
	if logical_id == "element_resonance_new":
		_request_skill_choice(actor_id, "element_resonance_element", logical_id, ["lightning", "fire", "poison", "bleed"], {"target_id": target_id})
		return
	if logical_id == "gold_panning_new":
		_request_skill_choice(actor_id, "gold_panning_card", logical_id, _gold_panning_options(actor_id), {"card_id": card_id})
		return
	if logical_id == "thunderstorm_new":
		_request_skill_choice(actor_id, "card_area_choice", logical_id, ["northwest", "northeast", "southwest", "southeast"], {"card_id": card_id})
		return
	if logical_id == "dragon_breath_new":
		_request_skill_choice(actor_id, "card_area_choice", logical_id, ["row", "column"], {"card_id": card_id})
		return
	if logical_id == "scatter_new":
		_request_skill_choice(actor_id, "scatter_direction", logical_id, ["left", "right"], {"card_id": card_id})
		return
	if logical_id == "suppress_new":
		_resolve_suppress(actor_id, card_id, _payload_position(payload.get("position", [])))
		return
	if logical_id == "momentum_new":
		_request_skill_choice(actor_id, "momentum_direction", logical_id, ["up", "right", "down", "left"], {"target_id": target_id})
		return
	if logical_id in ["precision_stab_new", "thunder_strike_new"]:
		_request_skill_choice(actor_id, "precision_direction", logical_id, ["up", "right", "down", "left"], {"card_id": card_id})
		return
	if logical_id == "body_slam_new":
		_request_skill_choice(actor_id, "precision_direction", logical_id, ["up", "right", "down", "left"], {"card_id": card_id})
		return
	if logical_id == "neutralize_new":
		var recipients: Array[int] = []
		for candidate_id: int in players.size():
			if candidate_id != target_id and bool(players[candidate_id].get("alive", false)):
				recipients.append(candidate_id)
		if not recipients.is_empty():
			_request_skill_choice(actor_id, "neutralize_target", logical_id, recipients, {"source_id": target_id})
		return
	if logical_id == "tactical_retreat_new":
		_move_back_from_last_action(actor_id, 2)
	if logical_id == "demolition_new":
		var demolition_position := _payload_position(payload.get("position", []))
		destroyed_tiles[_tile_key(demolition_position)] = true
		_emit("tile_destroyed", {"player_id": actor_id, "position": _position_payload(demolition_position), "message": "%s 摧毁了该格子；它永久成为崩坠格。" % String(players[actor_id].get("name", ""))})
	if logical_id == "hunt_new":
		var hunt_destination := _hunt_destination(actor_id, target_id)
		if hunt_destination == Vector2i.ZERO:
			_emit("card_resolution_failed", {"player_id": actor_id, "card_id": card_id, "target_id": target_id, "message": "【猎杀】目标后方没有合法空格。"})
			return
		var hunt_previous: Vector2i = players[actor_id].get("position", Vector2i.ZERO) as Vector2i
		players[actor_id]["position"] = hunt_destination
		players[actor_id]["last_action_direction"] = _position_payload(Vector2i(signi(hunt_destination.x - hunt_previous.x), signi(hunt_destination.y - hunt_previous.y)))
		_emit("hunt_moved", {"player_id": actor_id, "target_id": target_id, "position": _position_payload(hunt_destination), "message": "%s 移动至目标后方发动【猎杀】。" % String(players[actor_id].get("name", ""))})
	_open_response_or_resolve(action)


func _hunt_destination(source_id: int, target_id: int) -> Vector2i:
	if source_id < 0 or source_id >= players.size() or target_id < 0 or target_id >= players.size():
		return Vector2i.ZERO
	var direction := _payload_position(players[target_id].get("last_action_direction", []))
	if direction == Vector2i.ZERO:
		return Vector2i.ZERO
	var destination: Vector2i = (players[target_id].get("position", Vector2i.ZERO) as Vector2i) - direction
	if not active_bounds().has_point(destination) or _is_occupied(destination, source_id):
		return Vector2i.ZERO
	return destination


func _handle_use_skill(payload: Dictionary) -> void:
	var actor_id: int = active_player_index
	var skill_id: String = String(payload.get("skill_id", ""))
	var variant: String = String(payload.get("variant", "normal"))
	var target_id: int = int(payload.get("target_id", actor_id))
	var skill: Dictionary = _skill_definition(actor_id, skill_id)
	var revised_skill_id := String(skill.get("revised_skill_id", REVISED_SKILL_ALIASES.get(skill_id, skill_id)))
	if revised_skill_id == "q_thunder_guard":
		_begin_q_thunder_guard(actor_id)
		return
	if revised_skill_id == "ginger_power":
		_begin_ginger_power(actor_id, skill, variant)
		return
	if revised_skill_id == "zc_frenzy":
		_begin_zc_frenzy(actor_id)
		return
	if revised_skill_id == "maddy_explore":
		var maddy_skill_uses: Dictionary = players[actor_id].get("skill_uses", {}) as Dictionary
		maddy_skill_uses[skill_id] = int(maddy_skill_uses.get(skill_id, 0)) + 1
		players[actor_id]["skill_uses"] = maddy_skill_uses
		_begin_maddy_explore(actor_id)
		return
	if revised_skill_id == "maddy_reclaim":
		# Reclaim is offered after Maddy actually deals damage; it is not a free attack.
		return
	var paid_resources := _pay_skill_resources(actor_id, skill, variant)
	var skill_uses: Dictionary = players[actor_id].get("skill_uses", {}) as Dictionary
	skill_uses[skill_id] = int(skill_uses.get(skill_id, 0)) + 1
	players[actor_id]["skill_uses"] = skill_uses
	var policy := skill_usage_policy(actor_id, skill_id)
	if int(policy.get("uses_per_profession_per_match", 0)) > 0 and skill_id != "k_strategy":
		var match_uses: Dictionary = players[actor_id].get("skill_match_uses", {}) as Dictionary
		var match_key := _skill_match_usage_key(actor_id, skill_id)
		match_uses[match_key] = int(match_uses.get(match_key, 0)) + 1
		players[actor_id]["skill_match_uses"] = match_uses
	var discard_requirement: Dictionary = skill.get("discard_requirement", {}) as Dictionary
	if not discard_requirement.is_empty():
		var selection_mode := String(discard_requirement.get("mode", "rank_sum"))
		pending_skill_discard = {
			"request_id": "%d:%d:%s" % [command_log.size(), actor_id, skill_id],
			"player_id": actor_id,
			"skill_id": skill_id,
			"target_id": target_id,
			"variant": variant,
			"paid_resources": paid_resources,
			"selection_mode": selection_mode,
			"required_rank_sum": int(discard_requirement.get("rank_sum", 0)),
			"minimum_count": int(discard_requirement.get("minimum_cards", 1)),
			"required_count": int(discard_requirement.get("count", 0))
		}
		_emit("skill_used", {"player_id": actor_id, "target_id": target_id, "skill_id": skill_id, "pending_cost": true, "message": "%s 准备发动【%s】，等待弃牌。" % [String(players[actor_id].get("name", "")), String(skill.get("name", skill_id))]})
		var requirement_text := "恰好%d张" % int(pending_skill_discard["required_count"]) if selection_mode == "count" else "点数和为%d" % int(pending_skill_discard["required_rank_sum"])
		_emit("discard_requested", {"player_id": actor_id, "request_id": pending_skill_discard["request_id"], "selection_mode": selection_mode, "required_rank_sum": pending_skill_discard["required_rank_sum"], "minimum_count": pending_skill_discard["minimum_count"], "required_count": pending_skill_discard["required_count"], "reason_id": "skill:%s" % skill_id, "message": "%s 请选择%s的牌发动【%s】。" % [String(players[actor_id].get("name", "")), requirement_text, String(skill.get("name", skill_id))]})
		return
	if revised_skill_id == "k_strategy":
		var strange_cards := _available_k_strategy_cards(actor_id)
		var medium_cards: Array = (players[actor_id].get("hand", []) as Array).duplicate()
		var repeat_count := maxi(1, medium_cards.size())
		if variant == "exhaust":
			repeat_count += int(paid_resources.get("mana", 0))
		var strategy_discard: Array = players[actor_id].get("discard", []) as Array
		strategy_discard.append_array(medium_cards)
		players[actor_id]["hand"] = []
		players[actor_id]["discard"] = strategy_discard
		for medium_card_id: String in medium_cards:
			_record_discard_origin(actor_id, medium_card_id)
		_emit("cards_discarded", {"player_id": actor_id, "card_ids": medium_cards.duplicate(), "reason_id": "skill:k_strategy", "message": "K 将全部%d张手牌作为【奇策】媒介弃置。" % medium_cards.size()})
		_request_skill_choice(actor_id, "k_strategy_card", "k_strategy", strange_cards, {"resolution_count": repeat_count, "medium_cards": medium_cards.duplicate()})
		return
	var active: Dictionary = players[actor_id]
	active = players[actor_id]
	players[actor_id] = active
	var action: Dictionary = {
		"source_id": actor_id,
		"target_id": target_id,
		"definition": skill.duplicate(true),
		"category": "skill",
		"card_id": "",
		"damage_bonus": 0,
		"unanswerable": false
	}
	_emit("skill_used", {"player_id": actor_id, "target_id": target_id, "skill_id": skill_id, "variant": variant, "paid_resources": paid_resources, "message": "%s 发动【%s】。" % [String(active.get("name", "")), String(skill.get("name", skill_id))]})
	_open_response_or_resolve(action)


func _begin_ginger_power(player_id: int, skill: Dictionary, variant: String) -> void:
	var active: Dictionary = players[player_id]
	var before_health := int(active.get("health", 0))
	var loss := maxi(0, before_health - 2)
	active["health"] = 2
	var breakthroughs: Dictionary = active.get("active_breakthroughs", {}) as Dictionary
	breakthroughs["ginger_power"] = true
	active["active_breakthroughs"] = breakthroughs
	var losses: Dictionary = active.get("breakthrough_losses", {}) as Dictionary
	losses["ginger_power"] = {"health": loss}
	active["breakthrough_losses"] = losses
	var uses: Dictionary = active.get("skill_uses", {}) as Dictionary
	uses["ginger_power"] = int(uses.get("ginger_power", 0)) + 1
	active["skill_uses"] = uses
	players[player_id] = active
	_draw_cards(player_id, 2)
	_emit("skill_used", {"player_id": player_id, "skill_id": "ginger_power", "message": "%s 发动【强攻】，生命调整至2并摸两张牌。" % String(active.get("name", ""))})
	_request_skill_choice(player_id, "ginger_power_max_health", "ginger_power", ["keep", "reduce"])


func _request_ginger_power_cards(player_id: int) -> void:
	pending_skill_discard = {"request_id": "%d:%d:ginger_power" % [command_log.size(), player_id], "player_id": player_id, "skill_id": "ginger_power", "target_id": player_id, "variant": "normal", "selection_mode": "count", "required_rank_sum": 0, "minimum_count": 2, "required_count": 2}
	_emit("discard_requested", {"player_id": player_id, "request_id": pending_skill_discard["request_id"], "selection_mode": "count", "required_count": 2, "reason_id": "skill:ginger_power", "message": "请选择两张手牌作为【舍身突击】并弃置。"})


func _available_k_strategy_cards(player_id: int) -> Array[String]:
	var result: Array[String] = []
	var used: Dictionary = players[player_id].get("skill_match_uses", {}) as Dictionary
	for definition_value: Variant in catalog.get("staged_cards") as Array:
		var definition: Dictionary = definition_value as Dictionary
		if String(definition.get("category", "")) != "奇异":
			continue
		var profession := String(definition.get("profession", "neutral"))
		if int(used.get("k_strategy:%s" % profession, 0)) > 0:
			continue
		var instances: Array = definition.get("instances", []) as Array
		if not instances.is_empty():
			var instance_id := "%s#001" % String(definition.get("id", ""))
			if not _skill_target_options(player_id, catalog.call("resolve_card", instance_id) as Dictionary).is_empty():
				result.append(instance_id)
	return result


func _open_response_or_resolve(action: Dictionary) -> void:
	var target_id: int = int(action.get("target_id", -1))
	var category: String = String(action.get("category", ""))
	if target_id >= 0 and target_id != int(action.get("source_id", -1)) and not bool(action.get("unanswerable", false)):
		var responses: Array[String] = _valid_response_cards(target_id, category)
		var shya_id := _available_shya_negater(int(action.get("source_id", -1)))
		if shya_id >= 0:
			action["responder_id"] = shya_id
			action["normal_responder_id"] = target_id if not responses.is_empty() else -1
			action["shya_flash_negate_offer"] = true
			pending_action = action
			_emit("response_opened", {"player_id": shya_id, "category": category, "response_id": "shya_flash_negate", "message": "Shya 可移除场上2个闪光无效这张牌。"})
			return
		if not responses.is_empty():
			action["responder_id"] = target_id
			pending_action = action
			_emit("response_opened", {"player_id": target_id, "category": category, "message": "%s 可以响应。" % String(players[target_id].get("name", ""))})
			return
	_resolve_action(action)


func _handle_response(payload: Dictionary) -> void:
	var action: Dictionary = pending_action.duplicate(true)
	pending_action.clear()
	var responder_id: int = int(action.get("responder_id", -1))
	var card_id: String = String(payload.get("card_id", ""))
	if bool(action.get("shya_flash_negate_offer", false)):
		if card_id == "shya_flash_negate":
			_consume_two_flashes(responder_id)
			var flags: Dictionary = players[responder_id].get("flags", {}) as Dictionary
			flags["shya_flash_negate_used"] = true
			players[responder_id]["flags"] = flags
			_emit("action_canceled", {"source_id": int(action.get("source_id", -1)), "player_id": responder_id, "reason_id": "shya_flash_negate", "message": "Shya 移除2个闪光，无效了这张牌。"})
			if bool(action.get("zc_frenzy", false)):
				_finish_zc_frenzy(action, false)
			return
		action.erase("shya_flash_negate_offer")
		var normal_responder := int(action.get("normal_responder_id", -1))
		action.erase("normal_responder_id")
		if normal_responder >= 0 and not _valid_response_cards(normal_responder, String(action.get("category", ""))).is_empty():
			action["responder_id"] = normal_responder
			pending_action = action
			_emit("response_opened", {"player_id": normal_responder, "category": String(action.get("category", "")), "message": "%s 可以响应。" % String(players[normal_responder].get("name", ""))})
			return
		_resolve_action(action)
		return
	if card_id.is_empty():
		_emit("response_passed", {"player_id": responder_id, "message": "%s 放弃响应。" % String(players[responder_id].get("name", ""))})
		_resolve_action(action)
		return
	var definition: Dictionary = catalog.call("resolve_card", card_id) as Dictionary
	var responder: Dictionary = players[responder_id]
	if not _remove_first(responder.get("hand", []) as Array, card_id):
		_remove_first(responder.get("purchased_hand", []) as Array, card_id)
	players[responder_id] = responder
	_pay_cost(responder_id, definition)
	responder = players[responder_id]
	(responder.get("discard", []) as Array).append(card_id)
	players[responder_id] = responder
	_record_discard_origin(responder_id, card_id)
	var canceled: bool = false
	var reflected: bool = false
	for effect_value: Variant in definition.get("effects", []) as Array:
		var effect: Dictionary = effect_value as Dictionary
		var operation: String = String(effect.get("op", ""))
		var required_category: String = String(effect.get("category", ""))
		if operation == "negate" and required_category == String(action.get("category", "")):
			canceled = true
		elif operation == "reflect" and required_category == String(action.get("category", "")):
			reflected = true
		elif operation != "negate" and operation != "reflect":
			_apply_single_effect(responder_id, responder_id, effect, "response", 0)
	_emit("response_played", {"player_id": responder_id, "card_id": card_id, "message": "%s 使用响应【%s】。" % [String(responder.get("name", "")), String(definition.get("name", card_id))]})
	_record_public_card(responder_id, card_id, int(action.get("source_id", -1)), "response")
	var original_source := int(action.get("source_id", -1))
	if original_source >= 0 and String(players[original_source].get("character_id", "")) == "shya" and responder_id != original_source:
		_request_skill_choice(original_source, "shya_response_offer", "shya_break_flash", ["use", "skip"], {"responder_id": responder_id, "response_card_id": card_id, "response_action": action.duplicate(true), "canceled": canceled, "reflected": reflected})
		return
	_finish_response_resolution(action, canceled, reflected, responder_id, card_id)


func _finish_response_resolution(action: Dictionary, canceled: bool, reflected: bool, responder_id: int, card_id: String) -> void:
	if canceled:
		_emit("action_canceled", {"source_id": int(action.get("source_id", -1)), "message": "原行动被抵消。"})
		if bool(action.get("zc_frenzy", false)):
			_finish_zc_frenzy(action, false)
		return
	if reflected:
		var original_source := int(action.get("source_id", -1))
		action["source_id"] = responder_id
		action["target_id"] = original_source
		action["damage_bonus"] = 1 if card_id == "counter_charge" else 0
		action["unanswerable"] = true
	_resolve_action(action)


func _handle_buy(payload: Dictionary) -> void:
	var market_index: int = int(payload.get("market_index", -1))
	var actor_id: int = active_player_index
	var card_id: String = market[market_index]
	var definition: Dictionary = catalog.call("resolve_card", card_id) as Dictionary
	var active: Dictionary = players[actor_id]
	active["coins"] = int(active.get("coins", 0)) - int(definition.get("price", 0))
	active["market_bought"] = true
	players[actor_id] = active
	market.remove_at(market_index)
	if String(definition.get("category", "")) == "equipment":
		_equip(actor_id, card_id)
	else:
		var purchased_hand: Array = (active.get("purchased_hand", []) as Array).duplicate()
		purchased_hand.append(card_id)
		active["purchased_hand"] = purchased_hand
		players[actor_id] = active
	_replenish_market()
	_emit("market_bought", {"player_id": actor_id, "card_id": card_id, "message": "%s 购买【%s】。" % [String(active.get("name", "")), String(definition.get("name", card_id))]})


func _handle_event_choice(payload: Dictionary) -> void:
	var choice_index: int = int(payload.get("choice_index", -1))
	var choices: Array = pending_event.get("choices", []) as Array
	var choice: Dictionary = choices[choice_index] as Dictionary
	var title: String = String(pending_event.get("title", "事件"))
	pending_event.clear()
	_apply_effects(active_player_index, active_player_index, choice.get("effects", []) as Array, "event", 0, 0)
	_emit("event_resolved", {"player_id": active_player_index, "choice_index": choice_index, "message": "【%s】选择：%s" % [title, String(choice.get("label", ""))]})


func _handle_end_turn() -> void:
	var ending_id: int = active_player_index
	var active: Dictionary = players[ending_id]
	# A player can die while an effect (including a discard request) is settling.
	# Dead players never discard or spend resources; advance immediately.
	if not bool(active.get("alive", false)):
		_finish_end_turn(ending_id)
		return
	_check_ginger_breakthrough(ending_id)
	active = players[ending_id]
	var hand_limit_for_turn: int = maxi(1, int(active.get("health", 0)) - 2)
	var excess: int = (active.get("hand", []) as Array).size() - hand_limit_for_turn
	if excess > 0:
		_request_discard(ending_id, excess, "end_turn")
		return
	if bool(active.get("q_thunder_guard_end_available", false)):
		active["q_thunder_guard_end_available"] = false
		players[ending_id] = active
		_request_skill_choice(ending_id, "q_thunder_guard_end_decision", "q_thunder_guard", ["use", "skip"])
		return
	_finish_end_turn(ending_id)


func _finish_end_turn(ending_id: int) -> void:
	var active: Dictionary = players[ending_id]
	_finish_maddy_reclaim(ending_id)
	var hound_flags: Dictionary = players[ending_id].get("match_flags", {}) as Dictionary
	var black_hound_debt := int(hound_flags.get("black_hound_debt", 0))
	if bool(players[ending_id].get("alive", false)) and black_hound_debt > 0:
		hound_flags.erase("black_hound_debt")
		players[ending_id]["match_flags"] = hound_flags
		_change_max_health(ending_id, -black_hound_debt, "black_hound_new")
		_deal_damage(ending_id, black_hound_debt, "true", -1, false)
		_emit("black_hound_paid", {"player_id": ending_id, "amount": black_hound_debt, "message": "%s 偿还【黑犬之佑】代价：失去%d点生命上限并受到%d点伤害。" % [String(players[ending_id].get("name", "")), black_hound_debt, black_hound_debt]})
	if bool(players[ending_id].get("alive", false)) and _equipped_logical_id(ending_id, "accessory") == "poison_bottle_new":
		for target_id: int in _enemies_in_range(ending_id, 1):
			_apply_status(target_id, "poison", 1, ending_id)
		_emit("equipment_triggered", {"player_id": ending_id, "card_id": "poison_bottle_new", "message": "【毒雾瓶】使周围角色获得1层中毒。"})
	_tick_equipment_durability(ending_id)
	active = players[ending_id]
	var status_rounds: Dictionary = active.get("status_rounds", {}) as Dictionary
	var statuses: Dictionary = active.get("statuses", {}) as Dictionary
	if int(statuses.get("hidden", 0)) > 0 and int(status_rounds.get("hidden", completed_rounds)) < completed_rounds:
		statuses.erase("hidden")
		status_rounds.erase("hidden")
	active["statuses"] = statuses
	active["status_rounds"] = status_rounds
	active["stamina"] = 0
	active["mana"] = 0
	active["moves_remaining"] = 0
	players[ending_id] = active
	_emit("turn_ended", {"player_id": ending_id, "message": "%s 结束回合。" % String(active.get("name", ""))})
	var previous_index: int = active_player_index
	_advance_turn_index()
	if finished:
		return
	if active_player_index <= previous_index:
		var previous_pressure: int = _duel_pressure_bonus()
		completed_rounds += 1
		var current_pressure: int = _duel_pressure_bonus()
		if current_pressure != previous_pressure:
			_emit("duel_pressure_changed", {
				"round": completed_rounds + 1,
				"single_target_damage_bonus": current_pressure,
				"message": "决胜阶段：单体牌与技能伤害 +%d。" % current_pressure
			})
	_begin_turn()


func _resolve_card_area_choice(source_id: int, card_id: String, choice: String) -> void:
	var definition: Dictionary = catalog.call("resolve_card", card_id) as Dictionary
	var logical_id := String(catalog.call("logical_card_id", card_id))
	var source_position: Vector2i = players[source_id].get("position", Vector2i.ZERO) as Vector2i
	var targets: Array[int] = []
	for target_id: int in players.size():
		if target_id == source_id or not bool(players[target_id].get("alive", false)):
			continue
		var target_position: Vector2i = players[target_id].get("position", Vector2i.ZERO) as Vector2i
		if logical_id == "dragon_breath_new" and ((choice == "row" and target_position.y == source_position.y) or (choice == "column" and target_position.x == source_position.x)):
			targets.append(target_id)
		elif logical_id == "thunderstorm_new":
			var horizontal := -1 if choice in ["northwest", "southwest"] else 1
			var vertical := -1 if choice in ["northwest", "northeast"] else 1
			var delta := target_position - source_position
			if delta.x * horizontal >= 1 and delta.x * horizontal <= 2 and delta.y * vertical >= 1 and delta.y * vertical <= 2:
				targets.append(target_id)
	var damage_bonus := _consume_damage_bonuses(source_id, definition.get("effects", []) as Array, "attack")
	for target_id: int in targets:
		var damage_context := {"single_target": false, "area": true, "pressure_bonus": 0}
		for effect_value: Variant in definition.get("effects", []) as Array:
			_apply_single_effect(source_id, target_id, effect_value as Dictionary, "attack", damage_bonus, damage_context)
	_emit("area_card_resolved", {"player_id": source_id, "card_id": card_id, "choice": choice, "target_ids": targets.duplicate(), "message": "%s 结算【%s】，命中%d名角色。" % [String(players[source_id].get("name", "")), String(definition.get("name", card_id)), targets.size()]})


func _resolve_scatter(source_id: int, card_id: String, direction_id: String) -> void:
	var definition: Dictionary = catalog.call("resolve_card", card_id) as Dictionary
	var source_position: Vector2i = players[source_id].get("position", Vector2i.ZERO) as Vector2i
	var direction := -1 if direction_id == "left" else 1
	for target_id: int in players.size():
		if target_id == source_id or not bool(players[target_id].get("alive", false)):
			continue
		var target_position: Vector2i = players[target_id].get("position", Vector2i.ZERO) as Vector2i
		var horizontal_delta := (target_position.x - source_position.x) * direction
		if target_position.y == source_position.y and horizontal_delta >= 1 and horizontal_delta <= 5:
			_apply_effects(source_id, target_id, definition.get("effects", []) as Array, "attack", 0, 5, 0, true)


func _resolve_suppress(source_id: int, card_id: String, center: Vector2i) -> void:
	if not active_bounds().has_point(center) or tile_kind(center) == "collapsed":
		_emit("card_resolution_failed", {"player_id": source_id, "card_id": card_id, "message": "【压制】必须选择当前棋盘内未崩坏的格子。"})
		return
	var source: Dictionary = players[source_id]
	var damage_amount: int = int(source.get("stamina", 0)) + int(source.get("mana", 0))
	source["stamina"] = 0
	source["mana"] = 0
	players[source_id] = source
	var hit_targets: Array[int] = []
	for target_id: int in players.size():
		if target_id == source_id or not bool(players[target_id].get("alive", false)):
			continue
		var target_position: Vector2i = players[target_id].get("position", Vector2i.ZERO) as Vector2i
		if maxi(absi(target_position.x - center.x), absi(target_position.y - center.y)) <= 1:
			hit_targets.append(target_id)
			_deal_damage(target_id, damage_amount, "normal", source_id, true, {"single_target": false, "area": true, "pressure_bonus": 0, "card_effect": true})
	_emit("area_card_resolved", {"player_id": source_id, "card_id": card_id, "position": _position_payload(center), "resource_spent": damage_amount, "target_ids": hit_targets, "message": "%s 消耗%d点资源发动【压制】，命中%d名角色。" % [String(source.get("name", "")), damage_amount, hit_targets.size()]})


func _resolve_skirmish_followup(source_id: int, target_id: int, direction_id: String) -> void:
	var direction: Vector2i = {"up": Vector2i.UP, "right": Vector2i.RIGHT, "down": Vector2i.DOWN, "left": Vector2i.LEFT}.get(direction_id, Vector2i.ZERO) as Vector2i
	var destination: Vector2i = (players[source_id].get("position", Vector2i.ZERO) as Vector2i) + direction
	if direction != Vector2i.ZERO and active_bounds().has_point(destination) and not _is_occupied(destination, source_id):
		players[source_id]["position"] = destination
		players[source_id]["last_action_direction"] = _position_payload(direction)
	if target_id >= 0 and target_id < players.size() and bool(players[target_id].get("alive", false)):
		_deal_damage(target_id, 1, "normal", source_id, true, {"single_target": true, "area": false, "pressure_bonus": _duel_pressure_bonus(), "card_effect": true})
	_emit("skirmish_followup_resolved", {"player_id": source_id, "target_id": target_id, "direction": direction_id, "message": "【游击】首段未造成伤害，移动后追加1点伤害。"})


func _resolve_samurai_sword(source_id: int, first_target_id: int) -> void:
	if first_target_id < 0 or first_target_id >= players.size():
		return
	var source_position: Vector2i = players[source_id].get("position", Vector2i.ZERO) as Vector2i
	var target_position: Vector2i = players[first_target_id].get("position", Vector2i.ZERO) as Vector2i
	var direction := Vector2i(signi(target_position.x - source_position.x), signi(target_position.y - source_position.y))
	if direction == Vector2i.ZERO:
		return
	var hit_targets: Array[int] = []
	for _step: int in 4:
		var next_position: Vector2i = (players[source_id].get("position", Vector2i.ZERO) as Vector2i) + direction
		if not active_bounds().has_point(next_position) or _is_occupied(next_position, source_id):
			break
		players[source_id]["position"] = next_position
		for target_id: int in players.size():
			if target_id != source_id and bool(players[target_id].get("alive", false)) and (players[target_id].get("position", Vector2i.ZERO) as Vector2i) == next_position:
				hit_targets.append(target_id)
				_deal_damage(target_id, 1, "normal", source_id, true, {"single_target": false, "area": true, "card_effect": true})
	_emit("samurai_sword_triggered", {"player_id": source_id, "target_id": first_target_id, "target_ids": hit_targets, "message": "【武士刀】沿首次命中方向前进并伤害路径敌人。"})


func _resolve_exclusive(source_id: int, card_id: String) -> void:
	var gained_cards: Array[String] = []
	for target_id: int in players.size():
		if target_id == source_id or not bool(players[target_id].get("alive", false)):
			continue
		var target_hand: Array = players[target_id].get("hand", []) as Array
		if target_hand.is_empty():
			continue
		var card_id_to_gain: String = String(target_hand.pop_at(rng.randi_range(0, target_hand.size() - 1)))
		players[target_id]["hand"] = target_hand
		(players[source_id].get("hand", []) as Array).append(card_id_to_gain)
		gained_cards.append(card_id_to_gain)
	var source: Dictionary = players[source_id]
	var source_flags: Dictionary = source.get("flags", {}) as Dictionary
	source_flags["play_phase_ended"] = true
	source["flags"] = source_flags
	players[source_id] = source
	_emit("exclusive_resolved", {"player_id": source_id, "card_id": card_id, "card_ids": gained_cards, "message": "%s 以【独享】盲取%d张手牌，本回合后续出牌、移动、购买和技能已结束。" % [String(source.get("name", "")), gained_cards.size()]})


func _gold_panning_options(player_id: int) -> Array[String]:
	var result: Array[String] = []
	for card_value: Variant in players[player_id].get("hand", []) as Array:
		result.append(String(card_value))
	for slot: String in ["weapon", "armor", "accessory"]:
		var equipped_card_id: String = String((players[player_id].get("equipment", {}) as Dictionary).get(slot, ""))
		if not equipped_card_id.is_empty():
			result.append(equipped_card_id)
	return result


func _resolve_gold_panning(player_id: int, selected_card_id: String) -> void:
	var player_state: Dictionary = players[player_id]
	var hand: Array = player_state.get("hand", []) as Array
	var was_equipment := false
	if _remove_first(hand, selected_card_id):
		(player_state.get("discard", []) as Array).append(selected_card_id)
		_record_discard_origin(player_id, selected_card_id)
	else:
		for slot: String in ["weapon", "armor", "accessory"]:
			if String((player_state.get("equipment", {}) as Dictionary).get(slot, "")) == selected_card_id:
				was_equipment = true
				_discard_equipment_slot(player_id, slot, "gold_panning_new")
				break
	if not was_equipment:
		players[player_id] = player_state
	_change_coins(player_id, 3 if was_equipment else 2)
	_emit("gold_panning_resolved", {"player_id": player_id, "card_id": selected_card_id, "equipment": was_equipment, "coins": 3 if was_equipment else 2, "message": "%s 弃置%s并以【淘金】获得%d枚金币。" % [String(players[player_id].get("name", "")), "装备" if was_equipment else "手牌", 3 if was_equipment else 2]})


func _resolve_momentum_direction(source_id: int, target_id: int, direction_id: String) -> void:
	if target_id < 0 or target_id >= players.size() or not bool(players[target_id].get("alive", false)):
		return
	if bool((players[target_id].get("flags", {}) as Dictionary).get("movement_immune", false)) or _equipped_logical_id(target_id, "accessory") == "bedrock_new":
		_emit("movement_prevented", {"player_id": target_id, "source_id": source_id, "reason_id": "movement_immune", "message": "%s 免疫【气势】的卡牌位移。" % String(players[target_id].get("name", ""))})
		return
	var direction := {"up": Vector2i.UP, "right": Vector2i.RIGHT, "down": Vector2i.DOWN, "left": Vector2i.LEFT}.get(direction_id, Vector2i.ZERO) as Vector2i
	var moved := 0
	for _step: int in 2:
		var candidate: Vector2i = (players[target_id].get("position", Vector2i.ZERO) as Vector2i) + direction
		if not active_bounds().has_point(candidate) or _is_occupied(candidate, target_id):
			break
		players[target_id]["position"] = candidate
		moved += 1
	_emit("momentum_resolved", {"player_id": source_id, "target_id": target_id, "direction": direction_id, "steps": moved, "message": "%s 被【气势】移动%d格。" % [String(players[target_id].get("name", "")), moved]})


func _resolve_precision_direction(source_id: int, card_id: String, direction_id: String) -> void:
	var direction := {"up": Vector2i.UP, "right": Vector2i.RIGHT, "down": Vector2i.DOWN, "left": Vector2i.LEFT}.get(direction_id, Vector2i.ZERO) as Vector2i
	for _step: int in 2:
		var candidate: Vector2i = (players[source_id].get("position", Vector2i.ZERO) as Vector2i) + direction
		if not active_bounds().has_point(candidate) or _is_occupied(candidate, source_id):
			break
		players[source_id]["position"] = candidate
	var definition: Dictionary = catalog.call("resolve_card", card_id) as Dictionary
	var targets := _enemies_in_range(source_id, _definition_range(source_id, definition))
	if targets.is_empty():
		_emit("precision_stab_resolved", {"player_id": source_id, "card_id": card_id, "message": "【精巧刺击】移动后没有合法攻击目标。"})
		return
	var logical_id := String(catalog.call("logical_card_id", card_id))
	_request_skill_choice(source_id, "precision_target" if logical_id in ["precision_stab_new", "thunder_strike_new"] else "body_slam_target", logical_id, targets, {"card_id": card_id})


func _resolve_precision_target(source_id: int, card_id: String, target_id: int) -> void:
	var definition: Dictionary = catalog.call("resolve_card", card_id) as Dictionary
	_open_response_or_resolve({"source_id": source_id, "target_id": target_id, "definition": definition, "category": "attack", "card_id": card_id, "damage_bonus": 0, "unanswerable": false})


func _resolve_body_slam_target(source_id: int, card_id: String, target_id: int) -> void:
	var definition: Dictionary = catalog.call("resolve_card", card_id) as Dictionary
	definition["effects"] = [{"op": "damage", "amount": int(players[source_id].get("armor", 0)), "kind": "normal"}]
	_open_response_or_resolve({"source_id": source_id, "target_id": target_id, "definition": definition, "category": "attack", "card_id": card_id, "damage_bonus": 0, "unanswerable": false})


func _resolve_neutralize_target(_source_id: int, poison_source_id: int, target_id: int) -> void:
	var source_statuses: Dictionary = players[poison_source_id].get("statuses", {}) as Dictionary
	var amount := mini(2, int(source_statuses.get("poison", 0)))
	if amount <= 0:
		return
	source_statuses["poison"] = int(source_statuses.get("poison", 0)) - amount
	if int(source_statuses.get("poison", 0)) <= 0:
		source_statuses.erase("poison")
	players[poison_source_id]["statuses"] = source_statuses
	_apply_status(target_id, "poison", amount, poison_source_id)


func _move_back_from_last_action(player_id: int, amount: int) -> void:
	var direction := _payload_position(players[player_id].get("last_action_direction", []))
	if direction == Vector2i.ZERO:
		return
	for _step: int in amount:
		var candidate: Vector2i = (players[player_id].get("position", Vector2i.ZERO) as Vector2i) - direction
		if not active_bounds().has_point(candidate) or _is_occupied(candidate, player_id):
			break
		players[player_id]["position"] = candidate


func _resolve_action(action: Dictionary) -> void:
	var source_id: int = int(action.get("source_id", -1))
	var target_id: int = int(action.get("target_id", source_id))
	var definition: Dictionary = action.get("definition", {}) as Dictionary
	var category: String = String(action.get("category", ""))
	var damage_bonus: int = int(action.get("damage_bonus", 0))
	var pressure_bonus: int = 0
	if String(definition.get("target", "self")) == "enemy":
		pressure_bonus = _duel_pressure_bonus()
		damage_bonus += pressure_bonus
	var range_limit: int = _definition_range(source_id, definition)
	var card_id: String = String(action.get("card_id", ""))
	if bool(action.get("counterstrike_reflected", false)):
		var original_source := source_id
		source_id = int(action.get("counterstrike_owner", target_id))
		target_id = original_source
		action["source_id"] = source_id
		action["target_id"] = target_id
		if source_id >= 0 and target_id >= 0:
			var delta := (players[target_id].get("position", Vector2i.ZERO) as Vector2i) - (players[source_id].get("position", Vector2i.ZERO) as Vector2i)
			var step := Vector2i(signi(delta.x), signi(delta.y))
			var forward := (players[source_id].get("position", Vector2i.ZERO) as Vector2i) + step
			if step != Vector2i.ZERO and active_bounds().has_point(forward) and not _is_occupied(forward, source_id):
				players[source_id]["position"] = forward
		_emit("counterstrike_reflected", {"player_id": source_id, "target_id": target_id, "message": "【反戈一击】反弹攻击且向前移动1格。"})
	var resolution_count := 1
	if not card_id.is_empty() and source_id >= 0 and source_id < players.size():
		var source_modifiers: Dictionary = players[source_id].get("modifiers", {}) as Dictionary
		if int(source_modifiers.get("repeat_next_card", 0)) > 0:
			resolution_count += 1
			source_modifiers.erase("repeat_next_card")
			players[source_id]["modifiers"] = source_modifiers
			_emit("card_repeated", {"player_id": source_id, "card_id": card_id, "amount": 1, "message": "【%s】额外结算一次。" % String(definition.get("name", card_id))})
		if bool(action.get("na1_purchased", false)) and category == "attack":
			resolution_count += 1
			_emit("card_repeated", {"player_id": source_id, "card_id": card_id, "amount": 1, "source_id": "na1_foresight", "message": "Na1 的【远识】令商店攻击牌额外结算一次。"})
	for _resolution: int in resolution_count:
		if category == "attack" and _equipped_logical_id(source_id, "weapon") == "mortar_new" and target_id >= 0:
			var center: Vector2i = players[target_id].get("position", Vector2i.ZERO) as Vector2i
			for area_target_id: int in players.size():
				if area_target_id == source_id or not bool(players[area_target_id].get("alive", false)):
					continue
				var area_position: Vector2i = players[area_target_id].get("position", Vector2i.ZERO) as Vector2i
				if maxi(absi(area_position.x - center.x), absi(area_position.y - center.y)) <= 1:
					_apply_effects(source_id, area_target_id, definition.get("effects", []) as Array, category, damage_bonus, range_limit, pressure_bonus, true)
		else:
			_apply_effects(source_id, target_id, definition.get("effects", []) as Array, category, damage_bonus, range_limit, pressure_bonus, target_id < 0)
		if not pending_discard.is_empty():
			break
	if bool(action.get("na1_purchased", false)) and category == "defense" and bool(players[source_id].get("alive", false)):
		_draw_cards(source_id, 2)
		_emit("skill_effect_resolved", {"player_id": source_id, "skill_id": "na1_foresight", "card_id": card_id, "message": "Na1 的【远识】令商店防御牌额外摸2张。"})
	if bool(action.get("hand_repel", false)) and target_id >= 0 and bool(players[source_id].get("alive", false)) and bool(players[target_id].get("alive", false)):
		_push_target(target_id, source_id, 1)
	if bool(action.get("zc_frenzy", false)):
		var dealt_damage := int(players[target_id].get("health", 0)) < int(action.get("target_health_before", 0))
		_finish_zc_frenzy(action, dealt_damage)
	if bool(action.get("skirmish", false)) and target_id >= 0 and target_id < players.size() and bool(players[target_id].get("alive", false)) and int(players[target_id].get("health", 0)) >= int(action.get("target_health_before", 0)) and pending_skill_choice.is_empty():
		_request_skill_choice(source_id, "skirmish_direction", "skirmish_new", ["up", "right", "down", "left"], {"target_id": target_id})
	if not card_id.is_empty() and source_id >= 0 and source_id < players.size():
		var source: Dictionary = players[source_id]
		source["last_card_id"] = card_id
		players[source_id] = source
		if String(catalog.call("logical_card_id", card_id)) == "annihilate_new":
			_recover_annihilate(source_id, card_id)
	if target_id >= 0 and source_id != target_id and pending_skill_choice.is_empty():
		_offer_shya_break(source_id, target_id)
	if source_id >= 0 and source_id < players.size() and String(players[source_id].get("character_id", "")) == "maddy" and bool((players[source_id].get("flags", {}) as Dictionary).get("maddy_reclaim_ready", false)) and pending_skill_choice.is_empty():
		_request_skill_choice(source_id, "maddy_reclaim_offer", "maddy_reclaim", ["use", "skip"])
	var transfer_card := String(action.get("q_transfer_card", ""))
	if not transfer_card.is_empty() and bool(players[source_id].get("alive", false)):
		var recipients: Array[int] = []
		for candidate_id: int in players.size():
			if candidate_id != source_id and bool(players[candidate_id].get("alive", false)):
				recipients.append(candidate_id)
		if not recipients.is_empty():
			_request_skill_choice(source_id, "q_thunder_guard_transfer", "q_thunder_guard", recipients, {"card_id": transfer_card})


func _finish_zc_frenzy(action: Dictionary, dealt_damage: bool) -> void:
	var player_id := int(action.get("zc_frenzy_owner", action.get("source_id", -1)))
	if player_id < 0 or player_id >= players.size() or not bool(players[player_id].get("alive", false)):
		return
	if dealt_damage:
		var flags: Dictionary = players[player_id].get("flags", {}) as Dictionary
		var hit_targets: Array = flags.get("zc_frenzy_hit_targets", []) as Array
		var target_id := int(action.get("target_id", -1))
		if not hit_targets.has(target_id):
			hit_targets.append(target_id)
		flags["zc_frenzy_hit_targets"] = hit_targets
		players[player_id]["flags"] = flags
		_emit("skill_effect_resolved", {"player_id": player_id, "skill_id": "zc_frenzy", "target_id": target_id, "message": "【狂极】造成伤害，本回合不能再指定该目标。"})
	else:
		_deal_damage(player_id, 1, "true", player_id, false)
		_draw_cards(player_id, 2)
		_emit("skill_effect_resolved", {"player_id": player_id, "skill_id": "zc_frenzy", "message": "【狂极】未造成伤害，Z&C 失去1点生命并摸2张牌。"})


func _apply_effects(source_id: int, target_id: int, effects: Array, category: String, damage_bonus: int, range_limit: int, pressure_bonus: int = 0, area_action: bool = false) -> void:
	_apply_effects_from(source_id, target_id, effects, category, damage_bonus, range_limit, pressure_bonus, area_action, 0)


func _apply_effects_from(source_id: int, target_id: int, effects: Array, category: String, damage_bonus: int, range_limit: int, pressure_bonus: int, area_action: bool, start_index: int) -> void:
	var target_ids: Array[int] = [target_id]
	if target_id < 0:
		target_ids = _enemies_in_range(source_id, range_limit)
	var bonus: int = damage_bonus + (_consume_damage_bonuses(source_id, effects, category) if start_index == 0 else 0)
	var direct_action: bool = category == "attack" or category == "skill"
	var damage_context: Dictionary = {"single_target": direct_action and not area_action, "area": direct_action and area_action, "pressure_bonus": pressure_bonus, "card_effect": category in ["attack", "defense", "奇异"]}
	for effect_index: int in range(start_index, effects.size()):
		var effect_value: Variant = effects[effect_index]
		var effect: Dictionary = effect_value as Dictionary
		var operation: String = String(effect.get("op", ""))
		if operation == "self_discard" or operation == "discard_or_damage":
			var amount: int = int(effect.get("amount", 0))
			if _request_discard(source_id, amount, operation, {
				"source_id": source_id,
				"target_id": target_id,
				"effects": effects.duplicate(true),
				"category": category,
				"damage_bonus": bonus,
				"range_limit": range_limit,
				"pressure_bonus": pressure_bonus,
				"area_action": area_action,
				"effect_index": effect_index,
				"discard_amount": amount,
				"damage_shortfall": operation == "discard_or_damage"
			}):
				return
			if operation == "discard_or_damage":
				var missing: int = amount - mini(amount, (players[source_id].get("hand", []) as Array).size())
				if missing > 0:
					_deal_damage(source_id, missing, "true", -1, false)
			continue
		if TARGET_EFFECTS.has(operation):
			for affected_id: int in target_ids:
				_apply_single_effect(source_id, affected_id, effect, category, bonus, damage_context)
		else:
			_apply_single_effect(source_id, source_id, effect, category, bonus, damage_context)


func _apply_single_effect(source_id: int, target_id: int, effect: Dictionary, category: String, damage_bonus: int, damage_context: Dictionary = {}) -> void:
	if source_id < 0 or source_id >= players.size() or target_id < 0 or target_id >= players.size():
		return
	var operation: String = String(effect.get("op", ""))
	var amount: int = int(effect.get("amount", 0))
	match operation:
		"damage":
			damage_context["last_damage"] = _deal_damage(target_id, maxi(0, amount + damage_bonus), String(effect.get("kind", "normal")), source_id, category == "attack", damage_context)
		"damage_missing_health":
			var source: Dictionary = players[source_id]
			var missing_health := maxi(0, int(source.get("max_health", 0)) - int(source.get("health", 0)))
			var dynamic_amount := mini(missing_health, int(effect.get("maximum", missing_health)))
			damage_context["last_damage"] = _deal_damage(target_id, maxi(0, dynamic_amount + damage_bonus), String(effect.get("kind", "normal")), source_id, category == "attack", damage_context)
		"assassinate_damage":
			var target: Dictionary = players[target_id]
			var target_flags: Dictionary = target.get("flags", {}) as Dictionary
			var first_damage_this_round := int(target_flags.get("damaged_round", -1)) != completed_rounds
			var attack_amount := amount + (int(effect.get("bonus", 0)) if first_damage_this_round else 0) + damage_bonus
			damage_context["last_damage"] = _deal_damage(target_id, maxi(0, attack_amount), String(effect.get("kind", "normal")), source_id, true, damage_context)
			if int(damage_context.get("last_damage", 0)) > 0:
				target = players[target_id]
				target_flags = target.get("flags", {}) as Dictionary
				target_flags["damaged_round"] = completed_rounds
				target["flags"] = target_flags
				players[target_id] = target
		"status_if_damage":
			if int(damage_context.get("last_damage", 0)) > 0:
				_apply_status(target_id, String(effect.get("status", "")), int(effect.get("stacks", 1)), source_id)
		"self_damage":
			_deal_damage(source_id, amount, String(effect.get("kind", "true")), source_id, false)
		"heal":
			_heal(target_id, amount)
		"armor":
			_gain_armor(target_id, amount)
		"double_armor":
			var source: Dictionary = players[source_id]
			source["armor"] = maxi(0, int(source.get("armor", 0)) * 2)
			players[source_id] = source
		"iron_wall":
			var had_armor: bool = int(players[source_id].get("armor", 0)) > 0
			_gain_armor(source_id, 1)
			if had_armor:
				_gain_armor(source_id, 1)
				_draw_cards(source_id, 1)
		"resource":
			_change_resource(source_id, String(effect.get("resource", "mana")), amount)
		"next_attack_damage_bonus":
			var source: Dictionary = players[source_id]
			var modifiers: Dictionary = source.get("modifiers", {}) as Dictionary
			modifiers["next_attack_damage_bonus"] = int(modifiers.get("next_attack_damage_bonus", 0)) + amount
			source["modifiers"] = modifiers
			players[source_id] = source
		"attack_cost_discount":
			var source: Dictionary = players[source_id]
			var flags: Dictionary = source.get("flags", {}) as Dictionary
			flags["attack_cost_discount"] = int(flags.get("attack_cost_discount", 0)) + amount
			source["flags"] = flags
			players[source_id] = source
		"draw":
			_draw_cards(source_id, amount)
		"draw_if_turn_attack_count":
			if int(players[source_id].get("turn_attack_count", 0)) >= int(effect.get("threshold", 0)):
				_draw_cards(source_id, amount)
		"draw_if_below_half_health":
			var source: Dictionary = players[source_id]
			if int(source.get("health", 0)) * 2 < int(source.get("max_health", 1)):
				_draw_cards(source_id, amount)
		"draw_target":
			_draw_cards(target_id, amount)
		"max_resource":
			var resource := String(effect.get("resource", "stamina"))
			var maximum_key := "max_%s" % resource
			var target: Dictionary = players[target_id]
			target[maximum_key] = maxi(0, int(target.get(maximum_key, 0)) + amount)
			target[resource] = mini(int(target.get(resource, 0)), int(target.get(maximum_key, 0)))
			players[target_id] = target
			_emit("maximum_resource_changed", {"player_id": target_id, "resource": resource, "delta": amount, "maximum": int(target.get(maximum_key, 0)), "message": "%s 的%s上限变为%d。" % [String(target.get("name", "")), "体力" if resource == "stamina" else "法力", int(target.get(maximum_key, 0))]})
		"max_health":
			_change_max_health(target_id, amount, String(effect.get("source_id", "effect")))
		"trigger_event":
			_draw_event(source_id)
		"status":
			_apply_status(target_id, String(effect.get("status", "")), int(effect.get("stacks", 1)), source_id)
		"remove_status":
			_remove_status(target_id, String(effect.get("status", "")))
		"cleanse":
			_cleanse(source_id, amount)
		"coins":
			_change_coins(source_id, amount)
		"extra_action":
			# Old v5 data can still be inspected for migration and targeted tests,
			# but v10 has no action-point resource to modify.
			_emit("legacy_effect_ignored", {"player_id": source_id, "effect": "extra_action", "message": "旧版额外行动效果在新版无行动点规则中不结算。"})
		"extra_move":
			var source: Dictionary = players[source_id]
			source["moves_remaining"] = int(source.get("moves_remaining", 0)) + amount
			players[source_id] = source
		"push":
			_push_target(source_id, target_id, amount)
		"radial_push":
			if not bool((players[target_id].get("flags", {}) as Dictionary).get("movement_immune", false)):
				var delta := (players[target_id].get("position", Vector2i.ZERO) as Vector2i) - (players[source_id].get("position", Vector2i.ZERO) as Vector2i)
				var candidate := (players[target_id].get("position", Vector2i.ZERO) as Vector2i) + Vector2i(signi(delta.x), signi(delta.y))
				if active_bounds().has_point(candidate) and not _is_occupied(candidate, target_id):
					players[target_id]["position"] = candidate
				else:
					_deal_damage(target_id, 1, "true", source_id, false)
		"break_armor":
			var target: Dictionary = players[target_id]
			target["armor"] = maxi(0, int(target.get("armor", 0)) - amount)
			players[target_id] = target
		"steal_card":
			_steal_card(source_id, target_id)
		"self_discard":
			_discard_cards(source_id, amount)
		"discard_or_damage":
			var discarded: int = _discard_cards(source_id, amount)
			if discarded < amount:
				_deal_damage(source_id, amount - discarded, "true", -1, false)
		"recover_last_card":
			_recover_last_card(source_id)
		"reveal_hand":
			_emit("hand_revealed", {"player_id": source_id, "cards": (players[source_id].get("hand", []) as Array).duplicate(), "message": "%s 展示了手牌。" % String(players[source_id].get("name", ""))})
		"modifier":
			_apply_modifier(source_id, String(effect.get("modifier", "")), int(effect.get("stacks", 1)))
		"turn_flag":
			var source: Dictionary = players[source_id]
			var flags: Dictionary = source.get("flags", {}) as Dictionary
			flags[String(effect.get("flag", ""))] = bool(effect.get("value", true))
			source["flags"] = flags
			players[source_id] = source
		"gaze_next_turn":
			var target: Dictionary = players[target_id]
			var target_match_flags: Dictionary = target.get("match_flags", {}) as Dictionary
			target_match_flags["gaze_next_turn"] = true
			target["match_flags"] = target_match_flags
			players[target_id] = target
			_emit("turn_effect_queued", {"player_id": source_id, "target_id": target_id, "effect": "gaze", "message": "%s 的下回合首张非装备牌将额外消耗1体力和1法力。" % String(target.get("name", ""))})
		"guard_next_damage":
			var guarded_flags: Dictionary = players[target_id].get("match_flags", {}) as Dictionary
			guarded_flags["guard_owner_id"] = source_id
			guarded_flags["guard_until_round"] = completed_rounds
			players[target_id]["match_flags"] = guarded_flags
			_emit("guard_applied", {"player_id": source_id, "target_id": target_id, "message": "%s 将替%s承受本轮下一次伤害。" % [String(players[source_id].get("name", "")), String(players[target_id].get("name", ""))]})
		"transform_rightmost":
			var hand: Array = players[source_id].get("hand", []) as Array
			if hand.is_empty():
				return
			var physical_card_id := String(hand.back())
			var transformed_cards: Dictionary = players[source_id].get("transformed_cards", {}) as Dictionary
			transformed_cards[physical_card_id] = String(effect.get("card_id", "iron_body_new"))
			players[source_id]["transformed_cards"] = transformed_cards
			_emit("card_transformed", {"player_id": source_id, "card_id": physical_card_id, "into_card_id": String(effect.get("card_id", "iron_body_new")), "message": "%s 将最右手牌变为【钢筋铁骨】。" % String(players[source_id].get("name", ""))})


func _card_definition_for_player(player_id: int, card_id: String) -> Dictionary:
	var original: Dictionary = catalog.call("resolve_card", card_id) as Dictionary
	if original.is_empty() or player_id < 0 or player_id >= players.size():
		return original
	var transformed_cards: Dictionary = players[player_id].get("transformed_cards", {}) as Dictionary
	var replacement_id := String(transformed_cards.get(card_id, ""))
	if replacement_id.is_empty():
		return original
	var replacement: Dictionary = catalog.call("resolve_card", "%s#001" % replacement_id) as Dictionary
	if replacement.is_empty():
		return original
	replacement["instance_id"] = card_id
	replacement["suit"] = original.get("suit", "none")
	replacement["rank"] = int(original.get("rank", 0))
	replacement["color"] = original.get("color", "none")
	return replacement


func _consume_damage_bonuses(source_id: int, effects: Array, category: String) -> int:
	var has_damage: bool = false
	for effect_value: Variant in effects:
		if effect_value is Dictionary and String((effect_value as Dictionary).get("op", "")) == "damage":
			has_damage = true
			break
	if not has_damage:
		return 0
	var source: Dictionary = players[source_id]
	var statuses: Dictionary = source.get("statuses", {}) as Dictionary
	var modifiers: Dictionary = source.get("modifiers", {}) as Dictionary
	var bonus: int = 0
	if category == "attack" and int(statuses.get("scorch", 0)) > 0:
		bonus += 1
		_decrement_status(statuses, "scorch")
	if int(modifiers.get("echo", 0)) > 0:
		bonus += 1
		modifiers.erase("echo")
	if category == "attack" and int(modifiers.get("next_attack_damage_bonus", 0)) > 0:
		bonus += 1
		modifiers["next_attack_damage_bonus"] = int(modifiers.get("next_attack_damage_bonus", 0)) - 1
		if int(modifiers.get("next_attack_damage_bonus", 0)) <= 0:
			modifiers.erase("next_attack_damage_bonus")
	source["statuses"] = statuses
	source["modifiers"] = modifiers
	players[source_id] = source
	return bonus


func _resolve_landing(player_id: int) -> void:
	var active: Dictionary = players[player_id]
	var position: Vector2i = active.get("position", Vector2i.ZERO) as Vector2i
	var kind: String = tile_kind(position)
	if String(active.get("character_id", "")) == "na1":
		_change_coins(player_id, 1)
		_emit("passive_triggered", {"player_id": player_id, "skill_id": "na1_gold", "message": "Na1 停留在格子上，通过【金纵】获得1枚金币。"})
		active = players[player_id]
	if String(active.get("character_id", "")) == "maddy":
		var maddy_match_flags: Dictionary = active.get("match_flags", {}) as Dictionary
		if (maddy_match_flags.get("maddy_reclaimed_tiles", []) as Array).has(_tile_key(position)):
			_heal(player_id, 1)
			_draw_cards(player_id, 1)
			_emit("passive_triggered", {"player_id": player_id, "skill_id": "maddy_reclaim", "position": _position_payload(position), "message": "Maddy 进入【开垦】指定格，回复1点生命并摸1张牌。"})
			active = players[player_id]
	if kind == "wealth":
		var coin_amount: int = 2
		active["coins"] = int(active.get("coins", 0)) + coin_amount
		spent_tiles[_tile_key(position)] = true
		players[player_id] = active
		_emit("wealth_collected", {"player_id": player_id, "amount": coin_amount, "message": "%s 获得%d金币。" % [String(active.get("name", "")), coin_amount]})
	elif kind == "event":
		spent_tiles[_tile_key(position)] = true
		if _equipped_logical_id(player_id, "accessory") == "old_map_new":
			_request_skill_choice(player_id, "old_map_choice", "old_map_new", ["draw", "coins"])
		else:
			_draw_event(player_id)


func _draw_event(player_id: int) -> void:
	last_event = event_deck.call("draw") as Dictionary
	if last_event.is_empty():
		return
	_emit("event_drawn", {"player_id": player_id, "event_id": String(last_event.get("id", "")), "message": "%s 抽到事件【%s】。" % [String(players[player_id].get("name", "")), String(last_event.get("title", ""))]})
	if last_event.has("choices"):
		pending_event = last_event.duplicate(true)
	else:
		_apply_effects(player_id, player_id, last_event.get("effects", []) as Array, "event", 0, 0)
	var explorer_flags: Dictionary = players[player_id].get("match_flags", {}) as Dictionary
	if _equipped_logical_id(player_id, "accessory") == "explorer_hat_new" and not bool(explorer_flags.get("explorer_hat_triggering", false)):
		explorer_flags["explorer_hat_triggering"] = true
		players[player_id]["match_flags"] = explorer_flags
		_emit("equipment_triggered", {"player_id": player_id, "card_id": "explorer_hat_new", "message": "【探险家帽】额外触发一个随机事件。"})
		_draw_event(player_id)
		explorer_flags = players[player_id].get("match_flags", {}) as Dictionary
		explorer_flags.erase("explorer_hat_triggering")
		players[player_id]["match_flags"] = explorer_flags


func _event_choice_is_legal(active: Dictionary, choice: Dictionary) -> bool:
	if not choice.has("requires"):
		return true
	var requirements: Dictionary = choice.get("requires", {}) as Dictionary
	if int(active.get("coins", 0)) < int(requirements.get("coins", 0)):
		return false
	if int(active.get("stamina", 0)) < int(requirements.get("stamina", 0)):
		return false
	if int(active.get("mana", 0)) < int(requirements.get("mana", 0)):
		return false
	if (active.get("hand", []) as Array).size() < int(requirements.get("hand", 0)):
		return false
	return true


func _valid_response_cards(player_id: int, action_category: String) -> Array[String]:
	var result: Array[String] = []
	var seen: Dictionary = {}
	var available_cards: Array = (players[player_id].get("hand", []) as Array).duplicate()
	available_cards.append_array(players[player_id].get("purchased_hand", []) as Array)
	for card_value: Variant in available_cards:
		var card_id: String = String(card_value)
		if seen.has(card_id):
			continue
		seen[card_id] = true
		var definition: Dictionary = catalog.call("resolve_card", card_id) as Dictionary
		var logical_id := String(catalog.call("logical_card_id", card_id))
		var guardian_response := _equipped_logical_id(player_id, "accessory") == "guardian_ring_new" and String(definition.get("category", "")) == "attack" and not bool((players[player_id].get("flags", {}) as Dictionary).get("guardian_ring_used", false))
		if (not ["heavenly_sense_new", "shrug_off_new"].has(logical_id) and not guardian_response) or (not guardian_response and not _can_pay(player_id, definition)):
			continue
		if guardian_response:
			result.append(card_id)
			continue
		for effect_value: Variant in definition.get("effects", []) as Array:
			if effect_value is Dictionary and String((effect_value as Dictionary).get("op", "")) == "negate" and String((effect_value as Dictionary).get("category", "")) == action_category:
				result.append(card_id)
				break
	return result


func _can_pay(player_id: int, definition: Dictionary) -> bool:
	var cost: Dictionary = _effective_cost(player_id, definition)
	return int(players[player_id].get("stamina", 0)) >= int(cost.get("stamina", 0)) and int(players[player_id].get("mana", 0)) >= int(cost.get("mana", 0))


func _record_public_card(player_id: int, card_id: String, target_id: int, play_kind: String) -> void:
	var history: Array = players[player_id].get("public_card_history", []) as Array
	history.append({
		"round": completed_rounds + 1,
		"card_id": card_id,
		"target_id": target_id,
		"play_kind": play_kind
	})
	while history.size() > 5:
		history.pop_front()
	players[player_id]["public_card_history"] = history


func _public_play_history_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for player_state: Dictionary in players:
		result.append({
			"player_id": int(player_state.get("id", -1)),
			"entries": (player_state.get("public_card_history", []) as Array).duplicate(true)
		})
	return result


func _effective_cost(player_id: int, definition: Dictionary) -> Dictionary:
	var base_cost: Dictionary = definition.get("cost", {}) as Dictionary
	var stamina: int = int(base_cost.get("stamina", 0))
	var mana: int = int(base_cost.get("mana", 0))
	var player_state: Dictionary = players[player_id]
	if _equipped_logical_id(player_id, "accessory") == "element_ring_new" and _is_elemental_card(definition) and not bool((player_state.get("flags", {}) as Dictionary).get("element_ring_used", false)):
		stamina = maxi(0, stamina - 1)
		mana = maxi(0, mana - 1)
	if String(player_state.get("character_id", "")) == "k":
		var category_uses: Dictionary = player_state.get("turn_category_uses", {}) as Dictionary
		var category := String(definition.get("category", ""))
		var next_use := int(category_uses.get(category, 0)) + 1
		if category == "奇异" and next_use % 2 == 1:
			stamina = maxi(0, stamina - 1)
			mana = maxi(0, mana - 1)
		elif category == "attack" and next_use % 2 == 0:
			stamina += 1
	var modifiers: Dictionary = player_state.get("modifiers", {}) as Dictionary
	if int(modifiers.get("free_cast", 0)) > 0:
		return {"stamina": 0, "mana": 0}
	var flags: Dictionary = player_state.get("flags", {}) as Dictionary
	if (flags.get("free_card_ids", []) as Array).has(String(definition.get("instance_id", definition.get("id", "")))):
		return {"stamina": 0, "mana": 0}
	var match_flags: Dictionary = player_state.get("match_flags", {}) as Dictionary
	if player_id == active_player_index and bool(match_flags.get("gaze_first_card_pending", false)) and String(definition.get("category", "")) != "equipment":
		stamina += 1
		mana += 1
	if String(catalog.call("logical_card_id", String(definition.get("instance_id", definition.get("id", ""))))) == "annihilate_new":
		var annihilate_costs: Dictionary = flags.get("annihilate_cost_increases", {}) as Dictionary
		stamina += int(annihilate_costs.get(String(definition.get("instance_id", "")), 0))
	if String(definition.get("category", "")) == "attack":
		stamina = maxi(0, stamina - int(flags.get("attack_cost_discount", 0)))
		if _equipped_logical_id(player_id, "weapon") == "overlimit_pistol_new":
			stamina = maxi(0, stamina - 1)
	if String(catalog.call("logical_card_id", String(definition.get("instance_id", definition.get("id", "")))) ) == "rapid_fire_new":
		var previous_card: Dictionary = catalog.call("resolve_card", String(player_state.get("last_card_id", ""))) as Dictionary
		if String(previous_card.get("category", "")) == "attack":
			stamina = maxi(0, stamina - 1)
	if String(player_state.get("character_id", "")) == "k" and String(definition.get("category", "skill")) == "skill" and not bool(flags.get("spell_discount_used", false)):
		mana = maxi(0, mana - 1)
	return {"stamina": stamina, "mana": mana}


func _pay_cost(player_id: int, definition: Dictionary) -> void:
	var player_state: Dictionary = players[player_id]
	var modifiers: Dictionary = player_state.get("modifiers", {}) as Dictionary
	var used_free_cast: bool = int(modifiers.get("free_cast", 0)) > 0
	var cost: Dictionary = _effective_cost(player_id, definition)
	player_state["stamina"] = int(player_state.get("stamina", 0)) - int(cost.get("stamina", 0))
	player_state["mana"] = int(player_state.get("mana", 0)) - int(cost.get("mana", 0))
	if used_free_cast:
		modifiers.erase("free_cast")
		player_state["modifiers"] = modifiers
	var flags: Dictionary = player_state.get("flags", {}) as Dictionary
	if _equipped_logical_id(player_id, "accessory") == "element_ring_new" and _is_elemental_card(definition) and not bool(flags.get("element_ring_used", false)):
		flags["element_ring_used"] = true
	var played_card_id := String(definition.get("instance_id", definition.get("id", "")))
	var free_card_ids: Array = (flags.get("free_card_ids", []) as Array).duplicate()
	if _remove_first(free_card_ids, played_card_id):
		flags["free_card_ids"] = free_card_ids
		player_state["flags"] = flags
	var match_flags: Dictionary = player_state.get("match_flags", {}) as Dictionary
	if player_id == active_player_index and bool(match_flags.get("gaze_first_card_pending", false)) and String(definition.get("category", "")) != "equipment":
		match_flags.erase("gaze_first_card_pending")
		player_state["match_flags"] = match_flags
	if String(player_state.get("character_id", "")) == "k" and String(definition.get("category", "skill")) == "skill" and not bool(flags.get("spell_discount_used", false)):
		flags["spell_discount_used"] = true
		player_state["flags"] = flags
	players[player_id] = player_state
	var category := String(definition.get("category", ""))
	if category == "奇异" or category == "attack":
		var category_uses: Dictionary = player_state.get("turn_category_uses", {}) as Dictionary
		category_uses[category] = int(category_uses.get(category, 0)) + 1
		player_state["turn_category_uses"] = category_uses
		if category == "attack":
			player_state["turn_attack_count"] = int(player_state.get("turn_attack_count", 0)) + 1
			if int((player_state.get("flags", {}) as Dictionary).get("attack_cost_discount", 0)) > 0:
				var attack_flags: Dictionary = player_state.get("flags", {}) as Dictionary
				attack_flags["attack_cost_discount"] = int(attack_flags.get("attack_cost_discount", 0)) + 1
				player_state["flags"] = attack_flags
		players[player_id] = player_state


func _definition_range(player_id: int, definition: Dictionary) -> int:
	var category := String(definition.get("category", ""))
	if definition.has("local_range"):
		return int(definition.get("local_range", 0))
	if category == "attack" and bool(equipped_definition(player_id, "weapon").get("line_attack", false)):
		return board_size
	if bool(definition.get("ignore_distance", false)) or category == "奇异":
		return board_size
	if category != "attack":
		return int(definition.get("range", 0))
	if bool((players[player_id].get("flags", {}) as Dictionary).get("attacks_ignore_distance", false)):
		return board_size
	var profession := String(players[player_id].get("profession", ""))
	var result := int(PROFESSION_ATTACK_RANGES.get(profession, 1))
	var weapon_instance := String((players[player_id].get("equipment", {}) as Dictionary).get("weapon", ""))
	if not weapon_instance.is_empty():
		var weapon_definition: Dictionary = equipped_definition(player_id, "weapon")
		result += int(weapon_definition.get("attack_range_bonus", 0))
	return result


func equipped_definition(player_id: int, slot: String) -> Dictionary:
	if player_id < 0 or player_id >= players.size():
		return {}
	var copy_id := String((players[player_id].get("equipment_copies", {}) as Dictionary).get(slot, ""))
	if not copy_id.is_empty():
		return catalog.call("resolve_card", copy_id) as Dictionary
	var instance_id := String((players[player_id].get("equipment", {}) as Dictionary).get(slot, ""))
	return catalog.call("resolve_card", instance_id) as Dictionary if not instance_id.is_empty() else {}


func _apply_start_turn_equipment(player_id: int) -> void:
	var accessory_id := _equipped_logical_id(player_id, "accessory")
	var triggered := false
	match accessory_id:
		"strong_shell_new":
			players[player_id]["stamina"] = int(players[player_id].get("stamina", 0)) + 1
			triggered = true
		"velvet_ring_new":
			players[player_id]["mana"] = int(players[player_id].get("mana", 0)) + 1
			triggered = true
		"unyielding_heart_new":
			_heal(player_id, 1)
			triggered = true
		"hell_collar_new":
			_deal_damage(player_id, 1, "true", player_id, false)
			if bool(players[player_id].get("alive", false)):
				_draw_cards(player_id, 2)
			triggered = true
	if _equipped_logical_id(player_id, "armor") == "endless_line_new":
		(players[player_id].get("hand", []) as Array).append("defensive_line_new#001")
		_emit("card_created", {"player_id": player_id, "card_id": "defensive_line_new#001", "message": "%s 的【无尽防线】将【防线】置入手牌。" % String(players[player_id].get("name", ""))})
	var weapon_id := _equipped_logical_id(player_id, "weapon")
	if weapon_id == "heavy_blade_new":
		_change_resource(player_id, "stamina", -1)
	elif weapon_id == "hell_forge_sword_new":
		_deal_damage(player_id, 1, "true", player_id, false)


func _consume_equipment_durability(player_id: int, slot: String, source_id: String) -> void:
	var durability: Dictionary = players[player_id].get("equipment_durability", {}) as Dictionary
	var slot_durability: Dictionary = durability.get(slot, {}) as Dictionary
	var current := int(slot_durability.get("current", -1))
	if current < 0:
		return
	current = maxi(0, current - 1)
	slot_durability["current"] = current
	durability[slot] = slot_durability
	players[player_id]["equipment_durability"] = durability
	_emit("equipment_durability_changed", {"player_id": player_id, "slot": slot, "current": current, "maximum": int(slot_durability.get("maximum", current)), "source_id": source_id, "message": "%s 的装备耐久降至%d。" % [String(players[player_id].get("name", "")), current]})
	if current == 0:
		_discard_equipment_slot(player_id, slot, "durability_depleted")


func _tick_equipment_durability(player_id: int) -> void:
	# Unless a card explicitly says otherwise, equipment wears down once per owner turn.
	for slot: String in ["weapon", "armor", "accessory"]:
		if not _equipped_logical_id(player_id, slot).is_empty():
			_consume_equipment_durability(player_id, slot, "turn_end")


func _equipped_logical_id(player_id: int, slot: String) -> String:
	var definition := equipped_definition(player_id, slot)
	return String(definition.get("card_id", definition.get("id", "")))


func _move_range(player_id: int) -> int:
	var result: int = int(rules.get("move_range", 3))
	var player_state: Dictionary = players[player_id]
	if String(player_state.get("character_id", "")) == "zc":
		result += 1
	if _equipped_logical_id(player_id, "accessory") in ["hermes_wings", "hermes_wings_new"]:
		result = 3
	return result


func _distance(source_id: int, target_id: int) -> int:
	var source: Vector2i = players[source_id].get("position", Vector2i.ZERO) as Vector2i
	var target: Vector2i = players[target_id].get("position", Vector2i.ZERO) as Vector2i
	return maxi(absi(source.x - target.x), absi(source.y - target.y))


func _enemies_in_range(source_id: int, range_limit: int) -> Array[int]:
	var result: Array[int] = []
	for target_id: int in players.size():
		if target_id != source_id and bool(players[target_id].get("alive", false)) and _distance(source_id, target_id) <= range_limit:
			result.append(target_id)
	return result


func _deal_damage(target_id: int, amount: int, kind: String, source_id: int, is_attack: bool, damage_context: Dictionary = {}) -> int:
	if amount <= 0 or not bool(players[target_id].get("alive", false)):
		return 0
	var target: Dictionary = players[target_id]
	var source: Dictionary = players[source_id] if source_id >= 0 and source_id < players.size() else {}
	var decoy_flags: Dictionary = target.get("flags", {}) as Dictionary
	if bool(decoy_flags.get("decoy_ready", false)):
		decoy_flags.erase("decoy_ready")
		target["flags"] = decoy_flags
		players[target_id] = target
		_emit("damage_prevented", {"source_id": source_id, "target_id": target_id, "amount": amount, "reason_id": "decoy", "message": "%s 的【替身】防止了本次伤害。" % String(target.get("name", ""))})
		if source_id >= 0 and source_id < players.size() and not (players[source_id].get("hand", []) as Array).is_empty():
			_request_skill_choice(target_id, "decoy_discard", "decoy_new", (players[source_id].get("hand", []) as Array).duplicate(), {"attacker_id": source_id})
		return 0
	var guarded_flags: Dictionary = target.get("match_flags", {}) as Dictionary
	var guard_owner_id := int(guarded_flags.get("guard_owner_id", -1))
	if not bool(damage_context.get("guard_redirect", false)) and int(guarded_flags.get("guard_until_round", -1)) == completed_rounds and guard_owner_id >= 0 and guard_owner_id < players.size() and bool(players[guard_owner_id].get("alive", false)):
		guarded_flags.erase("guard_owner_id")
		guarded_flags.erase("guard_until_round")
		target["match_flags"] = guarded_flags
		players[target_id] = target
		var guarded_damage := _deal_damage(guard_owner_id, amount, kind, source_id, is_attack, {"guard_redirect": true, "card_effect": bool(damage_context.get("card_effect", false))})
		if guarded_damage > 0:
			_gain_armor(guard_owner_id, 1)
		_emit("guard_redirected", {"player_id": guard_owner_id, "target_id": target_id, "amount": guarded_damage, "message": "%s 为%s承受伤害并获得1点护甲。" % [String(players[guard_owner_id].get("name", "")), String(target.get("name", ""))]})
		return 0
	var charm_damage_flags: Dictionary = target.get("flags", {}) as Dictionary
	if _equipped_logical_id(target_id, "armor") == "shadow_charm_new" and bool(charm_damage_flags.get("shadow_charm_ready", false)):
		charm_damage_flags.erase("shadow_charm_ready")
		target["flags"] = charm_damage_flags
		players[target_id] = target
		_emit("damage_prevented", {"source_id": source_id, "target_id": target_id, "amount": amount, "reason_id": "shadow_charm", "message": "%s 的【暗影护符】无效了隐匿后的首次伤害。" % String(target.get("name", ""))})
		return 0
	if not source.is_empty() and source_id != target_id and bool((source.get("flags", {}) as Dictionary).get("cannot_deal_damage", false)):
		_emit("damage_prevented", {"source_id": source_id, "target_id": target_id, "amount": amount, "reason_id": "k_brain", "message": "%s 本回合无法造成伤害。" % String(source.get("name", ""))})
		return 0
	var final_amount: int = amount
	if _equipped_logical_id(target_id, "armor") == "resonance_robe_new" and kind != "true":
		var negative_statuses: Dictionary = target.get("statuses", {}) as Dictionary
		var negative_count := 0
		for status_id: String in ["paralyze", "bleed", "poison", "confusion", "scorch"]:
			if int(negative_statuses.get(status_id, 0)) > 0:
				negative_count += 1
		final_amount = maxi(0, final_amount - mini(3, negative_count))
	if _equipped_logical_id(target_id, "armor") == "rhythm_armor_new":
		var rhythm_flags: Dictionary = target.get("match_flags", {}) as Dictionary
		var rhythm_round := int(rhythm_flags.get("rhythm_armor_round", -1))
		var received := int(rhythm_flags.get("rhythm_armor_damage", 0)) if rhythm_round == completed_rounds else 0
		final_amount = mini(final_amount, maxi(0, 2 - received))
		rhythm_flags["rhythm_armor_round"] = completed_rounds
		rhythm_flags["rhythm_armor_damage"] = received + final_amount
		target["match_flags"] = rhythm_flags
	if _equipped_logical_id(target_id, "weapon") == "shuriken_kunai_new":
		var kunai_flags: Dictionary = target.get("match_flags", {}) as Dictionary
		if int(kunai_flags.get("shuriken_guard_round", -1)) != completed_rounds:
			final_amount = maxi(0, final_amount - 1)
			kunai_flags["shuriken_guard_round"] = completed_rounds
			target["match_flags"] = kunai_flags
	if _equipped_logical_id(target_id, "armor") == "lost_path_new" and not bool(damage_context.get("card_effect", false)):
		_emit("damage_prevented", {"source_id": source_id, "target_id": target_id, "amount": amount, "reason_id": "lost_path", "message": "%s 的【迷途】免疫非卡牌伤害。" % String(target.get("name", ""))})
		return 0
	var hell_forge_bonus := false
	if is_attack and not source.is_empty() and source_id != target_id and _equipped_logical_id(source_id, "weapon") == "heavy_blade_new":
		final_amount += 1
	if not source.is_empty() and source_id != target_id and _equipped_logical_id(source_id, "weapon") == "shuriken_kunai_new":
		final_amount += 1
	if is_attack and not source.is_empty() and source_id != target_id and _equipped_logical_id(source_id, "weapon") == "shield_axe_guardian_new" and int(target.get("armor", 0)) > 0:
		final_amount += 1
	if not source.is_empty() and source_id != target_id and _equipped_logical_id(source_id, "weapon") == "hell_forge_sword_new" and not bool((source.get("flags", {}) as Dictionary).get("hell_forge_used", false)):
		final_amount += 1
		hell_forge_bonus = true
	if target_id == active_player_index and _equipped_logical_id(target_id, "armor") == "crimson_cape_new":
		final_amount = maxi(0, final_amount - 1)
	if not source.is_empty() and source_id != target_id and String(source.get("character_id", "")) == "ginger" and int(target.get("health", 0)) * 2 <= int(target.get("max_health", 1)):
		final_amount += 1
	if kind == "lightning" and not source.is_empty() and String(source.get("character_id", "")) == "q":
		var source_flags: Dictionary = source.get("flags", {}) as Dictionary
		if not bool(source_flags.get("thunder_bonus_used", false)):
			final_amount += 1
			source_flags["thunder_bonus_used"] = true
			source["flags"] = source_flags
			players[source_id] = source
	if kind == "lightning" and not source.is_empty() and _equipped_logical_id(source_id, "accessory") == "thunderbird_feather":
		var source_flags: Dictionary = source.get("flags", {}) as Dictionary
		if not bool(source_flags.get("thunderbird_used", false)):
			final_amount += 1
			source_flags["thunderbird_used"] = true
			source["flags"] = source_flags
			players[source_id] = source
	if kind != "true":
		var target_statuses: Dictionary = target.get("statuses", {}) as Dictionary
		if int(target_statuses.get("hidden", 0)) > 0:
			final_amount = maxi(0, final_amount - 1)
		if (kind == "fire" or kind == "lightning") and _equipped_logical_id(target_id, "accessory") == "moonlight_protection":
			final_amount = maxi(0, final_amount - 1)
		if is_attack and _equipped_logical_id(target_id, "armor") == "bastion":
			var target_flags: Dictionary = target.get("flags", {}) as Dictionary
			if not bool(target_flags.get("bastion_used", false)):
				final_amount = maxi(0, final_amount - 1)
				target_flags["bastion_used"] = true
				target["flags"] = target_flags
	var na1_flags: Dictionary = target.get("match_flags", {}) as Dictionary
	if String(target.get("character_id", "")) == "na1" and final_amount > 0 and int(na1_flags.get("na1_gold_prevent_round", -1)) != completed_rounds:
		var coin_block: int = mini(final_amount, 1)
		if coin_block > 0:
			target["coins"] = int(target.get("coins", 0)) - coin_block
			final_amount -= coin_block
			na1_flags["na1_gold_prevent_round"] = completed_rounds
			target["match_flags"] = na1_flags
			_emit("damage_prevented", {"target_id": target_id, "amount": coin_block, "reason_id": "na1_gold", "message": "Na1 通过【金纵】失去1枚金币，抵消1点伤害；本整轮不再触发。"})
	var ignores_armor := source_id >= 0 and source_id < players.size() and is_attack and (bool((players[source_id].get("flags", {}) as Dictionary).get("attacks_ignore_armor", false)) or _equipped_logical_id(source_id, "weapon") == "needle_new")
	if kind != "true" and kind != "piercing" and final_amount > 0 and not ignores_armor:
		var blocked: int = mini(int(target.get("armor", 0)), final_amount)
		target["armor"] = int(target.get("armor", 0)) - blocked
		final_amount -= blocked
	target["health"] = int(target.get("health", 0)) - final_amount
	if final_amount > 0:
		var damage_flags: Dictionary = target.get("match_flags", {}) as Dictionary
		damage_flags["damage_received_round"] = completed_rounds
		target["match_flags"] = damage_flags
	players[target_id] = target
	if int(target.get("health", 0)) <= 0:
		var death_fight_flags: Dictionary = target.get("flags", {}) as Dictionary
		if bool(death_fight_flags.get("death_fight_ready", false)) and int(target.get("max_health", 1)) > 1:
			death_fight_flags.erase("death_fight_ready")
			target["flags"] = death_fight_flags
			target["max_health"] = int(target.get("max_health", 1)) - 1
			target["health"] = 1
			players[target_id] = target
			_emit("death_fight_triggered", {"player_id": target_id, "message": "%s 触发【死战】：失去1点生命上限并回复至1生命。" % String(target.get("name", ""))})
			return final_amount
		if _equipped_logical_id(target_id, "armor") == "black_hound_new":
			var restored := 1 - int(target.get("health", 0))
			var hound_flags: Dictionary = target.get("match_flags", {}) as Dictionary
			hound_flags["black_hound_debt"] = int(hound_flags.get("black_hound_debt", 0)) + restored
			target["match_flags"] = hound_flags
			target["health"] = 1
			players[target_id] = target
			_emit("black_hound_triggered", {"player_id": target_id, "restored": restored, "message": "%s 的【黑犬之佑】恢复至1生命，回合结束后偿还%d点代价。" % [String(target.get("name", "")), restored]})
			return final_amount
	if final_amount > 0 and _equipped_logical_id(target_id, "armor") == "hell_armor_new":
		_gain_armor(target_id, final_amount)
	var is_area: bool = bool(damage_context.get("area", false))
	var is_single_target: bool = bool(damage_context.get("single_target", false))
	var pressure_damage: int = mini(final_amount, int(damage_context.get("pressure_bonus", 0)))
	if final_amount > 0 and is_area:
		match_metrics["area_damage"] = int(match_metrics.get("area_damage", 0)) + final_amount
	elif final_amount > 0 and is_single_target:
		match_metrics["single_target_damage"] = int(match_metrics.get("single_target_damage", 0)) + final_amount
	if pressure_damage > 0:
		match_metrics["pressure_damage"] = int(match_metrics.get("pressure_damage", 0)) + pressure_damage
	_emit("damage", {
		"source_id": source_id,
		"target_id": target_id,
		"amount": final_amount,
		"kind": kind,
		"area": is_area,
		"duel_pressure_bonus": int(damage_context.get("pressure_bonus", 0)),
		"message": "%s 受到%d点%s伤害。" % [String(target.get("name", "")), final_amount, _damage_name(kind)]
	})
	if final_amount > 0 and source_id >= 0 and source_id < players.size() and source_id != target_id:
		if hell_forge_bonus:
			var forge_flags: Dictionary = players[source_id].get("flags", {}) as Dictionary
			forge_flags["hell_forge_used"] = true
			players[source_id]["flags"] = forge_flags
		var source_stats: Dictionary = players[source_id].get("stats", {}) as Dictionary
		source_stats["damage_dealt"] = int(source_stats.get("damage_dealt", 0)) + final_amount
		players[source_id]["stats"] = source_stats
		if _equipped_logical_id(source_id, "weapon") == "crowbar_new":
			var crowbar_flags: Dictionary = players[source_id].get("flags", {}) as Dictionary
			crowbar_flags["crowbar_ready"] = true
			players[source_id]["flags"] = crowbar_flags
			_emit("equipment_trigger_ready", {"player_id": source_id, "card_id": "crowbar_new", "message": "【撬棍】本次实际造成伤害，可选择崩坏一个格子。"})
		if _equipped_logical_id(source_id, "weapon") == "samurai_sword_new":
			var samurai_flags: Dictionary = players[source_id].get("flags", {}) as Dictionary
			if not bool(samurai_flags.get("samurai_sword_used", false)):
				samurai_flags["samurai_sword_used"] = true
				players[source_id]["flags"] = samurai_flags
				_resolve_samurai_sword(source_id, target_id)
		if _equipped_logical_id(source_id, "weapon") == "shadow_blade_new":
			var source_flags: Dictionary = players[source_id].get("flags", {}) as Dictionary
			source_flags["shadow_blade_turn_damage"] = int(source_flags.get("shadow_blade_turn_damage", 0)) + final_amount
			players[source_id]["flags"] = source_flags
			if int(source_flags.get("shadow_blade_turn_damage", 0)) > 3:
				_apply_status(source_id, "hidden", 1, source_id)
		if String(players[source_id].get("character_id", "")) == "shya":
			_gain_flash(source_id, 1, "shya_flash_damage")
		_apply_on_damage_equipment(source_id, target_id, is_attack)
		if _equipped_logical_id(source_id, "weapon") == "prospect_hammer_new":
			var prospect_position: Vector2i = players[target_id].get("position", Vector2i.ZERO) as Vector2i
			if active_bounds().has_point(prospect_position):
				wealth_tiles.append(prospect_position)
				spent_tiles.erase(_tile_key(prospect_position))
				_emit("tile_converted", {"player_id": source_id, "target_id": target_id, "position": _position_payload(prospect_position), "kind": "wealth", "message": "【勘探锤】将目标所在格转为财富格。"})
		if _equipped_logical_id(source_id, "weapon") == "wind_raise_new" and pending_skill_choice.is_empty():
			_request_skill_choice(source_id, "wind_raise_direction", "wind_raise_new", ["up", "right", "down", "left"], {"target_id": target_id})
		if _equipped_logical_id(source_id, "accessory") == "wolf_fang_new" and pending_skill_choice.is_empty():
			_request_skill_choice(source_id, "wolf_fang_choice", "wolf_fang_new", ["heal", "bleed"], {"target_id": target_id})
		if is_attack and _equipped_logical_id(source_id, "accessory") == "assassination_order_new" and pending_skill_choice.is_empty():
			var assassination_hand: Array = players[target_id].get("hand", []) as Array
			if not assassination_hand.is_empty():
				_request_skill_choice(source_id, "assassination_order_discard", "assassination_order_new", assassination_hand.duplicate(), {"target_id": target_id})
		_trigger_ginger_waist(source_id, target_id)
		if source_id == active_player_index and String(players[source_id].get("character_id", "")) == "maddy":
			var source_flags: Dictionary = players[source_id].get("flags", {}) as Dictionary
			var source_skill_uses: Dictionary = players[source_id].get("skill_uses", {}) as Dictionary
			if int(source_skill_uses.get("maddy_reclamation", 0)) < 1:
				source_flags["maddy_reclaim_ready"] = true
				players[source_id]["flags"] = source_flags
	if final_amount > 0 and source_id >= 0 and source_id < players.size() and source_id != target_id and not bool(damage_context.get("thorn_reflect", false)) and _equipped_logical_id(target_id, "armor") == "thorn_armor_new":
		_deal_damage(source_id, 1, "normal", target_id, false, {"thorn_reflect": true})
		_emit("thorn_reflected", {"player_id": target_id, "target_id": source_id, "amount": 1, "message": "%s 的【荆棘铠甲】反造成1点伤害。" % String(players[target_id].get("name", ""))})
	if final_amount > 0 and source_id >= 0 and source_id < players.size() and source_id != target_id and _equipped_logical_id(target_id, "armor") == "strange_face_new" and not (players[target_id].get("hand", []) as Array).is_empty() and not (players[source_id].get("hand", []) as Array).is_empty() and pending_skill_choice.is_empty():
		_request_skill_choice(target_id, "strange_face_self_card", "strange_face_new", (players[target_id].get("hand", []) as Array).duplicate(), {"attacker_id": source_id})
	if final_amount > 0 and source_id >= 0 and source_id < players.size() and source_id != target_id and _equipped_logical_id(target_id, "armor") == "fear_shield_new":
		_push_target(target_id, source_id, 1)
		_emit("fear_shield_triggered", {"player_id": target_id, "target_id": source_id, "message": "%s 的【恐盾】令伤害来源后退1格。" % String(players[target_id].get("name", ""))})
	if final_amount > 0 and source_id >= 0 and source_id < players.size() and source_id != target_id and _equipped_logical_id(target_id, "armor") == "flame_cape_new":
		_deal_damage(source_id, 1, "fire", target_id, false, {"flame_cape_reflect": true})
		_apply_status(source_id, "scorch", 1, target_id)
		_emit("flame_cape_triggered", {"player_id": target_id, "target_id": source_id, "message": "%s 的【火焰披风】反造成火焰伤害并施加灼热。" % String(players[target_id].get("name", ""))})
	if final_amount > 0 and source_id >= 0 and source_id < players.size() and source_id != target_id and _equipped_logical_id(target_id, "armor") == "burning_cape_new" and pending_skill_choice.is_empty():
		var cape_options := _elemental_hand_cards(target_id)
		if not cape_options.is_empty():
			_request_skill_choice(target_id, "burning_cape_discard", "burning_cape_new", cape_options, {"attacker_id": source_id})
	if final_amount > 0 and _equipped_logical_id(target_id, "weapon") == "a_plus_new":
		_discard_equipment_slot(target_id, "weapon", "a_plus_self_damage")
	if int(target.get("health", 0)) <= 0:
		_defeat_player(target_id, source_id)
	return final_amount


func _apply_on_damage_equipment(source_id: int, target_id: int, is_attack: bool) -> void:
	var source: Dictionary = players[source_id]
	var source_flags: Dictionary = source.get("flags", {}) as Dictionary
	if _equipped_logical_id(source_id, "weapon") == "gold_pick_new":
		_change_coins(source_id, 1)
	if _equipped_logical_id(source_id, "weapon") == "serpent_blade_new":
		_apply_status(target_id, "poison", 1, source_id)
	if _equipped_logical_id(source_id, "weapon") in ["shield_axe", "shield_axe_guardian_new"]:
		_gain_armor(source_id, 1)


func _trigger_ginger_waist(source_id: int, target_id: int) -> void:
	if source_id == target_id or not bool(players[source_id].get("alive", false)):
		return
	if String(players[source_id].get("character_id", "")) != "ginger" and _equipped_logical_id(source_id, "weapon") != "dragon_slayer_new":
		return
	if not bool(players[target_id].get("alive", false)) or int(players[target_id].get("health", 0)) <= 0:
		return
	if int(players[target_id].get("health", 0)) >= int(players[source_id].get("health", 0)):
		return
	_emit("passive_triggered", {"player_id": source_id, "skill_id": "ginger_waist", "message": "%s 触发【腰裂】，失去2点生命。" % String(players[source_id].get("name", ""))})
	_deal_damage(source_id, 2, "true", source_id, false)


func _defeat_player(target_id: int, source_id: int) -> void:
	var target: Dictionary = players[target_id]
	target["health"] = 0
	target["alive"] = false
	players[target_id] = target
	if source_id >= 0 and source_id < players.size() and source_id != target_id:
		_change_coins(source_id, 2)
		var source_stats: Dictionary = players[source_id].get("stats", {}) as Dictionary
		source_stats["eliminations"] = int(source_stats.get("eliminations", 0)) + 1
		players[source_id]["stats"] = source_stats
		if source_id == active_player_index:
			players[source_id]["turn_eliminations"] = int(players[source_id].get("turn_eliminations", 0)) + 1
		if _equipped_logical_id(source_id, "weapon") in ["ritual_dagger", "ritual_dagger_new"]:
			var owner: Dictionary = players[source_id]
			owner["max_health"] = int(owner.get("max_health", 0)) + 1
			owner["health"] = mini(int(owner.get("health", 0)), int(owner.get("max_health", 0)))
			var durability: Dictionary = owner.get("equipment_durability", {}) as Dictionary
			var weapon_durability: Dictionary = durability.get("weapon", {}) as Dictionary
			weapon_durability["current"] = int(weapon_durability.get("maximum", weapon_durability.get("current", 0)))
			durability["weapon"] = weapon_durability
			owner["equipment_durability"] = durability
			players[source_id] = owner
			_emit("maximum_health_changed", {"player_id": source_id, "delta": 1, "maximum": int(owner.get("max_health", 0)), "source_id": "ritual_dagger_new", "message": "%s 通过【仪式匕首】获得1点生命上限并重置耐久。" % String(owner.get("name", ""))})
	_emit("defeated", {"player_id": target_id, "source_id": source_id, "message": "%s 被击败。" % String(target.get("name", ""))})


func _heal(player_id: int, amount: int) -> void:
	var target: Dictionary = players[player_id]
	var before: int = int(target.get("health", 0))
	target["health"] = mini(int(target.get("max_health", 0)), before + maxi(0, amount))
	players[player_id] = target
	var restored: int = int(target.get("health", 0)) - before
	if restored > 0:
		if player_id == active_player_index:
			target = players[player_id]
			target["turn_healing"] = int(target.get("turn_healing", 0)) + restored
			players[player_id] = target
		_emit("healed", {"player_id": player_id, "amount": restored, "message": "%s 回复%d点生命。" % [String(target.get("name", "")), restored]})
		if pending_skill_choice.is_empty():
			for owner_id: int in players.size():
				if owner_id == player_id or _equipped_logical_id(owner_id, "weapon") != "sleeve_arrow_new":
					continue
				var attacks: Array[String] = _attack_hand_options(owner_id)
				attacks.erase("")
				if not attacks.is_empty():
					_request_skill_choice(owner_id, "sleeve_arrow_card", "sleeve_arrow_new", attacks, {"healed_id": player_id})
					break


func _check_ginger_breakthrough(player_id: int) -> void:
	if player_id != active_player_index or String(players[player_id].get("character_id", "")) != "ginger":
		return
	var active: Dictionary = players[player_id]
	var breakthroughs: Dictionary = active.get("active_breakthroughs", {}) as Dictionary
	if not bool(breakthroughs.get("ginger_power", false)):
		return
	if int(active.get("turn_healing", 0)) < 3 and int(active.get("turn_eliminations", 0)) < 2:
		return
	var losses: Dictionary = active.get("breakthrough_losses", {}) as Dictionary
	var loss: Dictionary = losses.get("ginger_power", {}) as Dictionary
	var restored := int(loss.get("health", 0))
	breakthroughs.erase("ginger_power")
	losses.erase("ginger_power")
	active["active_breakthroughs"] = breakthroughs
	active["breakthrough_losses"] = losses
	players[player_id] = active
	if restored > 0:
		_heal(player_id, restored)
	_emit("breakthrough_completed", {"player_id": player_id, "skill_id": "ginger_power", "health_restored": restored, "message": "Ginger 达成【强攻】破围，回复该技能代价失去的生命。"})


func _gain_armor(player_id: int, amount: int) -> void:
	var target: Dictionary = players[player_id]
	target["armor"] = clampi(int(target.get("armor", 0)) + amount, 0, armor_cap)
	players[player_id] = target


func _change_resource(player_id: int, resource: String, amount: int) -> void:
	var target: Dictionary = players[player_id]
	var maximum_key: String = "max_%s" % resource
	if player_id != active_player_index:
		target[resource] = 0
		players[player_id] = target
		return
	target[resource] = clampi(int(target.get(resource, 0)) + amount, 0, int(target.get(maximum_key, 0)))
	players[player_id] = target


func _change_max_health(player_id: int, amount: int, source_id: String = "effect") -> void:
	if amount < 0 and _equipped_logical_id(player_id, "accessory") == "rock_bottom_new":
		_emit("maximum_health_prevented", {"player_id": player_id, "amount": amount, "source_id": source_id, "message": "%s 的【谷底石】阻止了生命上限降低。" % String(players[player_id].get("name", ""))})
		return
	var target: Dictionary = players[player_id]
	target["max_health"] = maxi(1, int(target.get("max_health", 1)) + amount)
	target["health"] = mini(int(target.get("health", 0)), int(target.get("max_health", 1)))
	players[player_id] = target


func _change_coins(player_id: int, amount: int) -> void:
	var target: Dictionary = players[player_id]
	if amount > 0 and _equipped_logical_id(player_id, "accessory") == "gold_magnet_new":
		var flags: Dictionary = target.get("flags", {}) as Dictionary
		var bonus_count := int(flags.get("gold_magnet_bonus_count", 0))
		if bonus_count < 2:
			amount += 1
			flags["gold_magnet_bonus_count"] = bonus_count + 1
			target["flags"] = flags
	target["coins"] = maxi(0, int(target.get("coins", 0)) + amount)
	players[player_id] = target


func _apply_status(player_id: int, status_id: String, stacks: int, source_id: int = -1) -> void:
	if status_id.is_empty() or not bool(players[player_id].get("alive", false)):
		return
	var target: Dictionary = players[player_id]
	if status_id == "paralyze" and String(target.get("character_id", "")) == "q":
		return
	if status_id == "poison" and String(target.get("character_id", "")) == "zc":
		return
	if status_id == "confusion" and int(target.get("flash", 0)) > 0:
		_emit("status_prevented", {"player_id": player_id, "status": status_id, "reason_id": "flash", "message": "%s 因持有闪光而免疫混乱。" % String(target.get("name", ""))})
		return
	if (status_id == "poison" or status_id == "bleed") and _equipped_logical_id(player_id, "armor") in ["living_wood", "living_wood_new"]:
		_emit("status_prevented", {"player_id": player_id, "status": status_id, "reason_id": "living_wood", "message": "%s 的【活木甲】免疫%s。" % [String(target.get("name", "")), "中毒" if status_id == "poison" else "流血"]})
		return
	if status_id == "poison" and source_id >= 0 and source_id < players.size() and String(players[source_id].get("character_id", "")) == "zc":
		var source_flags: Dictionary = players[source_id].get("flags", {}) as Dictionary
		if not bool(source_flags.get("zc_insect_used", false)):
			source_flags["zc_insect_used"] = true
			players[source_id]["flags"] = source_flags
			stacks += 1
			var center: Vector2i = players[player_id].get("position", Vector2i.ZERO) as Vector2i
			poison_mists.append({"center": _position_payload(center), "source_id": source_id, "expires_after_round": completed_rounds + 1})
			_emit("poison_mist_created", {"player_id": source_id, "target_id": player_id, "center": _position_payload(center), "expires_after_round": completed_rounds + 1, "message": "Z&C 触发【虫刻】：本次中毒层数+1，并在目标周围生成持续两回合的毒雾。"})
	if source_id >= 0 and source_id < players.size() and _equipped_logical_id(source_id, "accessory") == "element_lens_new" and status_id in ["paralyze", "bleed", "poison", "confusion", "scorch"]:
		var lens_flags: Dictionary = players[source_id].get("flags", {}) as Dictionary
		if not bool(lens_flags.get("element_lens_used", false)):
			stacks += 1
			lens_flags["element_lens_used"] = true
			players[source_id]["flags"] = lens_flags
			_emit("equipment_triggered", {"player_id": source_id, "target_id": player_id, "card_id": "element_lens_new", "status": status_id, "message": "【元素透镜】使本次%s额外增加1层。" % status_id})
	var status_definition: Dictionary = catalog.call("status", status_id) as Dictionary
	var maximum: int = int(status_definition.get("max_stacks", 1))
	var statuses: Dictionary = target.get("statuses", {}) as Dictionary
	statuses[status_id] = mini(maximum, int(statuses.get(status_id, 0)) + stacks)
	var status_sources: Dictionary = target.get("status_sources", {}) as Dictionary
	if source_id >= 0:
		status_sources[status_id] = source_id
	if status_id == "hidden":
		var status_rounds: Dictionary = target.get("status_rounds", {}) as Dictionary
		status_rounds[status_id] = completed_rounds
		target["status_rounds"] = status_rounds
		if _equipped_logical_id(player_id, "armor") == "shadow_charm_new":
			var charm_flags: Dictionary = target.get("flags", {}) as Dictionary
			charm_flags["shadow_charm_ready"] = true
			target["flags"] = charm_flags
	target["statuses"] = statuses
	target["status_sources"] = status_sources
	players[player_id] = target
	_emit("status_applied", {"player_id": player_id, "status": status_id, "stacks": int(statuses.get(status_id, 0)), "message": "%s 获得%s。" % [String(target.get("name", "")), String(status_definition.get("name", status_id))]})
	if status_id == "poison" and int(statuses.get("poison", 0)) >= 4:
		statuses.erase("poison")
		var poison_source_id: int = int(status_sources.get("poison", -1))
		status_sources.erase("poison")
		target["statuses"] = statuses
		target["status_sources"] = status_sources
		players[player_id] = target
		_deal_damage(player_id, 3, "true", poison_source_id, false)


func _apply_modifier(player_id: int, modifier_id: String, stacks: int) -> void:
	if modifier_id.is_empty() or not bool(players[player_id].get("alive", false)):
		return
	var target: Dictionary = players[player_id]
	var modifiers: Dictionary = target.get("modifiers", {}) as Dictionary
	modifiers[modifier_id] = clampi(int(modifiers.get(modifier_id, 0)) + stacks, 0, 1)
	target["modifiers"] = modifiers
	players[player_id] = target


func _remove_status(player_id: int, status_id: String) -> void:
	var target: Dictionary = players[player_id]
	(target.get("statuses", {}) as Dictionary).erase(status_id)
	(target.get("status_sources", {}) as Dictionary).erase(status_id)
	(target.get("status_rounds", {}) as Dictionary).erase(status_id)
	players[player_id] = target


func _cleanse(player_id: int, amount: int) -> void:
	var target: Dictionary = players[player_id]
	var statuses: Dictionary = target.get("statuses", {}) as Dictionary
	var status_sources: Dictionary = target.get("status_sources", {}) as Dictionary
	var removed: int = 0
	for status_id: String in NEGATIVE_STATUSES:
		if statuses.has(status_id) and removed < amount:
			statuses.erase(status_id)
			status_sources.erase(status_id)
			removed += 1
	target["statuses"] = statuses
	target["status_sources"] = status_sources
	players[player_id] = target


func _decrement_status(statuses: Dictionary, status_id: String) -> void:
	var remaining: int = int(statuses.get(status_id, 0)) - 1
	if remaining > 0:
		statuses[status_id] = remaining
	else:
		statuses.erase(status_id)


func _push_target(source_id: int, target_id: int, amount: int) -> void:
	if amount <= 0:
		return
	if bool((players[target_id].get("flags", {}) as Dictionary).get("movement_immune", false)):
		_emit("movement_prevented", {"player_id": target_id, "source_id": source_id, "reason_id": "mountain_still", "message": "%s 以【不动如山】免疫了位移。" % String(players[target_id].get("name", ""))})
		return
	var source_position: Vector2i = players[source_id].get("position", Vector2i.ZERO) as Vector2i
	var target_position: Vector2i = players[target_id].get("position", Vector2i.ZERO) as Vector2i
	var delta: Vector2i = target_position - source_position
	var direction: Vector2i = Vector2i(signi(delta.x), 0) if absi(delta.x) >= absi(delta.y) else Vector2i(0, signi(delta.y))
	if direction == Vector2i.ZERO:
		return
	var destination: Vector2i = target_position
	for _step: int in amount:
		var candidate: Vector2i = destination + direction
		if not active_bounds().has_point(candidate) or _is_occupied(candidate, target_id):
			_deal_damage(target_id, 1, "true", source_id, false)
			break
		destination = candidate
	var target: Dictionary = players[target_id]
	target["position"] = destination
	players[target_id] = target


func _steal_card(source_id: int, target_id: int) -> void:
	var target_hand: Array = players[target_id].get("hand", []) as Array
	if target_hand.is_empty():
		return
	var index: int = rng.randi_range(0, target_hand.size() - 1)
	var card_value: Variant = target_hand.pop_at(index)
	(players[source_id].get("hand", []) as Array).append(card_value)


func _discard_cards(player_id: int, amount: int) -> int:
	var hand: Array = players[player_id].get("hand", []) as Array
	var discard: Array = players[player_id].get("discard", []) as Array
	var discarded: int = mini(amount, hand.size())
	for _index: int in discarded:
		var card_id: String = String(hand.pop_back())
		discard.append(card_id)
		_record_discard_origin(player_id, card_id)
	return discarded


func _draw_cards(player_id: int, amount: int) -> void:
	if amount <= 0:
		return
	if not planning_pending.is_empty():
		var planning_ids: Array = planning_pending.keys()
		planning_pending.clear()
		_emit("planning_triggered", {"player_id": player_id, "card_ids": planning_ids, "message": "%s 抽到【运筹】，摸2张牌并移除其他牌堆顶的【运筹】。" % String(players[player_id].get("name", ""))})
		_draw_cards(player_id, 2)
		return
	var target: Dictionary = players[player_id].duplicate(true)
	var hand: Array = (target.get("hand", []) as Array).duplicate()
	var hand_before_draw := hand.size()
	var common_deck: Array[String] = _string_array(target.get("common_deck", []))
	var profession_deck: Array[String] = _string_array(target.get("profession_deck", []))
	var common_discard: Array[String] = _string_array(target.get("common_discard", []))
	var profession_discard: Array[String] = _string_array(target.get("profession_discard", []))
	for _index: int in amount:
		if common_deck.is_empty() and not common_discard.is_empty():
			common_deck = common_discard.duplicate()
			common_discard.clear()
			_shuffle_strings(common_deck)
		if profession_deck.is_empty() and not profession_discard.is_empty():
			profession_deck = profession_discard.duplicate()
			profession_discard.clear()
			_shuffle_strings(profession_deck)
		var use_profession: bool = not profession_deck.is_empty() and (common_deck.is_empty() or rng.randi_range(0, 1) == 1)
		if use_profession:
			var drawn_profession: String = profession_deck.pop_back()
			hand.append(drawn_profession)
		elif not common_deck.is_empty():
			var drawn_common: String = common_deck.pop_back()
			hand.append(drawn_common)
		else:
			break
	target["hand"] = hand
	target["common_deck"] = common_deck
	target["profession_deck"] = profession_deck
	target["common_discard"] = common_discard
	target["profession_discard"] = profession_discard
	players[player_id] = target
	if hand.size() > hand_before_draw and _equipped_logical_id(player_id, "accessory") == "wax_seal_new":
		_draw_cards(player_id, 1)
	if hand.size() > hand_before_draw and pending_skill_choice.is_empty():
		for owner_id: int in players.size():
			if owner_id == player_id or not bool(players[owner_id].get("alive", false)):
				continue
			for card_value: Variant in players[owner_id].get("hand", []) as Array:
				var consume_card_id: String = String(card_value)
				if String(catalog.call("logical_card_id", consume_card_id)) == "consume_new":
					_request_skill_choice(owner_id, "consume_offer", "consume_new", ["use", "skip"], {"gainer_id": player_id, "consume_card_id": consume_card_id})
					return


func _build_common_deck() -> Array[String]:
	return catalog.call("staged_instance_ids_for_profession", "neutral") as Array[String]


func _build_profession_deck(profession: String) -> Array[String]:
	if profession.is_empty() or profession == "neutral":
		return []
	return catalog.call("staged_instance_ids_for_profession", profession) as Array[String]


func _record_discard_origin(player_id: int, card_id: String) -> void:
	var definition: Dictionary = catalog.call("resolve_card", card_id) as Dictionary
	var profession: String = String(definition.get("profession", "neutral"))
	var target: Dictionary = players[player_id]
	var discard_key: String = "profession_discard" if profession != "neutral" and String(definition.get("category", "")) != "equipment" else "common_discard"
	(target.get(discard_key, []) as Array).append(card_id)
	players[player_id] = target


func _is_elemental_card(definition: Dictionary) -> bool:
	if definition.is_empty() or String(definition.get("category", "")) == "equipment":
		return false
	for effect_value: Variant in definition.get("effects", []) as Array:
		if effect_value is Dictionary:
			var effect: Dictionary = effect_value as Dictionary
			if String(effect.get("op", "")) in ["status", "status_if_damage"] and String(effect.get("status", "")) in ["paralyze", "scorch", "confusion", "bleed", "poison"]:
				return true
	return false


func _elemental_hand_cards(player_id: int) -> Array[String]:
	var result: Array[String] = []
	for card_value: Variant in players[player_id].get("hand", []) as Array:
		var card_id := String(card_value)
		if _is_elemental_card(catalog.call("resolve_card", card_id) as Dictionary):
			result.append(card_id)
	return result


func _elemental_status_for_card(definition: Dictionary) -> String:
	for effect_value: Variant in definition.get("effects", []) as Array:
		if effect_value is Dictionary:
			var effect: Dictionary = effect_value as Dictionary
			var status_id := String(effect.get("status", ""))
			if String(effect.get("op", "")) in ["status", "status_if_damage"] and status_id in ["paralyze", "scorch", "confusion", "bleed", "poison"]:
				return status_id
	return ""


func _recover_last_card(player_id: int) -> void:
	var target: Dictionary = players[player_id]
	var card_id := String(target.get("last_card_id", ""))
	if card_id.is_empty():
		return
	var discard: Array = target.get("discard", []) as Array
	if not _remove_first(discard, card_id):
		return
	var definition: Dictionary = catalog.call("resolve_card", card_id) as Dictionary
	var origin_key := "profession_discard" if String(definition.get("profession", "neutral")) != "neutral" and String(definition.get("category", "")) != "equipment" else "common_discard"
	_remove_first(target.get(origin_key, []) as Array, card_id)
	(target.get("hand", []) as Array).append(card_id)
	target["last_card_id"] = ""
	players[player_id] = target
	_emit("card_recovered", {"player_id": player_id, "card_id": card_id, "message": "%s 取回上一张牌【%s】。" % [String(target.get("name", "")), String(definition.get("name", card_id))]})


func _recover_annihilate(player_id: int, card_id: String) -> void:
	var target: Dictionary = players[player_id]
	var discard: Array = target.get("discard", []) as Array
	if not _remove_first(discard, card_id):
		return
	var definition: Dictionary = catalog.call("resolve_card", card_id) as Dictionary
	var origin_key := "profession_discard" if String(definition.get("profession", "neutral")) != "neutral" else "common_discard"
	_remove_first(target.get(origin_key, []) as Array, card_id)
	(target.get("hand", []) as Array).append(card_id)
	var flags: Dictionary = target.get("flags", {}) as Dictionary
	var cost_increases: Dictionary = flags.get("annihilate_cost_increases", {}) as Dictionary
	cost_increases[card_id] = int(cost_increases.get(card_id, 0)) + 1
	flags["annihilate_cost_increases"] = cost_increases
	target["flags"] = flags
	players[player_id] = target
	_emit("card_recovered", {"player_id": player_id, "card_id": card_id, "stamina_increase": int(cost_increases.get(card_id, 0)), "message": "%s 取回【灭杀】；该实例本回合体力消耗增加至%d。" % [String(target.get("name", "")), int(cost_increases.get(card_id, 0))]})


func _recover_specific_card(player_id: int, card_id: String) -> bool:
	var target: Dictionary = players[player_id]
	var discard: Array = target.get("discard", []) as Array
	if not _remove_first(discard, card_id):
		return false
	var definition: Dictionary = catalog.call("resolve_card", card_id) as Dictionary
	var origin_key := "profession_discard" if String(definition.get("profession", "neutral")) != "neutral" and String(definition.get("category", "")) != "equipment" else "common_discard"
	_remove_first(target.get(origin_key, []) as Array, card_id)
	(target.get("hand", []) as Array).append(card_id)
	players[player_id] = target
	return true


func _equip(player_id: int, card_id: String, definition_override: Dictionary = {}) -> void:
	var definition: Dictionary = definition_override.duplicate(true) if not definition_override.is_empty() else catalog.call("resolve_card", card_id) as Dictionary
	var slot: String = String(definition.get("slot", ""))
	if slot.is_empty():
		return
	var target: Dictionary = players[player_id]
	var equipment: Dictionary = target.get("equipment", {}) as Dictionary
	var previous: String = String(equipment.get(slot, ""))
	if not previous.is_empty():
		_remove_equipment_modifiers(player_id, previous)
		(target.get("discard", []) as Array).append(previous)
		_record_discard_origin(player_id, previous)
		target = players[player_id]
		equipment = target.get("equipment", {}) as Dictionary
		(target.get("equipment_durability", {}) as Dictionary).erase(slot)
		(target.get("equipment_copies", {}) as Dictionary).erase(slot)
	equipment[slot] = card_id
	target["equipment"] = equipment
	var equipment_copies: Dictionary = target.get("equipment_copies", {}) as Dictionary
	if definition.has("copied_by_endgame"):
		equipment_copies[slot] = String(definition.get("copied_by_endgame", ""))
	else:
		equipment_copies.erase(slot)
	target["equipment_copies"] = equipment_copies
	var durability_value: Variant = definition.get("durability", null)
	var maximum_durability := -1 if durability_value == null else int(durability_value)
	var durability: Dictionary = target.get("equipment_durability", {}) as Dictionary
	durability[slot] = {"current": maximum_durability, "maximum": maximum_durability}
	target["equipment_durability"] = durability
	players[player_id] = target
	if String(definition.get("card_id", definition.get("id", ""))) == "zero_day_bomb_new":
		var bomb_flags: Dictionary = target.get("match_flags", {}) as Dictionary
		bomb_flags["zero_day_bomb_turns"] = 2
		target["match_flags"] = bomb_flags
		players[player_id] = target
	if String(definition.get("card_id", definition.get("id", ""))) == "fortress_ideals":
		target = players[player_id]
		target["max_stamina"] = int(target.get("max_stamina", 0)) + 1
		target["max_mana"] = int(target.get("max_mana", 0)) + 1
		target["stamina"] = int(target.get("stamina", 0)) + 1
		target["mana"] = int(target.get("mana", 0)) + 1
		players[player_id] = target


func _explode_zero_day_bomb(player_id: int) -> void:
	var center: Vector2i = players[player_id].get("position", Vector2i.ZERO) as Vector2i
	for target_id: int in players.size():
		if not bool(players[target_id].get("alive", false)):
			continue
		var position: Vector2i = players[target_id].get("position", Vector2i.ZERO) as Vector2i
		if target_id == player_id or maxi(absi(position.x - center.x), absi(position.y - center.y)) <= 1:
			var target: Dictionary = players[target_id]
			target["max_stamina"] = maxi(0, int(target.get("max_stamina", 0)) - 2)
			target["stamina"] = mini(int(target.get("stamina", 0)), int(target.get("max_stamina", 0)))
			players[target_id] = target
	_emit("zero_day_bomb_exploded", {"player_id": player_id, "position": _position_payload(center), "message": "【零日炸弹】爆炸，降低自身及周围角色2点体力上限。"})
	_discard_equipment_slot(player_id, "accessory", "zero_day_bomb_exploded")


func _discard_equipment_slot(player_id: int, slot: String, source_id: String) -> String:
	var equipment: Dictionary = players[player_id].get("equipment", {}) as Dictionary
	var card_id := String(equipment.get(slot, ""))
	if card_id.is_empty():
		return ""
	var was_secret_letter := String(catalog.call("logical_card_id", card_id)) == "secret_letter_new"
	_remove_equipment_modifiers(player_id, card_id)
	var target: Dictionary = players[player_id]
	equipment = target.get("equipment", {}) as Dictionary
	equipment[slot] = ""
	target["equipment"] = equipment
	(target.get("equipment_durability", {}) as Dictionary).erase(slot)
	(target.get("equipment_copies", {}) as Dictionary).erase(slot)
	(target.get("discard", []) as Array).append(card_id)
	players[player_id] = target
	_record_discard_origin(player_id, card_id)
	_emit("equipment_destroyed", {"player_id": player_id, "slot": slot, "card_id": card_id, "source_id": source_id, "message": "%s 的装备【%s】进入弃牌堆。" % [String(target.get("name", "")), String((catalog.call("resolve_card", card_id) as Dictionary).get("name", card_id))]})
	if was_secret_letter:
		_deal_damage(player_id, 2, "true", -1, false)
	return card_id


func _blocked_by_guard_unit(mover_id: int, destination: Vector2i) -> bool:
	for owner_id: int in players.size():
		if owner_id == mover_id or not bool(players[owner_id].get("alive", false)) or _equipped_logical_id(owner_id, "armor") != "guard_unit_new":
			continue
		var owner_position: Vector2i = players[owner_id].get("position", Vector2i.ZERO) as Vector2i
		if maxi(absi(destination.x - owner_position.x), absi(destination.y - owner_position.y)) <= 2:
			return true
	return false


func _remove_equipment_modifiers(player_id: int, card_id: String) -> void:
	if String(catalog.call("logical_card_id", card_id)) != "fortress_ideals":
		return
	var target: Dictionary = players[player_id]
	target["max_stamina"] = maxi(1, int(target.get("max_stamina", 1)) - 1)
	target["max_mana"] = maxi(0, int(target.get("max_mana", 0)) - 1)
	target["stamina"] = mini(int(target.get("stamina", 0)), int(target.get("max_stamina", 0)))
	target["mana"] = mini(int(target.get("mana", 0)), int(target.get("max_mana", 0)))
	players[player_id] = target


func _collapse_board() -> void:
	if collapse_count >= max_collapses:
		return
	collapse_in_progress = true
	var previous_size: int = active_bounds().size.x
	collapse_count += 1
	var occupied: Array[Vector2i] = []
	for player_id: int in players.size():
		if not bool(players[player_id].get("alive", false)):
			continue
		var position: Vector2i = players[player_id].get("position", Vector2i.ZERO) as Vector2i
		if active_bounds().has_point(position):
			occupied.append(position)
			continue
		if String(players[player_id].get("character_id", "")) == "signal":
			_emit("passive_triggered", {"player_id": player_id, "skill_id": "signal_mix", "message": "Signal 留在崩坠区域内行动。"})
			continue
		var safe_position: Vector2i = _nearest_open_position(position, occupied)
		var target: Dictionary = players[player_id]
		target["position"] = safe_position
		players[player_id] = target
		occupied.append(safe_position)
		_deal_damage(player_id, 1, "true", -1, false)
	_emit("board_collapsed", {
		"collapse": collapse_count,
		"from_size": previous_size,
		"size": active_bounds().size.x,
		"cause": "elimination",
		"message": "棋盘崩坠至 %dx%d。" % [active_bounds().size.x, active_bounds().size.y]
	})
	collapse_in_progress = false


func _settle_eliminations(initial_snapshot: Array[Dictionary]) -> void:
	if collapse_in_progress or finished:
		return
	if not pending_discard.is_empty():
		var pending_player_id: int = int(pending_discard.get("player_id", -1))
		if pending_player_id >= 0 and not bool(players[pending_player_id].get("alive", false)):
			pending_discard.clear()
			discard_continuation.clear()
	if not pending_skill_discard.is_empty():
		var pending_skill_player_id: int = int(pending_skill_discard.get("player_id", -1))
		if pending_skill_player_id >= 0 and not bool(players[pending_skill_player_id].get("alive", false)):
			pending_skill_discard.clear()
	if not pending_skill_choice.is_empty():
		var pending_choice_player_id: int = int(pending_skill_choice.get("player_id", -1))
		if pending_choice_player_id >= 0 and not bool(players[pending_choice_player_id].get("alive", false)):
			pending_skill_choice.clear()
	var initial_candidate_ids: Array[int] = []
	for candidate: Dictionary in initial_snapshot:
		initial_candidate_ids.append(int(candidate.get("id", -1)))
	var wipe_snapshot: Array[Dictionary] = _capture_tiebreak_snapshot(initial_candidate_ids)
	while not finished:
		var alive: Array[int] = _alive_player_ids()
		if alive.size() == 1:
			_finish_match(alive[0], "last_survivor", "最后存活")
			return
		if alive.is_empty():
			_finish_from_snapshot(wipe_snapshot, "simultaneous_wipe", "同时全灭决胜")
			return
		var target_collapse: int = clampi(4 - alive.size(), 0, max_collapses)
		if collapse_count >= target_collapse:
			return
		wipe_snapshot = _capture_tiebreak_snapshot(alive)
		_collapse_board()


func _nearest_open_position(origin: Vector2i, occupied: Array[Vector2i]) -> Vector2i:
	var bounds: Rect2i = active_bounds()
	var best: Vector2i = bounds.position
	var best_distance: int = 1000000
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var candidate: Vector2i = Vector2i(x, y)
			if occupied.has(candidate):
				continue
			var distance: int = absi(candidate.x - origin.x) + absi(candidate.y - origin.y)
			if distance < best_distance:
				best = candidate
				best_distance = distance
	return best


func _alive_player_ids() -> Array[int]:
	var alive: Array[int] = []
	for player_id: int in players.size():
		if bool(players[player_id].get("alive", false)):
			alive.append(player_id)
	return alive


func _duel_pressure_bonus() -> int:
	var round_number: int = completed_rounds + 1
	var result: int = 0
	for stage_value: Variant in rules.get("duel_pressure", []) as Array:
		var stage: Dictionary = stage_value as Dictionary
		if round_number >= int(stage.get("start_round", 999999)):
			result = int(stage.get("single_target_damage_bonus", 0))
	return result


func _capture_tiebreak_snapshot(candidate_ids: Array[int]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for candidate_id: int in candidate_ids:
		var candidate: Dictionary = players[candidate_id]
		var stats: Dictionary = candidate.get("stats", {}) as Dictionary
		result.append({
			"id": candidate_id,
			"eliminations": int(stats.get("eliminations", 0)),
			"health_ratio": float(candidate.get("health", 0)) / float(maxi(1, int(candidate.get("max_health", 1)))),
			"damage_dealt": int(stats.get("damage_dealt", 0)),
			"armor": int(candidate.get("armor", 0)),
			"hand_size": (candidate.get("hand", []) as Array).size()
		})
	return result


func _finish_from_snapshot(snapshot: Array[Dictionary], reason_id: String, reason: String) -> void:
	if snapshot.is_empty():
		return
	var best: Dictionary = snapshot[0]
	for candidate_index: int in range(1, snapshot.size()):
		var candidate: Dictionary = snapshot[candidate_index]
		if _snapshot_beats(candidate, best):
			best = candidate
	_finish_match(int(best.get("id", -1)), reason_id, reason)


func _snapshot_beats(candidate: Dictionary, incumbent: Dictionary) -> bool:
	for key: String in ["eliminations", "health_ratio", "damage_dealt", "armor", "hand_size"]:
		if candidate.get(key) != incumbent.get(key):
			return float(candidate.get(key, 0)) > float(incumbent.get(key, 0))
	return int(candidate.get("id", -1)) < int(incumbent.get("id", -1))


func _beats_tiebreak(candidate_id: int, incumbent_id: int) -> bool:
	var candidate: Dictionary = players[candidate_id]
	var incumbent: Dictionary = players[incumbent_id]
	var candidate_stats: Dictionary = candidate.get("stats", {}) as Dictionary
	var incumbent_stats: Dictionary = incumbent.get("stats", {}) as Dictionary
	if int(candidate_stats.get("eliminations", 0)) != int(incumbent_stats.get("eliminations", 0)):
		return int(candidate_stats.get("eliminations", 0)) > int(incumbent_stats.get("eliminations", 0))
	var candidate_health_ratio: float = float(candidate.get("health", 0)) / float(maxi(1, int(candidate.get("max_health", 1))))
	var incumbent_health_ratio: float = float(incumbent.get("health", 0)) / float(maxi(1, int(incumbent.get("max_health", 1))))
	if not is_equal_approx(candidate_health_ratio, incumbent_health_ratio):
		return candidate_health_ratio > incumbent_health_ratio
	if int(candidate_stats.get("damage_dealt", 0)) != int(incumbent_stats.get("damage_dealt", 0)):
		return int(candidate_stats.get("damage_dealt", 0)) > int(incumbent_stats.get("damage_dealt", 0))
	for key: String in ["armor"]:
		if int(candidate.get(key, 0)) != int(incumbent.get(key, 0)):
			return int(candidate.get(key, 0)) > int(incumbent.get(key, 0))
	var candidate_hand: int = (candidate.get("hand", []) as Array).size()
	var incumbent_hand: int = (incumbent.get("hand", []) as Array).size()
	if candidate_hand != incumbent_hand:
		return candidate_hand > incumbent_hand
	return candidate_id < incumbent_id


func _finish_match(match_winner_id: int, reason_identifier: String, reason: String) -> void:
	finished = true
	winner_id = match_winner_id
	win_reason_id = reason_identifier
	win_reason = reason
	var winner: Dictionary = player(winner_id)
	_emit("match_finished", {"winner_id": winner_id, "reason_id": reason_identifier, "reason": reason, "message": "%s 获胜：%s。" % [String(winner.get("name", "未知")), reason]})


func _advance_turn_index() -> void:
	if players.is_empty():
		return
	for offset: int in range(1, players.size() + 1):
		var candidate: int = (active_player_index + offset) % players.size()
		if bool(players[candidate].get("alive", false)):
			active_player_index = candidate
			return


func _skill_definition(player_id: int, skill_id: String) -> Dictionary:
	var character_id := String(players[player_id].get("character_id", ""))
	var revised_skill_id := String(REVISED_SKILL_ALIASES.get(skill_id, skill_id))
	var revised_skill: Dictionary = catalog.call("staged_skill", character_id, revised_skill_id) as Dictionary
	if revised_skill.is_empty() and revised_skill_id == "ginger_power" and _equipped_logical_id(player_id, "weapon") == "dragon_slayer_new":
		revised_skill = catalog.call("executable_staged_skill", "ginger", "ginger_power") as Dictionary
	if not revised_skill.is_empty():
		if revised_skill_id == "k_brain":
			var brain := revised_skill.duplicate(true)
			brain["id"] = skill_id
			brain["revised_skill_id"] = revised_skill_id
			brain["category"] = "skill"
			brain["cost"] = {"stamina": 0, "mana": 0}
			brain["target"] = "self"
			brain["range"] = 0
			brain["discard_requirement"] = {"mode": "count", "count": 1, "selection": "hand"}
			brain["effects"] = [
				{"op": "recover_last_card", "amount": 1},
				{"op": "modifier", "modifier": "repeat_next_card", "stacks": 1},
				{"op": "modifier", "modifier": "free_cast", "stacks": 1},
				{"op": "turn_flag", "flag": "cannot_deal_damage", "value": true}
			]
			return brain
		if revised_skill_id == "k_strategy":
			var strategy := revised_skill.duplicate(true)
			strategy["id"] = skill_id
			strategy["category"] = "skill"
			strategy["target"] = "self"
			strategy["range"] = 0
			strategy["effects"] = []
			return strategy
		if revised_skill_id == "ginger_power":
			var power := revised_skill.duplicate(true)
			power["id"] = skill_id
			power["category"] = "skill"
			power["target"] = "self"
			power["range"] = 0
			power["effects"] = []
			return power
		if revised_skill_id == "zc_frenzy":
			var frenzy := revised_skill.duplicate(true)
			frenzy["id"] = skill_id
			frenzy["revised_skill_id"] = revised_skill_id
			frenzy["category"] = "skill"
			frenzy["target"] = "self"
			frenzy["range"] = 0
			frenzy["cost"] = {"stamina": 0, "mana": 0}
			frenzy["effects"] = []
			return frenzy
		if revised_skill_id == "maddy_explore":
			var explore := revised_skill.duplicate(true)
			explore["id"] = skill_id
			explore["revised_skill_id"] = revised_skill_id
			explore["category"] = "skill"
			explore["target"] = "self"
			explore["range"] = 0
			explore["cost"] = {"stamina": 0, "mana": 0}
			explore["effects"] = []
			return explore
		if revised_skill_id == "maddy_reclaim":
			return {}
		if revised_skill_id == "na1_endless":
			# New-rule Endless is a passive trigger, not the retired Free Spirit active.
			return {}
		if revised_skill_id == "na1_foresight":
			# Foresight resolves during the draw phase, not as the retired free active.
			return {}
		if revised_skill_id == "shya_break_flash":
			return {}
		if revised_skill_id == "ginger_waist":
			return {}
	var character_definition: Dictionary = catalog.call("character", String(players[player_id].get("character_id", ""))) as Dictionary
	for skill_value: Variant in character_definition.get("skills", []) as Array:
		if skill_value is Dictionary and String((skill_value as Dictionary).get("id", "")) == skill_id:
			var skill: Dictionary = (skill_value as Dictionary).duplicate(true)
			skill["category"] = "skill"
			return skill
	if skill_id == "q_thunderstorm" and character_id == "q":
		return catalog.call("executable_staged_skill", "q", skill_id) as Dictionary
	if skill_id == "q_thunder_guard" and character_id == "q":
		var guard: Dictionary = catalog.call("staged_skill", "q", skill_id) as Dictionary
		guard["id"] = skill_id
		guard["category"] = "skill"
		guard["target"] = "self"
		guard["range"] = 0
		guard["cost"] = {"stamina": 0, "mana": 0}
		guard["effects"] = []
		return guard
	return {}


func _replenish_market() -> void:
	while market.size() < int(rules.get("market_size", 3)):
		if market_deck.is_empty():
			market_deck = catalog.call("market_card_ids") as Array[String]
			_shuffle_strings(market_deck)
		if market_deck.is_empty():
			return
		market.append(market_deck.pop_back())


func _is_occupied(position: Vector2i, ignored_id: int) -> bool:
	for player_state: Dictionary in players:
		var player_position: Vector2i = player_state.get("position", Vector2i.ZERO) as Vector2i
		if bool(player_state.get("alive", false)) and int(player_state.get("id", -1)) != ignored_id and player_position == position:
			return true
	return false


func _remove_first(values: Array, target: Variant) -> bool:
	var index: int = values.find(target)
	if index < 0:
		return false
	values.remove_at(index)
	return true


func _vector_array(value: Variant) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not value is Array:
		return result
	for item: Variant in value as Array:
		result.append(_payload_position(item))
	return result


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for item: Variant in value as Array:
		result.append(String(item))
	return result


func _payload_position(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Array and (value as Array).size() >= 2:
		return Vector2i(int((value as Array)[0]), int((value as Array)[1]))
	return Vector2i.ZERO


func _position_payload(position: Vector2i) -> Array[int]:
	return [position.x, position.y]


func _tile_key(position: Vector2i) -> String:
	return "%d:%d" % [position.x, position.y]


func _tile_key_to_position(key: String) -> Vector2i:
	var parts := key.split(":", false)
	if parts.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


func _shuffle_strings(values: Array[String]) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var swap_value: String = values[index]
		values[index] = values[swap_index]
		values[swap_index] = swap_value


func _damage_name(kind: String) -> String:
	return {"normal": "", "piercing": "穿透", "true": "真实", "fire": "火焰", "lightning": "雷电"}.get(kind, "") as String


func _emit(event_type: String, payload: Dictionary) -> void:
	var event: Dictionary = MatchEventScript.make(event_type, payload)
	event_history.append(event)
	recent_events.append(event)
