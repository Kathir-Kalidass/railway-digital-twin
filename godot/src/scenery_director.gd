class_name SceneryDirector
extends Node3D

## Populates the full-scale world from the LTS Blender library: station
## platforms, buildings, catenary poles, benches and a dense tree line.

@export var track_path: NodePath = NodePath("../Track")
@export var terrain_path: NodePath = NodePath("../WorldWildlife/TerrainGenerator")
@export var registry_path: NodePath = NodePath("../TrackRegistry")
@export var inner_track_path: NodePath = NodePath("../InnerTrack")
@export var seed := 17
@export var tree_count := 280
@export var station_distance := 322.0
@export var station_module_spacing := 9.6
@export var station_modules := 5
@export var crossover_a_up_distance := 312.0
@export var crossover_b_up_distance := 434.0
@export var use_lts_models := true

const PLATFORM_LENGTH_M := 9.6
const PLATFORM_WIDTH_M := 2.2
const PLATFORM_TOP_M := 0.55
const PLATFORM_BOTTOM_M := -1.25

const LTS := "res://assets/models/lts/"
const TREES := [
	"res://assets/models/trees/oak.glb",
	"res://assets/models/trees/pine.glb",
	"res://assets/models/trees/birch.glb",
]

var _track: LTSTrack
var _terrain: TerrainGenerator
var _rng := RandomNumberGenerator.new()
var _tree_roots: Array[Node3D] = []


func _ready() -> void:
	_rng.seed = seed
	_track = get_node_or_null(track_path) as LTSTrack
	_terrain = get_node_or_null(terrain_path) as TerrainGenerator
	if not use_lts_models or not is_instance_valid(_track):
		return
	_build_station()
	_build_poles()
	_build_wires()
	_build_details()
	_scatter_trees()


func _inner_track() -> LTSTrack:
	var registry := get_node_or_null(registry_path) as TrackRegistry
	if registry != null:
		var down := registry.track("DOWN")
		if down != null:
			return down
	return get_node_or_null(inner_track_path) as LTSTrack


func _pose_pair(up_distance: float) -> Dictionary:
	var up_pose := _pose(up_distance)
	var down := _inner_track()
	if down == null:
		return {"up": up_pose, "down": null, "mid": up_pose}
	var down_pose := down.get_global_transform_at_distance(clampf(up_distance * down.length / _track.length, 0.0, down.length))
	var mid := up_pose
	mid.origin = (up_pose.origin + down_pose.origin) * 0.5
	return {"up": up_pose, "down": down_pose, "mid": mid}


func _place_platform_module(mid: Transform3D) -> Node3D:
	var platform := _spawn("platform", mid)
	if platform == null:
		return null
	var railing := platform.get_node_or_null("Cylinder_001")
	if railing:
		platform.remove_child(railing)
		railing.queue_free()
	var box := _local_mesh_aabb(platform)
	if box.size.x < 0.01 or box.size.y < 0.01 or box.size.z < 0.01:
		return platform
	var module_scale := Vector3(
		PLATFORM_LENGTH_M / box.size.x,
		(PLATFORM_TOP_M - PLATFORM_BOTTOM_M) / box.size.y,
		PLATFORM_WIDTH_M / box.size.z)
	platform.scale = module_scale
	platform.global_position = mid.origin - mid.basis * (box.get_center() * module_scale)
	_align_bottom(platform, mid.origin.y + PLATFORM_BOTTOM_M)
	return platform


func _local_mesh_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for item in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := item as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var transform := root.global_transform.affine_inverse() * mesh_instance.global_transform
		var box := mesh_instance.get_aabb()
		for index in 8:
			var point := transform * box.get_endpoint(index)
			if not found:
				result = AABB(point, Vector3.ZERO)
				found = true
			else:
				result = result.expand(point)
	return result


func _pose(distance_m: float, side_offset: float = 0.0) -> Transform3D:
	var pose := _track.get_global_transform_at_distance(clampf(distance_m, 0.0, _track.length))
	pose.origin += pose.basis.z * side_offset
	return pose


func _spawn(asset: String, pose: Transform3D, scale := 1.0, parent: Node3D = null) -> Node3D:
	var path := asset if asset.begins_with("res://") else LTS + asset + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	if node == null:
		return null
	parent = parent if parent else self
	parent.add_child(node)
	pose.basis = pose.basis.scaled_local(Vector3.ONE * scale)
	node.global_transform = pose
	return node


