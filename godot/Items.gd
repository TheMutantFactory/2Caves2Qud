# Pickup spells, campaign spell effects, and the things they leave on the track.
class_name Items
extends RefCounted

# The arcade pickups (item boxes): the keys are the engine's six behaviours and the
# tuning odds table; the labels and icons are the Qud items they play as.
const KINDS := {
	"fireball": "HE Grenade",
	"lightning_bolt": "Laser Rifle",
	"blink": "Recoiler",
	"lightning_form": "Blaze Injector",
	"freeze": "Cryo Grenade",
	"wolf": "Snapjaw Pack",
}

const TYPE_COLORS := {
	"Fire": Color(0.9, 0.11, 0.14), "Lightning": Color(1.0, 0.93, 0.35), "Ice": Color(0.31, 0.76, 0.97),
	"Nature": Color(0.45, 0.84, 0.45), "Arcane": Color(0.94, 0.38, 0.57), "Dark": Color(0.61, 0.15, 0.69),
	"Holy": Color(0.96, 1.0, 0.55), "Physical": Color(0.9, 0.82, 0.82), "Poison": Color(0.26, 0.74, 0.25),
	"Blood": Color(0.53, 0.05, 0.03), "Chaos": Color(1.0, 0.67, 0.3), "Metallic": Color(0.56, 0.61, 0.73),
}


static func type_color(dtype: String) -> Color:
	return TYPE_COLORS.get(dtype, Color.WHITE)


static func effect_strip(dtype: String) -> Texture2D:
	var tex := QUD.effect(dtype.to_lower())
	if tex == null:
		tex = QUD.effect("arcane")
	return tex


# behind_frac: 0 = leading, 1 = far behind the leader. Three anchors per item
# (leading / mid / far), interpolated. See docs/kart-reference.md section 7.
static func roll(rng: RandomNumberGenerator, behind_frac: float) -> String:
	var odds: Dictionary = Shared.t(["items", "odds"], {})
	var t := clampf(behind_frac, 0.0, 1.0)
	var keys := KINDS.keys()
	var weights := PackedFloat32Array()
	var total := 0.0
	for k in keys:
		var abc: Array = odds.get(k, [1, 1, 1])
		var a := float(abc[0])
		var b := float(abc[1])
		var c := float(abc[2])
		var w := a + (b - a) * (t * 2.0) if t < 0.5 else b + (c - b) * ((t - 0.5) * 2.0)
		w = maxf(0.0, w)
		weights.append(w)
		total += w
	if total <= 0.0:
		return keys[rng.randi_range(0, keys.size() - 1)]
	return keys[rng.rand_weighted(weights)]


# A billboard sprite with a strip animation that lives for a while.
class Effect extends Sprite3D:
	var t := 0.0
	var frame_time := 0.07
	var duration := 0.0
	var follow: Node3D = null
	var frames := 6

	static func make(tex: Texture2D, at: Vector3, p_frames: int, p_frame_time := 0.07, p_duration := -1.0, size := 1.0) -> Effect:
		var e := Effect.new()
		e.texture = tex
		e.hframes = p_frames
		e.frames = p_frames
		e.frame_time = p_frame_time
		e.duration = p_duration if p_duration > 0.0 else p_frames * p_frame_time
		e.pixel_size = Track.U * size
		e.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		e.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		e.position = at
		return e

	func tick(dt: float) -> bool:
		t += dt
		if follow != null and is_instance_valid(follow):
			position = follow.position + Vector3(0, 30 * Track.U, 0)
		frame = int(t / frame_time) % frames
		return t < duration


