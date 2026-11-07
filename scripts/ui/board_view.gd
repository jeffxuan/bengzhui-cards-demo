class_name BoardView
extends Control

signal cell_selected(position: Vector2i)
signal player_selected(player_id: int)

const PLAYER_COLORS: Array[Color] = [Color("d94f76"), Color("36a6c9"), Color("75b86b"), Color("e0a93f")]
const SPARK_TEXTURE := preload("res://assets/third_party/godot_demo_particles/spark_particle2.png")
const LocalizationScript = preload("res://scripts/ui/localization.gd")
const TILE_COLORS: Dictionary = {
	"normal": Color("252a31"),
	"wealth": Color("57451f"),
	"event": Color("432c43"),
	"trap": Color("4b2529"),
	"collapsed": Color("0b0c0f")
}

var state: RefCounted
var move_commands: Dictionary = {}
var target_ids: Array[int] = []
var range_cells: Array[Vector2i] = []
var move_path_cells: Array[Vector2i] = []
var hovered_cell: Vector2i = Vector2i(-1, -1)
var keyboard_cell: Vector2i = Vector2i(-1, -1)
var font: Font
var feedback: Array[Dictionary] = []
var reduced_motion: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	tooltip_text = "棋盘：方向键移动光标，回车确认"
	custom_minimum_size = Vector2(400, 400)
	font = load("res://assets/third_party/noto_sans_sc/NotoSansSC-Variable.ttf") as Font


func set_match_state(match_state: RefCounted) -> void:
	state = match_state
	queue_redraw()


func set_reduced_motion(enabled: bool) -> void:
	reduced_motion = enabled


func show_match_event(event: Dictionary) -> void:
	if state == null:
		return
	var event_type: String = String(event.get("type", ""))
	if event_type != "damage" and event_type != "healed" and event_type != "defeated":
		return
	var payload: Dictionary = event.get("payload", {}) as Dictionary
	var player_id: int = int(payload.get("target_id", payload.get("player_id", -1)))
	if player_id < 0 or player_id >= (state.get("players") as Array).size():
		return
	var player_state: Dictionary = state.call("player", player_id) as Dictionary
	var entry := {
		"position": player_state.get("position", Vector2i.ZERO),
		"player_id": player_id,
		"type": event_type,
		"amount": int(payload.get("amount", 0)),
		"area": bool(payload.get("area", false)),
		"start": Time.get_ticks_msec()
	}
	var source_id: int = int(payload.get("source_id", -1))
	if source_id >= 0 and source_id < (state.get("players") as Array).size() and source_id != player_id:
		entry["source_position"] = (state.call("player", source_id) as Dictionary).get("position", Vector2i.ZERO)
	feedback.append(entry)
	if feedback.size() > 16:
		feedback.pop_front()
	set_process(true)
	queue_redraw()


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	for index: int in range(feedback.size() - 1, -1, -1):
		if now - int(feedback[index].get("start", now)) >= 650:
			feedback.remove_at(index)
	queue_redraw()
	if feedback.is_empty():
		set_process(false)


func set_interactions(legal_moves: Dictionary, legal_targets: Array[int]) -> void:
	move_commands = legal_moves.duplicate(true)
	target_ids = legal_targets.duplicate()
	_ensure_keyboard_cell()
	queue_redraw()


func set_range_preview(cells: Array[Vector2i]) -> void:
	range_cells = cells.duplicate()
	queue_redraw()


func set_move_path(cells: Array[Vector2i]) -> void:
	move_path_cells = cells.duplicate()
	queue_redraw()


func set_keyboard_cell(position: Vector2i) -> void:
	if state == null:
		keyboard_cell = Vector2i(-1, -1)
		return
	var grid_size: int = int(state.get("board_size"))
	keyboard_cell = Vector2i(clampi(position.x, 0, grid_size - 1), clampi(position.y, 0, grid_size - 1))
	queue_redraw()


func focus_selection() -> void:
	if state == null:
		return
	for player_value: Variant in state.get("players") as Array:
		var player_state: Dictionary = player_value as Dictionary
		if target_ids.has(int(player_state.get("id", -1))) and bool(player_state.get("alive", false)):
			set_keyboard_cell(player_state.get("position", Vector2i.ZERO) as Vector2i)
			grab_focus()
			return
	_ensure_keyboard_cell()
	grab_focus()


