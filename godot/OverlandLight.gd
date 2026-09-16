# The overland light bake (docs/overland.md G8; tools/qud_light.py is the reference).
#
# Qud's light is daylight by the clock plus each lit source's radius, and nothing else, so
# it is BAKED: per loaded chunk, per cell, light = max(daylight(segment), point lights), laid
# down as one MIX-black mesh over the chunk (alpha = (1 - light) * DARK_MAX) and as the
# instance colours of the billboard MultiMeshes. The sun (Race's DirectionalLight3D) and the
# ambient follow the same clock, so shadows stay real-time and identical on every machine.
#
# RACE MODE bakes once at the start and again only at KEYFRAMES — race seconds at which the
# daylight has moved by more than `max_delta` since the last bake (none for a race in steady
# light). FREE DRIVE rebakes every `rebake_s`. A chunk streamed in after a bake is baked on
# load at the current segment, so it matches its neighbours. Walls (voxel blocks) are not
# dimmed yet: they carry their own vertex colours (Deferred in the plan).
#
# Probes: `light: keys=[...]` at setup (race mode), `light: bake #k seg=S (HH:MM) daylight=D
# chunks=N mode=race|free` per whole-world bake, and `light: bakes=K` in the summary.
class_name OverlandLight
extends RefCounted

const DAY_SEGMENTS := 12000
const START_OF_DAY := 3250
const START_OF_NIGHT := 10000
const DAWN := 1000
const DUSK := 1000
const DARK_MAX := 0.85
const DARK_LIFT_PX := 8.5    # above the road (7.5) and its curbs, under the standing sprites

var start_seg := 9000        # 18:00 — a dusk race by default (tuning overland.clock_start_seg)
var seg_per_s := 500.0 / 60.0   # an hour of Qud a minute (overland.seg_per_s)
var rebake_s := 60.0
var max_delta := 0.1
var horizon_s := 600.0
var keys: Array = []
var next_key := 0
var bakes := 0
var last_seg := -1
var last_free_bake := -INF
var sun: DirectionalLight3D = null
var env: Environment = null
var _dark_mat: StandardMaterial3D = null
var _sky_day := {}     # the canvas sky's colours as built, scaled down with the daylight


static func daylight(seg: int) -> float:
	var s := ((seg % DAY_SEGMENTS) + DAY_SEGMENTS) % DAY_SEGMENTS
	if s < START_OF_DAY or s >= START_OF_NIGHT:
		return 0.0
	if s < START_OF_DAY + DAWN:
		return float(s - START_OF_DAY) / float(DAWN)
	if s >= START_OF_NIGHT - DUSK:
		return float(START_OF_NIGHT - s) / float(DUSK)
	return 1.0


static func point_light(dist_cells: float, radius: int) -> float:
	if radius <= 0:
		return 0.0
	return clampf(1.0 - dist_cells / float(radius), 0.0, 1.0)


func segment(t: float) -> int:
	return ((int(round(start_seg + t * seg_per_s)) % DAY_SEGMENTS) + DAY_SEGMENTS) % DAY_SEGMENTS


## The race seconds at which to re-bake (tools/qud_light.bake_keyframes).
func keyframes() -> Array:
	var out := [0.0]
	var last := daylight(segment(0.0))
	var t := 1.0
	while t <= horizon_s:
		var d := daylight(segment(t))
		if absf(d - last) > max_delta:
			var k := t - 1.0 if t - 1.0 > out[out.size() - 1] else t
			out.append(k)
			last = daylight(segment(k))
		t += 1.0
	return out


