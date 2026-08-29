extends Control

const AIControllerScript = preload("res://scripts/core/ai_controller.gd")
const AudioFeedbackScript = preload("res://scripts/ui/audio_feedback.gd")
const BoardViewScript = preload("res://scripts/ui/board_view.gd")
const ContentCatalogScript = preload("res://scripts/core/content_catalog.gd")
const MatchCommandScript = preload("res://scripts/core/match_command.gd")
const MatchStateScript = preload("res://scripts/core/match_state.gd")
const SaveServiceScript = preload("res://scripts/core/save_service.gd")

const COLORS: Dictionary = {
	"void": Color("0b0c0f"),
	"table": Color("171a20"),
	"surface": Color("232831"),
	"surface_high": Color("2d333e"),
	"line": Color("59616d"),
	"ink": Color("f4f0e8"),
	"muted": Color("aab5c3"),
	"primary": Color("9b315e"),
	"primary_hover": Color("b33d70"),
	"gold": Color("e1b94f"),
	"danger": Color("e2706a"),
	"success": Color("62a875")
}
const CHARACTER_ORDER: Array[String] = ["q", "k", "shya", "ginger", "zc", "na1", "maddy", "signal"]

var catalog: RefCounted
var ai_controller: RefCounted
var audio_feedback: AudioFeedback
var state: RefCounted
var rules: Dictionary
var settings: Dictionary
var ui_font: Font
var selected_character_id: String = "q"
var selected_target_commands: Array[Dictionary] = []
var move_commands: Dictionary = {}
var log_lines: Array[String] = []
var ai_running: bool = false
var settings_open: bool = false
var character_buttons: Dictionary = {}
var discard_selected_indices: Array[int] = []

var screen_root: Control
var character_detail_label: Label
var start_button: Button
var board_view: BoardView
var summary_label: Label
var action_hint_label: Label
var resources_box: GridContainer
var status_box: HFlowContainer
var skill_box: VBoxContainer
var market_box: VBoxContainer
var opponents_box: VBoxContainer
var hand_box: HBoxContainer
var hand_band: Control
var log_label: RichTextLabel
var end_turn_button: Button
var modal_layer: ColorRect
var modal_title: Label
var modal_description: Label
var modal_actions: VBoxContainer


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--export-smoke"):
		_run_export_smoke.call_deferred()
		return
	set_process_unhandled_key_input(true)
	ui_font = load("res://assets/third_party/noto_sans_sc/NotoSansSC-Variable.ttf") as Font
	var settings_result: Dictionary = SaveServiceScript.load_settings_result()
	settings = settings_result.get("settings", {}) as Dictionary
	theme = _build_theme(float(settings.get("text_scale", 1.0)))
	_apply_audio_settings()
	audio_feedback = AudioFeedbackScript.new() as AudioFeedback
	add_child(audio_feedback)
	catalog = ContentCatalogScript.new()
	ai_controller = AIControllerScript.new()
	rules = _load_json("res://rules/match_rules.json")
	if not bool(catalog.call("is_valid")):
		_show_fatal_error("内容校验失败：\n%s" % "\n".join(catalog.get("validation_errors") as Array[String]))
		return
	_show_character_select(String(settings_result.get("error", "")))


func _run_export_smoke() -> void:
	var smoke_catalog: RefCounted = ContentCatalogScript.new()
	var smoke_rules: Dictionary = _load_json("res://rules/match_rules.json")
	if not bool(smoke_catalog.call("is_valid")):
		push_error("EXPORT_SMOKE_FAILED: invalid content catalog")
		get_tree().quit(1)
		return
	var smoke_state: RefCounted = MatchStateScript.new(smoke_rules, smoke_catalog, ["q", "ginger", "maddy", "signal"], 4603)
	var smoke_ai: RefCounted = AIControllerScript.new()
	var command_count: int = 0
	while not bool(smoke_state.get("finished")) and command_count < 500:
		var actor_id: int
		var pending_action: Dictionary = smoke_state.get("pending_action") as Dictionary
		var pending_discard: Dictionary = smoke_state.get("pending_discard") as Dictionary
		var pending_skill_discard: Dictionary = smoke_state.get("pending_skill_discard") as Dictionary
		if not pending_discard.is_empty():
			actor_id = int(pending_discard.get("player_id", -1))
		elif not pending_skill_discard.is_empty():
			actor_id = int(pending_skill_discard.get("player_id", -1))
		elif pending_action.is_empty():
			actor_id = int((smoke_state.call("current_player") as Dictionary).get("id", -1))
		else:
			actor_id = int(pending_action.get("responder_id", -1))
		var command: Dictionary = smoke_ai.call("choose_command", smoke_state, actor_id) as Dictionary
		if command.is_empty() or not bool(smoke_state.call("submit_command", command)):
			push_error("EXPORT_SMOKE_FAILED: command %d could not resolve" % command_count)
			get_tree().quit(1)
			return
		command_count += 1
	if not bool(smoke_state.get("finished")):
		push_error("EXPORT_SMOKE_FAILED: match exceeded the command cap")
		get_tree().quit(1)
		return
	print("EXPORT_SMOKE_OK: winner=%d reason=%s commands=%d" % [int(smoke_state.get("winner_id")), String(smoke_state.get("win_reason_id")), command_count])
	get_tree().quit(0)


func _show_character_select(message: String = "") -> void:
	_clear_screen()
	state = null
	var replay_result: Dictionary = SaveServiceScript.load_replay_result()
	var notices: Array[String] = []
	if not message.is_empty():
		notices.append(message)
	var replay_error: String = String(replay_result.get("error", ""))
	if not replay_error.is_empty():
		notices.append(replay_error)
	var background: ColorRect = _background()
	screen_root.add_child(background)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_root.add_child(center)
	var content: VBoxContainer = VBoxContainer.new()
	content.custom_minimum_size = Vector2(780, 620)
	content.add_theme_constant_override("separation", 16)
	center.add_child(content)
	var title: Label = _label("崩坠牌局", 38, COLORS["ink"] as Color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var subtitle: Label = _label("选择你的角色", 18, COLORS["muted"] as Color)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(subtitle)
	if not notices.is_empty():
		var message_label: Label = _label("\n".join(notices), 15, COLORS["danger"] as Color)
		message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(message_label)
	var selection_band: HBoxContainer = HBoxContainer.new()
	selection_band.size_flags_vertical = Control.SIZE_EXPAND_FILL
	selection_band.add_theme_constant_override("separation", 18)
	content.add_child(selection_band)
	var roster_panel: PanelContainer = _panel(COLORS["surface"] as Color)
	roster_panel.custom_minimum_size = Vector2(420, 420)
	selection_band.add_child(roster_panel)
	var roster_grid: GridContainer = GridContainer.new()
	var character_group: ButtonGroup = ButtonGroup.new()
	character_buttons.clear()
	roster_grid.columns = 2
	roster_grid.add_theme_constant_override("h_separation", 10)
	roster_grid.add_theme_constant_override("v_separation", 10)
	roster_panel.add_child(roster_grid)
	for character_id: String in CHARACTER_ORDER:
		var character_definition: Dictionary = catalog.call("character", character_id) as Dictionary
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(185, 82)
		button.toggle_mode = true
		button.button_group = character_group
		button.text = "%s\n%s" % [String(character_definition.get("name", character_id)), _profession_name(String(character_definition.get("profession", "")))]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.tooltip_text = String((character_definition.get("passive", {}) as Dictionary).get("description", ""))
		button.pressed.connect(_select_character.bind(character_id))
		roster_grid.add_child(button)
		character_buttons[character_id] = button
	var detail_panel: PanelContainer = _panel(COLORS["surface"] as Color)
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selection_band.add_child(detail_panel)
	var detail_box: VBoxContainer = VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 12)
	detail_panel.add_child(detail_box)
	var detail_scroll: ScrollContainer = ScrollContainer.new()
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	detail_box.add_child(detail_scroll)
	character_detail_label = _label("", 16, COLORS["ink"] as Color)
	character_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	character_detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(character_detail_label)
	start_button = Button.new()
	start_button.text = "以此角色开始"
	start_button.icon = load("res://assets/third_party/lucide/swords.svg") as Texture2D
	start_button.custom_minimum_size.y = 48
	start_button.pressed.connect(_start_new_match)
	detail_box.add_child(start_button)
	var footer: HBoxContainer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 12)
	content.add_child(footer)
	if bool(replay_result.get("ok", false)) and bool(replay_result.get("exists", false)):
		var continue_button: Button = Button.new()
		continue_button.text = "继续上局"
		continue_button.icon = load("res://assets/third_party/lucide/scroll-text.svg") as Texture2D
		continue_button.pressed.connect(_continue_match)
		footer.add_child(continue_button)
	var settings_button: Button = Button.new()
	settings_button.text = "设置"
	settings_button.icon = load("res://assets/third_party/lucide/settings.svg") as Texture2D
	settings_button.pressed.connect(_open_settings)
	footer.add_child(settings_button)
	_select_character(selected_character_id)
	(character_buttons[selected_character_id] as Button).grab_focus.call_deferred()


