extends Node3D

@export var seed_value: int = 0
@export var segment_count: int = 300
@export var road_width: float = 11.0
@export var segment_length: float = 4.0
@export var elevation_gain: float = 180.0
@export var guardrail_height: float = 1.2

@export_group("Curvature")
@export var max_turn_angle: float = 25.0
@export var hairpin_chance: float = 0.08
@export var hairpin_segments: int = 8
@export var subdivisions: int = 3
@export var heading_bounce_back: float = 0.12
@export var max_heading_deviation: float = 100.0
@export var hairpin_cooldown_segments: int = 14

@export_group("Self-Overlap Guard")
@export var min_self_distance: float = 14.0
@export var self_check_min_gap: int = 10
@export var max_generation_attempts: int = 25

var rng: RandomNumberGenerator
var road_points: Array[Vector3] = []
var road_rights: Array[Vector3] = []
var road_forwards: Array[Vector3] = []

func _ready() -> void:
	add_to_group("touge")
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else randi()
	generate()

func generate() -> void:
	_build_centerline()
	_subdivide_centerline()
	_compute_frames()
	_build_road_mesh()
	_build_terrain()

func _build_centerline() -> void:
	var best_points: Array[Vector3] = []
	var attempt := 0
	while attempt < max_generation_attempts:
		var candidate := _generate_centerline_candidate()
		if not _has_self_overlap(candidate):
			road_points = candidate
			return
		if candidate.size() > best_points.size():
			best_points = candidate
		attempt += 1

	# Fall back to the least-overlapping attempt if nothing came out clean.
	road_points = best_points

func _generate_centerline_candidate() -> Array[Vector3]:
	var points: Array[Vector3] = []

	var pos := Vector3.ZERO
	var angle := 0.0
	var elevation := 0.0
	var elev_per_seg := elevation_gain / float(segment_count)
	var max_dev := deg_to_rad(max_heading_deviation)

	# Keeps consecutive hairpins from stacking on top of each other and biases
	# each new hairpin to swing the opposite way from the last one, so the
	# road switches back instead of spiraling around in one direction.
	var segments_since_hairpin := hairpin_cooldown_segments
	var last_hairpin_dir := 0.0

	points.append(pos)

	var i := 0
	while i < segment_count:
		var can_hairpin := segments_since_hairpin >= hairpin_cooldown_segments and i + hairpin_segments < segment_count
		if can_hairpin and rng.randf() < hairpin_chance:
			var hairpin_dir := 1.0 if rng.randf() > 0.5 else -1.0
			if last_hairpin_dir != 0.0 and rng.randf() < 0.75:
				hairpin_dir = -last_hairpin_dir
			last_hairpin_dir = hairpin_dir

			var total_turn := deg_to_rad(rng.randf_range(140.0, 170.0)) * hairpin_dir
			var turn_per_seg := total_turn / float(hairpin_segments)
			for _j in hairpin_segments:
				angle += turn_per_seg
				var elev_step := elev_per_seg * rng.randf_range(0.6, 1.4)
				elevation += elev_step
				pos += Vector3(sin(angle) * segment_length, -elev_step, cos(angle) * segment_length)
				points.append(pos)
			i += hairpin_segments
			segments_since_hairpin = 0
		else:
			var turn := deg_to_rad(rng.randf_range(-max_turn_angle, max_turn_angle))
			# Mean-revert heading back toward "straight ahead" and cap total
			# deviation so ordinary curves can't random-walk into a full loop.
			angle = angle * (1.0 - heading_bounce_back) + turn
			angle = clampf(angle, -max_dev, max_dev)

			var elev_step := elev_per_seg * rng.randf_range(0.6, 1.4)
			elevation += elev_step
			pos += Vector3(sin(angle) * segment_length, -elev_step, cos(angle) * segment_length)
			points.append(pos)
			i += 1
			segments_since_hairpin += 1

	return points

func _has_self_overlap(points: Array[Vector3]) -> bool:
	var min_dist_sq := min_self_distance * min_self_distance
	for i in points.size():
		for j in range(i + self_check_min_gap, points.size()):
			var dx := points[i].x - points[j].x
			var dz := points[i].z - points[j].z
			if dx * dx + dz * dz < min_dist_sq:
				return true
	return false

func _subdivide_centerline() -> void:
	for _pass in subdivisions:
		var smoothed: Array[Vector3] = []
		smoothed.append(road_points[0])
		for i in range(1, road_points.size() - 1):
			var prev := road_points[i - 1]
			var curr := road_points[i]
			var next := road_points[i + 1]
			smoothed.append(prev * 0.25 + curr * 0.5 + next * 0.25)
		smoothed.append(road_points[road_points.size() - 1])
		road_points = smoothed

func _compute_frames() -> void:
	road_forwards.clear()
	road_rights.clear()

	for i in road_points.size():
		var fwd: Vector3
		if i < road_points.size() - 1:
			fwd = (road_points[i + 1] - road_points[i]).normalized()
		else:
			fwd = road_forwards[i - 1]

		var flat_fwd := Vector3(fwd.x, 0, fwd.z)
		var right: Vector3
		if flat_fwd.length() > 0.001:
			right = flat_fwd.normalized().cross(Vector3.UP).normalized()
			right = -right
		else:
			right = road_rights[i - 1] if i > 0 else Vector3.RIGHT

		road_forwards.append(fwd)
		road_rights.append(right)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	st.set_normal(normal)
	st.add_vertex(a)
	st.set_normal(normal)
	st.add_vertex(b)
	st.set_normal(normal)
	st.add_vertex(c)
	st.set_normal(normal)
	st.add_vertex(a)
	st.set_normal(normal)
	st.add_vertex(c)
	st.set_normal(normal)
	st.add_vertex(d)

