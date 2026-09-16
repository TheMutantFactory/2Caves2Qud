# The Qud surface as the ground (docs/overland.md). A course is built exactly as on its
# canvas — the road, curbs, branches, hazards, start line — but the ground under it is the
# real Qud world: one CHUNK per Qud zone (80 x 25 cells, one cell = CELL px), streamed round
# the karts from the store's world/<gameId>/ export (tools/qud_overland.py, fed by the Raves
# bridge's bake). The engine origin is the ANCHOR zone's origin, so the course keeps its
# canvas coordinates and every chunk is placed at (its global px - origin_px).
#
# Paving: a wall or solid object within half the road width + a verge of the route is not
# built (the same rule as tools/qud_world.pave). Walls stand as voxel runs (QudVox), floors
# lie flat, liquids are water cells, everything else is a billboard in a MultiMesh per art.
# Flat first: elevation, profile, camber and lean are stripped from the spec.
#
# Probes: `overland: chunks=N wanted=M loads=L unloads=U` whenever the set changes, and
# `overland_test: ...` from stream_test() (--stream_test): the streaming policy checked
# against itself along the route.
class_name QudWorld
extends Track

const CELL := 60.0
const ZONE_W := 80
const ZONE_H := 25
const PARASANG := 3
const WORLD_COLS := 240      # 80 parasangs x 3 zones
const WORLD_ROWS := 75       # 25 x 3
const TILE_W_PX := 48.0      # a Qud tile x3, as the dressing sprites
const TILE_H_PX := 72.0
const WALL_PUSH := 6.0

var gid := ""
var world_root := ""             # "world/<gid>/"
var index := {}
var atlas: Texture2D = null
var atlas_cols := 16
var atlas_rows := 1
var anchor := ""
var origin_px := Vector2.ZERO    # world px of the engine origin
var radius := 1
var verge := 60.0
var loaded := {}                 # zid -> {node, walls: Array[Vector2i], lights: Array}
var wall_cells := {}             # global cell (Vector2i) -> true, for resolve()
var lights: Array = []           # [{pos: Vector2 (local px), radius: int}] for the light bake
var loads := 0
var unloads := 0
var wanted_now: Array = []
var route_box := Rect2()
var _last_probe := ""
var _mats := {}                  # art -> StandardMaterial3D, shared across chunks
var _floor_mat: StandardMaterial3D = null
var _base_color := Color(0.5, 0.45, 0.35)
var light := OverlandLight.new()  # the clock, the keyframes, the per-cell bake (G8)
var light_ready := false


# ---------------------------------------------------------------- zone maths (mirrors tools/qud_world.py)

static func parse_zone(zid: String) -> Array:
	var parts := zid.split(".")
	var n := parts.size()
	return [int(parts[n - 5]), int(parts[n - 4]), int(parts[n - 3]), int(parts[n - 2]), int(parts[n - 1])]


static func zone_name(col: int, row: int, z := 10) -> String:
	@warning_ignore("integer_division")
	return "JoppaWorld.%d.%d.%d.%d.%d" % [col / PARASANG, row / PARASANG, col % PARASANG, row % PARASANG, z]


static func zone_col_row(zid: String) -> Vector2i:
	var c := parse_zone(zid)
	return Vector2i(c[0] * PARASANG + c[2], c[1] * PARASANG + c[3])


static func zone_origin_px(zid: String) -> Vector2:
	var cr := zone_col_row(zid)
	return Vector2(cr.x * ZONE_W * CELL, cr.y * ZONE_H * CELL)


static func zone_at(px: Vector2) -> String:
	if px.x < 0.0 or px.y < 0.0:
		return ""
	var col := int(px.x / (ZONE_W * CELL))
	var row := int(px.y / (ZONE_H * CELL))
	if col >= WORLD_COLS or row >= WORLD_ROWS:
		return ""
	return zone_name(col, row)


