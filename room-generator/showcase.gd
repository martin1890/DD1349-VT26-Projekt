extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var blob := generate_blob(Vector2.ZERO, 30.0, 1.0)
	create_blob_mesh(blob)

	var result := create_blob_wall_with_openings(
		rng,
		blob,
		4,      # exit_count
		3.0,    # exit_radius
		65.0,   # floor_percent
		1.0,    # vertices_per_unit
		12,     # vertical_steps
		0.35    # noise_strength
	)

	# Useful later if you want to attach tunnels.
	print(result["exit_positions"])
	print(result["exit_outward_dirs"])

func generate_blob(
	center: Vector2,
	base_radius: float,
	vertex_spacing: float = 8.0,
	rough_points: int = 48,
	irregularity: float = 0.35,
	smooth_steps: int = 3
) -> PackedVector2Array:
	var rough := PackedVector2Array()
	var radii: Array[float] = []

	# Generate random radii
	for i in range(rough_points):
		var r := base_radius * randf_range(1.0 - irregularity, 1.0 + irregularity)
		radii.append(r)

	# Smooth radii cyclically
	for s in range(smooth_steps):
		var new_radii: Array[float] = []
		for i in range(rough_points):
			var prev := radii[(i - 1 + rough_points) % rough_points]
			var curr := radii[i]
			var next := radii[(i + 1) % rough_points]
			new_radii.append((prev + curr + next) / 3.0)
		radii = new_radii

	# Create initial polygon
	for i in range(rough_points):
		var angle := TAU * float(i) / float(rough_points)
		var p := center + Vector2(cos(angle), sin(angle)) * radii[i]
		rough.append(p)

	# Resample edge with even spacing
	return resample_closed_polygon_by_spacing(rough, vertex_spacing, center, base_radius)
	
	
	
func resample_closed_polygon_by_spacing(
	points: PackedVector2Array,
	vertex_spacing: float,
	center: Vector2,
	base_radius: float,
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

	var target_count := maxi(8, int(round(total_length / vertex_spacing)))
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


func create_blob_mesh(blob: PackedVector2Array) -> void:
	var mesh := ArrayMesh.new()

	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()

	# Center vertex
	vertices.append(Vector3.ZERO)

	# Convert 2D blob points to 3D points on the XZ plane
	for p in blob:
		vertices.append(Vector3(p.x, 0.0, p.y))

	# Triangle fan
	for i in range(blob.size()):
		var a := 0
		var b := i + 1
		var c := ((i + 1) % blob.size()) + 1

		indices.append(a)
		indices.append(b)
		indices.append(c)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	add_child(mesh_instance)



func create_blob_wall_with_openings(
	rng: RandomNumberGenerator,
	blob: PackedVector2Array,
	exit_count: int,
	exit_radius: float = 3.0,
	floor_percent: float = 65.0,
	vertices_per_unit: float = 1.0,
	vertical_steps: int = 12,
	noise_strength: float = 0.35
) -> Dictionary:
	if blob.size() < 3:
		push_error("Blob needs at least 3 boundary points.")
		return {}

	if exit_count < 1:
		push_error("exit_count must be at least 1.")
		return {}

	# StairRoomCavern-compatible profile values.

	var percent: float = clamp(floor_percent, 0.0, 100.0) / 100.0
	var vertical_offset: float = -exit_radius * percent
	var center_height: float = -vertical_offset
	var opening_top_y: float = center_height + exit_radius
	var start_y: float = 0.0
	var top_y: float = start_y + opening_top_y
	var row_spacing: float = opening_top_y / float(vertical_steps)
	var max_vertical_offset: float = row_spacing * 0.45
	var max_horizontal_offset: float = min(row_spacing * 0.75, exit_radius * 0.25)
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var base_ring := PackedVector3Array()
	var base_ring_indices := PackedInt32Array()
	for p in blob:
		var pos := Vector3(p.x, 0.0, p.y)
		base_ring.append(pos)
		base_ring_indices.append(vertices.size())
		vertices.append(pos)
	var base_ring_2d := PackedVector2Array()
	for p in base_ring:
		base_ring_2d.append(Vector2(p.x, p.z))
	var centroid: Vector2 = _compute_centroid(base_ring_2d)


	var current_top_ring: PackedInt32Array = base_ring_indices
	var current_top_y: float = start_y

	var all_exit_distances: Array = []
	var all_exit_positions: Array = []
	var all_exit_outward_dirs: Array = []
	var continuous_top_row := PackedInt32Array()

	var floor_areas: Array = []
	var parent_vertex_map := {}

	var floor_wall_count := 0
	var last_action := ""

	var low_opening_chance_after_plain_wall := 0.15
	var max_safety_iterations := 80
	var safety := 0

	# Randomly allow the whole structure to start with an opening wall.
	# If it does not, the first action below will be create_walls(add_floors = true).
	if rng.randf() < 0.5:
		var opening_result := _run_opening_wall_layer(
			rng,
			vertices,
			indices,
			current_top_ring,
			current_top_y,
			percent,
			exit_count,
			exit_radius,
			center_height,
			opening_top_y,
			row_spacing,
			max_horizontal_offset,
			max_vertical_offset,
			centroid,
			vertices_per_unit,
			vertical_steps,
			noise_strength
		)

		current_top_ring = opening_result["current_top_ring"]
		current_top_y = opening_result["current_top_y"]

		all_exit_distances.append_array(opening_result["exit_distances"])
		all_exit_positions.append_array(opening_result["exit_positions"])
		all_exit_outward_dirs.append_array(opening_result["exit_outward_dirs"])
		continuous_top_row = opening_result["continuous_top_row"]

		last_action = "opening_wall"

	while floor_wall_count < 3 and safety < max_safety_iterations:
		safety += 1

		var should_run_floor_wall := false

		# The first create_walls call must always use add_floors = true.
		if floor_wall_count == 0:
			should_run_floor_wall = true
		else:
			# After the first floor-wall, sometimes insert plain walls before next floor-wall.
			should_run_floor_wall = rng.randf() < 0.45

		if should_run_floor_wall:
			var rows_lower := 1
			var rows_upper := 1

			# First floor-wall may be taller.
			if floor_wall_count == 0:
				rows_lower = 3
				rows_upper = 8

			var floor_wall_result := _run_extra_wall_layer(
				rng,
				vertices,
				indices,
				current_top_ring,
				current_top_y,
				centroid,
				noise_strength,
				row_spacing,
				max_horizontal_offset,
				max_vertical_offset,
				rows_lower,
				rows_upper,
				true,
				parent_vertex_map
			)

			current_top_ring = floor_wall_result["current_top_ring"]
			current_top_y = floor_wall_result["current_top_y"]
			parent_vertex_map = floor_wall_result["parent_vertex_map"]
			floor_areas.append_array(floor_wall_result["areas"])

			floor_wall_count += 1
			last_action = "floor_wall"

			# Mandatory opening wall directly after every floor-wall.
			var forced_opening_result := _run_opening_wall_layer(
				rng,
				vertices,
				indices,
				current_top_ring,
				current_top_y,
				percent,
				exit_count,
				exit_radius,
				center_height,
				opening_top_y,
				row_spacing,
				max_horizontal_offset,
				max_vertical_offset,
				centroid,
				vertices_per_unit,
				vertical_steps,
				noise_strength,
				false,
				true,
				row_spacing*rng.randf()
			)

			current_top_ring = forced_opening_result["current_top_ring"]
			current_top_y = forced_opening_result["current_top_y"]

			all_exit_distances.append_array(forced_opening_result["exit_distances"])
			all_exit_positions.append_array(forced_opening_result["exit_positions"])
			all_exit_outward_dirs.append_array(forced_opening_result["exit_outward_dirs"])
			continuous_top_row = forced_opening_result["continuous_top_row"]

			last_action = "opening_wall"

		else:
			var plain_wall_result := _run_extra_wall_layer(
				rng,
				vertices,
				indices,
				current_top_ring,
				current_top_y,
				centroid,
				noise_strength,
				row_spacing,
				max_horizontal_offset,
				max_vertical_offset,
				3,
				8,
				false,
				parent_vertex_map,
				false, # expand
				true,  # contract
				row_spacing * 1
			)

			current_top_ring = plain_wall_result["current_top_ring"]
			current_top_y = plain_wall_result["current_top_y"]
			parent_vertex_map = plain_wall_result["parent_vertex_map"]

			last_action = "plain_wall"

			# Low chance of opening wall after a plain wall.
			# This can never happen directly after another opening wall,
			# because the previous action here is plain_wall.
			if rng.randf() < low_opening_chance_after_plain_wall:
				var optional_opening_result := _run_opening_wall_layer(
					rng,
					vertices,
					indices,
					current_top_ring,
					current_top_y,
					percent,
					exit_count,
					exit_radius,
					center_height,
					opening_top_y,
					row_spacing,
					max_horizontal_offset,
					max_vertical_offset,
					centroid,
					vertices_per_unit,
					vertical_steps,
					noise_strength,
					false,
					true,
					row_spacing
				)

				current_top_ring = optional_opening_result["current_top_ring"]
				current_top_y = optional_opening_result["current_top_y"]

				all_exit_distances.append_array(optional_opening_result["exit_distances"])
				all_exit_positions.append_array(optional_opening_result["exit_positions"])
				all_exit_outward_dirs.append_array(optional_opening_result["exit_outward_dirs"])
				continuous_top_row = optional_opening_result["continuous_top_row"]

				last_action = "opening_wall"

	# Selection happens once, after all extra rows exist.
	


	# Build normals.
	var normals := _build_vertex_normals(vertices, indices)

	# Simple UVs.
	var uvs := PackedVector2Array()
	uvs.resize(vertices.size())
	for i in range(vertices.size()):
		var v: Vector3 = vertices[i]
		uvs[i] = Vector2(v.x * 0.25, v.y * 0.25)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "BlobWall"
	mesh_instance.mesh = mesh
	add_child(mesh_instance)

	var material := StandardMaterial3D.new()
	#material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	material.albedo_color = Color(0.32, 0.29, 0.25)
	mesh_instance.material_override = material


	return {
		"mesh_instance": mesh_instance,
		"exit_distances": all_exit_distances,
		"exit_positions": all_exit_positions,
		"exit_outward_dirs": all_exit_outward_dirs,
		"path_center_height": center_height,
		"opening_top_y": opening_top_y,
		"continuous_top_row": continuous_top_row,
		"final_top_ring": current_top_ring,
		"floor_areas": floor_areas,
		"parent_vertex_map": parent_vertex_map
	}
	

func _build_closed_path_info(points: PackedVector2Array) -> Dictionary:
	var cumulative_lengths: Array = [0.0]
	var total_length := 0.0
	var n := points.size()

	for i in range(n):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % n]
		total_length += a.distance_to(b)
		cumulative_lengths.append(total_length)

	return {
		"points": points,
		"cumulative_lengths": cumulative_lengths,
		"total_length": total_length,
	}


