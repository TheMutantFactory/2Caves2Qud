# HUD minimap. City tracks: a player-centred window of the street grid with
# the route in yellow and barricades in red. Synthetic tracks: the whole loop.
# Racers are dots; the wizard is white with a heading tick.
class_name MiniMap
extends Control

var race = null
var span_px := 22400.0   # world px shown edge to edge on city maps (700 m at 32 px/m)
var north_up := true


func _ready() -> void:
	clip_contents = true


func _world_to_map(p: Vector2, center: Vector2, scale: float) -> Vector2:
	return (p - center) * scale + size * 0.5


func _draw() -> void:
	if race == null or race.track == null:
		return
	var track = race.track
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.62))
	var center: Vector2
	var scale: float
	if track.city != null or track.n == 0:   # city maps and open fields: a window around the player
		center = race.hero_pos if race.has_method("forward_dir") else race.player.pos
		scale = size.x / span_px
	else:
		center = track.size * 0.5
		scale = minf(size.x / track.size.x, size.y / track.size.y) * 0.92

	var win_lo := center - size * 0.5 / scale
	var win_hi := center + size * 0.5 / scale

	if track.city != null:
		for st in track.city.streets:
			var pts: PackedVector2Array = st["points"]
			var visible := false
			for p in pts:
				if p.x >= win_lo.x and p.x <= win_hi.x and p.y >= win_lo.y and p.y <= win_hi.y:
					visible = true
					break
			if not visible:
				continue
			var mapped := PackedVector2Array()
			for p in pts:
				mapped.append(_world_to_map(p, center, scale))
			var w := maxf(1.0, float(st["width"]) * scale)
			draw_polyline(mapped, Color(0.42, 0.42, 0.48), w)

	# the route
	var route := PackedVector2Array()
	for p in track.points:
		route.append(_world_to_map(p, center, scale))
	if route.size() > 1:
		route.append(route[0])
		var rw := maxf(2.0, track.width * scale) if track.city != null else 3.0
		draw_polyline(route, Color(1.0, 0.93, 0.35, 0.9), rw)

	# barricades
	if track.city != null and not track.free_mode:
		for wall in track.barricade_walls:
			var a: Vector2 = wall[0]
			var b: Vector2 = wall[1]
			if a.x < win_lo.x or a.x > win_hi.x or a.y < win_lo.y or a.y > win_hi.y:
				continue
			draw_line(_world_to_map(a, center, scale), _world_to_map(b, center, scale), Color(0.9, 0.2, 0.2), 2.0)

	# shinies
	for box in race.item_boxes:
		if not box.visible:
			continue
		var p: Vector2 = box.get_meta("pos")
		var m := _world_to_map(p, center, scale)
		if m.x < 0 or m.y < 0 or m.x > size.x or m.y > size.y:
			continue
		var kind: String = box.get_meta("kind")
		var col := Color(0.47, 0.78, 1.0) if kind == "spell" else (Color(0.95, 0.3, 0.35) if kind == "heart" else Color(0.8, 0.7, 0.4))
		draw_circle(m, 2.0, col)

	if race.has_method("minimap_dots"):
		for d in race.minimap_dots():
			var m: Vector2 = _world_to_map(d[0], center, scale)
			if m.x < 0 or m.y < 0 or m.x > size.x or m.y > size.y:
				continue
			draw_circle(m, 2.5, d[1])

	# racers
	for kart in race.karts:
		var m := _world_to_map(kart.pos, center, scale)
		if kart.is_player:
			continue
		draw_circle(m, 3.5, Color(0.9, 0.11, 0.14))
	var ppos: Vector2 = race.hero_pos if race.has_method("forward_dir") else race.player.pos
	var pm := _world_to_map(ppos, center, scale)
	draw_circle(pm, 5.0, Color.WHITE)
	var f: Vector2 = race.forward_dir() if race.has_method("forward_dir") else race.player.forward()
	draw_line(pm, pm + f * 12.0, Color.WHITE, 2.0)

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.9, 0.86, 0.78), false, 2.0)
	if track.city != null:
		draw_string(QUD.font(), Vector2(8, 20), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.85, 0.85, 0.85))
		draw_string(QUD.font(), Vector2(size.x - 60, size.y - 8), "%dm" % int(span_px / 32.0 / 4.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.7, 0.7))
		draw_line(Vector2(size.x - 70, size.y - 14), Vector2(size.x - 70 + size.x * 0.25, size.y - 14), Color(0.7, 0.7, 0.7), 2.0)
