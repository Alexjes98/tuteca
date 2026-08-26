extends Node3D

## Root controller for main_test.tscn.
## Manages ENet peer setup (host / client), the lobby UI,
## player spawning via MultiplayerSpawner, and character selection.

const PORT       := 13579
const MAX_PEERS  := 8

@onready var lobby_ui        : Control            = $CanvasLayer/LobbyUI
@onready var players         : Node3D             = $Players
@onready var spawner         : MultiplayerSpawner = $MultiplayerSpawner
@onready var cricket_spawner : Node3D             = $CricketSpawner

# HUD & Game state references
@onready var hud: Control = $CanvasLayer/HUD
@onready var timer_label: Label = $CanvasLayer/HUD/MarginContainer/HBoxContainer/TimerLabel
@onready var crickets_label: Label = $CanvasLayer/HUD/MarginContainer/HBoxContainer/CricketsLabel
@onready var lizards_label: Label = $CanvasLayer/HUD/MarginContainer/HBoxContainer/LizardsLabel
@onready var game_over_panel: ColorRect = $CanvasLayer/GameOverPanel
@onready var win_label: Label = $CanvasLayer/GameOverPanel/CenterContainer/VBoxContainer/WinLabel
@onready var restart_btn: Button = $CanvasLayer/GameOverPanel/CenterContainer/VBoxContainer/RestartButton
@onready var chat_ui: Control = $CanvasLayer/HUD/ChatUI

## Replicated game variables (replicated via MultiplayerSynchronizer)
var time_left: float = 180.0
var total_crickets: int = 0
var eaten_crickets: int = 0
var total_lizards: int = 0
var captured_lizards: int = 0
var game_state: String = "lobby"
var winner_name: String = ""

# HUD Compass & Radar
var _compass_bar: Panel
var _compass_label: Label
var _cricket_icon: Label
var _switch_icon: Label

# Map Selection UI & State
var _basic_map_btn: Button
var _sunroom_map_btn: Button
var _chosen_map: String = "Basic House":
	set(val):
		_chosen_map = val
		var map = get_node_or_null("Map")
		if map:
			map.generate_selected_map(val)

# Dynamic Lobby & Pause Panels
var _main_menu_panel: VBoxContainer
var _net_setup_panel: VBoxContainer
var _lobby_room_panel: HBoxContainer
var _settings_panel: VBoxContainer
var _credits_panel: VBoxContainer
var _dev_tools_panel: Panel # F1 QA dev overlay
var _pause_menu_panel: Panel # Esc Pause Menu

# Dynamic UI Controls
var _ip_input_edit: LineEdit
var _player_list_container: VBoxContainer
var _tp_btn_1: Button
var _tp_btn_2: Button
var _tp_btn_3: Button
var _gekko_btn: Button
var _cat_btn: Button
var _start_game_btn: Button

# Configuration variables
var _settings_volume_master: float = 0.8
var _settings_fullscreen: bool = false
var _settings_shadows: bool = true
var _settings_time_limit: float = 180.0

# Orbital Camera Background variable
var _camera_angle: float = 0.0

# Light Switch state variables
var lights_on: bool = true
var lights_cooldown: float = 0.0
var _switch_prompt: Label

var _player_scene := preload("res://game_objects/tuteca.tscn")
var _cat_scene    := preload("res://game_objects/cat.tscn")
var _ai_cat_scene := preload("res://game_objects/ai_cat.tscn")

## The character this local player has chosen.
var _chosen_character: String = "gekko"

## Server-side map: peer_id → character string.
## Populated when a client sends _rpc_set_character, or directly for the host.
var _peer_characters: Dictionary = {}

# Ambient Music Track paths & Volume
const MUSIC_MAIN_MENU := "res://assets/sounds/main_menu.mp3"
const MUSIC_PLAY := "res://assets/sounds/play.mp3"
const MUSIC_HURRY_UP := "res://assets/sounds/hurry_up.mp3"
const MUSIC_AMBIENT_VOLUME_DB := -18.0

var _music_player: AudioStreamPlayer
var _current_music_track: String = ""

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Point spawner at the Players container and supply a spawn factory.
	spawner.spawn_path     = spawner.get_path_to(players)
	spawner.spawn_function = _on_spawner_create

	# Set authority to server (peer 1) for the main scene root
	set_multiplayer_authority(1)

	# Setup server-replicated game variables via MultiplayerSynchronizer
	var synchronizer := MultiplayerSynchronizer.new()
	var config := SceneReplicationConfig.new()
	config.add_property(".:time_left")
	config.add_property(".:total_crickets")
	config.add_property(".:eaten_crickets")
	config.add_property(".:total_lizards")
	config.add_property(".:captured_lizards")
	config.add_property(".:game_state")
	config.add_property(".:winner_name")
	config.add_property(".:_chosen_map")
	config.add_property(".:lights_on")
	config.add_property(".:lights_cooldown")
	synchronizer.replication_config = config
	synchronizer.root_path = get_path()
	synchronizer.set_multiplayer_authority(1)
	add_child(synchronizer)

	# Setup the light switch dynamic prompt on the HUD
	_switch_prompt = Label.new()
	_switch_prompt.text = "Press E to toggle lights"
	_switch_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_switch_prompt.anchor_left = 0.5
	_switch_prompt.anchor_top = 0.8
	_switch_prompt.anchor_right = 0.5
	_switch_prompt.anchor_bottom = 0.8
	_switch_prompt.offset_left = -250
	_switch_prompt.offset_top = 0
	_switch_prompt.offset_right = 250
	_switch_prompt.offset_bottom = 30
	_switch_prompt.visible = false
	var label_settings := LabelSettings.new()
	label_settings.font_size = 20
	label_settings.outline_size = 4
	label_settings.outline_color = Color.BLACK
	_switch_prompt.label_settings = label_settings
	hud.add_child(_switch_prompt)

	# ── Multiplayer signals ───────────────────────────────────────────────
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

	# ── GameOver controls ───────────────────────────────────────────────
	restart_btn.pressed.connect(_on_restart_pressed)

	# ── Rebuild dynamic lobby UI ──────────────────────────────────────────
	_build_lobby_ui()
	_build_dev_tools_ui()
	_build_pause_menu_ui()

	if chat_ui:
		chat_ui.message_sent.connect(_on_chat_message_sent)

	# Setup HUD Compass (hidden initially)
	_compass_bar = Panel.new()
	_compass_bar.custom_minimum_size = Vector2(300, 30)
	_compass_bar.anchor_left = 0.5
	_compass_bar.anchor_right = 0.5
	_compass_bar.anchor_top = 0.05
	_compass_bar.anchor_bottom = 0.05
	_compass_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_compass_bar.offset_left = -150
	_compass_bar.offset_top = 10
	_compass_bar.offset_right = 150
	_compass_bar.offset_bottom = 40
	_compass_bar.visible = false
	hud.add_child(_compass_bar)

	_compass_label = Label.new()
	_compass_label.text = "N                  E                  S                  W"
	_compass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compass_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_compass_label.anchor_right = 1.0
	_compass_label.anchor_bottom = 1.0
	_compass_bar.add_child(_compass_label)
	
	_cricket_icon = Label.new()
	_cricket_icon.text = "🦗"
	_cricket_icon.label_settings = LabelSettings.new()
	_cricket_icon.label_settings.font_size = 14
	_compass_bar.add_child(_cricket_icon)

	_switch_icon = Label.new()
	_switch_icon.text = "🔴"
	_switch_icon.label_settings = LabelSettings.new()
	_switch_icon.label_settings.font_size = 14
	_compass_bar.add_child(_switch_icon)

	# ── Ambient Background Music Setup ──────────────────────────────────
	_setup_music_player()
	_update_music_state()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_M and event.ctrl_pressed:
		var master_bus := AudioServer.get_bus_index("Master")
		AudioServer.set_bus_mute(master_bus, not AudioServer.is_bus_mute(master_bus))
		print("[Audio Settings] Mute toggled. Current state: ", AudioServer.is_bus_mute(master_bus))
	
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		_toggle_dev_tools()

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if game_state == "playing":
			_toggle_pause_menu()

	if event is InputEventKey and event.pressed and event.keycode == KEY_E and not _is_typing():
		var local_player = players.get_node_or_null(str(multiplayer.get_unique_id()))
		if local_player and is_instance_valid(local_player):
			var switch_pos := Vector3(16.0, 14.0, -48.7) if _chosen_map == "Basic House" else Vector3(16.0, 16.0, -48.7)
			if local_player.global_position.distance_to(switch_pos) < 5.0:
				rpc_toggle_lights.rpc()

