extends SceneTree

const ASSETS := [
	"res://assets/third_party/kaykit_adventurers/Barbarian.glb",
	"res://assets/third_party/kaykit_adventurers/Knight.glb",
	"res://assets/third_party/kaykit_adventurers/Mage.glb",
	"res://assets/third_party/kaykit_adventurers/Rogue.glb",
	"res://assets/third_party/kenney_mini_dungeon/floor.glb",
	"res://assets/third_party/kenney_mini_dungeon/chest.glb",
	"res://assets/third_party/kenney_mini_dungeon/trap.glb",
	"res://assets/third_party/kaykit_dungeon/floor_tile_small.gltf.glb",
	"res://assets/third_party/kaykit_dungeon/floor_tile_small_decorated.gltf.glb",
	"res://assets/third_party/kaykit_dungeon/floor_tile_big_spikes.glb",
	"res://assets/third_party/kaykit_dungeon/chest_gold.glb",
	"res://assets/third_party/kaykit_dungeon/coin_stack_small.gltf.glb",
	"res://assets/third_party/kaykit_dungeon/column.gltf.glb"
]


func _init() -> void:
	call_deferred("_inspect")


func _inspect() -> void:
	for path: String in ASSETS:
		var scene: PackedScene = load(path) as PackedScene
		if scene == null:
			push_error("Cannot load %s" % path)
			quit(1)
			return
		var model: Node3D = scene.instantiate() as Node3D
		root.add_child(model)
		var meshes: Array[MeshInstance3D] = []
		_find_meshes(model, meshes)
		var bounds := AABB()
		var has_bounds := false
		for mesh_node: MeshInstance3D in meshes:
			var local_bounds: AABB = model.global_transform.affine_inverse() * mesh_node.global_transform * mesh_node.get_aabb()
			if has_bounds:
				bounds = bounds.merge(local_bounds)
			else:
				bounds = local_bounds
				has_bounds = true
		print("ASSET_3D: %s meshes=%d bounds=%s" % [path.get_file(), meshes.size(), str(bounds)])
		for animation_node: Node in model.find_children("*", "AnimationPlayer", true, false):
			var player: AnimationPlayer = animation_node as AnimationPlayer
			var animation_names: PackedStringArray = player.get_animation_list()
			print("ASSET_ANIMATIONS: %s count=%d sample=%s" % [path.get_file(), animation_names.size(), str(animation_names.slice(0, mini(8, animation_names.size())))])
		model.queue_free()
	print("ASSET_3D_OK")
	quit(0)


func _find_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_find_meshes(child, result)