func _select_character(character_id: String) -> void:
	selected_character_id = character_id
	for button_id: String in character_buttons:
		(character_buttons[button_id] as Button).button_pressed = button_id == character_id
	if character_detail_label == null:
		return
	var character_definition: Dictionary = catalog.call("character", character_id) as Dictionary
	var passive: Dictionary = character_definition.get("passive", {}) as Dictionary
	var skills: Array = character_definition.get("skills", []) as Array
	var skill_lines: Array[String] = []
	for skill_value: Variant in skills:
		var skill: Dictionary = skill_value as Dictionary
		skill_lines.append("【%s】%s" % [String(skill.get("name", "")), String(skill.get("description", ""))])
	character_detail_label.text = "%s\n%s\n\n生命 %d · 体力 %d · 法力 %d\n\n被动【%s】\n%s\n\n%s" % [
		String(character_definition.get("name", character_id)),
		_profession_name(String(character_definition.get("profession", ""))),
		int(character_definition.get("health", 0)),
		int(character_definition.get("stamina", 0)),
		int(character_definition.get("mana", 0)),
		String(passive.get("name", "")),
		String(passive.get("description", "")),
		"\n\n".join(skill_lines)
	]


func _start_new_match() -> void:
	var roster: Array[String] = [selected_character_id]
	for character_id: String in CHARACTER_ORDER:
		if character_id != selected_character_id and roster.size() < 4:
			roster.append(character_id)
	var match_seed: int = int(Time.get_unix_time_from_system())
	state = MatchStateScript.new(rules, catalog, roster, match_seed)
	log_lines.clear()
	_collect_events()
	_build_match_screen()
	_after_state_change()
	if not bool(settings.get("tutorial_seen", false)):
		_open_tutorial.call_deferred()


func _continue_match() -> void:
	var replay_result: Dictionary = SaveServiceScript.load_replay_result()
	if not bool(replay_result.get("ok", false)) or not bool(replay_result.get("exists", false)):
		_show_character_select(String(replay_result.get("error", "未找到可继续的对局存档。")))
		return
	var replay: Dictionary = replay_result.get("document", {}) as Dictionary
	var rebuilt: Dictionary = SaveServiceScript.rebuild_match(MatchStateScript, rules, catalog, replay)
	if not bool(rebuilt.get("ok", false)):
		_show_character_select(String(rebuilt.get("error", "无法继续上局。")))
		return
	state = rebuilt.get("state") as RefCounted
	selected_character_id = String((state.call("player", 0) as Dictionary).get("character_id", "q"))
	log_lines.clear()
	log_lines.append("已从命令回放恢复对局。")
	_collect_events()
	_build_match_screen()
	_after_state_change()


func _build_match_screen() -> void:
	_clear_screen()
	selected_target_commands.clear()
	move_commands.clear()
	var background: ColorRect = _background()
	screen_root.add_child(background)
	var page: VBoxContainer = VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	page.add_theme_constant_override("separation", 10)
	screen_root.add_child(page)
	page.add_child(_build_top_bar())
	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	page.add_child(body)
	body.add_child(_sidebar_scroll(_build_left_sidebar(), 230))
	board_view = BoardViewScript.new() as BoardView
	board_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_view.set_match_state(state)
	board_view.cell_selected.connect(_on_board_cell_selected)
	board_view.player_selected.connect(_on_board_player_selected)
	body.add_child(board_view)
	body.add_child(_sidebar_scroll(_build_right_sidebar(), 285))
	page.add_child(_build_hand_band())
	_build_modal_layer()
	end_turn_button.grab_focus.call_deferred()


func _build_top_bar() -> Control:
	var panel: PanelContainer = _panel(COLORS["surface"] as Color)
	panel.custom_minimum_size.y = 58
	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	panel.add_child(bar)
	var title: Label = _label("崩坠牌局", 22, COLORS["ink"] as Color)
	title.custom_minimum_size.x = 150
	bar.add_child(title)
	summary_label = _label("", 17, COLORS["muted"] as Color)
	summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(summary_label)
	action_hint_label = _label("", 15, COLORS["gold"] as Color)
	action_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	action_hint_label.custom_minimum_size.x = 240
	bar.add_child(action_hint_label)
	var settings_button: Button = Button.new()
	settings_button.icon = load("res://assets/third_party/lucide/settings.svg") as Texture2D
	settings_button.tooltip_text = "设置"
	settings_button.custom_minimum_size = Vector2(42, 38)
	settings_button.pressed.connect(_open_settings)
	bar.add_child(settings_button)
	var debug_button: Button = Button.new()
	debug_button.icon = load("res://assets/third_party/lucide/scroll-text.svg") as Texture2D
	debug_button.tooltip_text = "对局信息"
	debug_button.custom_minimum_size = Vector2(42, 38)
	debug_button.pressed.connect(_open_debug_info)
	bar.add_child(debug_button)
	var help_button: Button = Button.new()
	help_button.text = "?"
	help_button.tooltip_text = "查看回合规则"
	help_button.custom_minimum_size = Vector2(42, 38)
	help_button.pressed.connect(_open_tutorial)
	bar.add_child(help_button)
	return panel


