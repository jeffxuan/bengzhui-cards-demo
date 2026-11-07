class_name BoardView3D
extends "res://scripts/ui/board_view.gd"

const FLOOR_SCENE := preload("res://assets/third_party/kaykit_dungeon/floor_tile_small.gltf.glb")
const FLOOR_DECORATED_SCENE := preload("res://assets/third_party/kaykit_dungeon/floor_tile_small_decorated.gltf.glb")
const FLOOR_BROKEN_A_SCENE := preload("res://assets/third_party/kaykit_dungeon/floor_tile_small_broken_A.gltf.glb")
const FLOOR_BROKEN_B_SCENE := preload("res://assets/third_party/kaykit_dungeon/floor_tile_small_broken_B.gltf.glb")
const CHEST_SCENE := preload("res://assets/third_party/kaykit_dungeon/chest_gold.glb")
const COIN_SCENE := preload("res://assets/third_party/kaykit_dungeon/coin_stack_small.gltf.glb")
const TRAP_SCENE := preload("res://assets/third_party/kaykit_dungeon/floor_tile_big_spikes.glb")
const COLUMN_SCENE := preload("res://assets/third_party/kaykit_dungeon/column.gltf.glb")
const CHARACTER_SCENES := {
	"q": preload("res://assets/third_party/kaykit_adventurers/Mage.glb"),
	"k": preload("res://assets/third_party/kaykit_adventurers/Knight.glb"),
	"shya": preload("res://assets/third_party/kaykit_adventurers/Rogue_Hooded.glb"),
	"ginger": preload("res://assets/third_party/kaykit_adventurers/Barbarian.glb"),
	"zc": preload("res://assets/third_party/kaykit_adventurers/Rogue.glb"),
	"na1": preload("res://assets/third_party/kaykit_adventurers/Mage.glb"),
	"maddy": preload("res://assets/third_party/kaykit_adventurers/Rogue.glb"),
	"signal": preload("res://assets/third_party/kaykit_adventurers/Knight.glb")
}

const BOARD_HALF := 7.0
const ACTOR_SCALE := 0.30
const CAMERA_POSITION := Vector3(0.0, 14.0, 18.0)

var scene_viewport: SubViewport
var world_root: Node3D
var camera: Camera3D
var tile_nodes: Dictionary = {}
var tile_overlays: Dictionary = {}
var tile_props: Dictionary = {}
var player_nodes: Dictionary = {}
var player_models: Dictionary = {}
var target_rings: Dictionary = {}
var tile_materials: Dictionary = {}
var highlight_materials: Dictionary = {}
var floor_materials: Dictionary = {}
var marker_materials: Dictionary = {}
var storm_feedback: Array[Dictionary] = []
var skeleton_feedback: Array[Dictionary] = []
var built_state: RefCounted
var camera_tween: Tween


func _ready() -> void:
	super._ready()
	_build_scene()
	_sync_state()
	resized.connect(_resize_viewport)
	_resize_viewport()
	set_process(true)


func _process(_delta: float) -> void:
	if storm_feedback.is_empty():
		return
	var now := Time.get_ticks_msec()
	storm_feedback = storm_feedback.filter(func(item: Dictionary) -> bool: return float(now - int(item.get("start", now))) < 2000.0)
	skeleton_feedback = skeleton_feedback.filter(func(item: Dictionary) -> bool: return float(now - int(item.get("start", now))) < 460.0)
	queue_redraw()


func set_match_state(match_state: RefCounted) -> void:
	super.set_match_state(match_state)
	if world_root != null:
		_sync_state()


func set_interactions(legal_moves: Dictionary, legal_targets: Array[int]) -> void:
	super.set_interactions(legal_moves, legal_targets)
	_refresh_highlights()


func set_range_preview(cells: Array[Vector2i]) -> void:
	super.set_range_preview(cells)
	_refresh_highlights()


func set_move_path(cells: Array[Vector2i]) -> void:
	super.set_move_path(cells)
	_refresh_highlights()


func set_keyboard_cell(position: Vector2i) -> void:
	super.set_keyboard_cell(position)
	_refresh_highlights()


func show_match_event(event: Dictionary) -> void:
	super.show_match_event(event)
	if world_root == null or reduced_motion:
		return
	var event_type: String = String(event.get("type", ""))
	if event_type != "damage" and event_type != "healed" and event_type != "defeated" and event_type != "skill_used":
		return
	var payload: Dictionary = event.get("payload", {}) as Dictionary
	if event_type == "skill_used":
		if String(payload.get("skill_id", "")) == "q_thunderstorm" and int(payload.get("player_id", -1)) >= 0 and player_nodes.has(int(payload.get("player_id", -1))):
			var q_id := int(payload.get("player_id", -1))
			var strike_id := int(payload.get("target_id", q_id))
			if not player_nodes.has(strike_id):
				strike_id = q_id
			_spawn_storm_cloud((player_nodes[strike_id] as Node3D).position, true)
			storm_feedback.append({"player_id": strike_id, "start": Time.get_ticks_msec()})
			_kick_camera()
			var strike_position: Vector3 = (player_nodes[strike_id] as Node3D).position
			get_tree().create_timer(0.72).timeout.connect(func() -> void:
				if is_instance_valid(self) and not reduced_motion:
					_spawn_skeleton_flash(strike_id)
					_spawn_impact(strike_position, Color("b9e8ff"), true)
					_kick_camera()
			)
			queue_redraw()
		return
	var player_id: int = int(payload.get("target_id", payload.get("player_id", -1)))
	if not player_nodes.has(player_id):
		return
	var amount: int = int(payload.get("amount", 0))
	var damage_kind := String(payload.get("kind", ""))
	var color := Color("e87a67") if amount > 0 else Color("9fcbe0")
	if event_type == "healed":
		color = Color("82c992")
	elif event_type == "defeated":
		color = Color("f2c76f")
	_spawn_impact((player_nodes[player_id] as Node3D).position, color, event_type == "defeated")
	if event_type == "damage" and amount > 0:
		_spawn_skeleton_flash(player_id)
		_play_actor_animation(player_id, "Hit_A")
		var source_id: int = int(payload.get("source_id", -1))
		if source_id >= 0 and source_id != player_id:
			_play_actor_animation(source_id, "1H_Melee_Attack_Chop")
			_animate_strike(source_id, player_id)
		_kick_camera()
	elif event_type == "defeated":
		_play_actor_animation(player_id, "Death_A")


