extends Node3D

## Grillo (Cricket) game object script.
## Manages surface placement, alignment perpendicular to surface normals,
## and synchronized parabolic jump animations.

@onready var character_body: CharacterBody3D = $CharacterBody3D
@onready var collision_shape: CollisionShape3D = $CharacterBody3D/CollisionShape3D

## SphereShape3D radius in grillo.tscn is ~0.59816.
## Pushes the cricket origin along surface normal so the bottom contact point touches the mesh.
const SURFACE_OFFSET := 0.59816116

# Hopping animation state variables
var _is_jumping: bool = false
var _jump_start_transform: Transform3D
var _jump_target_transform: Transform3D
var _jump_progress: float = 0.0
const JUMP_DURATION := 0.65  # Smooth half-second jump duration
const JUMP_PEAK := 1.6       # Height of the parabolic arc

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	var area = find_child("CollectionArea", true, false)
	if area:
		area.body_entered.connect(_on_body_entered)
	_reset_hop_timer()

# ─────────────────────────────────────────────────────────────────────────────
## Place and orient cricket on a surface given its hit position and normal vector.
func place_on_surface(hit_pos: Vector3, normal: Vector3, rng: RandomNumberGenerator = null) -> void:
	global_transform = _calculate_surface_transform(hit_pos, normal, rng)

# Helper to compute orientation basis aligned perpendicular to surface normal
func _calculate_surface_transform(hit_pos: Vector3, normal: Vector3, rng: RandomNumberGenerator = null) -> Transform3D:
	var n := normal.normalized()
	
	# Generate a random direction vector perpendicular to surface normal
	var random_dir: Vector3
	if rng:
		random_dir = Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		).normalized()
	else:
		random_dir = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()
	
	var tangent := random_dir.cross(n)
	if tangent.length_squared() < 0.001:
		var ref := Vector3.FORWARD if abs(n.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		tangent = ref.cross(n)
	tangent = tangent.normalized()
	
	var bitangent := n.cross(tangent).normalized()
	
	# Basis: Y axis = surface normal (perpendicular to surface)
	var b := Basis(tangent, n, bitangent).orthonormalized()
	
	# Position: surface hit location + normal * offset so bottom touches the mesh surface cleanly
	var surface_pos := hit_pos + n * SURFACE_OFFSET
	return Transform3D(b, surface_pos)

# ─────────────────────────────────────────────────────────────────────────────
# Server-side timer & jump trigger logic
# ─────────────────────────────────────────────────────────────────────────────
var _hop_timer: float = 0.0

func _reset_hop_timer() -> void:
	_hop_timer = randf_range(5.0, 10.0)  # Random duration between jumps

func _process(delta: float) -> void:
	# 1. Server-side AI logic to pick hop destinations
	if multiplayer.is_server():
		var main_node = get_tree().current_scene
		if main_node and main_node.get("game_state") == "playing":
			_hop_timer -= delta
			if _hop_timer <= 0.0:
				_reset_hop_timer()
				_attempt_hop()

	# 2. Local visual animation (Host & Clients)
	if _is_jumping:
		_jump_progress += delta / JUMP_DURATION
		if _jump_progress >= 1.0:
			_is_jumping = false
			global_transform = _jump_target_transform
		else:
			# Lerp horizontal/base position
			var lerped_pos := _jump_start_transform.origin.lerp(_jump_target_transform.origin, _jump_progress)
			# Parabolic vertical displacement (using sine curve from 0 to PI)
			var arc := sin(_jump_progress * PI) * JUMP_PEAK
			# Project arc along the blended up-direction (so wall-to-ceiling jumps work correctly)
			var up_dir := _jump_start_transform.basis.y.lerp(_jump_target_transform.basis.y, _jump_progress).normalized()
			global_position = lerped_pos + up_dir * arc
			
			# Smoothly slerp rotation basis
			var slerped_basis := _jump_start_transform.basis.orthonormalized().slerp(_jump_target_transform.basis.orthonormalized(), _jump_progress)
			global_transform.basis = slerped_basis

# Server checks for a valid nearby surface to leap towards
func _attempt_hop() -> void:
	var space := get_world_3d().direct_space_state
	if not space:
		return
		
	var random_dir := Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	).normalized()
	
	# Raycast 8.0 meters in the random direction
	var start_pos := global_position + global_transform.basis.y * 0.4
	var end_pos := start_pos + random_dir * 8.0
	
	var ray_query := PhysicsRayQueryParameters3D.create(start_pos, end_pos)
	if character_body:
		ray_query.exclude = [character_body.get_rid()]
		
	var hit := space.intersect_ray(ray_query)
	if not hit.is_empty() and hit.has("position") and hit.has("normal"):
		_rpc_hop.rpc(hit.position, hit.normal)

# Synchronized RPC to start the jump animation on all peers
@rpc("call_local", "reliable")
func _rpc_hop(pos: Vector3, normal: Vector3) -> void:
	_jump_start_transform = global_transform
	_jump_target_transform = _calculate_surface_transform(pos, normal)
	_jump_progress = 0.0
	_is_jumping = true

# ─────────────────────────────────────────────────────────────────────────────
# Gekko collision/collection logic
# ─────────────────────────────────────────────────────────────────────────────
func _on_body_entered(body: Node) -> void:
	if not multiplayer.is_server():
		return
	
	if body.is_in_group("lizards"):
		var main_node = get_tree().current_scene
		if main_node and main_node.has_method("collect_cricket"):
			main_node.collect_cricket(name)