func _build_left_sidebar() -> Control:
	var panel: PanelContainer = _panel(COLORS["surface"] as Color)
	panel.custom_minimum_size.x = 230
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(_section_label("你的状态"))
	resources_box = GridContainer.new()
	resources_box.columns = 3
	resources_box.add_theme_constant_override("separation", 8)
	box.add_child(resources_box)
	status_box = HFlowContainer.new()
	status_box.add_theme_constant_override("h_separation", 8)
	status_box.add_theme_constant_override("v_separation", 4)
	box.add_child(status_box)
	box.add_child(HSeparator.new())
	box.add_child(_section_label("角色技能"))
	skill_box = VBoxContainer.new()
	skill_box.add_theme_constant_override("separation", 8)
	box.add_child(skill_box)
	box.add_child(HSeparator.new())
	var market_heading: HBoxContainer = HBoxContainer.new()
	market_heading.add_child(_section_label("公共市场"))
	var market_icon: TextureRect = _icon_rect("res://assets/third_party/lucide/shopping-bag.svg", 18)
	market_heading.add_child(market_icon)
	box.add_child(market_heading)
	market_box = VBoxContainer.new()
	market_box.add_theme_constant_override("separation", 7)
	box.add_child(market_box)
	return panel


func _build_right_sidebar() -> Control:
	var panel: PanelContainer = _panel(COLORS["surface"] as Color)
	panel.custom_minimum_size.x = 285
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(_section_label("对手"))
	opponents_box = VBoxContainer.new()
	opponents_box.add_theme_constant_override("separation", 4)
	box.add_child(opponents_box)
	box.add_child(HSeparator.new())
	box.add_child(_section_label("战斗记录"))
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.fit_content = false
	log_label.scroll_active = true
	log_label.scroll_following = true
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.custom_minimum_size.y = 120
	log_label.add_theme_color_override("default_color", COLORS["muted"] as Color)
	box.add_child(log_label)
	return panel


func _sidebar_scroll(content: Control, width: int) -> ScrollContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size.x = width
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll


func _build_hand_band() -> Control:
	var panel: PanelContainer = _panel(COLORS["surface"] as Color)
	hand_band = panel
	panel.custom_minimum_size.y = 150
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var hand_column: VBoxContainer = VBoxContainer.new()
	hand_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_column.add_theme_constant_override("separation", 6)
	row.add_child(hand_column)
	hand_column.add_child(_section_label("手牌"))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hand_column.add_child(scroll)
	hand_box = HBoxContainer.new()
	hand_box.add_theme_constant_override("separation", 8)
	scroll.add_child(hand_box)
	var end_column: VBoxContainer = VBoxContainer.new()
	end_column.custom_minimum_size.x = 155
	end_column.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(end_column)
	end_turn_button = Button.new()
	end_turn_button.text = "结束回合"
	end_turn_button.icon = load("res://assets/third_party/lucide/scroll-text.svg") as Texture2D
	end_turn_button.custom_minimum_size = Vector2(150, 50)
	end_turn_button.pressed.connect(_submit_end_turn)
	end_column.add_child(end_turn_button)
	var shortcut: Label = _label("空格键", 13, COLORS["muted"] as Color)
	shortcut.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_column.add_child(shortcut)
	return panel


func _refresh_match_ui() -> void:
	if state == null or board_view == null:
		return
	summary_label.text = String(state.call("summary"))
	_refresh_resources()
	_refresh_statuses()
	_refresh_opponents()
	_refresh_hand()
	_refresh_skills()
	_refresh_market()
	_refresh_log()
	_refresh_interactions()
	_refresh_blocking_modal()
	board_view.set_match_state(state)
	board_view.queue_redraw()
	if bool(state.get("finished")):
		action_hint_label.text = "对局已结束"
	elif _required_actor_id() != 0:
		action_hint_label.text = "%s 正在决策" % String((state.call("player", _required_actor_id()) as Dictionary).get("name", "AI"))
	elif not selected_target_commands.is_empty():
		action_hint_label.text = "在棋盘上选择目标"
	else:
		action_hint_label.text = "选择手牌、技能或移动格"


func _refresh_resources() -> void:
	_clear_children(resources_box)
	var human: Dictionary = state.call("player", 0) as Dictionary
	resources_box.add_child(_resource_chip("res://assets/third_party/lucide/heart.svg", "%d/%d" % [int(human.get("health", 0)), int(human.get("max_health", 0))], "生命"))
	resources_box.add_child(_resource_chip("res://assets/third_party/lucide/swords.svg", "%d/%d" % [int(human.get("stamina", 0)), int(human.get("max_stamina", 0))], "体力；回合外视为0"))
	resources_box.add_child(_resource_chip("res://assets/third_party/lucide/shield.svg", str(int(human.get("armor", 0))), "护甲"))
	resources_box.add_child(_resource_chip("res://assets/third_party/lucide/zap.svg", "%d/%d" % [int(human.get("mana", 0)), int(human.get("max_mana", 0))], "法力"))
	resources_box.add_child(_resource_chip("res://assets/third_party/lucide/coins.svg", str(int(human.get("coins", 0))), "金币"))


func _refresh_statuses() -> void:
	_clear_children(status_box)
	var human: Dictionary = state.call("player", 0) as Dictionary
	var statuses: Dictionary = human.get("statuses", {}) as Dictionary
	for status_id: String in statuses:
		var definition: Dictionary = catalog.call("status", status_id) as Dictionary
		status_box.add_child(_status_chip(
			_status_icon(status_id),
			"%s ×%d" % [String(definition.get("name", status_id)), int(statuses[status_id])],
			String(definition.get("description", "")),
			_status_color(status_id)
		))
	var modifiers: Dictionary = human.get("modifiers", {}) as Dictionary
	for modifier_id: String in modifiers:
		var modifier_name: String = "祈祷" if modifier_id == "free_cast" else "回声"
		var modifier_description: String = "下一张牌费用为0。" if modifier_id == "free_cast" else "下一张伤害牌额外造成1点伤害。"
		status_box.add_child(_status_chip("res://assets/third_party/lucide/sparkles.svg", modifier_name, modifier_description, COLORS["gold"] as Color))
	if status_box.get_child_count() == 0:
		var empty_label: Label = _label("无状态效果", 13, COLORS["muted"] as Color)
		status_box.add_child(empty_label)


func _refresh_opponents() -> void:
	_clear_children(opponents_box)
	for player_id: int in range(1, 4):
		var opponent: Dictionary = state.call("player", player_id) as Dictionary
		var row: Button = Button.new()
		row.custom_minimum_size.y = 52
		var status_color: Color = COLORS["muted"] as Color if bool(opponent.get("alive", false)) else COLORS["danger"] as Color
		row.text = "%s\nHP %d/%d · 护 %d · 手牌 %d" % [String(opponent.get("name", "")), int(opponent.get("health", 0)), int(opponent.get("max_health", 0)), int(opponent.get("armor", 0)), (opponent.get("hand", []) as Array).size() + (opponent.get("purchased_hand", []) as Array).size()]
		row.modulate = status_color
		row.tooltip_text = "点击查看最近5张公开出牌"
		row.pressed.connect(_show_player_history.bind(player_id))
		opponents_box.add_child(row)


