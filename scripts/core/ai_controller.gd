class_name AIController
extends RefCounted

const MatchCommandScript = preload("res://scripts/core/match_command.gd")


func choose_command(state: RefCounted, actor_id: int) -> Dictionary:
	var commands: Array[Dictionary] = state.call("legal_commands", actor_id) as Array[Dictionary]
	if commands.is_empty():
		return {}
	if String(commands[0].get("type", "")) == MatchCommandScript.SWITCH_PROFESSION:
		return commands[0]
	if String(commands[0].get("type", "")) == MatchCommandScript.DISCARD_CARDS:
		return _choose_discard_command(state, actor_id, commands[0].get("payload", {}) as Dictionary)
	var persona: String = String((state.call("player", actor_id) as Dictionary).get("ai_persona", "control"))
	var best_command: Dictionary = commands[0]
	var best_score: float = -1000000.0
	for command: Dictionary in commands:
		var score: float = _score_command(state, actor_id, command, persona)
		if score > best_score:
			best_score = score
			best_command = command
	return best_command.duplicate(true)


func _score_command(state: RefCounted, actor_id: int, command: Dictionary, persona: String) -> float:
	var command_type: String = String(command.get("type", ""))
	var payload: Dictionary = command.get("payload", {}) as Dictionary
	match command_type:
		MatchCommandScript.RESPOND:
			return 100.0 if not String(payload.get("card_id", "")).is_empty() else 10.0
		MatchCommandScript.EVENT_CHOICE:
			return _score_event_choice(state, payload)
		MatchCommandScript.MOVE:
			return _score_move(state, actor_id, payload, persona)
		MatchCommandScript.PLAY_CARD:
			return _score_definition(state, actor_id, payload, true, persona)
		MatchCommandScript.USE_SKILL:
			return _score_definition(state, actor_id, payload, false, persona)
		MatchCommandScript.BUY:
			return 24.0 if persona == "resource" else 14.0
		MatchCommandScript.END_TURN:
			return -100.0
	return -1000.0


func _choose_discard_command(state: RefCounted, actor_id: int, payload: Dictionary) -> Dictionary:
	var required_count: int = int(payload.get("required_count", 0))
	var hand: Array = (state.call("player", actor_id) as Dictionary).get("hand", []) as Array
	var scored: Array[Dictionary] = []
	var catalog: RefCounted = state.get("catalog") as RefCounted
	for index: int in hand.size():
		var card_id: String = String(hand[index])
		var definition: Dictionary = catalog.call("card", card_id) as Dictionary
		var score: float = float(definition.get("price", 0))
		if String(definition.get("category", "")) == "equipment":
			score += 4.0
		elif String(definition.get("category", "")) == "attack":
			score += 2.0
		scored.append({"id": card_id, "score": score, "index": index})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a.get("score", 0.0)) == float(b.get("score", 0.0)):
			return int(a.get("index", 0)) < int(b.get("index", 0))
		return float(a.get("score", 0.0)) < float(b.get("score", 0.0))
	)
	var selected: Array[String] = []
	for entry: Dictionary in scored.slice(0, mini(required_count, scored.size())):
		selected.append(String(entry.get("id", "")))
	return MatchCommandScript.make(MatchCommandScript.DISCARD_CARDS, actor_id, {
		"request_id": String(payload.get("request_id", "")),
		"card_ids": selected
	})


func _score_event_choice(state: RefCounted, payload: Dictionary) -> float:
	var pending_event: Dictionary = state.get("pending_event") as Dictionary
	var choices: Array = pending_event.get("choices", []) as Array
	var choice_index: int = int(payload.get("choice_index", -1))
	if choice_index < 0 or choice_index >= choices.size():
		return -1000.0
	var choice: Dictionary = choices[choice_index] as Dictionary
	var score: float = 20.0
	for effect_value: Variant in choice.get("effects", []) as Array:
		if not effect_value is Dictionary:
			continue
		var effect: Dictionary = effect_value as Dictionary
		var operation: String = String(effect.get("op", ""))
		var amount: float = float(effect.get("amount", 0))
		if operation == "heal" or operation == "draw" or operation == "armor":
			score += amount * 3.0
		elif operation == "coins" or operation == "resource":
			score += amount * 2.0
		elif operation == "damage" or operation == "self_damage":
			score -= amount * 4.0
	return score