static func zones_within(px: Vector2, r: int) -> Array:
	var zid := zone_at(px)
	if zid == "":
		return []
	var cr := zone_col_row(zid)
	var out := []
	for c in range(cr.x - r, cr.x + r + 1):
		for rr in range(cr.y - r, cr.y + r + 1):
			if c >= 0 and c < WORLD_COLS and rr >= 0 and rr < WORLD_ROWS:
				out.append(zone_name(c, rr))
	return out


# ---------------------------------------------------------------- setup

func setup_overland(k: String, anchor_zid: String, rng: RandomNumberGenerator) -> void:
	key = k
	spec = (Shared.tracks[k] as Dictionary).duplicate(true)
	track_name = String(spec["name"]) + "  overland"
	spec["elevation"] = 0.0
	for drop in ["profile", "camber", "lean", "dressing", "floor_mode", "steps"]:
		spec.erase(drop)
	var wi: Dictionary = Shared.load_json(QUD.ROOT + "world/index.json")
	gid = String(wi.get("latest", ""))
	world_root = "world/%s/" % gid
	index = Shared.load_json(QUD.ROOT + world_root + "index.json")
	var anchors: Dictionary = index.get("anchors", {})
	anchor = anchor_zid if anchor_zid != "" else String(anchors.get(k, "JoppaWorld.10.21.2.0.10"))
	origin_px = zone_origin_px(anchor)
	radius = int(Shared.t(["overland", "radius"], 1))
	verge = float(Shared.t(["overland", "verge_px"], 60.0))
	var at: Dictionary = index.get("atlas", {})
	atlas_cols = maxi(1, int(at.get("cols", 16)))
	atlas_rows = maxi(1, int(at.get("rows", 1)))
	atlas = QUD.texture(world_root + "ground.png")
	# the floor and the road are Qud's (the export writes both): the viridian an unpainted
	# cell shows, and a DirtPath's dots for the road, not the course's canvas colours
	_base_color = Color(String(index.get("floor_color", "0f3b3a")))
	spec["road_tex"] = world_root + String(index.get("road", "road.png"))
	_build_loop(rng)
	var half := width * 0.5
	route_box = Rect2(points[0], Vector2.ZERO)
	for p in points:
		route_box = route_box.expand(p)
	for br in branches:
		for p in br["pts"]:
			route_box = route_box.expand(p)
	route_box = route_box.grow(half + verge + CELL)
	_build_paving(half, half + verge)
	print("overland: %s anchored at %s (origin %d,%d px), %d zones baked, radius %d, road %d px, paving %d road cells, %d verge cells" % [
		key, anchor, int(origin_px.x), int(origin_px.y), (index.get("zones", []) as Array).size(), radius, int(width), road_cells.size(), verge_cells.size()])


var road_cells := {}     # global cell -> true: under the road (everything but floors and water goes)
var verge_cells := {}    # global cell -> true: within the verge too (walls and solids go)


## The paved cells, once: every cell whose centre lies within `soft` px of the route is road,
## within `hard` px is verge. Walked from the route samples (and live branches) with a disc
## per sample; the samples sit closer than a cell, so a disc a half-cell wider than the reach
## covers the segments between them. Chunk loads then look cells up instead of scanning the
## route per object — with the grass standing (~500 sprites a zone) that scan cost a frame.
func _build_paving(soft: float, hard: float) -> void:
	road_cells.clear()
	verge_cells.clear()
	var pts: Array = [points]
	for br in branches:
		pts.append(br["pts"])
	var r_cells := int(ceil((hard + CELL * 0.71) / CELL))
	for arr in pts:
		for p in arr:
			var gp: Vector2 = Vector2(p) + origin_px
			var cx := int(floor(gp.x / CELL))
			var cy := int(floor(gp.y / CELL))
			for dy in range(-r_cells, r_cells + 1):
				for dx in range(-r_cells, r_cells + 1):
					var centre := Vector2((cx + dx + 0.5) * CELL, (cy + dy + 0.5) * CELL)
					var d := centre.distance_to(gp)
					var g := Vector2i(cx + dx, cy + dy)
					if d <= hard + CELL * 0.71:
						verge_cells[g] = true
					if d <= soft + CELL * 0.71:
						road_cells[g] = true


