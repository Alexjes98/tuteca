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

const STICK_FORCE   := 20.0   # Velocity pushed into the surface to keep contact
const SURFACE_LERP  := 12.0   # How fast the surface normal rotates on transitions
const MODEL_LERP    := 14.0   # How fast the model re-aligns to the surface
const HOVER         := 0.38   # Capsule-center height above the surface
const GROUND_RAY    := 0.55   # Down-probe length (along -surface_normal)
const FWD_RAY       := 0.95   # Forward-probe length (wall detection)
const MODEL_SCALE   := 0.85   # Preserve the ModelRoot scale from tuteca.tscn
const STICK_COOLDOWN := 0.18  # Seconds after a jump before we may re-stick

# ── Stamina (shared by sprint + ceiling-hang) ─────────────────────────────────
const STAMINA_MAX      := 15.0   # Full stamina pool
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
# ── HUD / UI State ────────────────────────────────────────────────────────────
var _hud: CanvasLayer
var _stamina_fill: ColorRect
var _camo_container: Control
var _camo_fill: ColorRect

# ── Camouflage state ──────────────────────────────────────────────────────────
const CAMOUFLAGE_DELAY := 3.0
const CAMOUFLAGE_TRANSPARENCY := 0.9
const CAMOUFLAGE_FADE_SPEED := 1.0

var camouflage_transparency: float = 0.0
var _still_time: float = 0.0
var _meshes: Array[GeometryInstance3D] = []

var _camo_sound_player: AudioStreamPlayer3D

# ─────────────────────────────────────────────────────────────────────────────
# ── Skeleton procedural animation state ───────────────────────────────────────
var _skeleton: Skeleton3D
var _spine_bones: Array[int] = []
var _tail_bones: Array[int] = []
var _neck_bone: int = -1
var _front_left_leg: int = -1
var _front_right_leg: int = -1
var _rear_left_leg: int = -1
var _rear_right_leg: int = -1
var _bone_rest_rotations: Dictionary = {}
var _walk_phase: float = 0.0

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	super()
	add_to_group("lizards")
	_build_hud()
	_find_meshes(_model_root)
	_setup_skeleton()
	
	# Dynamically add camouflage_transparency to MultiplayerSynchronizer so it replicates
	for child in get_children():
		if child is MultiplayerSynchronizer:
			child.replication_config.add_property(".:camouflage_transparency")

	# Setup proximity spatial audio player for camouflage sound
	_camo_sound_player = AudioStreamPlayer3D.new()
	var stream := load("res://assets/sounds/u_xg7ssi08yr-gecko-371354.mp3") as AudioStreamMP3
	if stream:
		stream.loop = true
	_camo_sound_player.stream = stream
	_camo_sound_player.volume_db = -12.0  # Reduced base volume
	_camo_sound_player.unit_size = 4.5    # Slower drop-off
	_camo_sound_player.max_distance = 24.0 # Silent beyond 24 meters
	_camo_sound_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_camo_sound_player)

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var res := _find_skeleton(child)
		if res: return res
	return null

func _setup_skeleton() -> void:
	_skeleton = _find_skeleton(_model_root)
	if not _skeleton:
		return

	_spine_bones.clear()
	_tail_bones.clear()
	_bone_rest_rotations.clear()

	for i in _skeleton.get_bone_count():
		var b_name := _skeleton.get_bone_name(i)
		_bone_rest_rotations[i] = _skeleton.get_bone_rest(i).basis.get_rotation_quaternion()
		print("BONE REST ", i, " (", b_name, "): pos=", _skeleton.get_bone_rest(i).origin)
		
		if b_name in ["Spine", "Spine_02", "Spine_03"]:
			_spine_bones.append(i)
		elif b_name == "Neck":
			_neck_bone = i
		elif b_name == "Clavicle_L":
			_front_left_leg = i
		elif b_name == "Clavicle_R":
			_front_right_leg = i
		elif b_name in ["Bone.005", "Leg_L", "Thigh_L"]:
			_rear_left_leg = i
		elif b_name in ["Bone.014", "Leg_R", "Thigh_R"]:
			_rear_right_leg = i
		elif b_name in ["Bone.017", "Bone.018", "Bone.019", "Bone.020", "Bone.021"]:
			_tail_bones.append(i)