func _refresh_hand() -> void:
	_clear_children(hand_box)
	var human: Dictionary = state.call("player", 0) as Dictionary
	var legal: Array[Dictionary] = state.call("legal_commands", 0) as Array[Dictionary]
	var display_hand: Array = (human.get("hand", []) as Array).duplicate()
	var purchased_count: int = (human.get("purchased_hand", []) as Array).size()
	display_hand.append_array(human.get("purchased_hand", []) as Array)
	for card_index: int in display_hand.size():
		var card_value: Variant = display_hand[card_index]
		var card_id: String = String(card_value)
		var definition: Dictionary = catalog.call("resolve_card", card_id) as Dictionary
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(260, 82)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var source_label: String = " · 商店保留" if card_index >= display_hand.size() - purchased_count else ""
		var identity_text := _card_identity_text(definition)
		var identity_suffix := " · %s" % identity_text if not identity_text.is_empty() else ""
		button.text = "%s%s%s\n%s · %s\n%s" % [String(definition.get("name", card_id)), source_label, identity_suffix, _cost_text(definition), _range_text(definition), _short_text(String(definition.get("description", "")), 28)]
		button.icon = _category_icon(String(definition.get("category", "")))
		button.tooltip_text = "%s\n%s · %s\n%s" % [String(definition.get("name", card_id)), _card_identity_text(definition), _cost_text(definition), String(definition.get("description", ""))]
		button.disabled = not _has_definition_command(legal, MatchCommandScript.PLAY_CARD, card_id)
		button.pressed.connect(_select_card.bind(card_id))
		hand_box.add_child(button)


func _card_identity_text(definition: Dictionary) -> String:
	var suit_names := {"hearts": "红桃", "diamonds": "方块", "clubs": "梅花", "spades": "黑桃", "none": "无花色"}
	var suit := String(definition.get("suit", "none"))
	var rank := int(definition.get("rank", 0))
	if suit == "none" and rank <= 0:
		return ""
	return "%s %s" % [String(suit_names.get(suit, suit)), str(rank) if rank > 0 else ""]


func _refresh_skills() -> void:
	_clear_children(skill_box)
	var human: Dictionary = state.call("player", 0) as Dictionary
	if bool(state.get("profession_choice_pending")):
		skill_box.add_child(_label("回合开始：选择职业", 16, COLORS["gold"] as Color))
		var first_choice: Button = null
		for profession_value: Variant in human.get("professions", []) as Array:
			var profession_id: String = String(profession_value)
			var choice: Button = Button.new()
			choice.text = "切换为%s" % _profession_name(profession_id)
			choice.tooltip_text = "本回合摸牌数量减少1张"
			choice.pressed.connect(_submit_profession_choice.bind(profession_id))
			skill_box.add_child(choice)
			if first_choice == null:
				first_choice = choice
		var keep: Button = Button.new()
		keep.text = "保持%s" % _profession_name(String(human.get("profession", "")))
		keep.pressed.connect(_submit_profession_choice.bind(""))
		skill_box.add_child(keep)
		if first_choice == null:
			first_choice = keep
		first_choice.grab_focus.call_deferred()
		return
	var character_definition: Dictionary = catalog.call("character", String(human.get("character_id", ""))) as Dictionary
	var legal: Array[Dictionary] = state.call("legal_commands", 0) as Array[Dictionary]
	for skill_value: Variant in character_definition.get("skills", []) as Array:
		var skill: Dictionary = skill_value as Dictionary
		var skill_id: String = String(skill.get("id", ""))
		var button: Button = Button.new()
		button.custom_minimum_size.y = 54
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.text = "%s · 无行动点限制 · 无资源消耗 · %s\n%s" % [String(skill.get("name", skill_id)), _range_text(skill), _short_text(String(skill.get("description", "")), 20)]
		button.icon = load("res://assets/third_party/lucide/sparkles.svg") as Texture2D
		button.tooltip_text = String(skill.get("description", ""))
		button.disabled = not _has_definition_command(legal, MatchCommandScript.USE_SKILL, skill_id)
		button.pressed.connect(_select_skill.bind(skill_id))
		skill_box.add_child(button)
	var staged_thunderstorm: Dictionary = state.call("_skill_definition", 0, "q_thunderstorm") as Dictionary
	if not staged_thunderstorm.is_empty() and not _has_definition_command(legal, MatchCommandScript.USE_SKILL, "q_thunderstorm"):
		staged_thunderstorm = {}
	if not staged_thunderstorm.is_empty():
		var staged_button := Button.new()
		staged_button.custom_minimum_size.y = 54
		staged_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		staged_button.text = "%s · 无行动点限制 · 弃牌点数和23 · %s\n暂存技能（provisional）" % [String(staged_thunderstorm.get("name", "雷暴")), _range_text(staged_thunderstorm)]
		staged_button.icon = load("res://assets/third_party/lucide/sparkles.svg") as Texture2D
		staged_button.tooltip_text = String(staged_thunderstorm.get("source_text", staged_thunderstorm.get("description", "")))
		staged_button.pressed.connect(_select_skill.bind("q_thunderstorm"))
		skill_box.add_child(staged_button)


func _refresh_market() -> void:
	_clear_children(market_box)
	var legal: Array[Dictionary] = state.call("legal_commands", 0) as Array[Dictionary]
	var market_cards: Array[String] = state.get("market") as Array[String]
	for market_index: int in market_cards.size():
		var card_id: String = market_cards[market_index]
		var definition: Dictionary = catalog.call("resolve_card", card_id) as Dictionary
		var button: Button = Button.new()
		button.custom_minimum_size.y = 48
		button.text = "%s%s  ·  %d金币" % [String(definition.get("name", card_id)), (" · " + _card_identity_text(definition)) if not _card_identity_text(definition).is_empty() else "", int(definition.get("price", 0))]
		button.tooltip_text = String(definition.get("description", ""))
		button.disabled = not _has_buy_command(legal, market_index)
		button.pressed.connect(_buy_market.bind(market_index))
		market_box.add_child(button)


func _refresh_log() -> void:
	if log_label == null:
		return
	log_label.text = "\n".join(log_lines.slice(maxi(0, log_lines.size() - 18)))


func _refresh_interactions() -> void:
	move_commands.clear()
	var legal_targets: Array[int] = []
	if selected_target_commands.is_empty():
		var legal: Array[Dictionary] = state.call("legal_commands", 0) as Array[Dictionary]
		for command: Dictionary in legal:
			if String(command.get("type", "")) != MatchCommandScript.MOVE:
				continue
			var path: Array = (command.get("payload", {}) as Dictionary).get("path", []) as Array
			if path.is_empty():
				continue
			var destination: Array = path.back() as Array
			move_commands["%d:%d" % [int(destination[0]), int(destination[1])]] = command
	else:
		for command: Dictionary in selected_target_commands:
			var target_id: int = int((command.get("payload", {}) as Dictionary).get("target_id", -1))
			if target_id >= 0 and not legal_targets.has(target_id):
				legal_targets.append(target_id)
	board_view.set_interactions(move_commands, legal_targets)
	if selected_target_commands.is_empty():
		board_view.set_range_preview([])
	else:
		var preview_command: Dictionary = selected_target_commands[0]
		var preview_payload: Dictionary = preview_command.get("payload", {}) as Dictionary
		var preview_type: String = String(preview_command.get("type", ""))
		var preview_id: String = String(preview_payload.get("card_id", preview_payload.get("skill_id", "")))
		var preview: Dictionary = state.call("targeting_preview", 0, preview_type, preview_id) as Dictionary
		board_view.set_range_preview(preview.get("cells", []) as Array[Vector2i])
	var end_command: Dictionary = MatchCommandScript.make(MatchCommandScript.END_TURN, 0)
	end_turn_button.disabled = not (state.call("legal_commands", 0) as Array).has(end_command)


