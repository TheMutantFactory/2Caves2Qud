# A race track built from shared/tracks.json: a Catmull-Rom loop through the
# control points, a road ribbon and curbs draped over rolling terrain, a
# textured ground plane, scenery, and the waypoint queries the karts use.
#
# World px (the shared contract's unit) map to metres by U. px x -> X, px y -> Z.
class_name Track
extends Node3D

const U := 0.05  # metres per world px
const TILE_PX := 60.0
const WALL_PX := 60.0   # one voxel wall block (16 voxels) spans this many world px

var key: String
var spec: Dictionary
var track_name: String
var scale_k: float
var width: float
var size: Vector2
var points := PackedVector2Array()
var n := 0
var seg_len := PackedFloat32Array()
var noise := FastNoiseLite.new()
var elev_amp := 0.0
var city: CityMap = null
var route := {}
var barricade_nodes: Array = []
var barricade_walls: Array = []   # [a: Vector2, b: Vector2] segments across sealed side streets
var free_mode := false
# Parallel routes (spec "branches"): a second road that leaves the loop at one fraction and
# rejoins at another. {name, kind (safe|expert), pts, from_i, to_i, width, ai_take, hazards}
var branches: Array = []
# Section races (spec "sections" > 0): the road is OPEN — one way from the grid to a finish
# at the far end, no laps; the course develops by section instead of by lap.
var open := false
var sections := 0
var start_i := 0                 # the loop index the grid stands on (after the lead-in)


func setup(k: String, rng: RandomNumberGenerator) -> void:
	key = k
	spec = Shared.tracks[k]
	track_name = spec["name"]
	if spec.has("city"):
		setup_city(rng)
		return
	_build_loop(rng)


# A track from one of the game's realm dumps: the realm's tileset on the road, its chasm
# as the ground, its walls as scenery, a seeded loop. Simple for now (docs/campaign.md).
func setup_level(level: Dictionary, rng: RandomNumberGenerator) -> void:
	key = "realm"
	var ts := String(level.get("tileset", "stone"))
	var ch := String(level.get("chasm", "water"))
	var diff := int(level.get("difficulty", 1))
	var lists: Dictionary = Shared.tuning.get("realm_spells", {})
	var spells: Array = lists.get(ts, lists.get("default", []))
	spec = {"key": "realm", "name": "Realm %d   %s over %s" % [diff, ts.capitalize(), ch],
		"walls": ["tiles", "tilesets", ts, ts + " wall"], "width": 230, "size": [3600, 2400],
		"ground": [0, 0, 0], "road_color": [80, 76, 70], "spells": spells, "tileset": ts, "chasm": ch,
		"road_tex": "tiles/floor_%s.png" % ts, "ground_tex": "tiles/chasm_%s.png" % ch, "control": []}
	track_name = spec["name"]
	var lrng := RandomNumberGenerator.new()
	lrng.seed = int(level.get("seed", 0)) * 7919 + diff
	var n_ctrl := lrng.randi_range(8, 11)
	var center := Vector2(1800, 1200)
	for i in n_ctrl:
		var ang := TAU * i / n_ctrl + lrng.randf_range(-0.12, 0.12)
		var rx := 1500.0 * lrng.randf_range(0.55, 0.95)
		var ry := 950.0 * lrng.randf_range(0.55, 0.95)
		spec["control"].append([center.x + cos(ang) * rx, center.y + sin(ang) * ry])
	_build_loop(rng)


func _build_loop(rng: RandomNumberGenerator) -> void:
	scale_k = float(Shared.t(["race", "track_scale"], 2.0))
	width = float(spec["width"]) * (1.0 + (scale_k - 1.0) * 0.35)
	size = Vector2(spec["size"][0], spec["size"][1]) * scale_k
	var control: Array = []
	for c in spec["control"]:
		control.append(Vector2(c[0], c[1]) * scale_k)
	var spacing := float(Shared.t(["race", "waypoint_spacing"], 90.0))
	# waypoints per control segment: dense enough that a kart cutting a corner still passes
	# within width x 0.7 of the next one (Track.advance), so a stretched loop gets more
	var samples := maxi(4, int(round(8.0 * scale_k * float(spec.get("stretch", 1.0)) * 90.0 / spacing)))
	sections = int(spec.get("sections", 0))
	open = sections > 0
	if open:
		# a lead-in behind the first point so the grid stands on road, then the one-way path
		var d0: Vector2 = (control[1] - control[0]).normalized()
		control.insert(0, control[0] - d0 * 500.0 * scale_k)
		points = catmull_rom_open(control, samples)
		start_i = samples
	else:
		points = catmull_rom(control, samples)
		start_i = 0
	n = points.size()
	seg_len.resize(n)
	for i in n:
		seg_len[i] = maxf(1.0, points[(i + 1) % n].distance_to(points[i])) if (not open or i < n - 1) else 1.0

	elev_amp = float(spec.get("elevation", Shared.t(["godot", "elevation_px"], 60.0)))
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = float(Shared.t(["godot", "elevation_freq"], 0.0006))
	_build_profile()
	_build_camber()
	if camber_px > 0.0:
		var mx := 0.0
		for b in bank:
			mx = maxf(mx, absf(b))
		print("camber: %s %d px, steepest bank %d px" % [key, int(camber_px), int(mx)])
	if not hgrid.is_empty():
		var lo := INF
		var hi := -INF
		for h in profile_h:
			lo = minf(lo, h)
			hi = maxf(hi, h)
		print("elevation: %s authored %d..%d px over the route, %d steps" % [key, int(lo), int(hi), steps.size()])

	_build_ground()
	_build_road()
	_build_branches()
	_build_mover_marks()
	_build_start_line()
	_build_scenery(rng)
	_build_cut_walls()
	_build_psychic(rng)
	_build_struts()


# ---------------------------------------------------------------- city

func setup_city(rng: RandomNumberGenerator) -> void:
	city = CityMap.load(String(spec["city"]))
	if city == null:
		push_error("Track: city map missing; falling back to the control points")
		spec = Shared.tracks["brick"]
		setup("brick", rng)
		return
	scale_k = 1.0
	size = city.size
	elev_amp = 0.0
	var ppm := city.px_per_m
	var lens: Array = spec.get("route_len_m", [1600, 2600])
	route = city.random_route(rng, float(lens[0]) * ppm, float(lens[1]) * ppm)
	if route.is_empty():
		push_error("Track: no closed route found in %s" % city.key)
		spec = Shared.tracks["brick"]
		setup("brick", rng)
		return
	width = minf(float(route["width"]), float(spec.get("width", 160)) * 1.0)
	var spacing := float(Shared.t(["race", "waypoint_spacing"], 90.0))
	points = _rotate_to_straight(CityMap.smooth_loop(route["points"], width, spacing * 0.7))
	n = points.size()
	seg_len.resize(n)
	for i in n:
		seg_len[i] = maxf(1.0, points[(i + 1) % n].distance_to(points[i]))
	track_name = "%s: %s" % [city.display_name, _route_label()]

	_build_flat_ground()
	_build_city_streets()
	_build_road()
	_build_start_line()
	_build_buildings()
	_build_barricades()


# Start the loop in the middle of its longest straight stretch, so the start
# grid and the chase camera behind it sit on the street rather than in a block.
static func _rotate_to_straight(pts: PackedVector2Array) -> PackedVector2Array:
	var m := pts.size()
	if m < 8:
		return pts
	var straight := PackedInt32Array()
	straight.resize(m)
	for i in m:
		var d0 := (pts[i] - pts[(i - 1 + m) % m]).normalized()
		var d1 := (pts[(i + 1) % m] - pts[i]).normalized()
		straight[i] = 1 if absf(d0.angle_to(d1)) < deg_to_rad(4.0) else 0
	var best_i := 0
	var best_len := -1
	var i := 0
	while i < m:
		if straight[i] == 0:
			i += 1
			continue
		var j := i
		while j < m and straight[j] == 1:
			j += 1
		if j - i > best_len:
			best_len = j - i
			best_i = (i + j) / 2
		i = j
	var out := PackedVector2Array()
	for k in m:
		out.append(pts[(best_i + k) % m])
	return out


# The whole city with no route: ground, every street, the buildings. For survivors.
func setup_city_open(city_key: String, rng: RandomNumberGenerator) -> void:
	key = "chicago_loop" if not Shared.tracks.has(city_key) else city_key
	spec = Shared.tracks[key]
	track_name = spec["name"]
	city = CityMap.load(String(spec.get("city", city_key)))
	if city == null:
		push_error("Track: city map missing")
		return
	scale_k = 1.0
	size = city.size
	elev_amp = 0.0
	width = float(spec.get("width", 480))
	points = PackedVector2Array()
	n = 0
	free_mode = true
	_build_flat_ground()
	_build_city_streets()
	_build_buildings(float(Shared.t(["survivors", "max_building_px"], 0.0)))


# Nothing but a size: the Arena draws the world (Survivors realm arenas).
func setup_void(px: Vector2) -> void:
	key = "void"
	spec = {"key": "void", "name": "", "width": 0}
	track_name = ""
	city = null
	scale_k = 1.0
	size = px
	elev_amp = 0.0
	width = 0.0
	points = PackedVector2Array()
	n = 0
	free_mode = true


