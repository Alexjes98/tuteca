extends Node3D

## Cricket Spawner
## Generates 4 crickets per Gekko player in the scene.
## Places crickets randomly on surfaces across the map (floors, walls, furniture, ceiling)
## ensuring they touch the surface and are oriented perpendicular to the surface normal.

const CRICKET_SCENE := preload("res://game_objects/grillo.tscn")
const CRICKETS_PER_GEKKO := 4
const SEED := 12245

var _rng := RandomNumberGenerator.new()
var _spawned_crickets: Array[Node3D] = []

func _ready() -> void:
	_rng.seed = SEED
	# Wait for physics frame so Map geometry colliders are loaded in 3D direct space state
	await get_tree().physics_frame
	spawn_crickets_for_scene()

## Spawns crickets for all Gekko players present (or default 1 Gekko count if starting scene standalone).
func spawn_crickets_for_scene() -> void:
	_clear_crickets()
	
	var gekko_count := _count_gekko_players()
	var total_crickets := gekko_count * CRICKETS_PER_GEKKO
	
	var space := get_world_3d().direct_space_state
	if not space:
		return
		
	var placed := 0
	var attempts := 0
	var max_attempts := total_crickets * 100
	
	while placed < total_crickets and attempts < max_attempts:
		attempts += 1
		
		# Pick random interior origin and random ray direction
		var from_pos := Vector3(
			_rng.randf_range(-40.0, 40.0),
			_rng.randf_range(0.5, 25.0),
			_rng.randf_range(-40.0, 40.0)
		)
		var dir := Vector3(
			_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.0, 1.0)
		).normalized()
		
		var ray_query := PhysicsRayQueryParameters3D.create(from_pos, from_pos + dir * 60.0)
		var hit := space.intersect_ray(ray_query)
		
		if not hit.is_empty() and hit.has("position") and hit.has("normal"):
			var hit_pos: Vector3 = hit.position
			var hit_normal: Vector3 = hit.normal
			
			if hit_normal.length_squared() < 0.001:
				continue
				
			var cricket := CRICKET_SCENE.instantiate() as Node3D
			add_child(cricket)
			
			if cricket.has_method("place_on_surface"):
				cricket.call("place_on_surface", hit_pos, hit_normal, _rng)
			else:
				_align_cricket(cricket, hit_pos, hit_normal)
				
			_spawned_crickets.append(cricket)
			placed += 1
			
	print("[CricketSpawner] Successfully spawned %d crickets (%d per Gekko player)." % [placed, CRICKETS_PER_GEKKO])

## Fallback alignment helper if place_on_surface method is not found on cricket root
func _align_cricket(cricket: Node3D, pos: Vector3, normal: Vector3) -> void:
	var n := normal.normalized()
	var random_dir := Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)
	).normalized()
	
	var tangent := random_dir.cross(n)
	if tangent.length_squared() < 0.001:
		var ref := Vector3.FORWARD if abs(n.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		tangent = ref.cross(n)
	tangent = tangent.normalized()
	var bitangent := n.cross(tangent).normalized()
	
	var b := Basis(tangent, n, bitangent).orthonormalized()
	var surface_offset := 0.59816116
	cricket.global_transform = Transform3D(b, pos + n * surface_offset)

## Counts Gekko players in the scene / multiplayer peer dictionary
func _count_gekko_players() -> int:
	var main_node = get_tree().current_scene
	if not main_node:
		return 1
		
	var count := 0
	
	# Check main_test.gd peer_characters dictionary if present
	if "_peer_characters" in main_node:
		var peer_chars: Dictionary = main_node._peer_characters
		for peer_id in peer_chars:
			if peer_chars[peer_id] == "gekko":
				count += 1
				
	# Check spawned player nodes under $Players if present
	if count == 0:
		var players_container = main_node.find_child("Players", true, false)
		if players_container:
			for child in players_container.get_children():
				var script_res = child.get_script()
				if script_res and "player.gd" in script_res.resource_path:
					count += 1
					
	# Fallback to at least 1 Gekko player for standalone scene testing
	return max(1, count)

func _clear_crickets() -> void:
	for cricket in _spawned_crickets:
		if is_instance_valid(cricket):
			cricket.queue_free()
	_spawned_crickets.clear()
