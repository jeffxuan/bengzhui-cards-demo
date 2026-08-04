class_name MatchEvent
extends RefCounted


static func make(event_type: String, payload: Dictionary = {}) -> Dictionary:
	return {
		"type": event_type,
		"payload": payload.duplicate(true)
	}
