# A racer: physics and AI ported from the mod's kart.py (numbers from
# shared/tuning.json, mechanics from docs/kart-reference.md), drawn as a
# Y-billboard sprite over the terrain.
class_name Kart
extends Node3D

var display_name := ""
var unit := ""
var is_player := false
var rng: RandomNumberGenerator

# state in world px (the shared contract's unit)
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var heading := 0.0
var next_wp := 1
var lap := 1
var progress := 0.0
var rank := 1
var finished := false
var finish_time := -1.0

var item := ""
var hp := 10.0
var max_hp := 10.0
var alive := true
var shields := 0
var ability := {}
var ability_spell := {}   # the monster's own spell as an owned-spell dict, cast through Items.cast_spell
var ability_cd := 5.0
var coins := 0            # speed coins: each adds top speed until the kart is hit
var is_wizard := false    # a CPU wizard racer (grand prix), not a monster
var human := -1           # local multiplayer: seat index of the person driving, -1 for CPU or the campaign wizard
var spells: Array = []    # local multiplayer: this kart's own action bar (owned spell dicts)
var slot := 0             # the selected slot, cast with one button
var respawn_t := 0.0
var remote := false       # online: a human on another machine, driven by frames from the network
var net_id := -1          # online: stable id shared with the guests
var net_pos := Vector2.ZERO   # online guest: the host's last position, eased toward
var net_age := -1.0
var net_heading := 0.0
var stun_t := 0.0
var slip_t := 0.0
var air_t := 0.0          # a jump pad's hop: no off-road drag, drawn lifted on an arc
var alt := 0.0            # height above the road under the kart (px): falling off a ledge
var vz := 0.0             # vertical speed of that fall (px/s)
var abs_h := 0.0          # the kart's absolute height last step
var landed_from := 0.0    # set for one step when a fall ends: how far it fell (px)
var void_t := 0.0         # falling into the void: sinks for a moment, then is returned to the road
var teleport_cd := 0.0    # seconds until a stairwell teleporter may take this kart again
const GRAVITY := 1400.0
var branch := -1          # the parallel route this kart is on (Track.branches index), -1 = the loop
var branch_idx := 0       # its sample along that branch
var branch_choice := -1   # an AI kart's pick at the next fork
var choice_fork := -1
var branch_log := false
var air_len := 0.0
var hit_flash := 0.0
var spin := 0.0
var speed_scale := 1.0
var face_right := true

# stats
var stat_speed := 5
var stat_weight := 5
var max_speed := 780.0
var accel := 640.0
var turn_rate := 2.7
var mass := 1.0
var metabolism := 0.75
var charge_scale := 1.0

# boosts: name -> [strength, time_left]
var boosts := {}
var boost_t := 0.0
var boost_mult := 1.0

# drift
var steer_s := 0.0
var drift_dir := 0
var drift_charge := 0.0
var drift_stage := 0
var drifting := false

# slipstream / start
var slip_charge := 0.0
var in_slip := false
var start_hold := 0.0
var ai_reaction := 0.0
var ai_drift_prob := 0.6
var ai_offset := 0.0
var ai_skill := 1.0
var ai_drift_bias := 0.5
var anim_t := 0.0

# test-rig archetypes (docs/test-rig.md): "", ahead, behind, swerve, beside, parked
var archetype := ""
var rig_dist := 0.0     # px along the route relative to the player, + ahead
var rig_lat := 0.0      # lateral offset as a fraction of half the road width, + right; swerve amplitude
var rig_t := 0.0
var no_items := false
var damage_taken := 0.0
var stun_total := 0.0
var rig_recover := 0.0  # seconds left before the gap error is measured again after a stun
var route_px := 0.0     # continuous distance along the route (rig), from the nearest segment
var route_idx := 0

# tuning
var K := {}
var D := {}
var B := {}
var BRAKE := 1000.0
var GRIP := 7.0
var DRAG := 0.55
var OFFROAD_DRAG := 1.6
var OFFROAD_SPEED := 0.45
var RADIUS := 24.0
var STEER_SMOOTH := 9.0
var BOOST_ACCEL := 2.0
var TURN_CURVE: Array = [[0.0, 0.4], [0.25, 1.0], [0.8, 0.5], [1.6, 0.45]]

