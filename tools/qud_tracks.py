"""The 20 courses of the Track Design Bible (mutant-plan/strategy/2caves2qud-tracks)
as the engine's shared/tracks.json.

Each course is authored here as a compact spec — a control-point loop drawn from the
bible's Route paragraph (the engine drapes a Catmull-Rom road over rolling ground),
a Qud biome tileset for road, off-road and walls (tools/export_godot_assets.py
TILESETS turns those into Qud floor tiles painted in the course palette), the
surface hazards the course is about (ice, fire, gas, water, oil, slime, warm
static: fixed patches at route fractions, tools/qud_tracks.py -> Race), lap count,
elevation, the Qud items that appear as scrolls, and the roster metadata (cup,
difficulty, target lap, signature skill, racing sentence).

What the engine cannot do yet is recorded per course under "gaps" (section races
run as loops, timed gates, moving hazards, vertical transfers, lap-by-lap
development) so the bible's ideas are not lost when they are cut to data.

    .venv/bin/python tools/qud_tracks.py      # rewrites shared/tracks.json
"""
import json
import math
import os

W, H = 3600, 2400          # the canvas every loop is drawn on (world px before track_scale)


def ellipse(cx, cy, rx, ry, n=10, start=0.0, wobble=None):
    pts = []
    for i in range(n):
        a = start + 2 * math.pi * i / n
        r = 1.0 if wobble is None else wobble(i)
        pts.append([round(cx + math.cos(a) * rx * r), round(cy + math.sin(a) * ry * r)])
    return pts


def haz(kind, at, side=0.0, radius=150, period=0.0, duty=0.5, phase=0.0, laps=None, per_lap=None):
    """A surface patch at a fraction of the loop. period > 0 makes it CYCLE: live for
    `duty` of every `period` seconds (offset by `phase`), with an amber cue the second
    before it goes live. kind "jump" is a pad that lofts karts crossing it while live.
    laps=[2, 3] makes it live only on those laps (drawn faint before: the preview);
    per_lap={2: {"period": 3.0}} overrides period/duty/phase on a lap. The lap is the
    race leader's, so the course develops for everyone at once."""
    h = {"kind": kind, "at": at, "side": side, "radius": radius}
    if period > 0:
        h.update({"period": period, "duty": duty, "phase": phase})
    if laps:
        h["laps"] = list(laps)
    if per_lap:
        h["per_lap"] = {str(k): v for k, v in per_lap.items()}
    return h


# Lap development per course (bible: Lap 1 teaches, Lap 2 complicates, Lap 3 resolves or
# escalates), as lap-gated hazards and per-lap overrides, plus the note the HUD shows.
LAPPED = {
    "joppa": [haz("wheel", 0.92, 0.0, 150, period=4.0, duty=0.45, per_lap={2: {"period": 3.0}, 3: {"period": 2.2, "duty": 0.35}})],
    "redrock": [haz("static", 0.20, 0.45, 120, period=5.0, duty=0.2, laps=[1]), haz("static", 0.26, -0.45, 120, period=5.0, duty=0.2, phase=2.5, laps=[1]),
                haz("static", 0.23, 0.0, 130, period=5.0, duty=0.2, laps=[2]),
                haz("static", 0.20, 0.3, 120, period=5.0, duty=0.2, laps=[3]), haz("static", 0.26, -0.3, 120, period=5.0, duty=0.2, phase=2.5, laps=[3])],
    "rustwells": [haz("jump", 0.295, 0.0, 130, laps=[3])],
    "stilt": [haz("cart", 0.45, -0.4, 150, period=8.0, duty=0.35, laps=[2]), haz("cart", 0.52, 0.4, 150, period=8.0, duty=0.35, phase=4.0, laps=[3])],
    "gritgate": [haz("barrier", 0.50, 0.0, 140, period=6.0, duty=0.5, phase=1.5, laps=[2, 3])],
    "asphalt": [haz("oil", 0.25, -0.3, 170, laps=[2, 3]), haz("oil", 0.88, -0.2, 160, laps=[3])],
    "golgotha": [haz("poison", 0.36, 0.0, 170, period=4.0, duty=0.4, laps=[2, 3]), haz("poison", 0.60, -0.3, 160, period=4.0, duty=0.4, phase=2.0, laps=[3]),
                 haz("slime", 0.7, 0.0, 200, laps=[3])],
    "bethesda": [haz("water", 0.15, 0.0, 180, laps=[1]), haz("ice", 0.5, -0.3, 170, laps=[2, 3]), haz("ice", 0.58, 0.3, 170, laps=[2, 3]),
                 haz("ice", 0.72, 0.0, 230, laps=[3]), haz("ice", 0.8, -0.35, 170, laps=[3])],
    "kyakukya": [haz("jump", 0.55, 0.0, 130, period=2.0, duty=0.5, per_lap={3: {"duty": 0.7}}),
                 haz("jump", 0.60, 0.0, 130, period=2.0, duty=0.5, per_lap={2: {"phase": 1.0}, 3: {"phase": 1.0, "duty": 0.3}}),
                 haz("jump", 0.65, 0.0, 130, period=2.0, duty=0.5, per_lap={3: {"duty": 0.7}})],
    "rainbowwood": [haz("slime", 0.16, 0.0, 180, period=9.0, duty=0.5), haz("slime", 0.5, 0.0, 180, period=9.0, duty=0.5, phase=3.0, laps=[2, 3]),
                    haz("slime", 0.83, 0.0, 180, period=9.0, duty=0.5, phase=6.0, laps=[3]), haz("slime", 0.20, 0.3, 140, period=9.0, duty=0.5, laps=[3])],
    "chavvah": [haz("jump", 0.30, 0.0, 130, laps=[2, 3])],
    "eynroj": [haz("static", 0.7, 0.3, 140, period=5.0, duty=0.4, phase=2.5, laps=[2, 3])],
    "hinnom": [haz("water", 0.45, -0.3, 180, laps=[1, 3]), haz("water", 0.45, 0.3, 180, laps=[2])],
    "palladium": [haz("jump", 0.60, 0.0, 130, laps=[2, 3]), haz("jump", 0.35, 0.3, 110, laps=[3])],
    "ydfreehold": [haz("jump", 0.90, 0.0, 130, laps=[3])],
    "moonstair": [haz("jump", 0.40, 0.0, 130, laps=[2, 3]), haz("jump", 0.70, 0.0, 130, laps=[2, 3])],
    "hydropon": [haz("water", 0.35, 0.0, 180, laps=[1, 2]), haz("jump", 0.50, 0.0, 120, laps=[3, 4, 5])],
    "omonporch": [haz("jump", 0.62, 0.0, 160, period=6.0, duty=0.6, per_lap={2: {"duty": 0.4}, 3: {"duty": 0.4}}), haz("jump", 0.68, 0.0, 140, period=6.0, duty=0.4, phase=3.0, laps=[3])],
    "tomb": [haz("fire", 0.46, 0.0, 150, period=5.0, duty=0.4, phase=1.25, laps=[3])],
    "thinworld": [haz("static", 0.3, 0.0, 170), haz("static", 0.55, -0.3, 150, laps=[2, 3]), haz("static", 0.8, 0.3, 170, laps=[3])],
}
# entries a LAPPED set REPLACES: (course, kind, at) of the always-on version
LAPPED_REPLACES = {
    "joppa": [("wheel", 0.92)], "redrock": [("static", 0.20), ("static", 0.26)], "rustwells": [("jump", 0.33)],
    "stilt": [("cart", 0.45), ("cart", 0.52)], "asphalt": [("oil", 0.25), ("oil", 0.88)],
    "kyakukya": [("jump", 0.55), ("jump", 0.60), ("jump", 0.65)], "rainbowwood": [("slime", 0.16), ("slime", 0.5), ("slime", 0.83)],
    "chavvah": [("jump", 0.30)], "eynroj": [("static", 0.7)], "hinnom": [("water", 0.45)], "palladium": [("jump", 0.60)],
    "golgotha": [("poison", 0.36), ("poison", 0.60), ("slime", 0.7)],
    "bethesda": [("water", 0.15), ("ice", 0.5), ("ice", 0.58), ("ice", 0.72), ("ice", 0.8)],
    "moonstair": [("jump", 0.40), ("jump", 0.70)], "hydropon": [("water", 0.35)], "omonporch": [("jump", 0.62)],
    "thinworld": [("static", 0.3), ("static", 0.55), ("static", 0.8)],
}
LAP_NOTES = {
    "joppa": {2: "the waterwheel turns faster", 3: "a gap opens in the paddles"},
    "redrock": {2: "the baboons aim for the racing lane", 3: "stones fall inside and out"},
    "rustwells": {2: "a bridge panel collapses: take the outer bypass", 3: "the gap is jumpable: pad before the break"},
    "stilt": {2: "the left aisle fills with carts", 3: "the market turns: right aisle busy"},
    "gritgate": {2: "a third gate comes online", 3: "the barrier cycle inverts"},
    "golgotha": {2: "the belts run faster: vents ahead", 3: "the cloaca: refuse islands"},
    "bethesda": {2: "rimed stone: the wards", 3: "the cryobarrios: ice"},
    "asphalt": {2: "an oil ribbon leaks across the causeway", 3: "a second ribbon: chain the slides"},
    "kyakukya": {2: "the middle cap falls off the beat", 3: "long, short, long"},
    "rainbowwood": {2: "the yellow weep joins the soup", 3: "magenta, and the rivers mix"},
    "chavvah": {2: "the tree leans toward the branch transfer", 3: "the tree leans back to the terrace"},
    "eynroj": {2: "the echoes double", 3: "the echoes intensify"},
    "hinnom": {2: "the kraken turns the current", 3: "the current turns back"},
    "palladium": {2: "the inner chute opens", 3: "a sunslag polyp glows gold"},
    "ydfreehold": {3: "the pipes light a surface bypass"},
    "moonstair": {2: "warm static: ELASTIC", 3: "warm static: TWINNED"},
    "hydropon": {3: "new leaves span the centre", 4: "the lilies keep growing", 5: "the bloom"},
    "omonporch": {2: "the magnetic window shortens", 3: "a second release point"},
    "tomb": {2: "the crematory sequences combine", 3: "press, arm, vent, fan at once"},
    "thinworld": {2: "the road thins: the void shows through", 3: "only the edges remain"},
}