func _gui_input(event: InputEvent) -> void:
	super._gui_input(event)
	if event is InputEventMouseMotion or event is InputEventKey:
		_refresh_highlights()


func _notification(what: int) -> void:
	super._notification(what)
	if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
		_refresh_highlights()


func _draw() -> void:
	if scene_viewport == null or state == null:
		return
	draw_texture_rect(scene_viewport.get_texture(), Rect2(Vector2.ZERO, size), false)
	_draw_player_labels()
	_draw_impact_labels()
	_draw_storm_feedback()
	_draw_skeleton_feedback()


func _draw_storm_feedback() -> void:
	var now := Time.get_ticks_msec()
	for item: Dictionary in storm_feedback:
		var age := float(now - int(item.get("start", now))) / 1000.0
		var player_id := int(item.get("player_id", -1))
		if not player_nodes.has(player_id):
			continue
		var center := _screen_position((player_nodes[player_id] as Node3D).position + Vector3(0, 1.45, 0))
		var fade := clampf(1.0 - maxf(age - 1.35, 0.0) / 0.65, 0.0, 1.0)
		var pulse := 1.0 + sin(age * 18.0) * 0.04
		# The cloud body is rendered by a spatial shader; this 2D pass is only the readable strike.
		if age < 0.62:
			var flash := clampf(1.0 - age / 0.62, 0.0, 1.0)
			var bolt_color := Color(0.82, 0.94, 1.0, flash)
			draw_line(center + Vector2(1, 18), center + Vector2(-13, 47), bolt_color, 6.0)
			draw_line(center + Vector2(-13, 47), center + Vector2(14, 82), bolt_color, 6.0)
			draw_line(center + Vector2(14, 82), center + Vector2(-5, 119), bolt_color, 6.0)
		if age > 0.68 and age < 1.02:
			var impact_alpha := 1.0 - (age - 0.68) / 0.34
			draw_circle(center + Vector2(0, 119), 24.0 + (age - 0.68) * 120.0, Color(0.70, 0.90, 1.0, impact_alpha * 0.92), false, 6.0)


func _spawn_skeleton_flash(player_id: int) -> void:
	if reduced_motion or not player_nodes.has(player_id):
		return
	var flash_data := {"player_id": player_id, "start": Time.get_ticks_msec(), "segments": [], "head": Vector2.ZERO}
	queue_redraw()
	if player_models.has(player_id):
		var model := player_models[player_id] as Node3D
		var skeleton: Skeleton3D = _find_model_skeleton(model)
		if skeleton != null:
			var cached_segments: Array[Array] = []
			var actor_center := _screen_position((player_nodes[player_id] as Node3D).position + Vector3(0, 0.58, 0))
			for bone_id: int in skeleton.get_bone_count():
				var parent_id := skeleton.get_bone_parent(bone_id)
				var bone_name := String(skeleton.get_bone_name(bone_id)).to_lower()
				var is_body_bone := bone_name in ["hips", "spine", "chest", "head", "upperarm.l", "upperarm.r", "lowerarm.l", "lowerarm.r", "upperleg.l", "upperleg.r", "lowerleg.l", "lowerleg.r", "foot.l", "foot.r"]
				if parent_id < 0 or not is_body_bone:
					continue
				var parent_name := String(skeleton.get_bone_name(parent_id)).to_lower()
				if parent_name == "root" or parent_name.contains("ik") or parent_name.contains("control") or parent_name.contains("slot"):
					continue
				var bone_position := _bone_screen_position(skeleton, bone_id)
				var parent_position := _bone_screen_position(skeleton, parent_id)
				if bone_position.distance_to(parent_position) >= 2.0 and bone_position.distance_to(actor_center) < 72.0 and parent_position.distance_to(actor_center) < 72.0:
					cached_segments.append([parent_position, bone_position])
			flash_data["segments"] = cached_segments
			var head_id := skeleton.find_bone("head")
			if head_id >= 0:
				flash_data["head"] = _bone_screen_position(skeleton, head_id)
			# The cached 2D skeleton remains visible even while the original model is hidden.
			model.visible = false
			get_tree().create_timer(0.16).timeout.connect(func() -> void:
				if is_instance_valid(model):
					model.visible = true
			)
		skeleton_feedback.append(flash_data)
	queue_redraw()


