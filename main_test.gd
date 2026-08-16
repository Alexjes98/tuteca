extends Node3D

## Root controller for main_test.tscn.
## Manages ENet peer setup (host / client), the lobby UI,
## player spawning via MultiplayerSpawner, and character selection.
##
## Character Selection Flow:
##   Host  → player picks character → clicks Host → server starts → spawns own player.
##   Client → player picks character → clicks Join → connects →
##             _on_connected_to_server sends chosen character to server via RPC →
##             server spawns the right scene for that peer.

const PORT       := 13579
const MAX_PEERS  := 8

@onready var lobby_ui        : Control            = $CanvasLayer/LobbyUI
@onready var ip_input        : LineEdit           = $CanvasLayer/LobbyUI/PanelContainer/VBoxContainer/IPInput
@onready var gekko_btn       : Button             = $CanvasLayer/LobbyUI/PanelContainer/VBoxContainer/CharacterRow/GekkoButton
@onready var cat_btn         : Button             = $CanvasLayer/LobbyUI/PanelContainer/VBoxContainer/CharacterRow/CatButton
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

var _player_scene := preload("res://game_objects/tuteca.tscn")
var _cat_scene    := preload("res://game_objects/cat.tscn")
var _ai_cat_scene := preload("res://game_objects/ai_cat.tscn")

## The character this local player has chosen.
var _chosen_character: String = "gekko"

## Server-side map: peer_id → character string.
## Populated when a client sends _rpc_set_character, or directly for the host.
var _peer_characters: Dictionary = {}

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
	synchronizer.replication_config = config
	synchronizer.root_path = get_path()
	synchronizer.set_multiplayer_authority(1)
	add_child(synchronizer)

	# ── Multiplayer signals ───────────────────────────────────────────────
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

	# ── Character selection buttons ───────────────────────────────────────
	gekko_btn.pressed.connect(_on_gekko_selected)
	cat_btn.pressed.connect(_on_cat_selected)
	restart_btn.pressed.connect(_on_restart_pressed)
	_update_character_ui()   # highlight default selection

	if chat_ui:
		chat_ui.message_sent.connect(_on_chat_message_sent)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_M and event.ctrl_pressed:
		var master_bus := AudioServer.get_bus_index("Master")
		AudioServer.set_bus_mute(master_bus, not AudioServer.is_bus_mute(master_bus))
		print("[Audio Settings] Mute toggled. Current state: ", AudioServer.is_bus_mute(master_bus))

# ─────────────────────────────────────────────────────────────────────────────
# Character selection
# ─────────────────────────────────────────────────────────────────────────────
func _on_gekko_selected() -> void:
	_chosen_character = "gekko"
	_update_character_ui()

func _on_cat_selected() -> void:
	_chosen_character = "cat"
	_update_character_ui()

func _update_character_ui() -> void:
	gekko_btn.modulate = Color.WHITE if _chosen_character == "cat" else Color(0.4, 1.0, 0.4)
	cat_btn.modulate   = Color.WHITE if _chosen_character == "gekko" else Color(0.4, 0.8, 1.0)

# ─────────────────────────────────────────────────────────────────────────────
# Spawner factory — called on ALL peers when spawner.spawn() is invoked on server.
# data = Dictionary { "peer_id": int, "character": String }
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

## Team spawn zones at opposite ends of the 100x100 house so cats can never
## insta-kill a gekko at round start (they spawn ~50+ m apart, beyond the AI
## cat's 25 m vision range).
func _spawn_position_for(character: String) -> Vector3:
	if character == "gekko":
		return Vector3(randf_range(-30.0, 30.0), 2.0, randf_range(-40.0, -25.0))
	return Vector3(randf_range(-30.0, 30.0), 2.0, randf_range(25.0, 40.0))

# ─────────────────────────────────────────────────────────────────────────────
# UI Button handlers
# ─────────────────────────────────────────────────────────────────────────────
func _on_host_pressed() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err  := peer.create_server(PORT, MAX_PEERS)
	if err != OK:
		push_error("[Host] Failed to start server: %s" % error_string(err))
		return
	multiplayer.multiplayer_peer = peer
	print("[Host] Server started on port %d" % PORT)
	lobby_ui.hide()
	# Host is always peer id 1; register character directly and spawn.
	_peer_characters[1] = _chosen_character
	_spawn_player(1)

func _on_join_pressed() -> void:
	var ip := ip_input.text.strip_edges()
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
# Multiplayer signal handlers
# ─────────────────────────────────────────────────────────────────────────────
func _on_peer_connected(id: int) -> void:
	print("[Net] Peer connected: ", id)
	# Server does NOT spawn here; it waits for the client's character RPC.

