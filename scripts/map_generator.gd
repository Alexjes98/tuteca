extends Node3D

## Procedural House & Sunroom Library Map Generator
## Encloses the 100x100 space in walls/ceiling, and spawns giant furniture.
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
var _brick_mat: StandardMaterial3D
var _fire_mat: StandardMaterial3D
var _foliage_mat: StandardMaterial3D
var _metal_mat: StandardMaterial3D
var _soil_mat: StandardMaterial3D

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Clear any editor placeholder children under this Map node
	for child in get_children():
		child.queue_free()
		
	_setup_environment("Basic House")
	_setup_materials()
	_generate_map()

# ─────────────────────────────────────────────────────────────────────────────
func _setup_environment(map_type: String) -> void:
	var shadows_on := true
	if get_parent() and "_settings_shadows" in get_parent():
		shadows_on = get_parent()._settings_shadows

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
	
	# Ambient light setup
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	if map_type == "Sunroom Library":
		env.ambient_light_color = Color(0.25, 0.23, 0.2)  # Cozy warm ambient fill
		env.ambient_light_energy = 1.6 # Brighten up shadow areas
	else:
		env.ambient_light_color = Color(0.04, 0.04, 0.06)  # Dim ambient light for Map 1
		env.ambient_light_energy = 0.15
	
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
	
	if map_type == "Sunroom Library":
		# Create cinema-grade ceiling ambient lighting (soft warm glow)
		var light_positions := [
			Vector3(-25.0, ROOM_HEIGHT - 2.0, -25.0),
			Vector3(25.0, ROOM_HEIGHT - 2.0, -25.0),
			Vector3(-25.0, ROOM_HEIGHT - 2.0, 25.0),
			Vector3(25.0, ROOM_HEIGHT - 2.0, 25.0)
		]
		for l_pos in light_positions:
			var light := OmniLight3D.new()
			light.position = l_pos
			light.light_color = Color(1.0, 0.9, 0.8)  # Warm bright tungsten light
			light.light_energy = 24.0
			light.omni_range = 80.0
			light.shadow_enabled = shadows_on
			light.shadow_bias = 0.05
			add_child(light)

		# Add center warm pendant drop lights to illuminate the central sunroom section
		for lx in [-15.0, 15.0]:
			var drop_light := OmniLight3D.new()
			drop_light.position = Vector3(lx, 22.0, 0.0)
			drop_light.light_color = Color(1.0, 0.95, 0.85)
			drop_light.light_energy = 22.0
			drop_light.omni_range = 65.0
			drop_light.shadow_enabled = shadows_on
			add_child(drop_light)

		# Optional: Background Ambient Music (Sunroom Library only)
		if FileAccess.file_exists("res://assets/sounds/library_music.ogg"):
			var music_player := AudioStreamPlayer.new()
			music_player.stream = load("res://assets/sounds/library_music.ogg")
			music_player.volume_db = -18.0 # Soft background volume
			music_player.autoplay = true
			add_child(music_player)
			print("[Audio] Ambient library music loaded and playing.")

		# Optional: 3D Fireplace Crackle Ambience (Sunroom Library only)
		if FileAccess.file_exists("res://assets/sounds/fireplace_crackle.ogg"):
			var fire_player := AudioStreamPlayer3D.new()
			fire_player.stream = load("res://assets/sounds/fireplace_crackle.ogg")
			fire_player.position = Vector3(0.0, 3.0, -47.0) # Centered in fireplace hearth
			fire_player.unit_size = 5.0
			fire_player.max_distance = 25.0
			fire_player.autoplay = true
			add_child(fire_player)
			print("[Audio] Fireplace crackle 3D ambience loaded and playing.")
	else:
		# Map 1: Standard layout lights for Basic House (original cozy/mood levels)
		var light_positions := [
			Vector3(-MAP_SIZE * 0.25, ROOM_HEIGHT - 3.0, -MAP_SIZE * 0.25),
			Vector3(MAP_SIZE * 0.25, ROOM_HEIGHT - 3.0, -MAP_SIZE * 0.25),
			Vector3(-MAP_SIZE * 0.25, ROOM_HEIGHT - 3.0, MAP_SIZE * 0.25),
			Vector3(MAP_SIZE * 0.25, ROOM_HEIGHT - 3.0, MAP_SIZE * 0.25)
		]
		for l_pos in light_positions:
			var light := OmniLight3D.new()
			light.position = l_pos
			light.light_color = Color(1.0, 0.88, 0.75)  # Cozy warm tungsten light
			light.light_energy = 8.0
			light.omni_range = 60.0
			light.shadow_enabled = shadows_on
			light.shadow_bias = 0.05
			add_child(light)



