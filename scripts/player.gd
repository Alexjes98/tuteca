extends "res://scripts/base_character.gd"

## Gekko (Tuteca) — a surface-walker that treats walls and ceilings as floor.
##
## Behaviour:
##   • While "stuck" the gecko has no world gravity. A stick force pins it to
##     whatever surface it stands on, and WASD moves along that surface plane.
##   • Walking into a wall wraps the gecko onto it (the wall becomes the new
##     floor). The same wrap carries it across inner corners onto ceilings.
##   • Jump (Space) launches away from the current surface; world gravity then
##     takes over until it lands on any surface and re-sticks.
##   • The visual model re-aligns so its "up" matches the surface normal —
##     vertical on walls, upside-down on ceilings.
##
## Fully overrides BaseCharacter._process_movement (never calls super) because
## gravity, movement and model orientation all become surface-relative here.

const STICK_FORCE   := 8.0    # Velocity pushed into the surface to keep contact
const SURFACE_LERP  := 12.0   # How fast the surface normal rotates on transitions
const MODEL_LERP    := 14.0   # How fast the model re-aligns to the surface
const HOVER         := 0.24   # Capsule-center height above the surface
const GROUND_RAY    := 0.55   # Down-probe length (along -surface_normal)
const FWD_RAY       := 0.95   # Forward-probe length (wall detection)
const MODEL_SCALE   := 0.85   # Preserve the ModelRoot scale from tuteca.tscn
const STICK_COOLDOWN := 0.18  # Seconds after a jump before we may re-stick

# ── Stamina (shared by sprint + ceiling-hang) ─────────────────────────────────
const STAMINA_MAX      := 10.0   # Full stamina pool
const CLIMB_DRAIN      := 1.0    # Stamina/sec while clinging to a wall
const CEILING_MULT     := 2.0    # Upside-down drains this × the wall rate
const SPRINT_DRAIN     := 1.5    # Stamina/sec drained while sprinting
const STAMINA_RECHARGE := 1.0    # Stamina/sec refilled when neither draining
const SPRINT_MULT      := 1.8    # Speed multiplier while sprinting
const CEILING_LOCKOUT  := 1.2    # Seconds it can't re-stick to a wall/ceiling after dropping
const WALL_DOT         := 0.5    # surface_normal.y below this = wall or ceiling (not floor)
const CEILING_DOT      := -0.35  # surface_normal.y below this counts as "upside-down"
const BAR_OFFSET       := 0.6    # Meters above the body to float the stamina bar
const BAR_WIDTH        := 0.5
const BAR_HEIGHT       := 0.08

# ── Surface-walking state ─────────────────────────────────────────────────────
## Normal of the surface we're glued to; this is our local "up". Starts as world up.
var _surface_normal: Vector3 = Vector3.UP
## true while pinned to a surface; false while airborne (jumping / falling).
var _stuck: bool = true
## Last horizontal facing direction on the surface plane (for idle orientation).
var _face_dir: Vector3 = Vector3.FORWARD
## Counts down after a jump so we don't instantly re-stick to what we left.
var _stick_cd: float = 0.0

# ── Stamina state ─────────────────────────────────────────────────────────────
## Shared stamina pool: drains while sprinting or hanging, refills otherwise.
var _stamina: float = STAMINA_MAX
## Blocks re-sticking to a ceiling right after stamina forced a drop.
var _ceiling_lock: float = 0.0
## true while pinned to a wall or ceiling (not the floor); costs stamina.
var _on_climb: bool = false
## true while pinned upside-down (ceiling); drains stamina at CEILING_MULT.
var _upside: bool = false
## true while sprinting (Shift held, moving, stamina left).
var _sprinting: bool = false
## World-space stamina bar floated above the body (built in _ready).
var _bar_root: Node3D
var _bar_fill: MeshInstance3D

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	super()
	add_to_group("lizards")
	_build_ceiling_bar()

func _get_camera_up() -> Vector3:
	return _surface_normal if _stuck else Vector3.UP

# ─────────────────────────────────────────────────────────────────────────────
func _process_movement(delta: float) -> void:
	# Sprint: Shift, only while grounded on a surface, moving, and with stamina.
	_sprinting = _stuck and _stamina > 0.0 \
			and Input.is_physical_key_pressed(KEY_SHIFT) \
			and _input_vector() != Vector2.ZERO
	if _stuck:
		_walk_surface(delta)
	else:
		_air(delta)
	_orient_model(delta)

