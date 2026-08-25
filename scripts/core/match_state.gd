class_name MatchState
extends RefCounted

const EventDeckScript = preload("res://scripts/core/event_deck.gd")
const MatchCommandScript = preload("res://scripts/core/match_command.gd")
const MatchEventScript = preload("res://scripts/core/match_event.gd")
const CARDINAL_DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const TARGET_EFFECTS: Array[String] = ["damage", "heal", "armor", "status", "remove_status", "break_armor", "push", "steal_card", "draw_target"]
const NEGATIVE_STATUSES: Array[String] = ["paralyze", "bleed", "poison", "confusion"]

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
var discard_continuation: Dictionary = {}
var last_event: Dictionary = {}
var market: Array[String] = []
var market_deck: Array[String] = []
var spent_tiles: Dictionary = {}
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
var collapse_in_progress: bool = false


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
		definition = catalog.call("card", definition_id) as Dictionary
	else:
		definition = _skill_definition(actor_id, definition_id)
	var source: Vector2i = players[actor_id].get("position", Vector2i.ZERO) as Vector2i
	var range_limit: int = _definition_range(actor_id, definition)
	var cells: Array[Vector2i] = []
	if String(definition.get("target", "self")) != "self":
		for y: int in range(active_bounds().position.y, active_bounds().end.y):
			for x: int in range(active_bounds().position.x, active_bounds().end.x):
				var cell := Vector2i(x, y)
				if absi(cell.x - source.x) + absi(cell.y - source.y) <= range_limit:
					cells.append(cell)
	return {"range": range_limit, "cells": cells}


func active_bounds() -> Rect2i:
	var side: int = collapse_sizes[mini(collapse_count, collapse_sizes.size() - 1)]
	var minimum: int = (board_size - side) / 2
	return Rect2i(minimum, minimum, side, side)


func tile_kind(position: Vector2i) -> String:
	if not active_bounds().has_point(position):
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
		MatchCommandScript.BUY:
			_handle_buy(payload)
		MatchCommandScript.EVENT_CHOICE:
			_handle_event_choice(payload)
		MatchCommandScript.END_TURN:
			_handle_end_turn()
		MatchCommandScript.DISCARD_CARDS:
			_handle_discard_cards(payload)
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
	if not pending_discard.is_empty():
		var discard_actor: int = int(pending_discard.get("player_id", -1))
		if actor_id < 0 or actor_id == discard_actor:
			result.append(MatchCommandScript.make(MatchCommandScript.DISCARD_CARDS, discard_actor, {
				"request_id": String(pending_discard.get("request_id", "")),
				"required_count": int(pending_discard.get("required_count", 0))
			}))
		return result
	if not pending_action.is_empty():
		var responder_id: int = int(pending_action.get("responder_id", -1))
		if actor_id >= 0 and actor_id != responder_id:
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
	if int(active.get("moves_remaining", 0)) > 0:
		result.append_array(_legal_move_commands(active_id))
	if int(active.get("actions", 0)) > 0:
		result.append_array(_legal_card_commands(active_id))
		result.append_array(_legal_skill_commands(active_id))
		result.append_array(_legal_buy_commands(active_id))
	result.append(MatchCommandScript.make(MatchCommandScript.END_TURN, active_id))
	return result


func drain_events() -> Array[Dictionary]:
	var drained: Array[Dictionary] = recent_events.duplicate(true)
	recent_events.clear()
	return drained


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
			"armor": int(player_state["armor"]),
			"coins": int(player_state["coins"]),
			"position": _position_payload(player_state["position"] as Vector2i),
			"hand": (player_state["hand"] as Array).duplicate(),
			"purchased_hand": (player_state.get("purchased_hand", []) as Array).duplicate(),
			"deck": (player_state["deck"] as Array).duplicate(),
			"discard": (player_state["discard"] as Array).duplicate(),
			"statuses": (player_state["statuses"] as Dictionary).duplicate(true),
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
		"played_history": _public_play_history_snapshot()
	}