func _animate_skeleton(delta: float, is_moving: bool, is_sprinting: bool) -> void:
	if not _skeleton:
		return

	if is_moving:
		# Faster gait and shaking when sprinting vs walking
		var freq := 22.0 if is_sprinting else 12.0
		_walk_phase += delta * freq

		var body_shake := sin(_walk_phase)
		var leg_swing1 := sin(_walk_phase)
		var leg_swing2 := sin(_walk_phase + PI)
		
		# Spine undulation (side-to-side body shake)
		var body_shake_amp := 0.16 if is_sprinting else 0.09
		var spine_rot := Quaternion(Vector3.UP, body_shake * body_shake_amp)
		for b_idx in _spine_bones:
			if b_idx in _bone_rest_rotations:
				var rest: Quaternion = _bone_rest_rotations[b_idx]
				_skeleton.set_bone_pose_rotation(b_idx, rest * spine_rot)

		# Neck counter flex (keeps head pointing forward)
		if _neck_bone >= 0 and _neck_bone in _bone_rest_rotations:
			var neck_counter := Quaternion(Vector3.UP, -body_shake * (0.10 if is_sprinting else 0.05))
			_skeleton.set_bone_pose_rotation(_neck_bone, _bone_rest_rotations[_neck_bone] * neck_counter)

		# Tail waving / shaking behind body
		for t_i in range(_tail_bones.size()):
			var b_idx: int = _tail_bones[t_i]
			if b_idx in _bone_rest_rotations:
				var tail_phase := _walk_phase - (t_i + 1) * 0.4
				var tail_rot := Quaternion(Vector3.UP, sin(tail_phase) * (0.18 if is_sprinting else 0.10))
				_skeleton.set_bone_pose_rotation(b_idx, _bone_rest_rotations[b_idx] * tail_rot)

		# Leg paddling / swinging
		var swing_amp := 0.40 if is_sprinting else 0.24
		var lift_amp := 0.20 if is_sprinting else 0.12

		# Leg Pair 1: Front Left & Rear Right
		if _front_left_leg >= 0 and _front_left_leg in _bone_rest_rotations:
			var rot := Quaternion(Vector3.UP, leg_swing1 * swing_amp) * Quaternion(Vector3.RIGHT, maxf(0.0, leg_swing1) * lift_amp)
			_skeleton.set_bone_pose_rotation(_front_left_leg, _bone_rest_rotations[_front_left_leg] * rot)

		if _rear_right_leg >= 0 and _rear_right_leg in _bone_rest_rotations:
			var rot := Quaternion(Vector3.UP, leg_swing1 * swing_amp) * Quaternion(Vector3.RIGHT, maxf(0.0, leg_swing1) * lift_amp)
			_skeleton.set_bone_pose_rotation(_rear_right_leg, _bone_rest_rotations[_rear_right_leg] * rot)

		# Leg Pair 2: Front Right & Rear Left
		if _front_right_leg >= 0 and _front_right_leg in _bone_rest_rotations:
			var rot := Quaternion(Vector3.UP, leg_swing2 * swing_amp) * Quaternion(Vector3.RIGHT, maxf(0.0, leg_swing2) * lift_amp)
			_skeleton.set_bone_pose_rotation(_front_right_leg, _bone_rest_rotations[_front_right_leg] * rot)

		if _rear_left_leg >= 0 and _rear_left_leg in _bone_rest_rotations:
			var rot := Quaternion(Vector3.UP, leg_swing2 * swing_amp) * Quaternion(Vector3.RIGHT, maxf(0.0, leg_swing2) * lift_amp)
			_skeleton.set_bone_pose_rotation(_rear_left_leg, _bone_rest_rotations[_rear_left_leg] * rot)
	else:
		# Smoothly reset all bones to rest pose when standing still
		_walk_phase = 0.0
		for b_idx in _bone_rest_rotations:
			var cur_rot := _skeleton.get_bone_pose_rotation(b_idx)
			var target_rot: Quaternion = _bone_rest_rotations[b_idx]
			_skeleton.set_bone_pose_rotation(b_idx, cur_rot.slerp(target_rot, minf(1.0, 14.0 * delta)))

func _find_meshes(node: Node) -> void:
	if node is GeometryInstance3D:
		_meshes.append(node)
	for child in node.get_children():
		_find_meshes(child)


func _get_camera_up() -> Vector3:
	return Vector3.UP

func _wants_climb() -> bool:
	return not _is_typing() and (Input.is_action_pressed("gekko_climb") or Input.is_physical_key_pressed(KEY_CTRL))

