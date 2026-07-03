extends CharacterBody3D

@export_category("Movement")
@export var acceleration: float = 22.0
@export var max_speed: float = 45.0
@export var braking: float = 40.0
@export var friction: float = 7.0

@export_category("Steering")
@export var steering_speed: float = 4.5
@export var return_speed: float = 5.0
@export var max_steering_angle: float = 0.8
@export var drift_steering_mult: float = 1.6

@export_category("Drift Settings")
@export var normal_traction: float = 0.30
@export var drift_traction: float = 0.008
@export var drift_speed_threshold: float = 15.0
@export var drift_entry_angle: float = 0.1
@export var drift_exit_angle: float = 0.04
@export var drift_rotation_boost: float = 1.5
@export var drift_acceleration_bonus: float = 8.0
@export var traction_recovery_speed: float = 0.6
@export var drift_speed_lead_limit: float = 6.0

@export_category("Ground Handling")
@export var floor_snap_length_car: float = 0.6
@export var coyote_time: float = 0.15
@export var landing_smooth_speed: float = 12.0
@export var slope_slip_force: float = 45.0
@export var slope_align_speed: float = 8.0
@export var floor_normal_smooth: float = 10.0    # low-pass on the floor normal to kill facet jitter

@export_category("Airborne Physics")
@export var auto_nose_dive: float = 1.5
@export var air_pitch_control: float = 2.5
@export var air_roll_control: float = 3.5

var current_speed: float = 0.0
var steering_angle: float = 0.0
var is_drifting: bool = false
var current_traction: float = 0.10
var time_since_floor: float = 0.0
var smoothed_floor_normal: Vector3 = Vector3.UP
var visual_y_offset: float = 0.0

func _ready() -> void:
	add_to_group("car")
	floor_snap_length = floor_snap_length_car
	floor_max_angle = deg_to_rad(60)
	floor_constant_speed = true
	
func _physics_process(delta: float) -> void:
	handle_gravity(delta)
	handle_inputs(delta)
	calculate_drift_movement(delta)
	
	handle_air_physics(delta)
	update_floor_normal(delta)
	apply_slope_slippage(delta)
	align_with_floor(delta)
	
	if has_node("Camera3D"):
		$Camera3D.velocity = velocity
	move_and_slide()
	
	DebugOverlay.watch_property("Speed", current_speed)
	DebugOverlay.watch_property("Drifting", is_drifting)
	DebugOverlay.watch_property("Traction", current_traction)

	if has_node("Car_Mesh"):
		visual_y_offset = move_toward(visual_y_offset, 0.0, landing_smooth_speed * delta)
		$Car_Mesh.position.y = lerp($Car_Mesh.position.y, 0.0167998 + visual_y_offset, landing_smooth_speed * delta)

func handle_gravity(delta: float) -> void:
	if is_on_floor():
		if time_since_floor > 0.0:
			# Just landed - squash the visual mesh proportional to impact speed
			visual_y_offset = clampf(velocity.y * 0.05, -0.6, 0.0)
		time_since_floor = 0.0
		# Apply "stick weight" to prevent hopping on mesh seams
		if velocity.y < 0.0:
			velocity.y = -5.0
	else:
		time_since_floor += delta
		# Coyote time: don't apply full gravity immediately after leaving the floor
		if time_since_floor < coyote_time:
			velocity.y -= 29.4 * delta * 0.3
		else:
			velocity.y -= 29.4 * delta

func handle_inputs(delta: float) -> void:
	var input_forward: float = Input.get_action_strength("forward")
	var input_back: float = Input.get_action_strength("down")
	var input_handbrake: float = Input.get_action_strength("handbrake")

	# Acceleration, Braking, Reversing, and Handbrake
	if input_forward > 0:
		var accel: float = acceleration
		if is_drifting:
			accel += drift_acceleration_bonus
		current_speed = move_toward(current_speed, max_speed, accel * input_forward * delta)
	elif input_back > 0:
		if current_speed > 0.1:
			# Brake
			current_speed = move_toward(current_speed, 0.0, braking * input_back * delta)
		else:
			# Reverse
			current_speed = move_toward(current_speed, -max_speed / 2.0, acceleration * input_back * delta)
	elif input_handbrake > 0:
		# Handbrake specifically zeroes speed
		current_speed = move_toward(current_speed, 0.0, braking * input_handbrake * delta)
	else:
		# Coasting
		current_speed = move_toward(current_speed, 0.0, friction * delta)
	

	# Steering
	var input_steer: float = Input.get_axis("right", "left")
	var steer_mult: float = drift_steering_mult if is_drifting else 1.0
	if input_steer != 0:
		steering_angle = move_toward(steering_angle, input_steer * max_steering_angle, steering_speed * steer_mult * delta)
	else:
		steering_angle = move_toward(steering_angle, 0.0, return_speed * delta)

	# Rotate Car
	if abs(current_speed) > 1.0:
		var turn_dir: int = sign(current_speed)
		var rot_mult: float = drift_rotation_boost if is_drifting else 1.0
		rotate_object_local(Vector3.UP, steering_angle * turn_dir * rot_mult * delta)