# The bible's timed and moving hazards and its jumps, per course, as cycling patches and
# jump pads (the two engine features added for them). Appended to the course's hazards.
TIMED = {
    "joppa": [haz("wheel", 0.92, 0.0, 150, period=4.0, duty=0.45), haz("jump", 0.60, -0.45, 110)],
    "redrock": [haz("static", 0.20, 0.45, 120, period=5.0, duty=0.2), haz("static", 0.26, -0.45, 120, period=5.0, duty=0.2, phase=2.5),
                haz("jump", 0.97, 0.0, 140)],
    "rustwells": [haz("slime", 0.20, -0.4, 150, period=6.0, duty=0.4), haz("slime", 0.55, 0.4, 150, period=6.0, duty=0.4, phase=2.0),
                  haz("slime", 0.85, -0.3, 140, period=6.0, duty=0.4, phase=4.0), haz("jump", 0.33, 0.0, 120)],
    "stilt": [haz("cart", 0.45, -0.4, 150, period=8.0, duty=0.35), haz("cart", 0.52, 0.4, 150, period=8.0, duty=0.35, phase=4.0)],
    "gritgate": [haz("barrier", 0.36, 0.0, 140, period=6.0, duty=0.5), haz("barrier", 0.62, 0.0, 140, period=6.0, duty=0.5, phase=3.0)],
    "asphalt": [haz("fire", 0.58, -0.4, 140, period=5.0, duty=0.35), haz("fire", 0.61, 0.4, 140, period=5.0, duty=0.35, phase=2.5)],
    "golgotha": [haz("poison", 0.36, 0.0, 170, period=4.0, duty=0.4), haz("poison", 0.60, -0.3, 160, period=4.0, duty=0.4, phase=2.0)],
    "bethesda": [haz("ice", 0.65, 0.3, 160, period=7.0, duty=0.5, phase=3.0), haz("jump", 0.38, 0.0, 130)],
    "kyakukya": [haz("jump", 0.55, 0.0, 130, period=2.0, duty=0.5), haz("jump", 0.60, 0.0, 130, period=2.0, duty=0.5, phase=1.0),
                 haz("jump", 0.65, 0.0, 130, period=2.0, duty=0.5)],
    "chavvah": [haz("jump", 0.30, 0.0, 130), haz("jump", 0.55, 0.0, 130), haz("jump", 0.62, 0.0, 130), haz("jump", 0.69, 0.0, 130)],
    "eynroj": [haz("jump", 0.80, 0.0, 130), haz("jump", 0.86, 0.0, 130)],
    "hinnom": [haz("jump", 0.50, -0.2, 140, period=4.0, duty=0.5), haz("jump", 0.53, 0.3, 140, period=4.0, duty=0.5, phase=2.0)],
    "palladium": [haz("jump", 0.60, 0.0, 130)],
    "ydfreehold": [haz("barrier", 0.30, 0.3, 130, period=6.0, duty=0.45), haz("jump", 0.75, 0.0, 130)],
    "moonstair": [haz("jump", 0.40, 0.0, 130), haz("jump", 0.70, 0.0, 130)],
    "hydropon": [haz("jump", 0.60, 0.0, 120, period=3.0, duty=0.6)],
    "omonporch": [haz("jump", 0.62, 0.0, 160, period=6.0, duty=0.6)],
    "tomb": [haz("jump", 0.15, 0.0, 130), haz("barrier", 0.42, -0.3, 130, period=5.0, duty=0.4), haz("barrier", 0.50, 0.3, 130, period=5.0, duty=0.4, phase=2.5),
             haz("bell", 0.50, 0.0, 900, period=14.0, duty=0.1)],
    "thinworld": [haz("jump", 0.35, 0.0, 130), haz("jump", 0.85, 0.0, 140)],
}
# hazards a timed entry REPLACES (the same idea, now cycling)
REPLACED = {
    "rustwells": "slime", "gritgate": "static", "omonporch": "static",
}


# --- the courses ------------------------------------------------------------
# control: the loop, drawn so the start (first point) faces +x; width in kart-widths
# per the bible (4.5 teaching / 3.25 ordinary) at ~55 px per kart width.