# ─────────────────────────────────────────────────────────────────────────────
## Movement, surface detection and stick force while pinned to a surface.
func _walk_surface(delta: float) -> void:
	var space := get_world_3d().direct_space_state

	# Camera-relative input projected onto the current surface plane. Using the
	# camera's full basis (not just yaw) means looking up a wall and pressing W
	# drives the gecko up it — free movement across the surface, not just sideways.
	var raw := _input_vector()
	var move_dir := _camera_move(raw, _surface_normal)
	var moving := move_dir.length() > 0.01
	if moving:
		move_dir = move_dir.normalized()
	var facing := move_dir if moving else _face_dir

	var target_normal := _surface_normal

	# 1. Wall ahead → wrap onto it (climb). Only counts as a new surface if its
	#    normal differs enough from our current up.
	if moving:
		var f_hit := _ray(space, global_position, facing, FWD_RAY)
		if not f_hit.is_empty() and f_hit.normal.dot(_surface_normal) < 0.7:
			target_normal = f_hit.normal

	# 2. Otherwise follow the ground under us (slopes, steps, gentle wrap).
	if target_normal == _surface_normal:
		var g_hit := _ray(space, global_position, -_surface_normal, GROUND_RAY)
		if not g_hit.is_empty():
			target_normal = g_hit.normal
			# Ease toward the hover height so we hug the surface without snapping.
			var goal: Vector3 = g_hit.position + _surface_normal * HOVER
			global_position = global_position.lerp(goal, 0.3)
		else:
			# Ground fell away: probe just ahead-and-down to wrap an outer edge.
			var probe := global_position + facing * 0.3
			var e_hit := _ray(space, probe, -_surface_normal, GROUND_RAY + 0.4)
			if not e_hit.is_empty():
				target_normal = e_hit.normal
			else:
				# Nothing to stand on — we walked off into open air.
				_stuck = false
				velocity += get_gravity() * delta
				return

	# Rotate our up toward the detected surface, then rebuild movement on it.
	_surface_normal = _surface_normal.slerp(target_normal, minf(1.0, SURFACE_LERP * delta)).normalized()
	up_direction = _surface_normal

	# Stamina: clinging to walls/ceilings and/or sprinting drain it. On a wall or
	# ceiling, running dry forces a drop (the floor never costs stamina).
	_on_climb = _surface_normal.y < WALL_DOT
	_upside = _surface_normal.y < CEILING_DOT
	_update_stamina(delta)
	if _on_climb and _stamina <= 0.0:
		_detach()
		_ceiling_lock = CEILING_LOCKOUT   # can't grab a wall/ceiling again yet
		return

	var speed := SPEED * (SPRINT_MULT if _sprinting else 1.0)
	var vel := Vector3.ZERO
	if moving:
		var md := _project(facing, _surface_normal)
		if md.length() > 0.01:
			md = md.normalized()
			_face_dir = md
			vel = md * speed
	else:
		# If standing still, face the camera's projected look direction on the surface
		var cam_forward := -camera.global_transform.basis.z
		var md := _project(cam_forward, _surface_normal)
		if md.length() > 0.01:
			_face_dir = md.normalized()
			
	vel += -_surface_normal * STICK_FORCE   # keep contact
	velocity = vel

	# Jump: launch away from the surface. World gravity then pulls us off.
	if Input.is_action_just_pressed("jump"):
		_detach()

# ─────────────────────────────────────────────────────────────────────────────
## Break away from the current surface with an outward launch.
func _detach() -> void:
	_stuck = false
	_stick_cd = STICK_COOLDOWN
	up_direction = Vector3.UP
	# Keep a little tangential momentum, add the outward jump kick.
	var tangential := velocity + _surface_normal * STICK_FORCE   # remove the stick component
	velocity = tangential * 0.4 + _surface_normal * JUMP_VELOCITY

# ─────────────────────────────────────────────────────────────────────────────
## Airborne: world gravity plus light air control.
func _air(delta: float) -> void:
	up_direction = Vector3.UP
	_on_climb = false
	_upside = false
	_update_stamina(delta)   # airborne: neither clinging nor sprinting → recharges
	if _stick_cd > 0.0:
		_stick_cd = maxf(_stick_cd - delta, 0.0)
	if _ceiling_lock > 0.0:
		_ceiling_lock = maxf(_ceiling_lock - delta, 0.0)
	velocity += get_gravity() * delta

	var raw := _input_vector()
	if raw != Vector2.ZERO:
		var world_dir := _camera_move(raw, Vector3.UP).normalized()
		var horiz := Vector3(velocity.x, 0.0, velocity.z)
		horiz = horiz.move_toward(world_dir * SPEED, SPEED * 2.0 * delta)
		velocity.x = horiz.x
		velocity.z = horiz.z
		_face_dir = world_dir

# ─────────────────────────────────────────────────────────────────────────────
## After move_and_slide: if airborne and we touched a surface, stick to it.
func _post_physics() -> void:
	if _stuck or _stick_cd > 0.0:
		return
	for i in range(get_slide_collision_count()):
		var n := get_slide_collision(i).get_normal()
		# While the lockout is active, refuse to grab any wall/ceiling again.
		if n.y < WALL_DOT and _ceiling_lock > 0.0:
			continue
		# Only stick when moving into the surface (not scraping away from it).
		if velocity.dot(n) < 0.5:
			_surface_normal = n
			_stuck = true
			up_direction = n
			velocity -= velocity.dot(n) * n   # kill the into-surface component
			return

