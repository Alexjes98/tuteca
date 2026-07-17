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

var _player_scene := preload("res://player.tscn")
var _cat_scene    := preload("res://cat.tscn")

## The character this local player has chosen.
var _chosen_character: String = "gekko"

## Server-side map: peer_id → character string.
## Populated when a client sends _rpc_set_character, or directly for the host.
var _peer_characters: Dictionary = {}

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Point spawner at the Players container and supply a spawn factory.
	# spawn_function receives a Dictionary { "peer_id": int, "character": String }.
	spawner.spawn_path     = spawner.get_path_to(players)
	spawner.spawn_function = _on_spawner_create

	# ── Multiplayer signals ───────────────────────────────────────────────
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

	# ── Character selection buttons ───────────────────────────────────────
	gekko_btn.pressed.connect(_on_gekko_selected)
	cat_btn.pressed.connect(_on_cat_selected)
	_update_character_ui()   # highlight default selection

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
	var scene: PackedScene = _player_scene if data["character"] == "gekko" else _cat_scene
	var entity := scene.instantiate()
	entity.name = str(data["peer_id"])
	return entity

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
	_peer_characters.erase(id)
	if players.has_node(str(id)):
		players.get_node(str(id)).queue_free()

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
	spawner.spawn({"peer_id": id, "character": character})
	print("[Server] Spawned %s for peer %d" % [character, id])