func _draw_skeleton_feedback() -> void:
	var now := Time.get_ticks_msec()
	for item: Dictionary in skeleton_feedback:
		var age := float(now - int(item.get("start", now))) / 1000.0
		var player_id := int(item.get("player_id", -1))
		if not player_nodes.has(player_id) or age > 0.46:
			continue
		# Two quick flashes sell the anime-style X-ray hit without replacing the character model.
		var pulse := 1.0 if age < 0.16 or (age > 0.20 and age < 0.30) else 0.0
		if pulse <= 0.0:
			continue
		var fade := 1.0 if age < 0.16 else clampf(1.0 - (age - 0.20) / 0.30, 0.0, 1.0)
		var center := _screen_position((player_nodes[player_id] as Node3D).position + Vector3(0, 0.58, 0))
		var glow := Color(0.72, 0.88, 1.0, 0.12 * fade)
		var bone := Color(1.0, 0.99, 0.91, 0.98 * fade)
		var cached_segments: Array = item.get("segments", []) as Array
		if not cached_segments.is_empty():
			for segment: Array in cached_segments:
				draw_line(segment[0] as Vector2, segment[1] as Vector2, glow, 5.0, true)
				draw_line(segment[0] as Vector2, segment[1] as Vector2, bone, 2.8, true)
			var head_position: Vector2 = item.get("head", Vector2.ZERO) as Vector2
			if head_position != Vector2.ZERO:
				draw_circle(head_position, 9.0, glow, false, 5.0)
				draw_circle(head_position, 6.5, bone, false, 2.8)
			continue
		# Fallback for a future character asset without a Skeleton3D.
		draw_circle(center + Vector2(0, -24), 10.0, glow, false, 7.0)
		for segment: Array in _skeleton_segments(center):
			draw_line(segment[0] as Vector2, segment[1] as Vector2, glow, 7.0, true)
		draw_circle(center + Vector2(0, -24), 7.0, bone, false, 2.4)
		for segment: Array in _skeleton_segments(center):
			draw_line(segment[0] as Vector2, segment[1] as Vector2, bone, 2.1, true)


func _find_model_skeleton(model: Node3D) -> Skeleton3D:
	if model == null:
		return null
	for node: Node in model.find_children("*", "Skeleton3D", true, false):
		return node as Skeleton3D
	return null


func _bone_screen_position(skeleton: Skeleton3D, bone_id: int) -> Vector2:
	var world_pose := skeleton.global_transform * skeleton.get_bone_global_pose(bone_id)
	return _screen_position(world_pose.origin)


func _skeleton_segments(center: Vector2) -> Array[Array]:
	return [
		[center + Vector2(0, -17), center + Vector2(0, 17)],
		[center + Vector2(-13, -10), center + Vector2(13, -10)],
		[center + Vector2(-11, -3), center + Vector2(11, -3)],
		[center + Vector2(-9, 5), center + Vector2(9, 5)],
		[center + Vector2(-9, 14), center + Vector2(9, 14)],
		[center + Vector2(-13, -9), center + Vector2(-22, 5)],
		[center + Vector2(-22, 5), center + Vector2(-25, 18)],
		[center + Vector2(13, -9), center + Vector2(22, 5)],
		[center + Vector2(22, 5), center + Vector2(25, 18)],
		[center + Vector2(-8, 16), center + Vector2(-13, 33)],
		[center + Vector2(-13, 33), center + Vector2(-18, 47)],
		[center + Vector2(8, 16), center + Vector2(13, 33)],
		[center + Vector2(13, 33), center + Vector2(18, 47)]
	]


func _cell_at(local_position: Vector2) -> Vector2i:
	if camera == null or scene_viewport == null or state == null or size.x <= 0.0 or size.y <= 0.0:
		return Vector2i(-1, -1)
	var viewport_position := local_position * Vector2(scene_viewport.size) / size
	for player_value: Variant in state.get("players") as Array:
		var player_state: Dictionary = player_value as Dictionary
		if not bool(player_state.get("alive", false)):
			continue
		var player_cell: Vector2i = player_state.get("position", Vector2i.ZERO) as Vector2i
		var player_screen: Vector2 = camera.unproject_position(_world_position(player_cell) + Vector3(0, 0.55, 0))
		if viewport_position.distance_to(player_screen) < 18.0:
			return player_cell
	var ray_origin: Vector3 = camera.project_ray_origin(viewport_position)
	var ray_direction: Vector3 = camera.project_ray_normal(viewport_position)
	if absf(ray_direction.y) < 0.001:
		return Vector2i(-1, -1)
	var distance: float = -ray_origin.y / ray_direction.y
	if distance < 0.0:
		return Vector2i(-1, -1)
	var hit: Vector3 = ray_origin + ray_direction * distance
	var cell := Vector2i(floori(hit.x + BOARD_HALF + 0.5), floori(hit.z + BOARD_HALF + 0.5))
	var grid_size: int = int(state.get("board_size"))
	if cell.x < 0 or cell.y < 0 or cell.x >= grid_size or cell.y >= grid_size:
		return Vector2i(-1, -1)
	return cell