func _sample_closed_path_2d(
	points: PackedVector2Array,
	cumulative_lengths: Array,
	total_length: float,
	distance_along_path: float
) -> Vector2:
	var s: float = fposmod(distance_along_path, total_length)
	var n := points.size()

	for i in range(n):
		var l0: float = cumulative_lengths[i]
		var l1: float = cumulative_lengths[i + 1]

		if s <= l1 or i == n - 1:
			var seg_length: float = l1 - l0
			var t := 0.0
			if seg_length > 0.00001:
				t = (s - l0) / seg_length
			return points[i].lerp(points[(i + 1) % n], t)

	return points[0]


func _generate_exit_distances(
	rng: RandomNumberGenerator,
	total_length: float,
	exit_count: int,
	min_separation: float
) -> Array:
	var result: Array = []
	var max_attempts := 8000
	var attempts := 0

	while result.size() < exit_count and attempts < max_attempts:
		var candidate: float = rng.randf() * total_length
		var ok := true

		for existing in result:
			var d: float = abs(candidate - existing)
			d = min(d, total_length - d)
			if d < min_separation:
				ok = false
				break

		if ok:
			result.append(candidate)

		attempts += 1

	result.sort()

	# Fallback to even spacing if random placement failed.
	if result.size() != exit_count:
		result.clear()
		for i in range(exit_count):
			var base_s: float = total_length * float(i) / float(exit_count)
			var jitter: float = rng.randf_range(-0.15, 0.15) * min_separation
			result.append(fposmod(base_s + jitter, total_length))
		result.sort()

	return result


func _opening_chord_width_at_y(
	y: float,
	radius: float,
	center_height: float
) -> float:
	var local_y: float = y - center_height
	var inside: float = radius * radius - local_y * local_y
	if inside <= 0.0:
		return 0.0
	return sqrt(inside) * 2.0


func _build_interval_row_positions_3d(
	path_info: Dictionary,
	start_center_s: float,
	end_center_s: float,
	y: float,
	chord_width: float,
	vertices_per_unit: float
) -> Array:
	var total_length: float = path_info["total_length"]

	var start_s: float = start_center_s + chord_width * 0.5
	var end_s: float = end_center_s - chord_width * 0.5
	var span_length: float = end_s - start_s

	var segment_count: int = max(1, int(round(span_length * vertices_per_unit)))
	var result: Array = []

	for i in range(segment_count + 1):
		var t: float = float(i) / float(segment_count)
		var s: float = lerp(start_s, end_s, t)

		var p2: Vector2 = _sample_closed_path_2d(
			path_info["points"],
			path_info["cumulative_lengths"],
			total_length,
			s
		)

		result.append(Vector3(p2.x, y, p2.y))

	return result


func _perturb_wall_vertex(
	base_pos: Vector3,
	centroid: Vector2,
	noise_strength: float,
	max_horizontal_offset: float,
	max_vertical_offset: float,
	y: float,
	top_y: float
) -> Vector3:
	var seed := _hash_position_to_seed(base_pos)

	var rx := _hash_float(seed + 11) * 2.0 - 1.0
	var ry := _hash_float(seed + 37) * 2.0 - 1.0
	var rz := _hash_float(seed + 71) * 2.0 - 1.0

	var random_dir := Vector3(rx, ry, rz)
	if random_dir.length_squared() < 0.0001:
		random_dir = Vector3.UP
	else:
		random_dir = random_dir.normalized()

	var horizontal_amount: float = min(noise_strength, max_horizontal_offset)
	var vertical_amount: float = min(noise_strength, max_vertical_offset)

	var offset := Vector3(
		random_dir.x * horizontal_amount,
		random_dir.y * vertical_amount,
		random_dir.z * horizontal_amount
	)

	var final_pos := base_pos + offset

	# Keep bottom fixed elsewhere by not calling this function for row 0.
	# Clamp so vertices do not go below the floor.
	final_pos.y = clamp(final_pos.y, 0.0, top_y + max_vertical_offset)

	return final_pos


func _stitch_rows(
	indices: PackedInt32Array,
	row_a: PackedInt32Array,
	row_b: PackedInt32Array
) -> void:
	if row_a.size() < 2 or row_b.size() < 2:
		return

	var a_last: int = row_a.size() - 1
	var b_last: int = row_b.size() - 1

	var i := 0
	var j := 0

	while i < a_last or j < b_last:
		var next_t_a := INF
		var next_t_b := INF

		if i < a_last:
			next_t_a = float(i + 1) / float(a_last)
		if j < b_last:
			next_t_b = float(j + 1) / float(b_last)

		if i < a_last and (j >= b_last or next_t_a <= next_t_b):
			indices.append(row_a[i])
			indices.append(row_b[j])
			indices.append(row_a[i + 1])
			i += 1
		elif j < b_last:
			indices.append(row_a[i])
			indices.append(row_b[j])
			indices.append(row_b[j + 1])
			j += 1