var sprite: Sprite3D
var shadow: MeshInstance3D
var label: Label3D
var stun_icon: Sprite3D
var boost_fx: Sprite3D
var frame_size := 60
var idle_frames := 1


static func interp(curve: Array, x: float) -> float:
	if x <= float(curve[0][0]):
		return float(curve[0][1])
	for i in range(1, curve.size()):
		var x1 := float(curve[i][0])
		var y1 := float(curve[i][1])
		if x <= x1:
			var x0 := float(curve[i - 1][0])
			var y0 := float(curve[i - 1][1])
			var t := (x - x0) / (x1 - x0) if x1 > x0 else 0.0
			return y0 + (y1 - y0) * t
	return float(curve[curve.size() - 1][1])


# Speed and weight 1..9 from a Rift Wizard unit (docs section 1).
static func stats_from_unit(hp: float, flying: bool, p_rng: RandomNumberGenerator) -> Vector2i:
	var weight := int(round(1.0 + 2.2 * log(maxf(1.0, hp) / 5.0 + 1.0)))
	weight = clampi(weight + p_rng.randi_range(-1, 1), 1, 9)
	var speed := 10 - weight + (2 if flying else 0) + p_rng.randi_range(-1, 1)
	return Vector2i(clampi(speed, 1, 9), weight)


static func wrap_angle(a: float) -> float:
	while a > PI:
		a -= TAU
	while a < -PI:
		a += TAU
	return a


func setup(p_name: String, p_unit: String, p_pos: Vector2, p_heading: float, p_player: bool, p_rng: RandomNumberGenerator, shadow_mesh: Mesh, stats := Vector2i(5, 5), p_hp := 10.0) -> void:
	display_name = p_name
	unit = p_unit
	max_hp = p_hp
	hp = p_hp
	pos = p_pos
	heading = p_heading
	is_player = p_player
	rng = p_rng
	ai_offset = rng.randf_range(-0.4, 0.4)
	ai_skill = rng.randf_range(0.7, 1.0)
	ai_drift_bias = rng.randf()
	anim_t = rng.randf()

	K = Shared.tuning.get("kart", {})
	D = Shared.tuning.get("drift", {})
	B = Shared.tuning.get("boost", {})
	BRAKE = float(K.get("brake", BRAKE))
	GRIP = float(K.get("grip", GRIP))
	DRAG = float(K.get("drag", DRAG))
	OFFROAD_DRAG = float(K.get("offroad_drag", OFFROAD_DRAG))
	OFFROAD_SPEED = float(K.get("offroad_speed", OFFROAD_SPEED))
	RADIUS = float(K.get("radius", RADIUS))
	STEER_SMOOTH = float(K.get("steer_smooth", STEER_SMOOTH))
	BOOST_ACCEL = float(K.get("boost_accel_multiplier", BOOST_ACCEL))
	TURN_CURVE = K.get("turn_curve", TURN_CURVE)

	stat_speed = stats.x
	stat_weight = stats.y
	max_speed = float(K.get("max_speed", 780.0)) * (1.0 + float(K.get("stat_speed_pct", 0.025)) * (stat_speed - 5))
	accel = float(K.get("accel", 640.0)) * (1.0 + float(K.get("stat_accel_pct", 0.12)) * (5 - stat_speed))
	turn_rate = float(K.get("turn", 2.7)) * (1.0 + float(K.get("stat_weight_turn_pct", 0.03)) * (5 - stat_weight))
	mass = 1.0 + 1.5 * (stat_weight - 1) / 8.0
	var ml := float(B.get("metabolism_light", 0.5))
	var mh := float(B.get("metabolism_heavy", 1.0))
	metabolism = ml + (mh - ml) * (stat_weight - 1) / 8.0
	charge_scale = 1.0 + float(D.get("stat_charge_pct", 0.05)) * ((stat_speed - 5) - (stat_weight - 5))

	var info: Dictionary = QUD.unit_info(unit)
	frame_size = int(info.get("frame_size", 60))
	idle_frames = maxi(1, int(info.get("idle_frames", 1)))

	shadow = MeshInstance3D.new()
	shadow.mesh = shadow_mesh
	shadow.position = Vector3(0, 0.5 * Track.U, 0)
	add_child(shadow)

	sprite = Sprite3D.new()
	sprite.texture = QUD.unit_idle(unit)
	sprite.hframes = idle_frames
	sprite.pixel_size = Track.U
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.position = Vector3(0, frame_size * Track.U * 0.5, 0)
	add_child(sprite)

	stun_icon = Sprite3D.new()
	stun_icon.texture = QUD.texture("status/stun.png")
	stun_icon.pixel_size = Track.U * 1.4
	stun_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	stun_icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	stun_icon.position = Vector3(0, (frame_size + 18) * Track.U, 0)
	stun_icon.visible = false
	add_child(stun_icon)

	boost_fx = Sprite3D.new()
	boost_fx.texture = QUD.effect("lightning_0")
	boost_fx.hframes = 6
	boost_fx.pixel_size = Track.U * 1.2
	boost_fx.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	boost_fx.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	boost_fx.position = Vector3(0, frame_size * Track.U * 0.5, 0)
	boost_fx.visible = false
	add_child(boost_fx)

	label = Label3D.new()
	label.text = display_name
	label.font = QUD.font()
	label.font_size = 32
	label.pixel_size = Track.U * 0.22
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.modulate = Color.WHITE if is_player else Color(0.85, 0.85, 0.85)
	label.outline_size = 6
	label.position = Vector3(0, (frame_size + 6) * Track.U, 0)
	label.visible = not is_player
	add_child(label)