func _build_scene() -> void:
	scene_viewport = SubViewport.new()
	scene_viewport.size = Vector2i(640, 480)
	scene_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	scene_viewport.msaa_3d = Viewport.MSAA_2X
	scene_viewport.world_3d = World3D.new()
	add_child(scene_viewport)
	world_root = Node3D.new()
	scene_viewport.add_child(world_root)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("10151b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b8c1cc")
	environment.ambient_light_energy = 0.65
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world_root.add_child(world_environment)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 11.8
	world_root.add_child(camera)
	camera.position = CAMERA_POSITION
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var key_light := DirectionalLight3D.new()
	world_root.add_child(key_light)
	key_light.position = Vector3(-8, 16, 7)
	key_light.look_at(Vector3.ZERO)
	key_light.light_color = Color("ffe9cb")
	key_light.light_energy = 1.35
	key_light.shadow_enabled = true
	var fill_light := OmniLight3D.new()
	fill_light.position = Vector3(7, 8, -5)
	fill_light.light_color = Color("94bfd0")
	fill_light.light_energy = 0.55
	fill_light.omni_range = 24.0
	world_root.add_child(fill_light)
	_build_materials()
	_build_table()


func _build_materials() -> void:
	for kind: String in ["normal", "wealth", "event", "trap", "collapsed"]:
		var color: Color = {
			"normal": Color("363c43"), "wealth": Color("6a5833"),
			"event": Color("574261"), "trap": Color("613737"),
			"collapsed": Color("13171c")
		}[kind]
		tile_materials[kind] = _material(color)
	for kind: String in ["wealth", "event", "trap"]:
		var marker_color: Color = {
			"wealth": Color(0.97, 0.68, 0.17, 0.28),
			"event": Color(0.75, 0.35, 0.68, 0.30),
			"trap": Color(0.93, 0.25, 0.22, 0.33)
		}[kind]
		marker_materials[kind] = _material(marker_color, true)
	for kind: String in ["range", "move", "path", "cursor", "hover"]:
		var color: Color = {
			"range": Color(0.90, 0.72, 0.31, 0.33),
			"move": Color(0.80, 0.24, 0.44, 0.42),
			"path": Color(0.38, 0.75, 0.54, 0.50),
			"cursor": Color(1.0, 0.85, 0.45, 0.62),
			"hover": Color(0.80, 0.88, 0.96, 0.28)
		}[kind]
		var material := _material(color, true)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		highlight_materials[kind] = material


func _build_table() -> void:
	var table := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(16.0, 0.42, 16.0)
	table.mesh = slab
	table.position.y = -0.30
	table.material_override = _material(Color("1e252c"))
	world_root.add_child(table)
	var floor_body := StaticBody3D.new()
	floor_body.position.y = -0.07
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(15.2, 0.20, 15.2)
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	world_root.add_child(floor_body)
	for edge: int in 4:
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(16.1, 0.22, 0.22) if edge < 2 else Vector3(0.22, 0.22, 16.1)
		rail.mesh = rail_mesh
		rail.position = [Vector3(0, 0.02, -7.90), Vector3(0, 0.02, 7.90), Vector3(-7.90, 0.02, 0), Vector3(7.90, 0.02, 0)][edge]
		rail.material_override = _material(Color("73634a"), false, 0.35)
		world_root.add_child(rail)
	for x: int in [-8, 8]:
		for z: int in [-8, 8]:
			var corner: Node3D = COLUMN_SCENE.instantiate() as Node3D
			corner.position = Vector3(float(x), -0.07, float(z))
			corner.scale = Vector3.ONE * 0.92
			_tint_floor(corner)
			world_root.add_child(corner)
	for y: int in 15:
		for x: int in 15:
			_build_tile(Vector2i(x, y))


func _build_tile(cell: Vector2i) -> void:
	var key: String = _cell_key(cell)
	var holder := Node3D.new()
	holder.position = _world_position(cell)
	world_root.add_child(holder)
	var base := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.98, 0.14, 0.98)
	base.mesh = box
	base.position.y = -0.08
	base.material_override = tile_materials["normal"] as Material
	holder.add_child(base)
	var floor_scene: PackedScene = FLOOR_SCENE
	var variation: int = (cell.x * 13 + cell.y * 29) % 19
	if variation == 0:
		floor_scene = FLOOR_DECORATED_SCENE
	elif variation == 3:
		floor_scene = FLOOR_BROKEN_A_SCENE
	elif variation == 7:
		floor_scene = FLOOR_BROKEN_B_SCENE
	var floor: Node3D = floor_scene.instantiate() as Node3D
	floor.scale = Vector3(0.495, 0.50, 0.495)
	floor.position.y = 0.005
	_tint_floor(floor)
	holder.add_child(floor)
	var marker := MeshInstance3D.new()
	var marker_plane := PlaneMesh.new()
	marker_plane.size = Vector2(0.86, 0.86)
	marker.mesh = marker_plane
	marker.position.y = 0.048
	marker.visible = false
	holder.add_child(marker)
	var overlay := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.94, 0.94)
	overlay.mesh = plane
	overlay.position.y = 0.052
	overlay.visible = false
	holder.add_child(overlay)
	tile_nodes[key] = {"holder": holder, "base": base, "floor": floor, "marker": marker, "kind": ""}
	tile_overlays[key] = overlay


