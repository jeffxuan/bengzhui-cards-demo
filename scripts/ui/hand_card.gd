class_name HandCard
extends Button

const CATEGORY_COLORS := {
	"attack": Color("d56c60"),
	"skill": Color("6ba9a3"),
	"response": Color("8ea7d0"),
	"equipment": Color("d5ad60")
}
const SUIT_COLORS := {"hearts": Color("e9847d"), "diamonds": Color("e5ad64"), "clubs": Color("9ecb9c"), "spades": Color("bdc9dc")}

var resting_rotation: float = 0.0
var selected: bool = false
var reduced_motion: bool = false
var pose_tween: Tween


func _ready() -> void:
	mouse_entered.connect(_refresh_pose)
	mouse_exited.connect(_refresh_pose)
	focus_entered.connect(_refresh_pose)
	focus_exited.connect(_refresh_pose)


func set_pose(angle: float, is_selected: bool, motion_reduced: bool) -> void:
	resting_rotation = angle
	selected = is_selected
	reduced_motion = motion_reduced
	pivot_offset = custom_minimum_size * 0.5
	_refresh_pose(true)


func _refresh_pose(immediate: bool = false) -> void:
	if pose_tween != null and pose_tween.is_running():
		pose_tween.kill()
	var raised: bool = selected or is_hovered() or has_focus()
	var target_scale: Vector2 = Vector2.ONE * (1.07 if raised and not disabled else 1.0)
	var target_rotation: float = 0.0 if raised else resting_rotation
	z_index = 3 if raised else 0
	if immediate or reduced_motion:
		scale = target_scale
		rotation = target_rotation
		return
	pose_tween = create_tween().set_parallel(true)
	pose_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	pose_tween.tween_property(self, "scale", target_scale, 0.18)
	pose_tween.tween_property(self, "rotation", target_rotation, 0.18)


func configure(definition: Dictionary, identity: String, cost: String, range_text: String, reserved: bool, scale: float) -> void:
	custom_minimum_size = Vector2(216, 102)
	clip_contents = true
	autowrap_mode = TextServer.AUTOWRAP_OFF
	var category: String = String(definition.get("category", "skill"))
	var accent: Color = CATEGORY_COLORS.get(category, Color("9ba9b8")) as Color
	var base: Color = Color("252b32")
	for state_name: String in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = base if state_name != "hover" else Color("343d47")
		style.border_color = accent if state_name != "disabled" else Color("515a64")
		style.set_border_width_all(1)
		style.border_width_top = 3
		style.set_corner_radius_all(6)
		add_theme_stylebox_override(state_name, style)
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		add_theme_color_override(color_name, Color.TRANSPARENT)
	add_theme_constant_override("h_separation", 0)

	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 10
	content.offset_top = 8
	content.offset_right = -10
	content.offset_bottom = -7
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 2)
	add_child(content)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(header)
	var suit: String = String(definition.get("suit", "none"))
	var badge := _label(identity if not identity.is_empty() else "--", 15, SUIT_COLORS.get(suit, Color("c4cbd1")) as Color, scale)
	badge.custom_minimum_size.x = 46
	header.add_child(badge)
	var category_label := _label(_category_name(category), 11, accent, scale)
	category_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	category_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(category_label)
	var title := _label(String(definition.get("name", "未知卡牌")), 16, Color("f4f0e8"), scale)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(spacer)
	var footer := HBoxContainer.new()
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(footer)
	var cost_label := _label(cost, 11, Color("d9e0e6"), scale)
	cost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(cost_label)
	var range_label := _label("保留" if reserved else range_text, 11, Color("bac6d0"), scale)
	range_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(range_label)


func _label(value: String, font_size: int, color: Color, scale: float) -> Label:
	var result := Label.new()
	result.text = value
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_font_size_override("font_size", int(round(font_size * scale)))
	result.add_theme_color_override("font_color", color)
	return result


func _category_name(category: String) -> String:
	return {"attack": "攻击", "defense": "防御牌", "奇异": "奇异牌", "skill": "技能", "response": "响应", "equipment": "装备"}.get(category, "卡牌") as String