# ─────────────────────────────────────────────────────────────────────────────
func _setup_materials() -> void:
	# Floor mat (cozy dark carpet)
	_floor_mat = StandardMaterial3D.new()
	_floor_mat.albedo_color = Color(0.18, 0.15, 0.15)
	_floor_mat.roughness = 0.9
	
	# Wall mat (soft cream plaster)
	_wall_mat = StandardMaterial3D.new()
	_wall_mat.albedo_color = Color(0.85, 0.82, 0.78)
	_wall_mat.roughness = 0.85
	
	# Wood mat (mahogany wood)
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

	# Brick mat (terracotta brick color)
	_brick_mat = StandardMaterial3D.new()
	_brick_mat.albedo_color = Color(0.55, 0.25, 0.15)
	_brick_mat.roughness = 0.9
	
	# Fire mat (emissive warm fire)
	_fire_mat = StandardMaterial3D.new()
	_fire_mat.albedo_color = Color(1.0, 0.5, 0.0)
	_fire_mat.emission_enabled = true
	_fire_mat.emission = Color(1.0, 0.5, 0.0)
	_fire_mat.emission_energy_multiplier = 4.0
	
	# Foliage mat (forest green)
	_foliage_mat = StandardMaterial3D.new()
	_foliage_mat.albedo_color = Color(0.15, 0.45, 0.2)
	_foliage_mat.roughness = 0.85
	
	# Metal mat (brass/gold)
	_metal_mat = StandardMaterial3D.new()
	_metal_mat.albedo_color = Color(0.75, 0.6, 0.25)
	_metal_mat.roughness = 0.2
	_metal_mat.metallic = 0.8
	
	# Soil mat (dark potting soil)
	_soil_mat = StandardMaterial3D.new()
	_soil_mat.albedo_color = Color(0.18, 0.12, 0.08)
	_soil_mat.roughness = 0.95

# ─────────────────────────────────────────────────────────────────────────────
# Default generator (defaults to Basic House)
func _generate_map() -> void:
	_generate_basic_house()

# ─────────────────────────────────────────────────────────────────────────────
# Real-time Map Switching trigger
func generate_selected_map(type: String) -> void:
	# Clear previous map elements
	for child in get_children():
		child.queue_free()
	_setup_environment(type)
	# Regenerate
	if type == "Basic House":
		_generate_basic_house()
	else:
		_generate_sunroom_library()

# ─────────────────────────────────────────────────────────────────────────────
# MAP 1: Recovered Original Basic House
# ─────────────────────────────────────────────────────────────────────────────
func _generate_basic_house() -> void:
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

	# 3. Baseboards
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

	# 7. Bed
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
	# Red Blanket
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

	# 9. Light Switch Box on the back wall next to the TV console (positioned at Y = 14.0 on back wall)
	var switch_box_mat := StandardMaterial3D.new()
	switch_box_mat.albedo_color = Color(0.05, 0.05, 0.05) # Sleek black box
	switch_box_mat.roughness = 0.6
	
	var switch_btn_mat := StandardMaterial3D.new()
	switch_btn_mat.albedo_color = Color(0.8, 0.2, 0.2)   # Bright red toggle button
	switch_btn_mat.roughness = 0.3

	_spawn_block(Vector3(16.0, 14.0, -48.7), Vector3(0.6, 0.8, 0.4), switch_box_mat)
	_spawn_block(Vector3(16.0, 14.0, -48.45), Vector3(0.2, 0.3, 0.1), switch_btn_mat)

