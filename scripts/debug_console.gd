extends Node3D

@export var world_viewport: Viewport

var fly_mode: bool = false
var console_open: bool = false

var fly_speed: float = 30.0
var fly_fast_speed: float = 80.0
var mouse_sensitivity: float = 0.002

var fly_camera: Camera3D
var game_camera: Camera3D
var pitch: float = 0.0
var yaw: float = 0.0

var console_panel: PanelContainer
var console_output: RichTextLabel
var console_input: LineEdit
var console_lines: PackedStringArray = []

func _ready() -> void:
	fly_camera = Camera3D.new()
	fly_camera.name = "FlyCamera"
	# Parented into world_viewport (not self) so it renders through the same
	# viewport as the game camera - otherwise it'd render into this node's own
	# viewport, which the full-screen retro display layer now sits in front of.
	if world_viewport:
		world_viewport.add_child(fly_camera)
	else:
		add_child(fly_camera)
	fly_camera.current = false

	_build_console_ui()
	_log("[color=gray]Dev console ready. Press F1 to toggle console. Type 'fly' to toggle flight mode.[/color]")

func _build_console_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)

	console_panel = PanelContainer.new()
	console_panel.visible = false
	console_panel.anchor_left = 0.0
	console_panel.anchor_right = 1.0
	console_panel.anchor_top = 0.0
	console_panel.anchor_bottom = 0.5
	console_panel.offset_left = 0
	console_panel.offset_right = 0
	console_panel.offset_top = 0
	console_panel.offset_bottom = 0
	canvas.add_child(console_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.92)
	style.border_color = Color(0.3, 0.8, 0.3, 0.6)
	style.border_width_bottom = 2
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	console_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	console_panel.add_child(vbox)

	console_output = RichTextLabel.new()
	console_output.bbcode_enabled = true
	console_output.scroll_following = true
	console_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	console_output.add_theme_font_size_override("normal_font_size", 14)
	vbox.add_child(console_output)

	console_input = LineEdit.new()
	console_input.placeholder_text = "Type a command..."
	console_input.caret_blink = true
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0.1, 0.1, 0.12, 1.0)
	input_style.border_color = Color(0.3, 0.8, 0.3, 0.4)
	input_style.border_width_top = 1
	input_style.content_margin_left = 8
	input_style.content_margin_bottom = 4
	input_style.content_margin_top = 4
	console_input.add_theme_stylebox_override("normal", input_style)
	console_input.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	console_input.add_theme_font_size_override("font_size", 14)
	console_input.text_submitted.connect(_on_command_submitted)
	vbox.add_child(console_input)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1 or event.physical_keycode == KEY_F1:
			_toggle_console()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE and console_open:
			_toggle_console()
			get_viewport().set_input_as_handled()
			return

	if fly_mode and not console_open and event is InputEventMouseMotion:
		yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, -PI * 0.49, PI * 0.49)
		fly_camera.rotation = Vector3(pitch, yaw, 0)
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not fly_mode:
		return

	var speed := fly_fast_speed if Input.is_key_pressed(KEY_CTRL) else fly_speed
	var move := Vector3.ZERO
	var cam_basis := fly_camera.global_transform.basis

	if Input.is_key_pressed(KEY_W):
		move -= cam_basis.z
	if Input.is_key_pressed(KEY_S):
		move += cam_basis.z
	if Input.is_key_pressed(KEY_A):
		move -= cam_basis.x
	if Input.is_key_pressed(KEY_D):
		move += cam_basis.x
	if Input.is_key_pressed(KEY_SPACE):
		move += Vector3.UP
	if Input.is_key_pressed(KEY_SHIFT):
		move -= Vector3.UP

	if move.length() > 0:
		move = move.normalized() * speed
	fly_camera.global_position += move * delta

func _toggle_console() -> void:
	console_open = not console_open
	console_panel.visible = console_open
	if console_open:
		console_input.grab_focus()
		console_input.clear()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		if fly_mode:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_command_submitted(text: String) -> void:
	console_input.clear()
	if text.strip_edges().is_empty():
		return

	_log("[color=lime]> " + text + "[/color]")
	_exec(text.strip_edges())