COURSES = [
    dict(key="joppa", name="Joppa Waterwheel Run", cup="Fresh Water Cup", cup_index=1, difficulty=1.0,
         format="3-lap circuit", target_lap="65-75 s", skill="Wide-to-tight drift timing",
         sentence="Circle Joppa's watervine farms, cut through its briny shallows, and time the rotating waterwheel gate on the way back to the village square.",
         tileset="watervine", offroad="salt", wallset="brinestalk", road=[104, 92, 58], ground=[150, 148, 122],
         width=250, elevation=35, laps=3,
         control=[[500, 1900], [1300, 2050], [2100, 1850], [2500, 1500], [2200, 1150], [2700, 850], [3100, 1100],
                  [3200, 1700], [2900, 2100], [1900, 1300], [1100, 1000], [500, 1250]],
         hazards=[haz("water", 0.58, 0.35, 170), haz("water", 0.63, 0.4, 150)],
         spells=["Bronze Dagger", "Salve Injector", "Short Bow", "Chrome Revolver", "High Explosive Grenade Mk I", "Stun Gas Grenade Mk I", "Rubbergum Injector", "Musket"],
         gaps=["timed waterwheel gate", "shallow-water shortcut line", "hay carts between laps"]),
    dict(key="redrock", name="Red Rock Ramble", cup="Fresh Water Cup", cup_index=2, difficulty=1.5,
         format="3-lap folded circuit", target_lap="70-80 s", skill="Controlled descent",
         sentence="Drop through Red Rock's canyon strata, race beside the underground river, and climb a switchback tunnel while baboon-thrown stones alter the best line.",
         tileset="canyon", offroad="desert", wallset="rock", road=[132, 60, 40], ground=[92, 40, 30],
         width=230, elevation=110, laps=3,
         control=[[400, 400], [1400, 350], [2000, 700], [1700, 1200], [2300, 1500], [3000, 1300], [3200, 1900],
                  [2500, 2150], [1600, 2000], [900, 2100], [500, 1500], [900, 900]],
         hazards=[haz("water", 0.42, 0.0, 220), haz("water", 0.47, 0.3, 160)],
         spells=["Iron Dagger", "Carbine", "Salve Injector", "Thermal Grenade Mk I", "Compound Bow", "Sleep Gas Grenade Mk I", "Blaze Injector", "Pump Shotgun"],
         gaps=["baboon stone throws with shadow targets", "cavern bridges and the arch jump", "dogthorn edge punishment"]),
    dict(key="rustwells", name="Rust Wells Spiral", cup="Fresh Water Cup", cup_index=3, difficulty=2.0,
         format="3-lap vertical circuit", target_lap="72-82 s", skill="Spiral line choice",
         sentence="Spiral around three chrome-lined Rust Wells while corrosive qudzu narrows the inside and hanging wire offers risky aerial transfers.",
         tileset="rust", offroad="chrome", wallset="metal", road=[96, 64, 40], ground=[70, 76, 80],
         width=220, elevation=140, laps=3,
         control=ellipse(1000, 1200, 700, 520, 5, start=math.pi) + [[1800, 500]] + ellipse(2650, 1000, 600, 460, 5, start=-math.pi / 2)
                 + [[3200, 1700]] + ellipse(2300, 1900, 600, 380, 4, start=0.3) + [[1500, 2100]],
         hazards=[haz("slime", 0.2, -0.4, 150), haz("slime", 0.55, 0.4, 150), haz("slime", 0.85, -0.3, 140)],
         spells=["Steel Dagger", "Chrome Revolver", "Dart Gun", "Acid Gas Grenade Mk I", "Salve Injector", "Grappling Gun", "Semi-automatic Pistol", "EMP Grenade Mk I"],
         gaps=["three-well descent/ascent helix", "collapsing bridge panel by lap", "wire aerial transfers"]),
    dict(key="stilt", name="Six Day Stilt Pilgrimage", cup="Fresh Water Cup", cup_index=4, difficulty=2.0,
         format="3-lap circuit", target_lap="78-88 s", skill="Reading moving market lanes",
         sentence="Follow a pilgrim's loop across the salt dunes and through the Six Day Stilt's bazaar, where merchant traffic reshapes wide but readable lanes around the cathedral.",
         tileset="salt", offroad="dune", wallset="marble", road=[196, 190, 168], ground=[176, 160, 118],
         width=270, elevation=70, laps=3,
         control=[[300, 1200], [900, 700], [1700, 900], [2300, 500], [2900, 800], [3300, 1300], [3000, 1800],
                  [2400, 1600], [2000, 2000], [1300, 2100], [700, 1800]],
         hazards=[],
         spells=["Bronze Dagger", "Short Bow", "Salve Injector", "Flashbang Grenade Mk I", "Musket", "Love Injector", "Chrome Revolver", "Sleep Gas Grenade Mk I"],
         gaps=["three bazaar aisles with merchant traffic by lap", "six-statue chicane", "sacred well plaza turn"]),

    dict(key="gritgate", name="Grit Gate Grand Prix", cup="Chrome Cup", cup_index=5, difficulty=2.5,
         format="3-lap circuit", target_lap="75-85 s", skill="Force-barrier timing",
         sentence="Thread ruined approaches and the Barathrumite enclave while cycling force barriers alternately open a fast atrium line and a safer service tunnel.",
         tileset="chrome", offroad="ruin", wallset="metal", road=[110, 116, 124], ground=[120, 104, 76],
         width=230, elevation=40, laps=3,
         control=[[300, 600], [1200, 400], [1900, 700], [1900, 1300], [2700, 1300], [2700, 700], [3300, 900],
                  [3300, 1900], [2400, 2100], [1500, 1900], [800, 2100], [300, 1500]],
         hazards=[haz("static", 0.36, 0.0, 130), haz("static", 0.62, 0.0, 130)],
         spells=["Laser Pistol", "Chain Pistol", "Rubbergum Injector", "EMP Grenade Mk I", "Carbine", "Freeze Grenade Mk I", "Salve Injector", "Stun Gas Grenade Mk I"],
         gaps=["cycling force barriers (upper corridor vs service tunnel)", "communications panel that inverts the cycle"]),
    dict(key="asphalt", name="Asphalt Mines Slick", cup="Chrome Cup", cup_index=6, difficulty=2.5,
         format="3-lap folded circuit", target_lap="80-90 s", skill="Surface-state management",
         sentence="Descend an abandoned asphalt mine where sticky black pools punish cuts, rainbow oil enables long slides, and a deep lava gallery powers the climb home.",
         tileset="asphalt", offroad="bone", wallset="rock", road=[38, 36, 40], ground=[140, 132, 110],
         width=220, elevation=130, laps=3,
         control=[[400, 300], [1300, 500], [900, 1000], [1600, 1300], [2300, 1000], [3000, 1300], [3300, 1900],
                  [2600, 2200], [1900, 1900], [1200, 2150], [500, 1800], [300, 1000]],
         hazards=[haz("oil", 0.25, -0.3, 170), haz("oil", 0.5, 0.2, 200), haz("fire", 0.66, 0.0, 180), haz("fire", 0.72, 0.4, 150), haz("oil", 0.88, -0.2, 160)],
         spells=["Thermal Grenade Mk I", "Flamethrower", "Laser Rifle", "High Explosive Grenade Mk I", "Salve Injector", "Steel Dagger", "Plasma Grenade Mk I", "Blaze Injector"],
         gaps=["two-level shaft descent and turbine lift", "drillbot wall cuts", "fire snout bursts", "oil ribbons added per lap"]),
    dict(key="golgotha", name="Golgotha Drop", cup="Chrome Cup", cup_index=7, difficulty=3.0,
         format="3-section race", target_lap="section race", target_run="160-180 s", skill="Forced-movement lane changes",
         sentence="Commit to a one-way plunge through Golgotha's conveyor-fed trash chutes, dodge vent cycles, and outrun the refuse into the Cloaca.",
         tileset="rust", offroad="bile", wallset="metal", road=[84, 90, 70], ground=[60, 86, 40],
         width=210, elevation=160, laps=3, size=[4800, 3200],
         sections=3,
         # S1 the jungle and the chute mouths, S2 two conveyor floors swept east then west with a shaft
         # drop between, S3 the wide Cloaca run through refuse islands to the finish lamps
         control=[[300, 300], [1100, 300], [1700, 650], [1300, 1100], [2300, 1150], [3300, 1050], [4200, 1300],
                  [3600, 1700], [2400, 1750], [1200, 1650], [500, 1950], [900, 2500], [1800, 2700], [2600, 2550],
                  [3400, 2800], [4300, 2900]],
         hazards=[haz("poison", 0.3, 0.3, 160), haz("poison", 0.48, -0.3, 160), haz("slime", 0.7, 0.0, 200), haz("poison", 0.9, 0.35, 150)],
         spells=["Acid Gas Grenade Mk I", "Poison Gas Grenade Mk I", "Chaingun", "Salve Injector", "Gaslight Kris", "Grappling Gun", "Hulk Honey Injector", "Freeze Grenade Mk I"],
         gaps=["one-way section race with four chute mouths", "conveyor belts", "vent cycles with cues", "shaft drops"]),
    dict(key="bethesda", name="Bethesda Susa Deep Freeze", cup="Chrome Cup", cup_index=8, difficulty=3.5,
         format="3-section race", target_lap="section race", target_run="170-190 s", skill="Progressive ice control",
         sentence="Descend Bethesda Susa as every sector grows colder, earn three gate keys through racing lines, and survive the cryobarrios before the warm Temple of the Rock.",
         tileset="marble", offroad="jungle", wallset="marble", road=[128, 132, 136], ground=[40, 84, 44],
         width=230, elevation=120, laps=3, size=[4800, 3200],
         sections=3,
         # S1 the ruins, the wharf and three pool arenas as lobes, S2 the ward switchbacks west, S3 the
         # cryobarrios east to the warm Temple
         control=[[300, 250], [1000, 250], [1600, 550], [1300, 1000], [2100, 1300], [2800, 1000], [3500, 1250],
                  [4200, 1600], [3300, 1900], [2300, 1800], [1300, 2000], [600, 2300], [1300, 2700], [2200, 2850],
                  [3100, 2750], [3900, 2950], [4500, 2700]],
         hazards=[haz("water", 0.15, 0.0, 180), haz("ice", 0.5, -0.3, 170), haz("ice", 0.58, 0.3, 170), haz("ice", 0.72, 0.0, 230), haz("ice", 0.8, -0.35, 170)],
         spells=["Freeze Grenade Mk I", "Freeze Ray", "Salve Injector", "Ubernostrum Injector", "Laser Pistol", "Sleep Gas Grenade Mk I", "Steel Dagger", "Shade Oil Injector"],
         gaps=["three keyed gates from arena tokens", "chrome elevator vs switchbacks", "phase-web door bypass", "grip in visible thirds"]),

    dict(key="kyakukya", name="Kyakukya Cap Circuit", cup="Canopy Cup", cup_index=9, difficulty=2.5,
         format="3-lap circuit", target_lap="68-78 s", skill="Banking around organic structures",
         sentence="Bank around Kyakukya's giant mushroom dwellings, skim its jungle pools, and slalom past a monumental ape statue as springy caps reshape jump timing.",
         tileset="mushroom", offroad="jungle", wallset="mushroom", road=[150, 128, 96], ground=[44, 92, 48],
         width=240, elevation=80, laps=3,
         control=[[400, 1800], [1000, 2100], [1800, 1900], [2300, 2100], [2900, 1700], [3200, 1100], [2700, 700],
                  [2100, 900], [1700, 500], [1000, 400], [500, 800], [700, 1300]],
         hazards=[haz("water", 0.3, 0.0, 200), haz("water", 0.36, 0.3, 150)],
         spells=["Bronze Dagger", "Seed Spitter", "Salve Injector", "Thistle Pitcher", "Short Bow", "Poison Gas Grenade Mk I", "Skulk Injector", "Chrome Revolver"],
         gaps=["springy mushroom-cap jumps on a beat", "root ramp to the upper village", "Oboroqoru statue plaza"]),
    dict(key="rainbowwood", name="Rainbow Wood Soupway", cup="Canopy Cup", cup_index=10, difficulty=3.5,
         format="3-lap circuit", target_lap="82-92 s", skill="Predicting liquid-mix zones",
         sentence="Navigate Rainbow Wood's fungus corridors while colored weeps feed primordial-soup rivers and every new liquid mixture grows a different temporary slalom.",
         tileset="fungus", offroad="soup", wallset="mushroom", road=[110, 70, 130], ground=[60, 30, 80],
         width=230, elevation=60, laps=3,
         control=ellipse(900, 700, 600, 450, 5, start=math.pi * 0.8) + ellipse(2700, 700, 650, 450, 5, start=math.pi * 1.2)
                 + ellipse(1800, 1800, 900, 500, 6, start=-math.pi * 0.35),
         hazards=[haz("slime", 0.16, 0.0, 180, period=9.0, duty=0.5), haz("slime", 0.5, 0.0, 180, period=9.0, duty=0.5, phase=3.0),
                  haz("slime", 0.83, 0.0, 180, period=9.0, duty=0.5, phase=6.0)],
         spells=["Acid Gas Grenade Mk I", "Poison Gas Grenade Mk I", "Salve Injector", "Dart Gun", "Sphynx Salt Injector", "Gaslight Kris", "Freeze Grenade Mk I", "Compound Bow"],
         gaps=["colored weeps mixing into soup rivers", "temporary sludge slaloms per lap"]),
    dict(key="chavvah", name="Chavvah Canopy Climb", cup="Canopy Cup", cup_index=11, difficulty=3.5,
         format="3-lap vertical circuit", target_lap="80-90 s", skill="Vertical branch transfers",
         void_offroad=True, void_margin=120,
         sentence="Climb the inhabited branches of Chavvah on spiral stairs and crystalline limbs, then dive through the canopy while the roaming tree gently changes its lean.",
         tileset="crystal", offroad="leaf", wallset="crystal1", road=[190, 200, 205], ground=[50, 110, 60],
         width=220, elevation=200, laps=3,
         control=ellipse(1800, 1200, 1500, 900, 12, start=math.pi, wobble=lambda i: 1.0 - 0.18 * (i % 2)),
         hazards=[],
         spells=["Crysteel Dagger", "Turbow", "Salve Injector", "Light Rail", "Blaze Injector", "Time Dilation Grenade Mk I", "Compound Bow", "Rubbergum Injector"],
         gaps=["spiral stair-road around the trunk", "leaf ramps and branch jumps", "tree lean per lap"]),
    dict(key="eynroj", name="Eyn Roj Dreamroot", cup="Canopy Cup", cup_index=12, difficulty=4.0,
         format="3-section descent and ascent", target_lap="section race", target_run="165-185 s", skill="Reading psychic route echoes",
         sentence="Dive beneath Eyn Roj through crystalline roots where psychic echoes show several possible roads but only solid rhythm rock marks the immediate racing line.",
         tileset="marble", offroad="crystal", wallset="crystal1", road=[150, 150, 160], ground=[110, 60, 140],
         width=220, elevation=170, laps=3, size=[4800, 3200],
         sections=3,
         # S1 circles the marble glade and dives, S2 the root helix as three chambers tightening inward,
         # S3 the trunk ascent to the chiming rock
         control=[[500, 1100], [1200, 700], [2000, 900], [2100, 1500], [1400, 1800], [800, 1500], [1000, 2200],
                  [1900, 2500], [2800, 2900], [3800, 2700], [4300, 2100], [3600, 1700], [2800, 2000], [3000, 1300],
                  [3600, 900], [4300, 1000], [4600, 400]],
         hazards=[haz("static", 0.45, 0.0, 150, period=5.0, duty=0.4), haz("static", 0.7, 0.3, 140, period=5.0, duty=0.4, phase=2.5)],
         # the psychic overlays by section (Track._build_psychic): doubled edges, then false
         # silhouettes, then delayed ghosts of the racers; nothing within the envelope (px,
         # five kart lengths); the rhythm-rock studs pulse at `beat` Hz before every real turn
         psychic={"1": ["edges"], "2": ["edges", "silhouettes"], "3": ["edges", "silhouettes", "ghosts"], "envelope": 300, "beat": 2.0},
         spells=["Sunder Mind" if False else "Eigenpistol", "Stasis Grenade Mk I", "Salve Injector", "Nullray Pistol", "Skulk Injector", "Normality Gas Grenade Mk I", "Vibro Dagger", "Ubernostrum Injector"],
         gaps=["rhythm rock haptics", "the briefly solidified echo across two root gaps"]),

    dict(key="hinnom", name="Lake Hinnom Causeway", cup="Reef Cup", cup_index=13, difficulty=3.0,
         format="3-lap circuit", target_lap="82-92 s", skill="Causeway-to-water transitions",
         sentence="Race broken causeways across Lake Hinnom, using giant clams as timed jump pads while enormous reef creatures reshape the open-water current.",
         tileset="esh", offroad="water", wallset="coolant", road=[210, 208, 196], ground=[20, 70, 60],
         width=230, elevation=30, laps=3,
         control=[[300, 1100], [900, 600], [1700, 800], [2400, 400], [3200, 700], [3300, 1400], [2700, 1900],
                  [2000, 1500], [1400, 2000], [700, 1900]],
         hazards=[haz("water", 0.22, 0.0, 200), haz("water", 0.45, -0.3, 180), haz("water", 0.75, 0.0, 220), haz("water", 0.9, 0.3, 160)],
         spells=["Cast Net" if False else "Bronze Dagger", "Chain Pistol", "Salve Injector", "Freeze Ray", "Compound Bow", "Blaze Injector", "Sleep Gas Grenade Mk II", "Grappling Gun"],
         gaps=["giant clam jump pads on a cycle", "reef creatures reversing currents", "coral ramps over broken spans"]),
    dict(key="palladium", name="Palladium Reef Polyp Maze", cup="Reef Cup", cup_index=14, difficulty=4.0,
         format="3-lap circuit", target_lap="84-94 s", skill="Racing with partial sightlines",
         sentence="Thread the Palladium Reef's old arcology while translucent struts interrupt distant sightlines and plucked polyps expose brief sunslag boost pockets.",
         tileset="chrome", offroad="reef", wallset="coolant", road=[150, 156, 164], ground=[120, 60, 110],
         width=210, elevation=90, laps=3,
         control=[[300, 400], [1000, 300], [1500, 700], [1100, 1100], [1700, 1400], [2400, 1000], [2900, 400],
                  [3300, 900], [3000, 1500], [3300, 2000], [2400, 2200], [1600, 1900], [900, 2100], [300, 1600]],
         hazards=[haz("static", 0.3, -0.3, 130, period=5.0, duty=0.3), haz("static", 0.55, 0.3, 130, period=5.0, duty=0.3, phase=2.5), haz("water", 0.7, 0.0, 200)],
         spells=["Laser Rifle", "Arc Winder", "Salve Injector", "Eigenrifle", "Sphynx Salt Injector", "Plasma Grenade Mk I", "Hand Rail", "Rubbergum Injector"],
         gaps=["translucent struts hiding apexes", "plasma jellies venting", "sunslag polyp boost pockets per lap"]),
    dict(key="ydfreehold", name="Yd Freehold Pipeworks", cup="Reef Cup", cup_index=15, difficulty=3.5,
         format="3-lap circuit with parallel rooms (run as one line)", target_lap="78-88 s", skill="Room-route strategy",
         sentence="Follow Yd Freehold's dyed pipework through a lyrical surface community and choose among parallel underground rooms that trade speed, items, and technical difficulty.",
         tileset="pipe", offroad="sponge", wallset="metal", road=[60, 90, 150], ground=[150, 120, 70],
         width=230, elevation=100, laps=3,
         control=[[300, 700], [1100, 400], [2000, 600], [2800, 400], [3300, 900], [3100, 1500], [2300, 1300],
                  [2500, 1900], [1700, 2100], [1000, 1800], [400, 2000], [300, 1300]],
         hazards=[haz("oil", 0.4, 0.3, 150), haz("fire", 0.6, -0.3, 140)],
         spells=["Chrome Revolver", "Steel Dagger", "Salve Injector", "Chain Laser", "Hulk Honey Injector", "Thermal Grenade Mk II", "Semi-automatic Pistol", "Shade Oil Injector"],
         gaps=["three parallel underground rooms", "Many Eyes chamber and corkscrew pipe", "lap-3 surface bypass"]),
    dict(key="moonstair", name="Moon Stair Static Circuit", cup="Reef Cup", cup_index=16, difficulty=4.5,
         format="3-lap circuit", target_lap="86-96 s", skill="Adapting to announced rule changes",
         sentence="Climb a black-marble maze of hexagonal crystal while warm static announces one changed racing rule per lap and broken prisms release mirrored rival echoes.",
         tileset="blackmarble", offroad="crystal", wallset="crystal1", road=[40, 38, 48], ground=[90, 60, 130],
         width=210, elevation=150, laps=3,
         control=ellipse(1800, 1200, 1500, 950, 6, start=math.pi) + [[1800, 1200]] if False else
                 [[300, 1200], [800, 500], [1500, 300], [2200, 500], [2000, 1100], [2700, 900], [3300, 500],
                  [3300, 1400], [2800, 2000], [2000, 1700], [1400, 2100], [700, 1900]],
         hazards=[haz("static", 0.2, 0.0, 160), haz("static", 0.5, 0.3, 160), haz("static", 0.65, -0.3, 160), haz("static", 0.85, 0.0, 180)],
         spells=["Eigenrifle", "Stasis Grenade Mk I", "Salve Injector", "Time Dilation Grenade Mk I", "Spaser Rifle", "Ubernostrum Injector", "Light Rail", "Normality Gas Grenade Mk I"],
         gaps=["one announced rule change per lap", "hovering icosahedral platforms", "mirrored ghost echoes"]),

    dict(key="hydropon", name="The Hydropon Bloom", cup="Spindle Cup", cup_index=17, difficulty=3.5,
         format="5-lap sprint circuit", target_lap="38-45 s", skill="Anticipating a growing track",
         sentence="Sprint around the hydroponic cradle as sunslag-fed lilies grow new banked leaves each lap and gradually open a faster route across the center.",
         tileset="lily", offroad="water", wallset="marble", road=[80, 140, 70], ground=[20, 60, 80],
         width=200, elevation=40, laps=5, size=[2400, 1800],
         control=[[300, 900], [800, 400], [1500, 300], [2000, 700], [1700, 1100], [2100, 1500], [1400, 1600], [700, 1400]],
         hazards=[haz("water", 0.35, 0.0, 180), haz("water", 0.8, 0.3, 150)],
         spells=["Bronze Dagger", "Salve Injector", "Dart Gun", "Blaze Injector", "Seed Spitter", "Freeze Grenade Mk I"],
         gaps=["leaves growing per lap to open the center route", "foam-pad chicane"]),
    dict(key="omonporch", name="Omonporch Twin Gates", cup="Spindle Cup", cup_index=18, difficulty=4.0,
         format="3-lap circuit", target_lap="88-98 s", skill="Magnetic wall banking",
         sentence="Sweep through Omonporch's sultan court and banana groves, then ride the Spindle's magnetic pull up a blue wall before diving past the sealed Twin Gates.",
         tileset="sultan", offroad="banana", wallset="sultan_columns", road=[170, 150, 100], ground=[60, 110, 40],
         width=240, elevation=180, laps=3,
         control=[[300, 1800], [1000, 2100], [1800, 1900], [2500, 2100], [3200, 1700], [3300, 1000], [2800, 500],
                  [2000, 400], [1400, 800], [800, 500], [400, 1000], [600, 1400]],
         hazards=[haz("static", 0.62, 0.0, 200)],
         spells=["Etched Cleaver" if False else "Carbide Dagger", "Sniper Rifle", "Salve Injector", "Arc Cannon", "Gravity Grenade Mk I", "Hulk Honey Injector", "Missile Launcher", "Ubernostrum Injector"],
         gaps=["magnetic roadway up the Spindle with release windows", "paired-statue slalom", "gate murals lighting in order"]),
    dict(key="tomb", name="Tomb of the Eaters Bell Run", cup="Spindle Cup", cup_index=19, difficulty=5.0,
         format="3-section ascent", target_lap="section race", target_run="190-215 s", skill="Timed sanctuary routing", spoiler=True,
         sentence="Ascend the Tomb of the Eaters from bone catacombs through its lethal crematory, reaching checkered Places of Rest before each Bell pulse displaces exposed racers.",
         tileset="bone", offroad="blackmarble", wallset="bone", road=[170, 160, 130], ground=[30, 26, 22],
         width=210, elevation=160, laps=3, size=[4800, 3200],
         sections=3,
         # S1 the Death Gate down through the catacombs' bone channels, S2 the crematory conveyors west to
         # the Columbarium, S3 the climb through two gardens and the U-shaped tomb hall to the Spindle
         control=[[3600, 400], [4300, 450], [4500, 1000], [3900, 1300], [4400, 1700], [3700, 2000], [2900, 2300],
                  [2000, 2200], [1200, 2500], [500, 2200], [600, 1500], [1300, 1200], [800, 700], [1500, 300],
                  [2200, 600], [2500, 1500], [3400, 1300], [3600, 600], [3000, 250]],
         hazards=[haz("fire", 0.4, -0.3, 160), haz("fire", 0.47, 0.3, 160), haz("fire", 0.55, 0.0, 170), haz("poison", 0.7, 0.3, 150)],
         spells=["Fullerite Dagger", "Light Rail", "Salve Injector", "Plasma Grenade Mk II", "Spaser Pistol", "Ubernostrum Injector", "High Explosive Grenade Mk III", "Shade Oil Injector"],
         gaps=["the Bell clock and checkered sanctuaries", "crematory press/arm/vent/fan sequence", "stairwell teleporter"]),
    dict(key="thinworld", name="Thin World Crossing", cup="Spindle Cup", cup_index=20, difficulty=5.0,
         format="3-lap transformational circuit", target_lap="92-102 s", skill="Committing to recomposed road states", spoiler=True,
         void_offroad=True, void_margin=80,
         sentence="Cross the Thin World on a road that recomposes from solid azzurum to holographic geometry, where falling cannot end the race but returns the kart through a different line.",
         tileset="hologram", offroad="void", wallset="filigree", road=[60, 150, 180], ground=[8, 8, 14],
         width=220, elevation=120, laps=3,
         control=[[300, 1200], [1000, 600], [1900, 400], [2700, 600], [3300, 1100], [3100, 1800], [2300, 2100],
                  [1700, 1700], [2200, 1300], [1500, 1000], [900, 1500], [500, 1900]],
         hazards=[haz("static", 0.3, 0.0, 170), haz("static", 0.55, -0.3, 150), haz("static", 0.8, 0.3, 170)],
         spells=["Zetachrome Dagger", "Eigenrifle", "Ubernostrum Injector", "Phase Cannon", "Stasis Grenade Mk II", "Sphynx Salt Injector", "Hypertractor", "Space Inverter"],
         gaps=["road material thinning per lap", "Recoming/Crossing portal split", "Evil Twin best-lap ghost"]),
]

