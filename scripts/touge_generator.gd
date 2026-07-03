extends Node3D

@export var seed_value: int = 0
@export var segment_count: int = 300
@export var road_width: float = 11.0
@export var segment_length: float = 4.0
@export var elevation_gain: float = 250.0
@export var guardrail_height: float = 1.2

@export_group("Curvature")
@export var max_turn_angle: float = 14.0        # cap on how sharp a normal curve can get (deg/segment)
@export var turn_jitter: float = 3.5            # how much the steering can change each segment (deg)
@export var turn_damping: float = 0.07          # how strongly curves ease back toward straight
@export var hairpin_chance: float = 0.05
@export var hairpin_segments: int = 10
@export var subdivisions: int = 3
@export var heading_bounce_back: float = 0.05
@export var hairpin_cooldown_segments: int = 18

@export_group("Banking")
@export var enable_banking: bool = true
@export var bank_strength: float = 0.6           # curvature -> bank angle multiplier
@export var max_bank_angle: float = 22.0         # cap on how far a corner tilts (deg)
@export var bank_window: int = 2                 # points each side used to measure curvature

@export_group("Self-Overlap Guard")
@export var min_self_distance: float = 22.0
@export var self_check_min_gap: int = 10
@export var max_generation_attempts: int = 40

@export_group("Scenery")
@export var enable_signs: bool = true
@export var sharp_turn_threshold: float = 38.0   # heading change (deg) that warrants a warning sign
@export var sign_lookahead: int = 6              # how far ahead to sample the upcoming turn
@export var sign_spacing: int = 12               # min segments between signs
@export var sign_setback: int = 5                # place the sign this many points before the turn
@export var sign_margin: float = 0.8             # gap from road edge to the post
@export var sign_post_height: float = 2.4
@export var sign_size: float = 1.1               # warning-diamond half-height
@export var cliff_depth: float = 70.0            # how far the drop-side cliff falls
@export var cliff_edge_width: float = 1.5        # flat verge before the drop
@export var cliff_run: float = 4.0               # horizontal run of the cliff face (smaller = steeper)

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
	_build_signs()

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
	var turn_rate := 0.0
	var elevation := 0.0
	var elev_per_seg := elevation_gain / float(segment_count)
	var max_rate := deg_to_rad(max_turn_angle)
	var jitter := deg_to_rad(turn_jitter)

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

			var total_turn := deg_to_rad(rng.randf_range(140.0, 165.0)) * hairpin_dir
			var turn_per_seg := total_turn / float(hairpin_segments)
			for _j in hairpin_segments:
				angle += turn_per_seg
				var elev_step := elev_per_seg * rng.randf_range(0.85, 1.15)
				elevation += elev_step
				pos += Vector3(sin(angle) * segment_length, -elev_step, cos(angle) * segment_length)
				points.append(pos)
			# Exit the hairpin heading straight instead of inheriting old steering.
			turn_rate = 0.0
			i += hairpin_segments
			segments_since_hairpin = 0
		else:
			# Smoothly-varying steering: the turn RATE drifts a little each
			# segment and eases back toward straight, so curves flow in, hold,
			# and ease out - instead of the heading jumping to a fresh random
			# angle every step (which is what made the road snake constantly).
			turn_rate += rng.randf_range(-jitter, jitter)
			turn_rate *= (1.0 - turn_damping)
			turn_rate = clampf(turn_rate, -max_rate, max_rate)

			angle += turn_rate
			# Wrap, then ease heading the short way back toward the descent axis.
			# No hard clamp: a hard cap would snap the heading (and kink the road)
			# right after a hairpin, which legitimately leaves it pointing ~180
			# from downhill. The gentle pull lets switchbacks recover naturally.
			angle = wrapf(angle, -PI, PI)
			angle *= (1.0 - heading_bounce_back)

			var elev_step := elev_per_seg * rng.randf_range(0.85, 1.15)
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

	_apply_banking()