# ─────────────────────────────────────────────────────────────────────────────
## Align the model so its up = surface normal and its -Z = facing direction.
func _orient_model(delta: float) -> void:
	var up := _surface_normal if _stuck else Vector3.UP
	var fwd := _project(_face_dir, up)
	if fwd.length() < 0.01:
		# Facing is parallel to up (rare) — pick any perpendicular axis.
		fwd = _project(Vector3.FORWARD, up)
		if fwd.length() < 0.01:
			fwd = _project(Vector3.RIGHT, up)
	fwd = fwd.normalized()

	var x := fwd.cross(up).normalized()
	var target := Basis(x, up, -fwd)
	var cur := _model_root.transform.basis.orthonormalized()
	var blended := cur.slerp(target, minf(1.0, MODEL_LERP * delta))
	_model_root.transform.basis = blended.scaled(Vector3(MODEL_SCALE, MODEL_SCALE, MODEL_SCALE))

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────
func _input_vector() -> Vector2:
	var raw := Vector2.ZERO
	if Input.is_action_pressed("move_forward"): raw.y -= 1.0
	if Input.is_action_pressed("move_back"):    raw.y += 1.0
	if Input.is_action_pressed("move_left"):    raw.x -= 1.0
	if Input.is_action_pressed("move_right"):   raw.x += 1.0
	return raw

## Project a vector onto the plane whose normal is n (removes the n component).
func _project(v: Vector3, n: Vector3) -> Vector3:
	return v - v.dot(n) * n

## Build a movement vector from WASD using the camera's real orientation
## (forward + right, pitch included), projected onto the surface plane n.
func _camera_move(raw: Vector2, n: Vector3) -> Vector3:
	var cb := camera.global_transform.basis
	var dir := cb.x * raw.x + (-cb.z) * (-raw.y)   # right * A/D + forward * W/S
	return _project(dir, n)

## Cast a ray from `from` along `dir` for `len`, excluding this body.
## Returns the intersect_ray dict (empty if nothing hit).
func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, len: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * len)
	q.exclude = [get_rid()]
	q.collision_mask = collision_mask
	return space.intersect_ray(q)

# ─────────────────────────────────────────────────────────────────────────────
# Ceiling-timer bar (world-space, floats above the body)
# ─────────────────────────────────────────────────────────────────────────────
func _build_ceiling_bar() -> void:
	_bar_root = Node3D.new()
	add_child(_bar_root)
	_bar_root.add_child(_make_bar_quad(Color(0.0, 0.0, 0.0, 0.7)))   # background
	_bar_fill = _make_bar_quad(Color(0.95, 0.35, 0.15))              # depleting fill
	_bar_fill.position.z = 0.002   # sit just in front of the background
	_bar_root.add_child(_bar_fill)
	_bar_root.visible = false

func _make_bar_quad(col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # visible from both sides
	mat.no_depth_test = true                       # draw over walls
	mi.material_override = mat
	return mi

# Position, aim-at-camera, and fill the bar. Visuals only → runs in _process.
func _process(_dt: float) -> void:
	if _bar_root == null:
		return
	# The stamina bar is always shown for the controlling player.
	var show := is_multiplayer_authority()
	_bar_root.visible = show
	if not show:
		return
	_bar_root.global_position = global_position + Vector3.UP * BAR_OFFSET
	var cam := get_viewport().get_camera_3d()
	if cam:
		# Billboard the whole bar so its local X stays horizontal on screen.
		var dir := (cam.global_position - _bar_root.global_position).normalized()
		var up_ref := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
		_bar_root.look_at(cam.global_position, up_ref)
	# Deplete right-to-left, keeping the left edge anchored.
	var frac := clampf(_stamina / STAMINA_MAX, 0.0, 1.0)
	_bar_fill.scale.x = maxf(frac, 0.0001)
	_bar_fill.position.x = -BAR_WIDTH * (1.0 - frac) * 0.5
	# Green when full, red when low.
	var mat := _bar_fill.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(0.9, 0.2, 0.15).lerp(Color(0.3, 0.85, 0.3), frac)

# ─────────────────────────────────────────────────────────────────────────────
## Drain stamina while clinging to walls/ceilings and/or sprinting; recharge otherwise.
func _update_stamina(delta: float) -> void:
	var drain := 0.0
	if _on_climb:
		drain += CLIMB_DRAIN * (CEILING_MULT if _upside else 1.0)
	if _sprinting:
		drain += SPRINT_DRAIN
	if drain > 0.0:
		_stamina = maxf(_stamina - drain * delta, 0.0)
	else:
		_stamina = minf(_stamina + STAMINA_RECHARGE * delta, STAMINA_MAX)