# The ground, scenery and dressing are the world's; the loop builder's own are skipped.
func _build_ground() -> void:
	pass


func _build_scenery(_rng: RandomNumberGenerator) -> void:
	pass


func _build_dressing(_rng: RandomNumberGenerator) -> void:
	pass


# ---------------------------------------------------------------- streaming

## Keep every zone within `radius` of any position loaded and nothing else. Loads at most
## `max_loads` chunks per call (one per frame in play; many at setup), so a hitch is bounded.
func stream(positions: Array, max_loads := 1) -> void:
	var want := {}
	for p in positions:
		for z in zones_within(Vector2(p) + origin_px, radius):
			want[z] = true
	for z in loaded.keys():
		if not want.has(z):
			_unload_chunk(z)
	var done := 0
	for z in want:
		if loaded.has(z):
			continue
		if done >= max_loads:
			break
		_load_chunk(z)
		done += 1
	# a load a frame, and a build step a frame; at setup (max_loads 99) everything at once
	_run_steps(99 if max_loads >= 99 else 1)
	wanted_now = want.keys()
	var line := "overland: chunks=%d wanted=%d loads=%d unloads=%d" % [loaded.size(), want.size(), loads, unloads]
	if line != _last_probe:
		_last_probe = line
		print(line)


func chunk_of(local_px: Vector2) -> String:
	return zone_at(local_px + origin_px)


## The streaming policy checked against itself: walk the route in `steps`, stream at each
## stop until settled, and require loaded == wanted, every wanted zone within the radius and
## none beyond it. Prints one `overland_test:` line the score script reads.
func stream_test(steps := 8) -> bool:
	var ok := true
	var max_chunks := 0
	var at := ""
	for s in steps:
		@warning_ignore("integer_division")
		var i := (s * n) / steps
		var p := points[i]
		stream([p], 99)
		var here := chunk_of(p)
		var cr := zone_col_row(here)
		var want := {}
		for z in zones_within(p + origin_px, radius):
			want[z] = true
		for z in loaded:
			var zc := zone_col_row(z)
			if absi(zc.x - cr.x) > radius or absi(zc.y - cr.y) > radius:
				ok = false
				print("overland_test: %s loaded beyond radius at step %d (%s)" % [z, s, here])
			if not want.has(z):
				ok = false
		for z in want:
			if not loaded.has(z):
				ok = false
				print("overland_test: %s wanted but not loaded at step %d" % [z, s])
		max_chunks = maxi(max_chunks, loaded.size())
		at = here
	var cap := (2 * radius + 1) * (2 * radius + 1)
	if max_chunks > cap:
		ok = false
	print("overland_test: ok=%s steps=%d max_chunks=%d cap=%d loads=%d unloads=%d last=%s" % [str(ok).to_lower(), steps, max_chunks, cap, loads, unloads, at])
	return ok


# ---------------------------------------------------------------- chunks