# ─────────────────────────────────────────────────────────────────────────────
# MAP 2: Upgraded, Vivid Glass Sunroom Library & Study Loft
# ─────────────────────────────────────────────────────────────────────────────
func _generate_sunroom_library() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	
	# 1. Glass and window framing materials
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.65, 0.85, 0.95, 0.35) # Light blue transparent glass
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.roughness = 0.05
	glass_mat.metallic = 0.95
	
	# 2. Floor
	_spawn_block(Vector3(0.0, -0.5, 0.0), Vector3(MAP_SIZE, 1.0, MAP_SIZE), _floor_mat)
	
	# 3. Enclosing Walls & Ceiling with giant windows
	# Back wall (Solid brick/wood for loft/paintings)
	_spawn_block(Vector3(0.0, ROOM_HEIGHT / 2.0, -MAP_SIZE / 2.0), Vector3(MAP_SIZE, ROOM_HEIGHT, 2.0), _wall_mat)
	
	# Left wall (Solid for massive bookshelf/stairs)
	_spawn_block(Vector3(-MAP_SIZE / 2.0, ROOM_HEIGHT / 2.0, 0.0), Vector3(2.0, ROOM_HEIGHT, MAP_SIZE), _wall_mat)
	
	# Front Wall (Conservatory grid window)
	_spawn_block(Vector3(0.0, 2.0, MAP_SIZE / 2.0), Vector3(MAP_SIZE, 4.0, 2.0), _wall_mat) # Base
	_spawn_block(Vector3(0.0, ROOM_HEIGHT - 3.0, MAP_SIZE / 2.0), Vector3(MAP_SIZE, 6.0, 2.0), _wall_mat) # Top
	_spawn_block(Vector3(0.0, 14.0, MAP_SIZE / 2.0), Vector3(MAP_SIZE, 20.0, 0.2), glass_mat) # Glass
	
	# Right Wall (Conservatory grid window)
	_spawn_block(Vector3(MAP_SIZE / 2.0, 2.0, 0.0), Vector3(2.0, 4.0, MAP_SIZE), _wall_mat) # Base
	_spawn_block(Vector3(MAP_SIZE / 2.0, ROOM_HEIGHT - 3.0, 0.0), Vector3(2.0, 6.0, MAP_SIZE), _wall_mat) # Top
	_spawn_block(Vector3(MAP_SIZE / 2.0, 14.0, 0.0), Vector3(0.2, 20.0, MAP_SIZE), glass_mat) # Glass
	
	# Vertical structural columns for the glass facade
	for x_col in range(-45, 46, 15):
		_spawn_block(Vector3(x_col, ROOM_HEIGHT / 2.0, MAP_SIZE / 2.0), Vector3(1.5, ROOM_HEIGHT, 2.1), _wood_mat)
	for z_col in range(-45, 46, 15):
		_spawn_block(Vector3(MAP_SIZE / 2.0, ROOM_HEIGHT / 2.0, z_col), Vector3(2.1, ROOM_HEIGHT, 1.5), _wood_mat)

	# Ceiling skylight grid
	for x_pos in range(-50, 51, 10):
		_spawn_block(Vector3(x_pos, ROOM_HEIGHT, 0.0), Vector3(0.6, 0.6, 100.0), _wood_mat)
	for z_pos in range(-50, 51, 10):
		_spawn_block(Vector3(0.0, ROOM_HEIGHT, z_pos), Vector3(100.0, 0.6, 0.6), _wood_mat)
	_spawn_block(Vector3(0.0, ROOM_HEIGHT + 0.1, 0.0), Vector3(100.0, 0.1, 100.0), glass_mat)

	# Baseboards (solid wall bottom frames)
	var bs_h := 1.0
	var bs_d := 0.4
	_spawn_block(Vector3(0.0, bs_h / 2.0, -MAP_SIZE / 2.0 + bs_d / 2.0), Vector3(MAP_SIZE, bs_h, bs_d), _wood_mat)
	_spawn_block(Vector3(-MAP_SIZE / 2.0 + bs_d / 2.0, bs_h / 2.0, 0.0), Vector3(bs_d, bs_h, MAP_SIZE), _wood_mat)

	# 4. Mezzanine Loft (Split back balcony to fit fireplace chimney)
	# Left back loft floor
	_spawn_block(Vector3(-28.0, 11.5, -42.5), Vector3(44.0, 1.0, 15.0), _wood_light_mat)
	# Right back loft floor
	_spawn_block(Vector3(28.0, 11.5, -42.5), Vector3(44.0, 1.0, 15.0), _wood_light_mat)
	# Right side loft floor
	_spawn_block(Vector3(42.5, 11.5, 7.5), Vector3(15.0, 1.0, 85.0), _wood_light_mat)
	
	# Loft Handrails
	_spawn_block(Vector3(-28.0, 12.8, -35.0), Vector3(44.0, 0.2, 0.2), _wood_mat) # Left back railing
	_spawn_block(Vector3(28.0, 12.8, -35.0), Vector3(44.0, 0.2, 0.2), _wood_mat)  # Right back railing
	_spawn_block(Vector3(35.0, 12.8, 7.5), Vector3(0.2, 0.2, 85.0), _wood_mat)    # Right side railing
	
	# Loft Balusters (posts)
	for px in range(-48, -7, 5):
		_spawn_block(Vector3(px, 12.4, -35.0), Vector3(0.15, 1.6, 0.15), _wood_mat)
	for px in range(8, 49, 5):
		_spawn_block(Vector3(px, 12.4, -35.0), Vector3(0.15, 1.6, 0.15), _wood_mat)
	for pz in range(-30, 46, 5):
		_spawn_block(Vector3(35.0, 12.4, pz), Vector3(0.15, 1.6, 0.15), _wood_mat)

	# 5. Staircase to Mezzanine (starts at floor left-side, goes up to back loft)
	for i in range(12):
		var step_y := i * 1.0 + 0.5
		var step_z := -3.0 * i
		_spawn_block(Vector3(-42.0, step_y, step_z), Vector3(6.0, 1.0, 3.5), _wood_light_mat)

	# 6. Cat Tree Tower (front-left vertical climbing path)
	_spawn_block(Vector3(-30.0, 9.0, 30.0), Vector3(1.5, 18.0, 1.5), _wood_mat) # Center pole
	# Platforms at heights 5.0, 9.0, 13.0, 17.5
	_spawn_block(Vector3(-27.0, 5.0, 30.0), Vector3(5.0, 0.5, 5.0), _fabric_blue_mat)
	_spawn_block(Vector3(-30.0, 9.0, 27.0), Vector3(5.0, 0.5, 5.0), _fabric_blue_mat)
	_spawn_block(Vector3(-33.0, 13.0, 30.0), Vector3(5.0, 0.5, 5.0), _fabric_blue_mat)
	_spawn_block(Vector3(-30.0, 17.5, 30.0), Vector3(6.0, 1.0, 6.0), _fabric_blue_mat)
	_spawn_block(Vector3(-30.0, 18.25, 30.0), Vector3(5.0, 0.5, 5.0), _pillow_mat) # Top bed cushion

	# 7. Giant Study Desk
	# Desk top
	_spawn_block(Vector3(-20.0, 6.5, -25.0), Vector3(36.0, 1.0, 20.0), _wood_mat)
	# Legs
	_spawn_block(Vector3(-36.0, 3.0, -33.0), Vector3(2.0, 6.0, 2.0), _wood_mat)
	_spawn_block(Vector3(-4.0, 3.0, -33.0), Vector3(2.0, 6.0, 2.0), _wood_mat)
	_spawn_block(Vector3(-36.0, 3.0, -17.0), Vector3(2.0, 6.0, 2.0), _wood_mat)
	_spawn_block(Vector3(-4.0, 3.0, -17.0), Vector3(2.0, 6.0, 2.0), _wood_mat)
	
	# Laptop on Desk
	_spawn_block(Vector3(-20.0, 7.1, -23.0), Vector3(8.0, 0.2, 6.0), _plastic_mat) # Base
	_spawn_block(Vector3(-20.0, 10.5, -26.0), Vector3(8.0, 6.0, 0.4), _plastic_mat) # Screen frame
	_spawn_block(Vector3(-20.0, 10.5, -25.75), Vector3(7.4, 5.4, 0.1), _screen_mat) # Screen panel
	
	# Hollow Giant Coffee Mug on Desk
	_spawn_block(Vector3(-8.0, 7.1, -22.0), Vector3(3.0, 0.2, 3.0), _fabric_red_mat) # Mug bottom
	_spawn_block(Vector3(-9.4, 8.5, -22.0), Vector3(0.2, 3.0, 3.0), _fabric_red_mat) # Left wall
	_spawn_block(Vector3(-6.6, 8.5, -22.0), Vector3(0.2, 3.0, 3.0), _fabric_red_mat) # Right wall
	_spawn_block(Vector3(-8.0, 8.5, -23.4), Vector3(3.0, 3.0, 0.2), _fabric_red_mat) # Back wall
	_spawn_block(Vector3(-8.0, 8.5, -20.6), Vector3(3.0, 3.0, 0.2), _fabric_red_mat) # Front wall
	_spawn_block(Vector3(-5.6, 8.5, -22.0), Vector3(1.8, 1.6, 0.6), _fabric_red_mat) # Handle
	
	# Coffee liquid mesh inside the mug
	var coffee_mat := StandardMaterial3D.new()
	coffee_mat.albedo_color = Color(0.2, 0.1, 0.05, 0.8) # Coffee brown, semi-transparent
	coffee_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	coffee_mat.roughness = 0.1
	_spawn_block(Vector3(-8.0, 8.0, -22.0), Vector3(2.6, 1.6, 2.6), coffee_mat)
	
	# Giant Desk Lamp with SpotLight3D
	_spawn_block(Vector3(-32.0, 7.2, -27.0), Vector3(3.0, 0.4, 3.0), _plastic_mat) # Base
	_spawn_block(Vector3(-32.0, 10.5, -27.0), Vector3(0.4, 6.0, 0.4), _metal_mat) # Neck
	_spawn_block(Vector3(-30.0, 13.5, -25.0), Vector3(2.5, 1.2, 2.5), _plastic_mat) # Head/Shade
	
	var shadows_on := true
	if get_parent() and "_settings_shadows" in get_parent():
		shadows_on = get_parent()._settings_shadows

	var desk_light := SpotLight3D.new()
	desk_light.position = Vector3(-30.0, 12.8, -25.0)
	desk_light.rotation_degrees = Vector3(-90, 0, 0) # Point straight down
	desk_light.light_color = Color(1.0, 0.95, 0.8) # Warm desk lamp light
	desk_light.light_energy = 10.0
	desk_light.spot_range = 15.0
	desk_light.spot_angle = 60.0
	desk_light.shadow_enabled = shadows_on
	add_child(desk_light)

	# 8. Fireplace (Relocated to center back wall under mezzanine)
	# Pillars and arch
	_spawn_block(Vector3(-6.0, 6.0, -47.0), Vector3(3.0, 12.0, 2.0), _brick_mat) # Left pillar
	_spawn_block(Vector3(6.0, 6.0, -47.0), Vector3(3.0, 12.0, 2.0), _brick_mat)  # Right pillar
	_spawn_block(Vector3(0.0, 7.5, -49.0), Vector3(15.0, 15.0, 2.0), _brick_mat) # Fireplace back
	_spawn_block(Vector3(0.0, 10.0, -47.0), Vector3(15.0, 4.0, 2.0), _brick_mat) # Fireplace arch front
	# Mantle board
	_spawn_block(Vector3(0.0, 12.2, -45.5), Vector3(18.0, 0.6, 5.0), _wood_mat)
	# Brick Chimney rising up through mezzanine floor to ceiling
	_spawn_block(Vector3(0.0, 21.0, -48.0), Vector3(12.0, 18.0, 4.0), _brick_mat)
	# Stacked charcoal logs with glowing ember center
	var log_mat := StandardMaterial3D.new()
	log_mat.albedo_color = Color(0.15, 0.1, 0.08)
	log_mat.roughness = 0.9
	log_mat.emission_enabled = true
	log_mat.emission = Color(0.95, 0.25, 0.0)  # Deep embers orange glow
	log_mat.emission_energy_multiplier = 2.0
	_spawn_block(Vector3(-1.4, 0.6, -47.5), Vector3(2.5, 0.4, 0.6), log_mat)
	_spawn_block(Vector3(1.4, 0.6, -47.5), Vector3(2.5, 0.4, 0.6), log_mat)
	_spawn_block(Vector3(0.0, 1.0, -47.3), Vector3(3.0, 0.4, 0.6), log_mat)

	# Dynamic CPUParticles3D fire emitter
	var fire_particles := CPUParticles3D.new()
	fire_particles.position = Vector3(0.0, 1.0, -47.5)
	fire_particles.amount = 45
	fire_particles.lifetime = 1.3
	fire_particles.speed_scale = 1.6
	fire_particles.randomness = 0.6
	
	fire_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fire_particles.emission_box_extents = Vector3(1.6, 0.2, 0.5)
	
	fire_particles.direction = Vector3.UP
	fire_particles.spread = 12.0
	fire_particles.gravity = Vector3(0.0, 4.0, 0.0)  # Slow upward draft drift
	fire_particles.initial_velocity_min = 2.0
	fire_particles.initial_velocity_max = 4.5
	
	var gradient := Gradient.new()
	gradient.set_colors([
		Color(1.0, 0.95, 0.3, 1.0),  # Bright core yellow
		Color(1.0, 0.5, 0.0, 0.9),   # Intense orange
		Color(0.8, 0.15, 0.0, 0.45), # Dark warm red
		Color(0.2, 0.1, 0.1, 0.0)    # Faded ash
	])
	fire_particles.color_ramp = gradient
	
	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(0.85, 0.85)
	
	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	p_mat.vertex_color_use_as_albedo = true
	p_mat.billboard_mode = StandardMaterial3D.BILLBOARD_ENABLED
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad_mesh.material = p_mat
	fire_particles.mesh = quad_mesh
	add_child(fire_particles)

	# Warm glowing firelight projecting out of the fireplace hearth
	var fire_light := OmniLight3D.new()
	fire_light.position = Vector3(0.0, 2.0, -45.5)
	fire_light.light_color = Color(1.0, 0.55, 0.15)  # Warm fire orange
	fire_light.light_energy = 16.0
	fire_light.omni_range = 35.0
	fire_light.shadow_enabled = shadows_on
	add_child(fire_light)

	# 9. Planter Boxes & Trellis Climbing Grid (front-right)
	# Planter Box 1
	_spawn_block(Vector3(25.0, 1.5, 25.0), Vector3(14.0, 3.0, 14.0), _wood_light_mat) # Outer box
	_spawn_block(Vector3(25.0, 2.8, 25.0), Vector3(13.6, 0.4, 13.6), _soil_mat)       # Soil
	_spawn_block(Vector3(22.0, 4.5, 22.0), Vector3(4.0, 3.0, 4.0), _foliage_mat)       # Foliage blocks
	_spawn_block(Vector3(26.0, 5.5, 26.0), Vector3(5.0, 5.0, 5.0), _foliage_mat)
	_spawn_block(Vector3(24.0, 7.5, 25.0), Vector3(3.0, 3.5, 3.0), _foliage_mat)
	
	# Planter Box 2
	_spawn_block(Vector3(15.0, 3.0, 35.0), Vector3(8.0, 6.0, 8.0), _wood_light_mat)  # Outer box
	_spawn_block(Vector3(15.0, 5.8, 35.0), Vector3(7.6, 0.4, 7.6), _soil_mat)        # Soil
	_spawn_block(Vector3(15.0, 8.0, 35.0), Vector3(6.0, 4.0, 6.0), _foliage_mat)
	_spawn_block(Vector3(14.0, 11.0, 34.0), Vector3(4.0, 3.0, 4.0), _foliage_mat)
	
	# Trellis climbing grid on right wall
	for ty in range(2, 25, 4):
		_spawn_block(Vector3(48.8, ty, 20.0), Vector3(0.2, 0.2, 20.0), _wood_mat)
	for tz in range(10, 31, 4):
		_spawn_block(Vector3(48.8, 12.0, tz), Vector3(0.2, 24.0, 0.2), _wood_mat)

	# 10. Wall Frames & Paintings (Load Custom Generated Art)
	var gecko_tex := load("res://assets/gecko_painting.jpg")
	var gecko_mat := StandardMaterial3D.new()
	gecko_mat.albedo_texture = gecko_tex
	gecko_mat.roughness = 0.8
	
	var cat_tex := load("res://assets/cat_painting.jpg")
	var cat_mat := StandardMaterial3D.new()
	cat_mat.albedo_texture = cat_tex
	cat_mat.roughness = 0.8

	# Painting 1 (Gecko Art)
	_spawn_block(Vector3(-25.0, 18.0, -48.7), Vector3(16.0, 10.0, 0.4), _wood_mat)      # Frame
	_spawn_block(Vector3(-25.0, 18.0, -48.45), Vector3(15.0, 9.0, 0.2), gecko_mat)      # Canvas
	# Painting 2 (Cat Art)
	_spawn_block(Vector3(25.0, 18.0, -48.7), Vector3(16.0, 10.0, 0.4), _wood_mat)
	_spawn_block(Vector3(25.0, 18.0, -48.45), Vector3(15.0, 9.0, 0.2), cat_mat)
	# Painting 3
	_spawn_block(Vector3(-48.7, 18.0, 20.0), Vector3(0.4, 10.0, 16.0), _wood_mat)
	_spawn_block(Vector3(-48.45, 18.0, 20.0), Vector3(0.2, 9.0, 15.0), _pillow_mat)

	# 11. Sofa & Coffee Table (Vivid reading spot)
	# Sofa
	_spawn_block(Vector3(0.0, 0.6, 20.0), Vector3(28.0, 1.2, 12.0), _wood_mat)
	_spawn_block(Vector3(0.0, 1.8, 19.0), Vector3(25.0, 1.2, 9.0), _fabric_red_mat)
	_spawn_block(Vector3(0.0, 4.0, 24.5), Vector3(28.0, 6.0, 2.0), _fabric_red_mat)
	_spawn_block(Vector3(-13.0, 2.5, 19.0), Vector3(2.0, 3.0, 9.0), _fabric_red_mat)
	_spawn_block(Vector3(13.0, 2.5, 19.0), Vector3(2.0, 3.0, 9.0), _fabric_red_mat)
	# Coffee Table
	_spawn_block(Vector3(0.0, 2.5, 5.0), Vector3(16.0, 0.6, 10.0), _wood_light_mat)
	_spawn_block(Vector3(-7.0, 1.1, 4.0), Vector3(1.0, 2.2, 1.0), _wood_light_mat)
	_spawn_block(Vector3(7.0, 1.1, 4.0), Vector3(1.0, 2.2, 1.0), _wood_light_mat)
	_spawn_block(Vector3(-7.0, 1.1, 6.0), Vector3(1.0, 2.2, 1.0), _wood_light_mat)
	_spawn_block(Vector3(7.0, 1.1, 6.0), Vector3(1.0, 2.2, 1.0), _wood_light_mat)

	# 12. Light Switch Box (mounted on back wall next to loft stairs platform)
	var switch_box_mat := StandardMaterial3D.new()
	switch_box_mat.albedo_color = Color(0.05, 0.05, 0.05) # Sleek black box
	switch_box_mat.roughness = 0.6
	
	var switch_btn_mat := StandardMaterial3D.new()
	switch_btn_mat.albedo_color = Color(0.8, 0.2, 0.2)   # Bright red toggle button
	switch_btn_mat.roughness = 0.3

	_spawn_block(Vector3(16.0, 16.0, -48.7), Vector3(0.6, 0.8, 0.4), switch_box_mat)
	_spawn_block(Vector3(16.0, 16.0, -48.45), Vector3(0.2, 0.3, 0.1), switch_btn_mat)

	# 13. Giant Physics Yarn Balls
	_spawn_yarn_ball(Vector3(10.0, 3.0, -15.0), 2.0, Color(0.8, 0.3, 0.3)) # Red ball
	_spawn_yarn_ball(Vector3(-15.0, 3.0, 15.0), 2.5, Color(0.3, 0.5, 0.8)) # Blue ball
	_spawn_yarn_ball(Vector3(25.0, 2.0, 0.0), 1.8, Color(0.8, 0.7, 0.2))  # Yellow ball

	# 14. Massive Wall Bookshelves
	_spawn_bookshelf(-46.0, 20.0, 30.0, 22.0, 4.0, false) # Left wall shelf unit
	_spawn_bookshelf(46.0, -20.0, 30.0, 10.0, 4.0, false) # Right wall shelf unit (under loft)

	# 15. Climbable Book Piles on the floor
	_spawn_book_pile(Vector3(-25.0, 0.0, -10.0), 5)
	_spawn_book_pile(Vector3(20.0, 0.0, 20.0), 6)

	# 16. Hanging Ivy under Mezzanine balcony
	_spawn_block(Vector3(-28.0, 10.5, -34.8), Vector3(10.0, 2.0, 0.4), _foliage_mat)
	_spawn_block(Vector3(28.0, 10.5, -34.8), Vector3(10.0, 2.0, 0.4), _foliage_mat)
	_spawn_block(Vector3(34.8, 10.5, 15.0), Vector3(0.4, 2.0, 12.0), _foliage_mat)

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