func _select_card(card_id: String) -> void:
	_select_definition_commands(MatchCommandScript.PLAY_CARD, "card_id", card_id)


func _select_skill(skill_id: String) -> void:
	_select_definition_commands(MatchCommandScript.USE_SKILL, "skill_id", skill_id)


func _submit_profession_choice(profession_id: String) -> void:
	_submit_human_command(MatchCommandScript.make(MatchCommandScript.SWITCH_PROFESSION, 0, {"profession": profession_id}))


func _select_definition_commands(command_type: String, payload_key: String, definition_id: String) -> void:
	selected_target_commands.clear()
	for command: Dictionary in state.call("legal_commands", 0) as Array[Dictionary]:
		var payload: Dictionary = command.get("payload", {}) as Dictionary
		if String(command.get("type", "")) == command_type and String(payload.get(payload_key, "")) == definition_id:
			selected_target_commands.append(command)
	if selected_target_commands.size() == 1:
		var only_target: int = int((selected_target_commands[0].get("payload", {}) as Dictionary).get("target_id", -1))
		if only_target == 0 or only_target == -1:
			_submit_human_command(selected_target_commands[0])
			return
	_refresh_match_ui()
	if not selected_target_commands.is_empty():
		board_view.focus_selection()


func _on_board_cell_selected(position: Vector2i) -> void:
	if settings_open or state == null:
		return
	var key: String = "%d:%d" % [position.x, position.y]
	if move_commands.has(key):
		_submit_human_command(move_commands[key] as Dictionary)


func _on_board_player_selected(player_id: int) -> void:
	if settings_open:
		return
	if player_id == 0:
		return
	for command: Dictionary in selected_target_commands:
		if int((command.get("payload", {}) as Dictionary).get("target_id", -1)) == player_id:
			_submit_human_command(command)
			return
	_show_player_history(player_id)


func _buy_market(market_index: int) -> void:
	for command: Dictionary in state.call("legal_commands", 0) as Array[Dictionary]:
		if String(command.get("type", "")) == MatchCommandScript.BUY and int((command.get("payload", {}) as Dictionary).get("market_index", -1)) == market_index:
			_submit_human_command(command)
			return


func _submit_end_turn() -> void:
	_submit_human_command(MatchCommandScript.make(MatchCommandScript.END_TURN, 0))


func _submit_human_command(command: Dictionary) -> void:
	selected_target_commands.clear()
	if not bool(state.call("submit_command", command)):
		log_lines.append("[color=#e2706a]%s[/color]" % String(state.get("last_error")))
	_collect_events()
	_after_state_change()


func _after_state_change() -> void:
	if state == null:
		return
	if bool(state.get("finished")):
		SaveServiceScript.clear_replay()
	elif not SaveServiceScript.save_replay(state.call("replay_document") as Dictionary):
		log_lines.append("[color=#e2706a]无法写入对局存档；请检查存储空间或目录权限。[/color]")
	_refresh_match_ui()
	_schedule_ai()


func _collect_events() -> void:
	if state == null:
		return
	for event: Dictionary in state.call("drain_events") as Array[Dictionary]:
		if audio_feedback != null:
			audio_feedback.play_match_event(event)
		var payload: Dictionary = event.get("payload", {}) as Dictionary
		var message: String = String(payload.get("message", ""))
		if not message.is_empty():
			log_lines.append(message)


func _schedule_ai() -> void:
	if ai_running or state == null or bool(state.get("finished")) or _required_actor_id() == 0:
		return
	ai_running = true
	call_deferred("_run_ai_loop")


func _run_ai_loop() -> void:
	while state != null and not bool(state.get("finished")):
		var actor_id: int = _required_actor_id()
		if actor_id == 0 or actor_id < 0:
			break
		var delay: float = 0.05 if bool(settings.get("reduced_motion", false)) else 0.28
		await get_tree().create_timer(delay).timeout
		var command: Dictionary = ai_controller.call("choose_command", state, actor_id) as Dictionary
		if command.is_empty() or not bool(state.call("submit_command", command)):
			log_lines.append("[color=#e2706a]AI 无法提交合法命令。[/color]")
			break
		_collect_events()
		if not bool(state.get("finished")) and not SaveServiceScript.save_replay(state.call("replay_document") as Dictionary):
			log_lines.append("[color=#e2706a]无法写入对局存档；请检查存储空间或目录权限。[/color]")
		_refresh_match_ui()
	ai_running = false
	if state != null and bool(state.get("finished")):
		SaveServiceScript.clear_replay()
		_refresh_match_ui()


func _required_actor_id() -> int:
	if state == null:
		return -1
	var pending_action: Dictionary = state.get("pending_action") as Dictionary
	if not pending_action.is_empty():
		return int(pending_action.get("responder_id", -1))
	var pending_discard: Dictionary = state.get("pending_discard") as Dictionary
	if not pending_discard.is_empty():
		return int(pending_discard.get("player_id", -1))
	var pending_skill_discard: Dictionary = state.get("pending_skill_discard") as Dictionary
	if not pending_skill_discard.is_empty():
		return int(pending_skill_discard.get("player_id", -1))
	return int((state.call("current_player") as Dictionary).get("id", -1))


func _build_modal_layer() -> void:
	modal_layer = ColorRect.new()
	modal_layer.color = Color(0.0, 0.0, 0.0, 0.68)
	modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_layer.visible = false
	screen_root.add_child(modal_layer)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.add_child(center)
	var panel: PanelContainer = _panel(COLORS["surface_high"] as Color, COLORS["gold"] as Color)
	panel.custom_minimum_size = Vector2(520, 260)
	center.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	modal_title = _label("", 24, COLORS["ink"] as Color)
	modal_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(modal_title)
	modal_description = _label("", 16, COLORS["muted"] as Color)
	modal_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(modal_description)
	modal_actions = VBoxContainer.new()
	modal_actions.add_theme_constant_override("separation", 8)
	box.add_child(modal_actions)