class Projectile extends Sprite3D:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var owner_kart: Kart
	var life := 1.8
	var age := 0.0
	var damage := 0.0
	var stun := 1.2
	var radius := 0.0
	var dtype := "Fire"
	var homing: Kart = null
	var player_only := false
	var cause := "bolt"
	var heal_frac := 0.0     # the owner heals this fraction of the damage dealt
	var shove := 0.0         # px/s added to the victim along the projectile's path (negative pulls it back)
	var hit_sound := ""      # played where it lands (a grenade's detonation, a slug's impact)

	func tick(dt: float, track: Track) -> bool:
		if homing != null and is_instance_valid(homing) and homing.alive:
			var to := homing.pos - pos
			if to.length_squared() > 1.0:
				var want := to.normalized() * vel.length()
				vel = vel.lerp(want, minf(1.0, 4.0 * dt))
		pos += vel * dt
		life -= dt
		age += dt
		position = track.to3(pos, 24.0)
		return life > 0.0


class IcePatch extends Sprite3D:
	var pos := Vector2.ZERO
	var owner_kart: Kart
	var life := 14.0
	var t := 0.0
	const RADIUS := 46.0

	func tick(dt: float) -> bool:
		t += dt
		life -= dt
		frame = int(t / 0.15) % 4
		if life < 2.0:
			modulate.a = life / 2.0
		return life > 0.0


# A lingering hazard on the road: damages (and can ice) karts inside it on a tick.
class Hazard extends Node3D:
	var pos := Vector2.ZERO
	var owner_kart: Kart
	var radius := 200.0
	var damage := 5.0
	var tick := 0.8
	var life := 6.0
	var dtype := "Fire"
	var slip := false
	var stun := 0.0          # seconds of stun on a tick (barriers, warm static)
	var active := true       # a cycling course hazard is only live part of its period
	var cue := 0.0           # 0..1 in the second before it goes live: the amber warning
	var t := 0.0
	var next_tick := 0.0
	var tiles: Array = []
	var base_tint := Color.WHITE

	# one animated tile per 90 px cell inside the radius, like the game's cloud fields
	func build(tex: Texture2D, frames: int, tint: Color, track: Track) -> void:
		var step := 90.0
		var n := int(ceil(radius / step))
		for gx in range(-n, n + 1):
			for gy in range(-n, n + 1):
				var off := Vector2(gx, gy) * step
				if off.length() > radius:
					continue
				var s := Sprite3D.new()
				s.texture = tex
				s.hframes = frames
				s.frame = posmod(gx * 3 + gy * 5, maxi(1, frames))
				s.pixel_size = Track.U * 1.6
				s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				s.axis = Vector3.AXIS_Y
				s.modulate = tint
				base_tint = tint
				s.position = track.to3(pos + off, 3.0) - track.to3(pos, 3.0)
				add_child(s)
				tiles.append(s)

	# the same field on flat ground (Survivors, Gauntlet): tiles offset in the node's own space
	func build_flat(tex: Texture2D, frames: int, tint: Color) -> void:
		var step := 90.0
		var n := int(ceil(radius / step))
		for gx in range(-n, n + 1):
			for gy in range(-n, n + 1):
				var off := Vector2(gx, gy) * step
				if off.length() > radius:
					continue
				var s := Sprite3D.new()
				s.texture = tex
				s.hframes = frames
				s.frame = posmod(gx * 3 + gy * 5, maxi(1, frames))
				s.pixel_size = Track.U * 1.6
				s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				s.axis = Vector3.AXIS_Y
				s.modulate = tint
				s.position = Vector3(off.x * Track.U, 0.0, off.y * Track.U)
				add_child(s)
				tiles.append(s)

	func tick_hazard(dt: float) -> bool:
		t += dt
		life -= dt
		next_tick -= dt
		var a := clampf(life / 1.5, 0.0, 1.0)
		if not active:
			a *= 0.22 + 0.3 * cue      # dormant: faint; the cue brightens it toward amber
		var tint := base_tint if base_tint != Color.WHITE else Color(1, 1, 1)
		if cue > 0.0 and not active:
			tint = tint.lerp(Color(1.0, 0.75, 0.2), 0.5 + 0.5 * sin(t * 18.0) * 0.5)
		for i in tiles.size():
			var s: Sprite3D = tiles[i]
			s.frame = (int(t / 0.14) + i) % maxi(1, s.hframes)
			s.modulate = tint
			s.modulate.a = a
		return life > 0.0