func _build_vertex_normals(
	vertices: PackedVector3Array,
	indices: PackedInt32Array
) -> PackedVector3Array:
	var accum: Array = []
	accum.resize(vertices.size())
	for i in range(accum.size()):
		accum[i] = Vector3.ZERO

	for t in range(0, indices.size(), 3):
		var ia: int = indices[t]
		var ib: int = indices[t + 1]
		var ic: int = indices[t + 2]

		var a: Vector3 = vertices[ia]
		var b: Vector3 = vertices[ib]
		var c: Vector3 = vertices[ic]

		var normal := (b - a).cross(c - a)
		if normal.length_squared() > 0.000001:
			normal = normal.normalized()

		accum[ia] += normal
		accum[ib] += normal
		accum[ic] += normal

	var normals := PackedVector3Array()
	normals.resize(vertices.size())

	for i in range(vertices.size()):
		var n: Vector3 = accum[i]
		if n.length_squared() > 0.000001:
			n = n.normalized()
		else:
			n = Vector3.UP
		normals[i] = n

	return normals


func _compute_centroid(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO

	var sum := Vector2.ZERO
	for p in points:
		sum += p

	return sum / float(points.size())


func _hash_position_to_seed(pos: Vector3) -> int:
	# Quantize position so tiny float differences do not create totally different random values.
	var qx := int(round(pos.x * 1000.0))
	var qy := int(round(pos.y * 1000.0))
	var qz := int(round(pos.z * 1000.0))

	var h := qx * 73856093
	h = h ^ (qy * 19349663)
	h = h ^ (qz * 83492791)

	return abs(h)


func _hash_float(seed: int) -> float:
	var x := seed
	x = ((x >> 16) ^ x) * 73244475
	x = ((x >> 16) ^ x) * 73244475
	x = (x >> 16) ^ x

	return float(abs(x % 100000)) / 100000.0


func _add_wall_row_above(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	previous_interval_rows: Array,
	target_y: float,
	centroid: Vector2,
	noise_strength: float,
	max_horizontal_offset: float,
	max_vertical_offset: float
) -> Array:
	var new_interval_rows: Array = []

	for i in range(previous_interval_rows.size()):
		var previous_row: PackedInt32Array = previous_interval_rows[i]
		var new_row := PackedInt32Array()

		for j in range(previous_row.size()):
			var reuse_existing := false
			var reused_index := -1

			if i > 0 and j == 0:
				reuse_existing = true
				var previous_new_row: PackedInt32Array = new_interval_rows[i - 1]
				reused_index = previous_new_row[previous_new_row.size() - 1]

			elif i == previous_interval_rows.size() - 1 and j == previous_row.size() - 1:
				reuse_existing = true
				var first_new_row: PackedInt32Array = new_interval_rows[0]
				reused_index = first_new_row[0]

			if reuse_existing:
				new_row.append(reused_index)
			else:
				var old_vertex: Vector3 = vertices[previous_row[j]]

				# Same x/z as row below, but fixed ideal height for this row.
				var base_pos := Vector3(
					old_vertex.x,
					target_y,
					old_vertex.z
				)

				var final_pos := _perturb_wall_vertex(
					base_pos,
					centroid,
					noise_strength,
					max_horizontal_offset,
					max_vertical_offset,
					target_y,
					target_y
				)

				var new_index := vertices.size()
				vertices.append(final_pos)
				new_row.append(new_index)

		_stitch_rows(indices, previous_row, new_row)
		new_interval_rows.append(new_row)

	return new_interval_rows


func _make_continuous_ring_from_interval_rows(interval_rows: Array) -> PackedInt32Array:
	var ring := PackedInt32Array()

	for i in range(interval_rows.size()):
		var row: PackedInt32Array = interval_rows[i]

		for j in range(row.size()):
			# Skip first vertex except for first interval,
			# because it overlaps previous interval's last vertex.
			if i > 0 and j == 0:
				continue

			# Skip final closing duplicate on last interval.
			if i == interval_rows.size() - 1 and j == row.size() - 1:
				continue

			ring.append(row[j])

	return ring
	


func _select_and_flatten_floor_vertex_span(
	rng: RandomNumberGenerator,
	vertices: PackedVector3Array,
	ring: PackedInt32Array,
	row_y: float,
	min_side_steps: int = 8,
	max_side_steps: int = 18
) -> Dictionary:
	var selected := PackedInt32Array()

	var ring_size := ring.size()
	if ring_size <= 0:
		return {
			"selected": selected,
			"start_ring_i": -1,
			"end_ring_i": -1
		}

	if ring_size < 6:
		return {
			"selected": selected,
			"start_ring_i": -1,
			"end_ring_i": -1
		}

	var max_allowed_side_steps := maxi(1, int((ring_size - 1) / 2) - 1)

	min_side_steps = clamp(min_side_steps, 1, max_allowed_side_steps)
	max_side_steps = clamp(max_side_steps, min_side_steps, max_allowed_side_steps)

	var center_ring_i := rng.randi_range(0, ring_size - 1)
	var side_steps := rng.randi_range(min_side_steps, max_side_steps)

	var start_ring_i := (center_ring_i - side_steps + ring_size) % ring_size
	var end_ring_i := (center_ring_i + side_steps) % ring_size

	var ring_i := start_ring_i

	while true:
		var vertex_index: int = ring[ring_i]

		var p: Vector3 = vertices[vertex_index]
		p.y = row_y
		vertices[vertex_index] = p

		selected.append(vertex_index)

		if ring_i == end_ring_i:
			break

		ring_i = (ring_i + 1) % ring_size

	return {
		"selected": selected,
		"start_ring_i": start_ring_i,
		"end_ring_i": end_ring_i
	}
	
	
func _debug_spawn_vertex_balls(
	vertices: PackedVector3Array,
	selected_vertex_indices: PackedInt32Array,
	radius: float = 0.25
) -> void:
	var parent := Node3D.new()
	parent.name = "DebugSelectedFloorVertices"
	add_child(parent)

	var count := selected_vertex_indices.size()
	if count == 0:
		return

	for order_i in range(count):
		var vertex_index: int = selected_vertex_indices[order_i]
		var p: Vector3 = vertices[vertex_index]

		var ball := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = radius
		sphere.height = radius * 2.0
		ball.mesh = sphere

		ball.position = p + Vector3.UP * 0.2

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


func add_floor_extension(
	current_top_rows: Array,
	extra_rows: int,
	row_spacing: float,
	top_y: float,
	rng: RandomNumberGenerator,
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	centroid: Vector2,
	min_side_steps: int = 8,
	max_side_steps: int = 18,
	debug_ball_radius: float = 0.28,
	arc_vertex_spacing: float = 2.0,
	rough_points: int = 5,
	irregularity: float = 0.25,
	smooth_steps: int = 2,
	edge_noise_strength: float = 0.2,
	edge_noise_frequency: float = 0.12
) -> PackedInt32Array:
	var current_top_ring: PackedInt32Array = _make_continuous_ring_from_interval_rows(current_top_rows)
	var final_row_y: float = top_y + row_spacing * float(extra_rows)

	var selection: Dictionary = _select_and_flatten_floor_vertex_span(
		rng,
		vertices,
		current_top_ring,
		final_row_y,
		min_side_steps,
		max_side_steps
	)

	var selected_floor_vertices: PackedInt32Array = selection["selected"]
	var start_ring_i: int = selection["start_ring_i"]
	var end_ring_i: int = selection["end_ring_i"]

	_debug_spawn_vertex_balls(
		vertices,
		selected_floor_vertices,
		debug_ball_radius
	)

	var outer_arc_vertices: PackedInt32Array = _create_debug_full_circle_from_selected_span_diameter(
		vertices,
		selected_floor_vertices,
		centroid,
		final_row_y,
		arc_vertex_spacing,
		rough_points,
		irregularity,
		smooth_steps,
		edge_noise_strength,
		edge_noise_frequency
	)

	_debug_spawn_vertex_balls(
		vertices,
		outer_arc_vertices,
		debug_ball_radius * 1.25
	)

	_create_floor_from_selected_span_and_outer_arc(
		vertices,
		indices,
		selected_floor_vertices,
		outer_arc_vertices,
		final_row_y
	)

	var updated_ring: PackedInt32Array = _replace_ring_span_with_outer_arc(
		current_top_ring,
		start_ring_i,
		end_ring_i,
		outer_arc_vertices
	)

	return updated_ring
	
	
func _create_debug_full_circle_from_selected_span_diameter(
	vertices: PackedVector3Array,
	selected_floor_vertices: PackedInt32Array,
	centroid: Vector2,
	floor_y: float,
	circle_vertex_spacing: float = 1.0,
	rough_points: int = 16,
	irregularity: float = 0.35,
	smooth_steps: int = 3,
	edge_noise_strength: float = 0.5,
	edge_noise_frequency: float = 0.15
) -> PackedInt32Array:
	var arc_indices := PackedInt32Array()

	if selected_floor_vertices.size() < 2:
		return arc_indices

	var start_index: int = selected_floor_vertices[0]
	var end_index: int = selected_floor_vertices[selected_floor_vertices.size() - 1]

	var start_pos: Vector3 = vertices[start_index]
	var end_pos: Vector3 = vertices[end_index]

	start_pos.y = floor_y
	end_pos.y = floor_y

	vertices[start_index] = start_pos
	vertices[end_index] = end_pos

	var center := (start_pos + end_pos) * 0.5
	center.y = floor_y

	var diameter_vec := end_pos - start_pos
	diameter_vec.y = 0.0

	var diameter_length := diameter_vec.length()
	if diameter_length < 0.001:
		return arc_indices

	var base_radius := diameter_length * 0.5

	var x_axis := diameter_vec.normalized()
	var z_axis := Vector3(-x_axis.z, 0.0, x_axis.x).normalized()

	var outward_2d := Vector2(center.x - centroid.x, center.z - centroid.y)
	if outward_2d.length() > 0.001:
		outward_2d = outward_2d.normalized()
		var outward := Vector3(outward_2d.x, 0.0, outward_2d.y)

		if z_axis.dot(outward) < 0.0:
			z_axis = -z_axis

	rough_points = maxi(3, rough_points)

	var rough_positions: Array[Vector3] = []
	var radii: Array[float] = []

	for i in range(rough_points + 1):
		var t := float(i) / float(rough_points)

		if i == 0 or i == rough_points:
			radii.append(base_radius)
		else:
			var r := base_radius * randf_range(1.0 - irregularity, 1.0 + irregularity)
			radii.append(r)

	for s in range(smooth_steps):
		var new_radii: Array[float] = []

		for i in range(rough_points + 1):
			if i == 0 or i == rough_points:
				new_radii.append(base_radius)
			else:
				var prev := radii[i - 1]
				var curr := radii[i]
				var next := radii[i + 1]
				new_radii.append((prev + curr + next) / 3.0)

		radii = new_radii

	for i in range(rough_points + 1):
		var t := float(i) / float(rough_points)
		var angle := PI + PI * t

		var p := center
		p += x_axis * cos(angle) * radii[i]
		p += z_axis * -sin(angle) * radii[i]
		p.y = floor_y

		if i == 0:
			p = start_pos
		elif i == rough_points:
			p = end_pos

		rough_positions.append(p)

	var resampled_positions: Array[Vector3] = _resample_open_polyline_by_spacing_3d(
		rough_positions,
		circle_vertex_spacing,
		edge_noise_strength,
		edge_noise_frequency,
		center,
		x_axis,
		z_axis,
		base_radius*3,
		floor_y
	)

	arc_indices.append(start_index)

	for i in range(1, resampled_positions.size() - 1):
		var idx := vertices.size()
		vertices.append(resampled_positions[i])
		arc_indices.append(idx)

	arc_indices.append(end_index)

	return arc_indices
	
	
func _resample_open_polyline_by_spacing_3d(
	points: Array[Vector3],
	vertex_spacing: float,
	noise_strength: float,
	noise_frequency: float,
	center: Vector3,
	x_axis: Vector3,
	z_axis: Vector3,
	base_radius: float,
	floor_y: float
) -> Array[Vector3]:
	var result: Array[Vector3] = []

	if points.size() < 2:
		return result

	var lengths: Array[float] = []
	var total_length := 0.0

	for i in range(points.size() - 1):
		var segment_length := points[i].distance_to(points[i + 1])
		lengths.append(segment_length)
		total_length += segment_length

	var target_count := maxi(2, int(round(total_length / vertex_spacing)))
	var actual_spacing := total_length / float(target_count)

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = noise_frequency
	noise.seed = randi()

	for k in range(target_count + 1):
		var target_distance := actual_spacing * float(k)

		var accumulated := 0.0
		var current_edge := 0

		while current_edge < lengths.size() - 1 and accumulated + lengths[current_edge] < target_distance:
			accumulated += lengths[current_edge]
			current_edge += 1

		var edge_start: Vector3 = points[current_edge]
		var edge_end: Vector3 = points[current_edge + 1]
		var edge_length: float = lengths[current_edge]

		var t := 0.0
		if edge_length > 0.0:
			t = (target_distance - accumulated) / edge_length

		var p := edge_start.lerp(edge_end, t)
		p.y = floor_y

		# Keep endpoints fixed.
		if k != 0 and k != target_count:
			var from_center := p - center
			from_center.y = 0.0

			if from_center.length() > 0.001:
				var radial_dir := from_center.normalized()
				var noise_value := noise.get_noise_1d(float(k))
				p += radial_dir * noise_value * noise_strength
				p.y = floor_y

		result.append(p)

	# Force exact endpoints.
	result[0] = points[0]
	result[result.size() - 1] = points[points.size() - 1]

	return result

func _create_floor_from_selected_span_and_outer_arc(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	selected_floor_vertices: PackedInt32Array,
	outer_arc_vertices: PackedInt32Array,
	floor_y: float
) -> void:
	if selected_floor_vertices.size() < 2:
		return
	if outer_arc_vertices.size() < 2:
		return

	# Keep wall vertices separate from floor vertices so normals do not get averaged together.
	var inner_floor_curve := _duplicate_curve_for_floor(
		vertices,
		selected_floor_vertices,
		floor_y
	)

	var outer_floor_curve := _duplicate_curve_for_floor(
		vertices,
		outer_arc_vertices,
		floor_y
	)

	_stitch_floor_curves(
		vertices,
		indices,
		inner_floor_curve,
		outer_floor_curve
	)
	
func _stitch_floor_curves(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	inner_curve: PackedInt32Array,
	outer_curve: PackedInt32Array
) -> void:
	if inner_curve.size() < 2 or outer_curve.size() < 2:
		return

	var inner_last := inner_curve.size() - 1
	var outer_last := outer_curve.size() - 1

	var i := 0
	var j := 0

	while i < inner_last or j < outer_last:
		var next_t_inner := INF
		var next_t_outer := INF

		if i < inner_last:
			next_t_inner = float(i + 1) / float(inner_last)

		if j < outer_last:
			next_t_outer = float(j + 1) / float(outer_last)

		if i < inner_last and (j >= outer_last or next_t_inner <= next_t_outer):
			var a := inner_curve[i]
			var b := outer_curve[j]
			var c := inner_curve[i + 1]

			# If invisible from above, swap b/c.
			indices.append_array([a, b, c])

			i += 1
		elif j < outer_last:
			var a := inner_curve[i]
			var b := outer_curve[j]
			var c := outer_curve[j + 1]

			# If invisible from above, swap b/c.
			indices.append_array([a, b, c])

			j += 1


func _replace_ring_span_with_outer_arc(
	current_ring: PackedInt32Array,
	start_ring_i: int,
	end_ring_i: int,
	outer_arc_vertices: PackedInt32Array
) -> PackedInt32Array:
	var new_ring := PackedInt32Array()

	var ring_size := current_ring.size()
	if ring_size == 0:
		return new_ring

	if start_ring_i < 0 or end_ring_i < 0:
		return current_ring

	if outer_arc_vertices.size() < 2:
		return current_ring

	# Keep the part of the old ring that is NOT replaced.
	# This walks from end -> start, preserving the outside remainder.
	var i := end_ring_i
	while true:
		new_ring.append(current_ring[i])

		if i == start_ring_i:
			break

		i = (i + 1) % ring_size

	# Add the new outer boundary from start -> end.
	# Skip endpoints because new_ring already contains end and start.
	# new_ring currently ends at start, so append arc interior from start side to end side,
	# then the ring is cyclically connected back to the first vertex, which is end.
	for j in range(1, outer_arc_vertices.size() - 1):
		new_ring.append(outer_arc_vertices[j])

	return new_ring
	
	
func add_floor_extension_from_ring(
	current_top_ring: PackedInt32Array,
	extra_rows: int,
	row_spacing: float,
	top_y: float,
	rng: RandomNumberGenerator,
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	centroid: Vector2,
	forbidden_floor_vertices: Dictionary,
	padding_steps: int = 5,
	min_side_steps: int = 8,
	max_side_steps: int = 18,
	debug_ball_radius: float = 0.28,
	arc_vertex_spacing: float = 2.0,
	rough_points: int = 5,
	irregularity: float = 0.25,
	smooth_steps: int = 2,
	edge_noise_strength: float = 0.2,
	edge_noise_frequency: float = 0.12
) -> Dictionary:
	var final_row_y: float = top_y + row_spacing * float(extra_rows)

	var selection: Dictionary = _select_and_flatten_floor_vertex_span_avoiding(
		rng,
		vertices,
		current_top_ring,
		final_row_y,
		forbidden_floor_vertices,
		padding_steps,
		min_side_steps,
		max_side_steps
	)

	var selected_floor_vertices: PackedInt32Array = selection["selected"]
	var start_ring_i: int = selection["start_ring_i"]
	var end_ring_i: int = selection["end_ring_i"]

	if selected_floor_vertices.size() < 2:
		return {
			"created": false,
			"updated_ring": current_top_ring,
			"floor_y": final_row_y,
			"inner_boundary_vertices": PackedInt32Array(),
			"outer_boundary_vertices": PackedInt32Array()
		}

	var outer_arc_vertices: PackedInt32Array = _create_debug_full_circle_from_selected_span_diameter(
		vertices,
		selected_floor_vertices,
		centroid,
		final_row_y,
		arc_vertex_spacing,
		rough_points,
		irregularity,
		smooth_steps,
		edge_noise_strength,
		edge_noise_frequency
	)

	_create_floor_from_selected_span_and_outer_arc(
		vertices,
		indices,
		selected_floor_vertices,
		outer_arc_vertices,
		final_row_y
	)

	_debug_spawn_vertex_balls(vertices, selected_floor_vertices, debug_ball_radius)
	_debug_spawn_vertex_balls(vertices, outer_arc_vertices, debug_ball_radius * 1.25)

	var updated_ring: PackedInt32Array = _replace_ring_span_with_outer_arc(
		current_top_ring,
		start_ring_i,
		end_ring_i,
		outer_arc_vertices
	)

	_mark_vertices_and_padding_forbidden_on_ring(
		forbidden_floor_vertices,
		updated_ring,
		outer_arc_vertices,
		padding_steps
	)

	return {
		"created": true,
		"updated_ring": updated_ring,
		"floor_y": final_row_y,
		"inner_boundary_vertices": selected_floor_vertices,
		"outer_boundary_vertices": outer_arc_vertices,
		"start_ring_i": start_ring_i,
		"end_ring_i": end_ring_i
	}
	
	
func _add_wall_ring_above(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	previous_ring: PackedInt32Array,
	target_y: float,
	centroid: Vector2,
	noise_strength: float,
	max_horizontal_offset: float,
	max_vertical_offset: float
) -> PackedInt32Array:
	var new_ring := PackedInt32Array()
	var n := previous_ring.size()

	if n < 2:
		return new_ring

	for i in range(n):
		var old_vertex: Vector3 = vertices[previous_ring[i]]

		var base_pos := Vector3(
			old_vertex.x,
			target_y,
			old_vertex.z
		)

		var final_pos := _perturb_wall_vertex(
			base_pos,
			centroid,
			noise_strength,
			max_horizontal_offset,
			max_vertical_offset,
			target_y,
			target_y
		)

		var new_index := vertices.size()
		vertices.append(final_pos)
		new_ring.append(new_index)

	for i in range(n):
		var a0: int = previous_ring[i]
		var a1: int = previous_ring[(i + 1) % n]
		var b0: int = new_ring[i]
		var b1: int = new_ring[(i + 1) % n]

		indices.append_array([a0, b0, a1])
		indices.append_array([a1, b0, b1])

	return new_ring

func _duplicate_curve_for_floor(
	vertices: PackedVector3Array,
	curve: PackedInt32Array,
	floor_y: float
) -> PackedInt32Array:
	var result := PackedInt32Array()

	for old_idx in curve:
		var p: Vector3 = vertices[old_idx]
		p.y = floor_y

		var new_idx := vertices.size()
		vertices.append(p)
		result.append(new_idx)

	return result


func _select_and_flatten_floor_vertex_span_avoiding(
	rng: RandomNumberGenerator,
	vertices: PackedVector3Array,
	ring: PackedInt32Array,
	row_y: float,
	forbidden_vertices: Dictionary,
	padding_steps: int = 5,
	min_side_steps: int = 8,
	max_side_steps: int = 18
) -> Dictionary:
	var empty_selected := PackedInt32Array()

	var ring_size := ring.size()
	if ring_size < 6:
		return {
			"selected": empty_selected,
			"start_ring_i": -1,
			"end_ring_i": -1
		}

	var max_allowed_side_steps := maxi(
		1,
		int((ring_size - 1) / 2) - padding_steps - 1
	)

	min_side_steps = clamp(min_side_steps, 1, max_allowed_side_steps)
	max_side_steps = clamp(max_side_steps, min_side_steps, max_allowed_side_steps)

	var candidates: Array[Dictionary] = []

	for center_ring_i in range(ring_size):
		for side_steps in range(min_side_steps, max_side_steps + 1):
			if _is_padded_span_free(
				ring,
				center_ring_i,
				side_steps,
				padding_steps,
				forbidden_vertices
			):
				candidates.append({
					"center_ring_i": center_ring_i,
					"side_steps": side_steps
				})

	if candidates.is_empty():
		return {
			"selected": empty_selected,
			"start_ring_i": -1,
			"end_ring_i": -1
		}

	var chosen: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]

	var center_ring_i: int = chosen["center_ring_i"]
	var side_steps: int = chosen["side_steps"]

	var start_ring_i := (center_ring_i - side_steps + ring_size) % ring_size
	var end_ring_i := (center_ring_i + side_steps) % ring_size

	var selected := PackedInt32Array()
	var ring_i := start_ring_i

	while true:
		var vertex_index: int = ring[ring_i]

		var p: Vector3 = vertices[vertex_index]
		p.y = row_y
		vertices[vertex_index] = p

		selected.append(vertex_index)

		if ring_i == end_ring_i:
			break

		ring_i = (ring_i + 1) % ring_size

	return {
		"selected": selected,
		"start_ring_i": start_ring_i,
		"end_ring_i": end_ring_i
	}
	