func _load_chunk(zid: String) -> void:
	var holder := Node3D.new()
	holder.name = zid.replace(".", "_")
	add_child(holder)
	var local0 := zone_origin_px(zid) - origin_px
	var rec := {"node": holder, "walls": [], "lights": [], "local0": local0, "props": [], "dark": null}
	loaded[zid] = rec
	loads += 1
	_base_plane(holder, local0)
	var d: Dictionary = Shared.load_json(QUD.ROOT + world_root + zid + ".json")
	if d.is_empty():
		return   # outside the baked region: bare ground
	var w := int(d.get("w", ZONE_W))
	var h := int(d.get("h", ZONE_H))
	var pal: Array = d.get("palette", [])
	var cr := zone_col_row(zid)
	var wall_grid := {}
	var floors := {}
	var props := {}
	var water := []
	var creatures := []
	var paved := 0
	for o in d.get("objs", []):
		var x := int(o[0])
		var y := int(o[1])
		var p: Dictionary = pal[int(o[2])]
		var kind := String(p.get("kind", "skip"))
		if kind == "skip":
			continue
		var c := local0 + Vector2((x + 0.5) * CELL, (y + 0.5) * CELL)
		# the road takes everything on it but floors and water; the verge takes the hard things
		var hard := bool(p.get("wall", false)) or bool(p.get("solid", false))
		var g := Vector2i(cr.x * ZONE_W + x, cr.y * ZONE_H + y)
		if (hard and verge_cells.has(g)) or (kind != "floor" and kind != "water" and road_cells.has(g)):
			paved += 1
			continue
		match kind:
			"wall":
				wall_grid[Vector2i(x, y)] = int(o[2])
			"floor":
				_push(floors, String(p.get("art", "")), c)
			"water":
				water.append([c, Color.html(String(p.get("color", "3a6fd0")))])
			"creature":
				creatures.append([c, String(p.get("art", ""))])
			_:
				# grouped by art AND size: Qud's light-occluders (trees, brinestalk) stand at x2
				_push(props, "%s@%d" % [String(p.get("art", "")), int(p.get("scale", 1))], c)
		if int(p.get("radius", 0)) > 0:
			rec["lights"].append({"pos": c, "cell": Vector2i(x, y), "radius": int(p["radius"])})
	if paved > 0:
		print("overland: %s paved %d objects under the road" % [zid, paved])
	# The rest is built one STEP per frame (stream() runs them), so a chunk arriving during a
	# race costs a few small frames instead of one long one: the floor, then walls and water,
	# then the standing sprites, then the creatures and the light bake.
	rec["steps"] = [
		func() -> void: _build_floor(holder, local0, w, h, d.get("ground", [])),
		func() -> void:
			_build_walls(holder, local0, cr, wall_grid, pal, rec)
			_build_floor_art(holder, floors)
			_build_water(holder, water),
		func() -> void: _build_props(holder, props, local0, rec),
		func() -> void:
			_build_creatures(holder, creatures)
			lights.append_array(rec["lights"])
			if light.bakes > 0:
				_bake_chunk(rec, light.last_seg),   # a chunk streamed in after a bake matches its neighbours
	]


## Run pending build steps, at most `budget` across all loading chunks (one a frame in play).
func _run_steps(budget: int) -> void:
	for zid in loaded:
		var rec: Dictionary = loaded[zid]
		var steps: Array = rec.get("steps", [])
		while budget > 0 and not steps.is_empty():
			var step: Callable = steps.pop_front()
			step.call()
			budget -= 1
		if budget <= 0:
			return


func building() -> int:
	var n := 0
	for zid in loaded:
		if not (loaded[zid].get("steps", []) as Array).is_empty():
			n += 1
	return n


func _unload_chunk(zid: String) -> void:
	var rec: Dictionary = loaded[zid]
	var holder: Node3D = rec["node"]
	rec["steps"] = []   # whatever was still to be built for it is not
	for g in rec["walls"]:
		wall_cells.erase(g)
	var keep := []
	for b in scenery_blocks:
		if (b["node"] as Node).get_parent() != holder:
			keep.append(b)
	scenery_blocks = keep
	if not rec["lights"].is_empty():
		var kl := []
		for l in lights:
			if not rec["lights"].has(l):
				kl.append(l)
		lights = kl
	holder.queue_free()
	loaded.erase(zid)
	unloads += 1


func _push(groups: Dictionary, art: String, c: Vector2) -> void:
	if art == "" or art.begins_with("@"):
		return
	if not groups.has(art):
		groups[art] = []
	groups[art].append(c)




# ---------------------------------------------------------------- builders

func _base_plane(holder: Node3D, local0: Vector2) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := local0
	var b := local0 + Vector2(ZONE_W * CELL, 0)
	var c := local0 + Vector2(ZONE_W * CELL, ZONE_H * CELL)
	var d := local0 + Vector2(0, ZONE_H * CELL)
	for tri in [[a, b, c], [a, c, d]]:
		for p in tri:
			st.set_uv(p / TILE_PX)
			st.add_vertex(to3(p, -0.5))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Base"
	mi.mesh = st.commit()
	mi.material_override = _material(null, _base_color)
	holder.add_child(mi)


