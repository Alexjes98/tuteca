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

# ─────────────────────────────────────────────────────────────────────────────
## Cat-specific abilities run each physics frame after shared movement.
func _process_special(delta: float) -> void:
	# Tick down the pounce cooldown
	if _pounce_timer > 0.0:
		_pounce_timer = max(_pounce_timer - delta, 0.0)

	# ── Pounce (cat_pounce) ───────────────────────────────────────────────
	if Input.is_action_just_pressed("cat_pounce") and _pounce_timer <= 0.0:
		_do_pounce()

	# ── Scratch (cat_scratch) ─────────────────────────────────────────────
	if Input.is_action_just_pressed("cat_scratch"):
		_do_scratch()

# ─────────────────────────────────────────────────────────────────────────────
## Pounce: burst forward in the direction the cat is facing.
func _do_pounce() -> void:
	# -Z is the forward axis in Godot's default basis
	var forward := -transform.basis.z.normalized()
	velocity += forward * POUNCE_FORCE
	velocity.y = POUNCE_UP_KICK
	_pounce_timer = POUNCE_COOLDOWN
	print("[Cat] Pounce! Cooldown: %.1fs" % POUNCE_COOLDOWN)

# ─────────────────────────────────────────────────────────────────────────────
## Scratch: placeholder — ready for hit detection, animation, sound, etc.
func _do_scratch() -> void:
	# TODO: play scratch animation, check hit area, apply damage to targets
	print("[Cat] Scratch!")