func handle_air_physics(delta: float) -> void:
	if not is_on_floor():
		# 1. Natural Gravity Nose-Dive
		if velocity.y < -2.0:
			var dive_strength = min(abs(velocity.y) * 0.02, 1.0)
			rotate_object_local(Vector3.RIGHT, -auto_nose_dive * dive_strength * delta)

		# 2. Player-controlled pitch/roll while airborne (landing correction, tricks)
		var pitch_input: float = Input.get_action_strength("forward") - Input.get_action_strength("down")
		var roll_input: float = Input.get_axis("right", "left")
		rotate_object_local(Vector3.RIGHT, -pitch_input * air_pitch_control * delta)
		rotate_object_local(Vector3.FORWARD, roll_input * air_roll_control * delta)

func calculate_drift_movement(delta: float) -> void:
	var vel_flat := Vector3(velocity.x, 0, velocity.z)
	var speed := vel_flat.length()

	var forward_vector: Vector3 = -global_transform.basis.z
	forward_vector.y = 0
	forward_vector = forward_vector.normalized()

	# 1. Measure how sideways the car is moving vs facing (Slip Angle)
	var slip: float = 0.0
	if speed > 2.0:
		slip = forward_vector.cross(vel_flat.normalized()).length()

	var is_handbraking: bool = Input.is_action_pressed("handbrake")
	var can_drift: bool = abs(current_speed) >= drift_speed_threshold

	# 2. Determine Traction Target FIRST
	var target_traction: float = normal_traction
	
	if is_handbraking:
		# Handbrake instantly locks wheels, destroying lateral grip
		target_traction = drift_traction 
	elif is_drifting:
		# If we are actively drifting but let go of the handbrake, 
		# give back *some* grip so the player can control the slide, but keep it slippery
		target_traction = drift_traction * 3.0 
	else:
		# Normal driving grip
		target_traction = normal_traction

	# 3. Apply Traction (Snap instantly if losing grip, smooth if recovering)
	if target_traction < current_traction:
		current_traction = target_traction 
	else:
		current_traction = move_toward(current_traction, target_traction, traction_recovery_speed * delta)

	# 4. The Drift State Machine (Triggered by physics, not just a button)
	if not is_drifting:
		# If we are slipping enough (caused by handbraking + steering), trigger the arcade drift state
		if can_drift and slip > drift_entry_angle:
			is_drifting = true
	else:
		# Exit the drift if the car straightens out and the handbrake is released
		if (slip < drift_exit_angle and not is_handbraking) or abs(current_speed) <= drift_speed_threshold:
			is_drifting = false

	# 5. Keep the throttle target from running away from actual speed while
	# traction is too low to make use of it - otherwise the extra speed just
	# banks silently and dumps into velocity as a delayed "pop" once traction
	# (and thus the drift) ends.
	if is_drifting:
		current_speed = clampf(current_speed, speed - drift_speed_lead_limit, speed + drift_speed_lead_limit)

	# 6. Apply the final calculated movement
	var target_velocity: Vector3 = forward_vector * current_speed
	var y_vel: float = velocity.y

	velocity = velocity.lerp(target_velocity, current_traction)
	velocity.y = y_vel

func update_floor_normal(delta: float) -> void:
	# The road collision mesh is faceted (two triangles per quad, non-planar once
	# banked), so get_floor_normal() steps between values as the car crosses
	# triangle edges. Low-pass it so alignment and slope-slip read a stable normal
	# instead of shaking frame to frame.
	var t := clampf(floor_normal_smooth * delta, 0.0, 1.0)
	var target := get_floor_normal() if is_on_floor() else Vector3.UP
	smoothed_floor_normal = smoothed_floor_normal.slerp(target, t).normalized()

func align_with_floor(delta: float) -> void:
	if not is_on_floor():
		return

	var normal: Vector3 = smoothed_floor_normal
	var current_forward: Vector3 = -global_transform.basis.z
	
	# Calculate the new 'right' vector horizontally across the slope
	var right: Vector3 = current_forward.cross(normal).normalized()
	
	# Prevent math errors if pointing absolutely straight up/down
	if right.length_squared() < 0.001:
		right = global_transform.basis.x
		
	# Calculate the true orthogonal forward vector
	var forward: Vector3 = normal.cross(right).normalized()
	
	# Slerp smoothly to the new slope rotation
	var target_basis: Basis = Basis(right, normal, -forward)
	global_transform.basis = global_transform.basis.slerp(target_basis, clampf(slope_align_speed * delta, 0.0, 1.0))

func apply_slope_slippage(delta: float) -> void:
	if is_on_floor():
		var normal: Vector3 = smoothed_floor_normal
		# If normal.y is less than 0.99, the car is on an angled slope
		if normal.y < 0.99:
			# Calculate the physical downward force sliding along the surface
			var slide_vector: Vector3 = Vector3.DOWN.slide(normal)
			
			# Add this slide force directly to the car's physical velocity
			velocity += slide_vector * slope_slip_force * delta
