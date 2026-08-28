class_name ContentCatalog
extends RefCounted

const CARD_PATH := "res://rules/cards.json"
const CHARACTER_PATH := "res://rules/characters.json"
const EVENT_PATH := "res://rules/events.json"
const NEW_EVENT_PATH := "res://rules/events_new.json"
const NEW_CARD_PATH := "res://rules/cards_new.json"
const STATUS_PATH := "res://rules/statuses.json"
const EFFECT_ALIASES_PATH := "res://rules/effect_aliases.json"
const SUPPORTED_EFFECTS: Array[String] = [
	"damage", "self_damage", "heal", "armor", "resource", "draw", "draw_target",
	"status", "remove_status", "cleanse", "coins", "extra_action", "extra_move",
	"push", "break_armor", "steal_card", "self_discard", "discard_or_damage",
	"recover_last_card", "reveal_hand", "equip", "negate", "reflect", "modifier", "provisional"
]
const LAUNCH_STATUS_IDS: Array[String] = ["paralyze", "bleed", "poison", "confusion", "hidden", "scorch"]
const MODIFIER_IDS: Array[String] = ["free_cast", "echo"]
const SUIT_IDS: Array[String] = ["none", "hearts", "diamonds", "clubs", "spades"]
const COLOR_IDS: Array[String] = ["none", "red", "black"]
const RANK_MIN := 0
const RANK_MAX := 13

var version: int = 1
var cards: Array[Dictionary] = []
var card_instances: Array[Dictionary] = []
var characters: Array[Dictionary] = []
var events: Array[Dictionary] = []
var staged_events: Array[Dictionary] = []
var staged_cards: Array[Dictionary] = []
var statuses: Array[Dictionary] = []
var effect_aliases: Dictionary = {}
var cards_by_id: Dictionary = {}
var cards_by_instance_id: Dictionary = {}
var characters_by_id: Dictionary = {}
var statuses_by_id: Dictionary = {}
var validation_errors: Array[String] = []


func _init() -> void:
	_load_all()


func is_valid() -> bool:
	return validation_errors.is_empty()


func card(card_id: String) -> Dictionary:
	if cards_by_id.has(card_id):
		return cards_by_id.get(card_id, {}) as Dictionary
	if cards_by_instance_id.has(card_id):
		return cards_by_instance_id.get(card_id, {}) as Dictionary
	return {}


func card_instance(instance_id: String) -> Dictionary:
	return cards_by_instance_id.get(instance_id, {}) as Dictionary


func logical_card_id(value: String) -> String:
	if cards_by_id.has(value):
		return value
	var instance: Dictionary = card_instance(value)
	return String(instance.get("card_id", ""))


func character(character_id: String) -> Dictionary:
	return characters_by_id.get(character_id, {}) as Dictionary


func status(status_id: String) -> Dictionary:
	return statuses_by_id.get(status_id, {}) as Dictionary


func provisional_report() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition: Dictionary in cards:
		if bool(definition.get("provisional", false)):
			result.append({"kind": "card", "id": definition.get("id", ""), "description": definition.get("description", "")})
	for character_definition: Dictionary in characters:
		for skill_value: Variant in character_definition.get("skills", []) as Array:
			if skill_value is Dictionary and bool((skill_value as Dictionary).get("provisional", false)):
				result.append({"kind": "skill", "id": (skill_value as Dictionary).get("id", ""), "description": (skill_value as Dictionary).get("description", "")})
	for event_definition: Dictionary in events:
		if bool(event_definition.get("provisional", false)):
			result.append({"kind": "event", "id": event_definition.get("id", ""), "description": event_definition.get("description", "")})
	for card_definition: Dictionary in staged_cards:
		result.append({"kind": "staged_card", "id": card_definition.get("id", ""), "description": card_definition.get("source_text", "")})
	for event_definition: Dictionary in staged_events:
		result.append({"kind": "staged_event", "id": event_definition.get("id", ""), "description": event_definition.get("source_text", "")})
	return result