func _sync_state() -> void:
	if state == null or world_root == null:
		return
	if built_state != state:
		for player_node: Variant in player_nodes.values():
			(player_node as Node3D).queue_free()
		player_nodes.clear()
		player_models.clear()
		target_rings.clear()
		built_state = state
	for player_value: Variant in state.get("players") as Array:
		var player_state: Dictionary = player_value as Dictionary
		var player_id: int = int(player_state.get("id", -1))
		if not player_nodes.has(player_id):
			_build_player(player_state)
		var actor: Node3D = player_nodes[player_id] as Node3D
		actor.visible = bool(player_state.get("alive", false))
		var destination: Vector3 = _world_position(player_state.get("position", Vector2i.ZERO) as Vector2i)
		if actor.position != destination:
			if actor.has_meta("position_tween"):
				(actor.get_meta("position_tween") as Tween).kill()
			if reduced_motion or actor.position == Vector3.ZERO and not actor.has_meta("placed"):
				actor.position = destination
			else:
				var movement_tween := create_tween()
				movement_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
				movement_tween.tween_property(actor, "position", destination, 0.22)
				actor.set_meta("position_tween", movement_tween)
		actor.set_meta("placed", true)
	var occupied: Array[Vector2i] = []
	for player_value: Variant in state.get("players") as Array:
		var player_state: Dictionary = player_value as Dictionary
		if bool(player_state.get("alive", false)):
			occupied.append(player_state.get("position", Vector2i.ZERO) as Vector2i)
	for y: int in 15:
		for x: int in 15:
			var cell := Vector2i(x, y)
			var key: String = _cell_key(cell)
			var kind: String = String(state.call("tile_kind", cell))
			var tile: Dictionary = tile_nodes[key] as Dictionary
			if String(tile.get("kind", "")) != kind:
				(tile["base"] as MeshInstance3D).material_override = tile_materials[kind] as Material
				(tile["floor"] as Node3D).visible = kind != "collapsed"
				(tile["base"] as MeshInstance3D).visible = kind != "collapsed"
				(tile["marker"] as MeshInstance3D).visible = marker_materials.has(kind)
				if marker_materials.has(kind):
					(tile["marker"] as MeshInstance3D).material_override = marker_materials[kind] as Material
				_update_prop(key, kind, tile["holder"] as Node3D)
				tile["kind"] = kind
				tile_nodes[key] = tile
			if tile_props.has(key):
				(tile_props[key] as Node3D).visible = not occupied.has(cell)
	_refresh_highlights()
	queue_redraw()


func _update_prop(key: String, kind: String, holder: Node3D) -> void:
	if tile_props.has(key):
		(tile_props[key] as Node3D).queue_free()
		tile_props.erase(key)
	var scene: PackedScene = null
	match kind:
		"wealth": scene = COIN_SCENE
		"event": scene = CHEST_SCENE
		"trap": scene = TRAP_SCENE
	if scene == null:
		return
	var prop: Node3D = scene.instantiate() as Node3D
	prop.position.y = 0.045
	prop.scale = Vector3.ONE * {"wealth": 0.64, "event": 0.37, "trap": 0.22}[kind]
	if kind == "trap":
		_tint_floor(prop)
	holder.add_child(prop)
	tile_props[key] = prop


func _build_player(player_state: Dictionary) -> void:
	var player_id: int = int(player_state.get("id", -1))
	var actor := Node3D.new()
	actor.name = "Player%d" % player_id
	world_root.add_child(actor)
	var pedestal := MeshInstance3D.new()
	var pedestal_mesh := CylinderMesh.new()
	pedestal_mesh.top_radius = 0.41
	pedestal_mesh.bottom_radius = 0.44
	pedestal_mesh.height = 0.12
	pedestal.mesh = pedestal_mesh
	pedestal.position.y = 0.08
	pedestal.material_override = _material(PLAYER_COLORS[player_id % PLAYER_COLORS.size()], false, 0.25)
	actor.add_child(pedestal)
	var character_id: String = String(player_state.get("character_id", "q"))
	var model_scene: PackedScene = CHARACTER_SCENES.get(character_id, CHARACTER_SCENES["q"]) as PackedScene
	var model: Node3D = model_scene.instantiate() as Node3D
	model.scale = Vector3.ONE * ACTOR_SCALE
	model.position.y = 0.14
	actor.add_child(model)
	var target_ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.46
	ring_mesh.outer_radius = 0.52
	target_ring.mesh = ring_mesh
	target_ring.position.y = 0.15
	target_ring.material_override = _material(Color("f2cd73"), true)
	target_ring.visible = false
	actor.add_child(target_ring)
	player_nodes[player_id] = actor
	player_models[player_id] = model
	target_rings[player_id] = target_ring
	_play_actor_animation(player_id, "Idle")


func _refresh_highlights() -> void:
	if state == null or tile_overlays.is_empty():
		return
	for y: int in 15:
		for x: int in 15:
			var cell := Vector2i(x, y)
			var key: String = _cell_key(cell)
			var overlay: MeshInstance3D = tile_overlays[key] as MeshInstance3D
			var kind: String = String((tile_nodes[key] as Dictionary).get("kind", ""))
			overlay.visible = kind != "collapsed" and (move_commands.has(key) or move_path_cells.has(cell) or range_cells.has(cell) or hovered_cell == cell or has_focus() and keyboard_cell == cell)
			if not overlay.visible:
				continue
			var highlight := "range"
			if move_commands.has(key): highlight = "move"
			if move_path_cells.has(cell): highlight = "path"
			if hovered_cell == cell: highlight = "hover"
			if has_focus() and keyboard_cell == cell: highlight = "cursor"
			overlay.material_override = highlight_materials[highlight] as Material
	for player_id: int in target_rings:
		(target_rings[player_id] as MeshInstance3D).visible = target_ids.has(player_id)
	queue_redraw()