# ─────────────────────────────────────────────────────────────────────────────
# Ambient Background Music System
# ─────────────────────────────────────────────────────────────────────────────
func _setup_music_player() -> void:
	if _music_player != null and is_instance_valid(_music_player):
		return
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "BackgroundMusicPlayer"
	_music_player.volume_db = MUSIC_AMBIENT_VOLUME_DB
	_music_player.bus = "Master"
	add_child(_music_player)

func _play_music(track_path: String) -> void:
	if _current_music_track == track_path and _music_player != null and _music_player.playing:
		return
	_current_music_track = track_path
	if _music_player == null or not is_instance_valid(_music_player):
		_setup_music_player()
	if not FileAccess.file_exists(track_path):
		push_warning("[Audio] Music track file not found: %s" % track_path)
		return
	var stream = load(track_path)
	if stream is AudioStreamMP3:
		stream.loop = true
	elif stream is AudioStreamOggVorbis:
		stream.loop = true
	_music_player.stream = stream
	_music_player.volume_db = MUSIC_AMBIENT_VOLUME_DB
	_music_player.play()
	print("[Audio] Playing ambient music: %s (looping, volume: %.1f dB)" % [track_path, MUSIC_AMBIENT_VOLUME_DB])

func _update_music_state() -> void:
	if game_state == "playing":
		if time_left <= 60.0 and time_left > 0.0:
			_play_music(MUSIC_HURRY_UP)
		else:
			_play_music(MUSIC_PLAY)
	elif game_state == "lobby" or game_state == "lobby_room":
		_play_music(MUSIC_MAIN_MENU)

