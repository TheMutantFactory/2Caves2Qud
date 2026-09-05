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
	points = catmull_rom(control, maxi(4, int(round(8.0 * scale_k * 90.0 / spacing))))
	n = points.size()
	seg_len.resize(n)
	for i in n:
		seg_len[i] = maxf(1.0, points[(i + 1) % n].distance_to(points[i]))

	elev_amp = float(spec.get("elevation", Shared.t(["godot", "elevation_px"], 60.0)))
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = float(Shared.t(["godot", "elevation_freq"], 0.0006))

	_build_ground()
	_build_road()
	_build_start_line()
	_build_scenery(rng)


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
func _wall_block(fam: String, variant: String, p: Vector2, facing: Vector2, parent: Node) -> bool:
	var mi := QudVox.block(fam, variant, WALL_PX / 16.0, U)
	if mi == null:
		return false
	mi.position = to3(p)
	mi.rotation.y = atan2(facing.x, facing.y)
	parent.add_child(mi)
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


func height_px(p: Vector2) -> float:
	return noise.get_noise_2d(p.x, p.y) * elev_amp


func to3(p: Vector2, lift_px := 0.0) -> Vector3:
	return Vector3(p.x * U, (height_px(p) + lift_px) * U, p.y * U)


func direction_at(i: int) -> Vector2:
	var d := points[(i + 1) % n] - points[i % n]
	return d.normalized() if d.length_squared() > 0.0 else Vector2.RIGHT


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
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	var prev_l: Vector3
	var prev_r: Vector3
	var prev_v := 0.0
	for i in range(n + 1):
		var idx := i % n
		var p := points[idx]
		var d := direction_at(idx)
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
		along += seg_len[idx]
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material(tex, color)
	mi.name = name
	add_child(mi)


func _build_road() -> void:
	var half := width * 0.5
	var curb := 12.0
	var road_tex: Texture2D = QUD.texture(String(spec.get("road_tex", "tiles/track_%s_road.png" % key)))
	# lifted above the interpolated ground so slopes never poke through the surface
	_ribbon(-half - curb, -half, 7.0, null, Color(0.88, 0.84, 0.76), "CurbL")
	_ribbon(half, half + curb, 7.0, null, Color(0.88, 0.84, 0.76), "CurbR")
	_ribbon(-half, half, 7.5, road_tex, Color.WHITE, "Road")


func _build_start_line() -> void:
	var img := Image.create(16, 2, false, Image.FORMAT_RGBA8)
	for y in 2:
		for x in 16:
			img.set_pixel(x, y, Color.WHITE if (x + y) % 2 == 0 else Color(0.08, 0.08, 0.08))
	var tex := ImageTexture.create_from_image(img)
	var d := direction_at(0)
	var nrm := Vector2(-d.y, d.x)
	var base := points[0]
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
	mi.name = "StartLine"
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
	for k in range(lo, hi):
		var i := ((k % n) + n) % n
		var q := Geometry2D.get_closest_point_to_segment(p, points[i], points[(i + 1) % n])
		var d := p.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best_i = i
	return {"idx": best_i, "dist": sqrt(best_d)}


func on_road(p: Vector2, hint: int) -> bool:
	if city != null and (free_mode or nearest(p, hint).dist > width * 0.5):
		return city.on_any_street(p)
	return nearest(p, hint).dist <= width * 0.5


func start_positions(count: int) -> Array:
	var base := points[0]
	var d := direction_at(0)
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
	for h in spec.get("hazards", []):
		var i := int(floor(float(h.get("at", 0.0)) * n)) % n
		var d := direction_at(i)
		var nrm := Vector2(-d.y, d.x)
		out.append({"kind": String(h.get("kind", "fire")), "pos": points[i] + nrm * float(h.get("side", 0.0)) * width * 0.5,
			"radius": float(h.get("radius", 150.0)), "period": float(h.get("period", 0.0)),
			"duty": float(h.get("duty", 0.5)), "phase": float(h.get("phase", 0.0)),
			"laps": h.get("laps", []), "per_lap": h.get("per_lap", {})})
	return out


func item_positions() -> Array:
	var out := []
	var step := maxi(8, int(n / (5.0 * scale_k)))
	var i := step
	while i < n:
		var d := direction_at(i)
		var nrm := Vector2(-d.y, d.x)
		for k in [-1, 0, 1]:
			out.append(points[i] + nrm * (k * width * 0.3))
		i += step
	return out


const WINDOW := 10

# Move the kart's waypoint pointer forward; returns true on a new lap.
func advance(kart) -> bool:
	var thresh2 := pow(width * 0.7, 2)
	var best := -1
	for k in WINDOW:
		var idx: int = (kart.next_wp + k) % n
		var kp: Vector2 = kart.pos
		if kp.distance_squared_to(points[idx]) < thresh2:
			best = k
	if best < 0:
		return false
	var new_lap := false
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
