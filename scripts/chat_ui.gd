extends Control

## UI script for the multiplayer team chat overlay.
## Listens for "Y" key to open input, formats team chat messages,
## and automatically hides after 10 seconds of inactivity.

signal message_sent(text: String)

const AUTO_HIDE_TIME: float = 10.0

@onready var panel_container: PanelContainer = $PanelContainer
@onready var chat_log: RichTextLabel = $PanelContainer/VBoxContainer/ScrollContainer/ChatLog
@onready var input_container: HBoxContainer = $PanelContainer/VBoxContainer/InputContainer
@onready var chat_input: LineEdit = $PanelContainer/VBoxContainer/InputContainer/ChatInput
@onready var send_button: Button = $PanelContainer/VBoxContainer/InputContainer/SendButton

var is_chat_active: bool = false
var _fade_timer: float = 10.0

func _ready() -> void:
	chat_log.bbcode_enabled = true
	chat_log.scroll_following = true
	send_button.pressed.connect(_on_send_pressed)
	chat_input.text_submitted.connect(_on_text_submitted)
	
	_set_chat_active(false)
	_reset_fade_timer()

func _process(delta: float) -> void:
	if is_chat_active or chat_input.has_focus():
		_fade_timer = AUTO_HIDE_TIME
		panel_container.visible = true
		panel_container.modulate.a = lerpf(panel_container.modulate.a, 1.0, 15.0 * delta)
	else:
		if _fade_timer > 0.0:
			_fade_timer -= delta
			panel_container.visible = true
			panel_container.modulate.a = lerpf(panel_container.modulate.a, 1.0, 15.0 * delta)
		else:
			panel_container.modulate.a = lerpf(panel_container.modulate.a, 0.0, 5.0 * delta)
			if panel_container.modulate.a < 0.01:
				panel_container.visible = false

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
		
	# If input is already active / focused, process Escape to close
	if is_chat_active or chat_input.has_focus():
		if event.keycode == KEY_ESCAPE:
			_set_chat_active(false)
			get_viewport().set_input_as_handled()
		return
		
	# Open chat on Y key or toggle_chat action
	if event.keycode == KEY_Y or event.is_action_pressed("toggle_chat"):
		_set_chat_active(true)
		get_viewport().set_input_as_handled()

func _reset_fade_timer() -> void:
	_fade_timer = AUTO_HIDE_TIME
	panel_container.visible = true
	panel_container.modulate.a = 1.0

func _set_chat_active(active: bool) -> void:
	is_chat_active = active
	_reset_fade_timer()
	
	if active:
		chat_input.grab_focus()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		chat_input.release_focus()
		var root = get_tree().current_scene
		if root and root.get("game_state") == "playing":
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_send_pressed() -> void:
	_submit_current_message()

func _on_text_submitted(_text: String) -> void:
	_submit_current_message()

func _submit_current_message() -> void:
	var msg := chat_input.text.strip_edges()
	if not msg.is_empty():
		message_sent.emit(msg)
		chat_input.clear()
	_set_chat_active(false)

## Adds a formatted message to the chat log window.
func add_chat_message(sender_id: int, team_name: String, text: String) -> void:
	var my_id := multiplayer.get_unique_id()
	var is_me := (sender_id == my_id)
	var display_name := "Me" if is_me else ("Player %d" % sender_id)
	
	var formatted := ""
	if team_name == "gekko":
		formatted = "[color=#55ff55]🦎 [Gekko] %s: %s[/color]\n" % [display_name, text]
	elif team_name == "cat":
		formatted = "[color=#66ccff]🐱 [Cat] %s: %s[/color]\n" % [display_name, text]
	else:
		formatted = "[color=#ffffaa]📢 System: %s[/color]\n" % text
		
	chat_log.append_text(formatted)
	_reset_fade_timer()
