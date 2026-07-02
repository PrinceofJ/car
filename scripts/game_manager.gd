extends Node

@export_enum("Touge", "Test Floor") var environment: int = 0
@export var car: CharacterBody3D
@export var map_generator: Node3D
@export var test_floor: RigidBody3D

func _ready() -> void:
	if environment == 0:
		_setup_touge()
	else:
		_setup_test_floor()

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("Reset"):
		car.velocity = Vector3.ZERO
		_setup_touge()
	if Input.is_action_just_pressed("Reset2"):
		car.velocity = Vector3.ZERO
		_setup_test_floor()

func _setup_touge() -> void:
	if test_floor:
		test_floor.visible = false
		test_floor.process_mode = Node.PROCESS_MODE_DISABLED
		for child in test_floor.get_children():
			if child is CollisionShape3D:
				child.disabled = true

	if map_generator:
		map_generator.process_mode = Node.PROCESS_MODE_INHERIT
		map_generator.visible = true

		if not map_generator.is_inside_tree():
			await map_generator.ready

		await get_tree().process_frame

		if map_generator.has_method("get_spawn_position") and car:
			var spawn_pos: Vector3 = map_generator.get_spawn_position()
			var spawn_dir: Vector3 = map_generator.get_spawn_direction()
			car.global_position = spawn_pos
			car.velocity = Vector3.ZERO
			var look_target: Vector3 = spawn_pos + spawn_dir
			car.look_at(look_target, Vector3.UP)

func _setup_test_floor() -> void:
	if map_generator:
		map_generator.process_mode = Node.PROCESS_MODE_DISABLED
		map_generator.visible = false

	if test_floor:
		test_floor.visible = true
		test_floor.process_mode = Node.PROCESS_MODE_INHERIT
		for child in test_floor.get_children():
			if child is CollisionShape3D:
				child.disabled = false

	if car:
		var floor_y: float = test_floor.global_position.y + 150.5 if test_floor else 1.5
		car.global_position = Vector3(0, floor_y, 0)
		car.velocity = Vector3.ZERO