# ─────────────────────────────────────────────────────────────────────────────
# Dynamic UI Builder
# ─────────────────────────────────────────────────────────────────────────────
func _build_lobby_ui() -> void:
	for child in lobby_ui.get_children():
		child.queue_free()
		
	var bg_panel = Panel.new()
	bg_panel.set_anchors_and_offsets_preset(15)
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.05, 0.05, 0.08, 0.65)
	bg_panel.add_theme_stylebox_override("panel", bg_style)
	lobby_ui.add_child(bg_panel)

	# --- 1. Main Menu Panel ---
	_main_menu_panel = VBoxContainer.new()
	_main_menu_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_main_menu_panel.set_anchors_and_offsets_preset(15)
	_main_menu_panel.add_theme_constant_override("separation", 15)
	bg_panel.add_child(_main_menu_panel)
	
	var title = Label.new()
	title.text = "TUTECA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.label_settings = LabelSettings.new()
	title.label_settings.font_size = 48
	title.label_settings.font_color = Color(0.4, 0.9, 0.5)
	_main_menu_panel.add_child(title)
	
	var subtitle = Label.new()
	subtitle.text = "Cat vs Lizard - Hide & Seek"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.label_settings = LabelSettings.new()
	subtitle.label_settings.font_size = 18
	subtitle.label_settings.font_color = Color(0.7, 0.7, 0.7)
	_main_menu_panel.add_child(subtitle)
	
	var sep := HSeparator.new()
	_main_menu_panel.add_child(sep)
	
	var sp_btn = Button.new()
	sp_btn.text = "Single Player"
	sp_btn.custom_minimum_size = Vector2(250, 40)
	sp_btn.pressed.connect(_on_single_player_pressed)
	_style_button(sp_btn)
	_main_menu_panel.add_child(sp_btn)
	
	var mp_btn = Button.new()
	mp_btn.text = "Multiplayer Lobby"
	mp_btn.custom_minimum_size = Vector2(250, 40)
	mp_btn.pressed.connect(func(): _switch_screen("net_setup"))
	_style_button(mp_btn)
	_main_menu_panel.add_child(mp_btn)
	
	var settings_btn = Button.new()
	settings_btn.text = "Settings"
	settings_btn.custom_minimum_size = Vector2(250, 40)
	settings_btn.pressed.connect(func(): _switch_screen("settings"))
	_style_button(settings_btn)
	_main_menu_panel.add_child(settings_btn)
	
	var credits_btn = Button.new()
	credits_btn.text = "Credits"
	credits_btn.custom_minimum_size = Vector2(250, 40)
	credits_btn.pressed.connect(func(): _switch_screen("credits"))
	_style_button(credits_btn)
	_main_menu_panel.add_child(credits_btn)
	
	var exit_btn = Button.new()
	exit_btn.text = "Exit"
	exit_btn.custom_minimum_size = Vector2(250, 40)
	exit_btn.pressed.connect(func(): get_tree().quit())
	_style_button(exit_btn)
	_main_menu_panel.add_child(exit_btn)

	# --- 2. Net Setup Panel ---
	_net_setup_panel = VBoxContainer.new()
	_net_setup_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_net_setup_panel.set_anchors_and_offsets_preset(15)
	_net_setup_panel.add_theme_constant_override("separation", 15)
	_net_setup_panel.visible = false
	bg_panel.add_child(_net_setup_panel)
	
	var mp_title = Label.new()
	mp_title.text = "MULTIPLAYER SETUP"
	mp_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mp_title.label_settings = LabelSettings.new()
	mp_title.label_settings.font_size = 32
	_net_setup_panel.add_child(mp_title)
	
	var ip_label = Label.new()
	ip_label.text = "Enter Server IP Address:"
	ip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_net_setup_panel.add_child(ip_label)
	
	_ip_input_edit = LineEdit.new()
	_ip_input_edit.text = "127.0.0.1"
	_ip_input_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ip_input_edit.custom_minimum_size = Vector2(200, 30)
	_net_setup_panel.add_child(_ip_input_edit)
	
	var mp_row = HBoxContainer.new()
	mp_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_net_setup_panel.add_child(mp_row)
	
	var host_btn_net = Button.new()
	host_btn_net.text = "Host Server"
	host_btn_net.pressed.connect(_on_host_pressed)
	_style_button(host_btn_net)
	mp_row.add_child(host_btn_net)
	
	var join_btn_net = Button.new()
	join_btn_net.text = "Join Server"
	join_btn_net.pressed.connect(_on_join_pressed)
	_style_button(join_btn_net)
	mp_row.add_child(join_btn_net)
	
	var back_btn_net = Button.new()
	back_btn_net.text = "Back to Main Menu"
	back_btn_net.pressed.connect(func(): _switch_screen("main_menu"))
	_style_button(back_btn_net)
	_net_setup_panel.add_child(back_btn_net)

	# --- 3. Lobby Room Panel ---
	_lobby_room_panel = HBoxContainer.new()
	_lobby_room_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_lobby_room_panel.set_anchors_and_offsets_preset(15)
	_lobby_room_panel.add_theme_constant_override("separation", 50)
	_lobby_room_panel.visible = false
	bg_panel.add_child(_lobby_room_panel)
	
	var left_side = VBoxContainer.new()
	left_side.alignment = BoxContainer.ALIGNMENT_CENTER
	_lobby_room_panel.add_child(left_side)
	
	var list_title = Label.new()
	list_title.text = "Connected Players:"
	list_title.label_settings = LabelSettings.new()
	list_title.label_settings.font_size = 24
	left_side.add_child(list_title)
	
	_player_list_container = VBoxContainer.new()
	left_side.add_child(_player_list_container)
	
	var right_side = VBoxContainer.new()
	right_side.alignment = BoxContainer.ALIGNMENT_CENTER
	right_side.add_theme_constant_override("separation", 15)
	_lobby_room_panel.add_child(right_side)
	
	var custom_title = Label.new()
	custom_title.text = "Lobby Controls"
	custom_title.label_settings = LabelSettings.new()
	custom_title.label_settings.font_size = 24
	right_side.add_child(custom_title)
	
	var char_label = Label.new()
	char_label.text = "Choose Character:"
	right_side.add_child(char_label)

	var char_row = HBoxContainer.new()
	char_row.alignment = BoxContainer.ALIGNMENT_CENTER
	right_side.add_child(char_row)
	
	_gekko_btn = Button.new()
	_gekko_btn.text = "Gekko"
	_gekko_btn.pressed.connect(_on_gekko_selected)
	_style_button(_gekko_btn, Color(0.4, 1.0, 0.4))
	char_row.add_child(_gekko_btn)
	
	_cat_btn = Button.new()
	_cat_btn.text = "Cat"
	_cat_btn.pressed.connect(_on_cat_selected)
	_style_button(_cat_btn, Color(0.4, 0.8, 1.0))
	char_row.add_child(_cat_btn)
	
	var map_label = Label.new()
	map_label.text = "Select Map Arena:"
	right_side.add_child(map_label)

	var map_row = HBoxContainer.new()
	map_row.alignment = BoxContainer.ALIGNMENT_CENTER
	right_side.add_child(map_row)
	
	_basic_map_btn = Button.new()
	_basic_map_btn.text = "Basic House"
	_basic_map_btn.pressed.connect(func(): _on_map_type_selected("Basic House"))
	_style_button(_basic_map_btn, Color(0.4, 1.0, 0.4))
	map_row.add_child(_basic_map_btn)
	
	_sunroom_map_btn = Button.new()
	_sunroom_map_btn.text = "Sunroom Library"
	_sunroom_map_btn.pressed.connect(func(): _on_map_type_selected("Sunroom Library"))
	_style_button(_sunroom_map_btn, Color(0.4, 1.0, 0.4))
	map_row.add_child(_sunroom_map_btn)
	
	_start_game_btn = Button.new()
	_start_game_btn.text = "Start Match"
	_start_game_btn.pressed.connect(func(): rpc_start_game.rpc())
	_start_game_btn.custom_minimum_size = Vector2(200, 45)
	_style_button(_start_game_btn, Color(0.9, 0.3, 0.3))
	right_side.add_child(_start_game_btn)
	
	var leave_btn = Button.new()
	leave_btn.text = "Leave Lobby"
	leave_btn.pressed.connect(_on_leave_lobby_pressed)
	_style_button(leave_btn)
	right_side.add_child(leave_btn)

	# --- 4. Settings Panel ---
	_settings_panel = VBoxContainer.new()
	_settings_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_settings_panel.set_anchors_and_offsets_preset(15)
	_settings_panel.add_theme_constant_override("separation", 15)
	_settings_panel.visible = false
	bg_panel.add_child(_settings_panel)
	
	var settings_title = Label.new()
	settings_title.text = "SETTINGS & AUDIO"
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_title.label_settings = LabelSettings.new()
	settings_title.label_settings.font_size = 32
	_settings_panel.add_child(settings_title)
	
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 15)
	_settings_panel.add_child(grid)
	
	var vol_label = Label.new()
	vol_label.text = "Master Volume:"
	grid.add_child(vol_label)
	
	var vol_slider = HSlider.new()
	vol_slider.min_value = 0.0
	vol_slider.max_value = 1.0
	vol_slider.step = 0.05
	vol_slider.value = _settings_volume_master
	vol_slider.custom_minimum_size = Vector2(150, 20)
	vol_slider.value_changed.connect(_on_volume_changed)
	grid.add_child(vol_slider)
	
	var fs_label = Label.new()
	fs_label.text = "Fullscreen Mode:"
	grid.add_child(fs_label)
	
	var fs_check = CheckBox.new()
	fs_check.button_pressed = _settings_fullscreen
	fs_check.toggled.connect(_on_fullscreen_toggled)
	grid.add_child(fs_check)
	
	var sh_label = Label.new()
	sh_label.text = "Enable Shadows:"
	grid.add_child(sh_label)
	
	var sh_check = CheckBox.new()
	sh_check.button_pressed = _settings_shadows
	sh_check.toggled.connect(_on_shadows_toggled)
	grid.add_child(sh_check)
	
	var time_lbl = Label.new()
	time_lbl.text = "Round Duration:"
	grid.add_child(time_lbl)
	
	var time_opt = OptionButton.new()
	time_opt.add_item("2 Minutes", 120)
	time_opt.add_item("3 Minutes", 180)
	time_opt.add_item("5 Minutes", 300)
	time_opt.select(1)
	time_opt.item_selected.connect(_on_round_time_selected)
	grid.add_child(time_opt)
	
	var back_btn_settings = Button.new()
	back_btn_settings.text = "Apply & Back"
	back_btn_settings.pressed.connect(func():
		if game_state == "playing":
			_switch_screen("")
			lobby_ui.hide()
			if _pause_menu_panel:
				_pause_menu_panel.visible = true
		else:
			_switch_screen("main_menu")
	)
	_style_button(back_btn_settings)
	_settings_panel.add_child(back_btn_settings)

	# --- 5. Credits Panel ---
	_credits_panel = VBoxContainer.new()
	_credits_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_credits_panel.set_anchors_and_offsets_preset(15)
	_credits_panel.add_theme_constant_override("separation", 15)
	_credits_panel.visible = false
	bg_panel.add_child(_credits_panel)
	
	var cr_title = Label.new()
	cr_title.text = "GAME CREDITS"
	cr_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cr_title.label_settings = LabelSettings.new()
	cr_title.label_settings.font_size = 32
	_credits_panel.add_child(cr_title)
	
	var cr_label = Label.new()
	cr_label.text = "Developer: Pedro\nDeveloper: Hilmer Vivas\nDeveloper & 3D Artist: Alejandro Lopez\nDesigner Artist: Ivan Lopez"
	cr_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_credits_panel.add_child(cr_label)
	
	var back_btn_credits = Button.new()
	back_btn_credits.text = "Back"
	back_btn_credits.pressed.connect(func(): _switch_screen("main_menu"))
	_style_button(back_btn_credits)
	_credits_panel.add_child(back_btn_credits)

	_switch_screen("main_menu")