func _is_padded_span_free(
	ring: PackedInt32Array,
	center_ring_i: int,
	side_steps: int,
	padding_steps: int,
	forbidden_vertices: Dictionary
) -> bool:
	var ring_size := ring.size()

	var total_steps := side_steps * 2 + padding_steps * 2 + 1
	if total_steps >= ring_size:
		return false

	var start_i := center_ring_i - side_steps - padding_steps
	var end_i := center_ring_i + side_steps + padding_steps

	for raw_i in range(start_i, end_i + 1):
		var ring_i := posmod(raw_i, ring_size)
		var vertex_index: int = ring[ring_i]

		if forbidden_vertices.has(vertex_index):
			return false

	return true
	
	
func _mark_vertices_and_padding_forbidden_on_ring(
	forbidden_vertices: Dictionary,
	ring: PackedInt32Array,
	vertices_to_mark: PackedInt32Array,
	padding_steps: int = 5
) -> void:
	var ring_size := ring.size()
	if ring_size == 0:
		return

	for vertex_index in vertices_to_mark:
		var ring_i := _find_vertex_index_in_ring(ring, vertex_index)
		if ring_i == -1:
			continue

		for offset in range(-padding_steps, padding_steps + 1):
			var padded_i := posmod(ring_i + offset, ring_size)
			var padded_vertex_index: int = ring[padded_i]
			forbidden_vertices[padded_vertex_index] = true
			
