extends CharacterBody3D

## Base class for all playable characters (Gekko and Cat).
##
## Handles shared mechanics:
##   • Multiplayer authority setup & camera activation
##   • Mouse-look (yaw on body, pitch on camera)
##   • Gravity, floor-jump, and WASD movement
##
## Subclasses override:
##   • _process_movement(delta) — to inject character-specific physics
##     (e.g. Gekko wall-climb) before or instead of normal movement.
##   • _process_special(delta)  — for unique abilities (pounce, scratch…).
##   • _post_physics()          — for any work needed after move_and_slide().

const SPEED             := 5.0
const JUMP_VELOCITY     := 4.5
const MOUSE_SENSITIVITY := 0.003

@onready var camera: Camera3D = $Camera3D

var _pitch: float = 0.0

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
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
		# Yaw: rotate the whole body
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		# Pitch: tilt camera only, clamped ±90°
		_pitch = clamp(_pitch - event.relative.y * MOUSE_SENSITIVITY,
				-PI / 2.0, PI / 2.0)
		camera.rotation.x = _pitch

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

	# WASD
	var raw := Vector2.ZERO
	if Input.is_action_pressed("move_forward"): raw.y -= 1.0
	if Input.is_action_pressed("move_back"):    raw.y += 1.0
	if Input.is_action_pressed("move_left"):    raw.x -= 1.0
	if Input.is_action_pressed("move_right"):   raw.x += 1.0
	raw = raw.normalized()

	var direction := (transform.basis * Vector3(raw.x, 0.0, raw.y)).normalized()
	if direction.length_squared() > 0.0:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)

# ─────────────────────────────────────────────────────────────────────────────
## Override in subclasses for character-unique abilities.
func _process_special(_delta: float) -> void:
	pass

# ─────────────────────────────────────────────────────────────────────────────
## Called after move_and_slide() each frame. Override for post-physics work.
func _post_physics() -> void:
	pass