func _draw() -> void:
	if state == null:
		return
	var geometry: Dictionary = _board_geometry()
	var origin: Vector2 = geometry["origin"] as Vector2
	var cell_size: float = float(geometry["cell_size"])
	var grid_size: int = int(state.get("board_size"))
	draw_rect(Rect2(origin - Vector2(10, 10), Vector2.ONE * (cell_size * grid_size + 20.0)), Color("111318"), true)
	for y: int in grid_size:
		for x: int in grid_size:
			var position: Vector2i = Vector2i(x, y)
			var kind: String = String(state.call("tile_kind", position))
			var rect: Rect2 = Rect2(origin + Vector2(x, y) * cell_size, Vector2.ONE * cell_size).grow(-2.0)
			var tile_color: Color = TILE_COLORS.get(kind, TILE_COLORS["normal"]) as Color
			if position == hovered_cell and kind != "collapsed":
				tile_color = tile_color.lightened(0.10)
			draw_rect(rect, tile_color, true)
			draw_rect(rect, Color("49515b") if kind != "collapsed" else Color("17191e"), false, 1.0)
			var destination_key: String = "%d:%d" % [x, y]
			if move_commands.has(destination_key):
				draw_rect(rect.grow(-3.0), Color("d94f76"), false, 3.0)
			if move_path_cells.has(position):
				draw_rect(rect.grow(-5.0), Color(0.38, 0.66, 0.46, 0.28), true)
				draw_rect(rect.grow(-5.0), Color("b9e3c7"), false, 2.0)
			if range_cells.has(position):
				draw_rect(rect.grow(-5.0), Color("e1b94f"), false, 2.0)
			if has_focus() and position == keyboard_cell:
				draw_rect(rect.grow(-6.0), Color("f3c75f"), false, 2.0)
			_draw_tile_marker(kind, rect, cell_size)
	_draw_players(origin, cell_size)
	_draw_feedback(origin, cell_size)


func _draw_tile_marker(kind: String, rect: Rect2, cell_size: float) -> void:
	var marker: String = {"wealth": "◆", "event": "?", "trap": "×"}.get(kind, "") as String
	if marker.is_empty():
		return
	var marker_color: Color = {"wealth": Color("f3c75f"), "event": Color("e590c1"), "trap": Color("f0756e")}.get(kind, Color.WHITE) as Color
	var marker_size: int = maxi(14, int(cell_size * 0.30))
	var marker_width: float = font.get_string_size(marker, HORIZONTAL_ALIGNMENT_LEFT, -1, marker_size).x
	draw_string(font, rect.get_center() + Vector2(-marker_width * 0.5, marker_size * 0.34), marker, HORIZONTAL_ALIGNMENT_LEFT, -1, marker_size, marker_color)


func _draw_players(origin: Vector2, cell_size: float) -> void:
	for player_value: Variant in state.get("players") as Array:
		var player_state: Dictionary = player_value as Dictionary
		if not bool(player_state.get("alive", false)):
			continue
		var player_id: int = int(player_state.get("id", -1))
		var position: Vector2i = player_state.get("position", Vector2i.ZERO) as Vector2i
		var center: Vector2 = origin + (Vector2(position) + Vector2(0.5, 0.5)) * cell_size
		if not reduced_motion:
			for effect: Dictionary in feedback:
				if int(effect.get("player_id", -1)) == player_id and String(effect.get("type", "")) == "damage" and int(effect.get("amount", 0)) > 0:
					var age: float = float(Time.get_ticks_msec() - int(effect.get("start", 0))) / 1000.0
					if age < 0.18:
						center.x += sin(age * 105.0) * (1.0 - age / 0.18) * 4.0
		var radius: float = cell_size * 0.31
		if target_ids.has(player_id):
			draw_circle(center, radius + 6.0, Color("f3c75f"))
		draw_circle(center, radius, PLAYER_COLORS[player_id % PLAYER_COLORS.size()])
		draw_arc(center, radius, 0.0, TAU, 32, Color("f4f0e8"), 2.0)
		var label: String = String(player_state.get("name", "?"))
		if label.length() > 3:
			label = label.left(3)
		var font_size: int = maxi(12, int(cell_size * 0.21))
		var label_width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, center + Vector2(-label_width * 0.5, font_size * 0.32), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("121318"))
		var health_ratio: float = float(player_state.get("health", 0)) / float(maxi(1, int(player_state.get("max_health", 1))))
		var bar_rect: Rect2 = Rect2(center + Vector2(-radius, radius + 5.0), Vector2(radius * 2.0, 4.0))
		draw_rect(bar_rect, Color("0d0e11"), true)
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * health_ratio, bar_rect.size.y)), Color("eb6b67"), true)


