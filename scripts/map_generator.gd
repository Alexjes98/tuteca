extends Node3D

## Procedural House Map Generator
## Encloses the 200x200 space in walls/ceiling, and spawns giant furniture.
## Implements cinema-grade lighting, SSAO, glow, and warm room lights.
## Uses a fixed seed (12345) to ensure deterministic generation on all peers.

const SEED := 12345
const MAP_SIZE := 200.0
const ROOM_HEIGHT := 60.0

# Materials
var _floor_mat: StandardMaterial3D
var _wall_mat: StandardMaterial3D
var _wood_mat: StandardMaterial3D
var _wood_light_mat: StandardMaterial3D
var _fabric_red_mat: StandardMaterial3D
var _fabric_blue_mat: StandardMaterial3D
var _pillow_mat: StandardMaterial3D
var _screen_mat: StandardMaterial3D
var _plastic_mat: StandardMaterial3D

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Clear any editor placeholder children under this Map node
	for child in get_children():
		child.queue_free()
		
	_setup_environment()
	_setup_materials()
	_generate_map()

# ─────────────────────────────────────────────────────────────────────────────
func _setup_environment() -> void:
	# Dim the global DirectionalLight3D to simulate night/cozy indoor atmosphere
	var dir_light = get_parent().find_child("DirectionalLight3D", true, false)
	if dir_light and dir_light is DirectionalLight3D:
		dir_light.light_energy = 0.1
		dir_light.light_color = Color(0.6, 0.7, 0.9)  # Cool moonlight
	
	# Programmatic WorldEnvironment setup for AAA post-processing
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)  # Dark night outside
	
	# Cinematic Tonemapping
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	
	# Glow & Bloom
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_strength = 1.0
	env.glow_bloom = 0.12
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	
	# Screen-Space Ambient Occlusion (SSAO) for contact shadows (adds huge depth)
	env.ssao_enabled = true
	env.ssao_radius = 3.0
	env.ssao_intensity = 4.0
	
	# Screen-Space Reflections (SSR) for shiny table tops
	env.ssr_enabled = true
	
	world_env.environment = env
	add_child(world_env)
	
	# Spawn 4 warm indoor ceiling lights
	var light_positions := [
		Vector3(-50.0, ROOM_HEIGHT - 5.0, -50.0),
		Vector3(50.0, ROOM_HEIGHT - 5.0, -50.0),
		Vector3(-50.0, ROOM_HEIGHT - 5.0, 50.0),
		Vector3(50.0, ROOM_HEIGHT - 5.0, 50.0)
	]
	
	for l_pos in light_positions:
		var light := OmniLight3D.new()
		light.position = l_pos
		light.light_color = Color(1.0, 0.88, 0.75)  # Warm tungsten light
		light.light_energy = 12.0
		light.omni_range = 120.0
		light.shadow_enabled = true
		light.shadow_bias = 0.05
		add_child(light)

# ─────────────────────────────────────────────────────────────────────────────
func _setup_materials() -> void:
	# Floor mat (warm wood floor parquet color)
	_floor_mat = StandardMaterial3D.new()
	_floor_mat.albedo_color = Color(0.28, 0.18, 0.1)
	_floor_mat.roughness = 0.7
	
	# Wall mat (cream/white wallpaper tone)
	_wall_mat = StandardMaterial3D.new()
	_wall_mat.albedo_color = Color(0.9, 0.88, 0.82)
	_wall_mat.roughness = 0.95
	
	# Wood mat (dark mahogany)
	_wood_mat = StandardMaterial3D.new()
	_wood_mat.albedo_color = Color(0.22, 0.12, 0.05)
	_wood_mat.roughness = 0.25  # Slightly shiny polished wood
	_wood_mat.metallic = 0.05
	
	# Wood mat (oak wood)
	_wood_light_mat = StandardMaterial3D.new()
	_wood_light_mat.albedo_color = Color(0.48, 0.32, 0.18)
	_wood_light_mat.roughness = 0.4
	
	# Fabrics
	_fabric_red_mat = StandardMaterial3D.new()
	_fabric_red_mat.albedo_color = Color(0.72, 0.18, 0.18)  # Crimson blanket
	_fabric_red_mat.roughness = 0.85
	
	_fabric_blue_mat = StandardMaterial3D.new()
	_fabric_blue_mat.albedo_color = Color(0.18, 0.32, 0.55)  # Cozy sofa fabric
	_fabric_blue_mat.roughness = 0.8
	
	# Pillows / Sheets
	_pillow_mat = StandardMaterial3D.new()
	_pillow_mat.albedo_color = Color(0.88, 0.88, 0.88)
	_pillow_mat.roughness = 0.9
	
	# TV Screen
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.albedo_color = Color(0.04, 0.04, 0.05)
	_screen_mat.roughness = 0.1
	_screen_mat.metallic = 0.9
	
	# TV Frame / General Plastic
	_plastic_mat = StandardMaterial3D.new()
	_plastic_mat.albedo_color = Color(0.1, 0.1, 0.11)
	_plastic_mat.roughness = 0.5