# ---------------------------------------------------------------- helpers

func speed() -> float:
	return vel.length()


func forward() -> Vector2:
	return Vector2(cos(heading), sin(heading))


func take_damage(amount: float) -> bool:
	hp = maxf(0.0, hp - amount)
	hit_flash = 0.35
	return hp <= 0.0


func stun(duration: float) -> void:
	if stun_t <= 0.0:
		vel *= 0.35
	stun_t = maxf(stun_t, duration)
	hit_flash = 0.35
	_end_drift(false)


# A jump pad's launch: a hop for `seconds` with a boost for the same time.
func launch(seconds: float, strength: float) -> void:
	air_t = seconds
	air_len = seconds
	slip_t = 0.0
	add_boost("jump", strength, seconds)


func lift_px() -> float:
	var hop := 0.0
	if air_t > 0.0 and air_len > 0.0:
		hop = sin(PI * (1.0 - air_t / air_len)) * 55.0
	return maxf(hop, alt)


func add_boost(name: String, strength: float, time: float) -> void:
	if boosts.has(name):
		var cur: Array = boosts[name]
		if cur[1] < time:
			boosts[name] = [strength, time]
		else:
			cur[0] = maxf(cur[0], strength)
	else:
		boosts[name] = [strength, time]


func _update_boosts(dt: float) -> void:
	var strengths := PackedFloat32Array()
	boost_t = 0.0
	for name in boosts.keys():
		var entry: Array = boosts[name]
		entry[1] -= dt
		if entry[1] <= 0.0:
			boosts.erase(name)
		else:
			strengths.append(entry[0])
			boost_t = maxf(boost_t, entry[1])
	strengths.sort()
	strengths.reverse()
	var total := 0.0
	for i in strengths.size():
		total += strengths[i] / (1.0 + metabolism * i)
	boost_mult = 1.0 + minf(total, float(B.get("cap", 0.8)))


func _end_drift(release: bool) -> void:
	if drift_dir != 0 and release and drift_stage > 0:
		var stage: Dictionary = D["stages"][drift_stage - 1]
		add_boost("drift", float(stage["strength"]), float(stage["boost_time"]))
	drift_dir = 0
	drift_charge = 0.0
	drift_stage = 0
	drifting = false


# ---------------------------------------------------------------- physics

