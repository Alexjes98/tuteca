extends CharacterBody3D

## Base class for all playable characters (Gekko and Cat).
##
## Handles shared mechanics:
##   • Multiplayer authority setup & camera activation
##   • Free-look camera: the mouse orbits the CameraPivot (yaw + pitch)
##     around the character without ever rotating the body — you can walk
##     one way and look another. SpringArm3D keeps the camera behind the
##     pivot and retracts against walls so it never clips through geometry.
##   • Camera-relative WASD movement; the visual model (ModelRoot)
##     turns smoothly to face the walking direction.
##   • Gravity and floor-jump.
##
## Subclasses override:
##   • _process_movement(delta) — to inject character-specific physics
##     (e.g. Gekko wall-climb) before or instead of normal movement.
##   • _process_special(delta)  — for unique abilities (pounce, scratch…).
##   • _post_physics()          — for any work needed after move_and_slide().

var SPEED               := 5.0
const JUMP_VELOCITY     := 4.5
const MOUSE_SENSITIVITY := 0.003
## How fast the model turns to face the walking direction (higher = snappier).
const TURN_SPEED        := 10.0

## Pitch limits: look down steeply onto the character, but not far above the horizon.
const PITCH_MIN := -1.3   # ~ -75°
const PITCH_MAX :=  0.5   # ~  30°

@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var _cam_pivot: Node3D = $CameraPivot
@onready var _spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _model_root: Node3D = $ModelRoot

## Start tilted slightly down so the character is framed on spawn.
var _pitch: float = -0.35

## Captured state: when true, character is disabled and invisible.
var captured: bool = false
var _was_captured: bool = false
var _in_coffee: bool = false
var noclip: bool = false:
	set(val):
		noclip = val
		var col = get_node_or_null("CollisionShape3D")
		if col:
			col.disabled = val

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	# The spring arm must ignore the player's own collider, otherwise it
	# retracts to zero length and snaps the camera inside the character.
	_spring_arm.add_excluded_object(get_rid())
	_spring_arm.rotation.x = _pitch
	# Node name == peer_id (assigned by server spawner)
	var peer_id := int(name)
	set_multiplayer_authority(peer_id)
	
	# Instantiate and configure MultiplayerSynchronizer
	var synchronizer := MultiplayerSynchronizer.new()
	synchronizer.name = "MultiplayerSynchronizer"
	var config := SceneReplicationConfig.new()
	config.add_property(".:position")
	config.add_property(".:rotation")
	config.add_property(".:captured")
	config.add_property("ModelRoot:rotation")
	synchronizer.replication_config = config
	synchronizer.root_path = get_path()
	# Set authority to match the character controller peer
	synchronizer.set_multiplayer_authority(peer_id)
	add_child(synchronizer)

	if is_multiplayer_authority():
		camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		camera.current = false

func _update_captured_state() -> void:
	if captured == _was_captured:
		return
	_was_captured = captured
	if captured:
		if _model_root:
			_model_root.visible = false
		collision_layer = 0
		collision_mask = 0
		if is_multiplayer_authority():
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		if _model_root:
			_model_root.visible = true
		collision_layer = 1
		collision_mask = 1

## Virtual function to retrieve the character's local UP direction.
## Gekko overrides this to return its current surface normal.
func _get_camera_up() -> Vector3:
	return Vector3.UP

# ─────────────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if captured:
		return
	if not is_multiplayer_authority():
		return
		
	# Press Escape to release mouse
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return
		
	# Left-click on game view to capture mouse (only when F1/Pause overlay is closed)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var main = get_tree().current_scene
		var is_ui_open := false
		if main:
			var dev = main.get("_dev_tools_panel")
			var pause = main.get("_pause_menu_panel")
			is_ui_open = (dev and dev.visible) or (pause and pause.visible)
		
		if not is_ui_open:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
		
	if event is InputEventMouseMotion:
		# Yaw: rotate the CameraPivot around its local Y axis (surface normal)
		var local_y := _cam_pivot.global_transform.basis.y.normalized()
		_cam_pivot.global_transform.basis = _cam_pivot.global_transform.basis.rotated(local_y, -event.relative.x * MOUSE_SENSITIVITY).orthonormalized()
		
		# Pitch: clamp and set on child SpringArm3D
		_pitch = clamp(_pitch - event.relative.y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)
		_spring_arm.rotation.x = _pitch