func _build_road_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var hw := road_width * 0.5

	for i in road_points.size() - 1:
		var r0 := road_rights[i]
		var r1 := road_rights[i + 1]
		var p0 := road_points[i]
		var p1 := road_points[i + 1]

		var a := p0 - r0 * hw
		var b := p0 + r0 * hw
		var c := p1 + r1 * hw
		var d := p1 - r1 * hw

		_quad(st, a, b, c, d, Vector3.UP)

	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.17)
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	add_child(mi)

	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(mesh.get_faces())
	shape.backface_collision = true
	col.shape = shape
	body.add_child(col)
	add_child(body)

	_build_road_lines()

func _build_road_lines() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var lw := 0.12
	var edge_offset := road_width * 0.5 - 0.4
	var up_offset := Vector3.UP * 0.02

	for side: float in [-1.0, 1.0]:
		for i in road_points.size() - 1:
			var r0 := road_rights[i]
			var r1 := road_rights[i + 1]
			var c0: Vector3 = road_points[i] + r0 * edge_offset * side + up_offset
			var c1: Vector3 = road_points[i + 1] + r1 * edge_offset * side + up_offset

			var a := c0 - r0 * lw
			var b := c0 + r0 * lw
			var c := c1 + r1 * lw
			var d := c1 - r1 * lw
			_quad(st, a, b, c, d, Vector3.UP)

	for i in road_points.size() - 1:
		if i % 4 < 2:
			continue
		var r0 := road_rights[i]
		var r1 := road_rights[i + 1]
		var a := road_points[i] - r0 * lw + up_offset
		var b := road_points[i] + r0 * lw + up_offset
		var c := road_points[i + 1] + r1 * lw + up_offset
		var d := road_points[i + 1] - r1 * lw + up_offset
		_quad(st, a, b, c, d, Vector3.UP)

	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.95, 0.85)
	mat.roughness = 0.5
	mi.material_override = mat
	add_child(mi)

func _build_guardrails() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rail_offset := road_width * 0.5 + 0.3
	var thickness := 0.1
	var h := guardrail_height

	for side: float in [-1.0, 1.0]:
		for i in road_points.size() - 1:
			var r0 := road_rights[i]
			var r1 := road_rights[i + 1]

			var base0: Vector3 = road_points[i] + r0 * rail_offset * side
			var base1: Vector3 = road_points[i + 1] + r1 * rail_offset * side
			var top0 := base0 + Vector3.UP * h
			var top1 := base1 + Vector3.UP * h

			var outward: Vector3 = r0 * side
			_quad(st, base0, top0, top1, base1, outward)

			var inner_off: Vector3 = outward.normalized() * thickness
			var ib0 := base0 - inner_off
			var ib1 := base1 - inner_off
			var it0 := ib0 + Vector3.UP * h
			var it1 := ib1 + Vector3.UP * h
			_quad(st, it0, ib0, ib1, it1, -outward)

			_quad(st, top0, it0, it1, top1, Vector3.UP)

	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.75, 0.75)
	mat.metallic = 0.6
	mat.roughness = 0.4
	mi.material_override = mat
	add_child(mi)

	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(mesh.get_faces())
	shape.backface_collision = true
	col.shape = shape
	body.add_child(col)
	add_child(body)

func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var edge_offset := road_width * 0.5
	var shoulder_w := 3.0
	var terrain_w := 60.0

	# Flat shoulder flush with road, then sloped terrain beyond
	for side: float in [-1.0, 1.0]:
		for i in road_points.size() - 1:
			var r0 := road_rights[i]
			var r1 := road_rights[i + 1]

			var re0: Vector3 = road_points[i] + r0 * edge_offset * side
			var re1: Vector3 = road_points[i + 1] + r1 * edge_offset * side
			var sh0: Vector3 = re0 + r0 * shoulder_w * side
			var sh1: Vector3 = re1 + r1 * shoulder_w * side

			_quad(st, re0, sh0, sh1, re1, Vector3.UP)

			var drop := -12.0 if side < 0 else 8.0
			var o0: Vector3 = sh0 + r0 * terrain_w * side + Vector3.UP * drop
			var o1: Vector3 = sh1 + r1 * terrain_w * side + Vector3.UP * drop

			_quad(st, sh0, o0, o1, sh1, Vector3.UP)

	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.086, 0.259, 0.155, 1.0)
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	add_child(mi)

	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(mesh.get_faces())
	shape.backface_collision = true
	col.shape = shape
	body.add_child(col)
	add_child(body)

func get_spawn_position() -> Vector3:
	if road_points.size() > 0:
		return road_points[0] + Vector3.UP * 1.5
	return Vector3.UP * 1.5

func get_spawn_direction() -> Vector3:
	if road_forwards.size() > 0:
		return road_forwards[0]
	return Vector3.FORWARD
