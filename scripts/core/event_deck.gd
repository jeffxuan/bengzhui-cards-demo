class_name EventDeck
extends RefCounted

var _draw_pile: Array[Dictionary] = []
var _discard_pile: Array[Dictionary] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(cards: Array[Dictionary], seed: int) -> void:
	_draw_pile = cards.duplicate(true)
	_rng.seed = seed
	_shuffle_draw_pile()


func draw() -> Dictionary:
	if _draw_pile.is_empty():
		_draw_pile = _discard_pile.duplicate(true)
		_discard_pile.clear()
		_shuffle_draw_pile()
	if _draw_pile.is_empty():
		return {}
	var card: Dictionary = _draw_pile.pop_back() as Dictionary
	_discard_pile.append(card)
	return card.duplicate(true)


func remaining_count() -> int:
	return _draw_pile.size()


func discard_count() -> int:
	return _discard_pile.size()


func snapshot() -> Dictionary:
	var draw_ids: Array[String] = []
	var discard_ids: Array[String] = []
	for card: Dictionary in _draw_pile:
		draw_ids.append(String(card.get("id", "")))
	for card: Dictionary in _discard_pile:
		discard_ids.append(String(card.get("id", "")))
	return {"draw": draw_ids, "discard": discard_ids}


func _shuffle_draw_pile() -> void:
	for index: int in range(_draw_pile.size() - 1, 0, -1):
		var swap_index: int = _rng.randi_range(0, index)
		var swap_card: Dictionary = _draw_pile[index]
		_draw_pile[index] = _draw_pile[swap_index]
		_draw_pile[swap_index] = swap_card