func setup(tuning_overland: Dictionary, clock_override: int, race_sun: DirectionalLight3D, race_env: Environment) -> void:
	start_seg = int(tuning_overland.get("clock_start_seg", start_seg))
	if clock_override >= 0:
		start_seg = clock_override
	seg_per_s = float(tuning_overland.get("seg_per_s", seg_per_s))
	rebake_s = float(tuning_overland.get("rebake_s", rebake_s))
	max_delta = float(tuning_overland.get("max_delta", max_delta))
	sun = race_sun
	env = race_env
	_sky_day.clear()
	if env != null and env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
		var sm: ProceduralSkyMaterial = env.sky.sky_material
		_sky_day = {"top": sm.sky_top_color, "horizon": sm.sky_horizon_color,
			"ground_bottom": sm.ground_bottom_color, "ground_horizon": sm.ground_horizon_color, "fog": env.fog_light_color}
	keys = keyframes()
	next_key = 0
	print("light: start seg=%d (%s) keys=%s" % [start_seg, clock_text(start_seg), str(keys)])


static func clock_text(seg: int) -> String:
	var h := (seg * 24) / DAY_SEGMENTS
	var m := ((seg * 24 * 60) / DAY_SEGMENTS) % 60
	return "%02d:%02d" % [h, m]


## Whether a whole-world bake is due at race time t. Race mode follows the keyframes, free
## drive the cadence; the first call always bakes.
func due(t: float, free: bool) -> bool:
	if bakes == 0:
		return true
	if free:
		return t - last_free_bake >= rebake_s
	if next_key < keys.size() and t >= keys[next_key]:
		return true
	return false


func mark_baked(t: float, free: bool, seg: int) -> void:
	bakes += 1
	last_seg = seg
	if free:
		last_free_bake = t
	else:
		while next_key < keys.size() and t >= keys[next_key]:
			next_key += 1
		last_free_bake = t


## Per-cell light for a chunk (w x h) from its sources ([{cell: Vector2i, radius: int}]).
func grid(w: int, h: int, sources: Array, seg: int) -> PackedFloat32Array:
	var base := daylight(seg)
	var g := PackedFloat32Array()
	g.resize(w * h)
	g.fill(base)
	for s in sources:
		var c: Vector2i = s["cell"]
		var r: int = s["radius"]
		if r <= 0:
			continue
		for y in range(maxi(0, c.y - r), mini(h, c.y + r + 1)):
			for x in range(maxi(0, c.x - r), mini(w, c.x + r + 1)):
				var v := point_light(Vector2(x - c.x, y - c.y).length(), r)
				var i := y * w + x
				if v > g[i]:
					g[i] = v
	return g


## The sun and the ambient for a segment: elevation from 10 deg at dawn/dusk to 70 at noon,
## energy with the daylight, a faint moonlit floor at night.
func apply_sky(seg: int) -> void:
	var d := daylight(seg)
	if sun != null:
		var f := clampf(float(seg - START_OF_DAY) / float(START_OF_NIGHT - START_OF_DAY), 0.0, 1.0)
		var elev := 10.0 + 60.0 * sin(PI * f) if d > 0.0 else 10.0
		sun.rotation_degrees = Vector3(-elev, 30.0 + 120.0 * f, 0.0)
		sun.light_energy = 0.15 + 0.95 * d
		sun.light_color = Color(1.0, 0.92, 0.85).lerp(Color(0.8, 0.85, 1.0), 1.0 - d)
	if env != null:
		env.ambient_light_energy = 0.25 + 0.45 * d
		# the sky goes down with the sun too: a quarter of the canvas colours at midnight
		if not _sky_day.is_empty():
			var k := 0.25 + 0.75 * d
			var sm: ProceduralSkyMaterial = env.sky.sky_material
			sm.sky_top_color = (_sky_day["top"] as Color) * k
			sm.sky_horizon_color = (_sky_day["horizon"] as Color) * k
			sm.ground_bottom_color = (_sky_day["ground_bottom"] as Color) * k
			sm.ground_horizon_color = (_sky_day["ground_horizon"] as Color) * k
			env.fog_light_color = (_sky_day["fog"] as Color) * k


func dark_material() -> StandardMaterial3D:
	if _dark_mat == null:
		_dark_mat = StandardMaterial3D.new()
		_dark_mat.vertex_color_use_as_albedo = true
		_dark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dark_mat.no_depth_test = false
	return _dark_mat