# --- parallel routes -----------------------------------------------------------
# A branch leaves the loop at `frm` and rejoins at `to` (fractions). Its interior control
# points are placed on the chord between those two loop points, pushed by `offset` px along
# the chord's normal toward the loop's centroid (an inside cut) or away (an outer detour).
# kind "expert" = narrower, luminous curb; "safe" = wider, grey curb. Hazards are at
# fractions of the branch.

def _loop_points(control, samples=16):
    pts = []
    m = len(control)
    for i in range(m):
        p0, p1, p2, p3 = (control[(i - 1) % m], control[i], control[(i + 1) % m], control[(i + 2) % m])
        for s in range(samples):
            t = s / samples
            t2, t3 = t * t, t * t * t
            x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            pts.append((x, y))
    return pts


def branch(name, kind, frm, to, offset, width=180, ai_take=0.4, hazards=None, laps=None, bypass=False, sealed=False):
    """laps=[3, 4] makes the branch EXIST only on those laps (drawn as a translucent preview
    before); bypass=True makes AI karts take it when the loop stretch it skirts is a gap."""
    b = {"name": name, "kind": kind, "from": frm, "to": to, "offset": offset, "width": width,
         "ai_take": ai_take, "hazards": hazards or []}
    if laps:
        b["laps"] = list(laps)
    if bypass:
        b["bypass"] = True
    if sealed:
        b["sealed"] = True        # not a route until a mover with opens=<name> cuts through
    return b


