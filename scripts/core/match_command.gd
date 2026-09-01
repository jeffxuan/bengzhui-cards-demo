class_name MatchCommand
extends RefCounted

const MOVE := "move"
const PLAY_CARD := "play_card"
const RESPOND := "respond"
const USE_SKILL := "use_skill"
const BUY := "buy"
const EVENT_CHOICE := "event_choice"
const END_TURN := "end_turn"
const DISCARD_CARDS := "discard_cards"
const SWITCH_PROFESSION := "switch_profession"
const SKILL_DISCARD := "skill_discard"
const SKILL_CHOICE := "skill_choice"


static func make(command_type: String, actor_id: int, payload: Dictionary = {}) -> Dictionary:
	return {
		"type": command_type,
		"actor_id": actor_id,
		"payload": payload.duplicate(true)
	}