func _on_peer_disconnected(id: int) -> void:
	print("[Net] Peer disconnected: ", id)
	if _peer_characters.get(id, "") == "gekko":
		var player_node = players.get_node_or_null(str(id))
		if player_node:
			if player_node.captured:
				captured_lizards = max(0, captured_lizards - 1)
			total_lizards = max(0, total_lizards - 1)
	_peer_characters.erase(id)
	if players.has_node(str(id)):
		players.get_node(str(id)).queue_free()
	_check_win_conditions()

func _on_connected_to_server() -> void:
	print("[Client] Connected! My peer ID: ", multiplayer.get_unique_id())
	lobby_ui.hide()
	# Tell the server which character we chose.
	_rpc_set_character.rpc_id(1, _chosen_character)

func _on_connection_failed() -> void:
	push_error("[Client] Connection to server failed!")
	lobby_ui.show()

# ─────────────────────────────────────────────────────────────────────────────
# RPC — client → server: register character choice and trigger spawn.
# ─────────────────────────────────────────────────────────────────────────────
@rpc("any_peer", "reliable")
func _rpc_set_character(character: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	# Validate to avoid injection of unknown character strings.
	var valid_characters := ["gekko", "cat"]
	if character not in valid_characters:
		push_warning("[Server] Unknown character '%s' from peer %d — defaulting to gekko." % [character, sender_id])
		character = "gekko"
	_peer_characters[sender_id] = character
	print("[Server] Peer %d chose: %s" % [sender_id, character])
	_spawn_player(sender_id)

# ─────────────────────────────────────────────────────────────────────────────
# Spawn helper — server-only
# ─────────────────────────────────────────────────────────────────────────────
func _spawn_player(id: int) -> void:
	if not multiplayer.is_server():
		return
	if players.has_node(str(id)):
		return  # Guard against double-spawning
	var character: String = _peer_characters.get(id, "gekko")
	spawner.spawn({"peer_id": id, "character": character, "pos": _spawn_position_for(character)})
	print("[Server] Spawned %s for peer %d" % [character, id])
	
	# Update team counts
	if character == "gekko":
		total_lizards += 1
		# A Tuteca always faces an AI cat — spawn it if none exists yet.
		_spawn_ai_cat()
		
	# Transition from lobby to playing automatically when first player spawns
	if game_state == "lobby":
		game_state = "playing"
		time_left = 180.0
		eaten_crickets = 0
		captured_lizards = 0
		if cricket_spawner and cricket_spawner.has_method("spawn_crickets_for_scene"):
			cricket_spawner.spawn_crickets_for_scene()
		# Wait a physics frame for crickets to spawn
		await get_tree().physics_frame
		total_crickets = cricket_spawner.get_child_count()

# ─────────────────────────────────────────────────────────────────────────────
# AI cat — server-only spawn (replicated to clients via the MultiplayerSpawner)
# ─────────────────────────────────────────────────────────────────────────────
func _spawn_ai_cat() -> void:
	if not multiplayer.is_server():
		return
	if players.has_node("AICat"):
		return  # Only one AI cat at a time
	spawner.spawn({"peer_id": 0, "character": "ai_cat", "pos": _spawn_position_for("cat")})
	print("[Server] AI cat spawned — run, Tuteca!")

## Called directly by the AI cat (server-side) when it touches a lizard.
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
# Local Process Loop: updates HUD text and runs server countdown timer
# ─────────────────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	# 1. Update UI visibility depending on game state
	if game_state == "lobby":
		lobby_ui.show()
		hud.hide()
		game_over_panel.hide()
	elif game_state == "playing":
		lobby_ui.hide()
		hud.show()
		game_over_panel.hide()
		
		# Server-side timer tick
		if multiplayer.is_server():
			time_left = max(0.0, time_left - delta)
			if time_left <= 0.0:
				_end_game("Cats")  # Gekkos ran out of time
				
		# Update HUD labels
		var minutes := int(time_left) / 60
		var seconds := int(time_left) % 60
		timer_label.text = "Time: %d:%02d" % [minutes, seconds]
		crickets_label.text = "Crickets: %d/%d" % [eaten_crickets, total_crickets]
		lizards_label.text = "Lizards Remaining: %d" % [total_lizards - captured_lizards]
		
	elif game_state == "game_over":
		lobby_ui.hide()
		hud.hide()
		game_over_panel.show()
		win_label.text = "%s Win!" % winner_name
		# Free the mouse so the player can click the restart button.
		if Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

# ─────────────────────────────────────────────────────────────────────────────
# Server-side gameplay logic
# ─────────────────────────────────────────────────────────────────────────────
func collect_cricket(cricket_name: String) -> void:
	if not multiplayer.is_server():
		return
		
	# Replicated deletion across all clients
	_rpc_delete_cricket.rpc(cricket_name)
	
	eaten_crickets += 1
	print("[Server] Cricket collected: %s. Total: %d/%d" % [cricket_name, eaten_crickets, total_crickets])
	_check_win_conditions()

@rpc("call_local", "reliable")
func _rpc_delete_cricket(cricket_name: String) -> void:
	var cricket_node = cricket_spawner.get_node_or_null(cricket_name)
	if cricket_node:
		cricket_node.queue_free()

@rpc("any_peer", "reliable")
func rpc_capture_player(target_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
		
	# Verify sender has authority to capture (sender is a Cat)
	var sender_id := multiplayer.get_remote_sender_id()
	var sender_char = _peer_characters.get(sender_id, "")
	if sender_char != "cat" and sender_id != 1:
		push_warning("[Server] Non-cat peer %d tried to capture player %d!" % [sender_id, target_peer_id])
		return
		
	var player_node = players.get_node_or_null(str(target_peer_id))
	if player_node and not player_node.captured:
		player_node.captured = true
		captured_lizards += 1
		print("[Server] Lizard %d captured! Total: %d/%d" % [target_peer_id, captured_lizards, total_lizards])
		_check_win_conditions()

func _check_win_conditions() -> void:
	if game_state != "playing":
		return
		
	# 1. Gekkos eat all crickets
	if total_crickets > 0 and eaten_crickets >= total_crickets:
		_end_game("Tutecas")
	# 2. Cat captures all Gekkos
	elif total_lizards > 0 and captured_lizards >= total_lizards:
		_end_game("Cats")

func _end_game(winner: String) -> void:
	game_state = "game_over"
	winner_name = winner
	print("[Server] Game Over! Winner: %s" % winner)
	# The game stays on the game-over screen until someone clicks "Comenzar".

# ─────────────────────────────────────────────────────────────────────────────
# Restart button — any peer can click it; the server performs the restart.
# ─────────────────────────────────────────────────────────────────────────────
func _on_restart_pressed() -> void:
	if multiplayer.is_server():
		_restart_game()
	else:
		_rpc_request_restart.rpc_id(1)

@rpc("any_peer", "reliable")
func _rpc_request_restart() -> void:
	if multiplayer.is_server() and game_state == "game_over":
		_restart_game()

func _restart_game() -> void:
	if not multiplayer.is_server():
		return
		
	game_state = "playing"
	time_left = 180.0
	eaten_crickets = 0
	captured_lizards = 0
	winner_name = ""
	
	# Spawn new crickets
	if cricket_spawner and cricket_spawner.has_method("spawn_crickets_for_scene"):
		cricket_spawner.spawn_crickets_for_scene()
		
	await get_tree().physics_frame
	total_crickets = cricket_spawner.get_child_count()
	
	var lizards_count := 0
	for peer_id in _peer_characters:
		if _peer_characters[peer_id] == "gekko":
			lizards_count += 1
			
		# Uncapture and respawn players in their team's zone
		var player_node = players.get_node_or_null(str(peer_id))
		if player_node:
			player_node.captured = false
			player_node.global_position = _spawn_position_for(_peer_characters[peer_id])

	total_lizards = lizards_count

	# Move AI cats away from the respawn area so nobody dies instantly.
	for ai_cat in get_tree().get_nodes_in_group("ai_cats"):
		if ai_cat.has_method("reset_for_new_round"):
			ai_cat.reset_for_new_round()

# ─────────────────────────────────────────────────────────────────────────────
# Team Chat RPCs & Routing
# ─────────────────────────────────────────────────────────────────────────────
func _on_chat_message_sent(message_text: String) -> void:
	if multiplayer.is_server():
		_process_and_route_chat_message(1, message_text)
	else:
		rpc_send_chat_message.rpc_id(1, message_text)

@rpc("any_peer", "call_local", "reliable")
func rpc_send_chat_message(message: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	_process_and_route_chat_message(sender_id, message)

func _process_and_route_chat_message(sender_id: int, message: String) -> void:
	var sender_team: String = _peer_characters.get(sender_id, "gekko")
	var filtered := ChatFilter.filter_text(message)
	if filtered.strip_edges().is_empty():
		return
		
	# Route only to team members of sender_team
	for peer_id in multiplayer.get_peers():
		if _peer_characters.get(peer_id, "") == sender_team:
			rpc_receive_chat_message.rpc_id(peer_id, sender_id, sender_team, filtered)
			
	if _peer_characters.get(1, "") == sender_team:
		if multiplayer.is_server():
			if chat_ui:
				chat_ui.add_chat_message(sender_id, sender_team, filtered)
		else:
			rpc_receive_chat_message.rpc_id(1, sender_id, sender_team, filtered)

@rpc("any_peer", "call_local", "reliable")
func rpc_receive_chat_message(sender_id: int, team_name: String, filtered_text: String) -> void:
	if chat_ui:
		chat_ui.add_chat_message(sender_id, team_name, filtered_text)