def road_state(frm, to, laps, state):
    """A stretch of the loop that on `laps` is "hologram" (translucent, still road),
    "cracked" (amber: the preview of a coming gap) or "gap" (no road at all)."""
    return {"from": frm, "to": to, "laps": list(laps), "state": state}


# Moving hazards: a patch that travels a path of [at, side] pairs (loop fraction, lateral in
# half road widths) back and forth (pingpong) or around (loop) in `period` seconds; its path
# is drawn on the road as the sweep marking. A thrower lands a stone on the road at `at`
# every `period` seconds after a `cue`-second shadow.
def mover(name, kind, path, period=6.0, mode="pingpong", radius=140, laps=None, phase=0.0, cuts_walls=False, opens=""):
    """cuts_walls: on its first pass the mover removes the wall blocks along its path;
    opens: the sealed branch it bores toward becomes a route when it reaches the end."""
    m = {"name": name, "kind": kind, "path": [list(p) for p in path], "period": period, "mode": mode, "radius": radius, "phase": phase}
    if laps:
        m["laps"] = list(laps)
    if cuts_walls:
        m["cuts_walls"] = True
    if opens:
        m["opens"] = opens
    return m


def thrower(name, at, side=0.0, spread=0.3, period=5.0, cue=1.0, radius=120, damage=6, stun=0.6, laps=None, phase=2.0):
    t = {"name": name, "at": at, "side": side, "spread": spread, "period": period, "cue": cue, "radius": radius,
         "damage": damage, "stun": stun, "phase": phase}
    if laps:
        t["laps"] = list(laps)
    return t


