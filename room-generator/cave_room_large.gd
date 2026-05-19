extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	generate_cave_room(rng)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func generate_cave_room(
		rng: RandomNumberGenerator,
		initial_position: Vector2 = Vector2.ZERO,
		height: int = 40,
		initial_floor_radius: int = 35,
		rough_spacing: int = 1,
	) -> void:
	var no_floor = 0
	var cave_rand = initial_layout(initial_position, initial_floor_radius, rough_spacing)
	var min_rand_size: int = maxi(15, int(round(float(cave_rand.size()) / 10.0)))
	var max_rand_size: int = int(round(float(cave_rand.size()) * 1.2))
	var levels: Array[PackedVector2Array]
	levels.append(cave_rand)
	var floor_regions_by_level: Array[Dictionary] = []

	for i in range(height):
		if cave_rand.size() < min_rand_size:
			break
		cave_rand = resize_rand(cave_rand, 1, false, 0.8)
		print(cave_rand.size())

		_debug_draw_closed_curve_line(cave_rand, 1 * i + 1, Color.YELLOW)

		cave_rand = resample_closed_curve_by_spacing(cave_rand, rough_spacing, 0.8)

		var floor_regions: Array[Dictionary] = []

		if cave_rand.size() < max_rand_size:
			var allocation := allocate_floor_space(cave_rand, rng, rough_spacing, 3, 6, 17, 38, 7)

			cave_rand = allocation["cave_rand"]
			floor_regions = allocation["floor_regions"]

			#_debug_draw_closed_curve_line(cave_rand, 1 * i + 1, Color.YELLOW)

			var cleanup := remove_bad_close_intervals(cave_rand, rough_spacing * 0.8, floor_regions)

			cave_rand = cleanup["cave_rand"]
			floor_regions = cleanup["floor_regions"]
		else:
			no_floor+=1

		floor_regions_by_level.append({
			"height": float(i + 1),
			"cave_rand": cave_rand,
			"floor_regions": floor_regions
		})

		_debug_draw_closed_curve_line(cave_rand, 1 * i + 1, Color.RED)

		levels.append(cave_rand)
	print("made ", no_floor, "rands with no extra floor")
	
	var candidate_levels: Array[int] = []

	for level_i in range(floor_regions_by_level.size()):
		var level_info: Dictionary = floor_regions_by_level[level_i]
		var floor_regions: Array = level_info["floor_regions"]

		if floor_regions.size() >= 2:
			candidate_levels.append(level_i)

	if not candidate_levels.is_empty():
		var chosen_level_i := candidate_levels[rng.randi_range(0, candidate_levels.size() - 1)]
		var chosen_level: Dictionary = floor_regions_by_level[chosen_level_i]

		var bridge_result := make_bridges_on_level(
			chosen_level,
			rng,
			rough_spacing,
			3, # bridge_count
			rough_spacing * 5.0 # bridge_padding
		)

		floor_regions_by_level[chosen_level_i] = bridge_result["level_info"]

		print("made bridges: ", bridge_result["bridge_links"].size())
	

	_debug_spawn_floor_region_inner_balls_by_level(floor_regions_by_level)




func _debug_spawn_floor_region_inner_balls_by_level(
	floor_regions_by_level: Array[Dictionary],
	radius: float = 0.35
) -> void:
	for level_info in floor_regions_by_level:
		var debug_height: float = level_info["height"]
		var floor_regions: Array = level_info["floor_regions"]

		for floor_region in floor_regions:
			var inner_points: PackedVector2Array = floor_region["inner_points"]

			_debug_spawn_vertex_balls(
				inner_points,
				null,
				debug_height,
				radius
			)




func _debug_draw_closed_curve_line(
	points: PackedVector2Array,
	height: float = 0.0,
	color: Color = Color.YELLOW,
) -> void:
	if points.size() < 2:
		return

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "DebugClosedCurveLine"
	add_child(mesh_instance)

	var immediate_mesh := ImmediateMesh.new()
	mesh_instance.mesh = immediate_mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = mat

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	for i in range(points.size()):
		var a := points[i]
		var b := points[(i + 1) % points.size()]

		immediate_mesh.surface_add_vertex(Vector3(a.x, height, a.y))
		immediate_mesh.surface_add_vertex(Vector3(b.x, height, b.y))

	immediate_mesh.surface_end()



func initial_layout(
	center: Vector2,
	base_radius: float,
	rough_spacing: float = 8.0,
	rough_points: int = 48,
	irregularity: float = 0.35,
	smooth_steps: int = 3
) -> PackedVector2Array:
	var radii: Array[float] = []
	radii.resize(rough_points)

	# Generate random radii
	for i in range(rough_points):
		radii[i] = base_radius * randf_range(1.0 - irregularity, 1.0 + irregularity)

	# Smooth radii cyclically
	for s in range(smooth_steps):
		var new_radii: Array[float] = []
		new_radii.resize(rough_points)

		for i in range(rough_points):
			var prev := radii[(i - 1 + rough_points) % rough_points]
			var curr := radii[i]
			var next := radii[(i + 1) % rough_points]
			new_radii[i] = (prev + curr + next) / 3.0

		radii = new_radii

	# Create initial polygon
	var rough := PackedVector2Array()
	rough.resize(rough_points)

	for i in range(rough_points):
		var angle := TAU * float(i) / float(rough_points)
		rough[i] = center + Vector2(cos(angle), sin(angle)) * radii[i]

	return resample_closed_polygon_by_spacing(rough, rough_spacing, center)



func resample_closed_polygon_by_spacing(
	points: PackedVector2Array,
	rough_spacing: float,
	center: Vector2,
	noise_strength: float = 0.5,
	noise_frequency: float = 0.15
) -> PackedVector2Array:
	var total_length := 0.0
	var lengths: Array[float] = []
	var n := points.size()

	for i in range(n):
		var a := points[i]
		var b := points[(i + 1) % n]
		var segment_length := a.distance_to(b)
		lengths.append(segment_length)
		total_length += segment_length

	var target_count := maxi(8, int(round(total_length / rough_spacing)))
	var actual_spacing := total_length / float(target_count)

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = noise_frequency
	noise.seed = randi()

	var result := PackedVector2Array()

	for k in range(target_count):
		var target_distance := actual_spacing * float(k)

		var accumulated := 0.0
		var current_edge := 0

		while current_edge < n and accumulated + lengths[current_edge] < target_distance:
			accumulated += lengths[current_edge]
			current_edge += 1

		var edge_start := points[current_edge % n]
		var edge_end := points[(current_edge + 1) % n]
		var edge_length := lengths[current_edge % n]

		var t := 0.0
		if edge_length > 0.0:
			t = (target_distance - accumulated) / edge_length

		var p := edge_start.lerp(edge_end, t)

		# Push the point slightly inward/outward from the blob center
		var dir := (p - center).normalized()
		var noise_value := noise.get_noise_1d(float(k))
		p += dir * noise_value * noise_strength

		result.append(p)

	return result
	
	