func apply_control(dt: float, throttle: float, steer: float, drift: bool, track: Track) -> void:
	var on_road := track.on_road(pos, next_wp)
	# the road's grade: uphill caps speed and drags, downhill frees it (authored elevation)
	var grade := clampf(track.grade(pos, forward()), -0.4, 0.4)   # the shelf's off-road edge is steeper than any road
	if grade != 0.0 and air_t <= 0.0 and alt <= 0.0:
		vel += forward() * (-grade) * 420.0 * dt
	if air_t > 0.0:
		air_t = maxf(0.0, air_t - dt)
		on_road = true             # airborne: whatever is below does not slow the kart
	# a ledge: the road under the kart dropped away, so it falls until it meets the road again
	landed_from = 0.0
	var ground_h := track.height_px(pos)
	if alt <= 0.0 and abs_h - ground_h > 30.0 and abs_h != 0.0:
		alt = abs_h - ground_h        # drove off a step: keep the old height, start falling
		vz = 0.0
	if alt > 0.0:
		vz -= GRAVITY * dt
		alt = maxf(0.0, alt + vz * dt)
		on_road = true
		if alt <= 0.0:
			landed_from = -vz / GRAVITY * (-vz) * 0.5   # the height it fell, back from the speed
			vz = 0.0
	abs_h = ground_h + alt
	var stunned := stun_t > 0.0
	if stunned:
		throttle = 0.0
		steer = 0.0
		drift = false
		spin += 11.0 * dt
	else:
		spin = 0.0

	_update_boosts(dt)
	steer_s += (steer - steer_s) * minf(1.0, STEER_SMOOTH * dt)

	var fwd := forward()
	var along := vel.dot(fwd)
	var ratio := absf(along) / max_speed

	var boosted := boost_mult > 1.0
	var top := max_speed * speed_scale * boost_mult * (1.0 + coins * float(K.get("coin_speed_pct", 0.04)))
	if not on_road and not boosted:
		top *= OFFROAD_SPEED
	top *= clampf(1.0 - grade * 0.9, 0.72, 1.22)
	var acc := accel * (1.0 + (BOOST_ACCEL - 1.0) * (boost_mult - 1.0) / 0.3)

	if throttle > 0.0:
		vel += fwd * acc * throttle * dt
	elif throttle < 0.0:
		var rate := BRAKE if along > 30.0 else accel * 0.5
		vel += fwd * rate * throttle * dt

	# drift state machine (docs section 3)
	var min_ratio := float(D.get("min_speed_ratio", 0.55))
	var can_drift := drift and along > min_ratio * max_speed and on_road and not stunned
	if drift_dir == 0 and can_drift and absf(steer_s) > 0.3:
		drift_dir = 1 if steer_s > 0.0 else -1
		drift_charge = 0.0
		drift_stage = 0
	elif drift_dir != 0 and not can_drift:
		_end_drift(true)
	drifting = drift_dir != 0

	# turning (docs section 2)
	var turn := turn_rate * interp(TURN_CURVE, ratio)
	if drifting:
		var inward := (steer_s * drift_dir + 1.0) * 0.5
		var smin := float(D.get("steer_min", 0.2))
		var smax := float(D.get("steer_max", 1.0))
		var eff := drift_dir * (smin + (smax - smin) * inward)
		heading += eff * turn * float(D.get("turn_multiplier", 1.4)) * dt
		var rate := float(D.get("inward_charge_multiplier", 2.5)) if steer_s * drift_dir > 0.3 else 1.0
		drift_charge += dt * rate / charge_scale
		drift_stage = 0
		for s in D["stages"]:
			if drift_charge >= float(s["charge"]):
				drift_stage += 1
	elif along != 0.0:
		heading += steer_s * turn * dt * (1.0 if along >= 0.0 else -1.0) * minf(1.0, ratio * 4.0)

	var grip := float(D.get("grip", 1.7)) if drifting else GRIP
	grip *= 1.0 + 0.2 * track.banking(pos)      # a banked corner holds the kart
	if alt > 0.0:
		grip *= 0.35                               # in the air: some steering, not much
	if slip_t > 0.0:
		grip *= 0.12
	if not on_road:
		grip *= 0.7
	var spd := vel.length()
	if spd > 1.0:
		var desired := fwd * (spd if along >= 0.0 else -spd)
		vel = vel.lerp(desired, minf(1.0, grip * dt))

	vel *= maxf(0.0, 1.0 - DRAG * dt)
	if not on_road and not boosted:
		vel *= maxf(0.0, 1.0 - OFFROAD_DRAG * dt)
	if stunned:
		vel *= maxf(0.0, 1.0 - 3.0 * dt)

	spd = vel.length()
	if spd > top and spd > 0.0:
		var target := spd + (top - spd) * minf(1.0, 5.0 * dt)
		vel = vel.normalized() * target

	pos += vel * dt
	var hitr := track.resolve(pos, RADIUS)
	if hitr["hit"]:
		var nrm: Vector2 = hitr["normal"]
		pos = hitr["pos"]
		var into := vel.dot(nrm)
		if into < 0.0:
			vel -= nrm * into * 1.3   # bounce a little
			vel *= 0.7
			if into < -350.0:
				hit_flash = 0.3
	var w := track.size.x
	var h := track.size.y
	if pos.x < 30.0:
		pos.x = 30.0
		vel.x = absf(vel.x) * 0.5
	if pos.x > w - 30.0:
		pos.x = w - 30.0
		vel.x = -absf(vel.x) * 0.5
	if pos.y < 30.0:
		pos.y = 30.0
		vel.y = absf(vel.y) * 0.5
	if pos.y > h - 30.0:
		pos.y = h - 30.0
		vel.y = -absf(vel.y) * 0.5

	if stun_t > 0.0:
		stun_total += dt
	stun_t = maxf(0.0, stun_t - dt)
	slip_t = maxf(0.0, slip_t - dt)
	hit_flash = maxf(0.0, hit_flash - dt)
	anim_t += dt