# An open field: one flat plane, no route, no city, nothing to hit (Survivors arena).
func setup_plain(rng: RandomNumberGenerator) -> void:
	key = "plain"
	var floor_name := String(Shared.t(["survivors", "arena_floor"], "moss"))
	var px := float(Shared.t(["survivors", "arena_px"], 9000.0))
	spec = {"key": "plain", "name": "The Open Field", "width": 0, "ground_tex": "tiles/floor_%s.png" % floor_name, "walls": ["tiles", "tilesets", floor_name, floor_name + " wall"]}
	track_name = spec["name"]
	city = null
	scale_k = 1.0
	size = Vector2(px, px)
	elev_amp = 0.0
	width = 0.0
	points = PackedVector2Array()
	n = 0
	free_mode = true
	_build_flat_ground()


func _route_label() -> String:
	var names := []
	for si in route["streets"]:
		var nm: String = city.streets[si]["name"]
		if nm != "" and not (nm in names):
			names.append(nm)
		if names.size() >= 4:
			break
	return " / ".join(names) if names.size() > 0 else "unnamed loop"


func _build_flat_ground() -> void:
	var margin := 600.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector2(-margin, -margin)
	var b := Vector2(size.x + margin, -margin)
	var c := Vector2(size.x + margin, size.y + margin)
	var d := Vector2(-margin, size.y + margin)
	for tri in [[a, b, c], [a, c, d]]:
		for p in tri:
			st.set_uv(p / TILE_PX)
			st.add_vertex(Vector3(p.x * U, 0.0, p.y * U))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material(QUD.texture(String(spec.get("ground_tex", "tiles/track_%s_ground.png" % key))))
	mi.name = "Ground"
	add_child(mi)