func _build_floor(holder: Node3D, local0: Vector2, w: int, h: int, ground: Array) -> void:
	if atlas == null or ground.is_empty():
		return
	if _floor_mat == null:
		_floor_mat = _material(atlas)
		_floor_mat.texture_repeat = false
		_floor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		_floor_mat.alpha_scissor_threshold = 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells := 0
	for y in h:
		for x in w:
			var gi := int(ground[y * w + x])
			if gi < 0:
				continue
			cells += 1
			@warning_ignore("integer_division")
			var u0 := float(gi % atlas_cols) / float(atlas_cols)
			@warning_ignore("integer_division")
			var v0 := float(gi / atlas_cols) / float(atlas_rows)
			var u1 := u0 + 1.0 / float(atlas_cols)
			var v1 := v0 + 1.0 / float(atlas_rows)
			var a := local0 + Vector2(x * CELL, y * CELL)
			var b := a + Vector2(CELL, 0)
			var c := a + Vector2(CELL, CELL)
			var d := a + Vector2(0, CELL)
			for tri in [[a, Vector2(u0, v0), b, Vector2(u1, v0), c, Vector2(u1, v1)], [a, Vector2(u0, v0), c, Vector2(u1, v1), d, Vector2(u0, v1)]]:
				for i in range(0, 6, 2):
					st.set_uv(tri[i + 1])
					st.add_vertex(to3(tri[i], 1.0))
	if cells == 0:
		return
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Floor"
	mi.mesh = st.commit()
	mi.material_override = _floor_mat
	holder.add_child(mi)


func _build_walls(holder: Node3D, local0: Vector2, cr: Vector2i, grid: Dictionary, pal: Array, rec: Dictionary) -> void:
	var placed := 0
	for cell in grid:
		var p: Dictionary = pal[int(grid[cell])]
		var fam := String(p.get("fam", ""))
		if fam == "" or not QudVox.available(fam):
			continue
		var c := Vector2i(cell)
		var horizontal := grid.has(c + Vector2i(-1, 0)) or grid.has(c + Vector2i(1, 0)) or not (grid.has(c + Vector2i(0, -1)) or grid.has(c + Vector2i(0, 1)))
		var a := c.x if horizontal else c.y
		var b := a
		while grid.has(Vector2i(a - 1, c.y) if horizontal else Vector2i(c.x, a - 1)):
			a -= 1
		while grid.has(Vector2i(b + 1, c.y) if horizontal else Vector2i(c.x, b + 1)):
			b += 1
		var along := Vector2.RIGHT if horizontal else Vector2.DOWN
		var facing := Vector2.DOWN if horizontal else Vector2.RIGHT
		var k := (c.x if horizontal else c.y) - a
		var variant := QudVox.run_variant(k, b - a + 1, along, facing)
		var pos := local0 + Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)
		if _wall_block(fam, variant, pos, facing, holder):
			placed += 1
			var g := Vector2i(cr.x * ZONE_W + c.x, cr.y * ZONE_H + c.y)
			wall_cells[g] = true
			rec["walls"].append(g)


static var _billboard_shader: Shader = null


## Standing sprites get the overland billboard shader (facing, the instance tint, darker
## with distance); flat art a plain unshaded material.
func _art_material(art: String, billboard: bool) -> Material:
	var k := art + ("|b" if billboard else "|f")
	if _mats.has(k):
		return _mats[k]
	var tex := QUD.texture(world_root + art)
	if billboard:
		if _billboard_shader == null:
			_billboard_shader = load("res://overland_billboard.gdshader")
		var sm := ShaderMaterial.new()
		sm.shader = _billboard_shader
		sm.set_shader_parameter("tex", tex)
		sm.set_shader_parameter("dark_near", float(Shared.t(["overland", "dark_near_m"], 30.0)))
		sm.set_shader_parameter("dark_far", float(Shared.t(["overland", "dark_far_m"], 150.0)))
		sm.set_shader_parameter("dark_min", float(Shared.t(["overland", "dark_min"], 0.35)))
		_mats[k] = sm
		return sm
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[k] = m
	return m


