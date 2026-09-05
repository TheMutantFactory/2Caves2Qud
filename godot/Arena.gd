# One of the game's generated realms as a walkable arena: walls, floor and chasms from
# the dump's grid, at any tile size. Survivors uses it at twice the Gauntlet's tile
# (four times the area). Grid helpers, a flow field toward a goal, and the dump's units,
# lairs and props at their tile centres.
class_name Arena
extends Node3D

var tile_px := 100.0
var level := {}
var size := 0
var grid: Array = []
var walk: Array = []       # floor tiles
var passable: Array = []   # floor or chasm (flyers)
var flow: Array = []
var flow_goal := Vector2(-1, -1)


func load_realm(realm: int, rng: RandomNumberGenerator, file := "") -> bool:
	var opts := Shared.realm_options(realm)
	if opts.is_empty():
		return false
	var pick: Dictionary = opts[rng.randi_range(0, opts.size() - 1)]
	if file != "":
		for o in opts:
			if String(o["file"]) == file:
				pick = o
	var d := Shared.load_realm(String(pick["file"]))
	if d.is_empty():
		return false
	level = d
	size = int(d["size"])
	grid = d["grid"]
	walk = []
	passable = []
	for y in size:
		var wr := []
		var pr := []
		var row: String = grid[y]
		for x in size:
			var c := row[x]
			wr.append(c == ".")
			pr.append(c != "#")
		walk.append(wr)
		passable.append(pr)
	return true


func px_size() -> float:
	return size * tile_px


func tile_at(p: Vector2) -> Vector2i:
	return Vector2i(int(p.x / tile_px), int(p.y / tile_px))


func tile_center(x: int, y: int) -> Vector2:
	return Vector2((x + 0.5) * tile_px, (y + 0.5) * tile_px)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size and c.y < size


func can_stand(p: Vector2, radius: float, flying: bool) -> bool:
	for off in [Vector2(-radius, -radius), Vector2(radius, -radius), Vector2(-radius, radius), Vector2(radius, radius), Vector2.ZERO]:
		var c := tile_at(p + off)
		if not in_bounds(c):
			return false
		if flying:
			if not passable[c.y][c.x]:
				return false
		elif not walk[c.y][c.x]:
			return false
	return true


func blocks_shot(p: Vector2) -> bool:
	var c := tile_at(p)
	return not in_bounds(c) or not passable[c.y][c.x]


# Try the move, then each axis alone, so walls slide.
func try_move(p: Vector2, step: Vector2, radius: float, flying: bool) -> Vector2:
	if can_stand(p + step, radius, flying):
		return p + step
	if can_stand(p + Vector2(step.x, 0), radius, flying):
		return p + Vector2(step.x, 0)
	if can_stand(p + Vector2(0, step.y), radius, flying):
		return p + Vector2(0, step.y)
	return p


func update_flow(goal: Vector2) -> void:
	flow_goal = goal
	flow = []
	for y in size:
		var r := []
		for x in size:
			r.append(-1)
		flow.append(r)
	var start := tile_at(goal)
	if not in_bounds(start):
		return
	var queue := [start]
	flow[start.y][start.x] = 0
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var d: int = flow[c.y][c.x]
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + off
			if not in_bounds(n) or not passable[n.y][n.x] or flow[n.y][n.x] >= 0:
				continue
			flow[n.y][n.x] = d + 1
			queue.append(n)


func flow_dir(p: Vector2, flying: bool) -> Vector2:
	var c := tile_at(p)
	if not in_bounds(c) or flow.is_empty():
		return (flow_goal - p).normalized()
	var here: int = flow[c.y][c.x]
	if here <= 0:
		return (flow_goal - p).normalized()
	var best := here
	var target := Vector2i(-1, -1)
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var n: Vector2i = c + off
		if not in_bounds(n):
			continue
		var v: int = flow[n.y][n.x]
		if v < 0 or v >= best:
			continue
		if not flying and not walk[n.y][n.x]:
			continue
		if off.x != 0 and off.y != 0 and (not passable[c.y][n.x] or not passable[n.y][c.x]):
			continue
		best = v
		target = n
	if target.x < 0:
		return (flow_goal - p).normalized()
	return (tile_center(target.x, target.y) - p).normalized()


func to3(p: Vector2, lift_px := 0.0) -> Vector3:
	return Vector3(p.x * Track.U, lift_px * Track.U, p.y * Track.U)


func start_pos() -> Vector2:
	var st: Array = level.get("start", [size / 2, size / 2])
	return tile_center(int(st[0]), int(st[1]))


# ---------------------------------------------------------------- build

