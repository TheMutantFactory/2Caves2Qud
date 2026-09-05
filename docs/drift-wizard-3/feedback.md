# Feedback

Pause in Rift-Type (Esc, Tab or P) and press **F**. The feedback panel lists
everything in the current realm a person might want to talk about: you, the
boss, every monster species, your party, your spells, upgrades and artifacts,
the Force, the tavern, chests, rifts, XP orbs, the corridor. Leave the first
line selected for general notes, or pick a thing: the box on the right becomes
a mini level where that thing does what it does in the game, on a loop. A
monster flies its pattern and casts each of its abilities at a dummy wizard
(bolts, beams, summons of the thing it really summons, rings, rain, clouds,
lunges, blinks, heals, shields, buffs); the boss cycles its phases; a
companion fights beside the wizard against a dummy goblin; a spell is cast at
a dummy; upgrades, artifacts and pickups show as a card. The caption names the
ability being cast so words and picture line up.

Write in the box, **ctrl+enter** or SEND saves, **esc** or BACK returns to the
pause menu. Nothing leaves the machine yet.

## Where it goes

Entries append to `user://feedback.jsonl`, one JSON object per line. On Windows
that is `%APPDATA%\Godot\app_userdata\Drift Wizard 3\feedback.jsonl`. The
panel prints the full path after a save.

```json
{
  "time": "2026-09-05T18:22:41",
  "game": "drift-wizard-3",
  "version": "",
  "object": {"kind": "monster", "name": "Goblin", "unit": "goblin"},
  "text": "goblins swarm too fast on realm 2",
  "context": {
    "mode": "rifttype", "realm": 2, "tileset": "volcano", "t": 41.3, "state": "playing",
    "level": 3, "score": 410, "kills": 22, "hp": 18, "max_hp": 40,
    "upgrades": {"Twin Bolt": 1}, "spells": ["Fireball"], "party": ["Ranger"], "artifacts": [],
    "skin": "player_elephant", "boss_reached": false, "seed": 12345
  }
}
```

`object` is `null` for general feedback. `kind` is one of wizard, boss,
monster, companion, spell, upgrade, artifact, thing.

## The Cloudflare hookup, later

The line format is the wire format. A Worker endpoint that accepts a POST of
one entry (or an array of them) and writes to KV, D1 or R2 needs nothing more
from the game than an upload step: read the jsonl, send what has not been
sent, mark the lines. An opt-in toggle and a player handle belong in the
context when that arrives. `FeedbackPanel.save(entry)` is the one place
entries are written, so the upload hooks in there or reads the file.

## Reuse

`FeedbackPanel` (godot/Feedback.gd) takes a list of showcase objects, a
context dictionary, the realm and its tileset; `Showcase` (godot/Showcase.gd)
draws any of those objects. The racing and Survivors modes can hand in their
own lists the same way.

## Testing

```bash
"<godot.exe>" --path godot -- --mode=rifttype --realm=3 --seed=6 --auto --mute --screen=feedback --frames=120 --screenshot=out.png
```

`--screen=pause` stages the pause menu; `--screen=feedback` opens the panel
with the first object (the boss when the realm has one) in the showcase.

## Acted on

- 2026-09-05, Necromancer: "should bring living creatures back as skeletons,
  read the description". It did in the game and not here: none of the
  companions' passives had been ported, only their spells. All thirteen now
  carry their passives (see docs/rift-type.md, The tavern and the party), the
  tavern card quotes the game's own tooltip, and the showcase acts them out.
