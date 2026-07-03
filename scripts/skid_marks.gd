extends Node3D

@export var car: CharacterBody3D
@export var slip_threshold: float = 0.05
@export var mark_width: float = 0.3
@export var max_marks: int = 500
@export var rear_axle_offset: float = -2.5
@export var wheel_spread: float = 0.9

var left_prev: Vector3 = Vector3.ZERO
var right_prev: Vector3 = Vector3.ZERO
var left_prev_right: Vector3 = Vector3.ZERO
var right_prev_right: Vector3 = Vector3.ZERO
var has_prev: bool = false
var mark_count: int = 0

var st: SurfaceTool
var mi: MeshInstance3D
var vert_count: int = 0

func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.05, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true

	mi = MeshInstance3D.new()
	mi.material_override = mat
	add_child(mi)

	_reset()

func _reset() -> void:
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	vert_count = 0
	mark_count = 0
	has_prev = false

func _physics_process(_delta: float) -> void:
	if not car:
		return

	var vel_flat := Vector3(car.velocity.x, 0, car.velocity.z)
	var total_speed: float = vel_flat.length()

	if total_speed < 2.0:
		has_prev = false
		return

	var forward_dir: Vector3 = -car.global_transform.basis.z
	forward_dir.y = 0
	forward_dir = forward_dir.normalized()
	var vel_dir: Vector3 = vel_flat.normalized()

	var slip: float = forward_dir.cross(vel_dir).length()
	var _is_sliding: bool = slip > slip_threshold

	var side_dir: Vector3 = car.global_transform.basis.x
	var rear_center: Vector3 = car.global_position + forward_dir * rear_axle_offset
	var left_pos: Vector3 = rear_center - side_dir * wheel_spread + Vector3.UP * 0.03
	var right_pos: Vector3 = rear_center + side_dir * wheel_spread + Vector3.UP * 0.03

	if car.is_drifting:
		var perp: Vector3 = vel_dir.cross(Vector3.UP).normalized()
		if perp.length() < 0.001:
			perp = side_dir
		var hw: Vector3 = perp * mark_width * 0.5

		if has_prev:
			var fade: float = clamp(slip / 0.3, 0.3, 1.0)
			var col := Color(0.05, 0.05, 0.05, fade)

			_add_quad(left_prev - left_prev_right, left_prev + left_prev_right, left_pos + hw, left_pos - hw, col)
			_add_quad(right_prev - right_prev_right, right_prev + right_prev_right, right_pos + hw, right_pos - hw, col)

			mark_count += 1
			vert_count += 12

			mi.mesh = st.commit()
			st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			if mi.mesh:
				st.append_from(mi.mesh, 0, Transform3D.IDENTITY)

			if mark_count > max_marks:
				_reset()
				mi.mesh = null

		left_prev = left_pos
		right_prev = right_pos
		left_prev_right = hw
		right_prev_right = hw
		has_prev = true
	else:
		has_prev = false

func _add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	st.set_color(col)
	st.set_normal(Vector3.UP)
	st.add_vertex(a)
	st.set_color(col)
	st.set_normal(Vector3.UP)
	st.add_vertex(b)
	st.set_color(col)
	st.set_normal(Vector3.UP)
	st.add_vertex(c)

	st.set_color(col)
	st.set_normal(Vector3.UP)
	st.add_vertex(a)
	st.set_color(col)
	st.set_normal(Vector3.UP)
	st.add_vertex(c)
	st.set_color(col)
	st.set_normal(Vector3.UP)
	st.add_vertex(d)