MOVERS = {
    "stilt": [mover("pack animals", "cart", [(0.45, -1.1), (0.45, 1.1)], period=8.0, radius=130, laps=[2]),
              mover("handcarts", "cart", [(0.52, 1.1), (0.52, -1.1)], period=8.0, radius=130, laps=[3])],
    "asphalt": [mover("drillbot", "barrier", [(0.30, -0.95), (0.40, -1.6)], period=12.0, radius=110, cuts_walls=True, opens="drill cut")],
    "rainbowwood": [mover("cyan sludge", "slime", [(0.16, -0.6), (0.16, 0.6)], period=4.0, radius=150),
                    mover("yellow sludge", "slime", [(0.50, 0.6), (0.50, -0.6)], period=4.0, radius=150, laps=[2, 3]),
                    mover("magenta sludge", "slime", [(0.83, -0.6), (0.83, 0.6)], period=4.0, radius=150, laps=[3])],
    "hinnom": [mover("reef current", "water", [(0.60, -1.0), (0.60, 1.0)], period=6.0, radius=160)],
    "palladium": [mover("plasma jelly", "static", [(0.30, -0.7), (0.30, 0.7)], period=5.0, radius=120),
                  mover("plasma jelly", "static", [(0.55, 0.7), (0.55, -0.7)], period=5.0, radius=120, phase=2.5)],
    "tomb": [mover("crematory arm", "barrier", [(0.42, -0.9), (0.42, 0.9)], period=5.0, radius=120),
             mover("fan", "barrier", [(0.50, 0.9), (0.50, -0.9)], period=5.0, radius=120, phase=2.5, laps=[2, 3])],
    "golgotha": [mover("small fauna", "slime", [(0.55, -1.0), (0.55, 1.0)], period=7.0, radius=100)],
}
THROWERS = {
    "redrock": [thrower("baboon (outside)", 0.20, 0.55, 0.15, period=5.0, laps=[1]),
                thrower("baboon (inside)", 0.26, -0.55, 0.15, period=5.0, laps=[1], phase=4.5),
                thrower("baboon (lane)", 0.23, 0.0, 0.2, period=5.0, laps=[2]),
                thrower("baboon (outside)", 0.20, 0.5, 0.2, period=5.0, laps=[3]),
                thrower("baboon (inside)", 0.26, -0.5, 0.2, period=5.0, laps=[3], phase=4.5)],
    "kyakukya": [thrower("falling cap", 0.80, 0.0, 0.5, period=7.0, damage=4, stun=0.4)],
}
# stand-ins the movers and throwers replace (kind, at) on the loop
MOVER_REPLACES = {
    "stilt": [("cart", 0.45), ("cart", 0.52)], "rainbowwood": [("slime", 0.16), ("slime", 0.5), ("slime", 0.83), ("slime", 0.20)],
    "palladium": [("static", 0.3), ("static", 0.55)], "redrock": [("static", 0.20), ("static", 0.26), ("static", 0.23)],
    "tomb": [("barrier", 0.42), ("barrier", 0.50)],
}