func _draw_feedback(origin: Vector2, cell_size: float) -> void:
	var now: int = Time.get_ticks_msec()
	for effect: Dictionary in feedback:
		var age: float = float(now - int(effect.get("start", now))) / 1000.0
		var position: Vector2i = effect.get("position", Vector2i.ZERO) as Vector2i
		var center: Vector2 = origin + (Vector2(position) + Vector2(0.5, 0.5)) * cell_size
		var effect_type: String = String(effect.get("type", ""))
		var amount: int = int(effect.get("amount", 0))
		var color: Color = Color("e98170") if amount > 0 else Color("b5d0e3")
		var label: String = "−%d" % amount if amount > 0 else "抵消"
		if effect_type == "healed":
			color = Color("88d4a0")
			label = "+%d" % amount
		elif effect_type == "defeated":
			color = Color("f1c86a")
			label = "击败"
		if not reduced_motion and age < 0.28 and effect_type != "healed":
			var alpha: float = 1.0 - age / 0.28
			if age < 0.16:
				var flash_alpha: float = (1.0 - age / 0.16) * (0.48 if amount > 0 else 0.28)
				draw_rect(Rect2(center - Vector2.ONE * cell_size * 0.46, Vector2.ONE * cell_size * 0.92), Color(color.r, color.g, color.b, flash_alpha), true)
			if amount > 0 and not bool(effect.get("area", false)) and effect.has("source_position") and age < 0.20:
				var source_position: Vector2i = effect.get("source_position", Vector2i.ZERO) as Vector2i
				var source_center: Vector2 = origin + (Vector2(source_position) + Vector2(0.5, 0.5)) * cell_size
				var direction: Vector2 = (center - source_center).normalized()
				var slash_end: Vector2 = center + direction * cell_size * 0.20
				var slash_start: Vector2 = center - direction * cell_size * 0.65
				draw_line(slash_start, slash_end, Color(color.r, color.g, color.b, alpha * 0.42), 7.0)
				draw_line(slash_start, slash_end, Color(1.0, 0.96, 0.85, alpha), 2.0)
			draw_arc(center, cell_size * (0.24 + age * 0.8), 0.0, TAU, 24, Color(color.r, color.g, color.b, alpha * 0.8), 2.5)
			for spark_index: int in 8:
				var angle: float = float(spark_index) * TAU / 8.0
				var spark_center: Vector2 = center + Vector2.from_angle(angle) * cell_size * (0.22 + age * 0.9)
				var spark_size: float = maxf(3.0, cell_size * 0.13 * alpha)
				draw_texture_rect(SPARK_TEXTURE, Rect2(spark_center - Vector2.ONE * spark_size * 0.5, Vector2.ONE * spark_size), false, Color(color.r, color.g, color.b, alpha))
		var float_offset: float = minf(age * 30.0, 14.0) if not reduced_motion else 0.0
		var font_size: int = maxi(19, int(cell_size * 0.42))
		label = LocalizationScript.text(label)
		var text_width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var text_position: Vector2 = center + Vector2(-text_width * 0.5, -cell_size * 0.50 - float_offset)
		var fade: float = 1.0 if age < 0.38 else 1.0 - (age - 0.38) / 0.27
		var label_rect := Rect2(text_position + Vector2(-5, -font_size), Vector2(text_width + 10.0, font_size + 5.0))
		draw_rect(label_rect, Color(0.04, 0.05, 0.07, fade * 0.88), true)
		draw_string(font, text_position + Vector2(1, 2), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, fade * 0.9))
		draw_string(font, text_position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(color.r, color.g, color.b, fade))


