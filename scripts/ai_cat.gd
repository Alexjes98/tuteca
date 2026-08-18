extends CharacterBody3D

## AI-controlled cat NPC.
##
## Spawned by the server whenever a Gekko (Tuteca) enters the game. It wanders
## until a non-captured lizard enters its view cone with clear line of sight,
## then chases it (with a short memory of the last seen position), jumping when
## the target is above it or when it bumps into a wall. Touching a lizard
## captures it (server-side) which can end the game.
##
## Runs its logic only on the server; clients receive position/rotation through
## a MultiplayerSynchronizer built in _ready (same pattern as BaseCharacter).

const SPEED         := 7.0    # Chase speed (between gekko walk 5.0 and sprint 9.0)
const TURN_SPEED    := 8.0    # Model yaw lerp speed
const JUMP_VELOCITY := 8.0    # Vertical jump strength
const JUMP_COOLDOWN := 1.5    # Seconds between jumps
const JUMP_HEIGHT_TRIGGER := 1.5  # Target this much higher → try to jump
const CATCH_RADIUS  := 3.0    # Origin-to-origin distance that counts as a touch

# ── Vision ────────────────────────────────────────────────────────────────────
const VISION_RANGE   := 25.0  # Max sight distance
const VISION_FOV_DEG := 120.0 # Total field-of-view angle (60° each side)
const EYE_HEIGHT     := 1.2   # Ray origin above the body origin
const SIGHT_MEMORY   := 2.0   # Seconds it keeps chasing the last seen position

# ── Wander (when nobody is visible) ──────────────────────────────────────────
const WANDER_SPEED    := 2.5  # Slow patrol speed
const WANDER_RETARGET := 3.0  # Seconds between random direction changes

@onready var _model_root: Node3D = $ModelRoot

var _jump_cd: float = 0.0
var _sight_timer: float = 0.0        # Counts down after losing sight
var _last_seen_pos: Vector3 = Vector3.ZERO
var _wander_dir: Vector3 = Vector3.ZERO
var _wander_timer: float = 0.0

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("ai_cats")
	set_multiplayer_authority(1)

	# Replicate transform from the server to every client.
	var synchronizer := MultiplayerSynchronizer.new()
	var config := SceneReplicationConfig.new()
	config.add_property(".:position")
	config.add_property("ModelRoot:rotation")
	synchronizer.replication_config = config
	synchronizer.root_path = get_path()
	synchronizer.set_multiplayer_authority(1)
	add_child(synchronizer)

# ─────────────────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if not is_on_floor():
		velocity += get_gravity() * delta
	if _jump_cd > 0.0:
		_jump_cd = maxf(_jump_cd - delta, 0.0)

	var main := get_tree().current_scene
	var playing: bool = main != null and main.get("game_state") == "playing"

	# The cat only chases lizards it can actually SEE (view cone + occlusion ray).
	var target := _nearest_visible_lizard() if playing else null

	if target:
		_last_seen_pos = target.global_position
		_sight_timer = SIGHT_MEMORY
		_chase(_last_seen_pos, delta)
	elif playing and _sight_timer > 0.0:
		# Lost sight recently: keep heading to where the lizard was last seen.
		_sight_timer = maxf(_sight_timer - delta, 0.0)
		_chase(_last_seen_pos, delta)
	elif playing:
		_wander(delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)

	# Touch → capture regardless of sight (bumping into the cat still counts).
	if playing:
		var near := _nearest_lizard()
		if near and global_position.distance_to(near.global_position) <= CATCH_RADIUS:
			if main and main.has_method("ai_capture_player"):
				main.ai_capture_player(int(str(near.name)))

	move_and_slide()