# ─────────────────────────────────────────────────────────────────────────────
func _generate_map() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	
	# 1. Floor
	_spawn_block(Vector3(0.0, -0.5, 0.0), Vector3(MAP_SIZE, 1.0, MAP_SIZE), _floor_mat)
	
	# 2. Four Enclosing Walls & Ceiling
	_spawn_block(Vector3(0.0, ROOM_HEIGHT / 2.0, -MAP_SIZE / 2.0), Vector3(MAP_SIZE, ROOM_HEIGHT, 2.0), _wall_mat)
	_spawn_block(Vector3(0.0, ROOM_HEIGHT / 2.0, MAP_SIZE / 2.0), Vector3(MAP_SIZE, ROOM_HEIGHT, 2.0), _wall_mat)
	_spawn_block(Vector3(MAP_SIZE / 2.0, ROOM_HEIGHT / 2.0, 0.0), Vector3(2.0, ROOM_HEIGHT, MAP_SIZE), _wall_mat)
	_spawn_block(Vector3(-MAP_SIZE / 2.0, ROOM_HEIGHT / 2.0, 0.0), Vector3(2.0, ROOM_HEIGHT, MAP_SIZE), _wall_mat)
	_spawn_block(Vector3(0.0, ROOM_HEIGHT + 0.5, 0.0), Vector3(MAP_SIZE, 1.0, MAP_SIZE), _wall_mat)

	# 3. Baseboards (wood trims at bottom of walls to look finished)
	var bs_h := 1.5
	var bs_d := 0.6
	_spawn_block(Vector3(0.0, bs_h / 2.0, -MAP_SIZE / 2.0 + 1.0), Vector3(MAP_SIZE, bs_h, bs_d), _wood_mat)
	_spawn_block(Vector3(0.0, bs_h / 2.0, MAP_SIZE / 2.0 - 1.0), Vector3(MAP_SIZE, bs_h, bs_d), _wood_mat)
	_spawn_block(Vector3(MAP_SIZE / 2.0 - 1.0, bs_h / 2.0, 0.0), Vector3(bs_d, bs_h, MAP_SIZE), _wood_mat)
	_spawn_block(Vector3(-MAP_SIZE / 2.0 + 1.0, bs_h / 2.0, 0.0), Vector3(bs_d, bs_h, MAP_SIZE), _wood_mat)

	# 4. Giant Bookshelf (Highly detailed)
	var shelf_x := -60.0
	var shelf_z := -MAP_SIZE / 2.0 + 5.0
	var shelf_w := 60.0
	var shelf_h := 38.0
	var shelf_d := 9.0
	# Backboard
	_spawn_block(Vector3(shelf_x, shelf_h / 2.0, shelf_z - shelf_d / 2.0 + 0.25), Vector3(shelf_w, shelf_h, 0.5), _wood_mat)
	# Sides
	_spawn_block(Vector3(shelf_x - shelf_w / 2.0 + 0.5, shelf_h / 2.0, shelf_z), Vector3(1.0, shelf_h, shelf_d), _wood_mat)
	_spawn_block(Vector3(shelf_x + shelf_w / 2.0 - 0.5, shelf_h / 2.0, shelf_z), Vector3(1.0, shelf_h, shelf_d), _wood_mat)
	# Top Board
	_spawn_block(Vector3(shelf_x, shelf_h - 0.5, shelf_z), Vector3(shelf_w, 1.0, shelf_d), _wood_mat)
	# Middle shelves
	for sy in [8.0, 16.0, 24.0, 31.0]:
		_spawn_block(Vector3(shelf_x, sy, shelf_z), Vector3(shelf_w - 2.0, 0.8, shelf_d - 0.5), _wood_mat)
		# Populate Books
		for bx in range(-24, 25, 6):
			var book_h := rng.randf_range(4.0, 6.5)
			var book_w := rng.randf_range(1.2, 2.2)
			var book_d := shelf_d - 2.5
			var book_pos := Vector3(shelf_x + bx + rng.randf_range(-1, 1), sy + book_h / 2.0 + 0.4, shelf_z + rng.randf_range(-0.5, 0.5))
			var b_mat := StandardMaterial3D.new()
			b_mat.albedo_color = Color(rng.randf_range(0.2, 0.8), rng.randf_range(0.1, 0.7), rng.randf_range(0.1, 0.7))
			b_mat.roughness = 0.8
			_spawn_block(book_pos, Vector3(book_w, book_h, book_d), b_mat)

	# 5. Giant Dining Table
	var table_x := 55.0
	var table_z := -45.0
	var table_w := 65.0
	var table_d := 45.0
	var table_h := 15.0
	# Tabletop
	_spawn_block(Vector3(table_x, table_h + 1.0, table_z), Vector3(table_w, 2.0, table_d), _wood_light_mat)
	# Leg supports
	var leg_w := 3.0
	_spawn_block(Vector3(table_x - table_w/2.0 + leg_w, table_h/2.0, table_z - table_d/2.0 + leg_w), Vector3(leg_w, table_h, leg_w), _wood_light_mat)
	_spawn_block(Vector3(table_x + table_w/2.0 - leg_w, table_h/2.0, table_z - table_d/2.0 + leg_w), Vector3(leg_w, table_h, leg_w), _wood_light_mat)
	_spawn_block(Vector3(table_x - table_w/2.0 + leg_w, table_h/2.0, table_z + table_d/2.0 - leg_w), Vector3(leg_w, table_h, leg_w), _wood_light_mat)
	_spawn_block(Vector3(table_x + table_w/2.0 - leg_w, table_h/2.0, table_z + table_d/2.0 - leg_w), Vector3(leg_w, table_h, leg_w), _wood_light_mat)

	# 6. Giant Sofa
	var sofa_x := -65.0
	var sofa_z := 45.0
	var sofa_w := 55.0
	var sofa_d := 26.0
	# Wooden Frame
	_spawn_block(Vector3(sofa_x, 1.0, sofa_z), Vector3(sofa_w, 2.0, sofa_d), _wood_mat)
	# Soft Seat Cushions
	_spawn_block(Vector3(sofa_x, 3.5, sofa_z - 1.5), Vector3(sofa_w - 3.0, 3.0, sofa_d - 4.0), _fabric_blue_mat)
	# Backrest
	_spawn_block(Vector3(sofa_x, 9.5, sofa_z + sofa_d / 2.0 - 2.0), Vector3(sofa_w, 15.0, 4.0), _fabric_blue_mat)
	# Left & Right armrests
	_spawn_block(Vector3(sofa_x - sofa_w / 2.0 + 2.0, 5.0, sofa_z - 1.5), Vector3(4.0, 6.0, sofa_d - 3.0), _fabric_blue_mat)
	_spawn_block(Vector3(sofa_x + sofa_w / 2.0 - 2.0, 5.0, sofa_z - 1.5), Vector3(4.0, 6.0, sofa_d - 3.0), _fabric_blue_mat)

	# 7. Giant Bed (with Blanket Fold & Mattress Detail)
	var bed_x := 50.0
	var bed_z := 50.0
	var bed_w := 48.0
	var bed_d := 70.0
	# Bed base frame
	_spawn_block(Vector3(bed_x, 1.2, bed_z), Vector3(bed_w, 2.4, bed_d), _wood_mat)
	# Headboard
	_spawn_block(Vector3(bed_x, 7.5, bed_z + bed_d/2.0 - 1.0), Vector3(bed_w, 15.0, 2.0), _wood_mat)
	# Mattress
	_spawn_block(Vector3(bed_x, 4.2, bed_z - 1.0), Vector3(bed_w - 2.0, 3.6, bed_d - 3.0), _pillow_mat)
	# Red Blanket / Comforter covering lower bed
	_spawn_block(Vector3(bed_x, 4.3, bed_z - 6.0), Vector3(bed_w - 1.6, 3.8, bed_d - 22.0), _fabric_red_mat)
	# Pillows
	_spawn_block(Vector3(bed_x - 11.0, 6.3, bed_z + bed_d/2.0 - 9.0), Vector3(16.0, 2.0, 11.0), _pillow_mat)
	_spawn_block(Vector3(bed_x + 11.0, 6.3, bed_z + bed_d/2.0 - 9.0), Vector3(16.0, 2.0, 11.0), _pillow_mat)

	# 8. Giant TV Set and Entertainment Center
	var tv_x := 0.0
	var tv_z := -MAP_SIZE / 2.0 + 8.0
	var tv_w := 45.0
	var tv_h := 22.0
	# Console Table
	_spawn_block(Vector3(tv_x, 4.0, tv_z), Vector3(tv_w, 8.0, 6.0), _wood_mat)
	# TV Screen Stand
	_spawn_block(Vector3(tv_x, 8.5, tv_z), Vector3(6.0, 1.0, 4.0), _plastic_mat)
	_spawn_block(Vector3(tv_x, 11.0, tv_z), Vector3(1.5, 4.0, 1.5), _plastic_mat)
	# TV Screen Frame
	_spawn_block(Vector3(tv_x, 19.0, tv_z), Vector3(28.0, 16.0, 1.2), _plastic_mat)
	# Shiny TV Screen panel
	_spawn_block(Vector3(tv_x, 19.0, tv_z + 0.3), Vector3(26.8, 14.8, 0.8), _screen_mat)

	# 9. Stepping-stones / Navigation Helpers
	# Spawns Orange cushions and teal poles near furniture to aid jumping
	var spawn_clear_radius := 20.0
	
	# Helper poles (Teal)
	var num_poles := 12
	for i in range(num_poles):
		var pos_2d := _random_pos_outside(rng, spawn_clear_radius, MAP_SIZE / 2.0 - 15.0)
		var h := rng.randf_range(12.0, 24.0)
		var pos := Vector3(pos_2d.x, h / 2.0, pos_2d.y)
		# Spawn poles
		var body := _create_block_node(Vector3(2.0, h, 2.0), _floor_mat)
		add_child(body)
		body.global_position = pos
		# Add a nice teal cap on top of the pole
		var cap := _create_block_node(Vector3(2.4, 0.8, 2.4), _pillow_mat)
		body.add_child(cap)
		cap.position = Vector3(0, h/2.0 + 0.4, 0)

	# Chains of orange stepping platform pads
	var num_helper_paths := 12
	for p in range(num_helper_paths):
		var start_pos_2d := _random_pos_outside(rng, spawn_clear_radius, MAP_SIZE / 2.0 - 30.0)
		var current_pos := Vector3(start_pos_2d.x, rng.randf_range(3.0, 6.0), start_pos_2d.y)
		var chain_length := rng.randi_range(3, 5)
		var heading := rng.randf_range(-PI, PI)
		
		for c in range(chain_length):
			# Colored round-like pads (flat boxes)
			var pad_mat := StandardMaterial3D.new()
			pad_mat.albedo_color = Color(0.9, 0.45, 0.1) if rng.randf() > 0.3 else Color(0.1, 0.6, 0.5)
			pad_mat.roughness = 0.5
			_spawn_block(current_pos, Vector3(4.0, 0.8, 4.0), pad_mat)
			
			var dist := rng.randf_range(10.0, 13.0)
			var elevation_change := rng.randf_range(-1.5, 3.5)
			
			heading += rng.randf_range(-0.4, 0.4)
			current_pos += Vector3(sin(heading), 0.0, cos(heading)) * dist
			current_pos.y = clamp(current_pos.y + elevation_change, 3.0, 20.0)

# ─────────────────────────────────────────────────────────────────────────────
# Helper to generate random Vector2 positions outside spawn clearing
func _random_pos_outside(rng: RandomNumberGenerator, min_dist: float, max_dist: float) -> Vector2:
	while true:
		var x := rng.randf_range(-max_dist, max_dist)
		var z := rng.randf_range(-max_dist, max_dist)
		var pos := Vector2(x, z)
		if pos.length() > min_dist:
			return pos
	return Vector2.ZERO

# ─────────────────────────────────────────────────────────────────────────────
# Spawns a basic aligned box collision and mesh
func _spawn_block(pos: Vector3, size: Vector3, mat: Material) -> void:
	var body := _create_block_node(size, mat)
	add_child(body)
	body.global_position = pos

# ─────────────────────────────────────────────────────────────────────────────
# Creates a StaticBody3D with MeshInstance3D and CollisionShape3D
func _create_block_node(size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	
	# Mesh
	var mesh_inst := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = mat
	mesh_inst.mesh = box_mesh
	body.add_child(mesh_inst)
	
	# Collision
	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	collision.shape = box_shape
	body.add_child(collision)
	
	return body