func _find_vertex_index_in_ring(
	ring: PackedInt32Array,
	vertex_index: int
) -> int:
	for i in range(ring.size()):
		if ring[i] == vertex_index:
			return i

	return -1

func create_walls(
	rng: RandomNumberGenerator,
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	current_top_ring: PackedInt32Array,
	centroid: Vector2,
	noise_strength: float,
	row_spacing: float,
	top_y: float,
	max_horizontal_offset: float,
	max_vertical_offset: float,
	rows_lower_N: int = 3,
	rows_upper_N: int = 8,
	add_floors: bool = false,
	expand_circumference: bool = false,
	contract_circumference: bool = false,
	parent_vertex_map: Dictionary = {},
	circumference_step: float = 0.15
) -> Dictionary:
	var created_areas: Array = []
	var next_area_id := 0

	var extra_rows := rng.randi_range(rows_lower_N, rows_upper_N)

	for extra_row in range(extra_rows):
		var row_number := extra_row + 1
		var target_y: float = top_y + row_spacing * float(row_number)

		current_top_ring = _add_wall_ring_above_tracking(
			vertices,
			indices,
			current_top_ring,
			target_y,
			centroid,
			noise_strength,
			max_horizontal_offset,
			max_vertical_offset,
			parent_vertex_map,
			expand_circumference,
			contract_circumference,
			circumference_step
		)

		if add_floors:
			var extra_floors := rng.randi_range(1, 5)
			var forbidden_floor_vertices := {}

			for extra_floor in range(extra_floors):
				var floor_result: Dictionary = add_floor_extension_from_ring(
					current_top_ring,
					row_number,
					row_spacing,
					top_y,
					rng,
					vertices,
					indices,
					centroid,
					forbidden_floor_vertices,
					5
				)

				current_top_ring = floor_result["updated_ring"]

				if floor_result["created"]:
					var area: Dictionary = {
						"id": next_area_id,
						"row_number": row_number,
						"floor_y": floor_result["floor_y"],
						"inner_boundary_vertices": floor_result["inner_boundary_vertices"],
						"outer_boundary_vertices": floor_result["outer_boundary_vertices"],
						"links": []
					}

					_link_area_to_lower_areas(
						area,
						created_areas,
						parent_vertex_map
					)

					created_areas.append(area)
					next_area_id += 1

	return {
		"final_top_ring": current_top_ring,
		"extra_rows": extra_rows,
		"areas": created_areas,
		"parent_vertex_map": parent_vertex_map
	}
	