# Lap-changing geometry: roads that appear, collapse or thin between laps.
ROAD_STATES = {
    "rustwells": [road_state(0.31, 0.335, [1], "cracked"), road_state(0.31, 0.335, [2, 3], "gap")],
    "thinworld": [road_state(0.15, 0.30, [2, 3], "hologram"), road_state(0.42, 0.50, [3], "hologram"),
                  road_state(0.56, 0.68, [2, 3], "hologram"), road_state(0.74, 0.84, [3], "hologram")],
    "moonstair": [road_state(0.44, 0.50, [2, 3], "hologram")],
}


def place_branch(b, control):
    pts = _loop_points(control)
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    a = pts[int(b["from"] * len(pts)) % len(pts)]
    c = pts[int(b["to"] * len(pts)) % len(pts)]
    dx, dy = c[0] - a[0], c[1] - a[1]
    ln = math.hypot(dx, dy) or 1.0
    nx, ny = -dy / ln, dx / ln
    mx, my = (a[0] + c[0]) / 2, (a[1] + c[1]) / 2
    if (cx - mx) * nx + (cy - my) * ny < 0:     # make +offset point at the centroid
        nx, ny = -nx, -ny
    out = dict(b)
    out["control"] = []
    for f, k in ((0.25, 0.8), (0.5, 1.0), (0.75, 0.8)):
        px, py = a[0] + dx * f + nx * b["offset"] * k, a[1] + dy * f + ny * b["offset"] * k
        out["control"].append([int(px), int(py)])
    out.pop("offset")
    return out


BRANCHES = {
    "joppa": [branch("pond cut", "expert", 0.46, 0.58, 190, 150, 0.4, [haz("water", 0.3, 0.0, 150), haz("water", 0.7, 0.0, 150)])],
    "redrock": [branch("cavern bridge", "safe", 0.30, 0.44, -240, 220, 0.45)],
    "rustwells": [branch("wire bridge", "expert", 0.28, 0.40, 220, 140, 0.35, [haz("jump", 0.5, 0.0, 120)]),
                  branch("outer bypass", "safe", 0.29, 0.36, -230, 220, 0.3, laps=[2, 3], bypass=True)],
    "stilt": [branch("left aisle", "safe", 0.40, 0.56, -210, 240, 0.3), branch("right aisle", "safe", 0.40, 0.56, 210, 240, 0.3)],
    "gritgate": [branch("service tunnel", "safe", 0.34, 0.64, -260, 220, 0.45)],
    "asphalt": [branch("dry outer bend", "safe", 0.45, 0.56, -220, 220, 0.45),
                branch("drill cut", "expert", 0.30, 0.42, -260, 150, 0.4, sealed=True)],
    "golgotha": [branch("second chute", "expert", 0.05, 0.18, 200, 170, 0.4, [haz("poison", 0.5, 0.0, 150, period=4.0, duty=0.4, phase=2.0)])],
    "bethesda": [branch("chrome elevator", "expert", 0.34, 0.42, 240, 150, 0.35, [haz("jump", 0.5, 0.0, 130)])],
    "kyakukya": [branch("root ramp", "safe", 0.28, 0.40, -220, 220, 0.4)],
    "chavvah": [branch("slender branches", "expert", 0.26, 0.34, 260, 130, 0.3, [haz("jump", 0.35, 0.0, 110), haz("jump", 0.7, 0.0, 110)])],
    "hinnom": [branch("water line", "expert", 0.42, 0.50, 200, 170, 0.35, [haz("water", 0.5, 0.0, 170)])],
    "palladium": [branch("inner chute", "expert", 0.56, 0.66, 230, 150, 0.35, [haz("jump", 0.5, 0.0, 130)], laps=[2, 3])],
    "ydfreehold": [branch("red workshop", "expert", 0.36, 0.52, 240, 170, 0.3, [haz("barrier", 0.5, 0.0, 130, period=6.0, duty=0.45)]),
                   branch("violet salon", "safe", 0.36, 0.52, -240, 230, 0.3),
                   branch("surface bypass", "safe", 0.86, 0.96, -200, 200, 0.5, laps=[3])],
    "moonstair": [branch("shortcut crystals", "expert", 0.48, 0.58, 240, 140, 0.35, [haz("static", 0.5, 0.0, 140, period=5.0, duty=0.4)])],
    "hydropon": [branch("centre leaves", "expert", 0.30, 0.62, 300, 150, 0.35, [haz("jump", 0.5, 0.0, 120)], laps=[3, 4, 5])],
    "omonporch": [branch("high line", "expert", 0.58, 0.70, 260, 150, 0.35, [haz("jump", 0.5, 0.0, 130)])],
    "tomb": [branch("recovery corridor", "safe", 0.40, 0.56, -250, 220, 0.45)],
    "thinworld": [branch("Recoming portal", "safe", 0.80, 0.92, -220, 200, 0.5)],
}
# main-loop entries a branch takes over
BRANCH_REPLACES = {"stilt": [("cart", 0.45), ("cart", 0.52)], "palladium": [("jump", 0.60)], "hydropon": [("jump", 0.50)],
                   "bethesda": [("jump", 0.38)], "chavvah": [("jump", 0.30)]}

# Authored elevation: [at, height px] keypoints along the route (unscaled px; the engine
# scales them with the course). The road follows them and the ground shelves around it.
PROFILES = {
    "joppa": [[0, 0], [0.5, 25], [1, 0]],
    "redrock": [[0, 0], [0.15, -60], [0.33, -180], [0.33, -260, "step"], [0.5, -320], [0.62, -300], [0.8, -120], [0.95, 0]],
    "rustwells": [[0, 0], [0.25, -180], [0.45, -260], [0.7, -120], [0.85, 60], [1, 0]],
    "stilt": [[0, 0], [0.2, 60], [0.5, 0], [0.8, 90], [1, 0]],
    "gritgate": [[0, 0], [0.15, -90], [0.6, -90], [0.85, 20], [1, 0]],
    "asphalt": [[0, 0], [0.2, -150], [0.45, -320], [0.6, -360], [0.75, -180], [0.9, -40], [1, 0]],
    # a third element "step" makes a LEDGE: the road drops (or rises) there and the kart falls
    "golgotha": [[0, 0], [0.3, -150], [0.42, -150], [0.42, -330, "step"], [0.6, -380], [0.66, -380], [0.66, -560, "step"], [0.85, -600], [1, -620]],
    "bethesda": [[0, 0], [0.3, -180], [0.7, -380], [1, -420]],
    "kyakukya": [[0, 0], [0.3, 0], [0.45, 120], [0.6, 160], [0.8, 40], [1, 0]],
    "chavvah": [[0, 0], [0.2, 150], [0.45, 380], [0.55, 420], [0.7, 220], [0.9, 60], [1, 0]],
    "eynroj": [[0, 0], [0.28, -40], [0.30, -250, "step"], [0.6, -320], [0.85, -60], [1, 80]],
    "hinnom": [[0, 0], [0.5, -20], [1, 0]],
    "palladium": [[0, 0], [0.5, -40], [0.6, -200], [0.8, 60], [1, 0]],
    "ydfreehold": [[0, 0], [0.3, -40], [0.4, -240], [0.55, -240], [0.75, -60], [1, 0]],
    "moonstair": [[0, 0], [0.2, 150], [0.45, 320], [0.65, 280], [0.85, 80], [1, 0]],
    "omonporch": [[0, 0], [0.55, 0], [0.65, 300], [0.72, 340], [0.8, 60], [1, 0]],
    "tomb": [[0, 0], [0.3, 120], [0.6, 320], [0.85, 520], [1, 600]],
    "thinworld": [[0, 0], [0.28, 100], [0.32, 115, "step"], [0.40, 200], [0.40, 215, "step"], [0.48, 300], [0.48, 315, "step"], [0.5, 360], [0.7, 100], [1, 0]],
}