func _build_floor_art(holder: Node3D, floors: Dictionary) -> void:
	for art in floors:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for c in floors[art]:
			var a: Vector2 = c - Vector2(CELL, CELL) * 0.5
			var b := a + Vector2(CELL, 0)
			var cc := a + Vector2(CELL, CELL)
			var d := a + Vector2(0, CELL)
			for tri in [[a, Vector2(0, 0), b, Vector2(1, 0), cc, Vector2(1, 1)], [a, Vector2(0, 0), cc, Vector2(1, 1), d, Vector2(0, 1)]]:
				for i in range(0, 6, 2):
					st.set_uv(tri[i + 1])
					st.add_vertex(to3(tri[i], 2.0))
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.name = "Floor_" + art.get_file().get_basename()
		mi.mesh = st.commit()
		mi.material_override = _art_material(art, false)
		holder.add_child(mi)


func _build_water(holder: Node3D, water: Array) -> void:
	if water.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cw in water:
		var c: Vector2 = cw[0]
		var col: Color = cw[1]
		col.a = 0.75
		var a := c - Vector2(CELL, CELL) * 0.5
		var b := a + Vector2(CELL, 0)
		var cc := a + Vector2(CELL, CELL)
		var d := a + Vector2(0, CELL)
		for tri in [[a, b, cc], [a, cc, d]]:
			for p in tri:
				st.set_color(col)
				st.add_vertex(to3(p, 2.5))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.2
	mi.material_override = m
	holder.add_child(mi)


func _build_props(holder: Node3D, props: Dictionary, local0: Vector2, rec: Dictionary) -> void:
	for key in props:
		var art: String = key.get_slice("@", 0)
		var scale := float(maxi(1, int(key.get_slice("@", 1))))
		var centres: Array = props[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true     # the light bake tints each sprite by its cell (set before the count)
		var quad := QuadMesh.new()
		quad.size = Vector2(TILE_W_PX * U, TILE_H_PX * U) * scale
		mm.mesh = quad
		mm.instance_count = centres.size()
		var cells := PackedInt32Array()
		cells.resize(centres.size())
		for i in centres.size():
			var c: Vector2 = centres[i]
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, to3(c, TILE_H_PX * 0.5 * scale)))
			mm.set_instance_color(i, Color.WHITE)
			cells[i] = int((c.y - local0.y) / CELL) * ZONE_W + int((c.x - local0.x) / CELL)
		var mi := MultiMeshInstance3D.new()
		mi.name = "Props_" + art.get_file().get_basename()
		mi.multimesh = mm
		mi.material_override = _art_material(art, true)
		mi.set_meta("cells", cells)
		holder.add_child(mi)
		rec["props"].append(mi)


func _build_creatures(holder: Node3D, creatures: Array) -> void:
	for ca in creatures:
		var c: Vector2 = ca[0]
		var art: String = ca[1]
		var spr := Sprite3D.new()
		if art.begins_with("unit:"):
			var unit := art.substr(5)
			spr.texture = QUD.unit_idle(unit)
			spr.hframes = maxi(1, int(QUD.unit_info(unit).get("idle_frames", 1)))
		else:
			spr.texture = QUD.texture(world_root + art)
		if spr.texture == null:
			continue
		spr.pixel_size = U
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		var th := float(spr.texture.get_height()) / float(maxi(1, spr.vframes))
		spr.position = to3(c, th * 0.5)
		holder.add_child(spr)


## The unit strip of the region's most common creature of a kind ("flying" / "ground"), from
## the export's census of the bake — what actually lives on this stretch of the map.
func fauna(kind: String) -> String:
	var list: Array = index.get("fauna", {}).get(kind, [])
	for e in list:
		if QUD.has_unit(String(e[1])):
			return String(e[1])
	return ""