func _debug_spawn_vertex_balls(
	vertices: PackedVector2Array,
	selected_vertex_indices = null,
	height: float = 0.0,
	radius: float = 0.25
) -> void:
	var parent := Node3D.new()
	parent.name = "DebugSelectedFloorVertices"
	add_child(parent)

	var count := vertices.size()
	if selected_vertex_indices != null:
		count = selected_vertex_indices.size()

	if count == 0:
		return

	for order_i in range(count):
		var vertex_index := order_i

		if selected_vertex_indices != null:
			vertex_index = selected_vertex_indices[order_i]

		if vertex_index < 0 or vertex_index >= vertices.size():
			continue

		var p2: Vector2 = vertices[vertex_index]
		var p3 := Vector3(p2.x, height, p2.y)

		var ball := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = radius
		sphere.height = radius * 2.0
		ball.mesh = sphere

		ball.position = p3 + Vector3.UP * 0.2

		var mat := StandardMaterial3D.new()

		var t := 0.0
		if count > 1:
			t = float(order_i) / float(count - 1)

		# Color changes along the selected span.
		# Start = red-ish, middle = green-ish, end = blue-ish.
		mat.albedo_color = Color(
			1.0 - t,
			1.0 - abs(t - 0.5) * 2.0,
			t,
			1.0
		)

		ball.material_override = mat
		parent.add_child(ball)



func resize_rand(
	points: PackedVector2Array,
	offset_distance: float,
	expand: bool = true,
	radial_weight: float = 0.65
) -> PackedVector2Array:
	var n := points.size()
	if n < 3:
		return points

	var center := get_polygon_center(points)

	var result := PackedVector2Array()
	result.resize(n)

	var direction := 1.0
	if not expand:
		direction = -1.0

	for i in range(n):
		var prev_point := points[(i - 1 + n) % n]
		var curr_point := points[i]
		var next_point := points[(i + 1) % n]

		var tangent := next_point - prev_point

		if tangent.length_squared() < 0.000001:
			result[i] = curr_point
			continue

		tangent = tangent.normalized()

		var normal := Vector2(tangent.y, -tangent.x)

		var radial := curr_point - center
		if radial.length_squared() > 0.000001:
			radial = radial.normalized()
		else:
			radial = normal

		# Make sure normal points roughly outward from the center.
		if normal.dot(radial) < 0.0:
			normal = -normal

		var move_dir := normal.lerp(radial, radial_weight).normalized()

		result[i] = curr_point + move_dir * offset_distance * direction

	return result