func _draw_player_labels() -> void:
	var placed_labels: Array[Rect2] = []
	for player_value: Variant in state.get("players") as Array:
		var player_state: Dictionary = player_value as Dictionary
		if not bool(player_state.get("alive", false)):
			continue
		var player_id: int = int(player_state.get("id", -1))
		if not player_nodes.has(player_id):
			continue
		var anchor: Vector2 = _screen_position((player_nodes[player_id] as Node3D).position + Vector3(0, 1.04, 0))
		var name: String = String(player_state.get("name", "?"))
		var health: int = int(player_state.get("health", 0))
		var label: String = "%s  %d" % [name, health]
		var font_size := 15
		var width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 12.0
		var actor_position: Vector3 = (player_nodes[player_id] as Node3D).position
		var foot: Vector2 = _screen_position(actor_position)
		var candidates: Array[Rect2] = [
			Rect2(anchor - Vector2(width * 0.5, 23.0), Vector2(width, 22.0)),
			Rect2(foot + Vector2(-width * 0.5, 5.0), Vector2(width, 22.0)),
			Rect2(anchor - Vector2(width + 10.0, 23.0), Vector2(width, 22.0)),
			Rect2(anchor + Vector2(10.0, -23.0), Vector2(width, 22.0))
		]
		var rect: Rect2 = candidates[0]
		for candidate: Rect2 in candidates:
			if candidate.position.x < 0.0 or candidate.position.y < 0.0 or candidate.end.x > size.x or candidate.end.y > size.y:
				continue
			var intersects := false
			for placed: Rect2 in placed_labels:
				if candidate.grow(3.0).intersects(placed):
					intersects = true
					break
			if not intersects:
				rect = candidate
				break
		placed_labels.append(rect)
		draw_rect(rect, Color(0.055, 0.07, 0.09, 0.88), true)
		draw_rect(rect, PLAYER_COLORS[player_id % PLAYER_COLORS.size()], false, 1.5)
		draw_string(font, rect.position + Vector2(6, 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("f5f2e9"))


func _draw_impact_labels() -> void:
	var now: int = Time.get_ticks_msec()
	for effect: Dictionary in feedback:
		var age: float = float(now - int(effect.get("start", now))) / 1000.0
		var cell: Vector2i = effect.get("position", Vector2i.ZERO) as Vector2i
		var anchor: Vector2 = _screen_position(_world_position(cell) + Vector3(0, 1.42, 0))
		var amount: int = int(effect.get("amount", 0))
		var event_type: String = String(effect.get("type", ""))
		var label := "−%d" % amount if amount > 0 else "抵消"
		var color := Color("fa8a74") if amount > 0 else Color("a8d5ea")
		if event_type == "healed":
			label = "+%d" % amount
			color = Color("9bd9a8")
		elif event_type == "defeated":
			label = "击败"
			color = Color("f2c76f")
		if not reduced_motion and age < 0.24:
			var center: Vector2 = _screen_position(_world_position(cell) + Vector3(0, 0.30, 0))
			var flash_alpha: float = 0.85 * (1.0 - age / 0.24)
			draw_arc(center, 12.0 + age * 100.0, 0.0, TAU, 32, Color(color.r, color.g, color.b, flash_alpha), 3.0)
			if amount > 0 and not bool(effect.get("area", false)) and effect.has("source_position") and age < 0.17:
				var source_cell: Vector2i = effect.get("source_position", Vector2i.ZERO) as Vector2i
				var source: Vector2 = _screen_position(_world_position(source_cell) + Vector3(0, 0.30, 0))
				draw_line(source, center, Color(color.r, color.g, color.b, flash_alpha * 0.27), 7.0)
				draw_line(source, center, Color(1.0, 0.92, 0.75, flash_alpha), 2.0)
		var fade: float = 1.0 if age < 0.38 else clampf(1.0 - (age - 0.38) / 0.27, 0.0, 1.0)
		var font_size := 22
		label = LocalizationScript.text(label)
		var width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 16.0
		var float_offset: float = 0.0 if reduced_motion else minf(age * 22.0, 13.0)
		var rect := Rect2(anchor - Vector2(width * 0.5, 28.0 + float_offset), Vector2(width, 27.0))
		draw_rect(rect, Color(0.04, 0.05, 0.07, fade * 0.94), true)
		draw_string(font, rect.position + Vector2(8, 21), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(color.r, color.g, color.b, fade))


func _spawn_impact(position: Vector3, color: Color, large: bool) -> void:
	var center := position + Vector3(0, 0.60, 0)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.40
	ring_mesh.outer_radius = 0.48
	ring.mesh = ring_mesh
	ring.material_override = _material(Color(color.r, color.g, color.b, 0.88), true)
	ring.position = position + Vector3(0, 0.12, 0)
	ring.scale = Vector3.ONE * 0.55
	world_root.add_child(ring)
	var ring_tween := create_tween()
	ring_tween.set_parallel(true)
	ring_tween.tween_property(ring, "scale", Vector3.ONE * (2.0 if large else 1.45), 0.22).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	ring_tween.tween_property(ring, "transparency", 1.0, 0.22)
	ring_tween.finished.connect(ring.queue_free)
	for index: int in (12 if large else 8):
		var shard := RigidBody3D.new()
		shard.mass = 0.04
		shard.linear_damp = 1.6
		shard.angular_damp = 2.0
		shard.continuous_cd = true
		var shard_mesh := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.08, 0.08, 0.08) if not large else Vector3(0.12, 0.12, 0.12)
		shard_mesh.mesh = mesh
		shard_mesh.material_override = _material(color, true)
		shard.add_child(shard_mesh)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = mesh.size
		collision.shape = shape
		shard.add_child(collision)
		shard.position = center
		world_root.add_child(shard)
		var angle: float = float(index) * TAU / float(12 if large else 8)
		shard.linear_velocity = Vector3(cos(angle) * 2.8, 2.2 + float(index % 3) * 0.5, sin(angle) * 2.8)
		shard.angular_velocity = Vector3(2.0, 4.0, 3.0)
		var fade := create_tween()
		fade.tween_property(shard_mesh, "transparency", 1.0, 0.16).set_delay(0.28)
		fade.finished.connect(shard.queue_free)