# Every street in the map as a flat ribbon, so the whole grid is drivable in free mode.
func _build_city_streets() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lift := 1.0 * U
	for street in city.streets:
		var pts: PackedVector2Array = street["points"]
		var half: float = float(street["width"]) * 0.5
		var along := 0.0
		for i in range(pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			var d := (b - a)
			var seg := d.length()
			if seg < 1.0:
				continue
			d /= seg
			var nrm := Vector2(-d.y, d.x) * half
			var v0 := along / TILE_PX
			var v1 := (along + seg) / TILE_PX
			var al := Vector3((a - nrm).x * U, lift, (a - nrm).y * U)
			var ar := Vector3((a + nrm).x * U, lift, (a + nrm).y * U)
			var bl := Vector3((b - nrm).x * U, lift, (b - nrm).y * U)
			var br := Vector3((b + nrm).x * U, lift, (b + nrm).y * U)
			st.set_uv(Vector2(0, v0)); st.add_vertex(al)
			st.set_uv(Vector2(1, v1)); st.add_vertex(br)
			st.set_uv(Vector2(1, v0)); st.add_vertex(ar)
			st.set_uv(Vector2(0, v0)); st.add_vertex(al)
			st.set_uv(Vector2(0, v1)); st.add_vertex(bl)
			st.set_uv(Vector2(1, v1)); st.add_vertex(br)
			along += seg
		# round the junction with a disc so crossings don't show gaps
		for p in [pts[0], pts[pts.size() - 1]]:
			var c := Vector3(p.x * U, lift, p.y * U)
			for k in 12:
				var a0 := TAU * k / 12.0
				var a1 := TAU * (k + 1) / 12.0
				st.set_uv(Vector2(0.5, 0.5)); st.add_vertex(c)
				st.set_uv(Vector2(0.5, 0.5)); st.add_vertex(c + Vector3(cos(a1), 0, sin(a1)) * half * U)
				st.set_uv(Vector2(0.5, 0.5)); st.add_vertex(c + Vector3(cos(a0), 0, sin(a0)) * half * U)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material(QUD.texture("tiles/track_%s_road.png" % key), Color(0.75, 0.75, 0.78))
	mi.name = "Streets"
	add_child(mi)


func _build_buildings(max_px := 0.0) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for b in city.buildings:
		var pts: PackedVector2Array = b["points"]
		var h: float = (minf(float(b["height"]), max_px) if max_px > 0.0 else float(b["height"])) * U
		var shade := clampf(0.42 + h / 50.0, 0.42, 0.9)
		var col := Color(shade, shade * 0.96, shade * 1.05)
		var side := Color(shade * 0.85, shade * 0.82, shade * 0.9)
		var m := pts.size()
		# walls
		for i in m:
			var a := pts[i]
			var c := pts[(i + 1) % m]
			var a0 := Vector3(a.x * U, 0, a.y * U)
			var a1 := Vector3(a.x * U, h, a.y * U)
			var c0 := Vector3(c.x * U, 0, c.y * U)
			var c1 := Vector3(c.x * U, h, c.y * U)
			var v := (c - a).length() * U / 3.0
			var u := h / 3.0
			st.set_color(side)
			st.set_uv(Vector2(0, 0)); st.add_vertex(a0)
			st.set_uv(Vector2(v, u)); st.add_vertex(c1)
			st.set_uv(Vector2(v, 0)); st.add_vertex(c0)
			st.set_uv(Vector2(0, 0)); st.add_vertex(a0)
			st.set_uv(Vector2(0, u)); st.add_vertex(a1)
			st.set_uv(Vector2(v, u)); st.add_vertex(c1)
		# roof
		var tri := Geometry2D.triangulate_polygon(pts)
		if tri.is_empty():
			var rev := PackedVector2Array()
			for i in range(m - 1, -1, -1):
				rev.append(pts[i])
			tri = Geometry2D.triangulate_polygon(rev)
			pts = rev
		st.set_color(col)
		for i in range(0, tri.size() - 2, 3):
			for k in [tri[i], tri[i + 1], tri[i + 2]]:
				var p := pts[k]
				st.set_uv(p / TILE_PX)
				st.add_vertex(Vector3(p.x * U, h, p.y * U))
		count += 1
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mat.metallic_specular = 0.1
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.name = "Buildings"
	add_child(mi)


# Qud's wall family for this track's tileset (manifest "wall_families" from
# tools/export_godot_assets.py), when the store has its voxel model.
func _wall_family() -> String:
	var ts: String = spec["walls"][2] if spec.get("walls", []).size() > 2 else ""
	var fam := String(QUD.manifest.get("wall_families", {}).get(ts, ""))
	return fam if fam != "" and QudVox.available(fam) else ""


# One voxel wall block at a world-px position, its front face turned to `facing`
# (the direction a viewer stands in). Blocks are WALL_PX wide, the old sprite pitch.
var scenery_blocks: Array = []     # [{node, pos}] the wall blocks beside the road (a mover can cut them)


func _wall_block(fam: String, variant: String, p: Vector2, facing: Vector2, parent: Node) -> bool:
	var mi := QudVox.block(fam, variant, WALL_PX / 16.0, U)
	if mi == null:
		return false
	mi.position = to3(p)
	mi.rotation.y = atan2(facing.x, facing.y)
	parent.add_child(mi)
	scenery_blocks.append({"node": mi, "pos": p})
	return true


func _wall_sprites() -> Array:
	var walls: Array = []
	var ts: String = spec["walls"][2]
	for i in range(1, 5):
		var tex: Texture2D = QUD.texture("tiles/%s_wall_%d.png" % [ts, i])
		if tex:
			walls.append(tex)
	return walls


func _build_barricades() -> void:
	var fam := _wall_family()
	var walls: Array = [] if fam != "" else _wall_sprites()
	if fam == "" and walls.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "Barricades"
	add_child(holder)
	var blocks := 0
	for bar in city.barricades(route, width):
		var pos: Vector2 = bar["pos"]
		var dir: Vector2 = bar["dir"]
		var nrm := Vector2(-dir.y, dir.x)
		var w: float = bar["width"]
		barricade_walls.append([pos - nrm * (w * 0.5 + 20.0), pos + nrm * (w * 0.5 + 20.0)])
		var count := maxi(2, int(ceil(w / WALL_PX)))
		for k in count:
			var off := (k - (count - 1) * 0.5) * WALL_PX
			var p := pos + nrm * off
			if fam != "":
				# a run of blocks across the street, faces toward the route (the way the
				# kart comes), end pieces with their posts at both ends
				if _wall_block(fam, QudVox.run_variant(k, count, nrm, -dir), p, -dir, holder):
					blocks += 1
				continue
			var s := Sprite3D.new()
			s.texture = walls[k % walls.size()]
			s.pixel_size = U
			s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			s.position = Vector3(p.x * U, 30.0 * U, p.y * U)
			holder.add_child(s)
	if fam != "":
		print("walls: %d voxel barricade blocks (%s)" % [blocks, fam])
	barricade_nodes = [holder]


# Push a kart out of buildings and, in race mode, off the barricades.
# Returns {hit, pos, normal}.
func resolve(p: Vector2, radius: float) -> Dictionary:
	if city == null:
		return {"hit": false, "pos": p, "normal": Vector2.ZERO}
	var r := city.collide_buildings(p, radius)
	if r["hit"]:
		return r
	if not free_mode:
		for wall in barricade_walls:
			var a: Vector2 = wall[0]
			var b: Vector2 = wall[1]
			if p.distance_squared_to((a + b) * 0.5) > (radius + 800.0) * (radius + 800.0):
				continue
			var q := Geometry2D.get_closest_point_to_segment(p, a, b)
			var d := p.distance_to(q)
			if d < radius + 8.0:
				var n := (p - q).normalized() if d > 0.001 else Vector2(-(b - a).y, (b - a).x).normalized()
				return {"hit": true, "pos": q + n * (radius + 8.5), "normal": n}
	return {"hit": false, "pos": p, "normal": Vector2.ZERO}


func set_free_mode(on: bool) -> void:
	free_mode = on
	for h in barricade_nodes:
		h.visible = not on


func street_name_at(p: Vector2) -> String:
	if city == null:
		return ""
	var n := city.nearest_street(p)
	return String(n["name"]) if float(n["dist"]) <= float(n["width"]) * 0.6 else ""


# ---------------------------------------------------------------- geometry

static func catmull_rom(pts: Array, samples: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var m := pts.size()
	for i in m:
		var p0: Vector2 = pts[(i - 1 + m) % m]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[(i + 1) % m]
		var p3: Vector2 = pts[(i + 2) % m]
		for s in samples:
			var t := float(s) / samples
			var t2 := t * t
			var t3 := t2 * t
			var p := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
			out.append(p)
	return out


# Authored elevation (spec "profile": [[at, height_px], ...] along the route): the road
# rises and falls by the profile, and the ground around it follows within a few road widths
# (a shelf), fading to the terrain noise in the far field. Sampled from a grid built once.
var profile_h := PackedFloat32Array()     # per route point
var steps: Array = []                     # route indices where the road drops (or rises) a ledge
var hgrid := PackedFloat32Array()
var hg_cols := 0
var hg_rows := 0
var hg_origin := Vector2.ZERO
const HG_CELL := 160.0
const HG_MARGIN := 900.0


func _build_profile() -> void:
	profile_h.resize(n)
	hgrid.resize(0)
	var prof: Array = spec.get("profile", [])
	if prof.size() < 2 or n == 0:
		for i in n:
			profile_h[i] = 0.0
		return
	# smooth interpolation between the keypoints (cosine), wrapping on a loop
	var keys := []
	steps.clear()
	for k in prof:
		var at := clampf(float(k[0]), 0.0, 1.0)
		if k.size() > 2 and String(k[2]) == "step":
			# a ledge: the height jumps at `at`; the previous keypoint's height holds until then
			var prev_h: float = keys[keys.size() - 1].y if keys.size() > 0 else 0.0
			keys.append(Vector2(at - 0.0001, prev_h))
			steps.append(int(ceil(at * n)))      # the first sample whose f >= at takes the new height
		keys.append(Vector2(at, float(k[1]) * scale_k))
	keys.sort_custom(func(a, b): return a.x < b.x)
	for i in n:
		var f := float(i) / n
		var a: Vector2 = keys[0]
		var b: Vector2 = keys[keys.size() - 1]
		for j in range(keys.size() - 1):
			if f >= keys[j].x and f <= keys[j + 1].x:
				a = keys[j]
				b = keys[j + 1]
				break
		if f < keys[0].x:
			a = Vector2(keys[keys.size() - 1].x - 1.0, keys[keys.size() - 1].y) if not open else Vector2(0.0, keys[0].y)
			b = keys[0]
		elif f > keys[keys.size() - 1].x:
			a = keys[keys.size() - 1]
			b = Vector2(keys[0].x + 1.0, keys[0].y) if not open else Vector2(1.0, keys[keys.size() - 1].y)
		var span := maxf(0.0001, b.x - a.x)
		var u := clampf((f - a.x) / span, 0.0, 1.0)
		profile_h[i] = lerpf(a.y, b.y, 0.5 - 0.5 * cos(u * PI))
	# the shelf grid: each cell takes the nearest route point's height, faded by distance
	hg_origin = Vector2(-HG_MARGIN, -HG_MARGIN)
	hg_cols = int(ceil((size.x + 2.0 * HG_MARGIN) / HG_CELL)) + 1
	hg_rows = int(ceil((size.y + 2.0 * HG_MARGIN) / HG_CELL)) + 1
	hgrid.resize(hg_cols * hg_rows)
	var stride := maxi(1, n / 120)
	var full := width * 1.5
	var fade := width * 4.0
	for r in hg_rows:
		for c in hg_cols:
			var p := hg_origin + Vector2(c, r) * HG_CELL
			var best := INF
			var best_i := 0
			for i in range(0, n, stride):
				var d := p.distance_squared_to(points[i])
				if d < best:
					best = d
					best_i = i
			var dist := sqrt(best)
			var w := 1.0 if dist <= full else clampf(1.0 - (dist - full) / (fade - full), 0.0, 1.0)
			hgrid[r * hg_cols + c] = profile_h[best_i] * (0.5 - 0.5 * cos(w * PI))


# Camber (spec "camber", px across the road): corners bank, the outside edge raised by the
# course's camber scaled by the local curvature. The leaning tree (spec "lean": {"2": [dx, dy]}):
# the whole course tilts by lap, animated over a few seconds so the sway is the preview.
var camber_px := 0.0
var bank := PackedFloat32Array()       # per route point: signed bank height (px) at the road's edge
var lean := Vector2.ZERO               # height per px of position, about the map centre
var lean_target := Vector2.ZERO
var leaning := false
const LEAN_SECONDS := 3.0
const CURVE_REF := 0.05                # rad per sample that counts as a full corner


func _build_camber() -> void:
	camber_px = float(spec.get("camber", 0.0)) * scale_k
	bank.resize(n)
	for i in n:
		bank[i] = 0.0
	if camber_px <= 0.0 or n < 8:
		return
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		var a := direction_at((i - 1 + n) % n if not open else maxi(0, i - 1))
		var b := direction_at((i + 1) % n if not open else mini(n - 1, i + 1))
		raw[i] = a.x * b.y - a.y * b.x         # + turns toward +normal (the right)
	for i in n:                                 # smooth over the corner
		var acc := 0.0
		var cnt := 0
		for k in range(-6, 7):
			var j := (i + k + n) % n if not open else clampi(i + k, 0, n - 1)
			acc += raw[j]
			cnt += 1
		bank[i] = camber_px * clampf((acc / cnt) / CURVE_REF, -1.0, 1.0)


# The route point nearest p and p's lateral offset from it (+ toward the normal).
func _route_lateral(p: Vector2) -> Dictionary:
	var best := INF
	var bi := 0
	var stride := 1 if not steps.is_empty() else 2
	for i in range(0, n, stride):
		var d := p.distance_squared_to(points[i])
		if d < best:
			best = d
			bi = i
	var dir := direction_at(bi)
	var nrm := Vector2(-dir.y, dir.x)
	# how far along the route past sample bi the point lies (-1..1 samples), for interpolation
	var along := (p - points[bi]).dot(dir) / maxf(1.0, seg_len[bi])
	return {"i": bi, "lateral": (p - points[bi]).dot(nrm), "dist": sqrt(best), "along": clampf(along, -1.0, 1.0)}


func camber_at(p: Vector2, rl: Dictionary = {}) -> float:
	if camber_px <= 0.0:
		return 0.0
	if rl.is_empty():
		rl = _route_lateral(p)
	var half := width * 0.5
	var lat: float = rl["lateral"]
	var fade := 1.0 if absf(lat) <= half + 14.0 else clampf(1.0 - (absf(lat) - half - 14.0) / half, 0.0, 1.0)
	# the bank between neighbouring samples, so it never steps under a moving kart
	var i: int = rl["i"]
	var along: float = rl.get("along", 0.0)
	var j := i + 1 if along >= 0.0 else i - 1
	j = clampi(j, 0, n - 1) if open else (j + n) % n
	var b := lerpf(bank[i], bank[j], absf(along))
	# a right turn (bank > 0) raises the LEFT edge (negative lateral)
	return -b * clampf(lat / half, -1.0, 1.0) * fade


# 0..1: how banked the road is under p (for the grip bonus).
func banking(p: Vector2) -> float:
	if camber_px <= 0.0:
		return 0.0
	var rl := _route_lateral(p)
	if float(rl["dist"]) > width:
		return 0.0
	return absf(bank[rl["i"]]) / camber_px


func lean_h(p: Vector2) -> float:
	if lean == Vector2.ZERO:
		return 0.0
	var c := size * 0.5
	return lean.x * (p.x - c.x) + lean.y * (p.y - c.y)


func _process(dt: float) -> void:
	if not leaning:
		return
	lean = lean.move_toward(lean_target, dt * lean_target.distance_to(Vector2.ZERO) / LEAN_SECONDS + dt * 0.002)
	if lean.distance_to(lean_target) < 0.00005:
		lean = lean_target
		leaning = false
	# the built course (Track's own meshes) tilts as a whole about the map centre
	var c := Vector3(size.x * 0.5 * U, 0.0, size.y * 0.5 * U)
	var b := Basis(Vector3(0, 0, 1), -atan(lean.x)) * Basis(Vector3(1, 0, 0), atan(lean.y))
	transform = Transform3D(b, c - b * c)


# Near the road the route point's EXACT profile height (so a step is a cliff, not a ramp
# across a grid cell); the shelf grid beyond it. `rl` is a _route_lateral result to reuse.
func authored_height(p: Vector2, rl: Dictionary = {}) -> float:
	if hgrid.is_empty():
		return 0.0
	if rl.is_empty():
		rl = _route_lateral(p)
	if float(rl["dist"]) <= width * 1.5:
		# smooth along the route between neighbouring samples, except across a step (a cliff)
		var i: int = rl["i"]
		var along: float = rl.get("along", 0.0)
		var j := i + 1 if along >= 0.0 else i - 1
		if open:
			j = clampi(j, 0, n - 1)
		else:
			j = (j + n) % n
		if steps.has(maxi(i, j)) or j == i:
			return profile_h[i]
		return lerpf(profile_h[i], profile_h[j], absf(along))
	var g := (p - hg_origin) / HG_CELL
	var c := clampi(int(floor(g.x)), 0, hg_cols - 2)
	var r := clampi(int(floor(g.y)), 0, hg_rows - 2)
	var fx := clampf(g.x - c, 0.0, 1.0)
	var fy := clampf(g.y - r, 0.0, 1.0)
	var h00 := hgrid[r * hg_cols + c]
	var h10 := hgrid[r * hg_cols + c + 1]
	var h01 := hgrid[(r + 1) * hg_cols + c]
	var h11 := hgrid[(r + 1) * hg_cols + c + 1]
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fy)


func height_px(p: Vector2) -> float:
	var rl := {}
	if not hgrid.is_empty() or camber_px > 0.0:
		rl = _route_lateral(p)
	return noise.get_noise_2d(p.x, p.y) * elev_amp + authored_height(p, rl) + camber_at(p, rl) + lean_h(p)


# The road's grade under a kart: rise per px along `fwd` (positive = uphill).
func grade(p: Vector2, fwd: Vector2) -> float:
	if hgrid.is_empty() and lean == Vector2.ZERO:
		return 0.0
	var step := 60.0
	return (authored_height(p + fwd * step) + lean_h(p + fwd * step) - authored_height(p - fwd * step) - lean_h(p - fwd * step)) / (2.0 * step)


func to3(p: Vector2, lift_px := 0.0) -> Vector3:
	return Vector3(p.x * U, (height_px(p) + lift_px) * U, p.y * U)


func direction_at(i: int) -> Vector2:
	if open:
		var j := clampi(i, 0, n - 2)
		var dd := points[j + 1] - points[j]
		return dd.normalized() if dd.length_squared() > 0.0 else Vector2.RIGHT
	var d := points[(i + 1) % n] - points[i % n]
	return d.normalized() if d.length_squared() > 0.0 else Vector2.RIGHT


# The waypoint a kart starts on, and the stage (lap, or section on an open road) it is in.
func start_wp() -> int:
	return maxi(1, start_i - 6) if open else 1


func stage_of(kart) -> int:
	if open:
		return clampi(1 + int(kart.next_wp * sections / n), 1, sections)
	return int(kart.lap)


func stage_name() -> String:
	return "SECTION" if open else "LAP"


func stage_count(laps: int) -> int:
	return sections if open else laps


func _material(tex: Texture2D, color := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if tex:
		m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.texture_repeat = true
	m.roughness = 1.0
	m.metallic_specular = 0.0  # no sky reflection at grazing angles; the terrain is matte
	return m


func _build_ground() -> void:
	var margin := 900.0
	var cell := 80.0  # finer than the waypoint spacing so the ground follows the road's height closely
	var x0 := -margin
	var y0 := -margin
	var cols := int(ceil((size.x + 2.0 * margin) / cell))
	var rows := int(ceil((size.y + 2.0 * margin) / cell))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rows:
		for c in cols:
			var a := Vector2(x0 + c * cell, y0 + r * cell)
			var b := a + Vector2(cell, 0)
			var cc := a + Vector2(cell, cell)
			var d := a + Vector2(0, cell)
			for tri in [[a, b, cc], [a, cc, d]]:  # clockwise from above = front face in Godot
				for p in tri:
					st.set_uv(p / TILE_PX)
					st.add_vertex(to3(p))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material(QUD.texture(String(spec.get("ground_tex", "tiles/track_%s_ground.png" % key))))
	mi.name = "Ground"
	add_child(mi)


func _ribbon(offset_a: float, offset_b: float, lift_px: float, tex: Texture2D, color: Color, name: String) -> void:
	_ribbon_of(points, not open, offset_a, offset_b, lift_px, tex, color, name)


static func _dir_of(pts: PackedVector2Array, i: int, closed: bool) -> Vector2:
	var m := pts.size()
	var j := (i + 1) % m if closed else mini(i + 1, m - 1)
	var k := i if (closed or i < m - 1) else m - 2
	var d := pts[j] - pts[k]
	return d.normalized() if d.length_squared() > 0.0 else Vector2.RIGHT


# A road strip along any polyline (the loop, closed; a branch, open).
func _ribbon_of(pts: PackedVector2Array, closed: bool, offset_a: float, offset_b: float, lift_px: float, tex: Texture2D, color: Color, name: String) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	var prev_l: Vector3
	var prev_r: Vector3
	var prev_v := 0.0
	var m := pts.size()
	var count := m + 1 if closed else m
	for i in range(count):
		var idx := i % m
		var p := pts[idx]
		var d := _dir_of(pts, idx, closed)
		var nrm := Vector2(-d.y, d.x)
		var l := to3(p + nrm * offset_a, lift_px)
		var r := to3(p + nrm * offset_b, lift_px)
		var v := along / TILE_PX
		if i > 0:
			var ua := offset_a / TILE_PX
			var ub := offset_b / TILE_PX
			st.set_uv(Vector2(ua, prev_v)); st.add_vertex(prev_l)
			st.set_uv(Vector2(ub, v)); st.add_vertex(r)
			st.set_uv(Vector2(ub, prev_v)); st.add_vertex(prev_r)
			st.set_uv(Vector2(ua, prev_v)); st.add_vertex(prev_l)
			st.set_uv(Vector2(ua, v)); st.add_vertex(l)
			st.set_uv(Vector2(ub, v)); st.add_vertex(r)
		prev_l = l
		prev_r = r
		prev_v = v
		along += pts[idx].distance_to(pts[(idx + 1) % m])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material(tex, color)
	mi.name = name
	add_child(mi)
	return mi


# ---------------------------------------------------------------- parallel routes

static func catmull_rom_open(ctrl: Array, samples: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var m := ctrl.size()
	if m < 2:
		return out
	for i in range(m - 1):
		var p0: Vector2 = ctrl[maxi(0, i - 1)]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[i + 1]
		var p3: Vector2 = ctrl[mini(m - 1, i + 2)]
		for s in samples:
			var t := float(s) / samples
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(ctrl[m - 1])
	return out


func _build_branches() -> void:
	branches.clear()
	var samples := maxi(4, int(round(8.0 * scale_k * 90.0 / float(Shared.t(["race", "waypoint_spacing"], 90.0)))))
	var road_tex: Texture2D = QUD.texture(String(spec.get("road_tex", "tiles/track_%s_road.png" % key)))
	var bi := 0
	for b in spec.get("branches", []):
		var from_i := clampi(int(floor(float(b.get("from", 0.3)) * n)), 2, n - 3)
		var to_i := clampi(int(floor(float(b.get("to", 0.5)) * n)), from_i + 2, n - 2)
		var ctrl := [points[from_i]]
		for c in b.get("control", []):
			ctrl.append(Vector2(c[0], c[1]) * scale_k)
		ctrl.append(points[to_i])
		var pts := catmull_rom_open(ctrl, samples)
		var w := float(b.get("width", 180)) * (1.0 + (scale_k - 1.0) * 0.35)
		var kind := String(b.get("kind", "safe"))
		# the road: main texture; the curbs say what it is (bible route language: grey dashed =
		# the safer alternate, luminous = the expert route)
		var curb := Color(0.55, 0.55, 0.6) if kind == "safe" else Color(0.5, 1.0, 1.0)
		var color := Color(0.72, 0.72, 0.75) if kind == "safe" else Color(0.85, 0.9, 1.0)
		var mesh := _ribbon_of(pts, false, -w * 0.5, w * 0.5, 7.0, road_tex, color, "Branch%d" % bi)
		var curbs := [_ribbon_of(pts, false, -w * 0.5 - 14.0, -w * 0.5, 7.5, null, curb, "Branch%dCurbL" % bi),
			_ribbon_of(pts, false, w * 0.5, w * 0.5 + 14.0, 7.5, null, curb, "Branch%dCurbR" % bi)]
		branches.append({"name": String(b.get("name", "route %d" % (bi + 1))), "kind": kind, "pts": pts,
			"from_i": from_i, "to_i": to_i, "width": w, "ai_take": float(b.get("ai_take", 0.4)),
			"hazards": b.get("hazards", []), "laps": b.get("laps", []), "live": true,
			"bypass": bool(b.get("bypass", false)), "mesh": mesh, "curbs": curbs, "color": color,
			"sealed": bool(b.get("sealed", false))})     # sealed: not a route until a mover cuts it open
		bi += 1
	if bi > 0:
		print("branches: %d parallel routes (%s): %s" % [bi, key, ", ".join(branches.map(func(b): return "%s %s" % [b["name"], b["kind"]]))])


# Moving hazards (spec "movers"): a patch that travels a path authored as [at, side] pairs
# (loop fraction, lateral in half road widths), back and forth or around, in `period`
# seconds. The path is drawn on the road as a faint strip: the bible's sweep markings.
func mover_paths() -> Array:
	var out := []
	for m in spec.get("movers", []):
		var pts := PackedVector2Array()
		for ps in m.get("path", []):
			var i := int(floor(float(ps[0]) * n)) % n
			var d := direction_at(i)
			var nrm := Vector2(-d.y, d.x)
			pts.append(points[i] + nrm * float(ps[1]) * width * 0.5)
		if pts.size() < 2:
			continue
		var seg := PackedFloat32Array()
		var total := 0.0
		for j in range(pts.size() - 1):
			var l := pts[j].distance_to(pts[j + 1])
			seg.append(l)
			total += l
		out.append({"name": String(m.get("name", "mover")), "kind": String(m.get("kind", "cart")), "pts": pts, "seg": seg, "length": total,
			"period": float(m.get("period", 6.0)), "mode": String(m.get("mode", "pingpong")), "radius": float(m.get("radius", 140.0)),
			"laps": m.get("laps", []), "phase": float(m.get("phase", 0.0)),
			"cuts_walls": bool(m.get("cuts_walls", false)), "opens": String(m.get("opens", ""))})
	return out


func _build_mover_marks() -> void:
	var i := 0
	for mv in mover_paths():
		_ribbon_of(mv["pts"], false, -16.0, 16.0, 6.5, null, Color(1.0, 0.75, 0.2, 0.5), "MoverMark%d" % i)
		var mi: MeshInstance3D = get_node("MoverMark%d" % i)
		var mat: StandardMaterial3D = mi.material_override
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		i += 1


# Where along a mover's path it is at time t (pingpong sweeps back; loop wraps).
static func mover_pos(mv: Dictionary, t: float) -> Vector2:
	var pts: PackedVector2Array = mv["pts"]
	var L: float = mv["length"]
	if L <= 0.0:
		return pts[0]
	var speed := L / maxf(0.1, float(mv["period"]))
	var s := (t + float(mv["phase"])) * speed
	if String(mv["mode"]) == "loop":
		s = fmod(s, L)
	else:
		s = fmod(s, 2.0 * L)
		if s > L:
			s = 2.0 * L - s
	var seg: PackedFloat32Array = mv["seg"]
	for j in seg.size():
		if s <= seg[j] or j == seg.size() - 1:
			return pts[j].lerp(pts[j + 1], clampf(s / maxf(0.001, seg[j]), 0.0, 1.0))
		s -= seg[j]
	return pts[pts.size() - 1]


# A thrower's landing spot: the loop at `at`, `side` half-widths across, jittered by spread.
func throw_target(at: float, side: float, spread: float, rng: RandomNumberGenerator) -> Vector2:
	var i := int(floor(clampf(at + rng.randf_range(-spread, spread) * 0.02, 0.0, 0.999) * n)) % n
	var d := direction_at(i)
	var nrm := Vector2(-d.y, d.x)
	return points[i] + nrm * (side + rng.randf_range(-spread, spread)) * width * 0.5


# The main-loop index a branch sample stands in for (its share of the way from fork to merge).
func branch_equiv(b: int, j: int) -> int:
	var br: Dictionary = branches[b]
	var m: int = (br["pts"] as PackedVector2Array).size()
	return int(round(lerp(float(br["from_i"]), float(br["to_i"]), float(j) / maxf(1.0, m - 1))))


# Where an AI kart should aim `look` samples ahead: along its branch when it is on one (or
# has chosen one at the fork), else along the loop. -> {pos, dir, width}
func aim(kart, look: int) -> Dictionary:
	var b: int = kart.branch
	var j: int = kart.branch_idx + look
	if b < 0 and kart.branch_choice >= 0:
		var br: Dictionary = branches[kart.branch_choice]
		var ahead: int = int(br["from_i"]) - kart.next_wp
		if ahead <= look and ahead > -4:
			b = kart.branch_choice
			j = maxi(1, look - ahead)
	if b >= 0:
		var br: Dictionary = branches[b]
		var pts: PackedVector2Array = br["pts"]
		if j < pts.size() - 1:
			return {"pos": pts[j], "dir": _dir_of(pts, j, false), "width": float(br["width"])}
		var idx := (int(br["to_i"]) + (j - pts.size() + 1)) % n
		return {"pos": points[idx], "dir": direction_at(idx), "width": width}
	var idx2: int = (kart.next_wp + look) % n
	return {"pos": points[idx2], "dir": direction_at(idx2), "width": width}


# The fork decision: once per pass, an AI kart approaching a branch takes it with ai_take.
func choose_branch(kart) -> void:
	for b in branches.size():
		var br: Dictionary = branches[b]
		if not bool(br["live"]):
			continue
		var fork: int = int(br["from_i"]) - 6
		if kart.next_wp >= fork and kart.next_wp < int(br["from_i"]) and kart.choice_fork != fork:
			kart.choice_fork = fork
			var chance := float(br["ai_take"])
			if bool(br["bypass"]):
				for i in range(int(br["from_i"]), int(br["to_i"])):
					if _road_state_at(i) == "gap":
						chance = 0.9      # the road ahead is out: nearly everyone goes round
						break
			kart.branch_choice = b if kart.rng.randf() < chance else -1


# Lap-changing road (spec "road_states": {from, to, laps, state}): the road is built in
# pieces at those stretches so a piece can turn "hologram" (translucent, still road),
# "cracked" (amber: the preview of a coming gap), or "gap" (hidden, not road) on a lap.
var road_pieces: Array = []      # [{from_i, to_i, mesh, states: [{laps, state}], state}]


func _build_road() -> void:
	var half := width * 0.5
	var curb := 12.0
	var road_tex: Texture2D = QUD.texture(String(spec.get("road_tex", "tiles/track_%s_road.png" % key)))
	# lifted above the interpolated ground so slopes never poke through the surface
	_ribbon(-half - curb, -half, 7.0, null, Color(0.88, 0.84, 0.76), "CurbL")
	_ribbon(half, half + curb, 7.0, null, Color(0.88, 0.84, 0.76), "CurbR")
	road_pieces.clear()
	var states: Array = spec.get("road_states", [])
	if states.is_empty() and steps.is_empty():
		_ribbon(-half, half, 7.5, road_tex, Color.WHITE, "Road")
		return
	# cut points: every stretch boundary, in order; pieces between them
	var cuts := [0]
	for rs in states:
		cuts.append(clampi(int(floor(float(rs.get("from", 0.0)) * n)), 1, n - 2))
		cuts.append(clampi(int(floor(float(rs.get("to", 0.0)) * n)), 1, n - 2))
	for st in steps:
		cuts.append(clampi(st, 1, n - 2))
	cuts.append(n - 1 if open else n)
	cuts.sort()
	var uniq := []
	for c in cuts:
		if uniq.is_empty() or c != uniq[uniq.size() - 1]:
			uniq.append(c)
	for i in range(uniq.size() - 1):
		var a: int = uniq[i]
		var b: int = uniq[i + 1]
		var sub := PackedVector2Array()
		# a piece that ends at a ledge stops one point short, so no strip hangs down the shaft
		var last := mini(b + 1, n) if not steps.has(b) else b
		for j in range(a, last):
			sub.append(points[j])
		if not open and b == n:
			sub.append(points[0])
		if sub.size() < 2:
			continue
		var piece := {"from_i": a, "to_i": b, "states": [], "state": "road"}
		for rs in states:
			var f := clampi(int(floor(float(rs.get("from", 0.0)) * n)), 1, n - 2)
			var t2 := clampi(int(floor(float(rs.get("to", 0.0)) * n)), 1, n - 2)
			if a >= f and b <= t2:
				piece["states"].append({"laps": rs.get("laps", []), "state": String(rs.get("state", "road"))})
		piece["mesh"] = _ribbon_of(sub, false, -half, half, 7.5, road_tex, Color.WHITE, "Road%d" % i)
		road_pieces.append(piece)


func _road_state_at(idx: int) -> String:
	for piece in road_pieces:
		if idx >= int(piece["from_i"]) and idx < int(piece["to_i"]):
			return String(piece["state"])
	return "road"


# The course on lap `lap`: branch liveness and road-piece states. Returns the changes
# as strings for the log.
func apply_lap(lap: int) -> Array:
	var changes := []
	var leans: Dictionary = spec.get("lean", {})
	var want := Vector2.ZERO
	if leans.has(str(lap)):
		var v: Array = leans[str(lap)]
		want = Vector2(float(v[0]), float(v[1]))
	if want != lean_target:
		lean_target = want
		leaning = true
		changes.append("lean %.3f,%.3f" % [want.x, want.y])
	for b in branches.size():
		var br: Dictionary = branches[b]
		var gate: Array = br.get("laps", [])
		var live := (gate.is_empty() or gate.has(lap) or gate.has(float(lap))) and not bool(br["sealed"])
		if live != bool(br["live"]):
			br["live"] = live
			_set_branch_live(br, live)
			changes.append("branch %s %s" % [String(br["name"]), "live" if live else "dormant"])
	for piece in road_pieces:
		var st := "road"
		for cand in piece["states"]:
			var g: Array = cand["laps"]
			if g.is_empty() or g.has(lap) or g.has(float(lap)):
				st = String(cand["state"])
				break
		if st != String(piece["state"]):
			piece["state"] = st
			var mi: MeshInstance3D = piece["mesh"]
			var mat: StandardMaterial3D = mi.material_override
			mi.visible = st != "gap"
			match st:
				"hologram":
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat.albedo_color = Color(0.55, 0.95, 1.0, 0.38)
				"cracked":
					mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
					mat.albedo_color = Color(1.0, 0.75, 0.35)
				_:
					mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
					mat.albedo_color = Color.WHITE
			changes.append("road %d-%d %s" % [int(piece["from_i"]), int(piece["to_i"]), st])
	return changes


func _set_branch_live(br: Dictionary, live: bool) -> void:
	var road: MeshInstance3D = br["mesh"]
	var mat: StandardMaterial3D = road.material_override
	if live:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.albedo_color = br["color"]
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.7, 0.8, 0.9, 0.22)      # the preview of a road to come
	for c in br["curbs"]:
		(c as MeshInstance3D).visible = live


# A mover cut its way through: the sealed branch becomes a route.
func unseal_branch(name: String) -> bool:
	for br in branches:
		if String(br["name"]) == name and bool(br["sealed"]):
			br["sealed"] = false
			br["live"] = true
			_set_branch_live(br, true)
			return true
	return false


# The wall blocks within `radius` of a mover's path, each with the path distance at which the
# mover reaches it, so they can be cut as it passes.
func blocks_along(mv: Dictionary, radius: float) -> Array:
	var out := []
	var pts: PackedVector2Array = mv["pts"]
	var seg: PackedFloat32Array = mv["seg"]
	for blk in scenery_blocks:
		var p: Vector2 = blk["pos"]
		var s := 0.0
		for j in range(pts.size() - 1):
			var q := Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1])
			if p.distance_to(q) <= radius:
				out.append({"node": blk["node"], "pos": p, "s": s + pts[j].distance_to(q)})
				break
			s += seg[j]
	return out