func _exec(cmd: String) -> void:
	var parts := cmd.split(" ", false)
	if parts.is_empty():
		return
	var keyword := parts[0].to_lower()

	match keyword:
		"fly":
			_toggle_fly()
		"speed":
			if parts.size() >= 2 and parts[1].is_valid_float():
				fly_speed = parts[1].to_float()
				_log("Fly speed set to " + str(fly_speed))
			else:
				_log("Usage: speed <value>  (current: " + str(fly_speed) + ")")
		"tp":
			if parts.size() >= 4:
				var x := parts[1].to_float()
				var y := parts[2].to_float()
				var z := parts[3].to_float()
				if fly_mode:
					fly_camera.global_position = Vector3(x, y, z)
				else:
					var car := _find_car()
					if car:
						car.global_position = Vector3(x, y, z)
						car.velocity = Vector3.ZERO
				_log("Teleported to " + str(Vector3(x, y, z)))
			else:
				_log("Usage: tp <x> <y> <z>")
		"pos":
			if fly_mode:
				_log(str(fly_camera.global_position))
			else:
				var car := _find_car()
				if car:
					_log(str(car.global_position))
		"help":
			_log("[color=yellow]Commands:[/color]")
			_log("  fly        - toggle flight camera")
			_log("  speed <n>  - set fly speed")
			_log("  tp <x y z> - teleport")
			_log("  pos        - print position")
			_log("  seed <n>   - regenerate track with seed")
			_log("  regen      - regenerate track (random seed)")
			_log("  help       - this list")
		"seed":
			if parts.size() >= 2 and parts[1].is_valid_int():
				_regen_track(parts[1].to_int())
			else:
				_log("Usage: seed <integer>")
		"regen":
			_regen_track(0)
		_:
			_log("[color=red]Unknown command: " + keyword + ". Type 'help' for commands.[/color]")

func _toggle_fly() -> void:
	fly_mode = not fly_mode
	if fly_mode:
		var cam_source: Viewport = world_viewport if world_viewport else get_viewport()
		game_camera = cam_source.get_camera_3d()
		if game_camera:
			fly_camera.global_transform = game_camera.global_transform
			fly_camera.fov = game_camera.fov
			var rot := fly_camera.rotation
			pitch = rot.x
			yaw = rot.y
			game_camera.current = false
		fly_camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_log("[color=cyan]Flight mode ON — WASD move, mouse look, Space up, Shift down, Ctrl fast[/color]")
	else:
		fly_camera.current = false
		if game_camera:
			game_camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_log("[color=cyan]Flight mode OFF[/color]")

func _find_car() -> CharacterBody3D:
	var car := get_tree().get_first_node_in_group("car") as CharacterBody3D
	if car:
		return car
	var root := get_tree().current_scene
	for child in root.get_children():
		if child is CharacterBody3D:
			return child
	return null

func _regen_track(seed_val: int) -> void:
	var touge := get_tree().get_first_node_in_group("touge")
	if not touge:
		for child in get_tree().current_scene.get_children():
			if child.has_method("generate"):
				touge = child
				break
	if touge and touge.has_method("generate"):
		for child in touge.get_children():
			child.queue_free()
		if seed_val != 0:
			touge.rng.seed = seed_val
		else:
			touge.rng.seed = randi()
		touge.road_points.clear()
		touge.road_rights.clear()
		touge.road_forwards.clear()
		touge.generate()
		_log("[color=green]Track regenerated (seed: " + str(touge.rng.seed) + ")[/color]")
	else:
		_log("[color=red]No touge generator found in scene.[/color]")

func _log(msg: String) -> void:
	console_lines.append(msg)
	if console_lines.size() > 200:
		console_lines = console_lines.slice(console_lines.size() - 200)
	console_output.clear()
	for line in console_lines:
		console_output.append_text(line + "\n")