func _storm_material(color: Color, transparency: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 1.0 - transparency)
	material.emission_enabled = true
	material.emission = Color(color.r * 0.22, color.g * 0.24, color.b * 0.30)
	material.emission_energy_multiplier = 0.8
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = false
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _spawn_storm_cloud(position: Vector3, q_skill: bool = false) -> void:
	if reduced_motion:
		return
	var cloud_root := Node3D.new()
	cloud_root.name = "StormCloud"
	cloud_root.position = position + Vector3(0, 2.18 if q_skill else 1.75, 0)
	world_root.add_child(cloud_root)
	var cloud_quad := QuadMesh.new()
	cloud_quad.size = Vector2(2.70, 1.62)
	var cloud_shader := load("res://shaders/storm_cloud.gdshader") as Shader
	var cloud_shader_material := ShaderMaterial.new()
	cloud_shader_material.shader = cloud_shader
	cloud_shader_material.set_shader_parameter("intensity", 1.08)
	cloud_shader_material.set_shader_parameter("flash", 0.0)
	var cloud_surface := MeshInstance3D.new()
	cloud_surface.mesh = cloud_quad
	cloud_surface.material_override = cloud_shader_material
	cloud_surface.position = Vector3(0.0, 0.08, 0.0)
	# QuadMesh faces the camera; keep it vertical so the silhouette reads from the elevated board view.
	cloud_surface.rotation_degrees = Vector3.ZERO
	cloud_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cloud_root.add_child(cloud_surface)
	for sprite_data: Array in [
		["res://assets/third_party/kenney_particle_pack/PNG (Transparent)/smoke_01.png", Vector3(-0.22, 0.08, 0.08), Color(0.22, 0.28, 0.38, 0.72), 0.0028],
		["res://assets/third_party/kenney_particle_pack/PNG (Transparent)/smoke_04.png", Vector3(0.24, 0.12, -0.02), Color(0.30, 0.36, 0.48, 0.55), 0.0024],
		["res://assets/third_party/kenney_particle_pack/PNG (Transparent)/light_01.png", Vector3(0.0, -0.34, 0.02), Color(0.68, 0.88, 1.0, 0.0), 0.0018]
	]:
		var sprite := Sprite3D.new()
		sprite.texture = load(String(sprite_data[0])) as Texture2D
		sprite.position = sprite_data[1] as Vector3
		sprite.modulate = sprite_data[2] as Color
		sprite.pixel_size = float(sprite_data[3])
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.no_depth_test = true
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		cloud_root.add_child(sprite)
	var cloud_light_sprite := cloud_root.get_child(cloud_root.get_child_count() - 1) as Sprite3D
	var light_pulse := create_tween()
	light_pulse.tween_method(func(value: float) -> void:
		if is_instance_valid(cloud_shader_material):
			cloud_shader_material.set_shader_parameter("flash", value)
	, 0.0, 1.0, 0.07)
	light_pulse.tween_method(func(value: float) -> void:
		if is_instance_valid(cloud_shader_material):
			cloud_shader_material.set_shader_parameter("flash", value)
	, 1.0, 0.0, 0.18)
	light_pulse.tween_property(cloud_light_sprite, "modulate:a", 0.95, 0.08).set_delay(0.24)
	light_pulse.tween_property(cloud_light_sprite, "modulate:a", 0.08, 0.16)
	light_pulse.tween_property(cloud_light_sprite, "modulate:a", 0.9, 0.06).set_delay(0.14)
	light_pulse.tween_property(cloud_light_sprite, "modulate:a", 0.0, 0.26)
	var flash := OmniLight3D.new()
	flash.light_color = Color("d9efff")
	flash.light_energy = 0.0
	flash.omni_range = 4.2
	flash.position = Vector3(0, -0.10, 0)
	cloud_root.add_child(flash)
	var bolt := ImmediateMesh.new()
	var bolt_material := _storm_material(Color("f4fbff"))
	bolt_material.no_depth_test = true
	bolt_material.emission = Color("d7f3ff")
	bolt_material.emission_energy_multiplier = 2.8
	bolt.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, bolt_material)
	bolt.surface_set_color(Color("e9f7ff"))
	bolt.surface_add_vertex(Vector3(-0.08, -0.18, 0.0))
	bolt.surface_add_vertex(Vector3(0.10, -0.58, 0.01))
	bolt.surface_add_vertex(Vector3(-0.02, -1.04, 0.0))
	bolt.surface_add_vertex(Vector3(0.18, -1.52, 0.02))
	bolt.surface_end()
	var bolt_mesh := MeshInstance3D.new()
	bolt_mesh.mesh = bolt
	bolt_mesh.visible = false
	bolt_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cloud_root.add_child(bolt_mesh)
	var pulse := create_tween()
	pulse.tween_property(flash, "light_energy", 5.5, 0.035)
	pulse.tween_property(bolt_mesh, "visible", true, 0.0)
	pulse.tween_interval(0.055)
	pulse.tween_property(flash, "light_energy", 0.0, 0.16)
	pulse.tween_property(bolt_mesh, "visible", false, 0.0)
	pulse.tween_interval(0.07)
	pulse.tween_property(flash, "light_energy", 2.2, 0.025)
	pulse.tween_property(bolt_mesh, "visible", true, 0.0)
	pulse.tween_interval(0.045)
	pulse.tween_property(flash, "light_energy", 0.0, 0.18)
	pulse.tween_property(bolt_mesh, "visible", false, 0.0)
	var drift := create_tween().set_loops(2)
	drift.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	drift.tween_property(cloud_root, "position", cloud_root.position + Vector3(0.12, 0.05, 0), 0.32)
	drift.tween_property(cloud_root, "position", cloud_root.position + Vector3(-0.10, -0.02, 0), 0.32)
	var fade := create_tween()
	fade.tween_interval(1.18 if q_skill else 0.48)
	fade.tween_property(cloud_root, "scale", Vector3.ONE * (1.38 if q_skill else 1.18), 0.26)
	fade.finished.connect(cloud_root.queue_free)