# ─────────────────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	_update_captured_state()
	
	if captured:
		velocity = Vector3.ZERO
		return

	# Coffee mug detection & splash (Only in Sunroom Library map)
	var main_scene = get_tree().current_scene
	var is_library = main_scene and main_scene.get("_chosen_map") == "Sunroom Library"
	
	var in_coffee_box := false
	if is_library:
		in_coffee_box = global_position.x > -9.3 and global_position.x < -6.7 \
				and global_position.z > -23.3 and global_position.z < -20.7 \
				and global_position.y > 7.1 and global_position.y < 10.1
			
	if in_coffee_box:
		if not _in_coffee:
			_in_coffee = true
			if is_multiplayer_authority():
				rpc_spawn_splash.rpc(Vector3(-8.0, 8.8, -22.0))
				if FileAccess.file_exists("res://assets/sounds/coffee_splash.mp3"):
					rpc_play_splash_sound.rpc()
	else:
		_in_coffee = false
		
	# Smoothly align camera pivot's local up vector with the character's surface normal
	var current_up := _cam_pivot.global_transform.basis.y.normalized()
	var target_up := _get_camera_up()
	var axis := current_up.cross(target_up)
	
	if current_up.dot(target_up) < -0.99:
		# Opposing vectors (anti-parallel): use local X-axis to flip 180 degrees upright
		var fallback_axis := _cam_pivot.global_transform.basis.x.normalized()
		var rotation_step := minf(PI, 12.0 * delta)
		_cam_pivot.global_transform.basis = _cam_pivot.global_transform.basis.rotated(fallback_axis, rotation_step).orthonormalized()
	elif axis.length() > 0.001:
		axis = axis.normalized()
		var angle := current_up.angle_to(target_up)
		# Interpolate rotation smoothly so the camera doesn't snap abruptly
		var rotation_step := minf(angle, 12.0 * delta)
		_cam_pivot.global_transform.basis = _cam_pivot.global_transform.basis.rotated(axis, rotation_step).orthonormalized()

	if not is_multiplayer_authority():
		return

	# If player is typing in chat, freeze horizontal movement and skip processing controls
	if _is_typing():
		var is_stuck_gekko: bool = false
		var stuck_val = get("_stuck")
		if stuck_val != null:
			is_stuck_gekko = bool(stuck_val)
		if not is_stuck_gekko and not is_on_floor():
			velocity += get_gravity() * delta
		velocity.x = move_toward(velocity.x, 0.0, SPEED * 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, SPEED * 4.0 * delta)
		move_and_slide()
		return

	_process_movement(delta)
	_process_special(delta)
	move_and_slide()
	
	# Apply dynamic physics push impulse to RigidBody3D nodes (yarn balls)
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var collider := col.get_collider()
		if collider is RigidBody3D:
			var push_dir := -col.get_normal()
			push_dir.y = 0.0
			push_dir = push_dir.normalized()
			# Apply push force scaled by character speed
			var force := 12.0
			collider.apply_impulse(push_dir * force, col.get_position() - collider.global_position)
			
	_post_physics()

func _is_typing() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus != null and focus is LineEdit

# ─────────────────────────────────────────────────────────────────────────────
## Shared gravity + floor-jump + WASD locomotion.
## Gekko overrides this to inject wall-climb detection before calling super().
func _process_movement(delta: float) -> void:
	if noclip:
		var raw := Vector2.ZERO
		if not _is_typing():
			if Input.is_action_pressed("move_forward"): raw.y -= 1.0
			if Input.is_action_pressed("move_back"):    raw.y += 1.0
			if Input.is_action_pressed("move_left"):    raw.x -= 1.0
			if Input.is_action_pressed("move_right"):   raw.x += 1.0
		
		var cam_basis = camera.global_transform.basis
		var dir = cam_basis.x * raw.x + cam_basis.z * raw.y
		
		var up_down := 0.0
		if not _is_typing():
			if Input.is_action_pressed("jump"):
				up_down += 1.0
			if Input.is_physical_key_pressed(KEY_CTRL):
				up_down -= 1.0
				
		velocity = (dir.normalized() + Vector3.UP * up_down).normalized() * SPEED * 4.0
		return

	# Gravity
	if not is_on_floor():
		# Apply fireplace updraft (thermal lift) if in Sunroom Library map
		var main_scene = get_tree().root.get_child(0)
		var is_sunroom = main_scene != null and main_scene.get("_chosen_map") == "Sunroom Library"
		if is_sunroom and global_position.x > -8.0 and global_position.x < 8.0 \
				and global_position.z > -50.0 and global_position.z < -42.0 \
				and global_position.y > 0.0 and global_position.y < 25.0:
			velocity.y = move_toward(velocity.y, 16.0, 40.0 * delta)
		else:
			velocity += get_gravity() * delta

	# Jump — only from floor; mid-air space is reserved per-character
	if not _is_typing() and Input.is_action_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# WASD → camera-relative direction: W walks away from the camera, so
	# steering the camera while holding W curves the character's path.
	var raw := Vector2.ZERO
	if not _is_typing():
		if Input.is_action_pressed("move_forward"): raw.y -= 1.0
		if Input.is_action_pressed("move_back"):    raw.y += 1.0
		if Input.is_action_pressed("move_left"):    raw.x -= 1.0
		if Input.is_action_pressed("move_right"):   raw.x += 1.0
		raw = raw.normalized()

	var direction := Vector3(raw.x, 0.0, raw.y).rotated(Vector3.UP, _cam_pivot.rotation.y)
	if direction.length_squared() > 0.0:
		var target_vel := direction * SPEED
		var current_horiz := Vector3(velocity.x, 0.0, velocity.z)
		if current_horiz.length() > SPEED + 0.1:
			# Active steering/braking: if input direction opposes current momentum,
			# increase decay rate so player can steer or brake out of pounce.
			var decay_rate := 9.0
			if direction.length_squared() > 0.01 and current_horiz.normalized().dot(direction.normalized()) < 0.2:
				decay_rate = 24.0
				
			current_horiz = current_horiz.move_toward(target_vel, decay_rate * delta)
			velocity.x = current_horiz.x
			velocity.z = current_horiz.z
		else:
			velocity.x = target_vel.x
			velocity.z = target_vel.z
		_face_direction(direction, delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)
		
		# If standing still, face the visual model in the direction the camera is looking
		var cam_forward := -_cam_pivot.global_transform.basis.z.normalized()
		cam_forward.y = 0.0
		if cam_forward.length_squared() > 0.01:
			_face_direction(cam_forward.normalized(), delta)