func _world_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for item in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := item as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var box := mesh_instance.get_aabb()
		for index in 8:
			var point := mesh_instance.global_transform * box.get_endpoint(index)
			if not found:
				result = AABB(point, Vector3.ZERO)
				found = true
			else:
				result = result.expand(point)
	return result


func _place_on_ground(node: Node3D, lift := 0.0) -> void:
	var box := _world_aabb(node)
	var ground := 0.0
	if is_instance_valid(_terrain):
		ground = _terrain.height_at(node.global_position.x, node.global_position.z)
	node.global_position.y += ground + lift - box.position.y


func _align_bottom(node: Node3D, target_y: float) -> void:
	var box := _world_aabb(node)
	node.global_position.y += target_y - box.position.y


func _build_station() -> void:
	var platform_top := PLATFORM_TOP_M
	for module in station_modules:
		var pair := _pose_pair(station_distance + module * station_module_spacing)
		var mid: Transform3D = pair["mid"]
		var platform := _place_platform_module(mid)
		if platform:
			platform.name = "Platform%d" % module
		if module in [1, 3]:
			var bench_pose := mid
			bench_pose.origin += bench_pose.basis.x * 4.0
			var bench := _spawn("bench", bench_pose)
			if bench:
				bench.name = "Bench%d" % module
				_align_bottom(bench, mid.origin.y + platform_top)
			var bin := _spawn("garbage", bench_pose)
			if bin:
				bin.name = "Bin%d" % module
				bin.global_position += bench_pose.basis.x * 1.6
				_align_bottom(bin, mid.origin.y + platform_top)

	var house_pose := _pose(station_distance - 8.0, 30.0)
	house_pose.basis = house_pose.basis * Basis(Vector3.UP, -PI / 2.0)
	var house := _spawn("house", house_pose)
	if house:
		_place_on_ground(house)

	var office_pose := _pose(station_distance + 95.0, -34.0)
	office_pose.basis = office_pose.basis * Basis(Vector3.UP, PI / 2.0)
	var office := _spawn("office", office_pose)
	if office:
		_place_on_ground(office)


func _build_poles() -> void:
	var distance := 20.0
	var side := 1.0
	while distance < _track.length - 10.0:
		var offset := 8.5 if absf(distance - (station_distance + 25.0)) < 45.0 else 7.0
		var pose := _pose(distance, side * offset)
		var pole := _spawn("pole", pose)
		if pole:
			_place_on_ground(pole)
		distance += 31.0
		side = -side


func _build_details() -> void:
	_build_canopies()
	_build_footbridge()
	_build_lamps()
	_build_station_signs()
	_build_crossovers()
	_build_speed_signs()
	_build_mountains()
	_build_foothills()


func _build_foothills() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.10, 0.17, 0.11)
	material.roughness = 1.0
	for index in 20:
		var angle := index * TAU / 20.0 + 0.41
		var radius := _rng.randf_range(440.0, 560.0)
		var height := _rng.randf_range(32.0, 82.0)
		var base := _rng.randf_range(90.0, 170.0)
		var cone := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0
		mesh.bottom_radius = base
		mesh.height = height
		mesh.radial_segments = 7
		mesh.rings = 1
		cone.mesh = mesh
		cone.material_override = material
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cone.position = Vector3(cos(angle) * radius, -6.0 + height * 0.5, sin(angle) * radius)
		add_child(cone)


func _build_canopies() -> void:
	var metal := _plain_material(Color(0.24, 0.27, 0.30), 0.45, 0.55)
	var roof := _plain_material(Color(0.32, 0.35, 0.38), 0.6, 0.25)
	for module in [1, 2, 3]:
		var pair := _pose_pair(station_distance + module * station_module_spacing + 4.8)
		var root := Node3D.new()
		add_child(root)
		root.global_transform = pair["mid"]
		var slab := MeshInstance3D.new()
		var slab_mesh := BoxMesh.new()
		slab_mesh.size = Vector3(8.4, 0.16, 2.0)
		slab.mesh = slab_mesh
		slab.material_override = roof
		slab.position = Vector3(0.0, 3.85, 0.0)
		root.add_child(slab)
		for post_x in [-3.8, 3.8]:
			for post_z in [-0.8, 0.8]:
				var post := MeshInstance3D.new()
				var post_mesh := BoxMesh.new()
				post_mesh.size = Vector3(0.12, 3.4, 0.12)
				post.mesh = post_mesh
				post.material_override = metal
				post.position = Vector3(post_x, 2.15, post_z)
				root.add_child(post)


