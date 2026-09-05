# A real street grid from shared/maps/<key>.json (OpenStreetMap, ODbL) and
# random closed routes through it. Units are world px, y down.
class_name CityMap
extends RefCounted

var key := ""
var display_name := ""
var size := Vector2(1000, 1000)
var px_per_m := 8.0
var streets: Array = []      # {name, kind, oneway, width, from, to, points: PackedVector2Array}
var junctions := {}          # id -> {pos: Vector2, streets: Array[int]}
var buildings: Array = []    # {name, height, points: PackedVector2Array}
var cell := 600.0
var grid := {}               # Vector2i -> Array of [street index, segment index]
var bgrid := {}              # Vector2i -> Array of building indices (by bounding box)


static func load(p_key: String) -> CityMap:
	var path := "res://qud/shared/maps/%s.json" % p_key
	if not FileAccess.file_exists(path):
		push_error("CityMap: missing %s (run tools/export_godot_assets.py)" % path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return null
	var m := CityMap.new()
	m.key = p_key
	m.display_name = String(d["meta"].get("name", p_key))
	m.size = Vector2(float(d["meta"]["size"][0]), float(d["meta"]["size"][1]))
	m.px_per_m = float(d["meta"].get("px_per_m", 8.0))
	for st in d["streets"]:
		var pts := PackedVector2Array()
		for p in st["points"]:
			pts.append(Vector2(float(p[0]), float(p[1])))
		m.streets.append({"name": String(st.get("name", "")), "kind": String(st.get("kind", "")),
			"oneway": bool(st.get("oneway", false)), "width": float(st.get("width", 120.0)),
			"from": int(st["from"]), "to": int(st["to"]), "points": pts})
	for j in d["junctions"]:
		var idx := []
		for i in j["streets"]:
			idx.append(int(i))
		m.junctions[int(j["id"])] = {"pos": Vector2(float(j["pos"][0]), float(j["pos"][1])), "streets": idx}
	for b in d["buildings"]:
		var pts := PackedVector2Array()
		for p in b["points"]:
			pts.append(Vector2(float(p[0]), float(p[1])))
		m.buildings.append({"name": String(b.get("name", "")), "height": float(b.get("height", 100.0)), "points": pts})
	m._build_grid()
	return m


func _build_grid() -> void:
	grid.clear()
	bgrid.clear()
	for bi in buildings.size():
		var pts: PackedVector2Array = buildings[bi]["points"]
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in pts:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		buildings[bi]["lo"] = lo
		buildings[bi]["hi"] = hi
		for gx in range(int(lo.x / cell), int(hi.x / cell) + 1):
			for gy in range(int(lo.y / cell), int(hi.y / cell) + 1):
				var c := Vector2i(gx, gy)
				if not bgrid.has(c):
					bgrid[c] = []
				bgrid[c].append(bi)
	for si in streets.size():
		var pts: PackedVector2Array = streets[si]["points"]
		for k in range(pts.size() - 1):
			var a := pts[k]
			var b := pts[k + 1]
			var lo := Vector2i(int(minf(a.x, b.x) / cell), int(minf(a.y, b.y) / cell))
			var hi := Vector2i(int(maxf(a.x, b.x) / cell), int(maxf(a.y, b.y) / cell))
			for gx in range(lo.x, hi.x + 1):
				for gy in range(lo.y, hi.y + 1):
					var c := Vector2i(gx, gy)
					if not grid.has(c):
						grid[c] = []
					grid[c].append([si, k])


# Nearest street to a point: {street, dist, name, width}. dist is to the centreline.
func nearest_street(p: Vector2) -> Dictionary:
	var c := Vector2i(int(p.x / cell), int(p.y / cell))
	var best := INF
	var best_si := -1
	for gx in range(c.x - 1, c.x + 2):
		for gy in range(c.y - 1, c.y + 2):
			var lst = grid.get(Vector2i(gx, gy))
			if lst == null:
				continue
			for entry in lst:
				var si: int = entry[0]
				var k: int = entry[1]
				var pts: PackedVector2Array = streets[si]["points"]
				var q := Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1])
				var d := p.distance_squared_to(q)
				if d < best:
					best = d
					best_si = si
	if best_si < 0:
		return {"street": -1, "dist": INF, "name": "", "width": 0.0}
	return {"street": best_si, "dist": sqrt(best), "name": streets[best_si]["name"], "width": streets[best_si]["width"]}