# ─────────────────────────────────────────────────────────────────────────────
## Smoothly yaw the visual model so the head points where the character walks.
func _face_direction(direction: Vector3, delta: float) -> void:
	var target_yaw := atan2(-direction.x, -direction.z)
	_model_root.rotation.y = lerp_angle(
			_model_root.rotation.y, target_yaw, minf(TURN_SPEED * delta, 1.0))

# ─────────────────────────────────────────────────────────────────────────────
## Override in subclasses for character-unique abilities.
func _process_special(_delta: float) -> void:
	pass

# ─────────────────────────────────────────────────────────────────────────────
## Called after move_and_slide() each frame. Override for post-physics work.
func _post_physics() -> void:
	pass

# ─────────────────────────────────────────────────────────────────────────────
## Multi-player knockback implementation.
@rpc("any_peer", "call_local", "reliable")
func rpc_apply_knockback(force: Vector3) -> void:
	if is_multiplayer_authority():
		velocity += force
		print("[%s] Received knockback: %s" % [name, force])

# ─────────────────────────────────────────────────────────────────────────────
## Spawns a temporary particle explosion at the specified position.
@rpc("any_peer", "call_local", "reliable")
func rpc_spawn_explosion(pos: Vector3) -> void:
	var particles := CPUParticles3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.2
	sphere_mesh.height = 0.4
	
	var material := StandardMaterial3D.new()
	material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.3, 0.05)  # Bright fire orange
	sphere_mesh.material = material
	
	particles.mesh = sphere_mesh
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 35
	particles.lifetime = 0.6
	particles.spread = 180.0
	particles.initial_velocity_min = 10.0
	particles.initial_velocity_max = 18.0
	particles.gravity = Vector3(0, -12.0, 0)  # Gravity pulls sparks down
	
	# Add particles to the parent stage node so they stay stationary in the world
	get_parent().add_child(particles)
	particles.global_position = pos
	particles.emitting = true
	
	# Automatically clean up node after lifetime ends
	get_tree().create_timer(particles.lifetime + 0.1).timeout.connect(particles.queue_free)

# ─────────────────────────────────────────────────────────────────────────────
## Spawns a temporary splash particle effect at the specified position.
@rpc("any_peer", "call_local", "reliable")
func rpc_spawn_splash(pos: Vector3) -> void:
	var particles := CPUParticles3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.15
	sphere_mesh.height = 0.3
	
	var material := StandardMaterial3D.new()
	material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.2, 0.1, 0.05) # Coffee brown color
	sphere_mesh.material = material
	
	particles.mesh = sphere_mesh
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.amount = 25
	particles.lifetime = 0.6
	particles.spread = 45.0
	particles.direction = Vector3.UP # Splash upwards
	particles.initial_velocity_min = 6.0
	particles.initial_velocity_max = 10.0
	particles.gravity = Vector3(0, -12.0, 0)
	
	# Add particles to the parent stage node so they stay stationary in the world
	get_parent().add_child(particles)
	particles.global_position = pos
	particles.emitting = true
	
	# Automatically clean up node after lifetime ends
	get_tree().create_timer(particles.lifetime + 0.1).timeout.connect(particles.queue_free)

# ─────────────────────────────────────────────────────────────────────────────
## Plays a 3D splash sound locally and syncs it to other peers.
@rpc("any_peer", "call_local", "reliable")
func rpc_play_splash_sound() -> void:
	if FileAccess.file_exists("res://assets/sounds/coffee_splash.mp3"):
		var s_player := AudioStreamPlayer3D.new()
		s_player.stream = load("res://assets/sounds/coffee_splash.mp3")
		s_player.volume_db = 0.0
		s_player.unit_size = 6.0
		s_player.max_distance = 25.0
		get_parent().add_child(s_player)
		s_player.global_position = Vector3(-8.0, 8.8, -22.0)
		s_player.play()
		get_tree().create_timer(3.0).timeout.connect(s_player.queue_free)