# A summoned chaser: runs the track and bites the first racer it meets.
# A summoned kart: rides in formation with its owner (beside it, in a fixed ring, or in a
# road-following grid when there are many) and bites enemy karts that come within reach.
class Escort extends Node3D:
	var pos := Vector2.ZERO
	var heading := 0.0
	var owner_kart: Kart
	var life := 7.0
	var t := 0.0
	var damage := 5.0
	var bite_cd := 0.0
	var display_name := ""
	var sprite: Sprite3D
	var shadow: MeshInstance3D
	var label: Label3D
	var face_right := true
	const RADIUS := 26.0

	func tick(dt: float) -> bool:
		t += dt
		life -= dt
		bite_cd = maxf(0.0, bite_cd - dt)
		sprite.frame = int(t / 0.2) % maxi(1, sprite.hframes)
		if life < 1.5:
			sprite.modulate.a = life / 1.5
		return life > 0.0

	func place(track: Track, cam_right: Vector2) -> void:
		position = track.to3(pos)
		var dot := Vector2(cos(heading), sin(heading)).dot(cam_right)
		if dot > 0.15:
			face_right = true
		elif dot < -0.15:
			face_right = false
		sprite.flip_h = not face_right


static func spawn_projectile(race, kart: Kart, tex: Texture2D, speed: float, damage: float, dtype: String, radius := 0.0, life := 1.8, homing: Kart = null) -> Projectile:
	var fwd := kart.forward()
	var p := Projectile.new()
	p.texture = tex
	p.pixel_size = Track.U * 0.8
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	p.modulate = type_color(dtype).lerp(Color.WHITE, 0.5)
	p.pos = kart.pos + fwd * 44.0
	p.vel = fwd * speed + kart.vel * 0.3
	if homing != null:
		var to := homing.pos - kart.pos
		if to.length_squared() > 1.0:
			p.vel = to.normalized() * speed
	p.owner_kart = kart
	p.damage = damage
	p.radius = radius
	p.dtype = dtype
	p.life = life
	p.homing = homing
	race.add_child(p)
	race.projectiles.append(p)
	return p


static func spawn_summon(race, kart: Kart, unit: String, damage: float, duration: float, tint := Color.WHITE) -> Escort:
	var u := unit if QUD.has_unit(unit) else SpellDB.default_summon()
	var w := Escort.new()
	var info: Dictionary = QUD.unit_info(u)
	var fs := int(info.get("frame_size", 60))
	w.sprite = Sprite3D.new()
	w.sprite.texture = QUD.unit_idle(u)
	w.sprite.hframes = maxi(1, int(info.get("idle_frames", 1)))
	w.sprite.pixel_size = Track.U
	w.sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	w.sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	w.sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	w.sprite.modulate = tint
	w.sprite.position = Vector3(0, fs * Track.U * 0.5, 0)
	w.add_child(w.sprite)
	w.shadow = MeshInstance3D.new()
	w.shadow.mesh = race.shadow_mesh
	w.shadow.position = Vector3(0, 0.5 * Track.U, 0)
	w.shadow.scale = Vector3(0.8, 1.0, 0.8)
	w.add_child(w.shadow)
	w.display_name = u.capitalize()
	w.label = Label3D.new()
	w.label.text = w.display_name
	w.label.font = QUD.font()
	w.label.font_size = 26
	w.label.pixel_size = Track.U * 0.22
	w.label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	w.label.modulate = tint.lerp(Color.WHITE, 0.5)
	w.label.outline_size = 6
	w.label.position = Vector3(0, (fs + 6) * Track.U, 0)
	w.add_child(w.label)
	w.pos = kart.pos - kart.forward() * 60.0
	w.heading = kart.heading
	w.owner_kart = kart
	w.damage = damage
	w.life = duration
	race.add_child(w)
	race.escorts.append(w)
	return w


# Can `kart` hurt `other`? Monsters only go for the wizard, as in the game.
static func valid_target(kart: Kart, other: Kart) -> bool:
	return other != kart and other.alive and (kart.is_player or other.is_player)


