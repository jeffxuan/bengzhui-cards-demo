class_name MatchCommand
extends RefCounted

const MOVE := "move"
const PLAY_CARD := "play_card"
const RESPOND := "respond"
const USE_SKILL := "use_skill"
const BUY := "buy"
const EVENT_CHOICE := "event_choice"
const END_TURN := "end_turn"


static func make(command_type: String, actor_id: int, payload: Dictionary = {}) -> Dictionary:
	return {
		"type": command_type,
		"actor_id": actor_id,
		"payload": payload.duplicate(true)
	}
