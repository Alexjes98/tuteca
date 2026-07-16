extends CharacterBody3D

## Authority-safe FPV player controller.
## The node must be named after its peer ID so set_multiplayer_authority
## can be called correctly in _ready().

const SPEED          := 5.0
const JUMP_VELOCITY  := 4.5
const MOUSE_SENSITIVITY := 0.003

@onready var camera: Camera3D = $Camera3D

var _pitch: float = 0.0

func _ready() -> void:
	# Node name == peer_id (set by the server spawner)
	set_multiplayer_authority(int(name))

	if is_multiplayer_authority():
		camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		camera.current = false

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		# Horizontal look → rotate the whole body (yaw)
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		# Vertical look → tilt camera only (pitch), clamped ±90°
		_pitch = clamp(_pitch - event.relative.y * MOUSE_SENSITIVITY,
					-PI / 2.0, PI / 2.0)
		camera.rotation.x = _pitch

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	# ── Mouse capture toggle ──────────────────────────────────────────────
	if Input.is_action_just_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# ── Gravity ───────────────────────────────────────────────────────────
	if not is_on_floor():
		velocity += get_gravity() * delta

	# ── Jump (Space) ─────────────────────────────────────────────────────
	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# ── WASD Movement ────────────────────────────────────────────────────
	var raw := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): raw.y -= 1.0
	if Input.is_key_pressed(KEY_S): raw.y += 1.0
	if Input.is_key_pressed(KEY_A): raw.x -= 1.0
	if Input.is_key_pressed(KEY_D): raw.x += 1.0
	raw = raw.normalized()

	var direction := (transform.basis * Vector3(raw.x, 0.0, raw.y)).normalized()
	if direction.length_squared() > 0.0:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)

	move_and_slide()
