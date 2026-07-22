extends "res://scripts/base_character.gd"

## Gekko (Tuteca) — extends BaseCharacter with wall-climbing ability.
##
## Gekko-specific input action:
##   • "gekko_climb" (Space mid-air near wall) → stick to and traverse walls.
##
## _process_movement() is overridden to intercept the Space-held + on-wall
## condition before calling super() for normal gravity/WASD.

const CLIMB_SPEED := 3.0   # Up / down / lateral speed while wall-climbing
const CLIMB_GRACE_TIME := 0.15  # Time in seconds we tolerate losing wall contact

# ── Wall-climbing state ────────────────────────────────────────────────────────
# true while the Gekko is actively sticking to a wall.
var _climbing: bool = false
# Normal of the wall being climbed (points away from the wall, toward the player).
var _wall_normal: Vector3 = Vector3.ZERO
# Accumulated time since we lost contact with the wall
var _climb_lost_time: float = 0.0

# ─────────────────────────────────────────────────────────────────────────────
# Override: detect and handle wall-climbing before falling back to normal movement.
func _process_movement(delta: float) -> void:
	var climb_held: bool = Input.is_action_pressed("gekko_climb")

	# ── Wall-climbing detection ───────────────────────────────────────────
	if climb_held and not is_on_floor():
		if is_on_wall():
			_climbing    = true
			_wall_normal = get_wall_normal()
			_climb_lost_time = 0.0
		elif _climbing:
			# Lost contact but button is held: start counting grace period.
			_climb_lost_time += delta
			if _climb_lost_time > CLIMB_GRACE_TIME:
				_climbing    = false
				_wall_normal = Vector3.ZERO
				_climb_lost_time = 0.0
	else:
		# Key released or landed: always exit climbing.
		_climbing    = false
		_wall_normal = Vector3.ZERO
		_climb_lost_time = 0.0

	if _climbing:
		_process_climbing()
	else:
		super(delta)   # normal gravity + jump + WASD from BaseCharacter

# ─────────────────────────────────────────────────────────────────────────────
# Refresh wall normal after physics resolution (prevents flicker during rotate_y).
func _post_physics() -> void:
	if _climbing and is_on_wall():
		_wall_normal = get_wall_normal()

# ─────────────────────────────────────────────────────────────────────────────
# Climbing physics — called only while _climbing is true.
func _process_climbing() -> void:
	# Nullify gravity while hugging the wall.
	velocity.y = 0.0

	# A small push into the wall keeps is_on_wall() true next frame.
	# Only push if we actually have wall contact, otherwise we would float/drift.
	var into_wall: Vector3 = -_wall_normal * 0.5 if is_on_wall() else Vector3.ZERO

	# move_forward / move_back → climb up / down
	var vertical: float = 0.0
	if Input.is_action_pressed("move_forward"): vertical =  1.0
	if Input.is_action_pressed("move_back"):    vertical = -1.0

	# move_left / move_right → strafe laterally along the wall surface.
	# Tangent of the wall itself (UP × normal): horizontal, hugs the wall
	# plane, and works no matter where the body or camera are pointing.
	var wall_right := Vector3.UP.cross(_wall_normal).normalized()
	var lateral: float = 0.0
	if Input.is_action_pressed("move_left"):  lateral = -1.0
	if Input.is_action_pressed("move_right"): lateral =  1.0

	# Combine vertical and lateral movement on the wall plane.
	var climb_dir: Vector3 = (Vector3.UP * vertical + wall_right * lateral).normalized()
	if climb_dir.length_squared() > 0.0:
		velocity = climb_dir * CLIMB_SPEED + into_wall
	else:
		# Hold position: only push into the wall, no other drift.
		velocity = into_wall