func summary() -> String:
	if finished:
		var winner: Dictionary = player(winner_id)
		return "对局结束 · %s 获胜 · %s" % [String(winner.get("name", "未知")), win_reason]
	var pressure_bonus: int = _duel_pressure_bonus()
	var pressure_text: String = " · 决胜单体伤害 +%d" % pressure_bonus if pressure_bonus > 0 else ""
	return "第 %d 轮 · %s · 行动 %d · 移动 %d · 存活 %d/4 · 棋盘 %dx%d%s" % [
		completed_rounds + 1,
		String(current_player().get("name", "")),
		int(current_player().get("actions", 0)),
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
	if not pending_discard.is_empty():
		if String(command.get("type", "")) != MatchCommandScript.DISCARD_CARDS or actor_id != int(pending_discard.get("player_id", -1)):
			return "请先完成弃牌选择。"
		return _validate_discard_payload(command.get("payload", {}) as Dictionary)
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
		var position: Vector2i = start_positions[seat] if seat < start_positions.size() else Vector2i(1 + (seat % 2) * 6, 1 + (seat / 2) * 6)
		var deck: Array[String] = _string_array(definition.get("starter_cards", []))
		_shuffle_strings(deck)
		var max_stamina: int = int(definition.get("stamina", 2))
		var max_mana: int = int(definition.get("mana", 2))
		var player_state: Dictionary = {
			"id": seat,
			"character_id": String(definition.get("id", "q")),
			"name": String(definition.get("name", "Q")),
			"profession": String(definition.get("profession", "neutral")),
			"ai_persona": String(definition.get("ai_persona", "control")),
			"health": int(definition.get("health", 7)),
			"max_health": int(definition.get("health", 7)),
			"stamina": 0,
			"max_stamina": max_stamina,
			"mana": 0,
			"max_mana": max_mana,
			"armor": 0,
			"coins": 2 if character_id == "na1" else 0,
			"actions": 0,
			"moves_remaining": 0,
			"market_bought": false,
			"position": position,
			"hand": [],
			"purchased_hand": [],
			"deck": deck,
			"discard": [],
			"statuses": {},
			"status_sources": {},
			"modifiers": {},
			"status_rounds": {},
			"equipment": {"weapon": "", "armor": "", "accessory": ""},
			"stats": {"damage_dealt": 0, "eliminations": 0},
			"flags": {},
			"match_flags": {},
			"last_card_id": "",
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
	active["flags"] = {
		"spell_discount_used": false,
		"flash_guard_used": false,
		"bastion_used": false,
		"thorn_used": false,
		"shield_axe_used": false,
		"thunderbird_used": false,
		"extra_action_used": false
	}
	players[active_player_index] = active
	var status_snapshot: Array[Dictionary] = _capture_tiebreak_snapshot(_alive_player_ids())
	_tick_start_statuses(active_player_index)
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
	active["actions"] = int(rules.get("action_points", 2))
	active["moves_remaining"] = 1
	active["market_bought"] = false
	var statuses: Dictionary = active.get("statuses", {}) as Dictionary
	if int(statuses.get("paralyze", 0)) > 0:
		active["moves_remaining"] = 0
		statuses.erase("paralyze")
	if completed_rounds > 0:
		var draw_amount: int = draw_per_turn
		if int(statuses.get("confusion", 0)) > 0:
			draw_amount = maxi(0, draw_amount - 2)
			statuses.erase("confusion")
		_draw_cards(active_player_index, draw_amount)
	active["statuses"] = statuses
	players[active_player_index] = active
	_emit("turn_started", {"player_id": active_player_index, "message": "%s 开始回合。" % String(active.get("name", ""))})


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


func _legal_move_commands(actor_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var source: Vector2i = players[actor_id].get("position", Vector2i.ZERO) as Vector2i
	var max_range: int = _move_range(actor_id)
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
			if visited.has(key) or not active_bounds().has_point(next) or _is_occupied(next, actor_id):
				continue
			visited[key] = true
			var next_path: Array = path.duplicate()
			next_path.append(_position_payload(next))
			queue_positions.append(next)
			queue_paths.append(next_path)
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
		var definition: Dictionary = catalog.call("card", card_id) as Dictionary
		var category: String = String(definition.get("category", ""))
		if category == "response" or (_definition_has_extra_action(definition) and bool((active.get("flags", {}) as Dictionary).get("extra_action_used", false))) or not _can_pay(actor_id, definition):
			continue
		result.append_array(_target_commands(MatchCommandScript.PLAY_CARD, actor_id, card_id, definition))
	return result


func _legal_skill_commands(actor_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var character_definition: Dictionary = catalog.call("character", String(players[actor_id].get("character_id", ""))) as Dictionary
	for skill_value: Variant in character_definition.get("skills", []) as Array:
		if not skill_value is Dictionary:
			continue
		var skill: Dictionary = skill_value as Dictionary
		var skill_id: String = String(skill.get("id", ""))
		if _definition_has_extra_action(skill) and bool((players[actor_id].get("flags", {}) as Dictionary).get("extra_action_used", false)):
			continue
		result.append_array(_target_commands(MatchCommandScript.USE_SKILL, actor_id, skill_id, skill))
	return result


func _definition_has_extra_action(definition: Dictionary) -> bool:
	for effect_value: Variant in definition.get("effects", []) as Array:
		if effect_value is Dictionary and String((effect_value as Dictionary).get("op", "")) == "extra_action":
			return int((effect_value as Dictionary).get("amount", 0)) > 0
	return false


func _target_commands(command_type: String, actor_id: int, definition_id: String, definition: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var payload_key: String = "card_id" if command_type == MatchCommandScript.PLAY_CARD else "skill_id"
	var target_rule: String = String(definition.get("target", "self"))
	if target_rule == "self":
		result.append(MatchCommandScript.make(command_type, actor_id, {payload_key: definition_id, "target_id": actor_id}))
		return result
	var range_limit: int = _definition_range(actor_id, definition)
	if target_rule == "enemy":
		for target_id: int in players.size():
			if target_id != actor_id and bool(players[target_id].get("alive", false)) and _distance(actor_id, target_id) <= range_limit:
				result.append(MatchCommandScript.make(command_type, actor_id, {payload_key: definition_id, "target_id": target_id}))
	elif target_rule == "all_enemies_in_range" and not _enemies_in_range(actor_id, range_limit).is_empty():
		result.append(MatchCommandScript.make(command_type, actor_id, {payload_key: definition_id, "target_id": -1}))
	return result


func _legal_buy_commands(actor_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var active: Dictionary = players[actor_id]
	if bool(active.get("market_bought", false)):
		return result
	for market_index: int in market.size():
		var definition: Dictionary = catalog.call("card", market[market_index]) as Dictionary
		if int(active.get("coins", 0)) >= int(definition.get("price", 0)):
			result.append(MatchCommandScript.make(MatchCommandScript.BUY, actor_id, {"market_index": market_index}))
	return result


func _handle_move(payload: Dictionary) -> void:
	var path: Array = payload.get("path", []) as Array
	var actor_id: int = active_player_index
	var active: Dictionary = current_player()
	for step_value: Variant in path:
		var step: Vector2i = _payload_position(step_value)
		active["position"] = step
		players[actor_id] = active
		if tile_kind(step) == "trap":
			_deal_damage(actor_id, 1, "true", -1, false)
			_emit("trap_triggered", {"player_id": actor_id, "position": _position_payload(step), "message": "%s 穿过陷阱，受到1点伤害。" % String(active.get("name", ""))})
			if not bool(players[actor_id].get("alive", false)):
				break
	active = players[actor_id]
	active["moves_remaining"] = maxi(0, int(active.get("moves_remaining", 0)) - 1)
	players[actor_id] = active
	_emit("moved", {"player_id": actor_id, "position": _position_payload(active.get("position", Vector2i.ZERO) as Vector2i), "message": "%s 完成移动。" % String(active.get("name", ""))})
	if bool(active.get("alive", false)):
		_resolve_landing(actor_id)


func _handle_play_card(payload: Dictionary) -> void:
	var actor_id: int = active_player_index
	var card_id: String = String(payload.get("card_id", ""))
	var target_id: int = int(payload.get("target_id", actor_id))
	var definition: Dictionary = catalog.call("card", card_id) as Dictionary
	var active: Dictionary = players[actor_id]
	if not _remove_first(active.get("hand", []) as Array, card_id):
		_remove_first(active.get("purchased_hand", []) as Array, card_id)
	_pay_cost(actor_id, definition)
	active = players[actor_id]
	_change_actions(actor_id, -1, card_id)
	active = players[actor_id]
	players[actor_id] = active
	if String(definition.get("category", "")) == "equipment":
		_equip(actor_id, card_id)
		_emit("card_played", {"player_id": actor_id, "card_id": card_id, "message": "%s 装备了【%s】。" % [String(active.get("name", "")), String(definition.get("name", card_id))]})
		_record_public_card(actor_id, card_id, actor_id, "equipment")
		return
	(active.get("discard", []) as Array).append(card_id)
	var damage_bonus: int = 0
	var unanswerable: bool = false
	var statuses: Dictionary = active.get("statuses", {}) as Dictionary
	if String(definition.get("category", "")) == "attack" and int(statuses.get("hidden", 0)) > 0:
		damage_bonus += 1
		unanswerable = true
		statuses.erase("hidden")
		active["statuses"] = statuses
		players[actor_id] = active
	var action: Dictionary = {
		"source_id": actor_id,
		"target_id": target_id,
		"definition": definition.duplicate(true),
		"category": String(definition.get("category", "")),
		"card_id": card_id,
		"damage_bonus": damage_bonus,
		"unanswerable": unanswerable
	}
	_emit("card_played", {"player_id": actor_id, "target_id": target_id, "card_id": card_id, "message": "%s 使用【%s】。" % [String(active.get("name", "")), String(definition.get("name", card_id))]})
	_record_public_card(actor_id, card_id, target_id, "card")
	_open_response_or_resolve(action)


func _handle_use_skill(payload: Dictionary) -> void:
	var actor_id: int = active_player_index
	var skill_id: String = String(payload.get("skill_id", ""))
	var target_id: int = int(payload.get("target_id", actor_id))
	var skill: Dictionary = _skill_definition(actor_id, skill_id)
	var active: Dictionary = players[actor_id]
	_change_actions(actor_id, -1, skill_id)
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
	_emit("skill_used", {"player_id": actor_id, "target_id": target_id, "skill_id": skill_id, "message": "%s 发动【%s】。" % [String(active.get("name", "")), String(skill.get("name", skill_id))]})
	_open_response_or_resolve(action)


func _open_response_or_resolve(action: Dictionary) -> void:
	var target_id: int = int(action.get("target_id", -1))
	var category: String = String(action.get("category", ""))
	if target_id >= 0 and target_id != int(action.get("source_id", -1)) and not bool(action.get("unanswerable", false)):
		var responses: Array[String] = _valid_response_cards(target_id, category)
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
	if card_id.is_empty():
		_emit("response_passed", {"player_id": responder_id, "message": "%s 放弃响应。" % String(players[responder_id].get("name", ""))})
		_resolve_action(action)
		return
	var definition: Dictionary = catalog.call("card", card_id) as Dictionary
	var responder: Dictionary = players[responder_id]
	if not _remove_first(responder.get("hand", []) as Array, card_id):
		_remove_first(responder.get("purchased_hand", []) as Array, card_id)
	players[responder_id] = responder
	_pay_cost(responder_id, definition)
	responder = players[responder_id]
	(responder.get("discard", []) as Array).append(card_id)
	players[responder_id] = responder
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
	if canceled:
		_emit("action_canceled", {"source_id": int(action.get("source_id", -1)), "message": "原行动被抵消。"})
		return
	if reflected:
		var original_source: int = int(action.get("source_id", -1))
		action["source_id"] = responder_id
		action["target_id"] = original_source
		action["damage_bonus"] = 1 if card_id == "counter_charge" else 0
		action["unanswerable"] = true
	_resolve_action(action)


func _handle_buy(payload: Dictionary) -> void:
	var market_index: int = int(payload.get("market_index", -1))
	var actor_id: int = active_player_index
	var card_id: String = market[market_index]
	var definition: Dictionary = catalog.call("card", card_id) as Dictionary
	var active: Dictionary = players[actor_id]
	active["coins"] = int(active.get("coins", 0)) - int(definition.get("price", 0))
	active["actions"] = int(active.get("actions", 0)) - 1
	active["market_bought"] = true
	players[actor_id] = active
	market.remove_at(market_index)
	if String(definition.get("category", "")) == "equipment":
		_equip(actor_id, card_id)
	else:
		(active.get("purchased_hand", []) as Array).append(card_id)
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
	var hand_limit_for_turn: int = maxi(1, int(active.get("health", 0)) - 2)
	var excess: int = (active.get("hand", []) as Array).size() - hand_limit_for_turn
	if excess > 0:
		_request_discard(ending_id, excess, "end_turn")
		return
	_finish_end_turn(ending_id)


func _finish_end_turn(ending_id: int) -> void:
	var active: Dictionary = players[ending_id]
	var status_rounds: Dictionary = active.get("status_rounds", {}) as Dictionary
	var statuses: Dictionary = active.get("statuses", {}) as Dictionary
	if int(statuses.get("hidden", 0)) > 0 and int(status_rounds.get("hidden", completed_rounds)) < completed_rounds:
		statuses.erase("hidden")
		status_rounds.erase("hidden")
	active["statuses"] = statuses
	active["status_rounds"] = status_rounds
	active["stamina"] = 0
	active["mana"] = 0
	active["actions"] = 0
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
	_apply_effects(source_id, target_id, definition.get("effects", []) as Array, category, damage_bonus, range_limit, pressure_bonus, target_id < 0)
	var card_id: String = String(action.get("card_id", ""))
	if not card_id.is_empty() and source_id >= 0 and source_id < players.size():
		var source: Dictionary = players[source_id]
		source["last_card_id"] = card_id
		players[source_id] = source


func _apply_effects(source_id: int, target_id: int, effects: Array, category: String, damage_bonus: int, range_limit: int, pressure_bonus: int = 0, area_action: bool = false) -> void:
	_apply_effects_from(source_id, target_id, effects, category, damage_bonus, range_limit, pressure_bonus, area_action, 0)


func _apply_effects_from(source_id: int, target_id: int, effects: Array, category: String, damage_bonus: int, range_limit: int, pressure_bonus: int, area_action: bool, start_index: int) -> void:
	var target_ids: Array[int] = [target_id]
	if target_id < 0:
		target_ids = _enemies_in_range(source_id, range_limit)
	var bonus: int = damage_bonus + (_consume_damage_bonuses(source_id, effects, category) if start_index == 0 else 0)
	var direct_action: bool = category == "attack" or category == "skill"
	var damage_context: Dictionary = {"single_target": direct_action and not area_action, "area": direct_action and area_action, "pressure_bonus": pressure_bonus}
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
			_deal_damage(target_id, maxi(0, amount + damage_bonus), String(effect.get("kind", "normal")), source_id, category == "attack", damage_context)
		"self_damage":
			_deal_damage(source_id, amount, String(effect.get("kind", "true")), source_id, false)
		"heal":
			_heal(target_id, amount)
		"armor":
			_gain_armor(target_id, amount)
		"resource":
			_change_resource(source_id, String(effect.get("resource", "mana")), amount)
		"draw":
			_draw_cards(source_id, amount)
		"draw_target":
			_draw_cards(target_id, amount)
		"status":
			_apply_status(target_id, String(effect.get("status", "")), int(effect.get("stacks", 1)), source_id)
		"remove_status":
			_remove_status(target_id, String(effect.get("status", "")))
		"cleanse":
			_cleanse(source_id, amount)
		"coins":
			_change_coins(source_id, amount)
		"extra_action":
			_change_actions(source_id, amount, "extra_action")
			var source_flags: Dictionary = players[source_id].get("flags", {}) as Dictionary
			source_flags["extra_action_used"] = true
			players[source_id]["flags"] = source_flags
		"extra_move":
			var source: Dictionary = players[source_id]
			source["moves_remaining"] = int(source.get("moves_remaining", 0)) + amount
			players[source_id] = source
		"push":
			_push_target(source_id, target_id, amount)
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
			var source: Dictionary = players[source_id]
			var last_card_id: String = String(source.get("last_card_id", ""))
			if not last_card_id.is_empty():
				(source.get("hand", []) as Array).append(last_card_id)
			players[source_id] = source
		"reveal_hand":
			_emit("hand_revealed", {"player_id": source_id, "cards": (players[source_id].get("hand", []) as Array).duplicate(), "message": "%s 展示了手牌。" % String(players[source_id].get("name", ""))})
		"modifier":
			_apply_modifier(source_id, String(effect.get("modifier", "")), int(effect.get("stacks", 1)))


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
	source["statuses"] = statuses
	source["modifiers"] = modifiers
	players[source_id] = source
	return bonus


func _resolve_landing(player_id: int) -> void:
	var active: Dictionary = players[player_id]
	var position: Vector2i = active.get("position", Vector2i.ZERO) as Vector2i
	var kind: String = tile_kind(position)
	if kind == "wealth":
		var coin_amount: int = 2
		var match_flags: Dictionary = active.get("match_flags", {}) as Dictionary
		if String(active.get("character_id", "")) == "maddy" and not bool(match_flags.get("wealth_bonus_used", false)):
			coin_amount += 1
			match_flags["wealth_bonus_used"] = true
			active["match_flags"] = match_flags
		active["coins"] = int(active.get("coins", 0)) + coin_amount
		spent_tiles[_tile_key(position)] = true
		players[player_id] = active
		_emit("wealth_collected", {"player_id": player_id, "amount": coin_amount, "message": "%s 获得%d金币。" % [String(active.get("name", "")), coin_amount]})
	elif kind == "event":
		spent_tiles[_tile_key(position)] = true
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
		var definition: Dictionary = catalog.call("card", card_id) as Dictionary
		if String(definition.get("category", "")) != "response" or not ["heavenly_sense", "shrug_off"].has(card_id) or not _can_pay(player_id, definition):
			continue
		var tags: Array[String] = _string_array(definition.get("tags", []))
		if tags.has("response_any") or tags.has("response_%s" % action_category):
			result.append(card_id)
	return result


func _can_pay(player_id: int, definition: Dictionary) -> bool:
	var cost: Dictionary = _effective_cost(player_id, definition)
	return int(players[player_id].get("stamina", 0)) >= int(cost.get("stamina", 0)) and int(players[player_id].get("mana", 0)) >= int(cost.get("mana", 0))


func _change_actions(player_id: int, delta: int, source_id: String) -> void:
	var target: Dictionary = players[player_id]
	var before: int = int(target.get("actions", 0))
	target["actions"] = maxi(0, before + delta)
	players[player_id] = target
	_emit("action_points_changed", {
		"player_id": player_id,
		"before": before,
		"delta": delta,
		"after": int(target.get("actions", 0)),
		"source_id": source_id,
		"message": "%s %s%d个行动，剩余%d。" % [String(target.get("name", "")), "获得" if delta > 0 else "消耗", absi(delta), int(target.get("actions", 0))]
	})


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
	var modifiers: Dictionary = player_state.get("modifiers", {}) as Dictionary
	if int(modifiers.get("free_cast", 0)) > 0:
		return {"stamina": 0, "mana": 0}
	var flags: Dictionary = player_state.get("flags", {}) as Dictionary
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
	if String(player_state.get("character_id", "")) == "k" and String(definition.get("category", "skill")) == "skill" and not bool(flags.get("spell_discount_used", false)):
		flags["spell_discount_used"] = true
		player_state["flags"] = flags
	players[player_id] = player_state


func _definition_range(player_id: int, definition: Dictionary) -> int:
	var base_range: int = int(definition.get("range", 0))
	if String(definition.get("category", "")) != "attack":
		return base_range
	var weapon: String = String((players[player_id].get("equipment", {}) as Dictionary).get("weapon", ""))
	if weapon == "piercing_lance":
		base_range += 1
	elif weapon == "hunter_longbow":
		base_range += 2
	return base_range


func _move_range(player_id: int) -> int:
	var result: int = int(rules.get("move_range", 3))
	var player_state: Dictionary = players[player_id]
	if String(player_state.get("character_id", "")) == "zc":
		result += 1
	if String((player_state.get("equipment", {}) as Dictionary).get("accessory", "")) == "hermes_wings":
		result += 1
	return result


func _distance(source_id: int, target_id: int) -> int:
	var source: Vector2i = players[source_id].get("position", Vector2i.ZERO) as Vector2i
	var target: Vector2i = players[target_id].get("position", Vector2i.ZERO) as Vector2i
	return absi(source.x - target.x) + absi(source.y - target.y)


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
	var final_amount: int = amount
	if is_attack and not source.is_empty() and String(source.get("character_id", "")) == "ginger" and int(target.get("health", 0)) * 2 > int(target.get("max_health", 1)):
		final_amount += 1
	if kind == "lightning" and not source.is_empty() and String(source.get("character_id", "")) == "q":
		var source_flags: Dictionary = source.get("flags", {}) as Dictionary
		if not bool(source_flags.get("thunder_bonus_used", false)):
			final_amount += 1
			source_flags["thunder_bonus_used"] = true
			source["flags"] = source_flags
			players[source_id] = source
	if kind == "lightning" and not source.is_empty() and String((source.get("equipment", {}) as Dictionary).get("accessory", "")) == "thunderbird_feather":
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
		if String(target.get("character_id", "")) == "shya":
			var target_flags: Dictionary = target.get("flags", {}) as Dictionary
			if not bool(target_flags.get("flash_guard_used", false)):
				final_amount = maxi(0, final_amount - 1)
				target_flags["flash_guard_used"] = true
				target["flags"] = target_flags
		if String(target.get("character_id", "")) == "na1" and kind == "normal" and final_amount > 0:
			var coin_block: int = mini(final_amount, int(target.get("coins", 0)))
			target["coins"] = int(target.get("coins", 0)) - coin_block
			final_amount -= coin_block
		var equipment: Dictionary = target.get("equipment", {}) as Dictionary
		if (kind == "fire" or kind == "lightning") and String(equipment.get("accessory", "")) == "moonlight_protection":
			final_amount = maxi(0, final_amount - 1)
		if is_attack and String(equipment.get("armor", "")) == "bastion":
			var target_flags: Dictionary = target.get("flags", {}) as Dictionary
			if not bool(target_flags.get("bastion_used", false)):
				final_amount = maxi(0, final_amount - 1)
				target_flags["bastion_used"] = true
				target["flags"] = target_flags
	if kind != "true" and kind != "piercing" and final_amount > 0:
		var blocked: int = mini(int(target.get("armor", 0)), final_amount)
		target["armor"] = int(target.get("armor", 0)) - blocked
		final_amount -= blocked
	target["health"] = int(target.get("health", 0)) - final_amount
	players[target_id] = target
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
		var source_stats: Dictionary = players[source_id].get("stats", {}) as Dictionary
		source_stats["damage_dealt"] = int(source_stats.get("damage_dealt", 0)) + final_amount
		players[source_id]["stats"] = source_stats
		_apply_on_damage_equipment(source_id, target_id, is_attack)
	if int(target.get("health", 0)) <= 0:
		_defeat_player(target_id, source_id)
	return final_amount


func _apply_on_damage_equipment(source_id: int, target_id: int, is_attack: bool) -> void:
	var source: Dictionary = players[source_id]
	var source_equipment: Dictionary = source.get("equipment", {}) as Dictionary
	var source_flags: Dictionary = source.get("flags", {}) as Dictionary
	if String(source_equipment.get("weapon", "")) == "shield_axe" and not bool(source_flags.get("shield_axe_used", false)):
		_gain_armor(source_id, 1)
		source_flags["shield_axe_used"] = true
		source["flags"] = source_flags
		players[source_id] = source
	var target: Dictionary = players[target_id]
	var target_equipment: Dictionary = target.get("equipment", {}) as Dictionary
	var target_flags: Dictionary = target.get("flags", {}) as Dictionary
	if is_attack and String(target_equipment.get("armor", "")) == "thorn_armor" and _distance(source_id, target_id) == 1 and not bool(target_flags.get("thorn_used", false)):
		target_flags["thorn_used"] = true
		target["flags"] = target_flags
		players[target_id] = target
		_deal_damage(source_id, 1, "true", target_id, false)


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
		if String((players[source_id].get("equipment", {}) as Dictionary).get("weapon", "")) == "ritual_dagger":
			_heal(source_id, 2)
	_emit("defeated", {"player_id": target_id, "source_id": source_id, "message": "%s 被击败。" % String(target.get("name", ""))})


func _heal(player_id: int, amount: int) -> void:
	var target: Dictionary = players[player_id]
	var before: int = int(target.get("health", 0))
	target["health"] = mini(int(target.get("max_health", 0)), before + maxi(0, amount))
	players[player_id] = target
	var restored: int = int(target.get("health", 0)) - before
	if restored > 0:
		_emit("healed", {"player_id": player_id, "amount": restored, "message": "%s 回复%d点生命。" % [String(target.get("name", "")), restored]})


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


func _change_coins(player_id: int, amount: int) -> void:
	var target: Dictionary = players[player_id]
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
	if (status_id == "poison" or status_id == "bleed") and String((target.get("equipment", {}) as Dictionary).get("armor", "")) == "living_wood":
		return
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
		discard.append(hand.pop_back())
	return discarded


func _draw_cards(player_id: int, amount: int) -> void:
	if amount <= 0:
		return
	var target: Dictionary = players[player_id]
	var hand: Array = target.get("hand", []) as Array
	var deck: Array[String] = _string_array(target.get("deck", []))
	var discard: Array[String] = _string_array(target.get("discard", []))
	for _index: int in amount:
		if deck.is_empty() and not discard.is_empty():
			deck = discard.duplicate()
			discard.clear()
			_shuffle_strings(deck)
		if deck.is_empty():
			break
		hand.append(deck.pop_back())
	target["hand"] = hand
	target["deck"] = deck
	target["discard"] = discard
	players[player_id] = target


func _equip(player_id: int, card_id: String) -> void:
	var definition: Dictionary = catalog.call("card", card_id) as Dictionary
	var slot: String = String(definition.get("slot", ""))
	if slot.is_empty():
		return
	var target: Dictionary = players[player_id]
	var equipment: Dictionary = target.get("equipment", {}) as Dictionary
	var previous: String = String(equipment.get(slot, ""))
	if not previous.is_empty():
		_remove_equipment_modifiers(player_id, previous)
		(target.get("discard", []) as Array).append(previous)
		target = players[player_id]
		equipment = target.get("equipment", {}) as Dictionary
	equipment[slot] = card_id
	target["equipment"] = equipment
	players[player_id] = target
	if card_id == "fortress_ideals":
		target = players[player_id]
		target["max_stamina"] = int(target.get("max_stamina", 0)) + 1
		target["max_mana"] = int(target.get("max_mana", 0)) + 1
		target["stamina"] = int(target.get("stamina", 0)) + 1
		target["mana"] = int(target.get("mana", 0)) + 1
		players[player_id] = target


func _remove_equipment_modifiers(player_id: int, card_id: String) -> void:
	if card_id != "fortress_ideals":
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
		var safe_position: Vector2i = _nearest_open_position(position, occupied)
		var target: Dictionary = players[player_id]
		target["position"] = safe_position
		players[player_id] = target
		occupied.append(safe_position)
		var protected: bool = String(target.get("character_id", "")) == "signal" or String((target.get("equipment", {}) as Dictionary).get("accessory", "")) == "rock_bottom"
		if not protected:
			_deal_damage(player_id, 1, "true", -1, false)
		if String(target.get("character_id", "")) == "signal":
			_change_coins(player_id, 1)
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
	var character_definition: Dictionary = catalog.call("character", String(players[player_id].get("character_id", ""))) as Dictionary
	for skill_value: Variant in character_definition.get("skills", []) as Array:
		if skill_value is Dictionary and String((skill_value as Dictionary).get("id", "")) == skill_id:
			var skill: Dictionary = (skill_value as Dictionary).duplicate(true)
			skill["category"] = "skill"
			return skill
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
