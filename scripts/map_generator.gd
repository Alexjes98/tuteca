extends Node3D

## Procedural House Map Generator
## Encloses the 200x200 space in walls/ceiling, and spawns giant furniture.
## Implements cinema-grade lighting, SSAO, glow, and warm room lights.
## Uses a fixed seed (12345) to ensure deterministic generation on all peers.

const SEED := 12245
const MAP_SIZE := 100.0
const ROOM_HEIGHT := 30.0

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
		Vector3(-MAP_SIZE * 0.25, ROOM_HEIGHT - 3.0, -MAP_SIZE * 0.25),
		Vector3(MAP_SIZE * 0.25, ROOM_HEIGHT - 3.0, -MAP_SIZE * 0.25),
		Vector3(-MAP_SIZE * 0.25, ROOM_HEIGHT - 3.0, MAP_SIZE * 0.25),
		Vector3(MAP_SIZE * 0.25, ROOM_HEIGHT - 3.0, MAP_SIZE * 0.25)
	]
	
	for l_pos in light_positions:
		var light := OmniLight3D.new()
		light.position = l_pos
		light.light_color = Color(1.0, 0.88, 0.75)  # Warm tungsten light
		light.light_energy = 8.0
		light.omni_range = 60.0
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
	var bs_h := 1.0
	var bs_d := 0.4
	_spawn_block(Vector3(0.0, bs_h / 2.0, -MAP_SIZE / 2.0 + bs_d / 2.0), Vector3(MAP_SIZE, bs_h, bs_d), _wood_mat)
	_spawn_block(Vector3(0.0, bs_h / 2.0, MAP_SIZE / 2.0 - bs_d / 2.0), Vector3(MAP_SIZE, bs_h, bs_d), _wood_mat)
	_spawn_block(Vector3(MAP_SIZE / 2.0 - bs_d / 2.0, bs_h / 2.0, 0.0), Vector3(bs_d, bs_h, MAP_SIZE), _wood_mat)
	_spawn_block(Vector3(-MAP_SIZE / 2.0 + bs_d / 2.0, bs_h / 2.0, 0.0), Vector3(bs_d, bs_h, MAP_SIZE), _wood_mat)

	# 4. Bookshelf
	var shelf_x := -25.0
	var shelf_z := -MAP_SIZE / 2.0 + 3.0
	var shelf_w := 24.0
	var shelf_h := 18.0
	var shelf_d := 4.5
	# Backboard
	_spawn_block(Vector3(shelf_x, shelf_h / 2.0, shelf_z - shelf_d / 2.0 + 0.15), Vector3(shelf_w, shelf_h, 0.3), _wood_mat)
	# Sides
	_spawn_block(Vector3(shelf_x - shelf_w / 2.0 + 0.25, shelf_h / 2.0, shelf_z), Vector3(0.5, shelf_h, shelf_d), _wood_mat)
	_spawn_block(Vector3(shelf_x + shelf_w / 2.0 - 0.25, shelf_h / 2.0, shelf_z), Vector3(0.5, shelf_h, shelf_d), _wood_mat)
	# Top Board
	_spawn_block(Vector3(shelf_x, shelf_h - 0.25, shelf_z), Vector3(shelf_w, 0.5, shelf_d), _wood_mat)
	# Middle shelves
	for sy in [3.8, 7.6, 11.4, 15.2]:
		_spawn_block(Vector3(shelf_x, sy, shelf_z), Vector3(shelf_w - 1.0, 0.4, shelf_d - 0.3), _wood_mat)
		# Populate Books
		for bx in range(-9, 10, 3):
			var book_h := rng.randf_range(2.0, 3.0)
			var book_w := rng.randf_range(0.6, 1.1)
			var book_d := shelf_d - 1.2
			var book_pos := Vector3(shelf_x + bx + rng.randf_range(-0.3, 0.3), sy + book_h / 2.0 + 0.2, shelf_z + rng.randf_range(-0.2, 0.2))
			var b_mat := StandardMaterial3D.new()
			b_mat.albedo_color = Color(rng.randf_range(0.2, 0.8), rng.randf_range(0.1, 0.7), rng.randf_range(0.1, 0.7))
			b_mat.roughness = 0.8
			_spawn_block(book_pos, Vector3(book_w, book_h, book_d), b_mat)

	# 5. Dining Table
	var table_x := 25.0
	var table_z := -20.0
	var table_w := 26.0
	var table_d := 18.0
	var table_h := 7.0
	# Tabletop
	_spawn_block(Vector3(table_x, table_h + 0.5, table_z), Vector3(table_w, 1.0, table_d), _wood_light_mat)
	# Leg supports
	var leg_w := 1.2
	_spawn_block(Vector3(table_x - table_w/2.0 + leg_w, table_h/2.0, table_z - table_d/2.0 + leg_w), Vector3(leg_w, table_h, leg_w), _wood_light_mat)
	_spawn_block(Vector3(table_x + table_w/2.0 - leg_w, table_h/2.0, table_z - table_d/2.0 + leg_w), Vector3(leg_w, table_h, leg_w), _wood_light_mat)
	_spawn_block(Vector3(table_x - table_w/2.0 + leg_w, table_h/2.0, table_z + table_d/2.0 - leg_w), Vector3(leg_w, table_h, leg_w), _wood_light_mat)
	_spawn_block(Vector3(table_x + table_w/2.0 - leg_w, table_h/2.0, table_z + table_d/2.0 - leg_w), Vector3(leg_w, table_h, leg_w), _wood_light_mat)

	# 6. Sofa
	var sofa_x := -25.0
	var sofa_z := 20.0
	var sofa_w := 26.0
	var sofa_d := 12.0
	# Wooden Frame
	_spawn_block(Vector3(sofa_x, 0.5, sofa_z), Vector3(sofa_w, 1.0, sofa_d), _wood_mat)
	# Soft Seat Cushions
	_spawn_block(Vector3(sofa_x, 1.75, sofa_z - 0.5), Vector3(sofa_w - 1.5, 1.5, sofa_d - 2.0), _fabric_blue_mat)
	# Backrest
	_spawn_block(Vector3(sofa_x, 4.5, sofa_z + sofa_d / 2.0 - 1.0), Vector3(sofa_w, 7.0, 2.0), _fabric_blue_mat)
	# Left & Right armrests
	_spawn_block(Vector3(sofa_x - sofa_w / 2.0 + 1.0, 2.5, sofa_z - 0.5), Vector3(2.0, 3.0, sofa_d - 1.5), _fabric_blue_mat)
	_spawn_block(Vector3(sofa_x + sofa_w / 2.0 - 1.0, 2.5, sofa_z - 0.5), Vector3(2.0, 3.0, sofa_d - 1.5), _fabric_blue_mat)

	# 7. Bed (with Blanket Fold & Mattress Detail)
	var bed_x := 25.0
	var bed_z := 25.0
	var bed_w := 22.0
	var bed_d := 30.0
	# Bed base frame
	_spawn_block(Vector3(bed_x, 0.6, bed_z), Vector3(bed_w, 1.2, bed_d), _wood_mat)
	# Headboard
	_spawn_block(Vector3(bed_x, 3.75, bed_z + bed_d/2.0 - 0.5), Vector3(bed_w, 7.5, 1.0), _wood_mat)
	# Mattress
	_spawn_block(Vector3(bed_x, 2.1, bed_z - 0.5), Vector3(bed_w - 1.0, 1.8, bed_d - 1.5), _pillow_mat)
	# Red Blanket / Comforter covering lower bed
	_spawn_block(Vector3(bed_x, 2.15, bed_z - 3.0), Vector3(bed_w - 0.8, 1.9, bed_d - 10.0), _fabric_red_mat)
	# Pillows
	_spawn_block(Vector3(bed_x - 5.0, 3.5, bed_z + bed_d/2.0 - 4.5), Vector3(7.5, 1.0, 5.0), _pillow_mat)
	_spawn_block(Vector3(bed_x + 5.0, 3.5, bed_z + bed_d/2.0 - 4.5), Vector3(7.5, 1.0, 5.0), _pillow_mat)

	# 8. TV Set and Entertainment Center
	var tv_x := 0.0
	var tv_z := -MAP_SIZE / 2.0 + 4.0
	# Console Table
	_spawn_block(Vector3(tv_x, 2.0, tv_z), Vector3(22.0, 4.0, 3.5), _wood_mat)
	# TV Screen Stand
	_spawn_block(Vector3(tv_x, 4.2, tv_z), Vector3(3.0, 0.4, 2.0), _plastic_mat)
	_spawn_block(Vector3(tv_x, 5.4, tv_z), Vector3(0.8, 2.0, 0.8), _plastic_mat)
	# TV Screen Frame
	_spawn_block(Vector3(tv_x, 10.65, tv_z), Vector3(15.0, 8.5, 0.6), _plastic_mat)
	# Shiny TV Screen panel
	_spawn_block(Vector3(tv_x, 10.65, tv_z + 0.15), Vector3(14.2, 7.8, 0.4), _screen_mat)





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
