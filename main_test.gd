extends Node3D

## Root controller for main_test.tscn.
## Manages ENet peer setup (host / client), the lobby UI,
## and player spawning via MultiplayerSpawner.

const PORT       := 13579
const MAX_PEERS  := 8

@onready var lobby_ui : Control            = $CanvasLayer/LobbyUI
@onready var ip_input : LineEdit           = $CanvasLayer/LobbyUI/PanelContainer/VBoxContainer/IPInput
@onready var players  : Node3D             = $Players
@onready var spawner  : MultiplayerSpawner = $MultiplayerSpawner

var _player_scene := preload("res://player.tscn")

func _ready() -> void:
	# Point spawner at the Players container and supply a spawn factory.
	# Using spawn_function avoids having to configure the auto-spawn list
	# in the .tscn; the spawner tracks all spawned nodes and replays them
	# for late-joining clients automatically.
	spawner.spawn_path    = spawner.get_path_to(players)
	spawner.spawn_function = _on_spawner_create

	# ── Multiplayer signals ───────────────────────────────────────────────
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

# ─────────────────────────────────────────────────────────────────────────────
# Spawner factory — called on ALL peers when spawn() is invoked on the server.
# ─────────────────────────────────────────────────────────────────────────────
func _on_spawner_create(peer_id: int) -> Node:
	var player := _player_scene.instantiate()
	player.name = str(peer_id)
	return player

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
	# Spawn the host's own player (peer id = 1)
	_spawn_player(multiplayer.get_unique_id())

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
	# Only the server is authoritative over spawning.
	if multiplayer.is_server():
		_spawn_player(id)

func _on_peer_disconnected(id: int) -> void:
	print("[Net] Peer disconnected: ", id)
	if players.has_node(str(id)):
		players.get_node(str(id)).queue_free()

func _on_connected_to_server() -> void:
	print("[Client] Connected! My peer ID: ", multiplayer.get_unique_id())
	lobby_ui.hide()
	# The server will call _spawn_player for us via peer_connected.

func _on_connection_failed() -> void:
	push_error("[Client] Connection to server failed!")
	# Re-show lobby so the user can retry
	lobby_ui.show()

# ─────────────────────────────────────────────────────────────────────────────
# Spawn helper — server-only
# ─────────────────────────────────────────────────────────────────────────────
func _spawn_player(id: int) -> void:
	if not multiplayer.is_server():
		return
	if players.has_node(str(id)):
		return  # Guard against double-spawning
	spawner.spawn(id)
	print("[Server] Spawned player for peer ", id)