# ─────────────────────────────────────────────────────────────────────────────
# Dev Tools QA UI Panel
# ─────────────────────────────────────────────────────────────────────────────
func _build_dev_tools_ui() -> void:
	_dev_tools_panel = Panel.new()
	_dev_tools_panel.custom_minimum_size = Vector2(380, 230)
	_dev_tools_panel.anchor_left = 0.5
	_dev_tools_panel.anchor_top = 0.5
	_dev_tools_panel.anchor_right = 0.5
	_dev_tools_panel.anchor_bottom = 0.5
	_dev_tools_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dev_tools_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_dev_tools_panel.offset_left = -190
	_dev_tools_panel.offset_top = -115
	_dev_tools_panel.offset_right = 190
	_dev_tools_panel.offset_bottom = 115
	_dev_tools_panel.visible = false
	
	var dev_style = StyleBoxFlat.new()
	dev_style.bg_color = Color(0.12, 0.08, 0.08, 0.9)
	dev_style.border_width_left = 2
	dev_style.border_width_top = 2
	dev_style.border_width_right = 2
	dev_style.border_width_bottom = 2
	dev_style.border_color = Color(0.9, 0.3, 0.3)
	_dev_tools_panel.add_theme_stylebox_override("panel", dev_style)
	
	var main_canvas = $CanvasLayer
	main_canvas.add_child(_dev_tools_panel)
	
	var dev_layout = VBoxContainer.new()
	dev_layout.alignment = BoxContainer.ALIGNMENT_CENTER
	dev_layout.set_anchors_and_offsets_preset(15)
	dev_layout.add_theme_constant_override("separation", 10)
	_dev_tools_panel.add_child(dev_layout)
	
	var dev_lbl = Label.new()
	dev_lbl.text = "🛠️ QA DEV CONSOLE"
	dev_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dev_lbl.label_settings = LabelSettings.new()
	dev_lbl.label_settings.font_size = 18
	dev_lbl.label_settings.font_color = Color(1.0, 0.4, 0.4)
	dev_layout.add_child(dev_lbl)
	
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dev_layout.add_child(grid)
	
	# Teleport Button 1 (Desk or Table)
	var tp_desk = Button.new()
	tp_desk.pressed.connect(func():
		var lp = players.get_node_or_null(str(multiplayer.get_unique_id()))
		if lp:
			if _chosen_map == "Basic House":
				lp.global_position = Vector3(25.0, 9.5, -20.0) # Table top
			else:
				lp.global_position = Vector3(-20.0, 9.0, -23.0) # Study desk top
	)
	_style_button(tp_desk, Color(0.9, 0.4, 0.4), true)
	grid.add_child(tp_desk)
	_tp_btn_1 = tp_desk
	
	# Teleport Button 2 (Loft or Bed)
	var tp_loft = Button.new()
	tp_loft.pressed.connect(func():
		var lp = players.get_node_or_null(str(multiplayer.get_unique_id()))
		if lp:
			if _chosen_map == "Basic House":
				lp.global_position = Vector3(25.0, 5.0, 25.0) # Bed top
			else:
				lp.global_position = Vector3(16.0, 14.0, -42.0) # Mezzanine platform top
	)
	_style_button(tp_loft, Color(0.9, 0.4, 0.4), true)
	grid.add_child(tp_loft)
	_tp_btn_2 = tp_loft
	
	# Teleport Button 3 (Cat Tree or Sofa)
	var tp_tree = Button.new()
	tp_tree.pressed.connect(func():
		var lp = players.get_node_or_null(str(multiplayer.get_unique_id()))
		if lp:
			if _chosen_map == "Basic House":
				lp.global_position = Vector3(-25.0, 6.0, 20.0) # Sofa top
			else:
				lp.global_position = Vector3(-30.0, 20.5, 30.0) # Cat tree cushion top
	)
	_style_button(tp_tree, Color(0.9, 0.4, 0.4), true)
	grid.add_child(tp_tree)
	_tp_btn_3 = tp_tree
	
	# Spawn AI Cat
	var sp_ai = Button.new()
	sp_ai.text = "Spawn AI"
	sp_ai.pressed.connect(func():
		if multiplayer.is_server():
			_spawn_ai_cat()
		else:
			rpc_dev_spawn_ai.rpc_id(1)
	)
	_style_button(sp_ai, Color(0.9, 0.4, 0.4), true)
	grid.add_child(sp_ai)
	
	# Win Lizards
	var w_liz = Button.new()
	w_liz.text = "Win Liz"
	w_liz.pressed.connect(func():
		if multiplayer.is_server():
			eaten_crickets = total_crickets
			_check_win_conditions()
		else:
			rpc_dev_win_lizards.rpc_id(1)
	)
	_style_button(w_liz, Color(0.9, 0.4, 0.4), true)
	grid.add_child(w_liz)
	
	# Win Cats
	var w_cats = Button.new()
	w_cats.text = "Win Cat"
	w_cats.pressed.connect(func():
		if multiplayer.is_server():
			captured_lizards = total_lizards
			_check_win_conditions()
		else:
			rpc_dev_win_cats.rpc_id(1)
	)
	_style_button(w_cats, Color(0.9, 0.4, 0.4), true)
	grid.add_child(w_cats)
	
	# Toggle Noclip (Fly Mode)
	var btn_nc = Button.new()
	btn_nc.text = "Fly Mode"
	btn_nc.pressed.connect(func():
		var lp = players.get_node_or_null(str(multiplayer.get_unique_id()))
		if lp and "noclip" in lp:
			lp.noclip = not lp.noclip
			print("[Dev Tools] Toggled Noclip: ", lp.noclip)
	)
	_style_button(btn_nc, Color(0.9, 0.4, 0.4), true)
	grid.add_child(btn_nc)
	
	# Capture Self
	var btn_cap = Button.new()
	btn_cap.text = "Capture"
	btn_cap.pressed.connect(func():
		var lp_id = multiplayer.get_unique_id()
		if multiplayer.is_server():
			ai_capture_player(lp_id)
		else:
			rpc_capture_player.rpc_id(1, lp_id)
	)
	_style_button(btn_cap, Color(0.9, 0.4, 0.4), true)
	grid.add_child(btn_cap)
	
	# Add Time
	var btn_time = Button.new()
	btn_time.text = "+60 Secs"
	btn_time.pressed.connect(func():
		if multiplayer.is_server():
			time_left += 60.0
		else:
			rpc_dev_add_time.rpc_id(1)
	)
	_style_button(btn_time, Color(0.9, 0.4, 0.4), true)
	grid.add_child(btn_time)

	# Bottom Dev label
	var dev_hint = Label.new()
	dev_hint.text = "Press F1 to close this overlay"
	dev_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dev_hint.label_settings = LabelSettings.new()
	dev_hint.label_settings.font_size = 11
	dev_hint.label_settings.font_color = Color(0.7, 0.7, 0.7)
	dev_layout.add_child(dev_hint)