# ─────────────────────────────────────────────────────────────────────────────
# Spawns a sphere RigidBody3D with scale and material
func _spawn_yarn_ball(pos: Vector3, radius: float, color: Color) -> void:
	var body := RigidBody3D.new()
	body.mass = 5.0
	
	# Collision shape
	var collision := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = radius
	collision.shape = sphere_shape
	body.add_child(collision)
	
	# Mesh
	var mesh_inst := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = radius
	sphere_mesh.height = radius * 2.0
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	sphere_mesh.material = mat
	
	mesh_inst.mesh = sphere_mesh
	body.add_child(mesh_inst)
	
	add_child(body)
	body.global_position = pos

# ─────────────────────────────────────────────────────────────────────────────
# Spawns a detailed wooden bookshelf with procedurally stacked colorful books
func _spawn_bookshelf(x: float, z: float, width: float, height: float, depth: float, is_facing_z: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 42
	
	# Backboard
	if is_facing_z:
		_spawn_block(Vector3(x, height / 2.0, z - depth / 2.0 + 0.1), Vector3(width, height, 0.2), _wood_mat)
		# Sides
		_spawn_block(Vector3(x - width / 2.0 + 0.2, height / 2.0, z), Vector3(0.4, height, depth), _wood_mat)
		_spawn_block(Vector3(x + width / 2.0 - 0.2, height / 2.0, z), Vector3(0.4, height, depth), _wood_mat)
		# Top
		_spawn_block(Vector3(x, height - 0.2, z), Vector3(width, 0.4, depth), _wood_mat)
		# Shelves
		for sy in range(3, int(height), 4):
			_spawn_block(Vector3(x, sy, z), Vector3(width - 0.8, 0.3, depth - 0.1), _wood_mat)
			# Populate books
			for bx in range(int(-width/2.0 + 1.5), int(width/2.0 - 1.5), 2):
				var book_h := rng.randf_range(1.6, 2.6)
				var book_w := rng.randf_range(0.4, 0.8)
				var book_d := depth - 0.6
				var book_pos := Vector3(x + bx + rng.randf_range(-0.2, 0.2), sy + book_h / 2.0 + 0.15, z + rng.randf_range(-0.1, 0.1))
				
				var b_mat := StandardMaterial3D.new()
				b_mat.albedo_color = Color(rng.randf_range(0.2, 0.85), rng.randf_range(0.1, 0.75), rng.randf_range(0.1, 0.75))
				b_mat.roughness = 0.8
				_spawn_block(book_pos, Vector3(book_w, book_h, book_d), b_mat)
	else:
		# Facing X
		_spawn_block(Vector3(x - depth / 2.0 + 0.1, height / 2.0, z), Vector3(0.2, height, width), _wood_mat)
		# Sides
		_spawn_block(Vector3(x, height / 2.0, z - width / 2.0 + 0.2), Vector3(depth, height, 0.4), _wood_mat)
		_spawn_block(Vector3(x, height / 2.0, z + width / 2.0 - 0.2), Vector3(depth, height, 0.4), _wood_mat)
		# Top
		_spawn_block(Vector3(x, height - 0.2, z), Vector3(depth, 0.4, width), _wood_mat)
		# Shelves
		for sy in range(3, int(height), 4):
			_spawn_block(Vector3(x, sy, z), Vector3(depth - 0.1, 0.3, width - 0.8), _wood_mat)
			# Populate books
			for bz in range(int(-width/2.0 + 1.5), int(width/2.0 - 1.5), 2):
				var book_h := rng.randf_range(1.6, 2.6)
				var book_w := rng.randf_range(0.4, 0.8)
				var book_d := depth - 0.6
				var book_pos := Vector3(x + rng.randf_range(-0.1, 0.1), sy + book_h / 2.0 + 0.15, z + bz + rng.randf_range(-0.2, 0.2))
				
				var b_mat := StandardMaterial3D.new()
				b_mat.albedo_color = Color(rng.randf_range(0.2, 0.85), rng.randf_range(0.1, 0.75), rng.randf_range(0.1, 0.75))
				b_mat.roughness = 0.8
				_spawn_block(book_pos, Vector3(book_d, book_h, book_w), b_mat)

# ─────────────────────────────────────────────────────────────────────────────
# Spawns a stack of books that act as platforms
func _spawn_book_pile(pos: Vector3, count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + int(pos.x + pos.z)
	for i in range(count):
		var book_h := 0.4
		var book_w := 2.5
		var book_d := 3.2
		var current_y := pos.y + i * book_h + book_h / 2.0
		
		var b_mat := StandardMaterial3D.new()
		b_mat.albedo_color = Color(rng.randf_range(0.2, 0.8), rng.randf_range(0.1, 0.7), rng.randf_range(0.1, 0.7))
		b_mat.roughness = 0.8
		
		_spawn_block(Vector3(pos.x + rng.randf_range(-0.15, 0.15), current_y, pos.z + rng.randf_range(-0.15, 0.15)), Vector3(book_w, book_h, book_d), b_mat)