func _build_footbridge() -> void:
	var pair := _pose_pair(station_distance + 24.0)
	var mid: Transform3D = pair["mid"]
	var concrete := _plain_material(Color(0.55, 0.57, 0.58), 0.8)
	var steel := _plain_material(Color(0.30, 0.34, 0.38), 0.4, 0.6)
	var root := Node3D.new()
	add_child(root)
	root.global_transform = mid
	var deck := MeshInstance3D.new()
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(3.2, 0.35, 13.0)
	deck.mesh = deck_mesh
	deck.material_override = concrete
	deck.position = Vector3(0.0, 7.6, 0.0)
	root.add_child(deck)
	for wall_x in [-1.55, 1.55]:
		var parapet := MeshInstance3D.new()
		var parapet_mesh := BoxMesh.new()
		parapet_mesh.size = Vector3(0.10, 1.05, 13.0)
		parapet.mesh = parapet_mesh
		parapet.material_override = steel
		parapet.position = Vector3(wall_x, 8.3, 0.0)
		root.add_child(parapet)
	for tower_z in [-5.5, 5.5]:
		for tower_x in [-1.1, 1.1]:
			var leg := MeshInstance3D.new()
			var leg_mesh := BoxMesh.new()
			leg_mesh.size = Vector3(0.42, 7.6, 0.42)
			leg.mesh = leg_mesh
			leg.material_override = concrete
			leg.position = Vector3(tower_x, 3.8, tower_z)
			root.add_child(leg)
		var cap := MeshInstance3D.new()
		var cap_mesh := BoxMesh.new()
		cap_mesh.size = Vector3(2.7, 0.25, 2.2)
		cap.mesh = cap_mesh
		cap.material_override = steel
		cap.position = Vector3(0.0, 7.85, tower_z)
		root.add_child(cap)


func _build_lamps() -> void:
	var pole_material := StandardMaterial3D.new()
	pole_material.albedo_color = Color(0.16, 0.18, 0.20)
	pole_material.roughness = 0.55
	pole_material.metallic = 0.6
	var lamp_material := StandardMaterial3D.new()
	lamp_material.albedo_color = Color(1.0, 0.86, 0.58)
	lamp_material.emission_enabled = true
	lamp_material.emission = Color(1.0, 0.82, 0.5)
	lamp_material.emission_energy_multiplier = 2.2
	for module in station_modules:
		var pair := _pose_pair(station_distance + module * station_module_spacing + 4.8)
		var mid: Transform3D = pair["mid"]
		for side in [-1.0, 1.0]:
			var pole_position: Vector3 = mid.origin + mid.basis.z * side * 0.9
			var base_y: float = mid.origin.y + 0.55
			var pole := MeshInstance3D.new()
			var pole_mesh := CylinderMesh.new()
			pole_mesh.top_radius = 0.055
			pole_mesh.bottom_radius = 0.075
			pole_mesh.height = 3.8
			pole.mesh = pole_mesh
			pole.material_override = pole_material
			add_child(pole)
			pole.global_position = Vector3(pole_position.x, base_y + 1.9, pole_position.z)
			var head := MeshInstance3D.new()
			var head_mesh := SphereMesh.new()
			head_mesh.radius = 0.17
			head_mesh.height = 0.34
			head.mesh = head_mesh
			head.material_override = lamp_material
			add_child(head)
			head.global_position = Vector3(pole_position.x, base_y + 3.85, pole_position.z)
			var light := OmniLight3D.new()
			light.position = Vector3(pole_position.x, base_y + 3.75, pole_position.z)
			light.omni_range = 15.0
			light.light_energy = 1.1
			light.light_color = Color(1.0, 0.84, 0.58)
			light.shadow_enabled = false
			add_child(light)


