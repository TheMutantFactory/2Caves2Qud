# Rulebook export

`tools/export_rules.py` turns the game's data into a set of files an LLM (or a
human) can reason about when rewriting Drift Wizard's rules:

```bash
.venv/Scripts/python tools/export_rules.py
```

writes `extracted/rules/` (gitignored: it is the game's own text and numbers):

| file | contents |
| --- | --- |
| `rules.json` | how the game's numbers work (levels, charges, HP costs, ranges, tags, roles), damage types, tag list, constants |
| `spells.json` | the 186 player spells: level, tags, damage types, range, charges, HP cost, melee/self flags, stats, description, upgrades |
| `artifacts.json` | the equipment: tags, recipe, global/tag/spell bonuses, description |
| `monsters.json` | every unit: HP, shields, tags, resistances, flags, roles (spawn band, rare tier, final boss), its spells and passives |
| `kart.json` | what Drift Wizard currently makes of each spell and artifact (SpellDB.effect_for, Artifacts.effect_for), the mapping rules in words, and shared/tuning.json |
| `rulebook.md` | one compact Markdown digest of all of the above, one line per spell/artifact/monster with the kart mapping appended |

`kart.json` comes from the Godot build itself (`--mode=dump`), so it always
matches the code. Regenerate after a game update (extract_data.py first) or
after changing SpellDB, Artifacts or the tuning.

For a rules pass, hand the LLM `rulebook.md` (about 200 KB) or the JSON files
it needs, together with docs/campaign.md and docs/test-rig.md, and ask for
changes as edits to SpellDB.gd's mapping or the tuning file; the rig suite
(`tools/rig_test.py --all-spells`) then checks every spell still does
something.

## Feeding the answer back

`shared/overrides.json` is read by the Godot build after the automatic
mapping: `"spells": {name: {fields}}` replaces those fields of the spell's
effect dict, `"artifacts": {name: {bonuses}}` replaces the artifact's whole
bonus set, and `notes` are ignored. Copy it to `godot/rw3/shared/` (the
exporter does) and run `tools/rig_test.py --all-spells`. The prompt that asks
an LLM for exactly that file is in [rules-pass-prompt.md](rules-pass-prompt.md).