func _refresh_blocking_modal() -> void:
	if modal_layer == null or settings_open:
		return
	_clear_children(modal_actions)
	var pending_discard: Dictionary = state.get("pending_discard") as Dictionary
	var pending_skill_discard: Dictionary = state.get("pending_skill_discard") as Dictionary
	if not pending_skill_discard.is_empty() and _required_actor_id() == 0:
		modal_layer.visible = true
		var required_sum: int = int(pending_skill_discard.get("required_rank_sum", 0))
		var minimum_count: int = int(pending_skill_discard.get("minimum_count", 1))
		modal_title.text = "技能弃牌"
		modal_description.text = "选择至少%d张牌，点数和必须为%d。当前点数和：%d" % [minimum_count, required_sum, _selected_staged_rank_sum()]
		var human_skill: Dictionary = state.call("player", 0) as Dictionary
		var skill_hand: Array = human_skill.get("hand", []) as Array
		for index: int in skill_hand.size():
			var skill_card_id := String(skill_hand[index])
			var skill_card_definition := _card_definition_for_ui(skill_card_id)
			var skill_card_button := CheckButton.new()
			skill_card_button.text = "%s · 点数 %d" % [String(skill_card_definition.get("name", skill_card_id)), int(catalog.call("staged_instance_rank", skill_card_id))]
			skill_card_button.tooltip_text = String(skill_card_definition.get("source_text", skill_card_definition.get("description", "")))
			skill_card_button.button_pressed = discard_selected_indices.has(index)
			skill_card_button.pressed.connect(_toggle_discard_selection.bind(index))
			modal_actions.add_child(skill_card_button)
		var skill_confirm := Button.new()
		skill_confirm.text = "确认发动"
		skill_confirm.disabled = _selected_staged_rank_sum() != required_sum or discard_selected_indices.size() < minimum_count
		skill_confirm.pressed.connect(_confirm_skill_discard)
		modal_actions.add_child(skill_confirm)
		return
	if not pending_discard.is_empty() and _required_actor_id() == 0:
		modal_layer.visible = true
		var required_count: int = int(pending_discard.get("required_count", 0))
		modal_title.text = "选择弃牌"
		modal_description.text = "请选择%d张牌弃置。已选 %d/%d" % [required_count, discard_selected_indices.size(), required_count]
		var human: Dictionary = state.call("player", 0) as Dictionary
		var hand: Array = human.get("hand", []) as Array
		for index: int in hand.size():
			var card_id: String = String(hand[index])
			var definition: Dictionary = catalog.call("resolve_card", card_id) as Dictionary
			var card_button: CheckButton = CheckButton.new()
			card_button.text = "%s · %s" % [String(definition.get("name", card_id)), _range_text(definition)]
			card_button.tooltip_text = String(definition.get("description", ""))
			card_button.button_pressed = discard_selected_indices.has(index)
			card_button.disabled = not card_button.button_pressed and discard_selected_indices.size() >= required_count
			card_button.pressed.connect(_toggle_discard_selection.bind(index))
			modal_actions.add_child(card_button)
		var confirm: Button = Button.new()
		confirm.text = "确认弃置 %d 张" % discard_selected_indices.size()
		confirm.disabled = discard_selected_indices.size() != required_count
		confirm.pressed.connect(_confirm_discard)
		modal_actions.add_child(confirm)
		return
	if bool(state.get("finished")):
		modal_layer.visible = true
		modal_title.text = "对局结算"
		modal_description.text = String(state.call("summary"))
		var again: Button = Button.new()
		again.text = "返回角色选择"
		again.pressed.connect(_show_character_select)
		modal_actions.add_child(again)
		return
	var pending_event: Dictionary = state.get("pending_event") as Dictionary
	if not pending_event.is_empty() and _required_actor_id() == 0:
		modal_layer.visible = true
		modal_title.text = String(pending_event.get("title", "事件"))
		modal_description.text = String(pending_event.get("description", ""))
		var choices: Array = pending_event.get("choices", []) as Array
		var legal: Array[Dictionary] = state.call("legal_commands", 0) as Array[Dictionary]
		for choice_index: int in choices.size():
			var choice: Dictionary = choices[choice_index] as Dictionary
			var button: Button = Button.new()
			button.text = String(choice.get("label", ""))
			var command: Dictionary = MatchCommandScript.make(MatchCommandScript.EVENT_CHOICE, 0, {"choice_index": choice_index})
			button.disabled = not legal.has(command)
			button.pressed.connect(_submit_human_command.bind(command))
			modal_actions.add_child(button)
		return
	var pending_action: Dictionary = state.get("pending_action") as Dictionary
	if not pending_action.is_empty() and int(pending_action.get("responder_id", -1)) == 0:
		modal_layer.visible = true
		modal_title.text = "响应机会"
		var source: Dictionary = state.call("player", int(pending_action.get("source_id", -1))) as Dictionary
		var definition: Dictionary = pending_action.get("definition", {}) as Dictionary
		modal_description.text = "%s 对你使用【%s】。你最多响应一次。" % [String(source.get("name", "")), String(definition.get("name", definition.get("id", "行动")))]
		for command: Dictionary in state.call("legal_commands", 0) as Array[Dictionary]:
			var card_id: String = String((command.get("payload", {}) as Dictionary).get("card_id", ""))
			var button: Button = Button.new()
			button.text = "不响应" if card_id.is_empty() else "使用【%s】" % String((catalog.call("resolve_card", card_id) as Dictionary).get("name", card_id))
			button.pressed.connect(_submit_human_command.bind(command))
			modal_actions.add_child(button)
		return
	modal_layer.visible = false


func _toggle_discard_selection(index: int) -> void:
	if discard_selected_indices.has(index):
		discard_selected_indices.erase(index)
	else:
		discard_selected_indices.append(index)
	_refresh_blocking_modal()


func _selected_staged_rank_sum() -> int:
	if state == null:
		return 0
	var hand: Array = (state.call("player", 0) as Dictionary).get("hand", []) as Array
	var selected: Array[String] = []
	for index: int in discard_selected_indices:
		if index >= 0 and index < hand.size():
			selected.append(String(hand[index]))
	return int(catalog.call("staged_rank_sum", selected))


func _card_definition_for_ui(card_id: String) -> Dictionary:
	var definition: Dictionary = catalog.call("resolve_card", card_id) as Dictionary
	if not definition.is_empty():
		return definition
	return {"id": card_id, "name": card_id}


func _confirm_skill_discard() -> void:
	var pending_skill_discard: Dictionary = state.get("pending_skill_discard") as Dictionary
	var hand: Array = (state.call("player", 0) as Dictionary).get("hand", []) as Array
	var card_ids: Array[String] = []
	for index: int in discard_selected_indices:
		if index >= 0 and index < hand.size():
			card_ids.append(String(hand[index]))
	var command := MatchCommandScript.make(MatchCommandScript.SKILL_DISCARD, 0, {"request_id": String(pending_skill_discard.get("request_id", "")), "card_ids": card_ids})
	discard_selected_indices.clear()
	_submit_human_command(command)


func _confirm_discard() -> void:
	var pending_discard: Dictionary = state.get("pending_discard") as Dictionary
	var hand: Array = (state.call("player", 0) as Dictionary).get("hand", []) as Array
	var card_ids: Array[String] = []
	for index: int in discard_selected_indices:
		if index >= 0 and index < hand.size():
			card_ids.append(String(hand[index]))
	var command: Dictionary = MatchCommandScript.make(MatchCommandScript.DISCARD_CARDS, 0, {
		"request_id": String(pending_discard.get("request_id", "")),
		"card_ids": card_ids
	})
	discard_selected_indices.clear()
	_submit_human_command(command)


func _show_player_history(player_id: int) -> void:
	if state == null or player_id < 0:
		return
	settings_open = true
	modal_layer.visible = true
	_clear_children(modal_actions)
	var player_state: Dictionary = state.call("player", player_id) as Dictionary
	modal_title.text = "%s 的公开出牌" % String(player_state.get("name", "未知"))
	modal_description.text = "只显示最近5张已经公开打出的牌。"
	for entry_value: Variant in player_state.get("public_card_history", []) as Array:
		var entry: Dictionary = entry_value as Dictionary
		var definition: Dictionary = catalog.call("resolve_card", String(entry.get("card_id", ""))) as Dictionary
		var line: Label = _label("第%d轮 · %s%s · %s\n%s" % [int(entry.get("round", 0)), String(definition.get("name", entry.get("card_id", ""))), (" · " + _card_identity_text(definition)) if not _card_identity_text(definition).is_empty() else "", _range_text(definition), String(definition.get("description", ""))], 14, COLORS["ink"] as Color)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		modal_actions.add_child(line)
	if modal_actions.get_child_count() == 0:
		modal_actions.add_child(_label("暂无公开出牌记录。", 14, COLORS["muted"] as Color))
	var close_button: Button = Button.new()
	close_button.text = "返回对局"
	close_button.pressed.connect(_close_debug_info)
	modal_actions.add_child(close_button)