func staged_card_instance(card_id: String, copy_index: int) -> Dictionary:
	for definition: Dictionary in staged_cards:
		if String(definition.get("id", "")) != card_id:
			continue
		var instances: Array = definition.get("instances", []) as Array
		if copy_index < 0 or copy_index >= instances.size():
			return {}
		var instance: Dictionary = instances[copy_index] as Dictionary
		var result := definition.duplicate(true)
		result["card_id"] = card_id
		result["instance_id"] = "%s#%03d" % [card_id, copy_index + 1]
		result["suit"] = instance.get("suit", "none")
		result["rank"] = int(instance.get("rank", 0))
		result["color"] = _color_for_suit(String(result.get("suit", "none")))
		return result
	return {}


func staged_card_ids_for_profession(profession: String) -> Array[String]:
	var result: Array[String] = []
	for definition: Dictionary in staged_cards:
		if String(definition.get("profession", "")) == profession:
			result.append(String(definition.get("id", "")))
	return result


func staged_instance_ids_for_profession(profession: String) -> Array[String]:
	var result: Array[String] = []
	for definition: Dictionary in staged_cards:
		if String(definition.get("profession", "")) != profession:
			continue
		var card_id := String(definition.get("id", ""))
		var instances: Array = definition.get("instances", []) as Array
		for index: int in instances.size():
			result.append("%s#%03d" % [card_id, index + 1])
	return result


func market_card_ids() -> Array[String]:
	var result: Array[String] = []
	for card_definition: Dictionary in cards:
		var card_id: String = String(card_definition.get("id", ""))
		if not card_id.is_empty():
			result.append(card_id)
	return result


func market_card_instance_ids() -> Array[String]:
	var result: Array[String] = []
	for instance: Dictionary in card_instances:
		var instance_id := String(instance.get("instance_id", ""))
		if not instance_id.is_empty():
			result.append(instance_id)
	return result


func _load_all() -> void:
	var card_document: Dictionary = _load_document(CARD_PATH)
	var character_document: Dictionary = _load_document(CHARACTER_PATH)
	var event_document: Dictionary = _load_document(EVENT_PATH)
	var status_document: Dictionary = _load_document(STATUS_PATH)
	var aliases_document: Dictionary = _load_document(EFFECT_ALIASES_PATH)
	cards = _dictionary_array(card_document.get("cards", []))
	_normalize_cards()
	characters = _dictionary_array(character_document.get("characters", []))
	events = _dictionary_array(event_document.get("events", []))
	var new_event_document: Dictionary = _load_document(NEW_EVENT_PATH)
	staged_events = _dictionary_array(new_event_document.get("events", []))
	var new_card_document: Dictionary = _load_document(NEW_CARD_PATH)
	staged_cards = _dictionary_array(new_card_document.get("cards", []))
	for staged_card: Dictionary in staged_cards:
		if not staged_card.has("cost"):
			staged_card["cost"] = {"stamina": 0, "mana": 0}
	statuses = _dictionary_array(status_document.get("statuses", []))
	effect_aliases = aliases_document.get("aliases", {}) as Dictionary
	version = maxi(
		int(card_document.get("version", 1)),
		maxi(
			int(character_document.get("version", 1)),
			maxi(int(event_document.get("version", 1)), int(status_document.get("version", 1)))
		)
	)
	_index_definitions(cards, cards_by_id, "card")
	_build_card_instances()
	_index_definitions(characters, characters_by_id, "character")
	_index_definitions(statuses, statuses_by_id, "status")
	_validate()