func _toggle_dev_tools() -> void:
	if _dev_tools_panel:
		_dev_tools_panel.visible = not _dev_tools_panel.visible
		if _dev_tools_panel.visible:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			if game_state == "playing":
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# Dev tools server-side actions RPC
@rpc("any_peer", "reliable")
func rpc_dev_spawn_ai() -> void:
	if multiplayer.is_server(): _spawn_ai_cat()

@rpc("any_peer", "reliable")
func rpc_dev_win_lizards() -> void:
	if multiplayer.is_server():
		eaten_crickets = total_crickets
		_check_win_conditions()

@rpc("any_peer", "reliable")
func rpc_dev_win_cats() -> void:
	if multiplayer.is_server():
		captured_lizards = total_lizards
		_check_win_conditions()

@rpc("any_peer", "reliable")
func rpc_dev_add_time() -> void:
	if multiplayer.is_server(): time_left += 60.0

# ─────────────────────────────────────────────────────────────────────────────
# Dynamic Escape Pause Menu UI Panel
# ─────────────────────────────────────────────────────────────────────────────
func _build_pause_menu_ui() -> void:
	_pause_menu_panel = Panel.new()
	_pause_menu_panel.custom_minimum_size = Vector2(300, 260)
	_pause_menu_panel.anchor_left = 0.5
	_pause_menu_panel.anchor_top = 0.5
	_pause_menu_panel.anchor_right = 0.5
	_pause_menu_panel.anchor_bottom = 0.5
	_pause_menu_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause_menu_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_pause_menu_panel.offset_left = -150
	_pause_menu_panel.offset_top = -130
	_pause_menu_panel.offset_right = 150
	_pause_menu_panel.offset_bottom = 130
	_pause_menu_panel.visible = false
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.9, 0.5)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	_pause_menu_panel.add_theme_stylebox_override("panel", style)
	
	$CanvasLayer.add_child(_pause_menu_panel)
	
	var layout = VBoxContainer.new()
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.set_anchors_and_offsets_preset(15)
	layout.add_theme_constant_override("separation", 15)
	_pause_menu_panel.add_child(layout)
	
	var title = Label.new()
	title.text = "MATCH PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.label_settings = LabelSettings.new()
	title.label_settings.font_size = 24
	title.label_settings.font_color = Color(0.4, 0.9, 0.5)
	layout.add_child(title)
	
	var resume_btn = Button.new()
	resume_btn.text = "Resume Match"
	resume_btn.pressed.connect(func():
		_pause_menu_panel.visible = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	)
	_style_button(resume_btn)
	layout.add_child(resume_btn)
	
	var set_btn = Button.new()
	set_btn.text = "Settings"
	set_btn.pressed.connect(func():
		_pause_menu_panel.visible = false
		lobby_ui.show()
		_switch_screen("settings")
	)
	_style_button(set_btn)
	layout.add_child(set_btn)
	
	var main_btn = Button.new()
	main_btn.text = "Exit to Lobby"
	main_btn.pressed.connect(func():
		_pause_menu_panel.visible = false
		_on_leave_lobby_pressed()
	)
	_style_button(main_btn)
	layout.add_child(main_btn)

func _toggle_pause_menu() -> void:
	if _pause_menu_panel == null:
		return
	if lobby_ui.visible:
		return # Do not open pause menu if in settings/screens
	_pause_menu_panel.visible = not _pause_menu_panel.visible
	if _pause_menu_panel.visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _switch_screen(screen_name: String) -> void:
	if _main_menu_panel:   _main_menu_panel.visible = (screen_name == "main_menu")
	if _net_setup_panel:   _net_setup_panel.visible = (screen_name == "net_setup")
	if _lobby_room_panel:  _lobby_room_panel.visible = (screen_name == "lobby_room")
	if _settings_panel:    _settings_panel.visible = (screen_name == "settings")
	if _credits_panel:     _credits_panel.visible = (screen_name == "credits")

# ─────────────────────────────────────────────────────────────────────────────
# Settings Callbacks
# ─────────────────────────────────────────────────────────────────────────────
func _on_volume_changed(val: float) -> void:
	_settings_volume_master = val
	var db = linear_to_db(val) if val > 0.0 else -80.0
	AudioServer.set_bus_volume_db(0, db)
	print("[Settings] Master Volume set to DB: ", db)

func _on_fullscreen_toggled(button_pressed: bool) -> void:
	_settings_fullscreen = button_pressed
	if button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	print("[Settings] Fullscreen toggled: ", button_pressed)

func _on_shadows_toggled(button_pressed: bool) -> void:
	_settings_shadows = button_pressed
	var map = get_node_or_null("Map")
	if map:
		for child in map.get_children():
			if child is Light3D:
				child.shadow_enabled = button_pressed
	print("[Settings] Shadows toggled: ", button_pressed)

func _on_round_time_selected(idx: int) -> void:
	var values = [120.0, 180.0, 300.0]
	_settings_time_limit = values[idx]
	print("[Settings] Round Duration set to: ", _settings_time_limit)

# ─────────────────────────────────────────────────────────────────────────────
# Character & Map selection logic
# ─────────────────────────────────────────────────────────────────────────────
func _on_gekko_selected() -> void:
	_chosen_character = "gekko"
	_update_character_ui()
	if multiplayer.multiplayer_peer != null:
		_rpc_set_character.rpc_id(1, "gekko")
	else:
		_peer_characters[1] = "gekko"
		_update_lobby_room_list()

func _on_cat_selected() -> void:
	_chosen_character = "cat"
	_update_character_ui()
	if multiplayer.multiplayer_peer != null:
		_rpc_set_character.rpc_id(1, "cat")
	else:
		_peer_characters[1] = "cat"
		_update_lobby_room_list()

func _update_character_ui() -> void:
	if _gekko_btn and _cat_btn:
		_gekko_btn.modulate = Color(0.4, 1.0, 0.4) if _chosen_character == "gekko" else Color.WHITE
		_cat_btn.modulate   = Color(0.4, 0.8, 1.0) if _chosen_character == "cat" else Color.WHITE

func _on_map_type_selected(type: String) -> void:
	_chosen_map = type
	_update_map_ui()