func _add_wall_ring_above_tracking(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	previous_ring: PackedInt32Array,
	target_y: float,
	centroid: Vector2,
	noise_strength: float,
	max_horizontal_offset: float,
	max_vertical_offset: float,
	parent_vertex_map: Dictionary,
	expand_circumference: bool = false,
	contract_circumference: bool = false,
	circumference_step: float = 0.15
) -> PackedInt32Array:
	var new_ring := PackedInt32Array()
	var n := previous_ring.size()

	if n < 2:
		return new_ring

	for i in range(n):
		var old_vertex: Vector3 = vertices[previous_ring[i]]

		var base_pos := Vector3(
			old_vertex.x,
			target_y,
			old_vertex.z
		)

		var circumference_amount := 0.0
		if expand_circumference:
			circumference_amount += circumference_step
		if contract_circumference:
			circumference_amount -= circumference_step

		if circumference_amount != 0.0:
			var local_normal := _get_local_ring_normal_xz(
				vertices,
				previous_ring,
				i,
				centroid,
				true
			)

			base_pos = _apply_local_ring_offset(
				base_pos,
				local_normal,
				circumference_amount
			)

		var final_pos := _perturb_wall_vertex(
			base_pos,
			centroid,
			noise_strength,
			max_horizontal_offset,
			max_vertical_offset,
			target_y,
			target_y
		)

		var new_index := vertices.size()
		vertices.append(final_pos)
		new_ring.append(new_index)

		parent_vertex_map[new_index] = previous_ring[i]

	for i in range(n):
		var a0: int = previous_ring[i]
		var a1: int = previous_ring[(i + 1) % n]
		var b0: int = new_ring[i]
		var b1: int = new_ring[(i + 1) % n]

		# Use this winding if this is the one that currently looks correct for you.
		indices.append_array([a0, b0, a1])
		indices.append_array([a1, b0, b1])

	return new_ring
	
func _link_area_to_lower_areas(
	new_area: Dictionary,
	existing_areas: Array,
	parent_vertex_map: Dictionary
) -> void:
	for lower_area in existing_areas:
		if int(lower_area["row_number"]) >= int(new_area["row_number"]):
			continue

		var shared: Dictionary = _find_projected_shared_vertices_between_areas(
			new_area,
			lower_area,
			parent_vertex_map
		)

		var upper_shared: PackedInt32Array = shared["upper_shared"]
		var lower_shared: PackedInt32Array = shared["lower_shared"]

		if upper_shared.size() == 0:
			continue

		var new_links: Array = new_area["links"]
		new_links.append({
			"area_id": lower_area["id"],
			"this_shared_vertices": upper_shared,
			"other_shared_vertices": lower_shared
		})
		new_area["links"] = new_links

		var lower_links: Array = lower_area["links"]
		lower_links.append({
			"area_id": new_area["id"],
			"this_shared_vertices": lower_shared,
			"other_shared_vertices": upper_shared
		})
		lower_area["links"] = lower_links
		

func _find_projected_shared_vertices_between_areas(
	upper_area: Dictionary,
	lower_area: Dictionary,
	parent_vertex_map: Dictionary
) -> Dictionary:
	var upper_shared := PackedInt32Array()
	var lower_shared := PackedInt32Array()

	var lower_outer_lookup := {}

	var lower_outer: PackedInt32Array = lower_area["outer_boundary_vertices"]
	for v in lower_outer:
		lower_outer_lookup[v] = true

	var upper_inner: PackedInt32Array = upper_area["inner_boundary_vertices"]

	for upper_v in upper_inner:
		var ancestor: int = _find_first_ancestor_in_lookup(
			upper_v,
			lower_outer_lookup,
			parent_vertex_map
		)

		if ancestor != -1:
			upper_shared.append(upper_v)
			lower_shared.append(ancestor)

	return {
		"upper_shared": upper_shared,
		"lower_shared": lower_shared
	}
	