func _build_station_signs() -> void:
	for side in [-1.0, 1.0]:
		var pair := _pose_pair(station_distance + 22.0)
		var mid: Transform3D = pair["mid"]
		var root := Node3D.new()
		add_child(root)
		root.global_position = mid.origin + mid.basis.z * side * 0.85 + Vector3(0.0, 3.3, 0.0)
		root.global_basis = Basis.looking_at(mid.basis.z * side, mid.basis.y)
		var board := MeshInstance3D.new()
		var board_mesh := BoxMesh.new()
		board_mesh.size = Vector3(4.2, 1.1, 0.12)
		board.mesh = board_mesh
		board.material_override = _plain_material(Color(0.92, 0.93, 0.9), 0.6)
		root.add_child(board)
		var label := Label3D.new()
		label.text = "WILDTAL"
		label.font_size = 160
		label.pixel_size = 0.0045
		label.modulate = Color(0.08, 0.14, 0.28)
		label.outline_size = 0
		label.position = Vector3(0.0, 0.0, 0.075)
		root.add_child(label)
		for post_x in [-1.8, 1.8]:
			var post := MeshInstance3D.new()
			var post_mesh := BoxMesh.new()
			post_mesh.size = Vector3(0.1, 3.3, 0.1)
			post.mesh = post_mesh
			post.material_override = _plain_material(Color(0.2, 0.21, 0.22), 0.5, 0.6)
			post.position = Vector3(post_x, -1.65, -0.02)
			root.add_child(post)


func _build_crossovers() -> void:
	_build_crossover("CrossoverA", crossover_a_up_distance)
	_build_crossover("CrossoverB", crossover_b_up_distance)


func _build_crossover(node_name: String, up_distance: float) -> void:
	var pair := _pose_pair(up_distance)
	if pair["down"] == null:
		return
	var root := Node3D.new()
	root.name = node_name
	add_child(root)
	root.global_transform = pair["mid"]
	var down: LTSTrack = _inner_track()
	root.set_meta("up_distance", up_distance)
	root.set_meta("down_distance", up_distance * down.length / _track.length)

	var ballast := MeshInstance3D.new()
	var ballast_mesh := BoxMesh.new()
	ballast_mesh.size = Vector3(2.2, 0.18, 4.0)
	ballast.mesh = ballast_mesh
	ballast.material_override = _plain_material(Color(0.2, 0.18, 0.16), 0.95)
	ballast.position = Vector3(0.0, -0.14, 0.0)
	root.add_child(ballast)

	var rail_material := _plain_material(Color(0.38, 0.42, 0.44), 0.3, 0.7)
	for side in [-0.7175, 0.7175]:
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(2.2, 0.16, 0.13)
		rail.mesh = rail_mesh
		rail.material_override = rail_material
		rail.position = Vector3(0.0, 0.02, side)
		root.add_child(rail)

	var sleeper_material := _plain_material(Color(0.22, 0.13, 0.08), 0.9)
	for x in [-0.7, 0.0, 0.7]:
		var sleeper := MeshInstance3D.new()
		var sleeper_mesh := BoxMesh.new()
		sleeper_mesh.size = Vector3(0.18, 0.16, 2.35)
		sleeper.mesh = sleeper_mesh
		sleeper.material_override = sleeper_material
		sleeper.position = Vector3(x, -0.1, 0.0)
		root.add_child(sleeper)

	var blades := Node3D.new()
	blades.name = "Blades"
	blades.position = Vector3(0.0, 0.02, -2.0)
	root.add_child(blades)
	for side in [-0.9, 0.9]:
		var blade := MeshInstance3D.new()
		var blade_mesh := BoxMesh.new()
		blade_mesh.size = Vector3(1.1, 0.12, 0.09)
		blade.mesh = blade_mesh
		blade.material_override = rail_material
		blade.position = Vector3(0.0, 0.0, side * 0.75)
		blade.rotation.y = deg_to_rad(-6.0 if side < 0.0 else 6.0)
		blades.add_child(blade)


