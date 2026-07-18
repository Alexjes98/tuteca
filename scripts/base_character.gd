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

const SPEED             := 5.0
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

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	# The spring arm must ignore the player's own collider, otherwise it
	# retracts to zero length and snaps the camera inside the character.
	_spring_arm.add_excluded_object(get_rid())
	_cam_pivot.rotation.x = _pitch
	# Node name == peer_id (assigned by server spawner)
	set_multiplayer_authority(int(name))
	if is_multiplayer_authority():
		camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		camera.current = false

# ─────────────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		# Yaw + pitch both go to the camera pivot only: the body never
		# rotates, so looking around never changes the walking direction.
		_cam_pivot.rotation.y -= event.relative.x * MOUSE_SENSITIVITY
		_pitch = clamp(_pitch - event.relative.y * MOUSE_SENSITIVITY,
				PITCH_MIN, PITCH_MAX)
		_cam_pivot.rotation.x = _pitch

# ─────────────────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	# Mouse capture toggle
	if Input.is_action_just_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	_process_movement(delta)
	_process_special(delta)
	move_and_slide()
	_post_physics()

# ─────────────────────────────────────────────────────────────────────────────
## Shared gravity + floor-jump + WASD locomotion.
## Gekko overrides this to inject wall-climb detection before calling super().
func _process_movement(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Jump — only from floor; mid-air space is reserved per-character
	if Input.is_action_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# WASD → camera-relative direction: W walks away from the camera, so
	# steering the camera while holding W curves the character's path.
	var raw := Vector2.ZERO
	if Input.is_action_pressed("move_forward"): raw.y -= 1.0
	if Input.is_action_pressed("move_back"):    raw.y += 1.0
	if Input.is_action_pressed("move_left"):    raw.x -= 1.0
	if Input.is_action_pressed("move_right"):   raw.x += 1.0
	raw = raw.normalized()

	var direction := Vector3(raw.x, 0.0, raw.y).rotated(Vector3.UP, _cam_pivot.rotation.y)
	if direction.length_squared() > 0.0:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		_face_direction(direction, delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)

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