func _mat(tex: Texture2D, color := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if tex != null:
		m.albedo_texture = tex
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.albedo_color = color
	m.metallic_specular = 0.0
	m.roughness = 1.0
	return m


func _tile_texture(x: int, y: int, kind: String) -> Texture2D:
	var ts: String = level["tileset"]
	var chasm: String = level["chasm"]
	var ov: Dictionary = level.get("tile_overrides", {})
	var key := "%d,%d" % [x, y]
	if ov.has(key):
		ts = String(ov[key][0])
		chasm = String(ov[key][1])
	if kind == "floor":
		var tex := QUD.texture("tiles/floor_%s.png" % ts)
		return tex if tex != null else QUD.texture("tiles/floor_stone.png")
	if kind == "chasm":
		return QUD.texture("tiles/chasm_%s.png" % chasm)
	var w := QUD.texture("tiles/%s_wall_%d.png" % [ts, 1 + (x * 7 + y * 13) % 4])
	return w if w != null else QUD.texture("tiles/brick_wall_1.png")


func _group(groups: Dictionary, tex: Texture2D) -> SurfaceTool:
	if not groups.has(tex):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		groups[tex] = st
	return groups[tex]


func build() -> void:
	var U := Track.U
	var T := tile_px
	var groups := {}
	var wall_h := T * 0.28 * U   # low walls: the camera must see the wizard behind them
	var uvr := T / 60.0          # repeat the 60 px tile art across the cell
	for y in size:
		for x in size:
			var c: String = grid[y][x]
			var x0 := x * T * U
			var x1 := (x + 1) * T * U
			var z0 := y * T * U
			var z1 := (y + 1) * T * U
			if c == "#":
				var st: SurfaceTool = _group(groups, _tile_texture(x, y, "wall"))
				var corners := [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)]
				for i in 4:
					var a: Vector3 = corners[i]
					var b: Vector3 = corners[(i + 1) % 4]
					var at := a + Vector3(0, wall_h, 0)
					var bt := b + Vector3(0, wall_h, 0)
					st.set_uv(Vector2(0, 1)); st.add_vertex(a)
					st.set_uv(Vector2(uvr, 0)); st.add_vertex(bt)
					st.set_uv(Vector2(uvr, 1)); st.add_vertex(b)
					st.set_uv(Vector2(0, 1)); st.add_vertex(a)
					st.set_uv(Vector2(0, 0)); st.add_vertex(at)
					st.set_uv(Vector2(uvr, 0)); st.add_vertex(bt)
				var tl := Vector3(x0, wall_h, z0)
				var tr := Vector3(x1, wall_h, z0)
				var br := Vector3(x1, wall_h, z1)
				var bl := Vector3(x0, wall_h, z1)
				st.set_uv(Vector2(0, 0)); st.add_vertex(tl)
				st.set_uv(Vector2(uvr, 0)); st.add_vertex(tr)
				st.set_uv(Vector2(uvr, uvr)); st.add_vertex(br)
				st.set_uv(Vector2(0, 0)); st.add_vertex(tl)
				st.set_uv(Vector2(uvr, uvr)); st.add_vertex(br)
				st.set_uv(Vector2(0, uvr)); st.add_vertex(bl)
			else:
				var depth := 0.0 if c == "." else -T * 0.4 * U
				var st: SurfaceTool = _group(groups, _tile_texture(x, y, "floor" if c == "." else "chasm"))
				var a := Vector3(x0, depth, z0)
				var b := Vector3(x1, depth, z0)
				var cc := Vector3(x1, depth, z1)
				var d := Vector3(x0, depth, z1)
				st.set_uv(Vector2(0, 0)); st.add_vertex(a)
				st.set_uv(Vector2(uvr, 0)); st.add_vertex(b)
				st.set_uv(Vector2(uvr, uvr)); st.add_vertex(cc)
				st.set_uv(Vector2(0, 0)); st.add_vertex(a)
				st.set_uv(Vector2(uvr, uvr)); st.add_vertex(cc)
				st.set_uv(Vector2(0, uvr)); st.add_vertex(d)
				if c == "~":
					for pair in [[a, b], [b, cc], [cc, d], [d, a]]:
						var p0: Vector3 = pair[0]
						var p1: Vector3 = pair[1]
						var q0 := Vector3(p0.x, 0, p0.z)
						var q1 := Vector3(p1.x, 0, p1.z)
						st.set_uv(Vector2(0, 0)); st.add_vertex(q0)
						st.set_uv(Vector2(uvr, 0)); st.add_vertex(q1)
						st.set_uv(Vector2(uvr, 1)); st.add_vertex(p1)
						st.set_uv(Vector2(0, 0)); st.add_vertex(q0)
						st.set_uv(Vector2(uvr, 1)); st.add_vertex(p1)
						st.set_uv(Vector2(0, 1)); st.add_vertex(p0)
	for tex in groups:
		var st: SurfaceTool = groups[tex]
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _mat(tex)
		add_child(mi)
	var apron := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size * T * U * 3, size * T * U * 3)
	quad.orientation = PlaneMesh.FACE_Y
	apron.mesh = quad
	apron.position = Vector3(size * T * U / 2, -0.05, size * T * U / 2)
	apron.material_override = _mat(null, Color(0.03, 0.02, 0.05))
	add_child(apron)