func _load_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		validation_errors.append("Missing content file: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		validation_errors.append("Invalid JSON document: %s" % path)
		return {}
	return parsed as Dictionary


func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		return result
	for item: Variant in value as Array:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result


func _index_definitions(definitions: Array[Dictionary], target: Dictionary, kind: String) -> void:
	for definition: Dictionary in definitions:
		var definition_id: String = String(definition.get("id", ""))
		if definition_id.is_empty():
			validation_errors.append("A %s is missing its id." % kind)
		elif target.has(definition_id):
			validation_errors.append("Duplicate %s id: %s" % [kind, definition_id])
		else:
			target[definition_id] = definition


func _normalize_cards() -> void:
	# Older content stores one logical definition per card. Normalize metadata here
	# so new content can opt into copies without changing the runtime contract.
	for definition: Dictionary in cards:
		if not definition.has("suit"):
			definition["suit"] = "none"
		if not definition.has("rank"):
			definition["rank"] = 0
		if not definition.has("color"):
			definition["color"] = _color_for_suit(String(definition.get("suit", "none")))
		if not definition.has("durability"):
			definition["durability"] = 0
		if not definition.has("copies"):
			definition["copies"] = 1
		if not definition.has("provisional"):
			definition["provisional"] = false


func _build_card_instances() -> void:
	card_instances.clear()
	cards_by_instance_id.clear()
	for definition: Dictionary in cards:
		var card_id := String(definition.get("id", ""))
		var copies := maxi(1, int(definition.get("copies", 1)))
		for copy_index in range(copies):
			var instance := definition.duplicate(true)
			var instance_id := "%s#%03d" % [card_id, copy_index + 1]
			instance["instance_id"] = instance_id
			instance["card_id"] = card_id
			card_instances.append(instance)
			cards_by_instance_id[instance_id] = instance


func _color_for_suit(suit: String) -> String:
	if suit == "hearts" or suit == "diamonds":
		return "red"
	if suit == "clubs" or suit == "spades":
		return "black"
	return "none"


func _validate() -> void:
	if cards.size() != 80:
		validation_errors.append("Expected 80 cards, found %d." % cards.size())
	if characters.size() != 8:
		validation_errors.append("Expected 8 characters, found %d." % characters.size())
	if events.size() != 16:
		validation_errors.append("Expected 16 events, found %d." % events.size())
	if statuses.size() != 6:
		validation_errors.append("Expected six public statuses, found %d." % statuses.size())
	_validate_cards()
	_validate_characters()
	_validate_events()
	_validate_staged_events()
	_validate_staged_cards()
	_validate_statuses()


func _validate_cards() -> void:
	for card_definition: Dictionary in cards:
		var card_id: String = String(card_definition.get("id", "unknown"))
		for key: String in ["name_key", "name", "category", "profession", "cost", "price", "target", "range", "effects", "tags", "description", "suit", "rank", "color", "durability", "copies", "provisional"]:
			if not card_definition.has(key):
				validation_errors.append("Card %s is missing %s." % [card_id, key])
		_validate_card_metadata(card_definition)
		_validate_effects(card_definition.get("effects", []), "card %s" % card_id)
		if String(card_definition.get("category", "")) == "response" and not ["heavenly_sense", "shrug_off"].has(card_id):
			validation_errors.append("Response card %s is not allowed in v4." % card_id)
	if cards_by_instance_id.size() != card_instances.size():
		validation_errors.append("Card instance IDs must be globally unique.")


func _validate_card_metadata(card_definition: Dictionary) -> void:
	var card_id := String(card_definition.get("id", "unknown"))
	var suit := String(card_definition.get("suit", ""))
	var color := String(card_definition.get("color", ""))
	var rank := int(card_definition.get("rank", -1))
	var copies := int(card_definition.get("copies", 0))
	if not SUIT_IDS.has(suit):
		validation_errors.append("Card %s has invalid suit %s." % [card_id, suit])
	if not COLOR_IDS.has(color) or color != _color_for_suit(suit):
		validation_errors.append("Card %s has invalid color %s for suit %s." % [card_id, color, suit])
	if rank < RANK_MIN or rank > RANK_MAX:
		validation_errors.append("Card %s has invalid rank %d." % [card_id, rank])
	if copies < 1:
		validation_errors.append("Card %s must have at least one copy." % card_id)
	if int(card_definition.get("durability", 0)) < 0:
		validation_errors.append("Card %s cannot have negative durability." % card_id)
	if not card_definition.get("provisional", false) is bool:
		validation_errors.append("Card %s provisional must be boolean." % card_id)


func _validate_characters() -> void:
	for character_definition: Dictionary in characters:
		var character_id: String = String(character_definition.get("id", "unknown"))
		for key: String in ["name_key", "name", "profession", "health", "stamina", "mana", "passive", "skills", "starter_cards"]:
			if not character_definition.has(key):
				validation_errors.append("Character %s is missing %s." % [character_id, key])
		var starter_cards: Array = character_definition.get("starter_cards", []) as Array
		if starter_cards.size() != 20:
			validation_errors.append("Character %s must have 20 starter cards." % character_id)
		for card_value: Variant in starter_cards:
			var card_id: String = String(card_value)
			if not cards_by_id.has(card_id):
				validation_errors.append("Character %s references missing card %s." % [character_id, card_id])
		var skills: Array = character_definition.get("skills", []) as Array
		if skills.size() != 2:
			validation_errors.append("Character %s must have two active skills." % character_id)
		for skill_value: Variant in skills:
			if skill_value is Dictionary:
				var skill_definition: Dictionary = skill_value as Dictionary
				var skill_id: String = String(skill_definition.get("id", "unknown"))
				for key: String in ["id", "name_key", "name", "cost", "target", "range", "effects", "description"]:
					if not skill_definition.has(key):
						validation_errors.append("Skill %s is missing %s." % [skill_id, key])
				_validate_effects(skill_definition.get("effects", []), "skill %s" % String(skill_definition.get("id", "unknown")))
				var skill_cost: Dictionary = skill_definition.get("cost", {}) as Dictionary
				if int(skill_cost.get("stamina", -1)) != 0 or int(skill_cost.get("mana", -1)) != 0:
					validation_errors.append("Character skill %s must have zero resource cost." % skill_id)


func _validate_events() -> void:
	var category_counts: Dictionary = {"reward": 0, "choice": 0, "pressure": 0}
	for event_definition: Dictionary in events:
		var event_id: String = String(event_definition.get("id", "unknown"))
		for key: String in ["title_key", "title", "description_key", "description", "category"]:
			if not event_definition.has(key):
				validation_errors.append("Event %s is missing %s." % [event_id, key])
		var category: String = String(event_definition.get("category", ""))
		if category_counts.has(category):
			category_counts[category] = int(category_counts[category]) + 1
		else:
			validation_errors.append("Event %s has invalid category %s." % [event_id, category])
		if category == "choice":
			var choices: Array = event_definition.get("choices", []) as Array
			var has_fallback: bool = false
			for choice_value: Variant in choices:
				if not choice_value is Dictionary:
					continue
				var choice: Dictionary = choice_value as Dictionary
				if not choice.has("requires"):
					has_fallback = true
				_validate_effects(choice.get("effects", []), "event choice %s" % event_id)
			if not has_fallback:
				validation_errors.append("Choice event %s has no unconditional fallback." % event_id)
		else:
			_validate_effects(event_definition.get("effects", []), "event %s" % event_id)
	if int(category_counts["reward"]) != 8 or int(category_counts["choice"]) != 4 or int(category_counts["pressure"]) != 4:
		validation_errors.append("Event categories must be 8 reward / 4 choice / 4 pressure.")


func _validate_staged_events() -> void:
	var seen: Dictionary = {}
	for event_definition: Dictionary in staged_events:
		var event_id := String(event_definition.get("id", ""))
		if event_id.is_empty() or seen.has(event_id):
			validation_errors.append("Staged event IDs must be non-empty and unique.")
		seen[event_id] = true
		for key: String in ["title", "source_text", "effects", "provisional"]:
			if not event_definition.has(key):
				validation_errors.append("Staged event %s is missing %s." % [event_id, key])
		if not bool(event_definition.get("provisional", false)):
			validation_errors.append("Staged event %s must be marked provisional until mapped." % event_id)
		_validate_effects(event_definition.get("effects", []), "staged event %s" % event_id)


func _validate_staged_cards() -> void:
	var seen: Dictionary = {}
	var instance_seen: Dictionary = {}
	for card_definition: Dictionary in staged_cards:
		var card_id := String(card_definition.get("id", ""))
		if card_id.is_empty() or seen.has(card_id):
			validation_errors.append("Staged card IDs must be non-empty and unique.")
		seen[card_id] = true
		for key: String in ["name", "category", "profession", "cost", "source_text", "instances", "effects", "provisional"]:
			if not card_definition.has(key):
				validation_errors.append("Staged card %s is missing %s." % [card_id, key])
		if not bool(card_definition.get("provisional", false)):
			validation_errors.append("Staged card %s must be marked provisional until mapped." % card_id)
		if String(card_definition.get("category", "")) == "equipment" and card_definition.get("durability", null) != null and int(card_definition.get("durability", -1)) < 0:
			validation_errors.append("Staged equipment %s has invalid durability." % card_id)
		var instances: Array = card_definition.get("instances", []) as Array
		if instances.is_empty():
			validation_errors.append("Staged card %s must contain at least one instance." % card_id)
		for instance_index: int in instances.size():
			var instance_value: Variant = instances[instance_index]
			if not instance_value is Dictionary:
				validation_errors.append("Staged card %s has an invalid instance." % card_id)
				continue
			var instance: Dictionary = instance_value as Dictionary
			var instance_id := "%s#%03d" % [card_id, instance_index + 1]
			if instance_seen.has(instance_id):
				validation_errors.append("Staged card instance ID %s is duplicated." % instance_id)
			instance_seen[instance_id] = true
			if not SUIT_IDS.has(String(instance.get("suit", ""))) or int(instance.get("rank", -1)) < 1 or int(instance.get("rank", -1)) > 13:
				validation_errors.append("Staged card %s has invalid suit/rank instance." % card_id)
		_validate_effects(card_definition.get("effects", []), "staged card %s" % card_id)


func _validate_statuses() -> void:
	for status_id: String in LAUNCH_STATUS_IDS:
		if not statuses_by_id.has(status_id):
			validation_errors.append("Missing launch status %s." % status_id)
	for status_definition: Dictionary in statuses:
		var status_id: String = String(status_definition.get("id", "unknown"))
		if not LAUNCH_STATUS_IDS.has(status_id):
			validation_errors.append("Unsupported public status %s." % status_id)
		for key: String in ["name_key", "name", "max_stacks", "timing", "duration", "clear", "description"]:
			if not status_definition.has(key):
				validation_errors.append("Status %s is missing %s." % [status_id, key])


func _validate_effects(effect_values: Variant, owner: String) -> void:
	if not effect_values is Array:
		validation_errors.append("%s effects must be an array." % owner)
		return
	for effect_value: Variant in effect_values as Array:
		if not effect_value is Dictionary:
			validation_errors.append("%s has a non-dictionary effect." % owner)
			continue
		var effect: Dictionary = effect_value as Dictionary
		var operation: String = String(effect.get("op", ""))
		if not SUPPORTED_EFFECTS.has(operation):
			validation_errors.append("%s uses unsupported effect %s." % [owner, operation])
		elif operation == "provisional":
			if String(effect.get("alias", effect.get("text", ""))).is_empty():
				validation_errors.append("%s provisional effect must include alias or text." % owner)
		elif operation == "status" or operation == "remove_status":
			var status_id: String = String(effect.get("status", ""))
			if not statuses_by_id.has(status_id):
				validation_errors.append("%s references missing status %s." % [owner, status_id])
		elif operation == "modifier":
			var modifier_id: String = String(effect.get("modifier", ""))
			if not MODIFIER_IDS.has(modifier_id):
				validation_errors.append("%s references unsupported modifier %s." % [owner, modifier_id])