func _range_text(definition: Dictionary) -> String:
	var target: String = String(definition.get("target", "self"))
	if target == "self":
		return "自身"
	return "距离%d" % int(definition.get("range", 0))


func _open_settings() -> void:
	if modal_layer == null:
		_build_modal_layer()
	settings_open = true
	modal_layer.visible = true
	modal_title.text = "设置"
	modal_description.text = "调整会立即生效并保存。"
	_clear_children(modal_actions)
	var volume_row: HBoxContainer = HBoxContainer.new()
	var volume_label: Label = _label("主音量", 16, COLORS["ink"] as Color)
	volume_label.custom_minimum_size.x = 110
	volume_row.add_child(volume_label)
	var volume_slider: HSlider = HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.05
	volume_slider.value = float(settings.get("master_volume", 0.8))
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.value_changed.connect(_set_master_volume)
	volume_row.add_child(volume_slider)
	modal_actions.add_child(volume_row)
	var scale_row: HBoxContainer = HBoxContainer.new()
	var scale_label: Label = _label("文字缩放", 16, COLORS["ink"] as Color)
	scale_label.custom_minimum_size.x = 110
	scale_row.add_child(scale_label)
	var scale_slider: HSlider = HSlider.new()
	scale_slider.min_value = 0.85
	scale_slider.max_value = 1.35
	scale_slider.step = 0.05
	scale_slider.value = float(settings.get("text_scale", 1.0))
	scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_slider.value_changed.connect(_set_text_scale)
	scale_row.add_child(scale_slider)
	modal_actions.add_child(scale_row)
	var reduced_motion: CheckButton = CheckButton.new()
	reduced_motion.text = "减少动态效果"
	reduced_motion.button_pressed = bool(settings.get("reduced_motion", false))
	reduced_motion.toggled.connect(_set_reduced_motion)
	modal_actions.add_child(reduced_motion)
	var tutorial_button: Button = Button.new()
	tutorial_button.text = "查看回合规则"
	tutorial_button.pressed.connect(_open_tutorial)
	modal_actions.add_child(tutorial_button)
	var close_button: Button = Button.new()
	close_button.text = "保存并返回"
	close_button.pressed.connect(_close_settings)
	modal_actions.add_child(close_button)
	volume_slider.grab_focus.call_deferred()


func _open_debug_info() -> void:
	if state == null:
		return
	settings_open = true
	modal_layer.visible = true
	modal_title.text = "对局信息"
	modal_description.text = _debug_info_text()
	modal_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_clear_children(modal_actions)
	var copy_button := Button.new()
	copy_button.text = "复制调试信息"
	copy_button.icon = load("res://assets/third_party/lucide/scroll-text.svg") as Texture2D
	copy_button.pressed.connect(_copy_debug_info.bind(copy_button))
	modal_actions.add_child(copy_button)
	var close_button := Button.new()
	close_button.text = "返回对局"
	close_button.pressed.connect(_close_debug_info)
	modal_actions.add_child(close_button)
	copy_button.grab_focus.call_deferred()


func _copy_debug_info(button: Button) -> void:
	DisplayServer.clipboard_set(_debug_info_text())
	button.text = "已复制调试信息"
	if audio_feedback != null:
		audio_feedback.play_confirmation()


func _close_debug_info() -> void:
	settings_open = false
	modal_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_refresh_match_ui()


func _debug_info_text() -> String:
	if state == null:
		return ""
	var roster: Array[String] = []
	for player_value: Variant in state.get("players") as Array:
		var player_state := player_value as Dictionary
		roster.append("%s(%s)" % [String(player_state.get("name", "")), String(player_state.get("character_id", ""))])
	var snapshot: Dictionary = state.call("deterministic_snapshot") as Dictionary
	var bounds: Rect2i = state.call("active_bounds") as Rect2i
	var pending_label := "技能弃牌" if not (snapshot.get("pending_skill_discard", {}) as Dictionary).is_empty() else ("弃牌" if not (snapshot.get("pending_discard", {}) as Dictionary).is_empty() else "无")
	return "版本 %s\n规则 v%d · 内容 v%d\n种子 %d\n阵容 %s\n棋盘 %dx%d · 崩坠 %d\n胜因 %s\n命令数 %d\n待处理 %s · provisional %d" % [
		String(ProjectSettings.get_setting("application/config/version", "未知")),
		int(rules.get("version", 0)),
		int(catalog.get("version")),
		int(state.get("seed")),
		"、".join(roster),
		bounds.size.x,
		bounds.size.y,
		int(state.get("collapse_count")),
		String(state.get("win_reason_id")) if bool(state.get("finished")) else "进行中",
		(state.get("command_log") as Array).size(),
		pending_label,
		(catalog.call("provisional_report") as Array).size()
	]


func _close_settings() -> void:
	var saved: bool = SaveServiceScript.save_settings(settings)
	settings_open = false
	if state == null:
		_show_character_select("" if saved else "设置无法保存；请检查存储空间或目录权限。")
	else:
		if not saved:
			log_lines.append("[color=#e2706a]设置无法保存；请检查存储空间或目录权限。[/color]")
		_build_match_screen()
		_refresh_match_ui()


func _set_master_volume(value: float) -> void:
	settings["master_volume"] = value
	_apply_audio_settings()


func _set_text_scale(value: float) -> void:
	settings["text_scale"] = value
	theme = _build_theme(value)


func _set_reduced_motion(enabled: bool) -> void:
	settings["reduced_motion"] = enabled


func _open_tutorial() -> void:
	if modal_layer == null:
		_build_modal_layer()
	settings_open = true
	modal_layer.visible = true
	modal_title.text = "回合规则"
	modal_description.text = "15x15 棋盘只在玩家被击败后缩至 11x11、7x7。\n回合开始恢复体力和法力，回合外资源为0；角色技能不消耗行动点或资源，是否限次只按技能文本执行。每回合有1次免费移动。\n手牌上限为当前生命值减2，最低保留1张，超出时自行选择弃牌。\n第5轮起单体伤害提高，第7轮再次提高；范围伤害不受影响。\n只剩一名角色时立即获胜；同时全灭按淘汰数、生命比例、伤害、护甲、手牌依次裁定。\n红框是可达格，金框是攻击范围和可选目标。点击对手可查看最近5张公开出牌。"
	_clear_children(modal_actions)
	var close_button: Button = Button.new()
	close_button.text = "进入对局" if state != null else "返回角色选择"
	close_button.pressed.connect(_close_tutorial)
	modal_actions.add_child(close_button)
	close_button.grab_focus.call_deferred()


func _close_tutorial() -> void:
	settings["tutorial_seen"] = true
	var saved: bool = SaveServiceScript.save_settings(settings)
	settings_open = false
	if state == null:
		_show_character_select("" if saved else "设置无法保存；请检查存储空间或目录权限。")
	else:
		if not saved:
			log_lines.append("[color=#e2706a]设置无法保存；请检查存储空间或目录权限。[/color]")
		_refresh_match_ui()


