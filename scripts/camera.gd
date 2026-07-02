extends Camera3D

@export var target: Node3D
@export var base_height: float = 5.0
@export var behind_distance: float = 10.0
@export var look_ahead: float = 6.0
@export var look_ahead_up: float = 1.5

@export var follow_lerp: float = 4.0
@export var look_lerp: float = 6.0

@export var base_fov: float = 70.0
@export var max_fov: float = 90.0
@export var max_speed: float = 40.0


var velocity: Vector3 = Vector3.ZERO
var smoothed_look_target: Vector3 = Vector3.ZERO
var smoothed_cam_dir: Vector3 = Vector3.FORWARD

func _ready() -> void:
	if target:
		smoothed_look_target = target.global_transform.origin
		smoothed_cam_dir = -target.global_transform.basis.z.normalized()

func _physics_process(delta: float) -> void:
	if not target:
		return

	var forward_dir: Vector3 = -target.global_transform.basis.z.normalized()
	var speed: float = velocity.length()
	var speed_factor: float = clamp(speed / max_speed, 0.0, 1.0)

	# Camera direction blends between car facing and velocity direction
	var vel_flat := Vector3(velocity.x, 0, velocity.z)
	var vel_dir: Vector3 = vel_flat.normalized() if vel_flat.length() > 1.0 else forward_dir
	var blend: float = clamp(speed_factor * 0.6, 0.0, 0.6)
	var desired_cam_dir: Vector3 = forward_dir.lerp(vel_dir, blend).normalized()
	smoothed_cam_dir = smoothed_cam_dir.lerp(desired_cam_dir, clamp(delta * 3.0, 0.0, 1.0))

	var current_height: float = lerp(base_height, 3.5, speed_factor * speed_factor)
	var desired_pos: Vector3 = target.global_transform.origin + smoothed_cam_dir * -behind_distance + Vector3.UP * current_height
	global_transform.origin = global_transform.origin.lerp(desired_pos, clamp(delta * follow_lerp, 0.0, 1.0))

	# Look ahead of the car along its forward direction
	var ahead_amount: float = look_ahead * speed_factor
	var look_target: Vector3 = target.global_transform.origin + forward_dir * ahead_amount + Vector3.UP * look_ahead_up
	smoothed_look_target = smoothed_look_target.lerp(look_target, clamp(delta * look_lerp, 0.0, 1.0))
	look_at(smoothed_look_target, Vector3.UP)

	var desired_fov: float = lerp(base_fov, max_fov, speed_factor)
	fov = lerp(fov, desired_fov, 10.0 * delta)