# Camber (px across the road at a full corner, unscaled) and the leaning tree (lean per lap:
# height per px of position about the map centre; Chavvah leans toward the branch transfer on
# lap 2 and back toward the terrace on lap 3).
CAMBER = {"joppa": 20, "stilt": 15, "kyakukya": 30, "chavvah": 25, "hinnom": 15, "moonstair": 20,
          "omonporch": 40, "thinworld": 25, "redrock": 15, "asphalt": 15}
LEAN = {"chavvah": {2: [0.012, 0.0], 3: [-0.008, 0.006]}}

CUPS = ["Fresh Water Cup", "Chrome Cup", "Canopy Cup", "Reef Cup", "Spindle Cup"]

# The graybox pass (docs/graybox.md): the loops as first drawn lapped in about half the bible's
# target time (the AI field at racing pace runs ~850 px/s), and the section courses ran in a
# sixth of their target run. stretch scales a course's control points and size (widths stay
# in kart widths, hazards and movers sit at fractions, mover periods scale with the path) by
# target / measured lap, capped near 2.2 for a circuit (Chavvah 2.6); the section races were re-routed with about
# twice the road (three regions, one per section) and stretch by their run target instead.
STRETCH = {
    "joppa": 1.81, "redrock": 2.1, "rustwells": 1.10, "stilt": 2.6, "gritgate": 1.79, "asphalt": 2.05,
    "golgotha": 2.33, "bethesda": 2.51, "kyakukya": 2.2, "rainbowwood": 1.8, "chavvah": 2.6, "eynroj": 2.49,
    "hinnom": 2.7, "palladium": 1.9, "ydfreehold": 2.15, "moonstair": 2.1, "hydropon": 1.54,
    "omonporch": 2.7, "tomb": 2.9, "thinworld": 2.17,
}


def smooth_cusps(control, max_turn=120.0, cut=0.28):
    """The graybox's sightline proxy found cusps where two ellipses join (Rainbowwood 167 deg,
    Rust Wells 169): a control point turning more than max_turn becomes two, chamfered a
    share of the way along each neighbouring segment, so the spline rounds the corner."""
    n = len(control)
    if n < 4:
        return control
    out = []
    for i in range(n):
        a, b, c = control[i - 1], control[i], control[(i + 1) % n]
        v1 = (b[0] - a[0], b[1] - a[1])
        v2 = (c[0] - b[0], c[1] - b[1])
        turn = abs(math.degrees(math.atan2(v1[0] * v2[1] - v1[1] * v2[0], v1[0] * v2[0] + v1[1] * v2[1])))
        if turn > max_turn:
            out.append([b[0] - v1[0] * cut, b[1] - v1[1] * cut])
            out.append([b[0] + v2[0] * cut, b[1] + v2[1] * cut])
        else:
            out.append([b[0], b[1]])
    return out


def build():
    tracks = []
    for c in COURSES:
        t = dict(c)
        t.setdefault("size", [W, H])
        t["control"] = smooth_cusps([list(p) for p in t["control"]])
        k = STRETCH.get(t["key"], 1.0)
        if k != 1.0:
            t["control"] = [[x * k, y * k] for x, y in t["control"]]
            t["size"] = [t["size"][0] * k, t["size"][1] * k]
            t["stretch"] = k
        t.setdefault("laps", 3)
        if int(t.get("sections", 0)) > 0:
            t["laps"] = 1                 # one way: the far end is the finish
        t.setdefault("spoiler", False)
        # the engine's legacy paths, so older code reading spec["walls"][2] keeps working
        t["floor"] = ["tiles", "tilesets", t["tileset"], t["tileset"] + " floor", "floor"]
        t["walls"] = ["tiles", "tilesets", t["wallset"], t["wallset"] + " wall"]
        t["road_color"] = t.pop("road")
        fixed = [h for h in t.get("hazards", []) if h["kind"] != REPLACED.get(t["key"])]
        hz = fixed + TIMED.get(t["key"], [])
        gone = LAPPED_REPLACES.get(t["key"], [])
        hz = [h for h in hz if (h["kind"], h["at"]) not in gone]
        t["hazards"] = hz + LAPPED.get(t["key"], [])
        if t["key"] in LAP_NOTES:
            t["lap_notes"] = {str(k): v for k, v in LAP_NOTES[t["key"]].items()}
        gone = BRANCH_REPLACES.get(t["key"], [])
        t["hazards"] = [h for h in t["hazards"] if (h["kind"], h["at"]) not in gone]
        t["branches"] = [place_branch(b, t["control"]) for b in BRANCHES.get(t["key"], [])]
        if t["key"] in ROAD_STATES:
            t["road_states"] = ROAD_STATES[t["key"]]
        gone = MOVER_REPLACES.get(t["key"], [])
        t["hazards"] = [h for h in t["hazards"] if (h["kind"], h["at"]) not in gone]
        if t["key"] in MOVERS:
            t["movers"] = [dict(m, period=m["period"] * k) for m in MOVERS[t["key"]]]
        if t["key"] in PROFILES:
            t["profile"] = PROFILES[t["key"]]
        if t["key"] in CAMBER:
            t["camber"] = CAMBER[t["key"]]
        if t["key"] in LEAN:
            t["lean"] = {str(k): v for k, v in LEAN[t["key"]].items()}
        if t["key"] in THROWERS:
            t["throwers"] = THROWERS[t["key"]]
        t["control"] = [[int(x), int(y)] for x, y in t["control"]]
        tracks.append(t)
    return tracks


def main():
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    path = os.path.join(repo, "shared", "tracks.json")
    old = {}
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            old = json.load(f)
    keep = [t for t in old.get("tracks", []) if t.get("city")]      # the OSM city track stays as a guest
    for t in keep:
        t.setdefault("cup", "Guest Cup")
        t.setdefault("cup_index", 99)
        t.setdefault("difficulty", 3.0)
        t.setdefault("sentence", "A random closed route through the Chicago Loop's real streets, sealed with Qud brick.")
    out = {
        "_comment": "The 20 courses of the Track Design Bible (mutant-plan/strategy/2caves2qud-tracks) as engine data, generated by tools/qud_tracks.py — edit THAT and rerun. Coordinates are unscaled world px; both paths apply tuning.race.track_scale. tileset/offroad/wallset are Qud biomes (tools/export_godot_assets.py TILESETS). hazards: fixed surface patches at route fractions (kind ice|fire|poison|water|oil|slime|static, at 0..1, side -1..1 of the road, radius px). 'spells' are the Qud items that appear on the course as scrolls. 'gaps' lists what the bible asks for that the engine cannot build yet.",
        "cups": CUPS + ["Guest Cup"],
        "tracks": build() + keep,
    }
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)
        f.write("\n")
    print("wrote %d tracks to %s" % (len(out["tracks"]), path))


if __name__ == "__main__":
    main()