# Keep a disc of the given radius out of every building. Returns
# {hit: bool, pos: Vector2, normal: Vector2}; pos is the corrected position.
func collide_buildings(p: Vector2, radius: float) -> Dictionary:
	var c := Vector2i(int(p.x / cell), int(p.y / cell))
	var lst = bgrid.get(c)
	if lst == null:
		return {"hit": false, "pos": p, "normal": Vector2.ZERO}
	for bi in lst:
		var b: Dictionary = buildings[bi]
		var lo: Vector2 = b["lo"]
		var hi: Vector2 = b["hi"]
		if p.x < lo.x - radius or p.x > hi.x + radius or p.y < lo.y - radius or p.y > hi.y + radius:
			continue
		var pts: PackedVector2Array = b["points"]
		var inside := Geometry2D.is_point_in_polygon(p, pts)
		var best_d := INF
		var best_q := p
		var best_n := Vector2.ZERO
		var m := pts.size()
		for i in m:
			var a := pts[i]
			var e := pts[(i + 1) % m]
			var q := Geometry2D.get_closest_point_to_segment(p, a, e)
			var d := p.distance_to(q)
			if d < best_d:
				best_d = d
				best_q = q
				var edge := (e - a)
				best_n = Vector2(-edge.y, edge.x).normalized()
		if not inside and best_d >= radius:
			continue
		# outward normal: away from the polygon's interior
		var out_n := (p - best_q).normalized() if (not inside and best_d > 0.001) else best_n
		if inside:
			var probe := best_q + best_n * 2.0
			if Geometry2D.is_point_in_polygon(probe, pts):
				out_n = -best_n
			else:
				out_n = best_n
		return {"hit": true, "pos": best_q + out_n * (radius + 0.5), "normal": out_n}
	return {"hit": false, "pos": p, "normal": Vector2.ZERO}


func on_any_street(p: Vector2) -> bool:
	var n := nearest_street(p)
	return n["street"] >= 0 and float(n["dist"]) <= float(n["width"]) * 0.5


func other_end(si: int, from_id: int) -> int:
	var st: Dictionary = streets[si]
	return int(st["to"]) if int(st["from"]) == from_id else int(st["from"])


func street_points(si: int, from_id: int) -> PackedVector2Array:
	var st: Dictionary = streets[si]
	var pts: PackedVector2Array = st["points"]
	if int(st["from"]) == from_id:
		return pts
	var rev := PackedVector2Array()
	for i in range(pts.size() - 1, -1, -1):
		rev.append(pts[i])
	return rev


func street_length(si: int) -> float:
	var pts: PackedVector2Array = streets[si]["points"]
	var l := 0.0
	for i in range(pts.size() - 1):
		l += pts[i].distance_to(pts[i + 1])
	return l


# Shortest path between junctions (Dijkstra over street lengths), avoiding
# the given junctions and streets. Returns {streets: [int], length} or {}.
func shortest_path(src: int, dst: int, banned_j: Dictionary, banned_s: Dictionary) -> Dictionary:
	var dist := {src: 0.0}
	var prev := {}
	var open := [[0.0, src]]
	while not open.is_empty():
		var best_i := 0
		for i in range(1, open.size()):
			if open[i][0] < open[best_i][0]:
				best_i = i
		var cur: Array = open[best_i]
		open.remove_at(best_i)
		var d: float = cur[0]
		var u: int = cur[1]
		if u == dst:
			break
		if d > float(dist.get(u, INF)):
			continue
		for si in junctions[u]["streets"]:
			if banned_s.has(si):
				continue
			var v := other_end(si, u)
			if banned_j.has(v) and v != dst:
				continue
			var nd := d + street_length(si)
			if nd < float(dist.get(v, INF)):
				dist[v] = nd
				prev[v] = [u, si]
				open.append([nd, v])
	if not dist.has(dst):
		return {}
	var path := []
	var u := dst
	while u != src:
		var pr: Array = prev[u]
		path.append(pr[1])
		u = pr[0]
	path.reverse()
	return {"streets": path, "length": float(dist[dst])}


