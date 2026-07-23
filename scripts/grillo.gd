extends Node3D

## Grillo (Cricket) game object script.
## Manages surface placement and alignment perpendicular to surface normals.

@onready var character_body: CharacterBody3D = $CharacterBody3D
@onready var collision_shape: CollisionShape3D = $CharacterBody3D/CollisionShape3D

## SphereShape3D radius in grillo.tscn is ~0.59816.
## Pushes the cricket origin along surface normal so the bottom contact point touches the mesh.
const SURFACE_OFFSET := 0.59816116

## Place and orient cricket on a surface given its hit position and normal vector.
func place_on_surface(hit_pos: Vector3, normal: Vector3, rng: RandomNumberGenerator = null) -> void:
	var n := normal.normalized()
	
	# Generate a random direction vector perpendicular to surface normal
	var random_dir: Vector3
	if rng:
		random_dir = Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		).normalized()
	else:
		random_dir = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		).normalized()
	
	var tangent := random_dir.cross(n)
	if tangent.length_squared() < 0.001:
		var ref := Vector3.FORWARD if abs(n.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		tangent = ref.cross(n)
	tangent = tangent.normalized()
	
	var bitangent := n.cross(tangent).normalized()
	
	# Basis: Y axis = surface normal (perpendicular to surface)
	# X axis = tangent, Z axis = bitangent
	var b := Basis(tangent, n, bitangent).orthonormalized()
	
	# Position: surface hit location + normal * offset so bottom touches the mesh surface cleanly
	var surface_pos := hit_pos + n * SURFACE_OFFSET
	
	global_transform = Transform3D(b, surface_pos)