# ─────────────────────────────────────────────────────────────────────────────
## Run toward a world position, jumping over obstacles / toward high targets.
func _chase(target_pos: Vector3, delta: float) -> void:
	var to_target := target_pos - global_position
	var horiz := Vector3(to_target.x, 0.0, to_target.z)
	var dist := horiz.length()
	if dist > 0.1:
		var dir := horiz / dist
		velocity.x = dir.x * SPEED
		velocity.z = dir.z * SPEED
		_face_direction(dir, delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	if is_on_floor() and _jump_cd <= 0.0 \
			and (to_target.y > JUMP_HEIGHT_TRIGGER or is_on_wall()):
		velocity.y = JUMP_VELOCITY
		_jump_cd = JUMP_COOLDOWN

# ─────────────────────────────────────────────────────────────────────────────
## Nobody in sight: patrol slowly in a random direction, changing it every few
## seconds. The turning sweeps the view cone around so it can spot prey again.
func _wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0 or _wander_dir == Vector3.ZERO:
		_wander_timer = WANDER_RETARGET
		var angle := randf_range(0.0, TAU)
		_wander_dir = Vector3(cos(angle), 0.0, sin(angle))
	if is_on_wall():
		_wander_dir = -_wander_dir   # Bounce off walls instead of pushing into them
		_wander_timer = WANDER_RETARGET
	velocity.x = _wander_dir.x * WANDER_SPEED
	velocity.z = _wander_dir.z * WANDER_SPEED
	_face_direction(_wander_dir, delta)

# ─────────────────────────────────────────────────────────────────────────────
## Closest non-captured member of the "lizards" group, or null.
func _nearest_lizard() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for liz in get_tree().get_nodes_in_group("lizards"):
		if liz.get("captured"):
			continue
		var d: float = global_position.distance_squared_to(liz.global_position)
		if d < best_d:
			best_d = d
			best = liz
	return best

## Closest non-captured lizard the cat can actually see, or null.
func _nearest_visible_lizard() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for liz in get_tree().get_nodes_in_group("lizards"):
		if liz.get("captured"):
			continue
		var d: float = global_position.distance_squared_to(liz.global_position)
		if d < best_d and _can_see(liz):
			best_d = d
			best = liz
	return best

# ─────────────────────────────────────────────────────────────────────────────
## True when `liz` is within range, inside the view cone, and not occluded.
func _can_see(liz: PhysicsBody3D) -> bool:
	if "camouflage_transparency" in liz and liz.camouflage_transparency >= 0.6:
		return false

	var eye := global_position + Vector3.UP * EYE_HEIGHT
	var to := liz.global_position - eye
	if to.length() > VISION_RANGE:
		return false

	# View cone: compare against the model's facing direction on the floor plane.
	var fwd := -_model_root.global_transform.basis.z
	var fwd_flat := Vector3(fwd.x, 0.0, fwd.z)
	var to_flat := Vector3(to.x, 0.0, to.z)
	if fwd_flat.length() > 0.01 and to_flat.length() > 0.5:
		var cos_half_fov := cos(deg_to_rad(VISION_FOV_DEG * 0.5))
		if fwd_flat.normalized().dot(to_flat.normalized()) < cos_half_fov:
			return false

	# Occlusion: a wall between the eye and the lizard blocks sight.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(eye, liz.global_position)
	q.exclude = [get_rid(), liz.get_rid()]
	q.collision_mask = collision_mask
	return space.intersect_ray(q).is_empty()

# ─────────────────────────────────────────────────────────────────────────────
## Smoothly yaw the visual model toward the chase direction.
func _face_direction(direction: Vector3, delta: float) -> void:
	var target_yaw := atan2(-direction.x, -direction.z)
	_model_root.rotation.y = lerp_angle(
			_model_root.rotation.y, target_yaw, minf(TURN_SPEED * delta, 1.0))

# ─────────────────────────────────────────────────────────────────────────────
## Called by main on restart: back to the cat-team zone, far from the gekkos.
func reset_for_new_round() -> void:
	global_position = Vector3(randf_range(-30.0, 30.0), 2.0, randf_range(25.0, 40.0))
	velocity = Vector3.ZERO
	_sight_timer = 0.0
	_wander_dir = Vector3.ZERO