# The void: a kart that falls off this course (spec void_offroad, beyond void_margin px past
# the curbs) or into a gap/void stretch is returned to the road a little further on.
func void_here(p: Vector2, hint: int) -> bool:
	var near := nearest(p, hint)
	if int(near.get("branch", -1)) >= 0:
		return false
	var idx := int(near["idx"])
	var half := width * 0.5
	if not road_pieces.is_empty() and near.dist <= half and _road_state_at(idx) in ["gap", "void"]:
		return true
	if bool(spec.get("void_offroad", false)) and near.dist > half + 14.0 + float(spec.get("void_margin", 60.0)) * scale_k:
		return true
	return false


func return_point(hint: int) -> Dictionary:
	var idx := hint
	if not road_pieces.is_empty():
		while _road_state_at(idx) in ["gap", "void"] and idx < n - 1:
			idx += 1
	idx = (idx + 3) % n if not open else mini(n - 2, idx + 3)
	return {"idx": idx, "pos": points[idx], "dir": direction_at(idx)}


func branch_live(b: int) -> bool:
	return b >= 0 and b < branches.size() and bool(branches[b]["live"])


func _build_start_line() -> void:
	_build_line_at(start_i, "StartLine")
	if open:
		_build_line_at(n - 1, "FinishLine")