func _apply_banking() -> void:
	# Superelevation: tilt each cross-section into the curve so the inside edge
	# sits lower than the outside. Gravity then helps pull the car through the
	# corner instead of pushing it off - flowing, and much easier to hold.
	if not enable_banking:
		return

	var n := road_points.size()
	var max_bank := deg_to_rad(max_bank_angle)
	# Work off a copy so each point measures the un-tilted (flat) headings.
	var flat_rights := road_rights.duplicate()

	for i in n:
		var a := maxi(i - bank_window, 0)
		var b := mini(i + bank_window, n - 1)
		var fa := Vector3(road_forwards[a].x, 0.0, road_forwards[a].z)
		var fb := Vector3(road_forwards[b].x, 0.0, road_forwards[b].z)
		if fa.length() < 0.001 or fb.length() < 0.001:
			continue

		# Signed curvature: positive means the road is turning toward +right.
		var turn: float = (fb.normalized() - fa.normalized()).dot(flat_rights[i])
		var bank := clampf(turn * bank_strength, -max_bank, max_bank)

		# Roll the right vector in the right/up plane; +turn drops the inside (+right) edge.
		var r: Vector3 = flat_rights[i]
		road_rights[i] = (r * cos(bank) - Vector3.UP * sin(bank)).normalized()

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

	# Uphill embankment (+right): gentle, drivable rise. Cliff (-right): a narrow
	# verge, then a near-vertical face dropping far to a valley floor - steeper
	# than the car's floor_max_angle, so leaving the road here means falling.
	# Kept narrow on purpose: a wide apron would reach sideways into adjacent
	# switchback passes and poke green terrain up through the road there.
	var shoulder_w := 2.5
	var embank_w := 8.0
	var embank_rise := 5.0
	var valley_w := 25.0

	for i in road_points.size() - 1:
		var r0 := road_rights[i]
		var r1 := road_rights[i + 1]
		var p0 := road_points[i]
		var p1 := road_points[i + 1]

		# --- Uphill embankment side (+right) ---
		var ure0 := p0 + r0 * edge_offset
		var ure1 := p1 + r1 * edge_offset
		var ush0 := ure0 + r0 * shoulder_w
		var ush1 := ure1 + r1 * shoulder_w
		_quad(st, ure0, ush0, ush1, ure1, Vector3.UP)
		var uo0 := ush0 + r0 * embank_w + Vector3.UP * embank_rise
		var uo1 := ush1 + r1 * embank_w + Vector3.UP * embank_rise
		_quad(st, ush0, uo0, uo1, ush1, Vector3.UP)

		# --- Cliff side (-right) ---
		var cre0 := p0 - r0 * edge_offset
		var cre1 := p1 - r1 * edge_offset
		var cv0 := cre0 - r0 * cliff_edge_width
		var cv1 := cre1 - r1 * cliff_edge_width
		_quad(st, cre0, cre1, cv1, cv0, Vector3.UP)               # flat verge

		var cb0 := cv0 - r0 * cliff_run + Vector3.DOWN * cliff_depth
		var cb1 := cv1 - r1 * cliff_run + Vector3.DOWN * cliff_depth
		_quad(st, cv0, cv1, cb1, cb0, (-r0).normalized())         # steep face

		var vf0 := cb0 - r0 * valley_w
		var vf1 := cb1 - r1 * valley_w
		_quad(st, cb0, cb1, vf1, vf0, Vector3.UP)                 # valley floor

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

func _build_signs() -> void:
	if not enable_signs or road_forwards.size() < sign_lookahead + 2:
		return

	var post_st := SurfaceTool.new()
	post_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var panel_st := SurfaceTool.new()
	panel_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var thresh := deg_to_rad(sharp_turn_threshold)
	var last_sign := -sign_spacing
	var placed := 0

	for i in range(1, road_points.size() - sign_lookahead - 1):
		if i - last_sign < sign_spacing:
			continue

		# Heading change over the lookahead window flags a sharp corner
		var f_here := road_forwards[i]
		var f_ahead := road_forwards[i + sign_lookahead]
		var turn := Vector2(f_here.x, f_here.z).angle_to(Vector2(f_ahead.x, f_ahead.z))
		if absf(turn) < thresh:
			continue

		# Place the sign a bit before the turn, on the uphill (safe) side
		var idx := maxi(i - sign_setback, 1)
		_add_sign(post_st, panel_st, idx)
		last_sign = i
		placed += 1

	if placed == 0:
		return

	var post_mesh := post_st.commit()
	var post_mi := MeshInstance3D.new()
	post_mi.mesh = post_mesh
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.38, 0.38, 0.42)
	post_mat.roughness = 0.7
	post_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	post_mi.material_override = post_mat
	add_child(post_mi)

	var panel_mesh := panel_st.commit()
	var panel_mi := MeshInstance3D.new()
	panel_mi.mesh = panel_mesh
	var panel_mat := StandardMaterial3D.new()
	panel_mat.albedo_color = Color(0.96, 0.78, 0.09)
	panel_mat.roughness = 0.4
	panel_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	panel_mi.material_override = panel_mat
	add_child(panel_mi)

func _add_sign(post_st: SurfaceTool, panel_st: SurfaceTool, idx: int) -> void:
	var r := road_rights[idx]
	var fwd := road_forwards[idx]
	var base: Vector3 = road_points[idx] + r * (road_width * 0.5 + sign_margin)

	# Vertical post
	_box_column(post_st, base, r, fwd, 0.09, sign_post_height)

	# Warning diamond on top, facing back down the road toward oncoming drivers
	var center := base + Vector3.UP * sign_post_height
	var s := sign_size
	var top := center + Vector3.UP * s
	var bot := center - Vector3.UP * s
	var lft := center - r * s
	var rgt := center + r * s
	var normal := (-Vector3(fwd.x, 0.0, fwd.z)).normalized()
	_quad(panel_st, top, rgt, bot, lft, normal)

func _box_column(st: SurfaceTool, base: Vector3, right: Vector3, fwd: Vector3, half: float, height: float) -> void:
	var rt := Vector3(right.x, 0.0, right.z).normalized()
	var f := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var corners := [
		base - rt * half - f * half,
		base + rt * half - f * half,
		base + rt * half + f * half,
		base - rt * half + f * half,
	]
	var up := Vector3.UP * height
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		_quad(st, a, b, b + up, a + up, (a - base).normalized())

func get_spawn_position() -> Vector3:
	if road_points.size() > 0:
		return road_points[0] + Vector3.UP * 1.5
	return Vector3.UP * 1.5

func get_spawn_direction() -> Vector3:
	if road_forwards.size() > 0:
		return road_forwards[0]
	return Vector3.FORWARD
