# Local multiplayer

Up to four people in one race on one screen. Pick **LOCAL MULTIPLAYER** on the
race type page (or press `5`), take a seat, choose an outfit, ready up, and seat
1 starts the race. Each human drives their own kart in their own split-screen
panel with their own action bar, HP, coins and item. The CPU field is filled
with wizards in other outfits, and the realm-built tracks, scrolls, speed coins
and monsters work exactly as in a solo race.

## The lobby

Press any button on a keyboard side or a gamepad to take a seat. Seats fill in
order and each has a colour that is also the kart's name tag on the road.

| control | keyboard left | keyboard right | gamepad |
| --- | --- | --- | --- |
| steer / drive | WASD | arrows | left stick or d-pad, RT drives, LT brakes |
| drift | Shift | numpad 0 | A |
| cast the selected slot | F | numpad 1 | X |
| use item | E | numpad 2 | B |
| next / previous slot | R / Q | numpad 3 / numpad . | RB / LB |
| pause | Tab | numpad Enter | Start |

In the lobby: left/right (or the slot buttons) cycle the outfit, drift or cast
readies, item unreadies or, when unready, gives the seat back. When everyone is
ready, seat 1 presses drift or cast to start. `Esc` returns to the race types.

A pad pulled out mid-lobby leaves its seat waiting ("controller unplugged");
the next pad that presses a button takes that seat, with its outfit and ready
state.

## Party rules

The party race uses arcade rules rather than the campaign's single wizard:

- every human has its own HP (the campaign's max HP), spells and coins;
- scrolls on the road go on the bar of the kart that drove over them, up to
  the ten-slot limit; a duplicate refills a charge;
- one button casts the selected slot, bumpers or the slot keys move the
  selection, and the panel HUD shows the spell, its charges or cooldown and
  the slot number;
- a human at zero HP is wrecked for three seconds (`party_respawn` in
  `shared/tuning.json`) and comes back where it fell with full HP;
- each human's laps count separately, and the race ends when every human has
  finished; the results list humans first, then the field.

## Split screen

`godot/mp/ViewLayout.gd` picks the panel grid: one human gets the whole
screen, two are side by side, three and four a 2x2. Each panel is a
`SubViewportContainer` sharing the race's world with its own camera (chase
camera behind that kart) and its own HUD layer. The main HUD keeps only the
banner messages.

## The input stack (from playgraph)

`godot/mp/` is the salvageable part of the playgraph repo, ported under its MIT
licence:

- `DeviceState` (real or fake) is the only thing that reads the engine, so the
  adapters can be tested with no hardware;
- `ButtonEdges` turns "down" into "pressed this tick", `ButtonDebounce` drops
  one-tick glitches;
- `DriveFrame` is the normalized per-tick command (steer, throttle, drift,
  cast, item, next/prev, pause, confirm, back), the same shape whether it came
  from a keyboard, a gamepad, a script or, later, a phone or a network peer;
- `KeyboardAdapter` (two slots) and `GamepadAdapter` (deadzone 0.22, three
  tick settle after a hot-plug) produce frames; `DriveAdapter` caches one
  frame per tick;
- `Players` (autoload) is the join hub and roster: press-to-join, seat
  assignment, orphan reclaim, `join_with(controller_id, adapter)` for any
  transport.

Not ported: playgraph's phone-as-controller (LAN websocket + QR code) and its
own game logic. The phone path can be added later as another adapter feeding
`Players.join_with`.

## Debug flags

```bash
"<godot.exe>" --path godot -- --auto --newrun --map=brick --party=3 --frames=360 --screenshot=out.png
"<godot.exe>" --headless --path godot -- --auto --newrun --map=brick --party=4 --seconds=60 --timescale=4 --rig=
"<godot.exe>" --path godot -- --mode=lobby --party=3 --frames=60 --screenshot=lobby.png
```

`--party=N` seats N debug players (with `--auto`, every human is driven and
casts by the demo driver, through the same party code as a real press).
`--mode=lobby --party=N` seats fake players on the lobby page; the menu takes
`--frames`/`--screenshot` like the other scenes.

## Steam: install and lobbies

Online play goes through Steam. The GodotSteam GDExtension (MIT) wraps the
Steamworks SDK; its binaries are not committed. Fetch them once:

```bash
python tools/get_godotsteam.py
```