func _build_line_at(at: int, name: String) -> void:
	var img := Image.create(16, 2, false, Image.FORMAT_RGBA8)
	for y in 2:
		for x in 16:
			img.set_pixel(x, y, Color.WHITE if (x + y) % 2 == 0 else Color(0.08, 0.08, 0.08))
	var tex := ImageTexture.create_from_image(img)
	var d := direction_at(at)
	var nrm := Vector2(-d.y, d.x)
	var base := points[at]
	var half := width * 0.5
	var depth := 32.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := base - nrm * half - d * depth
	var b := base + nrm * half - d * depth
	var c := base + nrm * half
	var e := base - nrm * half
	var squares := width / 16.0
	for tri in [[a, c, b], [a, e, c]]:
		for p in tri:
			var uv := Vector2((p - a).dot(nrm) / width * squares, (p - a).dot(d) / depth)
			st.set_uv(uv)
			st.add_vertex(to3(p, 4.0))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material(tex)
	mi.name = name
	add_child(mi)


func _build_scenery(rng: RandomNumberGenerator) -> void:
	if city != null:
		return
	var fam := _wall_family()
	var walls: Array = [] if fam != "" else _wall_sprites()
	if fam == "" and walls.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "Scenery"
	add_child(holder)
	var target := int(min(900, 140 * scale_k * scale_k))
	var placed := 0
	var tries := 0
	while placed < target and tries < target * 20:
		tries += 1
		var p := Vector2(rng.randf_range(0, size.x), rng.randf_range(0, size.y))
		var near := nearest(p, -1)
		if near.dist < width * 0.8:
			continue
		if fam != "":
			# short ruined runs of wall off the road, turned to face it: isolated
			# blocks for singles, the run model with its open ends for longer bits
			var len_b := rng.randi_range(1, 4)
			var d := direction_at(near.idx)
			var along := d if rng.randf() < 0.5 else Vector2(-d.y, d.x)
			var facing := Vector2(-along.y, along.x)
			var q := points[near.idx]
			if (p - q).dot(facing) < 0.0:
				facing = -facing
			var start := p - along * (len_b - 1) * 0.5 * WALL_PX
			for k in len_b:
				if _wall_block(fam, QudVox.run_variant(k, len_b, along, facing), start + along * k * WALL_PX, facing, holder):
					placed += 1
			continue
		var s := Sprite3D.new()
		s.texture = walls[rng.randi_range(0, walls.size() - 1)]
		s.pixel_size = U
		s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.position = to3(p) + Vector3(0, 30.0 * U, 0)
		holder.add_child(s)
		placed += 1
	if fam != "":
		print("walls: %d voxel scenery blocks (%s)" % [placed, fam])