# ---------------------------------------------------------------- AI

func ai_control(dt: float, track: Track, karts: Array, drift_prob: float) -> Dictionary:
	var look := 3 + int(speed() / 220.0)
	var aim := track.aim(self, look)
	var d: Vector2 = aim["dir"]
	var nrm := Vector2(-d.y, d.x)
	ai_offset = clampf(ai_offset + rng.randf_range(-1.0, 1.0) * dt * 0.4, -0.45, 0.45)
	var target: Vector2 = aim["pos"] + nrm * (ai_offset * float(aim["width"]) * 0.5)

	var fwd := forward()
	var side := Vector2(-fwd.y, fwd.x)
	for other in karts:
		if other == self:
			continue
		var rel: Vector2 = other.pos - pos
		var ahead := rel.dot(fwd)
		if ahead > 0.0 and ahead < 120.0 and absf(rel.dot(side)) < 40.0:
			target += side * (60.0 if rel.dot(side) < 0.0 else -60.0)

	var to := target - pos
	var desired := atan2(to.y, to.x)
	var diff := wrap_angle(desired - heading)
	var steer := clampf(diff * 3.0, -1.0, 1.0)
	var throttle := 1.0 if absf(diff) < 1.2 else 0.35
	var drift := false
	if drifting:
		drift = absf(diff) > 0.12 and diff * drift_dir > -0.2
	else:
		var min_ratio := float(D.get("min_speed_ratio", 0.55))
		drift = absf(diff) > 0.45 and speed() > min_ratio * max_speed * 1.05 and ai_drift_bias < drift_prob
	var use := item != "" and rng.randf() < 0.7 * dt
	return {"throttle": throttle, "steer": steer, "drift": drift, "use": use}


# Track the continuous route distance from the nearest segment; never stalls on a missed waypoint.
func update_route(track: Track) -> void:
	var r := track.route_px_at(pos, route_idx)
	var m: float = r["px"]
	var delta := m - fposmod(route_px, track.total_len)
	if delta > track.total_len * 0.5:
		delta -= track.total_len
	elif delta < -track.total_len * 0.5:
		delta += track.total_len
	route_px += delta
	route_idx = r["idx"]
	if archetype != "":
		next_wp = (route_idx + 1) % track.n


# Kinematic archetype (the rig default): slides along the route holding its gap exactly,
# matching the player's speed plus a bounded catch-up; a stun stops it in place.
func rig_move(dt: float, track: Track, player: Kart, R: Dictionary) -> void:
	rig_t += dt
	var rate := 0.0
	if archetype != "parked" and stun_t <= 0.0:
		var err := player.route_px + rig_dist - route_px
		var cap := float(R.get("catchup_max", 400.0))
		rate = maxf(0.0, player.speed() + clampf(err * float(R.get("catchup_gain", 1.2)), -cap, cap))
	route_px += rate * dt
	var pt := track.point_at_px(route_px)
	var dir: Vector2 = pt["dir"]
	var nrm := Vector2(-dir.y, dir.x)
	pos = pt["pos"] + nrm * rig_lateral(R) * track.width * 0.5
	if rate > 1.0:
		heading = atan2(dir.y, dir.x)
	vel = dir * rate
	route_idx = int(pt["index"])
	next_wp = (route_idx + 1) % track.n
	if stun_t > 0.0:
		stun_total += dt
		spin += 11.0 * dt
	else:
		spin = 0.0
	stun_t = maxf(0.0, stun_t - dt)
	slip_t = maxf(0.0, slip_t - dt)
	hit_flash = maxf(0.0, hit_flash - dt)
	anim_t += dt