func _kick_camera() -> void:
	if camera_tween != null and camera_tween.is_running():
		camera_tween.kill()
	camera.position = CAMERA_POSITION + Vector3(0.12, 0.04, 0)
	camera_tween = create_tween()
	camera_tween.tween_property(camera, "position", CAMERA_POSITION, 0.17).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


func _animate_strike(source_id: int, target_id: int) -> void:
	if not player_nodes.has(source_id) or not player_nodes.has(target_id):
		return
	var source_actor: Node3D = player_nodes[source_id] as Node3D
	var target_actor: Node3D = player_nodes[target_id] as Node3D
	var direction: Vector3 = target_actor.position - source_actor.position
	if direction.length_squared() < 0.001:
		return
	direction = direction.normalized()
	for strike: Dictionary in [
		{"id": source_id, "offset": direction * 0.25},
		{"id": target_id, "offset": direction * 0.14}
	]:
		var model: Node3D = player_models[int(strike["id"])] as Node3D
		if model.has_meta("strike_tween"):
			(model.get_meta("strike_tween") as Tween).kill()
		model.position = Vector3(0, 0.14, 0)
		var tween := create_tween()
		tween.tween_property(model, "position", Vector3(0, 0.14, 0) + strike["offset"] as Vector3, 0.07).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tween.tween_property(model, "position", Vector3(0, 0.14, 0), 0.15).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		model.set_meta("strike_tween", tween)


func _play_actor_animation(player_id: int, animation_name: String) -> void:
	if not player_models.has(player_id):
		return
	var model: Node3D = player_models[player_id] as Node3D
	for animation_node: Node in model.find_children("*", "AnimationPlayer", true, false):
		var animation_player: AnimationPlayer = animation_node as AnimationPlayer
		if animation_player.has_animation(animation_name):
			animation_player.play(animation_name)
			if animation_name != "Idle":
				get_tree().create_timer(0.38).timeout.connect(func() -> void:
					if is_instance_valid(animation_player):
						animation_player.play("Idle")
				)
			return


func _resize_viewport() -> void:
	if scene_viewport == null:
		return
	scene_viewport.size = Vector2i(maxi(1, int(size.x)), maxi(1, int(size.y)))
	queue_redraw()


func _screen_position(world_position: Vector3) -> Vector2:
	return camera.unproject_position(world_position) * size / Vector2(scene_viewport.size)


func _world_position(cell: Vector2i) -> Vector3:
	return Vector3(float(cell.x) - BOARD_HALF, 0.0, float(cell.y) - BOARD_HALF)


func _cell_key(cell: Vector2i) -> String:
	return "%d:%d" % [cell.x, cell.y]


func _material(color: Color, unshaded: bool = false, metalness: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	material.metallic = metalness
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _tint_floor(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		for surface: int in mesh_node.get_surface_override_material_count():
			var original: Material = mesh_node.get_active_material(surface)
			if not original is StandardMaterial3D:
				continue
			var original_id: int = original.get_instance_id()
			if not floor_materials.has(original_id):
				var tinted: StandardMaterial3D = original.duplicate() as StandardMaterial3D
				tinted.albedo_color *= Color(0.34, 0.44, 0.43)
				floor_materials[original_id] = tinted
			mesh_node.set_surface_override_material(surface, floor_materials[original_id] as Material)
	for child: Node in node.get_children():
		_tint_floor(child)
