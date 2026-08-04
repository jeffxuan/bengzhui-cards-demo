class_name AudioFeedback
extends Node

const CHANNEL_COUNT := 6
const ACCEPTED_SOUND := preload("res://assets/third_party/kenney_audio/ui/click1.ogg")
const REJECTED_SOUND := preload("res://assets/third_party/kenney_audio/ui/click5.ogg")
const SOFT_SOUNDS: Array[AudioStream] = [
	preload("res://assets/third_party/kenney_audio/impact/impactSoft_medium_000.ogg"),
	preload("res://assets/third_party/kenney_audio/impact/impactSoft_medium_001.ogg"),
	preload("res://assets/third_party/kenney_audio/impact/impactSoft_medium_002.ogg"),
	preload("res://assets/third_party/kenney_audio/impact/impactSoft_medium_003.ogg"),
	preload("res://assets/third_party/kenney_audio/impact/impactSoft_medium_004.ogg")
]
const METAL_SOUNDS: Array[AudioStream] = [
	preload("res://assets/third_party/kenney_audio/impact/impactMetal_light_000.ogg"),
	preload("res://assets/third_party/kenney_audio/impact/impactMetal_light_001.ogg"),
	preload("res://assets/third_party/kenney_audio/impact/impactMetal_light_002.ogg"),
	preload("res://assets/third_party/kenney_audio/impact/impactMetal_light_003.ogg"),
	preload("res://assets/third_party/kenney_audio/impact/impactMetal_light_004.ogg")
]
const HEAVY_SOUNDS: Array[AudioStream] = [
	preload("res://assets/third_party/kenney_audio/impact/impactWood_heavy_000.ogg"),
	preload("res://assets/third_party/kenney_audio/impact/impactWood_heavy_001.ogg"),
	preload("res://assets/third_party/kenney_audio/impact/impactWood_heavy_002.ogg"),
	preload("res://assets/third_party/kenney_audio/impact/impactWood_heavy_003.ogg"),
	preload("res://assets/third_party/kenney_audio/impact/impactWood_heavy_004.ogg")
]

var channels: Array[AudioStreamPlayer] = []
var channel_cursor := 0
var sound_cursors: Dictionary = {"soft": 0, "metal": 0, "heavy": 0}


func _ready() -> void:
	for _index: int in CHANNEL_COUNT:
		var channel := AudioStreamPlayer.new()
		channel.bus = "Master"
		add_child(channel)
		channels.append(channel)


func _exit_tree() -> void:
	for channel: AudioStreamPlayer in channels:
		channel.stop()
		channel.stream = null
	channels.clear()


func play_match_event(event: Dictionary) -> void:
	var event_type := String(event.get("type", ""))
	var payload := event.get("payload", {}) as Dictionary
	match event_type:
		"command_rejected":
			_play(REJECTED_SOUND)
		"card_played", "skill_used", "event_drawn", "event_resolved", "market_bought", "response_played":
			_play_variant("soft", SOFT_SOUNDS)
		"damage":
			if int(payload.get("amount", 0)) > 0:
				_play_variant("metal", METAL_SOUNDS)
		"defeated", "board_collapsed", "match_finished":
			_play_variant("heavy", HEAVY_SOUNDS)
		"duel_pressure_changed":
			_play(ACCEPTED_SOUND)


func play_confirmation() -> void:
	_play(ACCEPTED_SOUND)


func _play_variant(group: String, streams: Array[AudioStream]) -> void:
	var cursor := int(sound_cursors.get(group, 0))
	_play(streams[cursor % streams.size()])
	sound_cursors[group] = cursor + 1


func _play(stream: AudioStream) -> void:
	if channels.is_empty() or DisplayServer.get_name() == "headless":
		return
	var channel := channels[channel_cursor % channels.size()]
	channel_cursor += 1
	channel.stream = stream
	channel.play()