# ─────────────────────────────────────────────────────────────────────────────
func _process_movement(delta: float) -> void:
	var is_moving := _input_vector() != Vector2.ZERO or velocity.length() > 0.2
	# Sprint: Shift, only while grounded on a surface, moving, and with stamina.
	_sprinting = _stuck and _stamina > 0.0 \
			and Input.is_physical_key_pressed(KEY_SHIFT) \
			and is_moving
	if _stuck:
		_walk_surface(delta)
	else:
		_air(delta)
	_orient_model(delta)
	_animate_skeleton(delta, is_moving and (_stuck or velocity.length() > 0.5), _sprinting)

# ─────────────────────────────────────────────────────────────────────────────
## Movement, surface detection and stick force while pinned to a surface.
func _walk_surface(delta: float) -> void:
	var space := get_world_3d().direct_space_state

	# Camera-relative input projected onto the current surface plane.
	var raw := _input_vector()
	var move_dir := _camera_move(raw, _surface_normal)
	var moving := move_dir.length() > 0.01
	if moving:
		move_dir = move_dir.normalized()
	var facing := move_dir if moving else _face_dir

	var target_normal := _surface_normal

	# 1. Wall ahead → wrap onto it (climb). Only allowed if Ctrl (_wants_climb) is held
	#    and normal differs enough from current up.
	if moving and _wants_climb():
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
			global_position = global_position.lerp(goal, 0.4)
		else:
			# Ground fell away: probe ahead-and-down or around edges to wrap outer corner.
			var probe := global_position + facing * 0.35
			var e_hit := _ray(space, probe, -_surface_normal, GROUND_RAY + 0.5)
			if not e_hit.is_empty():
				target_normal = e_hit.normal
			elif _wants_climb():
				# Try probing back towards our previous surface or curved edge
				var back_probe := global_position + facing * 0.35 - _surface_normal * 0.35
				var b_hit := _ray(space, back_probe, -facing, FWD_RAY + 0.4)
				if not b_hit.is_empty():
					target_normal = b_hit.normal
				else:
					# Fallback outer probe in facing direction turned inward
					var in_hit := _ray(space, probe, -facing, FWD_RAY + 0.4)
					if not in_hit.is_empty():
						target_normal = in_hit.normal
					else:
						_stuck = false
						velocity += get_gravity() * delta
						return
			else:
				# Nothing to stand on and not climbing — walk off into open air.
				_stuck = false
				velocity += get_gravity() * delta
				return

	# If target normal is a wall/ceiling (non-floor) but player is not holding Ctrl,
	# don't climb onto it!
	if target_normal.y < WALL_DOT and not _wants_climb():
		if _surface_normal.y < WALL_DOT:
			# Currently on a wall/ceiling and released Ctrl -> detach!
			_detach()
			return
		else:
			# Standing on floor, target surface is a wall, but no Ctrl -> keep current floor normal
			target_normal = _surface_normal

	# Rotate our up toward the detected surface, then rebuild movement on it.
	_surface_normal = _surface_normal.slerp(target_normal, minf(1.0, SURFACE_LERP * delta)).normalized()
	up_direction = _surface_normal

	# Stamina: clinging to walls/ceilings and/or sprinting drain it. On a wall or
	# ceiling, running dry forces a drop (the floor never costs stamina).
	_on_climb = _surface_normal.y < WALL_DOT
	_upside = _surface_normal.y < CEILING_DOT

	# Re-check: if we are on a climb surface and not holding Ctrl, detach.
	if _on_climb and not _wants_climb():
		_detach()
		return

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
		# If it's a wall or ceiling, only stick if holding Ctrl (_wants_climb)
		if n.y < WALL_DOT:
			if not _wants_climb() or _ceiling_lock > 0.0:
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
	if _is_typing():
		return raw
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
# ─────────────────────────────────────────────────────────────────────────────
# HUD/UI Setup
# ─────────────────────────────────────────────────────────────────────────────
func _build_hud() -> void:
	if not is_multiplayer_authority():
		return

	_hud = CanvasLayer.new()
	add_child(_hud)

	# 1. Stamina Bar Container (width 200, height 16, bottom center)
	var stamina_container := Control.new()
	stamina_container.name = "StaminaBar"
	stamina_container.anchor_left = 0.5
	stamina_container.anchor_top = 1.0
	stamina_container.anchor_right = 0.5
	stamina_container.anchor_bottom = 1.0
	stamina_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	stamina_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
	stamina_container.offset_left = -100
	stamina_container.offset_top = -80
	stamina_container.offset_right = 100
	stamina_container.offset_bottom = -64
	_hud.add_child(stamina_container)

	var stamina_bg := ColorRect.new()
	stamina_bg.color = Color(0.0, 0.0, 0.0, 0.5)
	stamina_bg.anchor_right = 1.0
	stamina_bg.anchor_bottom = 1.0
	stamina_bg.offset_right = 0
	stamina_bg.offset_bottom = 0
	stamina_container.add_child(stamina_bg)

	_stamina_fill = ColorRect.new()
	_stamina_fill.color = Color(0.3, 0.85, 0.3)
	_stamina_fill.anchor_bottom = 1.0
	_stamina_fill.offset_bottom = 0
	stamina_container.add_child(_stamina_fill)

	# 2. Camouflage Bar Container (directly below stamina, height 4)
	_camo_container = Control.new()
	_camo_container.name = "CamouflageBar"
	_camo_container.anchor_left = 0.5
	_camo_container.anchor_top = 1.0
	_camo_container.anchor_right = 0.5
	_camo_container.anchor_bottom = 1.0
	_camo_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_camo_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_camo_container.offset_left = -100
	_camo_container.offset_top = -64
	_camo_container.offset_right = 100
	_camo_container.offset_bottom = -60
	_hud.add_child(_camo_container)

	var camo_bg := ColorRect.new()
	camo_bg.color = Color(0.0, 0.0, 0.0, 0.5)
	camo_bg.anchor_right = 1.0
	camo_bg.anchor_bottom = 1.0
	camo_bg.offset_right = 0
	camo_bg.offset_bottom = 0
	_camo_container.add_child(camo_bg)

	_camo_fill = ColorRect.new()
	_camo_fill.color = Color(1.0, 1.0, 1.0)
	_camo_fill.anchor_bottom = 1.0
	_camo_fill.offset_bottom = 0
	_camo_container.add_child(_camo_fill)