func _update_map_ui() -> void:
	if _basic_map_btn == null or _sunroom_map_btn == null:
		return
	_basic_map_btn.modulate = Color(0.4, 1.0, 0.4) if _chosen_map == "Basic House" else Color.WHITE
	_sunroom_map_btn.modulate = Color(0.4, 1.0, 0.4) if _chosen_map == "Sunroom Library" else Color.WHITE
	
	var is_host = multiplayer.is_server() or multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED
	_basic_map_btn.disabled = not is_host
	_sunroom_map_btn.disabled = not is_host
	
	# Update Dev Tools TP button labels dynamically based on selected map
	if _tp_btn_1 and _tp_btn_2 and _tp_btn_3:
		if _chosen_map == "Basic House":
			_tp_btn_1.text = "TP Table"
			_tp_btn_2.text = "TP Bed"
			_tp_btn_3.text = "TP Sofa"
		else:
			_tp_btn_1.text = "TP Desk"
			_tp_btn_2.text = "TP Loft"
			_tp_btn_3.text = "TP CatTree"

func _on_leave_lobby_pressed() -> void:
	multiplayer.multiplayer_peer = null
	_peer_characters.clear()
	for child in players.get_children():
		child.queue_free()
	game_state = "lobby"
	_switch_screen("main_menu")
	_update_map_ui()
	print("[Lobby] Disconnected/Closed Server.")

# ─────────────────────────────────────────────────────────────────────────────
# Spawner factory
# ─────────────────────────────────────────────────────────────────────────────
func _on_spawner_create(data: Dictionary) -> Node:
	var entity: Node3D
	if data["character"] == "ai_cat":
		entity = _ai_cat_scene.instantiate()
		entity.name = "AICat"
	else:
		var scene: PackedScene = _player_scene if data["character"] == "gekko" else _cat_scene
		entity = scene.instantiate()
		entity.name = str(data["peer_id"])
	if data.has("pos"):
		entity.position = data["pos"]
	return entity

func _spawn_position_for(character: String) -> Vector3:
	if character == "gekko":
		return Vector3(randf_range(-30.0, 30.0), 2.0, randf_range(-40.0, -25.0))
	return Vector3(randf_range(-30.0, 30.0), 2.0, randf_range(25.0, 40.0))

# ─────────────────────────────────────────────────────────────────────────────
# Match Quick Play and Network Buttons
# ─────────────────────────────────────────────────────────────────────────────
func _on_single_player_pressed() -> void:
	_on_host_pressed()

func _on_host_pressed() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err  := peer.create_server(PORT, MAX_PEERS)
	if err != OK:
		push_error("[Host] Failed to start server: %s" % error_string(err))
		return
	multiplayer.multiplayer_peer = peer
	print("[Host] Server started on port %d" % PORT)
	
	_peer_characters.clear()
	_peer_characters[1] = _chosen_character
	
	game_state = "lobby_room"
	_switch_screen("lobby_room")
	_update_lobby_room_list()
	_update_character_ui()
	_update_map_ui()

func _on_join_pressed() -> void:
	var ip := _ip_input_edit.text.strip_edges() if _ip_input_edit else ""
	if ip.is_empty():
		ip = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var err  := peer.create_client(ip, PORT)
	if err != OK:
		push_error("[Client] Failed to connect to %s:%d — %s" % [ip, PORT, error_string(err)])
		return
	multiplayer.multiplayer_peer = peer
	print("[Client] Connecting to %s:%d …" % [ip, PORT])

# ─────────────────────────────────────────────────────────────────────────────
# Multiplayer signals
# ─────────────────────────────────────────────────────────────────────────────
func _on_peer_connected(id: int) -> void:
	print("[Net] Peer connected: ", id)
	_update_map_ui()
	_update_lobby_room_list()
	if multiplayer.is_server():
		rpc_sync_peer_characters.rpc(_peer_characters)

func _on_peer_disconnected(id: int) -> void:
	print("[Net] Peer disconnected: ", id)
	_peer_characters.erase(id)
	if players.has_node(str(id)):
		players.get_node(str(id)).queue_free()
	
	if game_state == "lobby_room":
		_update_lobby_room_list()
		if multiplayer.is_server():
			rpc_sync_peer_characters.rpc(_peer_characters)
	else:
		_check_win_conditions()

func _on_connected_to_server() -> void:
	print("[Client] Connected! My peer ID: ", multiplayer.get_unique_id())
	game_state = "lobby_room"
	_switch_screen("lobby_room")
	_update_map_ui()
	_rpc_set_character.rpc_id(1, _chosen_character)

func _on_connection_failed() -> void:
	push_error("[Client] Connection to server failed!")
	_switch_screen("main_menu")
	_update_map_ui()

# ─────────────────────────────────────────────────────────────────────────────
# RPC Synchronization & Spawn triggers
# ─────────────────────────────────────────────────────────────────────────────
@rpc("any_peer", "call_local", "reliable")
func _rpc_set_character(character: String) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	_peer_characters[sender_id] = character
	print("[Server] Peer %d chose: %s" % [sender_id, character])
	if multiplayer.is_server():
		rpc_sync_peer_characters.rpc(_peer_characters)

@rpc("any_peer", "call_local", "reliable")
func rpc_sync_peer_characters(sync_dict: Dictionary) -> void:
	_peer_characters = sync_dict
	_update_lobby_room_list()

@rpc("any_peer", "call_local", "reliable")
func rpc_start_game() -> void:
	lobby_ui.hide()
	game_state = "playing"
	time_left = _settings_time_limit
	eaten_crickets = 0
	captured_lizards = 0
	
	var menu_camera = get_node_or_null("Camera3D")
	if menu_camera:
		menu_camera.current = false
		
	if multiplayer.is_server():
		total_lizards = 0
		for peer_id in _peer_characters:
			var character = _peer_characters[peer_id]
			_spawn_player(peer_id)
			
		if cricket_spawner and cricket_spawner.has_method("spawn_crickets_for_scene"):
			cricket_spawner.spawn_crickets_for_scene()
			await get_tree().physics_frame
			total_crickets = cricket_spawner.get_child_count()

func _spawn_player(id: int) -> void:
	if not multiplayer.is_server():
		return
	if players.has_node(str(id)):
		return
	var character: String = _peer_characters.get(id, "gekko")
	spawner.spawn({"peer_id": id, "character": character, "pos": _spawn_position_for(character)})
	print("[Server] Spawned %s for peer %d" % [character, id])
	
	if character == "gekko":
		total_lizards += 1
		_spawn_ai_cat()

func _spawn_ai_cat() -> void:
	if not multiplayer.is_server():
		return
	if players.has_node("AICat"):
		return
	spawner.spawn({"peer_id": 0, "character": "ai_cat", "pos": _spawn_position_for("cat")})
	print("[Server] AI cat spawned — run, Tuteca!")