# Artifact and empowerment bonuses belong to the wizard only.
static func bon(kart: Kart, key: String) -> float:
	return Campaign.bonus(key) if kart.is_player else 0.0


# Nearest other racer ahead of the kart within range, preferring the one just ahead in the standings.
static func target_ahead(race, kart: Kart, range_px: float) -> Kart:
	var target: Kart = null
	var best := INF
	var fwd := kart.forward()
	for other in race.karts:
		if not valid_target(kart, other):
			continue
		var rel: Vector2 = other.pos - kart.pos
		var d := rel.length()
		if d > range_px or rel.dot(fwd) < -0.2 * d:
			continue
		var score := absi(int(other.rank) - (kart.rank - 1)) * 10000.0 + d
		if score < best:
			best = score
			target = other
	return target


# ---------------------------------------------------------------- pickup items

static func use(race, kart: Kart) -> bool:
	var kind := kart.item
	if kind == "":
		return false
	kart.item = ""
	var fwd := kart.forward()
	var track: Track = race.track
	var item_dmg := float(Shared.t(["campaign", "item_damage"], 6))

	match kind:
		"fireball":
			spawn_projectile(race, kart, QUD.texture("effects/proj/fire_ball.png"), 1050.0, item_dmg, "Fire", 60.0)
			race.play("pickup_" + kind)
		"lightning_bolt":
			var target := target_ahead(race, kart, 1300.0)
			if target == null:
				kart.item = kind
				return false
			race.hit_kart(target, item_dmg, "Lightning", kart, 0.9)
			race.spawn_bolt(kart.position, target.position)
			race.play("pickup_" + kind)
		"blink":
			var d := track.direction_at(kart.next_wp)
			race.spawn_effect(QUD.effect("translocation"), kart.position + Vector3(0, 30 * Track.U, 0), 6)
			kart.pos += d * 340.0
			kart.heading = atan2(d.y, d.x)
			kart.vel = d * maxf(kart.speed(), 320.0)
			race.spawn_effect(QUD.effect("translocation"), track.to3(kart.pos, 30.0), 6)
			race.play("pickup_" + kind)
		"lightning_form":
			kart.add_boost("lightning_form", float(Shared.t(["items", "lightning_form_strength"], 0.5)),
				float(Shared.t(["items", "lightning_form_time"], 2.4)))
			race.play("pickup_" + kind)
		"freeze":
			var ice := IcePatch.new()
			ice.texture = QUD.texture("tiles/cloud_ice_cloud.png")
			ice.hframes = 4
			ice.pixel_size = Track.U * 1.6
			ice.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			ice.axis = Vector3.AXIS_Y
			ice.pos = kart.pos - fwd * 60.0
			ice.owner_kart = kart
			ice.position = track.to3(ice.pos, 2.0)
			race.add_child(ice)
			race.patches.append(ice)
			race.play("pickup_" + kind)
		"wolf":
			spawn_summon(race, kart, SpellDB.default_summon(), float(Shared.t(["campaign", "wolf_damage"], 5)), 7.0)
			race.play("enemy")
	return true


# ---------------------------------------------------------------- campaign spells