then `godot --headless --path godot --import` registers the extension. The
`Net` autoload (`godot/net/SteamNet.gd`) initialises Steam under app id 480
(Valve's SpaceWar test app, until Drift Wizard has its own) and degrades to
"Steam not running" if the client or the plugin is missing, so every other
mode works without it.

**ONLINE (STEAM)** on the race type page (or `6`):

| key | action |
| --- | --- |
| H | host a public lobby (tagged `game=driftwizard3`, `protocol`, name, host, max 4) |
| R | refresh the lobby list (also polled every five seconds) |
| 1..9 | join that lobby from the list |
| I | invite friends through the Steam overlay; an accepted invite joins the lobby |
| L | leave the lobby |
| Esc | back (leaves the lobby) |

The list is filtered by the game key, so only Drift Wizard lobbies show even
though app 480 is shared with every other developer's test builds. A lobby
with another protocol number is listed but marked "other version". Lobby
chat is wired (`Net.say`, the `chat` signal) as the first message channel.

Self test, two headless processes:

```bash
"<godot.exe>" --headless --path godot -- --nettest=host --seconds=16
"<godot.exe>" --headless --path godot -- --nettest=browse --seconds=12
```

The host creates a lobby, refreshes every two seconds and answers chat; the
browser refreshes until it sees a Drift Wizard lobby, joins it and says hello.
Both print a `nettest:` summary line. One caveat: with two processes signed
in as the same account on one Steam client, only the process that created the
lobby receives lobby list results, so on a single machine this proves hosting
and listing but not joining. The join and chat paths need a second account.

## Steam: racing

The host presses **S** in the lobby (**M** cycles the map among the
`tracks.json` tracks). The lobby data flips to `racing` with the map and seed,
every guest changes scene, and the race runs host-authoritative:

- **Host.** The race is a party race whose remote humans are `RemoteAdapter`s:
  each guest's `DriveFrame` arrives over the network and is merged into the
  next tick (latest axes, every press kept). The host simulates everything and
  sends a state message twenty times a second (per kart: position, heading,
  velocity, HP, lap, rank, flags, respawn, coins, item, shields, drift, boost,
  stun, finish time; per guest: its spell bar and selected slot) plus reliable
  events for what needs drawing: casts, item uses, hits, deaths, wrecks,
  respawns, pickups taken and spawned, per-player messages, and the results.
- **Guest.** Builds the same track from the map and seed, sends `hello` until
  the host answers with the setup (laps, every kart with its id, name, unit and
  stats, every pickup), spawns those karts, then eases each one toward the
  reported position with the reported velocity. It sends its own frame every
  tick (reliably when a button was pressed), replays casts and item uses
  locally for the visuals, and never applies damage itself. Its HUD is the
  party panel fed from the host's numbers. Escape leaves the race.
- **Wire format.** Messages are `var_to_bytes` arrays. Over Steam they go
  through networking messages (`sendMessageToUser`, relay access is brought up
  when a race starts); over UDP they go as plain packets.

Not replicated yet: escort summons and the decorative wandering mobs, and the
host pausing (it never pauses online; the shop is off).

### UDP loopback and LAN

The same race runs without Steam over UDP, which is how it is tested on one
machine and how a LAN game could work:

```bash
"<godot.exe>" --headless --path godot -- --online=host --port=47001 --guests=1 --auto --newrun --map=brick --seed=3 --seconds=60 --timescale=3
"<godot.exe>" --path godot -- --online=guest --port=47001 --auto --newrun --map=brick --seed=3 --frames=900 --screenshot=guest.png
```

`--guests=N` reserves seats the first N addresses to say hello take; `--auto`
on the guest drives its kart with the AI through the network. Both print an
`online:` line at the end (seat, karts, lap, progress, rank, spells, pickups)
that must agree between the processes. `--host_ip=` points a guest at another
machine.

### Exit crash, fixed

Signals connected on the Steam singleton must be disconnected in
`_exit_tree`, or the extension calls into the freed autoload while tearing
down and every run ends in an access violation. `Net` keeps its connections
in a list for that, then calls `steamShutdown()`.

## The Python build

The mod that runs inside Rift Wizard 3 can get the same feature under the
game's own app id. The game bundles `steam_api64.dll` (and a SteamworksPy
wrapper that only exposes create/join/leave lobby and friend invites). The
DLL's flat C API does export the rest: `SteamAPI_ISteamMatchmaking_*` (lobby
list with filters, lobby data, members, chat), classic
`SteamAPI_ISteamNetworking_*` P2P packets, and `SteamAPI_ManualDispatch_*`
for callbacks, so a `ctypes` layer of a few hundred lines gives the mod
lobbies and P2P without new binaries. It does not have the newer
`ISteamNetworkingMessages`, so the Python side would use the older P2P packet
API. What both builds share is the wire protocol (drive frames and kart state
messages), not the code.
