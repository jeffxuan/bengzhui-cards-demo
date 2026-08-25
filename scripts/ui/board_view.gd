class_name BoardView
extends Control

signal cell_selected(position: Vector2i)
signal player_selected(player_id: int)

const PLAYER_COLORS: Array[Color] = [Color("d94f76"), Color("36a6c9"), Color("75b86b"), Color("e0a93f")]
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
var hovered_cell: Vector2i = Vector2i(-1, -1)
var keyboard_cell: Vector2i = Vector2i(-1, -1)
var font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	tooltip_text = "棋盘：方向键移动光标，回车确认"
	custom_minimum_size = Vector2(400, 400)
	font = load("res://assets/third_party/noto_sans_sc/NotoSansSC-Variable.ttf") as Font


func set_match_state(match_state: RefCounted) -> void:
	state = match_state
	queue_redraw()


func set_interactions(legal_moves: Dictionary, legal_targets: Array[int]) -> void:
	move_commands = legal_moves.duplicate(true)
	target_ids = legal_targets.duplicate()
	_ensure_keyboard_cell()
	queue_redraw()


func set_range_preview(cells: Array[Vector2i]) -> void:
	range_cells = cells.duplicate()
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
			if range_cells.has(position):
				draw_rect(rect.grow(-5.0), Color("e1b94f"), false, 2.0)
			if has_focus() and position == keyboard_cell:
				draw_rect(rect.grow(-6.0), Color("f3c75f"), false, 2.0)
			_draw_tile_marker(kind, rect, cell_size)
	_draw_players(origin, cell_size)


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
			return "%s\n生命 %d/%d · 护甲 %d · 手牌 %d\n状态 %s" % [String(player_state.get("name", "")), int(player_state.get("health", 0)), int(player_state.get("max_health", 0)), int(player_state.get("armor", 0)), (player_state.get("hand", []) as Array).size(), status_text]
	return {"wealth": "财富格：首次停留获得2金币", "event": "神异格：抽取公共事件", "trap": "陷阱：每次经过受到1点真实伤害", "collapsed": "已崩坠区域"}.get(String(state.call("tile_kind", cell)), "普通格") as String


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
