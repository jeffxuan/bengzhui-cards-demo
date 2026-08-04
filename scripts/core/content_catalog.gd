class_name ContentCatalog
extends RefCounted

const CARD_PATH := "res://rules/cards.json"
const CHARACTER_PATH := "res://rules/characters.json"
const EVENT_PATH := "res://rules/events.json"
const STATUS_PATH := "res://rules/statuses.json"
const SUPPORTED_EFFECTS: Array[String] = [
	"damage", "self_damage", "heal", "armor", "resource", "draw", "draw_target",
	"status", "remove_status", "cleanse", "coins", "extra_action", "extra_move",
	"push", "break_armor", "steal_card", "self_discard", "discard_or_damage",
	"recover_last_card", "reveal_hand", "equip", "negate", "reflect", "modifier"
]
const LAUNCH_STATUS_IDS: Array[String] = ["paralyze", "bleed", "poison", "confusion", "hidden", "scorch"]
const MODIFIER_IDS: Array[String] = ["free_cast", "echo"]

var version: int = 1
var cards: Array[Dictionary] = []
var characters: Array[Dictionary] = []
var events: Array[Dictionary] = []
var statuses: Array[Dictionary] = []
var cards_by_id: Dictionary = {}
var characters_by_id: Dictionary = {}
var statuses_by_id: Dictionary = {}
var validation_errors: Array[String] = []


func _init() -> void:
	_load_all()


func is_valid() -> bool:
	return validation_errors.is_empty()


func card(card_id: String) -> Dictionary:
	return cards_by_id.get(card_id, {}) as Dictionary


func character(character_id: String) -> Dictionary:
	return characters_by_id.get(character_id, {}) as Dictionary


func status(status_id: String) -> Dictionary:
	return statuses_by_id.get(status_id, {}) as Dictionary


func market_card_ids() -> Array[String]:
	var result: Array[String] = []
	for card_definition: Dictionary in cards:
		var card_id: String = String(card_definition.get("id", ""))
		if not card_id.is_empty():
			result.append(card_id)
	return result


func _load_all() -> void:
	var card_document: Dictionary = _load_document(CARD_PATH)
	var character_document: Dictionary = _load_document(CHARACTER_PATH)
	var event_document: Dictionary = _load_document(EVENT_PATH)
	var status_document: Dictionary = _load_document(STATUS_PATH)
	cards = _dictionary_array(card_document.get("cards", []))
	characters = _dictionary_array(character_document.get("characters", []))
	events = _dictionary_array(event_document.get("events", []))
	statuses = _dictionary_array(status_document.get("statuses", []))
	version = maxi(
		int(card_document.get("version", 1)),
		maxi(
			int(character_document.get("version", 1)),
			maxi(int(event_document.get("version", 1)), int(status_document.get("version", 1)))
		)
	)
	_index_definitions(cards, cards_by_id, "card")
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
	_validate_statuses()


func _validate_cards() -> void:
	for card_definition: Dictionary in cards:
		var card_id: String = String(card_definition.get("id", "unknown"))
		for key: String in ["name_key", "name", "category", "profession", "cost", "price", "target", "range", "effects", "tags", "description"]:
			if not card_definition.has(key):
				validation_errors.append("Card %s is missing %s." % [card_id, key])
		_validate_effects(card_definition.get("effects", []), "card %s" % card_id)


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
		elif operation == "status" or operation == "remove_status":
			var status_id: String = String(effect.get("status", ""))
			if not statuses_by_id.has(status_id):
				validation_errors.append("%s references missing status %s." % [owner, status_id])
		elif operation == "modifier":
			var modifier_id: String = String(effect.get("modifier", ""))
			if not MODIFIER_IDS.has(modifier_id):
				validation_errors.append("%s references unsupported modifier %s." % [owner, modifier_id])