# ---------------------------------------------------------------- the light bake (G8)

## Wire the clock to the race's sun and sky. `clock_override` < 0 keeps tuning's start.
func light_setup(clock_override: int) -> void:
	var sun: DirectionalLight3D = null
	var env: Environment = null
	var parent := get_parent()
	if parent != null:
		for ch in parent.get_children():
			if ch is DirectionalLight3D:
				sun = ch
			elif ch is WorldEnvironment:
				env = (ch as WorldEnvironment).environment
	light.setup(Shared.tuning.get("overland", {}), clock_override, sun, env)
	light_ready = true


## Called every physics frame with the race time; bakes when the schedule says so.
func light_step(t: float, free: bool) -> void:
	if not light_ready or not light.due(t, free):
		return
	var seg := light.segment(t)
	light.mark_baked(t, free, seg)
	bake_all(seg)
	print("light: bake #%d seg=%d (%s) daylight=%.2f chunks=%d mode=%s t=%.0f" % [
		light.bakes, seg, OverlandLight.clock_text(seg), OverlandLight.daylight(seg), loaded.size(), "free" if free else "race", t])


func bake_all(seg: int) -> void:
	light.apply_sky(seg)
	for zid in loaded:
		_bake_chunk(loaded[zid], seg)


## One chunk: the darkness mesh over its cells and the tint of its billboards.
func _bake_chunk(rec: Dictionary, seg: int) -> void:
	var grid := light.grid(ZONE_W, ZONE_H, rec["lights"], seg)
	var holder: Node3D = rec["node"]
	var local0: Vector2 = rec["local0"]
	if rec["dark"] != null:
		(rec["dark"] as Node).queue_free()
		rec["dark"] = null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := 0
	for y in ZONE_H:
		for x in ZONE_W:
			var l := grid[y * ZONE_W + x]
			if l >= 0.995:
				continue
			quads += 1
			var col := Color(0, 0, 0, (1.0 - l) * OverlandLight.DARK_MAX)
			var a := local0 + Vector2(x * CELL, y * CELL)
			var b := a + Vector2(CELL, 0)
			var c := a + Vector2(CELL, CELL)
			var d := a + Vector2(0, CELL)
			for tri in [[a, b, c], [a, c, d]]:
				for p in tri:
					st.set_color(col)
					st.add_vertex(to3(p, OverlandLight.DARK_LIFT_PX))
	if quads > 0:
		var mi := MeshInstance3D.new()
		mi.name = "Dark"
		mi.mesh = st.commit()
		mi.material_override = light.dark_material()
		holder.add_child(mi)
		rec["dark"] = mi
	for mmi in rec["props"]:
		var mm: MultiMesh = (mmi as MultiMeshInstance3D).multimesh
		var cells: PackedInt32Array = mmi.get_meta("cells")
		for i in mm.instance_count:
			var l := maxf(grid[cells[i]], 1.0 - OverlandLight.DARK_MAX)
			mm.set_instance_color(i, Color(l, l, l))


# ---------------------------------------------------------------- collision

func resolve(p: Vector2, r: float) -> Dictionary:
	var base := super.resolve(p, r)
	if base["hit"]:
		return base
	var gp := p + origin_px
	var cx := int(floor(gp.x / CELL))
	var cy := int(floor(gp.y / CELL))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var g := Vector2i(cx + dx, cy + dy)
			if not wall_cells.has(g):
				continue
			var r0 := Vector2(g.x * CELL, g.y * CELL) - origin_px
			var q := Vector2(clampf(p.x, r0.x, r0.x + CELL), clampf(p.y, r0.y, r0.y + CELL))
			var d := p.distance_to(q)
			if d < r + WALL_PUSH:
				var nrm := (p - q).normalized() if d > 0.001 else Vector2.DOWN
				return {"hit": true, "pos": q + nrm * (r + WALL_PUSH + 0.5), "normal": nrm}
	return base