# The rock a map-cutting mover bores through: a run of wall blocks along its path from the
# curb outward, faces turned back toward the road. Random scenery rarely sits on the path,
# so the cut is authored here and the mover frees these blocks as it passes them.
func _build_cut_walls() -> void:
	var fam := _wall_family()
	if fam == "":
		return
	var holder := Node3D.new()
	holder.name = "CutWalls"
	add_child(holder)
	var half := width * 0.5
	var placed := 0
	for mv in mover_paths():
		if not bool(mv["cuts_walls"]):
			continue
		var pts: PackedVector2Array = mv["pts"]
		for j in range(pts.size() - 1):
			var a := pts[j]
			var b := pts[j + 1]
			var along := (b - a).normalized()
			var facing := -along
			var count := int(floor(a.distance_to(b) / WALL_PX))
			for k in range(count + 1):
				var q := a + along * k * WALL_PX
				if nearest(q, -1).dist < half + 8.0:
					continue
				if _wall_block(fam, QudVox.run_variant(k, count + 1, along, facing), q, facing, holder):
					placed += 1
	if placed > 0:
		print("walls: %d voxel blocks across the cuts (%s)" % [placed, fam])


# ---------------------------------------------------------------- psychic overlays
#
# Eyn Roj's perception course (spec "psychic": forms per section). Three authored forms
# that alter what is seen, never what is driven: doubled road EDGES (a second, translucent
# magenta edge beyond the real curb), false distant SILHOUETTES (racers that are not there,
# off the road), and delayed GHOSTS of the racers (Race draws those). None of it inside the
# driving envelope: every overlay fades to nothing within `envelope` px of a kart. The
# rhythm-rock STUDS along the true edge pulse on the beat and brighter before a real turn,
# the one thing that is always trustworthy. The forms come by section and vanish at the
# finish (Race passes [] once the wizard is on the last stretch).

var psy_chunks: Array = []      # [{mid: Vector2, mats: [StandardMaterial3D, ...]}]
var psy_sils: Array = []        # [{sprite: Sprite3D, pos: Vector2}]
var psy_studs: MultiMeshInstance3D = null
var psy_stud_mat: StandardMaterial3D = null
const PSY_CHUNK := 8


func psychic() -> bool:
	return spec.get("psychic", {}) is Dictionary and not (spec.get("psychic", {}) as Dictionary).is_empty()


func psychic_forms(section: int) -> Array:
	var ps: Dictionary = spec.get("psychic", {})
	return ps.get(str(section), [])


func psychic_envelope() -> float:
	return float((spec.get("psychic", {}) as Dictionary).get("envelope", 300.0)) * scale_k * 0.5


func _build_psychic(rng: RandomNumberGenerator) -> void:
	if not psychic():
		return
	var holder := Node3D.new()
	holder.name = "Psychic"
	add_child(holder)
	var half := width * 0.5
	var edge := Color(1.0, 0.55, 1.0, 0.0)
	# doubled edges: a low translucent fence a little beyond the real curb (a flat strip
	# vanishes against the ground at speed), in chunks so each can fade on its own near a kart
	var i := 0
	while i < n - 1:
		var sub := PackedVector2Array()
		for j in range(i, mini(n, i + PSY_CHUNK + 1)):
			sub.append(points[j])
		if sub.size() >= 2:
			var mats := []
			for side in [-1.0, 1.0]:
				var mi := _fence_of(sub, side * (half + 36.0), 9.0, 34.0, edge)
				mi.name = "Echo%d" % i
				holder.add_child(mi)
				mats.append(mi.material_override)
			psy_chunks.append({"mid": sub[sub.size() / 2], "mats": mats})
		i += PSY_CHUNK
	# false silhouettes: racers that are not there, well off the road
	var units: Array = QUD.manifest.get("units", {}).keys()
	var count := int(18 * scale_k * 0.5)
	var tries := 0
	while psy_sils.size() < count and tries < count * 30 and not units.is_empty():
		tries += 1
		var p := Vector2(rng.randf_range(0, size.x), rng.randf_range(0, size.y))
		var d: float = nearest(p, -1).dist
		if d < half + 160.0 * scale_k * 0.5 or d > half + 620.0 * scale_k * 0.5:
			continue
		var unit: String = units[rng.randi_range(0, units.size() - 1)]
		var tex := QUD.unit_idle(unit)
		if tex == null:
			continue
		var spr := Sprite3D.new()
		spr.texture = tex
		spr.hframes = maxi(1, int(QUD.unit_info(unit).get("idle_frames", 1)))
		spr.pixel_size = U * 2.2
		spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		spr.modulate = Color(1.0, 0.6, 1.0, 0.0)
		spr.position = to3(p, 70.0)
		holder.add_child(spr)
		psy_sils.append({"sprite": spr, "pos": p})
	# rhythm-rock studs on the true edge, emphasised before a real turn
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(16.0 * U, 16.0 * U)
	mm.mesh = quad
	var studs := []
	var step_px := 150.0
	var acc := 0.0
	for k in range(n - 1 if open else n):
		acc += seg_len[k]
		if acc < step_px:
			continue
		acc = 0.0
		var d := direction_at(k)
		var emph := 1.0 if bend_ahead(k, BEND_LOOK_PX) > deg_to_rad(BEND_DEG) else 0.45
		var nrm := Vector2(-d.y, d.x)
		for side in [-1.0, 1.0]:
			studs.append([points[k] + nrm * side * (half + 8.0), emph])
	mm.instance_count = studs.size()
	for si in studs.size():
		var xf := Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), to3(studs[si][0], 9.5))
		mm.set_instance_transform(si, xf)
		mm.set_instance_color(si, Color(0.6, 0.95, 1.0, 1.0) * float(studs[si][1]))
	psy_studs = MultiMeshInstance3D.new()
	psy_studs.multimesh = mm
	psy_stud_mat = StandardMaterial3D.new()
	psy_stud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	psy_stud_mat.vertex_color_use_as_albedo = true
	psy_stud_mat.albedo_color = Color.WHITE
	psy_studs.material_override = psy_stud_mat
	holder.add_child(psy_studs)
	print("psychic: %d edge chunks, %d silhouettes, %d studs" % [psy_chunks.size(), psy_sils.size(), studs.size()])


