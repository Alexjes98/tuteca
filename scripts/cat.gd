extends "res://scripts/base_character.gd"

## Cat — extends BaseCharacter with cat-specific abilities.
##
## Cat-specific input actions:
##   • "cat_pounce"  (Shift)      → forward velocity burst with slight upward kick.
##   • "cat_scratch" (E / LMB)   → placeholder for damage / animation trigger.
##
## Both abilities are ready to be expanded with animations, hit detection,
## sound effects, or state-machine transitions.

const POUNCE_FORCE    := 12.0   # Horizontal burst strength
const POUNCE_UP_KICK  := 2.5    # Upward component added on pounce
const POUNCE_COOLDOWN := 2.0    # Seconds between pounces

var _pounce_timer: float = 0.0   # Counts down to 0 when cooldown is active

var _scratch_cast: ShapeCast3D
var _default_fov: float = 75.0
var _shift_down: bool = false

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	super()
	
	if is_multiplayer_authority() and camera:
		_default_fov = camera.fov
	
	# Instantiate and configure ShapeCast3D for scratch hit detection
	_scratch_cast = ShapeCast3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5  # Very tight radius for close melee range
	_scratch_cast.shape = sphere
	
	# Cast forward relative to the character body (very short range)
	_scratch_cast.target_position = Vector3(0, 0, -1.0)
	
	# Avoid hitting ourselves
	_scratch_cast.add_exception(self)
	_scratch_cast.enabled = false  # Update manually for performance
	
	# Add directly to the unscaled self node
	add_child(_scratch_cast)

# ─────────────────────────────────────────────────────────────────────────────
## Cat-specific abilities run each physics frame after shared movement.
func _process_special(delta: float) -> void:
	# Tick down the pounce cooldown
	if _pounce_timer > 0.0:
		_pounce_timer = max(_pounce_timer - delta, 0.0)

	# Smoothly return camera FOV to default after a pounce stretch (longer transition)
	if is_multiplayer_authority() and camera and camera.fov > _default_fov:
		camera.fov = lerp(camera.fov, _default_fov, 4.0 * delta)
		if camera.fov - _default_fov < 0.1:
			camera.fov = _default_fov

	# Programmatic Shift-key fallback to bypass any InputMap binding issues
	var shift_just_pressed := false
	var shift_held := Input.is_physical_key_pressed(KEY_SHIFT)
	if shift_held and not _shift_down:
		shift_just_pressed = true
	_shift_down = shift_held

	# Debug print input capture
	if Input.is_action_just_pressed("cat_pounce") or shift_just_pressed:
		print("[Cat Debug] cat_pounce action detected! Timer: %.1f" % _pounce_timer)

	# ── Pounce (cat_pounce) ───────────────────────────────────────────────
	if (Input.is_action_just_pressed("cat_pounce") or shift_just_pressed) and _pounce_timer <= 0.0:
		_do_pounce()

	# ── Scratch (cat_scratch) ─────────────────────────────────────────────
	if Input.is_action_just_pressed("cat_scratch"):
		_do_scratch()

# ─────────────────────────────────────────────────────────────────────────────
## Pounce: burst forward in the direction the cat is facing.
func _do_pounce() -> void:
	# The body never rotates (free-look camera), so "facing" lives on the
	# visual model — pounce toward the model's -Z.
	var forward := -_model_root.transform.basis.z.normalized()
	velocity += forward * POUNCE_FORCE
	velocity.y = POUNCE_UP_KICK
	_pounce_timer = POUNCE_COOLDOWN
	
	# Apply FOV speed stretch locally (subtler 90.0 FOV)
	if is_multiplayer_authority() and camera:
		camera.fov = 90.0
		
	print("[Cat] Pounce! Cooldown: %.1fs" % POUNCE_COOLDOWN)

# ─────────────────────────────────────────────────────────────────────────────
## Scratch: detects targets in front and applies a multiplayer knockback.
func _do_scratch() -> void:
	print("[Cat] Scratch triggered!")
	
	# Align the shapecast with the model's rotation and position (ignoring 18x scale)
	_scratch_cast.rotation.y = _model_root.rotation.y
	_scratch_cast.position = _model_root.position
	
	# Force query
	_scratch_cast.force_shapecast_update()
	
	if _scratch_cast.is_colliding():
		print("[Cat Debug] ShapeCast is colliding with %d objects" % _scratch_cast.get_collision_count())
		for i in range(_scratch_cast.get_collision_count()):
			var hit_collider = _scratch_cast.get_collider(i)
			if hit_collider:
				var dist := global_position.distance_to(hit_collider.global_position)
				print("[Cat Debug]   Hit object name: '%s', distance: %.2fm, has_knockback: %s" % 
						[hit_collider.name, dist, hit_collider.has_method("rpc_apply_knockback")])
				
				if hit_collider != self and hit_collider.has_method("rpc_apply_knockback"):
					# Calculate knockback direction
					var diff: Vector3 = hit_collider.global_position - global_position
					diff.y = 0.0  # Horizontal impulse
					var knockback_dir: Vector3 = diff.normalized()
					if knockback_dir.length_squared() == 0.0:
						knockback_dir = -_model_root.transform.basis.z.normalized()
					
					# High knockback force to throw target, plus a vertical lift
					var knockback_force = (knockback_dir * 18.0) + Vector3(0, 6.0, 0)
					
					# Apply force to target via RPC
					var target_authority = hit_collider.get_multiplayer_authority()
					hit_collider.rpc_apply_knockback.rpc_id(target_authority, knockback_force)
					
					# Spawn explosion on all peers at hit location
					rpc_spawn_explosion.rpc(hit_collider.global_position)
					print("[Cat] Hit %s! Applying knockback: %s" % [hit_collider.name, knockback_force])