func _score_move(state: RefCounted, actor_id: int, payload: Dictionary, persona: String) -> float:
	var path: Array = payload.get("path", []) as Array
	if path.is_empty():
		return -1000.0
	var destination_value: Array = path.back() as Array
	var destination: Vector2i = Vector2i(int(destination_value[0]), int(destination_value[1]))
	var board_size: int = int(state.get("board_size"))
	var center: Vector2i = Vector2i(board_size / 2, board_size / 2)
	var center_distance: int = absi(destination.x - center.x) + absi(destination.y - center.y)
	var score: float = 16.0 - float(center_distance) * 0.5
	var tile_kind: String = String(state.call("tile_kind", destination))
	if tile_kind == "event":
		score += 16.0 if persona != "offense" else 9.0
	elif tile_kind == "wealth":
		score += 18.0 if persona == "resource" else 10.0
	elif tile_kind == "trap":
		score -= 10.0
	var current_position: Vector2i = (state.call("player", actor_id) as Dictionary).get("position", Vector2i.ZERO) as Vector2i
	var current_nearest: int = 99
	var destination_nearest: int = 99
	for target_id: int in (state.get("players") as Array).size():
		if target_id == actor_id:
			continue
		var target: Dictionary = state.call("player", target_id) as Dictionary
		if not bool(target.get("alive", false)):
			continue
		var target_position: Vector2i = target.get("position", Vector2i.ZERO) as Vector2i
		current_nearest = mini(current_nearest, absi(current_position.x - target_position.x) + absi(current_position.y - target_position.y))
		destination_nearest = mini(destination_nearest, absi(destination.x - target_position.x) + absi(destination.y - target_position.y))
	var pursuit_weight: float = 8.0 if persona == "offense" else 5.0
	score += float(current_nearest - destination_nearest) * pursuit_weight
	return score - float(path.size()) * 0.05


func _score_definition(state: RefCounted, actor_id: int, payload: Dictionary, is_card: bool, persona: String) -> float:
	var definition: Dictionary
	if is_card:
		var catalog: RefCounted = state.get("catalog") as RefCounted
		definition = catalog.call("card", String(payload.get("card_id", ""))) as Dictionary
	else:
		definition = state.call("_skill_definition", actor_id, String(payload.get("skill_id", ""))) as Dictionary
	var actor: Dictionary = state.call("player", actor_id) as Dictionary
	var score: float = 15.0
	var target_id: int = int(payload.get("target_id", actor_id))
	for effect_value: Variant in definition.get("effects", []) as Array:
		if not effect_value is Dictionary:
			continue
		var effect: Dictionary = effect_value as Dictionary
		var operation: String = String(effect.get("op", ""))
		var amount: float = float(effect.get("amount", effect.get("stacks", 0)))
		if operation == "damage":
			score += 22.0 + amount * (9.0 if persona == "offense" else 7.0)
			if target_id >= 0:
				var target: Dictionary = state.call("player", target_id) as Dictionary
				if int(target.get("health", 99)) <= int(amount):
					score += 50.0
		elif operation == "status" or operation == "break_armor":
			score += amount * (7.0 if persona == "control" else 4.0)
		elif operation == "heal":
			var missing_health: int = maxi(0, int(actor.get("max_health", 0)) - int(actor.get("health", 0)))
			score += mini(float(missing_health), amount) * 6.0 if missing_health > 0 else -24.0
		elif operation == "armor":
			var missing_armor: int = maxi(0, 3 - int(actor.get("armor", 0)))
			score += mini(float(missing_armor), amount) * 5.0 if missing_armor > 0 else -20.0
		elif operation == "resource":
			var resource: String = String(effect.get("resource", "mana"))
			var missing_resource: int = maxi(0, int(actor.get("max_%s" % resource, 0)) - int(actor.get(resource, 0)))
			score += mini(float(missing_resource), amount) * (6.0 if persona == "resource" else 3.0) if missing_resource > 0 else -18.0
		elif operation == "draw" or operation == "coins":
			score += amount * (6.0 if persona == "resource" else 3.0)
		elif operation == "extra_action" or operation == "extra_move":
			score += amount * 8.0
		elif operation == "self_damage":
			score -= amount * 5.0
	if String(definition.get("category", "")) == "equipment":
		score += 10.0
	# Keep the deterministic showcase AI from over-selecting the strongest
	# burst kits while still making the economy/support characters act on
	# their distinctive opportunities. This is AI policy, not rule logic.
	var character_id: String = String(actor.get("character_id", ""))
	match character_id:
		"q": score -= 8.0
		"k": score -= 10.0
		"na1": score += 7.0
		"signal": score += 7.0
	return score