# A translucent vertical strip along a polyline: the doubled edge as a low fence.
func _fence_of(pts: PackedVector2Array, offset: float, lift_a: float, lift_b: float, color: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var m := pts.size()
	var prev_lo: Vector3
	var prev_hi: Vector3
	for i in m:
		var d := _dir_of(pts, i, false)
		var nrm := Vector2(-d.y, d.x)
		var q := pts[i] + nrm * offset
		var lo := to3(q, lift_a)
		var hi := to3(q, lift_b)
		if i > 0:
			st.add_vertex(prev_lo); st.add_vertex(hi); st.add_vertex(prev_hi)
			st.add_vertex(prev_lo); st.add_vertex(lo); st.add_vertex(hi)
			st.add_vertex(prev_lo); st.add_vertex(prev_hi); st.add_vertex(hi)   # both faces
			st.add_vertex(prev_lo); st.add_vertex(hi); st.add_vertex(lo)
		prev_lo = lo
		prev_hi = hi
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	return mi


const BEND_LOOK_PX := 1200.0    # a real turn: this much road ahead (about 1.4 s at pace)...
const BEND_DEG := 25.0          # ...turning the heading by at least this


# The heading change from waypoint i to the waypoint about `px` of road ahead: the studs'
# emphasis and the pad's rumble both mean "a real turn is coming" by this.
func bend_ahead(i: int, px: float) -> float:
	var j := i
	var acc := 0.0
	var steps := 0
	while acc < px and steps < n:
		acc += seg_len[j % n]
		j += 1
		steps += 1
		if open and j >= n - 1:
			break
	return absf(direction_at(i % n).angle_to(direction_at(j % n)))


# One frame of the overlays: which forms are on, and how far every kart is from each one.
# Returns counts for the log.
func psychic_update(t: float, kart_positions: Array, forms: Array, beat: float) -> Dictionary:
	var env := psychic_envelope()
	var edges := "edges" in forms
	var sils := "silhouettes" in forms
	var shown := 0
	var faded := 0
	for ci in psy_chunks.size():
		var c: Dictionary = psy_chunks[ci]
		var a := 0.0
		if edges:
			var dmin := INF
			for kp in kart_positions:
				dmin = minf(dmin, (kp as Vector2).distance_to(c["mid"]))
			var fade := clampf((dmin - env) / env, 0.0, 1.0)
			a = 0.55 * fade * (0.8 + 0.2 * sin(t * 1.3 + ci))
			if fade < 1.0:
				faded += 1
			if a > 0.01:
				shown += 1
		for mat in c["mats"]:
			(mat as StandardMaterial3D).albedo_color.a = a
	var sshown := 0
	for sd in psy_sils:
		var a := 0.0
		if sils:
			var dmin := INF
			for kp in kart_positions:
				dmin = minf(dmin, (kp as Vector2).distance_to(sd["pos"]))
			a = 0.5 * clampf((dmin - env * 1.5) / env, 0.0, 1.0)
			if a > 0.01:
				sshown += 1
		var spr: Sprite3D = sd["sprite"]
		spr.modulate.a = a
		spr.frame = int(t / 0.25) % maxi(1, spr.hframes)
	var pulse := 0.0
	if psy_stud_mat != null:
		pulse = 0.5 + 0.5 * maxf(0.0, sin(t * TAU * beat))
		psy_stud_mat.albedo_color = Color(0.55 + 0.45 * pulse, 0.55 + 0.45 * pulse, 0.55 + 0.45 * pulse)
		psy_studs.visible = not forms.is_empty()
	return {"edges": shown, "edges_total": psy_chunks.size(), "faded": faded, "sils": sshown, "sils_total": psy_sils.size(), "pulse": pulse}


# ---------------------------------------------------------------- occlusion struts
#
# Palladium's sightline course (spec "struts"): translucent panels that occlude vision and
# never block movement. Each strut is a tall vertical panel standing across part of the
# road or beside it, placed after a turn has been announced so the apex behind it is hidden
# at distance; within a couple of kart lengths of a human it goes nearly clear, so the road
# is always locally readable. "strut_strips" are luminous edge lines through the occluded
# sectors that draw THROUGH the struts (no depth test): the turn is established before the
# strut hides it. Silver strips outbound, gold on the return.

var struts: Array = []          # [{pos: Vector2, mat: StandardMaterial3D}]
var strut_strip_count := 0


func has_struts() -> bool:
	return not (spec.get("struts", []) as Array).is_empty()


func _build_struts() -> void:
	if not has_struts():
		return
	var holder := Node3D.new()
	holder.name = "Struts"
	add_child(holder)
	var half := width * 0.5
	var silver := Color(0.78, 0.84, 0.92, 0.82)
	for st in spec["struts"]:
		var i := int(floor(float(st.get("at", 0.0)) * n)) % n
		var d := direction_at(i)
		var nrm := Vector2(-d.y, d.x)
		var centre := points[i] + nrm * float(st.get("side", 0.0)) * half
		var span := float(st.get("span", 1.0)) * half * scale_k * 0.5
		var ang := deg_to_rad(float(st.get("angle", 0.0)))
		var along := nrm.rotated(ang)          # the panel runs across the road unless angled
		var pts := PackedVector2Array([centre - along * span * 0.5, centre + along * span * 0.5])
		var mi := _fence_of(pts, 0.0, 6.0, float(st.get("height", 96.0)), silver)
		mi.name = "Strut%d" % struts.size()
		holder.add_child(mi)
		struts.append({"pos": centre, "mat": mi.material_override})
	for rng_f in spec.get("strut_strips", []):
		var a := clampi(int(floor(float(rng_f[0]) * n)), 0, n - 2)
		var b := clampi(int(floor(float(rng_f[1]) * n)), a + 1, n - 1)
		var sub := PackedVector2Array()
		for j in range(a, b + 1):
			sub.append(points[j])
		var gold := String(rng_f[2] if rng_f.size() > 2 else "silver") == "gold"
		var col := Color(1.0, 0.85, 0.35, 0.95) if gold else Color(0.8, 0.95, 1.0, 0.95)
		for side in [-1.0, 1.0]:
			var mi := _ribbon_of(sub, false, side * (half + 1.0), side * (half + 9.0), 11.0, null, col, "Strip%d" % strut_strip_count)
			if mi.get_parent() != null:
				mi.reparent(holder)
			else:
				holder.add_child(mi)
			var mat: StandardMaterial3D = mi.material_override
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.no_depth_test = true            # the luminous edge shows through the struts
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			strut_strip_count += 1
	print("struts: %d panels, %d edge strips" % [struts.size(), strut_strip_count])


# One frame: a strut near a human goes nearly clear (the road is locally readable), the
# rest stand at their occluding alpha. Returns how many are clear.
func struts_update(human_positions: Array) -> int:
	var near := 230.0 * scale_k * 0.5
	var clear := 0
	for st in struts:
		var dmin := INF
		for hp in human_positions:
			dmin = minf(dmin, (hp as Vector2).distance_to(st["pos"]))
		var k := clampf((dmin - near * 0.6) / near, 0.0, 1.0)
		(st["mat"] as StandardMaterial3D).albedo_color.a = lerpf(0.14, 0.82, k)
		if k < 0.5:
			clear += 1
	return clear


# ---------------------------------------------------------------- polyps (Palladium)

# The soft gates of the skill route (spec "polyps": [{at, side}], "sunslag": which one
# hides the fixed sunslag boost): positions on the loop for Race to grow, pluck and regrow.
func polyp_spots() -> Array:
	var out := []
	var sun := int(spec.get("sunslag", -1))
	var i := 0
	for pl in spec.get("polyps", []):
		var idx := int(floor(float(pl.get("at", 0.0)) * n)) % n
		var d := direction_at(idx)
		var nrm := Vector2(-d.y, d.x)
		out.append({"pos": points[idx] + nrm * float(pl.get("side", 0.0)) * width * 0.5, "sunslag": i == sun, "id": i})
		i += 1
	return out


# ---------------------------------------------------------------- queries

# Nearest point on the loop. hint < 0 searches everything; otherwise a window
# of segments around hint (the kart's next waypoint) keeps it cheap.
func nearest(p: Vector2, hint: int, window := 30) -> Dictionary:
	var best_d := INF
	var best_i := 0
	var lo := 0
	var hi := n
	if hint >= 0:
		lo = hint - window
		hi = hint + window
	if open:
		lo = maxi(0, lo)
		hi = mini(n - 1, hi)
	for k in range(lo, hi):
		var i := ((k % n) + n) % n
		var q := Geometry2D.get_closest_point_to_segment(p, points[i], points[(i + 1) % n])
		var d := p.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best_i = i
	var out := {"idx": best_i, "dist": sqrt(best_d), "branch": -1, "bidx": 0}
	# a branch counts only within its own road; then its equivalent loop index stands in
	for b in branches.size():
		var br: Dictionary = branches[b]
		if not bool(br["live"]):
			continue
		var pts: PackedVector2Array = br["pts"]
		var half := float(br["width"]) * 0.5
		for j in range(pts.size() - 1):
			var q := Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1])
			var d := p.distance_squared_to(q)
			if d < best_d and d <= half * half:
				best_d = d
				out = {"idx": branch_equiv(b, j), "dist": sqrt(d), "branch": b, "bidx": j}
	return out