func _find_first_ancestor_in_lookup(
	vertex_index: int,
	lookup: Dictionary,
	parent_vertex_map: Dictionary
) -> int:
	var current := vertex_index

	var safety := 0
	while safety < 512:
		if lookup.has(current):
			return current

		if not parent_vertex_map.has(current):
			return -1

		current = parent_vertex_map[current]
		safety += 1

	return -1


func build_wall_with_openings_from_ring(
	rng: RandomNumberGenerator,
	percent: float,
	base_ring: PackedVector3Array,
	base_ring_indices: PackedInt32Array,
	exit_count: int,
	exit_radius: float,
	center_height: float,
	start_y: float,
	top_y: float,
	row_spacing: float,
	max_horizontal_offset: float,
	max_vertical_offset: float,
	centroid: Vector2,
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	vertices_per_unit: float = 1.0,
	vertical_steps: int = 12,
	noise_strength: float = 0.35,
	expand_circumference: bool = false,
	contract_circumference: bool = false,
	circumference_step: float = 0.15
) -> Dictionary:
	if base_ring.size() < 3:
		push_error("base_ring needs at least 3 boundary points.")
		return {}

	if exit_count < 1:
		push_error("exit_count must be at least 1.")
		return {}

	var base_ring_2d := PackedVector2Array()
	for p in base_ring:
		base_ring_2d.append(Vector2(p.x, p.z))

	# StairRoomCavern-compatible profile values.
	var vertical_offset: float = -exit_radius * percent

	# These are now relative to start_y.
	var opening_top_y: float = center_height + exit_radius

	var path_info := _build_closed_path_info(base_ring_2d)
	var total_length: float = path_info["total_length"]

	var min_exit_separation: float = exit_radius * 2.0
	if float(exit_count) * min_exit_separation > total_length:
		push_error("Too many exits for the ring perimeter with the requested minimum separation.")
		return {}

	var exit_distances: Array = _generate_exit_distances(
		rng,
		total_length,
		exit_count,
		min_exit_separation
	)

	if exit_distances.size() != exit_count:
		push_error("Failed to place exits.")
		return {}


	var interval_rows: Array = []
	var top_interval_positions: Array = []

	for i in range(exit_count):
		var start_center_s: float = exit_distances[i]
		var end_center_s: float = exit_distances[(i + 1) % exit_count]
		if end_center_s <= start_center_s:
			end_center_s += total_length

		var rows_for_interval: Array = []

		for row in range(vertical_steps):
			var relative_y: float = opening_top_y * float(row) / float(vertical_steps)
			var y: float = start_y + relative_y

			var chord_width: float = _opening_chord_width_at_y(
				relative_y,
				exit_radius,
				center_height
			)

			var row_positions: Array = _build_interval_row_positions_3d(
				path_info,
				start_center_s,
				end_center_s,
				y,
				chord_width,
				vertices_per_unit
			)
			
			var circumference_amount := 0.0
			if expand_circumference:
				circumference_amount += circumference_step * float(row)
			if contract_circumference:
				circumference_amount -= circumference_step * float(row)

			if row != 0:
				row_positions = _apply_local_offset_to_position_row(
					row_positions,
					centroid,
					circumference_amount
				)

			var row_indices := PackedInt32Array()

			if row == 0:
				row_indices = _sample_existing_ring_indices_for_interval(
					path_info,
					base_ring_indices,
					start_center_s,
					end_center_s,
					chord_width,
					vertices_per_unit
				)
			else:
				for base_pos in row_positions:
					var final_pos: Vector3 = _perturb_wall_vertex(
						base_pos,
						centroid,
						noise_strength,
						max_horizontal_offset,
						max_vertical_offset,
						y,
						top_y
					)

					row_indices.append(vertices.size())
					vertices.append(final_pos)

			rows_for_interval.append(row_indices)

		var top_positions: Array = _build_interval_row_positions_3d(
			path_info,
			start_center_s,
			end_center_s,
			top_y,
			0.0,
			vertices_per_unit
		)
		
		var top_circumference_amount := 0.0
		if expand_circumference:
			top_circumference_amount += circumference_step * float(vertical_steps)
		if contract_circumference:
			top_circumference_amount -= circumference_step * float(vertical_steps)

		top_positions = _apply_local_offset_to_position_row(
			top_positions,
			centroid,
			top_circumference_amount
		)

		top_interval_positions.append(top_positions)
		interval_rows.append(rows_for_interval)

	var top_interval_rows: Array = []
	var continuous_top_row := PackedInt32Array()

	for i in range(exit_count):
		var positions: Array = top_interval_positions[i]
		var row_indices := PackedInt32Array()

		for j in range(positions.size()):
			var reuse_existing := false
			var reused_index := -1

			if i > 0 and j == 0:
				reuse_existing = true
				var prev_row: PackedInt32Array = top_interval_rows[i - 1]
				reused_index = prev_row[prev_row.size() - 1]

			elif i == exit_count - 1 and j == positions.size() - 1:
				reuse_existing = true
				reused_index = top_interval_rows[0][0]

			if reuse_existing:
				row_indices.append(reused_index)
			else:
				var base_pos: Vector3 = positions[j]

				var final_pos: Vector3 = _perturb_wall_vertex(
					base_pos,
					centroid,
					noise_strength,
					max_horizontal_offset,
					max_vertical_offset,
					top_y,
					top_y
				)

				var new_index := vertices.size()
				vertices.append(final_pos)
				row_indices.append(new_index)
				continuous_top_row.append(new_index)

		top_interval_rows.append(row_indices)

	for i in range(exit_count):
		var rows_for_interval: Array = interval_rows[i]

		for row in range(rows_for_interval.size() - 1):
			var row_a: PackedInt32Array = rows_for_interval[row]
			var row_b: PackedInt32Array = rows_for_interval[row + 1]
			_stitch_rows(indices, row_a, row_b)

		var last_row: PackedInt32Array = rows_for_interval[rows_for_interval.size() - 1]
		var top_row_slice: PackedInt32Array = top_interval_rows[i]
		_stitch_rows(indices, last_row, top_row_slice)

	var current_top_rows: Array = top_interval_rows
	var current_top_ring: PackedInt32Array = _make_continuous_ring_from_interval_rows(current_top_rows)

	var exit_positions: Array = []
	var exit_outward_dirs: Array = []

	for s in exit_distances:
		var p2: Vector2 = _sample_closed_path_2d(
			path_info["points"],
			path_info["cumulative_lengths"],
			total_length,
			s
		)

		exit_positions.append(Vector3(p2.x, start_y + center_height, p2.y))

		var dir2: Vector2 = (p2 - centroid).normalized()
		exit_outward_dirs.append(Vector3(dir2.x, 0.0, dir2.y))

	return {
		"interval_rows": interval_rows,
		"top_interval_rows": top_interval_rows,
		"current_top_rows": current_top_rows,
		"current_top_ring": current_top_ring,
		"continuous_top_row": continuous_top_row,
		"exit_distances": exit_distances,
		"exit_positions": exit_positions,
		"exit_outward_dirs": exit_outward_dirs,
		"centroid": centroid,
		"center_height": center_height,
		"start_y": start_y,
		"top_y": top_y,
		"opening_top_y": opening_top_y,
		"row_spacing": row_spacing,
		"max_horizontal_offset": max_horizontal_offset,
		"max_vertical_offset": max_vertical_offset,
		"path_info": path_info,
		"total_length": total_length
	}
	