func _build_speed_signs() -> void:
	for entry in [[130.0, "80"], [260.0, "60"], [390.0, "80"]]:
		var pose := _pose(entry[0], 5.4)
		var root := Node3D.new()
		add_child(root)
		root.global_position = Vector3(pose.origin.x, pose.origin.y, pose.origin.z)
		root.global_basis = Basis.looking_at(pose.basis.x, pose.basis.y)
		var pole := MeshInstance3D.new()
		var pole_mesh := CylinderMesh.new()
		pole_mesh.top_radius = 0.045
		pole_mesh.bottom_radius = 0.06
		pole_mesh.height = 2.8
		pole.mesh = pole_mesh
		pole.material_override = _plain_material(Color(0.55, 0.57, 0.6), 0.45, 0.5)
		pole.position = Vector3(0.0, 1.4, 0.0)
		root.add_child(pole)
		var board := MeshInstance3D.new()
		var board_mesh := BoxMesh.new()
		board_mesh.size = Vector3(1.05, 1.05, 0.07)
		board.mesh = board_mesh
		board.material_override = _plain_material(Color(0.95, 0.95, 0.93), 0.55)
		board.position = Vector3(0.0, 2.75, 0.04)
		root.add_child(board)
		var label := Label3D.new()
		label.text = entry[1]
		label.font_size = 220
		label.pixel_size = 0.004
		label.modulate = Color(0.05, 0.05, 0.05)
		label.position = Vector3(0.0, 2.75, 0.085)
		root.add_child(label)


func _build_mountains() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.09, 0.15, 0.12)
	material.roughness = 1.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	for index in 26:
		var angle := index * TAU / 26.0 + 0.23
		var radius := _rng.randf_range(620.0, 940.0)
		var height := _rng.randf_range(70.0, 190.0)
		var base := _rng.randf_range(120.0, 260.0)
		var cone := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0
		mesh.bottom_radius = base
		mesh.height = height
		mesh.radial_segments = 7
		mesh.rings = 1
		cone.mesh = mesh
		cone.material_override = material
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cone.position = Vector3(cos(angle) * radius, -8.0 + height * 0.5, sin(angle) * radius)
		add_child(cone)


func _plain_material(color: Color, roughness := 0.8, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


func _build_wires() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.17, 0.18)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_build_track_wires(_track, "CatenaryWiresUP", material)
	var down := _inner_track()
	if down:
		_build_track_wires(down, "CatenaryWiresDOWN", material)


func _build_track_wires(track: LTSTrack, node_name: String, material: StandardMaterial3D) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var distance := 0.0
	while distance < track.length - 6.0:
		var a := track.get_global_transform_at_distance(distance).origin
		var b := track.get_global_transform_at_distance(distance + 6.0).origin
		for height in [5.55, 6.45]:
			mesh.surface_add_vertex(a + Vector3.UP * height)
			mesh.surface_add_vertex(b + Vector3.UP * height)
		if int(distance / 6.0) % 2 == 0:
			mesh.surface_add_vertex(a + Vector3.UP * 5.55)
			mesh.surface_add_vertex(a + Vector3.UP * 6.45)
		distance += 6.0
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	add_child(instance)


func tree_roots() -> Array[Node3D]:
	return _tree_roots


func _scatter_trees() -> void:
	for index in tree_count:
		var distance := _rng.randf_range(6.0, _track.length - 6.0)
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var offset := _rng.randf_range(12.0, 62.0)
		var pose := _pose(distance, side * offset)
		if absf(pose.origin.x) > 238.0 or absf(pose.origin.z) > 238.0:
			continue
		var ground := 0.0
		if is_instance_valid(_terrain):
			ground = _terrain.height_at(pose.origin.x, pose.origin.z)
		if ground < -2.0:
			continue
		var asset: String = TREES[_rng.randi_range(0, TREES.size() - 1)]
		var tree := _spawn(asset, pose, _rng.randf_range(0.75, 1.35))
		if tree == null:
			continue
		tree.rotation.y = _rng.randf_range(0.0, TAU)
		_place_on_ground(tree)
		_tree_roots.append(tree)

		for extra in _rng.randi_range(0, 2):
			var bush_pose := _pose(distance + _rng.randf_range(-6.0, 6.0), side * (offset + _rng.randf_range(1.0, 4.0)))
			var bush := _spawn("res://assets/models/trees/bush.glb", bush_pose, _rng.randf_range(0.7, 1.5))
			if bush:
				_place_on_ground(bush)