# Rig archetypes hold a set gap to the player along the route (and a lane), whatever the player does.
func rig_lateral(R: Dictionary) -> float:
	if archetype == "swerve":
		return rig_lat * sin(rig_t * TAU / float(R.get("swerve_period", 2.4)))
	return rig_lat


func rig_control(dt: float, track: Track, player: Kart, R: Dictionary) -> Dictionary:
	rig_t += dt
	var out := {"throttle": 0.0, "steer": 0.0, "drift": false, "use": false}
	if archetype == "parked":
		return out
	var my_px := route_px
	var err := player.route_px + rig_dist - my_px
	var look := maxf(120.0, speed() * 0.5)
	var pt := track.point_at_px(my_px + look)
	var dir: Vector2 = pt["dir"]
	var nrm := Vector2(-dir.y, dir.x)
	var aim: Vector2 = pt["pos"] + nrm * rig_lateral(R) * track.width * 0.5
	var to := aim - pos
	var diff := wrap_angle(atan2(to.y, to.x) - heading)
	out["steer"] = clampf(diff * 3.0, -1.0, 1.0)
	# corner speed limit from how much the route bends just past the aim point
	var far := track.point_at_px(my_px + look + float(R.get("bend_look", 220.0)))
	var fdir: Vector2 = far["dir"]
	var bend := absf(wrap_angle(atan2(fdir.y, fdir.x) - atan2(dir.y, dir.x)))
	var corner_cap := max_speed * clampf(float(R.get("bend_cap_base", 2.0)) - bend * float(R.get("bend_cap_gain", 0.0)), 0.45, 2.0)
	var want := player.speed() + err * float(R.get("catchup_gain", 1.2))
	want = clampf(want, 0.0, minf(max_speed * speed_scale, corner_cap))
	var along := vel.dot(forward())
	out["throttle"] = clampf((want - along) / 60.0, -0.7, 1.0)
	if absf(diff) > 1.2:
		out["throttle"] = minf(out["throttle"], 0.35)
	return out


# ---------------------------------------------------------------- visuals

func update_visual(track: Track, cam_right: Vector2, t: float) -> void:
	position = track.to3(pos)
	var lift := lift_px() * Track.U
	if void_t > 0.0:
		lift = -(1.0 - void_t) * 90.0 * Track.U      # sinking
	sprite.position.y = frame_size * Track.U * 0.5 + lift
	shadow.position.y = 0.5 * Track.U
	shadow.scale = Vector3.ONE * (1.0 - 0.35 * (lift_px() / 55.0))
	sprite.frame = int(anim_t / 0.2) % idle_frames
	if not is_player:
		label.text = "%s  %d" % [display_name, int(ceil(hp))]
		label.modulate = Color(1.0, 0.6, 0.6) if hp < max_hp * 0.35 else Color(0.85, 0.85, 0.85)
	var dot := forward().dot(cam_right)
	if dot > 0.15:
		face_right = true
	elif dot < -0.15:
		face_right = false
	sprite.flip_h = not face_right
	if hit_flash > 0.0:
		sprite.modulate = Color(1.0, 0.45, 0.45)
	elif shields > 0:
		sprite.modulate = Color(0.7, 1.0, 1.0)
	elif boost_t > 0.0:
		sprite.modulate = Color(1.1, 1.1, 0.8)
	elif drifting:
		var tint := [Color.WHITE, Color(1.1, 1.05, 0.8), Color(1.15, 0.9, 0.85), Color(0.85, 1.0, 1.2)]
		sprite.modulate = tint[mini(3, drift_stage)]
	else:
		sprite.modulate = Color.WHITE
	stun_icon.visible = stun_t > 0.0
	boost_fx.visible = boost_t > 0.0
	if boost_fx.visible:
		boost_fx.frame = int(t / 0.06) % 6
	shadow.scale = Vector3(1.0, 1.0, 1.0) * (1.25 if boost_t > 0.0 else 1.0)