# Position, aim-at-camera, and fill the bar. Visuals only → runs in _process.
func _process(delta: float) -> void:
	if is_multiplayer_authority():
		var is_still := _stuck and _input_vector().length() < 0.01 and velocity.slide(_surface_normal).length() < 0.05
		if is_still:
			_still_time += delta
		else:
			_still_time = 0.0
		
		var target_transparency := CAMOUFLAGE_TRANSPARENCY if _still_time >= CAMOUFLAGE_DELAY else 0.0
		camouflage_transparency = move_toward(camouflage_transparency, target_transparency, CAMOUFLAGE_FADE_SPEED * delta)
		
	for mesh in _meshes:
		if is_multiplayer_authority():
			mesh.transparency = camouflage_transparency
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		else:
			# For remote clients (like the cat), scale transparency to leave 1% opacity (max 0.99 transparent)
			var remote_transparency := camouflage_transparency / CAMOUFLAGE_TRANSPARENCY
			var t := clampf(remote_transparency, 0.0, 0.99)
			mesh.transparency = t
			if t > 0.95:
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			else:
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	# Proximity audio: play if fully/almost fully camouflaged
	if _camo_sound_player != null:
		var is_fully_camouflaged := camouflage_transparency >= CAMOUFLAGE_TRANSPARENCY - 0.01
		if is_fully_camouflaged:
			if not _camo_sound_player.playing:
				_camo_sound_player.play()
		else:
			if _camo_sound_player.playing:
				_camo_sound_player.stop()

	if not is_multiplayer_authority() or _hud == null:
		return

	# Update stamina bar fill & color
	var frac := clampf(_stamina / STAMINA_MAX, 0.0, 1.0)
	_stamina_fill.anchor_right = frac
	_stamina_fill.offset_right = 0
	_stamina_fill.color = Color(0.9, 0.2, 0.15).lerp(Color(0.3, 0.85, 0.3), frac)

	# Update camouflage bar visibility and fill
	var show_camo := _still_time > 0.0 or camouflage_transparency > 0.0
	_camo_container.visible = show_camo
	if show_camo:
		var camo_frac := clampf(_still_time / CAMOUFLAGE_DELAY, 0.0, 1.0)
		_camo_fill.anchor_right = camo_frac
		_camo_fill.offset_right = 0

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

# ─────────────────────────────────────────────────────────────────────────────
# RPC overrides
# ─────────────────────────────────────────────────────────────────────────────
@rpc("any_peer", "call_local", "reliable")
func rpc_apply_knockback(force: Vector3) -> void:
	super(force)
	if is_multiplayer_authority():
		# Force out of camouflage immediately on hit
		_still_time = 0.0
		camouflage_transparency = 0.0