func _gui_input(event: InputEvent) -> void:
	if state == null:
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		var direction: Vector2i = {
			KEY_LEFT: Vector2i.LEFT,
			KEY_RIGHT: Vector2i.RIGHT,
			KEY_UP: Vector2i.UP,
			KEY_DOWN: Vector2i.DOWN
		}.get(key_event.keycode, Vector2i.ZERO) as Vector2i
		if direction != Vector2i.ZERO:
			_ensure_keyboard_cell()
			set_keyboard_cell(keyboard_cell + direction)
			accept_event()
		elif key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER:
			_ensure_keyboard_cell()
			_activate_cell(keyboard_cell)
			accept_event()
	elif event is InputEventMouseMotion:
		hovered_cell = _cell_at((event as InputEventMouseMotion).position)
		queue_redraw()
	elif event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
			return
		var cell: Vector2i = _cell_at(mouse_event.position)
		if cell.x < 0:
			return
		set_keyboard_cell(cell)
		grab_focus()
		_activate_cell(cell)


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_ENTER:
		_ensure_keyboard_cell()
		queue_redraw()
	elif what == NOTIFICATION_FOCUS_EXIT:
		queue_redraw()


func _ensure_keyboard_cell() -> void:
	if state == null:
		keyboard_cell = Vector2i(-1, -1)
		return
	var grid_size: int = int(state.get("board_size"))
	if keyboard_cell.x >= 0 and keyboard_cell.y >= 0 and keyboard_cell.x < grid_size and keyboard_cell.y < grid_size:
		return
	for player_value: Variant in state.get("players") as Array:
		var player_state: Dictionary = player_value as Dictionary
		if int(player_state.get("id", -1)) == 0 and bool(player_state.get("alive", false)):
			keyboard_cell = player_state.get("position", Vector2i.ZERO) as Vector2i
			return
	keyboard_cell = Vector2i.ZERO


func _activate_cell(cell: Vector2i) -> void:
	if cell.x < 0:
		return
	for player_value: Variant in state.get("players") as Array:
		var player_state: Dictionary = player_value as Dictionary
		var player_position: Vector2i = player_state.get("position", Vector2i.ZERO) as Vector2i
		if bool(player_state.get("alive", false)) and player_position == cell:
			player_selected.emit(int(player_state.get("id", -1)))
			return
	cell_selected.emit(cell)


func _get_tooltip(at_position: Vector2) -> String:
	if state == null:
		return ""
	var cell: Vector2i = _cell_at(at_position)
	if cell.x < 0:
		return ""
	for player_value: Variant in state.get("players") as Array:
		var player_state: Dictionary = player_value as Dictionary
		var player_position: Vector2i = player_state.get("position", Vector2i.ZERO) as Vector2i
		if bool(player_state.get("alive", false)) and player_position == cell:
			var status_text: String = "、".join((player_state.get("statuses", {}) as Dictionary).keys())
			if status_text.is_empty():
				status_text = "无"
			return LocalizationScript.text("%s\n生命 %d/%d · 护甲 %d · 手牌 %d\n状态 %s" % [String(player_state.get("name", "")), int(player_state.get("health", 0)), int(player_state.get("max_health", 0)), int(player_state.get("armor", 0)), (player_state.get("hand", []) as Array).size(), status_text])
	return LocalizationScript.text({"wealth": "财富格：首次停留获得2金币", "event": "神异格：抽取公共事件", "trap": "陷阱：每次经过受到1点真实伤害", "collapsed": "已崩坠区域"}.get(String(state.call("tile_kind", cell)), "普通格") as String)


func _cell_at(local_position: Vector2) -> Vector2i:
	var geometry: Dictionary = _board_geometry()
	var origin: Vector2 = geometry["origin"] as Vector2
	var cell_size: float = float(geometry["cell_size"])
	var grid_size: int = int(state.get("board_size"))
	var relative: Vector2 = local_position - origin
	if relative.x < 0.0 or relative.y < 0.0 or relative.x >= cell_size * grid_size or relative.y >= cell_size * grid_size:
		return Vector2i(-1, -1)
	return Vector2i(int(relative.x / cell_size), int(relative.y / cell_size))


func _board_geometry() -> Dictionary:
	var side: float = minf(size.x, size.y) - 20.0
	var grid_size: int = int(state.get("board_size")) if state != null else 15
	var cell_size: float = floorf(side / float(grid_size))
	var board_side: float = cell_size * grid_size
	return {"cell_size": cell_size, "origin": (size - Vector2.ONE * board_side) * 0.5}