func ai_capture_player(target_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var player_node = players.get_node_or_null(str(target_peer_id))
	if player_node and not player_node.captured:
		player_node.captured = true
		captured_lizards += 1
		print("[Server] AI cat caught lizard %d! Total: %d/%d" % [target_peer_id, captured_lizards, total_lizards])
		_check_win_conditions()

# ─────────────────────────────────────────────────────────────────────────────
# Local Process Loop: compass update & orbital camera panning
# ─────────────────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_update_music_state()

	if game_state == "lobby" or game_state == "lobby_room":
		_camera_angle += 0.06 * delta
		var radius := 42.0
		var height := 16.0
		var cam_pos := Vector3(cos(_camera_angle) * radius, height, sin(_camera_angle) * radius)
		var menu_camera = get_node_or_null("Camera3D")
		if menu_camera:
			menu_camera.global_position = cam_pos
			menu_camera.look_at(Vector3(0.0, 6.0, 0.0), Vector3.UP)

	if game_state == "lobby" or game_state == "lobby_room":
		lobby_ui.show()
		hud.hide()
		game_over_panel.hide()
	elif game_state == "playing":
		# Hide Lobby screen but respect Pause Menu overlay
		lobby_ui.visible = _settings_panel.visible
		hud.show()
		game_over_panel.hide()
		
		if multiplayer.is_server():
			time_left = max(0.0, time_left - delta)
			if time_left <= 0.0:
				_end_game("Cats")  # Gekkos ran out of time
			
			# Tick down light switch cooldown and automatically restore lights when it hits 0
			if not lights_on:
				lights_cooldown = max(0.0, lights_cooldown - delta)
				if lights_cooldown <= 0.0:
					lights_on = true
					print("[Server] Darkness duration ended. Lights automatically restored.")
				
		var minutes := int(time_left) / 60
		var seconds := int(time_left) % 60
		timer_label.text = "Time: %d:%02d" % [minutes, seconds]
		crickets_label.text = "Crickets: %d/%d" % [eaten_crickets, total_crickets]
		lizards_label.text = "Lizards Remaining: %d" % [total_lizards - captured_lizards]

		# Update visual room lights (supports map-specific light energies)
		var map_node = find_child("Map", true, false)
		if map_node:
			for child in map_node.get_children():
				if child is OmniLight3D:
					if not lights_on:
						child.light_energy = 0.0
					else:
						# Restore map-specific energy
						if _chosen_map == "Basic House":
							child.light_energy = 8.0
						else:
							# Sunroom has ceiling lights (energy 24) and pendant lights (energy 22)
							if child.position.y > 20.0 and abs(child.position.x) < 20.0:
								child.light_energy = 22.0
							else:
								child.light_energy = 24.0

		# Update switch prompt visibility and text based on 3D distance to switch
		var show_prompt := false
		var local_player = players.get_node_or_null(str(multiplayer.get_unique_id()))
		if local_player and is_instance_valid(local_player):
			var switch_pos := Vector3(16.0, 14.0, -48.7) if _chosen_map == "Basic House" else Vector3(16.0, 16.0, -48.7)
			if local_player.global_position.distance_to(switch_pos) < 5.0:
				show_prompt = true
				
		if _switch_prompt:
			if show_prompt:
				var local_id := multiplayer.get_unique_id()
				var is_cat: bool = _peer_characters.get(local_id, "gekko") == "cat"
				if lights_on:
					if is_cat:
						_switch_prompt.text = "Press E to turn OFF lights"
					else:
						_switch_prompt.text = "Only Cats can turn off lights"
				else:
					if not is_cat:
						_switch_prompt.text = "Press E to turn ON lights early (Timer: %.1fs)" % lights_cooldown
					else:
						_switch_prompt.text = "Lights Sabotaged! Restoring in %.1fs" % lights_cooldown
				_switch_prompt.visible = true
			else:
				_switch_prompt.visible = false
		
		if _compass_bar:
			_compass_bar.visible = true
			
		if local_player and is_instance_valid(local_player) and _compass_bar:
			var cam = local_player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D")
			if cam:
				var cam_forward = -cam.global_transform.basis.z.normalized()
				var forward_2d = Vector2(cam_forward.x, cam_forward.z).normalized()
				var look_angle = forward_2d.angle()
				
				var deg = int(rad_to_deg(look_angle) + 450) % 360
				var dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
				var d_str = dirs[int((deg + 22.5) / 45) % 8]
				_compass_label.text = "%d° %s" % [deg, d_str]
				
				var nearest_cricket: Node3D = null
				var min_dist := 999999.0
				var crickets = find_child("CricketSpawner", true, false)
				if crickets:
					for cricket in crickets.get_children():
						var dist = local_player.global_position.distance_to(cricket.global_position)
						if dist < min_dist:
							min_dist = dist
							nearest_cricket = cricket
							
				if nearest_cricket and is_instance_valid(nearest_cricket):
					var diff = nearest_cricket.global_position - local_player.global_position
					var diff_2d = Vector2(diff.x, diff.z).normalized()
					var angle_diff = forward_2d.angle_to(diff_2d)
					
					if abs(angle_diff) < PI / 2.0:
						_cricket_icon.visible = true
						var factor = angle_diff / (PI / 2.0)
						_cricket_icon.offset_left = 150 + factor * 130 - 8
						_cricket_icon.offset_top = 5
					else:
						_cricket_icon.visible = false
				else:
					_cricket_icon.visible = false
					
				var switch_pos := Vector3(16.0, 14.0, -48.7) if _chosen_map == "Basic House" else Vector3(16.0, 16.0, -48.7)
				var diff_sw = switch_pos - local_player.global_position
				var diff_sw_2d = Vector2(diff_sw.x, diff_sw.z).normalized()
				var angle_diff_sw = forward_2d.angle_to(diff_sw_2d)
				
				if abs(angle_diff_sw) < PI / 2.0:
					_switch_icon.visible = true
					var factor = angle_diff_sw / (PI / 2.0)
					_switch_icon.offset_left = 150 + factor * 130 - 8
					_switch_icon.offset_top = 5
				else:
					_switch_icon.visible = false
		
	elif game_state == "game_over":
		if _compass_bar:
			_compass_bar.visible = false
		lobby_ui.hide()
		hud.hide()
		game_over_panel.show()
		win_label.text = "%s Win!" % winner_name
		if Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

# ─────────────────────────────────────────────────────────────────────────────
# Lobby updates list helper
# ─────────────────────────────────────────────────────────────────────────────
func _update_lobby_room_list() -> void:
	if _player_list_container == null:
		return
	for child in _player_list_container.get_children():
		child.queue_free()
		
	for peer_id in _peer_characters:
		var character = _peer_characters[peer_id]
		var label = Label.new()
		var suffix = " (Host)" if peer_id == 1 else ""
		var local_suffix = " (You)" if peer_id == multiplayer.get_unique_id() else ""
		label.text = "• Player %d%s%s — %s" % [peer_id, suffix, local_suffix, "Gekko" if character == "gekko" else "Cat"]
		_player_list_container.add_child(label)
	
	if _start_game_btn:
		var is_host = multiplayer.is_server() or multiplayer.multiplayer_peer == null
		_start_game_btn.visible = is_host
		_start_game_btn.disabled = not is_host

# ─────────────────────────────────────────────────────────────────────────────
# Win checks & restart
# ─────────────────────────────────────────────────────────────────────────────
func _check_win_conditions() -> void:
	if not multiplayer.is_server():
		return
	if game_state != "playing":
		return
	
	if captured_lizards >= total_lizards and total_lizards > 0:
		_end_game("Cats")
		return
		
	if eaten_crickets >= total_crickets and total_crickets > 0:
		_end_game("Lizards")
		return

func _end_game(winner: String) -> void:
	winner_name = winner
	game_state = "game_over"
	print("[Server] Game ended! Winner: ", winner)

func _on_restart_pressed() -> void:
	if not multiplayer.is_server():
		_rpc_request_restart.rpc_id(1)
		return
	
	time_left = _settings_time_limit
	eaten_crickets = 0
	captured_lizards = 0
	
	for child in players.get_children():
		players.remove_child(child)
		child.queue_free()
		
	total_lizards = 0
	for peer_id in _peer_characters:
		var character = _peer_characters[peer_id]
		_spawn_player(peer_id)
		
	if cricket_spawner and cricket_spawner.has_method("spawn_crickets_for_scene"):
		cricket_spawner.spawn_crickets_for_scene()
		await get_tree().physics_frame
		total_crickets = cricket_spawner.get_child_count()
		
	game_state = "playing"

@rpc("any_peer", "reliable")
func _rpc_request_restart() -> void:
	if multiplayer.is_server():
		_on_restart_pressed()

# ─────────────────────────────────────────────────────────────────────────────
# Cricket eating & score synced
# ─────────────────────────────────────────────────────────────────────────────
func collect_cricket(cricket_name: String) -> void:
	notify_cricket_eaten(cricket_name)

func notify_cricket_eaten(cricket_name: String) -> void:
	if multiplayer.is_server():
		_rpc_delete_cricket.rpc(cricket_name)
	else:
		_rpc_delete_cricket.rpc_id(1, cricket_name)

@rpc("any_peer", "call_local", "reliable")
func _rpc_delete_cricket(cricket_name: String) -> void:
	var c_node = cricket_spawner.get_node_or_null(cricket_name)
	if c_node:
		# Play eat sound in 3D space at the cricket position
		if FileAccess.file_exists("res://assets/sounds/cricket_eaten.mp3"):
			var eat_player := AudioStreamPlayer3D.new()
			eat_player.stream = load("res://assets/sounds/cricket_eaten.mp3")
			eat_player.volume_db = 0.0
			eat_player.unit_size = 5.0
			eat_player.global_position = c_node.global_position
			get_tree().root.add_child(eat_player)
			eat_player.play()
			eat_player.finished.connect(func(): eat_player.queue_free())

		c_node.queue_free()
		eaten_crickets += 1
		if multiplayer.is_server():
			_check_win_conditions()

@rpc("any_peer", "reliable")
func rpc_capture_player(target_peer_id: int) -> void:
	var player_node = players.get_node_or_null(str(target_peer_id))
	if player_node and not player_node.captured:
		player_node.captured = true
		if multiplayer.is_server():
			captured_lizards += 1
			print("[Server] Peer %d caught lizard %d! Total: %d/%d" % [multiplayer.get_remote_sender_id(), target_peer_id, captured_lizards, total_lizards])
			_check_win_conditions()

# ─────────────────────────────────────────────────────────────────────────────
# Chat UI callbacks
# ─────────────────────────────────────────────────────────────────────────────
func _on_chat_message_sent(message_text: String) -> void:
	if not message_text.is_empty():
		rpc_send_chat_message.rpc_id(1, message_text)

@rpc("any_peer", "call_local", "reliable")
func rpc_send_chat_message(message: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	var sender_team = _peer_characters.get(sender_id, "gekko")
	var filtered = message.strip_edges()
	
	if chat_ui and chat_ui.has_method("filter_message"):
		filtered = chat_ui.filter_message(filtered)
		
	for peer_id in multiplayer.get_peers():
		var peer_team = _peer_characters.get(peer_id, "gekko")
		if peer_team == sender_team:
			rpc_receive_chat_message.rpc_id(peer_id, sender_id, sender_team, filtered)
	rpc_receive_chat_message.rpc_id(1, sender_id, sender_team, filtered)

@rpc("any_peer", "call_local", "reliable")
func rpc_receive_chat_message(sender_id: int, team_name: String, filtered_text: String) -> void:
	if chat_ui:
		chat_ui.add_chat_message(sender_id, team_name, filtered_text)

# ─────────────────────────────────────────────────────────────────────────────
# Dynamic Button Styling helper
# ─────────────────────────────────────────────────────────────────────────────
func _style_button(btn: Button, accent: Color = Color(0.4, 0.9, 0.5), is_dev_btn: bool = false) -> void:
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.12, 0.12, 0.16, 0.8)
	style_normal.border_width_left = 1
	style_normal.border_width_top = 1
	style_normal.border_width_right = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = Color(0.35, 0.35, 0.45, 0.8)
	style_normal.corner_radius_top_left = 6
	style_normal.corner_radius_top_right = 6
	style_normal.corner_radius_bottom_left = 6
	style_normal.corner_radius_bottom_right = 6
	if is_dev_btn:
		style_normal.content_margin_left = 6
		style_normal.content_margin_right = 6
		style_normal.content_margin_top = 4
		style_normal.content_margin_bottom = 4
	else:
		style_normal.content_margin_left = 16
		style_normal.content_margin_right = 16
		style_normal.content_margin_top = 8
		style_normal.content_margin_bottom = 8
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color(0.18, 0.18, 0.24, 0.95)
	style_hover.border_color = accent
	
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = Color(0.08, 0.08, 0.12, 1.0)
	style_pressed.border_color = accent.darkened(0.2)
	
	var style_disabled = style_normal.duplicate()
	style_disabled.bg_color = Color(0.08, 0.08, 0.1, 0.4)
	style_disabled.border_color = Color(0.2, 0.2, 0.2, 0.4)
	
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.add_theme_stylebox_override("disabled", style_disabled)
	
	if is_dev_btn:
		btn.custom_minimum_size = Vector2(110, 42)
		btn.add_theme_font_size_override("font_size", 14)
	else:
		btn.custom_minimum_size = Vector2(280, 52)
		btn.add_theme_font_size_override("font_size", 20)
		
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color(0.8, 0.8, 0.8))
	btn.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5))

@rpc("any_peer", "call_local", "reliable")
func rpc_toggle_lights() -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	var sender_char: String = _peer_characters.get(sender_id, "gekko")
	
	if lights_on:
		# Only cats (or server/host) can turn off the lights
		if sender_char == "cat" or sender_id == 1:
			lights_on = false
			lights_cooldown = 15.0
			print("[Server] Lights turned OFF by peer %d. Cooldown started." % sender_id)
	else:
		# Only lizards (gekkos) can turn them back on early, or anyone can turn them on once the timer finishes
		if sender_char == "gekko" or sender_id == 1 or lights_cooldown <= 0.0:
			lights_on = true
			lights_cooldown = 0.0
			print("[Server] Lights restored by peer %d." % sender_id)

func _is_typing() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus != null and focus is LineEdit
