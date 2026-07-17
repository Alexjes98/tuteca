extends CharacterBody3D

## Authority-safe FPV player controller.
## The node must be named after its peer ID so set_multiplayer_authority
## can be called correctly in _ready().

const SPEED             := 5.0
const JUMP_VELOCITY     := 4.5
const MOUSE_SENSITIVITY := 0.003
const CLIMB_SPEED       := 3.0   # Up / down / lateral speed while wall-climbing

@onready var camera: Camera3D = $Camera3D

var _pitch: float = 0.0

# ── Wall-climbing state ────────────────────────────────────────────────────────
## true while the player is actively sticking to a wall
var _climbing: bool = false
## Normal of the wall being climbed (points away from the wall, toward the player)
var _wall_normal: Vector3 = Vector3.ZERO

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

	var space_held: bool = Input.is_key_pressed(KEY_SPACE)

	# ── Wall-climbing detection ───────────────────────────────────────────
	if space_held and not is_on_floor():
		# Refresh the wall normal only when we have confirmed contact.
		# This keeps the last good normal valid during brief gaps caused
		# by rotate_y() breaking contact mid-frame (camera mouse look).
		if is_on_wall():
			_climbing    = true
			_wall_normal = get_wall_normal()
		# else: remain in whatever state _climbing already is —
		# if we were climbing, keep climbing with the stored normal.
	else:
		# Space released or landed: always exit climbing
		_climbing    = false
		_wall_normal = Vector3.ZERO

	# ── Branch: climbing vs normal physics ───────────────────────────────
	if _climbing:
		_process_climbing(delta)
	else:
		_process_walking(delta)

	move_and_slide()

	# After physics resolution, refresh normal if still on wall.
	# Do NOT exit climbing here — a momentary gap from rotate_y() would
	# falsely drop the player. Exiting is handled by the Space/floor check above.
	if _climbing and is_on_wall():
		_wall_normal = get_wall_normal()

# ── Climbing physics ──────────────────────────────────────────────────────────
func _process_climbing(_delta: float) -> void:
	# Nullify gravity while hugging the wall
	velocity.y = 0.0

	# A small push into the wall keeps is_on_wall() true next frame
	var into_wall: Vector3 = -_wall_normal * 0.5

	# W / S → move up / down
	var vertical: float = 0.0
	if Input.is_key_pressed(KEY_W): vertical =  1.0
	if Input.is_key_pressed(KEY_S): vertical = -1.0

	# A / D → strafe laterally along the wall surface.
	# Use the player body's own world-space right (basis.x) instead of a
	# fixed world-axis cross product. Because rotate_y() rotates the whole
	# body, basis.x matches what the camera sees as "right" in every
	# orientation — it flips automatically when the player faces away from
	# the wall, keeping A/D perspective-correct in both cases.
	# Project onto the wall plane so the vector is purely lateral on the surface.
	var raw_right  := transform.basis.x
	var wall_right := (raw_right - raw_right.dot(_wall_normal) * _wall_normal).normalized()
	var lateral: float = 0.0
	if Input.is_key_pressed(KEY_A): lateral = -1.0
	if Input.is_key_pressed(KEY_D): lateral =  1.0

	# Combine vertical and lateral movement on the wall
	var climb_dir: Vector3 = (Vector3.UP * vertical + wall_right * lateral).normalized()
	if climb_dir.length_squared() > 0.0:
		velocity = climb_dir * CLIMB_SPEED + into_wall
	else:
		# Hold position: only push into the wall, no other drift
		velocity = into_wall

# ── Normal walking / jumping physics ─────────────────────────────────────────
func _process_walking(delta: float) -> void:
	# ── Gravity ───────────────────────────────────────────────────────────
	if not is_on_floor():
		velocity += get_gravity() * delta

	# ── Jump (Space while on floor) ───────────────────────────────────────
	# Mid-air Space is reserved for wall-climbing, so only jump from floor
	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# ── WASD Movement ─────────────────────────────────────────────────────
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