# Cast an owned spell (SpellDB.make_owned dict) from the action bar. Returns true if it went off.
static func cast_spell(race, kart: Kart, spell: Dictionary) -> bool:
	var e: Dictionary = spell["effect"]
	var kind := String(e["kind"])
	var dtype := String(e.get("dtype", "Arcane"))
	var tint := type_color(dtype)
	var track: Track = race.track
	var rng_px := float(e.get("range", 400.0)) + bon(kart, "spell_range")
	var dmg := float(e.get("damage", 0.0)) + bon(kart, "spell_damage")
	var dur := float(e.get("duration", 4.0)) + bon(kart, "spell_duration")
	# the item's or mutation's own sound (qud/data/spells.json kart.sound); beams play on a hit
	var snd := String(e.get("sound", ""))
	if kind != "beam":
		race.play(snd)
	match kind:
		"bolt":
			var homing := target_ahead(race, kart, rng_px * 1.5)
			var n := maxi(1, int(e.get("count", 1)))
			for i in n:
				var p := spawn_projectile(race, kart, proj_texture(e, "arcane_bolt"), 1100.0, dmg, dtype, 0.0, rng_px / 1100.0 + 0.4, homing if i == 0 else null)
				p.player_only = not kart.is_player
				if i > 0:   # the first shot homes; the rest fan out around it
					p.vel = p.vel.rotated(deg_to_rad(12.0 * ceil(i / 2.0) * (1.0 if i % 2 == 1 else -1.0)))
				_arm(p, e)
		"blast":
			var n := maxi(1, int(e.get("count", 1)))
			for i in n:
				var p := spawn_projectile(race, kart, proj_texture(e, "fire_ball"), 950.0, dmg, dtype, float(e.get("radius", 60.0)) + bon(kart, "spell_radius"), rng_px / 950.0 + 0.5)
				p.player_only = not kart.is_player
				if i > 0:
					p.vel = p.vel.rotated(deg_to_rad(10.0 * ceil(i / 2.0) * (1.0 if i % 2 == 1 else -1.0)))
				_arm(p, e)
		"beam":
			var n := int(e.get("targets", 1)) + int(bon(kart, "beam_targets"))
			var hit_any := false
			var seen := {}
			for i in n:
				var target: Kart = null
				var best := INF
				for other in race.karts:
					if not valid_target(kart, other) or seen.has(other):
						continue
					var rel: Vector2 = other.pos - kart.pos
					var d := rel.length()
					if d > rng_px or rel.dot(kart.forward()) < 0.0:
						continue
					if d < best:
						best = d
						target = other
				if target == null:
					break
				seen[target] = true
				var d_here := dmg
				if float(e.get("hp_frac", 0.0)) > 0.0:
					d_here = maxf(dmg, target.max_hp * float(e["hp_frac"]))   # a share of the victim's max HP
				race.hit_kart(target, d_here, dtype, kart, float(e.get("stun", 0.6)))
				_after_hit(race, kart, target, d_here, e, kart.forward())
				race.spawn_bolt(kart.position, target.position, tint)
				if not hit_any:
					race.play(snd)
					race.play(String(e.get("hit_sound", "")), -3.0)
				hit_any = true
			if not hit_any:
				return false
		"summon":
			race.play("summon")
			for i in int(e.get("count", 1)) + int(bon(kart, "summon_count")):
				spawn_summon(race, kart, String(spell.get("unit", "wolf")), float(e["damage"]) + bon(kart, "summon_damage"), float(e["duration"]), tint.lerp(Color.WHITE, 0.6))
		"shield":
			kart.shields = maxi(kart.shields, int(e.get("shields", 1)))
			race.spawn_effect(QUD.effect("shield_apply"), kart.position + Vector3(0, 30 * Track.U, 0), 6)
		"heal":
			race.heal_kart(kart, float(e.get("amount", 10)))
			race.spawn_effect(QUD.effect("heal"), kart.position + Vector3(0, 30 * Track.U, 0), 6)
		"buff":
			kart.add_boost(spell["name"], float(e.get("strength", 0.25)) + bon(kart, "boost"), dur)
			race.spawn_effect(QUD.effect("buff_apply"), kart.position + Vector3(0, 30 * Track.U, 0), 6)
		"blink":
			var d := track.direction_at(kart.next_wp)
			race.play("teleport")
			race.spawn_effect(QUD.effect("translocation"), kart.position + Vector3(0, 30 * Track.U, 0), 6)
			kart.pos += d * (float(e.get("distance", 340.0)) + bon(kart, "blink"))
			kart.heading = atan2(d.y, d.x)
			kart.vel = d * maxf(kart.speed(), 320.0)
			race.spawn_effect(QUD.effect("translocation"), track.to3(kart.pos, 30.0), 6)
		"melee":
			# a swipe at whoever is right in front: damage, a short stun and a shove
			var n := int(e.get("targets", 1))
			var fwd := kart.forward()
			var hits := []
			for other in race.karts:
				if not valid_target(kart, other):
					continue
				var rel: Vector2 = other.pos - kart.pos
				var d := rel.length()
				if d <= rng_px + other.RADIUS and rel.dot(fwd) > d * 0.2:
					hits.append(other)
			if hits.is_empty():
				return false
			hits.sort_custom(func(a, b): return a.pos.distance_squared_to(kart.pos) < b.pos.distance_squared_to(kart.pos))
			for other in hits.slice(0, n):
				race.hit_kart(other, dmg, dtype, kart, float(e.get("stun", 0.3)))
				_after_hit(race, kart, other, dmg, e, fwd, float(Shared.t(["campaign", "melee_shove"], 260.0)))
			race.spawn_effect(QUD.effect("physical"), kart.position + Vector3(fwd.x, 0.0, fwd.y) * 40.0 * Track.U + Vector3(0, 30 * Track.U, 0), 6, 0.05, -1.0, 1.6)
		"melee":
			# a swipe at whoever is right in front: damage, a short stun and a shove
			var n := int(e.get("targets", 1))
			var fwd := kart.forward()
			var hits := []
			for other in race.karts:
				if other == kart or not other.alive:
					continue
				var rel: Vector2 = other.pos - kart.pos
				var d := rel.length()
				if d <= rng_px + other.RADIUS and rel.dot(fwd) > d * 0.2:
					hits.append(other)
			if hits.is_empty():
				return false
			hits.sort_custom(func(a, b): return a.pos.distance_squared_to(kart.pos) < b.pos.distance_squared_to(kart.pos))
			for other in hits.slice(0, n):
				race.hit_kart(other, dmg, dtype, kart, 0.3)
				other.vel += fwd * float(Shared.t(["campaign", "melee_shove"], 260.0))
			race.spawn_effect(QUD.effect("physical"), kart.position + Vector3(fwd.x, 0.0, fwd.y) * 40.0 * Track.U + Vector3(0, 30 * Track.U, 0), 6, 0.05, -1.0, 1.6)
		"melee":
			# a swipe at whoever is right in front: damage, a short stun and a shove
			var n := int(e.get("targets", 1))
			var fwd := kart.forward()
			var hits := []
			for other in race.karts:
				if other == kart or not other.alive:
					continue
				var rel: Vector2 = other.pos - kart.pos
				var d := rel.length()
				if d <= rng_px + other.RADIUS and rel.dot(fwd) > d * 0.2:
					hits.append(other)
			if hits.is_empty():
				return false
			hits.sort_custom(func(a, b): return a.pos.distance_squared_to(kart.pos) < b.pos.distance_squared_to(kart.pos))
			for other in hits.slice(0, n):
				race.hit_kart(other, dmg, dtype, kart, 0.3)
				other.vel += fwd * float(Shared.t(["campaign", "melee_shove"], 260.0))
			race.spawn_effect(QUD.effect("physical"), kart.position + Vector3(fwd.x, 0.0, fwd.y) * 40.0 * Track.U + Vector3(0, 30 * Track.U, 0), 6, 0.05, -1.0, 1.6)
		"burst":
			# damage everyone around the caster; optional shove outward, stun, drain, only frozen karts
			var radius := float(e.get("radius", 300.0)) + bon(kart, "spell_radius")
			for other in race.karts:
				if not valid_target(kart, other):
					continue
				if bool(e.get("only_stunned", false)) and other.stun_t <= 0.0:
					continue
				var rel: Vector2 = other.pos - kart.pos
				if rel.length() > radius + other.RADIUS:
					continue
				race.hit_kart(other, dmg, dtype, kart, float(e.get("stun", 0.3)))
				_after_hit(race, kart, other, dmg, e, rel.normalized())
			ring_effects(race, kart.pos, radius, effect_strip(dtype), kart.forward())
		"aura":
			race.add_aura(kart, e, dtype)
			race.spawn_effect(QUD.effect("buff_apply"), kart.position + Vector3(0, 30 * Track.U, 0), 6)
		"patch":
			var h := Hazard.new()
			var fwd := kart.forward()
			h.pos = kart.pos + fwd * float(e.get("range", 0.0))
			h.owner_kart = kart
			h.radius = float(e.get("radius", 200.0)) + bon(kart, "spell_radius")
			h.damage = dmg
			h.tick = float(e.get("tick", 0.8))
			h.life = dur
			h.dtype = dtype
			h.slip = bool(e.get("slip", false))
			h.position = track.to3(h.pos, 3.0)
			race.add_child(h)
			if dtype == "Ice":
				h.build(QUD.texture("tiles/cloud_ice_cloud.png"), 4, Color.WHITE, track)
			elif dtype == "Lightning":
				h.build(QUD.texture("tiles/cloud_thunder_cloud.png"), 4, Color.WHITE, track)
			elif dtype == "Nature":
				h.build(QUD.texture("tiles/cloud_rainstorm_cloud.png"), 4, Color.WHITE, track)
			else:
				h.build(effect_strip(dtype), 6, tint.lerp(Color.WHITE, 0.3), track)
			race.hazards.append(h)
		"empower":
			if kart.is_player:
				Campaign.add_temp_bonus(e.get("bonuses", {}), dur)
			race.spawn_effect(QUD.effect("buff_apply"), kart.position + Vector3(0, 30 * Track.U, 0), 6)
		"hex":
			var target := target_ahead(race, kart, rng_px)
			if target == null:
				return false
			target.stun(minf(3.5, dur))
			target.slip_t = maxf(target.slip_t, dur)
			var fx: Effect = race.spawn_effect(QUD.effect("ice"), target.position + Vector3(0, 30 * Track.U, 0), 6)
			fx.follow = target
		_:
			return false
	return true