func get_polygon_center(points: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO

	if points.is_empty():
		return center

	for p in points:
		center += p

	return center / float(points.size())



func resample_closed_curve_by_spacing(
	points: PackedVector2Array,
	target_spacing: float,
	min_allowed_spacing_ratio: float = 0.5
) -> PackedVector2Array:
	var n := points.size()
	if n < 2:
		return points

	target_spacing = maxf(target_spacing, 0.001)

	var lengths: Array[float] = []
	lengths.resize(n)

	var total_length := 0.0

	for i in range(n):
		var a := points[i]
		var b := points[(i + 1) % n]
		var segment_length := a.distance_to(b)

		lengths[i] = segment_length
		total_length += segment_length

	if total_length <= 0.0:
		return points

	var point_count := maxi(3, int(round(total_length / target_spacing)))
	var actual_spacing := total_length / float(point_count)

	var result := PackedVector2Array()
	result.resize(point_count)

	var current_edge := 0
	var accumulated := 0.0

	for k in range(point_count):
		var target_distance := actual_spacing * float(k)

		while current_edge < n - 1 and accumulated + lengths[current_edge] < target_distance:
			accumulated += lengths[current_edge]
			current_edge += 1

		var edge_start := points[current_edge]
		var edge_end := points[(current_edge + 1) % n]
		var edge_length := lengths[current_edge]

		var t := 0.0
		if edge_length > 0.0:
			t = (target_distance - accumulated) / edge_length

		result[k] = edge_start.lerp(edge_end, t)

	var min_allowed_distance := target_spacing * min_allowed_spacing_ratio
	result = merge_vertices_that_are_too_close(result, min_allowed_distance)
	return result



func merge_vertices_that_are_too_close(
	points: PackedVector2Array,
	min_distance: float,
	min_vertex_count: int = 3
) -> PackedVector2Array:
	if points.size() < 2:
		return points

	min_distance = maxf(min_distance, 0.0)
	min_vertex_count = maxi(min_vertex_count, 3)

	var current := points
	var changed := true

	while changed:
		changed = false

		var n := current.size()
		if n <= min_vertex_count:
			break

		var result := PackedVector2Array()
		var i := 0

		while i < n:
			if result.size() + (n - i) <= min_vertex_count:
				result.append(current[i])
				i += 1
				continue

			var current_point := current[i]
			var next_index := (i + 1) % n

			# Do not handle wraparound inside the main loop.
			if i == n - 1:
				result.append(current_point)
				i += 1
				continue

			var next_point := current[next_index]
			var distance := current_point.distance_to(next_point)

			if distance < min_distance:
				var merged := (current_point + next_point) * 0.5
				result.append(merged)
				changed = true
				i += 2
			else:
				result.append(current_point)
				i += 1

		# Handle wraparound: last and first are also neighbors.
		if result.size() > min_vertex_count:
			var first_index := 0
			var last_index := result.size() - 1

			var first := result[first_index]
			var last := result[last_index]

			if first.distance_to(last) < min_distance:
				var merged_wrap := (first + last) * 0.5
				result[first_index] = merged_wrap
				result.remove_at(last_index)
				changed = true

		current = result

	return current



func allocate_floor_space(
	cave_rand: PackedVector2Array,
	rng: RandomNumberGenerator,
	rough_spacing: float,
	min_region_count: int,
	max_region_count: int,
	min_region_size: int,
	max_region_size: int,
	min_gap: int
) -> Dictionary:
	var result := {
		"cave_rand": cave_rand,
		"floor_regions": []
	}

	var n := cave_rand.size()
	if n < 3:
		return result

	min_region_count = maxi(0, min_region_count)
	max_region_count = maxi(min_region_count, max_region_count)

	min_region_size = maxi(2, min_region_size)
	max_region_size = maxi(min_region_size, max_region_size)

	min_gap = maxi(0, min_gap)

	var desired_region_count := rng.randi_range(min_region_count, max_region_count)

	var blocked_indices := PackedByteArray()
	blocked_indices.resize(n)

	var region_infos: Array[Dictionary] = []

	while region_infos.size() < desired_region_count:
		var available_intervals := _build_available_index_intervals(
			blocked_indices,
			n,
			min_region_size
		)

		if available_intervals.is_empty():
			break

		var region_request := _pick_random_region_from_intervals(
			available_intervals,
			rng,
			min_region_size,
			max_region_size
		)

		if region_request.is_empty():
			break

		var raw_start_index: int = region_request["start_index"]
		var region_size: int = region_request["region_size"]

		var start_index := raw_start_index % n
		if start_index < 0:
			start_index += n

		var end_index := (start_index + region_size - 1) % n

		var inner_indices := PackedInt32Array()
		inner_indices.resize(region_size)

		var inner_vertices := PackedVector2Array()
		inner_vertices.resize(region_size)

		for i in range(region_size):
			var index := (start_index + i) % n
			inner_indices[i] = index
			inner_vertices[i] = cave_rand[index]

		var outer_vertices := expand_outer_rand(
			cave_rand,
			start_index,
			end_index,
			rng,
			rough_spacing
		)

		var region_info := {
			"start_index": start_index,
			"end_index": end_index,
			"region_size": region_size,
			"wraps": end_index < start_index,
			"inner_indices": inner_indices,
			"inner_vertices": inner_vertices,
			"outer_vertices": outer_vertices
		}

		region_infos.append(region_info)

		_mark_blocked_index_span_by_size(
			start_index,
			region_size,
			min_gap,
			blocked_indices
		)

	var replacement_result := _replace_inner_regions_with_outer_regions(
		cave_rand,
		region_infos
	)

	result["cave_rand"] = replacement_result["cave_rand"]
	result["floor_regions"] = replacement_result["floor_regions"]

	return result



func _mark_blocked_index_span_by_size(
	start_index: int,
	region_size: int,
	min_gap: int,
	blocked_indices: PackedByteArray
) -> void:
	var n := blocked_indices.size()
	if n <= 0:
		return

	var from_offset := -min_gap
	var to_offset := region_size - 1 + min_gap

	for offset in range(from_offset, to_offset + 1):
		var index := (start_index + offset) % n
		if index < 0:
			index += n

		blocked_indices[index] = 1







func _build_available_index_intervals(
	blocked_indices: PackedByteArray,
	vertex_count: int,
	min_region_size: int
) -> Array[Dictionary]:
	var intervals: Array[Dictionary] = []

	if vertex_count <= 0:
		return intervals

	# If everything is available, return one full wrapping interval.
	var any_blocked := false
	for i in range(vertex_count):
		if blocked_indices[i] != 0:
			any_blocked = true
			break

	if not any_blocked:
		if vertex_count >= min_region_size:
			intervals.append({
				"start_index": 0,
				"size": vertex_count
			})
		return intervals

	# Find the first blocked index. Start scanning after it.
	# This allows a free run to wrap across n - 1 -> 0.
	var first_blocked := -1
	for i in range(vertex_count):
		if blocked_indices[i] != 0:
			first_blocked = i
			break

	var scan_start := (first_blocked + 1) % vertex_count
	var offset := 0

	while offset < vertex_count:
		var index := (scan_start + offset) % vertex_count

		if blocked_indices[index] != 0:
			offset += 1
			continue

		var run_start := index
		var run_size := 0

		while offset < vertex_count:
			index = (scan_start + offset) % vertex_count

			if blocked_indices[index] != 0:
				break

			run_size += 1
			offset += 1

		if run_size >= min_region_size:
			intervals.append({
				"start_index": run_start,
				"size": run_size
			})

	return intervals



func _pick_random_region_from_intervals(
	available_intervals: Array[Dictionary],
	rng: RandomNumberGenerator,
	min_region_size: int,
	max_region_size: int
) -> Dictionary:
	var total_possible_starts := 0

	for interval in available_intervals:
		var interval_size: int = interval["size"]
		var possible_starts := interval_size - min_region_size + 1

		if possible_starts > 0:
			total_possible_starts += possible_starts

	if total_possible_starts <= 0:
		return {}

	var chosen_start_slot := rng.randi_range(0, total_possible_starts - 1)

	for interval in available_intervals:
		var interval_start: int = interval["start_index"]
		var interval_size: int = interval["size"]

		var possible_starts := interval_size - min_region_size + 1
		if possible_starts <= 0:
			continue

		if chosen_start_slot >= possible_starts:
			chosen_start_slot -= possible_starts
			continue

		var local_start := chosen_start_slot
		var start_index := interval_start + local_start

		var max_size_here := mini(
			max_region_size,
			interval_size - local_start
		)

		var region_size := rng.randi_range(
			min_region_size,
			max_size_here
		)

		return {
			"start_index": start_index,
			"region_size": region_size
		}

	return {}



func _replace_inner_regions_with_outer_regions(
	cave_rand: PackedVector2Array,
	region_infos: Array[Dictionary]
) -> Dictionary:
	var result_dict := {
		"cave_rand": cave_rand,
		"floor_regions": []
	}

	var n := cave_rand.size()
	if n <= 0:
		return result_dict

	if region_infos.is_empty():
		return result_dict

	var start_output_index := 0

	for region_info in region_infos:
		var wraps: bool = region_info.get("wraps", false)

		if wraps:
			var end_index: int = region_info["end_index"]
			start_output_index = (end_index + 1) % n
			break

	var region_index_by_start := {}

	for region_i in range(region_infos.size()):
		var region_info: Dictionary = region_infos[region_i]
		var start_index: int = region_info["start_index"]
		region_index_by_start[start_index] = region_i

	var result := PackedVector2Array()
	var floor_regions: Array[Dictionary] = []

	var offset := 0
	while offset < n:
		var i := (start_output_index + offset) % n

		if region_index_by_start.has(i):
			var region_i: int = region_index_by_start[i]
			var region_info: Dictionary = region_infos[region_i]

			var outer_vertices: PackedVector2Array = region_info["outer_vertices"]
			var inner_vertices: PackedVector2Array = region_info["inner_vertices"]

			var outer_start_index := result.size()

			for local_i in range(outer_vertices.size()):
				result.append(outer_vertices[local_i])

			var outer_end_index := result.size() - 1

			floor_regions.append({
				"outer_start_index": outer_start_index,
				"outer_end_index": outer_end_index,
				"inner_points": inner_vertices
			})

			var region_size: int = region_info["region_size"]
			offset += region_size
		else:
			result.append(cave_rand[i])
			offset += 1

	result_dict["cave_rand"] = result
	result_dict["floor_regions"] = floor_regions

	return result_dict



func expand_outer_rand(
	cave_rand: PackedVector2Array,
	start_index: int,
	end_index: int,
	rng: RandomNumberGenerator,
	rough_spacing: float,
	rough_radius_variation: float = 0.35,
	rough_smooth_steps: int = 2
) -> PackedVector2Array:
	var n := cave_rand.size()
	if n < 3:
		return PackedVector2Array()

	start_index = clampi(start_index, 0, n - 1)
	end_index = clampi(end_index, 0, n - 1)

	var start_point := cave_rand[start_index]
	var end_point := cave_rand[end_index]

	var chord := end_point - start_point
	var chord_length := chord.length()

	if chord_length <= 0.0001:
		var fallback := PackedVector2Array()
		fallback.append(start_point)
		fallback.append(end_point)
		return fallback

	var chord_dir := chord / chord_length
	var center := _get_polygon_average_center(cave_rand)

	var mid_point := (start_point + end_point) * 0.5

	var outward := Vector2(-chord_dir.y, chord_dir.x)

	# Make sure the semicircle goes away from the cave center.
	if outward.dot(mid_point - center) < 0.0:
		outward = -outward

	var radius := chord_length * 0.5
	var approximate_arc_length := PI * radius

	var rough_point_count := maxi(
		5,
		int(round(approximate_arc_length / maxf(rough_spacing, 0.001))) + 2
	)

	var height_scales: Array[float] = []
	height_scales.resize(rough_point_count)

	for i in range(rough_point_count):
		if i == 0 or i == rough_point_count - 1:
			height_scales[i] = 1.0
		else:
			height_scales[i] = rng.randf_range(
				1.0 - rough_radius_variation,
				1.0 + rough_radius_variation
			)

	for s in range(rough_smooth_steps):
		var new_scales: Array[float] = []
		new_scales.resize(rough_point_count)

		for i in range(rough_point_count):
			if i == 0 or i == rough_point_count - 1:
				new_scales[i] = 1.0
				continue

			new_scales[i] = (
				height_scales[i - 1]
				+ height_scales[i]
				+ height_scales[i + 1]
			) / 3.0

		height_scales = new_scales

	var rough_points := PackedVector2Array()
	rough_points.resize(rough_point_count)

	for i in range(rough_point_count):
		var t := float(i) / float(rough_point_count - 1)

		var x := lerpf(-radius, radius, t)
		var semicircle_height := sqrt(maxf(radius * radius - x * x, 0.0))

		var p := mid_point
		p += chord_dir * x
		p += outward * semicircle_height * height_scales[i]

		rough_points[i] = p

	# Force exact endpoints.
	rough_points[0] = start_point
	rough_points[rough_point_count - 1] = end_point

	var bezier_sampled := _sample_open_bezier_chain(rough_points, 8)
	var resampled := resample_open_curve_by_spacing(bezier_sampled, rough_spacing)

	# Force exact endpoints again after resampling.
	if resampled.size() >= 2:
		resampled[0] = start_point
		resampled[resampled.size() - 1] = end_point

	return resampled



func _sample_open_bezier_chain(
	points: PackedVector2Array,
	steps_per_segment: int = 8
) -> PackedVector2Array:
	var n := points.size()
	if n < 2:
		return points

	steps_per_segment = maxi(1, steps_per_segment)

	var result := PackedVector2Array()

	for i in range(n - 1):
		var p0 := points[maxi(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[i + 1]
		var p3 := points[mini(i + 2, n - 1)]

		var c1 := p1 + (p2 - p0) / 6.0
		var c2 := p2 - (p3 - p1) / 6.0

		for step in range(steps_per_segment):
			var t := float(step) / float(steps_per_segment)
			result.append(_cubic_bezier(p1, c1, c2, p2, t))

	result.append(points[n - 1])

	return result



func _cubic_bezier(
	p0: Vector2,
	p1: Vector2,
	p2: Vector2,
	p3: Vector2,
	t: float
) -> Vector2:
	var u := 1.0 - t

	return (
		p0 * u * u * u
		+ p1 * 3.0 * u * u * t
		+ p2 * 3.0 * u * t * t
		+ p3 * t * t * t
	)



func resample_open_curve_by_spacing(
	points: PackedVector2Array,
	target_spacing: float
) -> PackedVector2Array:
	var n := points.size()
	if n < 2:
		return points

	target_spacing = maxf(target_spacing, 0.001)

	var lengths: Array[float] = []
	lengths.resize(n - 1)

	var total_length := 0.0

	for i in range(n - 1):
		var segment_length := points[i].distance_to(points[i + 1])
		lengths[i] = segment_length
		total_length += segment_length

	if total_length <= 0.0:
		return points

	var point_count := maxi(2, int(round(total_length / target_spacing)) + 1)
	var actual_spacing := total_length / float(point_count - 1)

	var result := PackedVector2Array()
	result.resize(point_count)

	var current_edge := 0
	var accumulated := 0.0

	for k in range(point_count):
		if k == point_count - 1:
			result[k] = points[n - 1]
			continue

		var target_distance := actual_spacing * float(k)

		while current_edge < n - 2 and accumulated + lengths[current_edge] < target_distance:
			accumulated += lengths[current_edge]
			current_edge += 1

		var edge_start := points[current_edge]
		var edge_end := points[current_edge + 1]
		var edge_length := lengths[current_edge]

		var t := 0.0
		if edge_length > 0.0:
			t = (target_distance - accumulated) / edge_length

		result[k] = edge_start.lerp(edge_end, t)

	return result



func _get_polygon_average_center(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO

	var center := Vector2.ZERO

	for p in points:
		center += p

	return center / float(points.size())



func remove_bad_close_intervals(
	points: PackedVector2Array,
	min_distance: float,
	floor_regions: Array[Dictionary] = [],
	min_interval_size: int = 2
) -> Dictionary:
	var current := points
	var current_floor_regions := floor_regions.duplicate(true)

	if current.size() < 4:
		return {
			"cave_rand": current,
			"floor_regions": current_floor_regions
		}

	min_distance = maxf(min_distance, 0.0)
	var min_distance_squared := min_distance * min_distance

	min_interval_size = maxi(1, min_interval_size)

	var changed := true

	while changed:
		changed = false

		var n := current.size()
		if n < 4:
			break

		var best_a := -1
		var best_b := -1
		var best_distance_squared := INF

		for a in range(n):
			for b in range(a + 1, n):
				var forward_size := b - a + 1
				var backward_size := n - (b - a) + 1

				# Ignore direct neighbors. Those should be handled elsewhere.
				if forward_size <= 2 or backward_size <= 2:
					continue

				var interval_size := mini(forward_size, backward_size)
				if interval_size < min_interval_size:
					continue

				var distance_squared := current[a].distance_squared_to(current[b])

				if distance_squared >= min_distance_squared:
					continue

				if distance_squared < best_distance_squared:
					best_distance_squared = distance_squared
					best_a = a
					best_b = b

		if best_a == -1:
			break

		var removal_info := _remove_shorter_interval_between_indices_with_floor_info(
			current,
			best_a,
			best_b,
			current_floor_regions
		)

		current = removal_info["points"]
		current_floor_regions = removal_info["floor_regions"]

		changed = true

	return {
		"cave_rand": current,
		"floor_regions": current_floor_regions
	}



func _remove_shorter_interval_between_indices_with_floor_info(
	points: PackedVector2Array,
	a: int,
	b: int,
	floor_regions: Array[Dictionary]
) -> Dictionary:
	var n := points.size()

	if n < 4:
		return {
			"points": points,
			"floor_regions": floor_regions
		}

	if a > b:
		var temp := a
		a = b
		b = temp

	var forward_count := b - a + 1
	var backward_count := n - (b - a) + 1

	var remove_forward := forward_count <= backward_count
	var merged_point := (points[a] + points[b]) * 0.5

	var result := PackedVector2Array()
	var old_to_new := PackedInt32Array()
	old_to_new.resize(n)

	var removed_indices := PackedInt32Array()
	var removed_points := PackedVector2Array()

	if remove_forward:
		for i in range(0, a):
			old_to_new[i] = result.size()
			result.append(points[i])

		var merged_index := result.size()
		result.append(merged_point)

		for i in range(a, b + 1):
			old_to_new[i] = merged_index
			removed_indices.append(i)
			removed_points.append(points[i])

		for i in range(b + 1, n):
			old_to_new[i] = result.size()
			result.append(points[i])
	else:
		var merged_index := 0
		result.append(merged_point)

		for i in range(b, n):
			old_to_new[i] = merged_index
			removed_indices.append(i)
			removed_points.append(points[i])

		for i in range(0, a + 1):
			old_to_new[i] = merged_index
			removed_indices.append(i)
			removed_points.append(points[i])

		for i in range(a + 1, b):
			old_to_new[i] = result.size()
			result.append(points[i])

	var updated_floor_regions := _update_floor_regions_after_bad_interval_removal(
		floor_regions,
		old_to_new,
		removed_indices,
		removed_points
	)

	return {
		"points": result,
		"floor_regions": updated_floor_regions
	}



func _update_floor_regions_after_bad_interval_removal(
	floor_regions: Array[Dictionary],
	old_to_new: PackedInt32Array,
	removed_indices: PackedInt32Array,
	removed_points: PackedVector2Array
) -> Array[Dictionary]:
	var updated_regions: Array[Dictionary] = floor_regions.duplicate(true)

	if removed_indices.is_empty():
		for region_i in range(updated_regions.size()):
			updated_regions[region_i] = _remap_floor_region_indices(
				updated_regions[region_i],
				old_to_new
			)

		return updated_regions

	var hits: Array[Dictionary] = []

	for region_i in range(updated_regions.size()):
		var region: Dictionary = updated_regions[region_i]

		var outer_start_index: int = region["outer_start_index"]
		var outer_end_index: int = region["outer_end_index"]

		var start_removed_pos := _find_index_in_packed_int_array(
			removed_indices,
			outer_start_index
		)

		if start_removed_pos != -1:
			hits.append({
				"region_i": region_i,
				"endpoint_type": "start",
				"removed_pos": start_removed_pos
			})

		var end_removed_pos := _find_index_in_packed_int_array(
			removed_indices,
			outer_end_index
		)

		if end_removed_pos != -1:
			hits.append({
				"region_i": region_i,
				"endpoint_type": "end",
				"removed_pos": end_removed_pos
			})

	hits.sort_custom(func(a, b): return a["removed_pos"] < b["removed_pos"])

	var removed_regions := {}
	var handled_regions := {}

	# Edge case: two floor regions are connected by the same bad interval.
	# Only merge when the order is:
	# first region END -> removed interval -> second region START
	for hit_i in range(hits.size() - 1):
		var first_hit: Dictionary = hits[hit_i]
		var second_hit: Dictionary = hits[hit_i + 1]

		var first_region_i: int = first_hit["region_i"]
		var second_region_i: int = second_hit["region_i"]

		if first_region_i == second_region_i:
			continue

		if removed_regions.has(first_region_i) or removed_regions.has(second_region_i):
			continue

		if handled_regions.has(first_region_i) or handled_regions.has(second_region_i):
			continue

		# Sanity check: this merge formula is only valid for end -> start.
		if first_hit["endpoint_type"] != "end":
			continue

		if second_hit["endpoint_type"] != "start":
			continue

		var first_region: Dictionary = updated_regions[first_region_i]
		var second_region: Dictionary = updated_regions[second_region_i]

		var first_inner: PackedVector2Array = first_region["inner_points"]
		var second_inner: PackedVector2Array = second_region["inner_points"]

		# Use the removed points between the two endpoints.
		# Exclude the endpoints themselves to avoid duplicating edge points.
		var bridge_points := _slice_packed_vector2_array(
			removed_points,
			first_hit["removed_pos"] + 1,
			second_hit["removed_pos"] - 1
		)

		var super_inner := PackedVector2Array()
		super_inner.append_array(first_inner)
		super_inner.append_array(bridge_points)
		super_inner.append_array(second_inner)

		first_region["outer_start_index"] = first_region["outer_start_index"]
		first_region["outer_end_index"] = second_region["outer_end_index"]
		first_region["inner_points"] = super_inner

		updated_regions[first_region_i] = first_region

		# Important:
		# first_region_i should remain in final output, but should not be
		# corrected again by the normal single-endpoint code.
		handled_regions[first_region_i] = true

		# second_region_i has been merged into first_region_i and should vanish.
		removed_regions[second_region_i] = true

	# Normal single-endpoint correction.
	for hit in hits:
		var region_i: int = hit["region_i"]

		if handled_regions.has(region_i):
			continue

		if removed_regions.has(region_i):
			continue

		var region: Dictionary = updated_regions[region_i]
		var inner_points: PackedVector2Array = region["inner_points"]

		var removed_pos: int = hit["removed_pos"]
		var endpoint_type: String = hit["endpoint_type"]

		if endpoint_type == "start":
			# Exclude the endpoint itself. It is already represented by the region.
			var prefix := _slice_packed_vector2_array(
				removed_points,
				0,
				removed_pos - 1
			)

			var new_inner := PackedVector2Array()
			new_inner.append_array(prefix)
			new_inner.append_array(inner_points)

			region["inner_points"] = new_inner

		elif endpoint_type == "end":
			# Exclude the endpoint itself. It is already represented by the region.
			var suffix := _slice_packed_vector2_array(
				removed_points,
				removed_pos + 1,
				removed_points.size() - 1
			)

			var new_inner := PackedVector2Array()
			new_inner.append_array(inner_points)
			new_inner.append_array(suffix)

			region["inner_points"] = new_inner

		updated_regions[region_i] = region

	var final_regions: Array[Dictionary] = []

	for region_i in range(updated_regions.size()):
		if removed_regions.has(region_i):
			continue

		var region := _remap_floor_region_indices(
			updated_regions[region_i],
			old_to_new
		)

		final_regions.append(region)

	return final_regions




func _remap_floor_region_indices(
	region: Dictionary,
	old_to_new: PackedInt32Array
) -> Dictionary:
	var remapped := region.duplicate(true)

	var outer_start_index: int = remapped["outer_start_index"]
	var outer_end_index: int = remapped["outer_end_index"]

	if outer_start_index >= 0 and outer_start_index < old_to_new.size():
		remapped["outer_start_index"] = old_to_new[outer_start_index]

	if outer_end_index >= 0 and outer_end_index < old_to_new.size():
		remapped["outer_end_index"] = old_to_new[outer_end_index]

	return remapped




func _find_index_in_packed_int_array(
	values: PackedInt32Array,
	target: int
) -> int:
	for i in range(values.size()):
		if values[i] == target:
			return i

	return -1




func _slice_packed_vector2_array(
	points: PackedVector2Array,
	from_index: int,
	to_index: int
) -> PackedVector2Array:
	var result := PackedVector2Array()

	if points.is_empty():
		return result

	from_index = clampi(from_index, 0, points.size() - 1)
	to_index = clampi(to_index, 0, points.size() - 1)

	if from_index > to_index:
		return result

	for i in range(from_index, to_index + 1):
		result.append(points[i])

	return result



func make_bridges_on_level(
	level_info: Dictionary,
	rng: RandomNumberGenerator,
	rough_spacing: float,
	bridge_count: int,
	bridge_padding: float = 3.0
) -> Dictionary:
	var updated_level := level_info.duplicate(true)
	var floor_regions: Array = updated_level["floor_regions"]
	var cave_rand: PackedVector2Array = updated_level["cave_rand"]

	var bridge_links: Array[Dictionary] = []

	var floor_count := floor_regions.size()
	if floor_count < 2:
		return {
			"level_info": updated_level,
			"bridge_links": bridge_links
		}

	var max_logical_bridges := _get_max_logical_bridge_count(floor_count)
	var wanted_count := mini(bridge_count, max_logical_bridges)

	var planned_pairs := _plan_bridge_pairs(
		floor_regions,
		rng,
		wanted_count
	)

	for pair in planned_pairs:
		var a_i: int = pair["a"]
		var b_i: int = pair["b"]

		if a_i < 0 or a_i >= floor_regions.size():
			continue

		if b_i < 0 or b_i >= floor_regions.size():
			continue

		var attempt := _try_make_single_bridge(
			floor_regions,
			cave_rand,
			a_i,
			b_i,
			rng,
			rough_spacing,
			bridge_padding
		)

		if not attempt["success"]:
			continue

		floor_regions = attempt["floor_regions"]
		updated_level["floor_regions"] = floor_regions

		bridge_links.append({
			"height": updated_level["height"],
			"floor_a": a_i,
			"floor_b": b_i,
			"bridge_points": attempt["bridge_points"]
		})

	return {
		"level_info": updated_level,
		"bridge_links": bridge_links
	}



func _get_max_logical_bridge_count(floor_count: int) -> int:
	if floor_count <= 1:
		return 0

	if floor_count == 2:
		return 1

	if floor_count == 3:
		return 3

	return floor_count



func _plan_bridge_pairs(
	floor_regions: Array,
	rng: RandomNumberGenerator,
	wanted_count: int
) -> Array[Dictionary]:
	var pairs: Array[Dictionary] = []
	var degree := {}

	for i in range(floor_regions.size()):
		degree[i] = 0

	var candidate_pairs: Array[Dictionary] = []

	for a in range(floor_regions.size()):
		for b in range(a + 1, floor_regions.size()):
			candidate_pairs.append({
				"a": a,
				"b": b
			})

	candidate_pairs.shuffle()

	for candidate in candidate_pairs:
		if pairs.size() >= wanted_count:
			break

		var a: int = candidate["a"]
		var b: int = candidate["b"]

		if degree[a] >= 2:
			continue

		if degree[b] >= 2:
			continue

		if _planned_pair_crosses_existing_pairs(
			floor_regions,
			pairs,
			a,
			b
		):
			continue

		pairs.append(candidate)
		degree[a] += 1
		degree[b] += 1

	return pairs



func _planned_pair_crosses_existing_pairs(
	floor_regions: Array,
	pairs: Array[Dictionary],
	a_i: int,
	b_i: int
) -> bool:
	var a_pos := _floor_region_outer_position(floor_regions[a_i])
	var b_pos := _floor_region_outer_position(floor_regions[b_i])

	if a_pos > b_pos:
		var temp := a_pos
		a_pos = b_pos
		b_pos = temp

	for pair in pairs:
		var c_i: int = pair["a"]
		var d_i: int = pair["b"]

		var c_pos := _floor_region_outer_position(floor_regions[c_i])
		var d_pos := _floor_region_outer_position(floor_regions[d_i])

		if c_pos > d_pos:
			var temp_2 := c_pos
			c_pos = d_pos
			d_pos = temp_2

		var interleaves_1 := a_pos < c_pos and c_pos < b_pos and b_pos < d_pos
		var interleaves_2 := c_pos < a_pos and a_pos < d_pos and d_pos < b_pos

		if interleaves_1 or interleaves_2:
			return true

	return false




func _floor_region_outer_position(region: Dictionary) -> float:
	var outer_start_index: int = region["outer_start_index"]
	var outer_end_index: int = region["outer_end_index"]

	return float(outer_start_index + outer_end_index) * 0.5



func _try_make_single_bridge(
	floor_regions: Array,
	cave_rand: PackedVector2Array,
	a_i: int,
	b_i: int,
	rng: RandomNumberGenerator,
	rough_spacing: float,
	bridge_padding: float
) -> Dictionary:
	var a_region: Dictionary = floor_regions[a_i]
	var b_region: Dictionary = floor_regions[b_i]

	var a_points: PackedVector2Array = a_region["inner_points"]
	var b_points: PackedVector2Array = b_region["inner_points"]

	if a_points.size() < 6 or b_points.size() < 6:
		return {"success": false}

	var a_mid := a_points[a_points.size() / 2]
	var b_mid := b_points[b_points.size() / 2]

	var a_anchor := _find_best_bridge_anchor_index(
		a_points,
		b_mid,
		bridge_padding,
		rough_spacing
	)

	var b_anchor := _find_best_bridge_anchor_index(
		b_points,
		a_mid,
		bridge_padding,
		rough_spacing
	)

	if a_anchor == -1 or b_anchor == -1:
		return {"success": false}

	var a_center := a_points[a_anchor]
	var b_center := b_points[b_anchor]

	if not _bridge_centerline_is_valid(
		a_center,
		b_center,
		floor_regions,
		cave_rand,
		a_i,
		b_i,
		bridge_padding
	):
		return {"success": false}

	var centerline_length := a_center.distance_to(b_center)
	var bridge_width := _get_bridge_width_from_length(
		centerline_length,
		rough_spacing
	)

	var half_width := bridge_width * 0.5

	var a_span := _get_bridge_span_around_anchor(
		a_points,
		a_anchor,
		half_width,
		rough_spacing
	)

	var b_span := _get_bridge_span_around_anchor(
		b_points,
		b_anchor,
		half_width,
		rough_spacing
	)

	if not a_span["success"] or not b_span["success"]:
		return {"success": false}

	var a_left_i: int = a_span["left_i"]
	var a_right_i: int = a_span["right_i"]
	var b_left_i: int = b_span["left_i"]
	var b_right_i: int = b_span["right_i"]

	var a_left: Vector2 = a_points[a_left_i].lerp(a_points[a_left_i + 1], rng.randf_range(0.25, 0.75))
	var a_right: Vector2 = a_points[a_right_i].lerp(a_points[a_right_i + 1], rng.randf_range(0.25, 0.75))

	var b_left: Vector2 = b_points[b_left_i].lerp(b_points[b_left_i + 1], rng.randf_range(0.25, 0.75))
	var b_right: Vector2 = b_points[b_right_i].lerp(b_points[b_right_i + 1], rng.randf_range(0.25, 0.75))


	var ordered := _fix_bridge_endpoint_order(
		a_center,
		b_center,
		a_left,
		a_right,
		b_left,
		b_right
	)

	a_left = ordered["a_left"]
	a_right = ordered["a_right"]
	b_left = ordered["b_left"]
	b_right = ordered["b_right"]


	var mid_left := (a_left + b_left) * 0.5
	var mid_right := (a_right + b_right) * 0.5

	var a_bridge_path := resample_open_curve_by_spacing(
		PackedVector2Array([a_left, mid_left, mid_right, a_right]),
		rough_spacing
	)

	var b_bridge_path := resample_open_curve_by_spacing(
		PackedVector2Array([b_left, mid_left, mid_right, b_right]),
		rough_spacing
	)

	a_region["inner_points"] = _replace_index_interval_with_path_open(
		a_points,
		a_left_i,
		a_right_i + 1,
		a_bridge_path
	)

	b_region["inner_points"] = _replace_index_interval_with_path_open(
		b_points,
		b_left_i,
		b_right_i + 1,
		b_bridge_path
	)

	floor_regions[a_i] = a_region
	floor_regions[b_i] = b_region

	return {
		"success": true,
		"floor_regions": floor_regions,
		"bridge_points": PackedVector2Array([
			a_left,
			mid_left,
			b_left,
			b_right,
			mid_right,
			a_right
		])
	}



func _find_best_bridge_anchor_index(
	points: PackedVector2Array,
	target: Vector2,
	bridge_padding: float,
	rough_spacing: float
) -> int:
	if points.size() < 3:
		return -1

	var padding_count := maxi(1, int(ceil(bridge_padding / maxf(rough_spacing, 0.001))))

	if points.size() <= padding_count * 2 + 1:
		return -1

	var best_i := -1
	var best_distance_squared := INF

	for i in range(padding_count, points.size() - padding_count):
		var distance_squared := points[i].distance_squared_to(target)

		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_i = i

	return best_i



func _get_bridge_width_from_length(
	length: float,
	rough_spacing: float
) -> float:
	if length < rough_spacing * 35.0:
		return rough_spacing * 3.0

	return rough_spacing * 4.0



func _get_bridge_span_around_anchor(
	points: PackedVector2Array,
	anchor_i: int,
	half_width: float,
	rough_spacing: float
) -> Dictionary:
	var side_count := maxi(1, int(ceil(half_width / maxf(rough_spacing, 0.001))))

	var left_i := anchor_i - side_count
	var right_i := anchor_i + side_count

	if left_i < 0:
		return {"success": false}

	if right_i >= points.size() - 1:
		return {"success": false}

	return {
		"success": true,
		"left_i": left_i,
		"right_i": right_i
	}



func _bridge_centerline_is_valid(
	a: Vector2,
	b: Vector2,
	floor_regions: Array,
	cave_rand: PackedVector2Array,
	a_region_i: int,
	b_region_i: int,
	bridge_padding: float
) -> bool:
	var inner_boundary_segments := _build_level_inner_boundary_segments(
		floor_regions,
		cave_rand
	)

	var padding_squared := bridge_padding * bridge_padding

	for segment in inner_boundary_segments:
		var c: Vector2 = segment["a"]
		var d: Vector2 = segment["b"]
		var owner_region_i: int = segment["owner_region_i"]
		var segment_type: String = segment["type"]

		var belongs_to_connected_floor := (
			segment_type == "floor_inner"
			and (
				owner_region_i == a_region_i
				or owner_region_i == b_region_i
			)
		)

		if belongs_to_connected_floor:
			# The bridge may start/end on these two floor borders,
			# but it must not cut through them.
			if _segments_intersect(a, b, c, d):
				return false

			continue

		# Everything else is "the rest of the level's inner boundary".
		# The centerline must not cross it and must stay bridge_padding away.
		if _segment_to_segment_distance_squared(a, b, c, d) < padding_squared:
			return false

	return true
	if _segment_intersects_closed_polyline(a, b, cave_rand):
		return false

	for region_i in range(floor_regions.size()):
		var region: Dictionary = floor_regions[region_i]
		var points: PackedVector2Array = region["inner_points"]

		if region_i == a_region_i or region_i == b_region_i:
			if _segment_intersects_open_polyline(a, b, points):
				return false
		else:
			if _segment_intersects_open_polyline(a, b, points):
				return false

			if _segment_distance_to_open_polyline_squared(a, b, points) < bridge_padding * bridge_padding:
				return false

	return true


func _build_level_inner_boundary_segments(
	floor_regions: Array,
	cave_rand: PackedVector2Array
) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []

	for region_i in range(floor_regions.size()):
		var region: Dictionary = floor_regions[region_i]
		var inner_points: PackedVector2Array = region["inner_points"]

		for point_i in range(inner_points.size() - 1):
			segments.append({
				"a": inner_points[point_i],
				"b": inner_points[point_i + 1],
				"type": "floor_inner",
				"owner_region_i": region_i
			})

	var sorted_regions: Array[Dictionary] = []

	for region_i in range(floor_regions.size()):
		var region: Dictionary = floor_regions[region_i]

		sorted_regions.append({
			"region_i": region_i,
			"outer_start_index": region["outer_start_index"],
			"outer_end_index": region["outer_end_index"]
		})

	sorted_regions.sort_custom(
		func(a, b): return a["outer_start_index"] < b["outer_start_index"]
	)

	if sorted_regions.size() < 2:
		return segments

	for sorted_i in range(sorted_regions.size()):
		var current_region: Dictionary = sorted_regions[sorted_i]
		var next_region: Dictionary = sorted_regions[(sorted_i + 1) % sorted_regions.size()]

		var from_index: int = current_region["outer_end_index"]
		var to_index: int = next_region["outer_start_index"]

		_add_cave_rand_interval_segments(
			segments,
			cave_rand,
			from_index,
			to_index
		)

	return segments



func _add_cave_rand_interval_segments(
	segments: Array[Dictionary],
	cave_rand: PackedVector2Array,
	from_index: int,
	to_index: int
) -> void:
	var n := cave_rand.size()

	if n < 2:
		return

	from_index = clampi(from_index, 0, n - 1)
	to_index = clampi(to_index, 0, n - 1)

	var current := from_index
	var guard := 0

	while current != to_index and guard < n:
		var next := (current + 1) % n

		segments.append({
			"a": cave_rand[current],
			"b": cave_rand[next],
			"type": "cave_link",
			"owner_region_i": -1
		})

		current = next
		guard += 1


func _segment_intersects_closed_polyline(
	a: Vector2,
	b: Vector2,
	points: PackedVector2Array
) -> bool:
	if points.size() < 2:
		return false

	for i in range(points.size()):
		var c := points[i]
		var d := points[(i + 1) % points.size()]

		if _segments_intersect(a, b, c, d):
			return true

	return false



func _segment_intersects_open_polyline(
	a: Vector2,
	b: Vector2,
	points: PackedVector2Array
) -> bool:
	if points.size() < 2:
		return false

	for i in range(points.size() - 1):
		if _segments_intersect(a, b, points[i], points[i + 1]):
			return true

	return false



func _segment_distance_to_open_polyline_squared(
	a: Vector2,
	b: Vector2,
	points: PackedVector2Array
) -> float:
	if points.size() < 2:
		return INF

	var best := INF

	for i in range(points.size() - 1):
		var distance_squared := _segment_to_segment_distance_squared(
			a,
			b,
			points[i],
			points[i + 1]
		)

		if distance_squared < best:
			best = distance_squared

	return best



func _replace_index_interval_with_path_open(
	points: PackedVector2Array,
	left_i: int,
	right_i: int,
	replacement_path: PackedVector2Array
) -> PackedVector2Array:
	var result := PackedVector2Array()

	if points.size() < 2:
		return points

	left_i = clampi(left_i, 0, points.size() - 1)
	right_i = clampi(right_i, 0, points.size() - 1)

	if left_i > right_i:
		var temp := left_i
		left_i = right_i
		right_i = temp

	for i in range(0, left_i):
		result.append(points[i])

	for p in replacement_path:
		if result.is_empty() or result[result.size() - 1].distance_squared_to(p) > 0.000001:
			result.append(p)

	for i in range(right_i + 1, points.size()):
		var p := points[i]

		if result.is_empty() or result[result.size() - 1].distance_squared_to(p) > 0.000001:
			result.append(p)

	return result




func _segments_intersect(
	a: Vector2,
	b: Vector2,
	c: Vector2,
	d: Vector2
) -> bool:
	var ab := b - a
	var cd := d - c

	var denominator := _cross_2d(ab, cd)

	if absf(denominator) < 0.000001:
		return false

	var ac := c - a
	var t := _cross_2d(ac, cd) / denominator
	var u := _cross_2d(ac, ab) / denominator

	return t > 0.0001 and t < 0.9999 and u > 0.0001 and u < 0.9999



func _cross_2d(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x



func _segment_to_segment_distance_squared(
	a: Vector2,
	b: Vector2,
	c: Vector2,
	d: Vector2
) -> float:
	if _segments_intersect(a, b, c, d):
		return 0.0

	var d1 := _point_to_segment_distance_squared(a, c, d)
	var d2 := _point_to_segment_distance_squared(b, c, d)
	var d3 := _point_to_segment_distance_squared(c, a, b)
	var d4 := _point_to_segment_distance_squared(d, a, b)

	return minf(minf(d1, d2), minf(d3, d4))



func _point_to_segment_distance_squared(
	p: Vector2,
	a: Vector2,
	b: Vector2
) -> float:
	var ab := b - a
	var ab_len_squared := ab.length_squared()

	if ab_len_squared <= 0.000001:
		return p.distance_squared_to(a)

	var t := (p - a).dot(ab) / ab_len_squared
	t = clampf(t, 0.0, 1.0)

	var closest := a + ab * t
	return p.distance_squared_to(closest)



func _fix_bridge_endpoint_order(
	a_center: Vector2,
	b_center: Vector2,
	a_left: Vector2,
	a_right: Vector2,
	b_left: Vector2,
	b_right: Vector2
) -> Dictionary:
	var dir := (b_center - a_center).normalized()
	var side := Vector2(-dir.y, dir.x)

	var a_left_side := (a_left - a_center).dot(side)
	var a_right_side := (a_right - a_center).dot(side)

	if a_left_side > a_right_side:
		var temp_a := a_left
		a_left = a_right
		a_right = temp_a

	var b_left_side := (b_left - b_center).dot(side)
	var b_right_side := (b_right - b_center).dot(side)

	if b_left_side > b_right_side:
		var temp_b := b_left
		b_left = b_right
		b_right = temp_b

	return {
		"a_left": a_left,
		"a_right": a_right,
		"b_left": b_left,
		"b_right": b_right
	}