func on_road(p: Vector2, hint: int) -> bool:
	if city != null and (free_mode or nearest(p, hint).dist > width * 0.5):
		return city.on_any_street(p)
	var near := nearest(p, hint)
	if int(near.get("branch", -1)) >= 0:
		return true
	if not road_pieces.is_empty() and _road_state_at(int(near["idx"])) == "gap":
		return false
	return near.dist <= width * 0.5


func start_positions(count: int) -> Array:
	var base := points[start_i]
	var d := direction_at(start_i)
	var nrm := Vector2(-d.y, d.x)
	var heading := atan2(d.y, d.x)
	var out := []
	for i in count:
		var row := i / 2
		var col := i % 2
		out.append({"pos": base - d * (110.0 + row * 95.0) + nrm * (col * 84.0 - 42.0), "heading": heading})
	return out


# The course's fixed surface hazards (shared/tracks.json "hazards": kind, at = fraction
# of the loop, side = -1..1 across the road, radius px) as world positions.
func hazard_spots() -> Array:
	var out := []
	if n == 0:
		return out
	for br in branches:
		var pts: PackedVector2Array = br["pts"]
		for h in br["hazards"]:
			var j := clampi(int(floor(float(h.get("at", 0.5)) * (pts.size() - 1))), 0, pts.size() - 1)
			var d := _dir_of(pts, j, false)
			var nrm := Vector2(-d.y, d.x)
			out.append({"kind": String(h.get("kind", "fire")), "pos": pts[j] + nrm * float(h.get("side", 0.0)) * float(br["width"]) * 0.5,
				"radius": float(h.get("radius", 150.0)), "period": float(h.get("period", 0.0)),
				"duty": float(h.get("duty", 0.5)), "phase": float(h.get("phase", 0.0)),
				"laps": h.get("laps", []), "per_lap": h.get("per_lap", {}), "branch": branches.find(br)})
	var jellies := 0
	for h in spec.get("hazards", []):
		var i := int(floor(float(h.get("at", 0.0)) * n)) % n
		var d := direction_at(i)
		var nrm := Vector2(-d.y, d.x)
		var kind := String(h.get("kind", "fire"))
		if kind == "jelly":
			# a plasma jelly sits just off one curb (side beyond +-1) and vents across the lane
			# on its side: three plasma patches from the curb to the road's centre share its
			# cycle; the emitter rides on the first so Race can swell it as the vent charges
			var sgn := signf(float(h.get("side", 1.0)))
			var emitter := points[i] + nrm * float(h.get("side", 1.2)) * width * 0.5
			for k in 3:
				var spot := {"kind": "plasma", "pos": points[i] + nrm * sgn * (0.78 - 0.3 * k) * width * 0.5,
					"radius": minf(float(h.get("radius", 110.0)), width * 0.2), "period": float(h.get("period", 6.0)),
					"duty": float(h.get("duty", 0.25)), "phase": float(h.get("phase", 0.0)),
					"laps": h.get("laps", []), "per_lap": h.get("per_lap", {})}
				if k == 0:
					spot["emitter"] = {"pos": emitter, "id": jellies, "facing": -nrm * sgn}
				out.append(spot)
			jellies += 1
			continue
		out.append({"kind": kind, "pos": points[i] + nrm * float(h.get("side", 0.0)) * width * 0.5,
			"radius": float(h.get("radius", 150.0)), "period": float(h.get("period", 0.0)),
			"duty": float(h.get("duty", 0.5)), "phase": float(h.get("phase", 0.0)),
			"laps": h.get("laps", []), "per_lap": h.get("per_lap", {})})
	return out


func item_positions() -> Array:
	var out := []
	# the bible's item rhythm: one decision-bearing set every 12-18 s of racing, so the sets
	# are spaced by road length at racing pace (race.item_set_seconds x race.item_pace_px)
	_ensure_cum()
	var gap_px := float(Shared.t(["race", "item_set_seconds"], 15.0)) * float(Shared.t(["race", "item_pace_px"], 600.0))
	var sets := clampi(int(round(total_len / maxf(1.0, gap_px))), 3, 12)
	var step := maxi(8, int(n / sets))
	var i := step
	while i < n:
		var d := direction_at(i)
		var nrm := Vector2(-d.y, d.x)
		for k in [-1, 0, 1]:
			out.append(points[i] + nrm * (k * width * 0.3))
		i += step
	# a branch carries a double set halfway along: the bible's premium pickups on the slower line
	for br in branches:
		var pts: PackedVector2Array = br["pts"]
		var j := pts.size() / 2
		var d := _dir_of(pts, j, false)
		var nrm := Vector2(-d.y, d.x)
		for k in [-1, 1]:
			out.append(pts[j] + nrm * (k * float(br["width"]) * 0.25))
	return out


const WINDOW := 10

# Move the kart's waypoint pointer forward; returns true on a new lap.
func advance(kart) -> bool:
	if not branches.is_empty():
		var near := nearest(kart.pos, kart.next_wp, 40)
		var was: int = kart.branch
		kart.branch = int(near.get("branch", -1))
		kart.branch_idx = int(near.get("bidx", 0))
		if kart.branch >= 0:
			var eq: int = int(near["idx"])
			if eq >= kart.next_wp and eq - kart.next_wp < n / 2:
				kart.next_wp = eq + 1        # branches never span the start line, so no lap here
			if was < 0 and kart.branch_log:
				print("branch: %s takes %s" % [kart.display_name, String(branches[kart.branch]["name"])])
		elif was >= 0:
			kart.branch_choice = -1
		choose_branch(kart)
	var thresh2 := pow(width * 0.7, 2)
	var best := -1
	for k in WINDOW:
		var idx: int = (kart.next_wp + k) % n if not open else mini(n - 1, kart.next_wp + k)
		var kp: Vector2 = kart.pos
		if kp.distance_squared_to(points[idx]) < thresh2:
			best = k
	if best < 0:
		return false
	var new_lap := false
	if open:
		kart.next_wp = mini(n - 1, kart.next_wp + best + 1)
		if kart.next_wp >= n - 1 and not kart.finished and int(kart.lap) <= 1:
			kart.lap = 99      # the far end IS the finish: past every lap count
			new_lap = true
		return new_lap
	for k in range(best + 1):
		kart.next_wp = (kart.next_wp + 1) % n
		if kart.next_wp == 1:
			kart.lap += 1
			new_lap = true
	return new_lap


# ---------------------------------------------------------------- arc length (test rig)

var cum_len := PackedFloat32Array()
var total_len := 0.0


func _ensure_cum() -> void:
	if cum_len.size() == n and n > 0:
		return
	cum_len = PackedFloat32Array()
	total_len = 0.0
	for i in n:
		cum_len.append(total_len)
		total_len += seg_len[i]


# Distance in px along the route, laps included, continuous with progress().
func progress_px(kart) -> float:
	_ensure_cum()
	var wp: int = kart.next_wp
	var prev := ((wp - 1) % n + n) % n
	var seg: float = seg_len[prev]
	var kp: Vector2 = kart.pos
	var frac := clampf(1.0 - kp.distance_to(points[wp]) / maxf(1.0, seg), 0.0, 1.0)
	return float(kart.lap) * total_len + cum_len[prev] + frac * seg


# Arc length (within the lap) of the route point nearest p, searched around hint.
func route_px_at(p: Vector2, hint: int, window := 30) -> Dictionary:
	_ensure_cum()
	var r := nearest(p, hint, window)
	var i: int = r["idx"]
	var q := Geometry2D.get_closest_point_to_segment(p, points[i], points[(i + 1) % n])
	return {"px": cum_len[i] + q.distance_to(points[i]), "idx": i, "dist": r["dist"]}


# Position and direction at arc length s (wraps around the lap).
func point_at_px(s: float) -> Dictionary:
	_ensure_cum()
	var d := fposmod(s, total_len)
	var i := 0
	while i < n - 1 and cum_len[i + 1] <= d:
		i += 1
	var seg: float = seg_len[i]
	var f := clampf((d - cum_len[i]) / maxf(1.0, seg), 0.0, 1.0)
	var a: Vector2 = points[i]
	var b: Vector2 = points[(i + 1) % n]
	return {"pos": a.lerp(b, f), "dir": (b - a).normalized(), "index": i}


func progress(kart) -> float:
	var wp: int = kart.next_wp
	var target: Vector2 = points[wp]
	var seg: float = seg_len[((wp - 1) % n + n) % n]
	var kp: Vector2 = kart.pos
	var frac := minf(1.0, kp.distance_to(target) / seg)
	return float(kart.lap) * n + wp - frac