func _sample_existing_ring_indices_for_interval(
	path_info: Dictionary,
	base_ring_indices: PackedInt32Array,
	start_center_s: float,
	end_center_s: float,
	chord_width: float,
	vertices_per_unit: float
) -> PackedInt32Array:
	var result := PackedInt32Array()

	var total_length: float = path_info["total_length"]

	var start_s: float = start_center_s + chord_width * 0.5
	var end_s: float = end_center_s - chord_width * 0.5
	var span_length: float = end_s - start_s

	var segment_count: int = max(1, int(round(span_length * vertices_per_unit)))

	var ring_size := base_ring_indices.size()
	if ring_size == 0:
		return result

	for i in range(segment_count + 1):
		var t: float = float(i) / float(segment_count)
		var s: float = lerp(start_s, end_s, t)

		var ring_i := _sample_ring_index_from_path_distance(
			path_info,
			s
		)

		result.append(base_ring_indices[ring_i])

	return _remove_consecutive_duplicate_indices(result)
	
	
func _sample_ring_index_from_path_distance(
	path_info: Dictionary,
	distance_along_path: float
) -> int:
	var total_length: float = path_info["total_length"]
	var cumulative_lengths: Array = path_info["cumulative_lengths"]

	var s: float = fposmod(distance_along_path, total_length)
	var n := cumulative_lengths.size() - 1

	for i in range(n):
		var l0: float = cumulative_lengths[i]
		var l1: float = cumulative_lengths[i + 1]

		if s <= l1 or i == n - 1:
			var seg_length: float = l1 - l0

			if seg_length <= 0.00001:
				return i

			var t := (s - l0) / seg_length

			if t < 0.5:
				return i
			else:
				return (i + 1) % n

	return 0

func _remove_consecutive_duplicate_indices(
	source: PackedInt32Array
) -> PackedInt32Array:
	var result := PackedInt32Array()

	for idx in source:
		if result.is_empty() or result[result.size() - 1] != idx:
			result.append(idx)

	if result.size() > 1 and result[0] == result[result.size() - 1]:
		result.remove_at(result.size() - 1)

	return result


func _run_opening_wall_layer(
	rng: RandomNumberGenerator,
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	current_top_ring: PackedInt32Array,
	current_top_y: float,
	percent: float,
	exit_count: int,
	exit_radius: float,
	center_height: float,
	opening_top_y: float,
	row_spacing: float,
	max_horizontal_offset: float,
	max_vertical_offset: float,
	centroid: Vector2,
	vertices_per_unit: float,
	vertical_steps: int,
	noise_strength: float,
	expand_circumference: bool = false,
	contract_circumference: bool = false,
	circumference_step: float = 0.05
) -> Dictionary:
	var base_ring: PackedVector3Array = _ring_indices_to_positions(
		vertices,
		current_top_ring
	)

	var next_top_y: float = current_top_y + opening_top_y

	var wall_data := build_wall_with_openings_from_ring(
		rng,
		percent,
		base_ring,
		current_top_ring,
		exit_count,
		exit_radius,
		center_height,
		current_top_y,
		next_top_y,
		row_spacing,
		max_horizontal_offset,
		max_vertical_offset,
		centroid,
		vertices,
		indices,
		vertices_per_unit,
		vertical_steps,
		noise_strength,
		expand_circumference,
	contract_circumference,
	circumference_step
	)

	return {
		"current_top_ring": wall_data["current_top_ring"],
		"current_top_y": next_top_y,
		"exit_distances": wall_data["exit_distances"],
		"exit_positions": wall_data["exit_positions"],
		"exit_outward_dirs": wall_data["exit_outward_dirs"],
		"continuous_top_row": wall_data["continuous_top_row"]
	}
	
func _ring_indices_to_positions(
	vertices: PackedVector3Array,
	ring: PackedInt32Array
) -> PackedVector3Array:
	var result := PackedVector3Array()

	for idx in ring:
		result.append(vertices[idx])

	return result
	

func _run_extra_wall_layer(
	rng: RandomNumberGenerator,
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	current_top_ring: PackedInt32Array,
	current_top_y: float,
	centroid: Vector2,
	noise_strength: float,
	row_spacing: float,
	max_horizontal_offset: float,
	max_vertical_offset: float,
	rows_lower_N: int,
	rows_upper_N: int,
	add_floors: bool,
	parent_vertex_map: Dictionary,
	expand_circumference: bool = false,
	contract_circumference: bool = false,
	circumference_step: float = 0.15
) -> Dictionary:
	var wall_result: Dictionary = create_walls(
		rng,
		vertices,
		indices,
		current_top_ring,
		centroid,
		noise_strength,
		row_spacing,
		current_top_y,
		max_horizontal_offset,
		max_vertical_offset,
		rows_lower_N,
		rows_upper_N,
		add_floors,
		expand_circumference,
		contract_circumference,
		parent_vertex_map,
		circumference_step
	)

	var extra_rows: int = wall_result["extra_rows"]
	var new_top_y: float = current_top_y + row_spacing * float(extra_rows)

	return {
		"current_top_ring": wall_result["final_top_ring"],
		"current_top_y": new_top_y,
		"areas": wall_result["areas"],
		"parent_vertex_map": wall_result["parent_vertex_map"],
		"extra_rows": extra_rows
	}

func _get_local_ring_normal_xz(
	vertices: PackedVector3Array,
	ring: PackedInt32Array,
	ring_i: int,
	centroid: Vector2,
	prefer_outward_from_centroid: bool = true
) -> Vector3:
	var n := ring.size()
	if n < 3:
		return Vector3.ZERO

	var prev_i := posmod(ring_i - 1, n)
	var next_i := posmod(ring_i + 1, n)

	var a: Vector3 = vertices[ring[prev_i]]
	var b: Vector3 = vertices[ring[next_i]]
	var p: Vector3 = vertices[ring[ring_i]]

	var tangent := b - a
	tangent.y = 0.0

	if tangent.length_squared() < 0.000001:
		return Vector3.ZERO

	tangent = tangent.normalized()

	# One of the two perpendicular directions in XZ.
	var normal := Vector3(-tangent.z, 0.0, tangent.x).normalized()

	# Make it consistently outward relative to centroid.
	var from_center := Vector3(
		p.x - centroid.x,
		0.0,
		p.z - centroid.y
	)

	if from_center.length_squared() > 0.000001:
		var points_outward := normal.dot(from_center) > 0.0

		if prefer_outward_from_centroid and not points_outward:
			normal = -normal
		elif not prefer_outward_from_centroid and points_outward:
			normal = -normal

	return normal
	
	
func _apply_local_ring_offset(
	pos: Vector3,
	normal: Vector3,
	amount: float
) -> Vector3:
	return pos + normal * amount
	

func _apply_local_offset_to_position_row(
	row_positions: Array,
	centroid: Vector2,
	amount: float
) -> Array:
	if amount == 0.0:
		return row_positions

	var result: Array = []
	var n := row_positions.size()

	if n < 2:
		return row_positions

	for i in range(n):
		var prev_i := maxi(i - 1, 0)
		var next_i := mini(i + 1, n - 1)

		if i == 0:
			prev_i = 0
			next_i = 1
		elif i == n - 1:
			prev_i = n - 2
			next_i = n - 1

		var a: Vector3 = row_positions[prev_i]
		var b: Vector3 = row_positions[next_i]
		var p: Vector3 = row_positions[i]

		var tangent := b - a
		tangent.y = 0.0

		if tangent.length_squared() < 0.000001:
			result.append(p)
			continue

		tangent = tangent.normalized()

		var normal := Vector3(-tangent.z, 0.0, tangent.x).normalized()

		var from_center := Vector3(
			p.x - centroid.x,
			0.0,
			p.z - centroid.y
		)

		if from_center.length_squared() > 0.000001:
			if normal.dot(from_center) < 0.0:
				normal = -normal

		result.append(p + normal * amount)

	return result