# A burst's look: the effect at the caster and a ring of them at the edge of the radius.
static func ring_effects(race, center: Vector2, radius: float, tex: Texture2D, fwd := Vector2.RIGHT) -> void:
	var track: Track = race.track
	race.spawn_effect(tex, track.to3(center, 30.0), 6, 0.06, -1.0, 1.3)
	var n := clampi(int(radius / 55.0), 6, 14)
	for i in n:
		var ang := TAU * i / n
		var dir := Vector2(cos(ang), sin(ang))
		if dir.dot(fwd) < -0.45:
			continue   # the rear wedge sits on the chase camera
		race.spawn_effect(tex, track.to3(center + dir * radius * 0.85, 24.0), 6, 0.07, -1.0, 1.2)


# The projectile's art: the item's own tile (the grenade you threw, the dagger, a slug,
# an arrow, a rocket; qud/data/spells.json kart.projectile), else the kind's default.
static func proj_texture(e: Dictionary, default: String) -> Texture2D:
	var name := String(e.get("projectile", ""))
	var tex: Texture2D = QUD.texture("effects/proj/%s.png" % name) if name != "" else null
	if tex == null:
		tex = QUD.texture("effects/proj/%s.png" % default)
	return tex


# Optional per-effect extras on a projectile.
static func _arm(p: Projectile, e: Dictionary) -> void:
	p.heal_frac = float(e.get("heal_frac", 0.0))
	p.shove = float(e.get("shove", 0.0))
	p.hit_sound = String(e.get("hit_sound", ""))
	if e.has("stun"):
		p.stun = float(e["stun"])


# After a direct hit: drain heals the caster, shove pushes (or pulls, if negative) the victim.
static func _after_hit(race, kart: Kart, target: Kart, dmg: float, e: Dictionary, dir: Vector2, default_shove := 0.0) -> void:
	var hf := float(e.get("heal_frac", 0.0))
	if hf > 0.0:
		race.heal_kart(kart, dmg * hf)
	var shove := float(e.get("shove", default_shove))
	if shove != 0.0:
		target.vel += dir * shove