# A closed route of roughly the wanted length: the shortest path from a start
# junction to a target about 40% of the perimeter away, then the shortest way
# back that avoids the first path. Returns {points, streets, junctions, length, width}
# or an empty dict.
func random_route(rng: RandomNumberGenerator, min_len: float, max_len: float, tries := 60) -> Dictionary:
	var ids := []
	for id in junctions:
		if junctions[id]["streets"].size() >= 3:
			ids.append(id)
	if ids.size() < 2:
		return {}
	var best := {}
	var mid := (min_len + max_len) * 0.5
	for _t in tries:
		var s: int = ids[rng.randi_range(0, ids.size() - 1)]
		var tg: int = ids[rng.randi_range(0, ids.size() - 1)]
		if s == tg:
			continue
		var d0: float = junctions[s]["pos"].distance_to(junctions[tg]["pos"])
		if d0 < min_len * 0.25 or d0 > max_len * 0.45:
			continue
		var a := shortest_path(s, tg, {}, {})
		if a.is_empty():
			continue
		var on_a := {}
		var banned_s := {}
		var u := s
		for si in a["streets"]:
			banned_s[si] = true
			u = other_end(si, u)
			on_a[u] = true
		on_a.erase(tg)
		var b := shortest_path(tg, s, on_a, banned_s)
		if b.is_empty():
			continue
		var streets_out: Array = a["streets"] + b["streets"]
		var total: float = float(a["length"]) + float(b["length"])
		var cand := _route_from_streets(s, streets_out, total)
		if min_len <= total and total <= max_len:
			return cand
		if best.is_empty() or absf(total - mid) < absf(float(best["length"]) - mid):
			best = cand
	return best


func _route_from_streets(start: int, route_streets: Array, length: float) -> Dictionary:
	var pts := PackedVector2Array()
	var jids := [start]
	var jid := start
	var width := INF
	for si in route_streets:
		var sp := street_points(si, jid)
		for i in sp.size():
			if pts.size() == 0 or pts[pts.size() - 1].distance_to(sp[i]) > 1.0:
				pts.append(sp[i])
		jid = other_end(si, jid)
		jids.append(jid)
		width = minf(width, float(streets[si]["width"]))
	if pts.size() > 2 and pts[0].distance_to(pts[pts.size() - 1]) < 1.0:
		pts.remove_at(pts.size() - 1)
	return {"points": pts, "streets": route_streets, "junctions": jids, "length": length, "width": width}


# Side streets to seal at each junction of a route: [{pos, dir, width}] where
# pos is a little way into the side street and dir points along it.
func barricades(route: Dictionary, route_width: float) -> Array:
	var out := []
	var on_route := {}
	for si in route["streets"]:
		on_route[si] = true
	for jid in route["junctions"]:
		var j: Dictionary = junctions[jid]
		for si in j["streets"]:
			if on_route.has(si):
				continue
			var pts := street_points(si, jid)
			if pts.size() < 2:
				continue
			var dir := (pts[1] - pts[0]).normalized()
			out.append({"pos": pts[0] + dir * (route_width * 0.55 + 40.0), "dir": dir, "width": float(streets[si]["width"])})
	return out


# Round the corners of a closed polyline and resample it at ~spacing px.
static func smooth_loop(poly: PackedVector2Array, width: float, spacing: float) -> PackedVector2Array:
	var m := poly.size()
	var rounded := PackedVector2Array()
	for i in m:
		var p := poly[i]
		var prev := poly[(i - 1 + m) % m]
		var next := poly[(i + 1) % m]
		var d1 := p - prev
		var d2 := next - p
		if d1.length() < 1.0 or d2.length() < 1.0:
			continue
		var ang := absf(d1.angle_to(d2))
		if ang < deg_to_rad(15.0):
			rounded.append(p)
			continue
		var r := minf(width * 1.1, minf(d1.length(), d2.length()) * 0.45)
		var a := p - d1.normalized() * r
		var b := p + d2.normalized() * r
		for k in 6:
			var t := k / 5.0
			rounded.append(a.lerp(p, t).lerp(p.lerp(b, t), t))
	var out := PackedVector2Array()
	var carry := 0.0
	var n := rounded.size()
	for i in n:
		var a := rounded[i]
		var b := rounded[(i + 1) % n]
		var seg := a.distance_to(b)
		var t := carry
		while t < seg:
			out.append(a.lerp(b, t / seg))
			t += spacing
		carry = t - seg
	return out