func _apply_audio_settings() -> void:
	var volume: float = float(settings.get("master_volume", 0.8))
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.001)))
	AudioServer.set_bus_mute(0, volume <= 0.001)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not (event as InputEventKey).pressed or (event as InputEventKey).echo:
		return
	var key_event: InputEventKey = event as InputEventKey
	if key_event.keycode == KEY_ESCAPE:
		if settings_open:
			_close_settings()
		else:
			_open_settings()
	elif key_event.keycode == KEY_SPACE and state != null and not settings_open:
		_submit_end_turn()


func _build_theme(scale: float) -> Theme:
	var result: Theme = Theme.new()
	result.default_font = ui_font
	result.default_font_size = int(16.0 * scale)
	result.set_color("font_color", "Label", COLORS["ink"] as Color)
	result.set_color("font_color", "Button", COLORS["ink"] as Color)
	result.set_color("font_hover_color", "Button", COLORS["ink"] as Color)
	result.set_color("font_disabled_color", "Button", Color("737b86"))
	result.set_stylebox("normal", "Button", _style_box(COLORS["surface_high"] as Color, COLORS["line"] as Color, 4, 1))
	result.set_stylebox("hover", "Button", _style_box(Color("39414e"), COLORS["primary_hover"] as Color, 4, 2))
	result.set_stylebox("pressed", "Button", _style_box(COLORS["primary"] as Color, COLORS["gold"] as Color, 4, 2))
	result.set_stylebox("focus", "Button", _style_box(Color(0, 0, 0, 0), COLORS["gold"] as Color, 4, 2))
	result.set_stylebox("disabled", "Button", _style_box(Color("1b1e24"), Color("333943"), 4, 1))
	result.set_constant("icon_max_width", "Button", int(20.0 * scale))
	result.set_color("font_color", "TooltipLabel", COLORS["ink"] as Color)
	result.set_stylebox("panel", "TooltipPanel", _style_box(COLORS["surface_high"] as Color, COLORS["line"] as Color, 4, 1))
	return result


func _style_box(background: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	return style


func _panel(background: Color, border: Color = Color("3b424d")) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style_box(background, border, 8, 1))
	return panel


func _background() -> ColorRect:
	var background: ColorRect = ColorRect.new()
	background.color = COLORS["void"] as Color
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return background


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	var scale: float = float(settings.get("text_scale", 1.0)) if not settings.is_empty() else 1.0
	label.add_theme_font_size_override("font_size", int(float(font_size) * scale))
	label.add_theme_color_override("font_color", color)
	return label


func _section_label(text_value: String) -> Label:
	return _label(text_value, 18, COLORS["ink"] as Color)


func _resource_chip(icon_path: String, value: String, tooltip: String) -> Control:
	var chip: VBoxContainer = VBoxContainer.new()
	chip.custom_minimum_size.x = 44
	chip.tooltip_text = tooltip
	var icon: TextureRect = _icon_rect(icon_path, 20)
	chip.add_child(icon)
	var label: Label = _label(value, 13, COLORS["ink"] as Color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(label)
	return chip


func _status_chip(icon_path: String, value: String, tooltip: String, color: Color) -> Control:
	var chip: HBoxContainer = HBoxContainer.new()
	chip.tooltip_text = tooltip
	chip.add_theme_constant_override("separation", 4)
	var icon: TextureRect = _icon_rect(icon_path, 15)
	icon.modulate = color
	chip.add_child(icon)
	chip.add_child(_label(value, 12, color))
	return chip


func _status_icon(status_id: String) -> String:
	return {
		"paralyze": "res://assets/third_party/lucide/zap.svg",
		"bleed": "res://assets/third_party/lucide/heart.svg",
		"poison": "res://assets/third_party/lucide/sparkles.svg",
		"confusion": "res://assets/third_party/lucide/bot.svg",
		"hidden": "res://assets/third_party/lucide/eye-off.svg",
		"scorch": "res://assets/third_party/lucide/sparkles.svg"
	}.get(status_id, "res://assets/third_party/lucide/sparkles.svg") as String


func _status_color(status_id: String) -> Color:
	return {
		"paralyze": COLORS["gold"],
		"bleed": COLORS["danger"],
		"poison": COLORS["success"],
		"confusion": Color("d897cf"),
		"hidden": COLORS["muted"],
		"scorch": Color("e78a53")
	}.get(status_id, COLORS["ink"]) as Color


func _icon_rect(path: String, side: int) -> TextureRect:
	var icon: TextureRect = TextureRect.new()
	icon.texture = load(path) as Texture2D
	icon.custom_minimum_size = Vector2(side, side)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = COLORS["ink"] as Color
	return icon


func _category_icon(category: String) -> Texture2D:
	var path: String = {
		"attack": "res://assets/third_party/lucide/swords.svg",
		"response": "res://assets/third_party/lucide/shield.svg",
		"skill": "res://assets/third_party/lucide/sparkles.svg",
		"equipment": "res://assets/third_party/lucide/shopping-bag.svg"
	}.get(category, "res://assets/third_party/lucide/scroll-text.svg") as String
	return load(path) as Texture2D


func _cost_text(definition: Dictionary) -> String:
	var cost: Dictionary = definition.get("cost", {}) as Dictionary
	return "体%d 法%d" % [int(cost.get("stamina", 0)), int(cost.get("mana", 0))]


func _short_text(value: String, maximum: int) -> String:
	return value if value.length() <= maximum else "%s…" % value.left(maximum - 1)


func _profession_name(profession: String) -> String:
	return {"vanguard": "先锋", "arcanist": "元素大师", "trickster": "诡术师", "stalker": "猎手", "shooter": "枪手", "assassin": "刺客", "berserker": "狂战士", "ambitionist": "野心家", "adventurer": "冒险家"}.get(profession, "中立") as String


func _has_definition_command(commands: Array[Dictionary], command_type: String, definition_id: String) -> bool:
	var payload_key: String = "card_id" if command_type == MatchCommandScript.PLAY_CARD else "skill_id"
	for command: Dictionary in commands:
		if String(command.get("type", "")) == command_type and String((command.get("payload", {}) as Dictionary).get(payload_key, "")) == definition_id:
			return true
	return false


func _has_buy_command(commands: Array[Dictionary], market_index: int) -> bool:
	for command: Dictionary in commands:
		if String(command.get("type", "")) == MatchCommandScript.BUY and int((command.get("payload", {}) as Dictionary).get("market_index", -1)) == market_index:
			return true
	return false


func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _clear_screen() -> void:
	if screen_root != null:
		remove_child(screen_root)
		screen_root.queue_free()
	screen_root = Control.new()
	screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen_root)
	modal_layer = null
	settings_open = false


func _clear_children(node: Node) -> void:
	for child: Node in node.get_children():
		if child is CanvasItem:
			(child as CanvasItem).visible = false
		child.queue_free()


func _show_fatal_error(message: String) -> void:
	_clear_screen()
	var background: ColorRect = _background()
	screen_root.add_child(background)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_root.add_child(center)
	var error_label: Label = _label(message, 18, COLORS["danger"] as Color)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.custom_minimum_size.x = 640
	center.add_child(error_label)
