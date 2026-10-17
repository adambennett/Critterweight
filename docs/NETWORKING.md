# CRITTERWEIGHT networking

Server-authoritative multiplayer over ENet with our own versioned binary protocol (decision D-014).
Code: `game/src/net/`. Tests: `game/src/test/net/`. Dedicated server operation: [SERVER.md](SERVER.md).

> **Evidence label.** Every result in this document comes from processes on **one Windows 10
> machine talking over loopback (127.0.0.1)**, optionally through the in-process network
> conditioner. That proves the protocol, authority and session behaviour; it is **not** evidence of
> off-machine internet connectivity (NAT, real routers, real loss). See §11.

## 1. Model

| Topic | Decision |
|---|---|
| Authority | The server (listen host or dedicated) runs the only `MatchSim`. Clients send input and requests; damage, KOs, results, rewards and progression are decided only on the server. |
| Simulation | Jolt physics + fighter logic at **120 Hz** fixed step (`server.tick_rate`, tuned at 120). |
| Client input | `FighterInput` (world-space move, held bits, per-button press counters) sampled every client physics tick, sent at **60 Hz**, each packet carrying the 4 newest samples (redundancy). |
| Server output | Full-state **snapshots at 30 Hz** (unreliable) + simulation **events** (reliable, tick-stamped) + roster changes (reliable). |
| Client view | No local simulation, no prediction/rollback: active ragdolls cannot be reconciled, so clients render an **interpolated** past (adaptive buffer: 40-90 ms measured over loopback, depending on machine load) and fire event feedback when the render clock reaches the event's tick. |
| Listen host | The host's fighter is driven by `LocalPlayerInput` inside the authoritative sim: **zero added latency** for the host. |
| Randomness | Owned by the server: the match seed (server RNG) drives bots and modes; it is stripped from replicated events. Clients never roll dice that affect outcomes; cosmetic randomness (particles, gore piece spin) is local. |
| Determinism | Not relied upon across machines. Same build + seed + inputs reproduce locally (sim tests), but the network model never assumes cross-machine float determinism. |

## 2. Roles and processes

| Role | How | Owner node |
|---|---|---|
| Listen host | `Net.host(cfg)` in the game (or `--host`) | `NetServer` + the normal `MatchScene` (`App.start_match`) |
| Client | `Net.join(addr, port, pwd)` (or `--connect host:port`) | `NetClient` + `NetMatchScene` |
| Dedicated server | `--server --config <file>` (headless) | `NetDedicated` -> `NetServer` (sim stepped by the server) |
| Test participant | `--net-client` (scripted, headless; `src/test/net/net_test_client.gd`) | `NetClient` / `NetServer` |

## 3. Ticks and timing

* Server physics frame order: `NetServer` (priority -100) services the network (applies inputs),
  sends the events and - every 4th tick - the snapshot of the **last completed** tick, then the sim
  steps (dedicated) or `MatchScene` steps it (listen). Snapshot `tick` N therefore pairs logic and
  physics of the same tick, and events emitted during tick N carry tick N.
* Client input: sampled each physics tick (`Controls.fill` with the camera basis - the
  `LocalPlayerInput` equivalent), sent every 2nd tick (60 Hz) with sequence numbers.
* Server input jitter buffer (`NetRemoteInput`): one sample per 1/60 s of sim time; backlog > 3
  samples collapses (press counters are cumulative, so no press is lost); starvation holds the
  last sample and neutralizes move/held after 0.25 s. Counters are re-based when a client (re)binds
  so rejoining never creates phantom presses.
* Client clock (`NetReplica`): the largest recent (snapshot time - arrival time) offset estimates
  server time; `render_time = server_time - target_delay`, advanced at local rate with +-10 %
  drift correction (re-sync on > 0.25 s error). `target_delay` (setting `network.interp`, applied
  live to the running connection): `low` = 1 interval + median jitter; `auto` = 1 interval +
  95th-percentile jitter + 5 ms; `high` = 2 intervals + 99th-percentile jitter + 10 ms (clamped
  25-500 ms). The listen host's own view never interpolates, so the setting does not apply there.
* Heartbeat: clients ping every second (unreliable); the server answers. Both sides declare the
  link dead after `timeout` seconds without any packet (setting `network.timeout`, applied live to
  a running client or listen host / `server.timeout`); ENet's own retransmission timeout is a
  backstop.

## 4. Transport

`ENetConnection` used directly (not the scene RPC layer), one host per process.

| Channel | Mode | Carries |
|---|---|---|
| 0 control | reliable, ordered | handshake, lobby, chat, notices, app messages, ping/pong (unreliable), closing/kick |
| 1 events | reliable, ordered | `MATCH_START`, roster changes, event batches, `MATCH_END` (one ordered stream per match) |
| 2 snapshot | unreliable, sequenced | snapshots (`FLAG_UNRELIABLE_FRAGMENT`, never retransmitted) |
| 3 input | unreliable, sequenced | client input samples |

Because `MATCH_START`, roster and events share channel 1, a client always knows a match and the
fighter in a slot before any event refers to them; snapshots carry the match id and are dropped
when they belong to another match. Disconnects carry a reason code (ENet disconnect data) as a
fallback when the reason message itself could not be delivered.

## 5. Protocol (version 5)

Every packet: `[u8 message id][payload]`. Ids 1-63 client->server, 64-127 server->client; the wrong
direction, an unknown id, the wrong channel, an oversized payload or a failed bounds-checked decode
is a **protocol violation**. Layouts are documented in `src/net/net_protocol.gd`,
`net_snapshot.gd`, `net_event_codec.gd`; primitives in `net_writer.gd`/`net_reader.gd`.

| Id | Name | Dir | Max | Payload |
|---|---|---|---|---|
| 1 | HELLO | C->S | 16 KB | protocol, game version, gameplay content hash, packages (<= 64) [{id, version, hash, client_only}], name, password proof, rejoin token, flags, creature, aim assist (x100) |
| 2 | LEAVE | C->S | 16 B | - (graceful leave: no rejoin reservation) |
| 3 | LOBBY | C->S | 1 KB | kind (ready, creature, team, spectate, assist, cosmetics) + value |
| 4 | CHAT | C->S | 600 B | text (<= 200 chars after cleaning) |
| 5 | VOTE | C->S | 16 B | candidate index (-1 = none) |
| 6 | INPUT | C->S | 256 B | seq, last snapshot tick, n (1-8), n x sample (4 + BUTTON_COUNT bytes) |
| 7 | APP | C->S | 64 KB | type, payload (plain data) |
| 8 | PING | C->S | 32 B | client ms |
| 64 | CHALLENGE | S->C | | protocol, game version, server name, 16-byte nonce, flags, players, max players, gameplay content hash, packages [{id, version, hash, client_only}] |
| 65 | WELCOME | S->C | | player id, rejoin token, flags (rejoined, spectator, dedicated), name, tick/snapshot rate, motd |
| 66 | REJECT | S->C | | reason code, message, detail lines |
| 67 | LOBBY | S->C | | lobby state (dictionary) |
| 68 | CHAT | S->C | | from id, name, text |
| 69 | NOTICE | S->C | | text |
| 70 | MATCH_START | S->C (ch 1) | | match info (arena dictionary + content hash - its look as `variant` -, arena package for a player-made layout, rules, mode, roster, AI Lab policies with their hashes, your fighter, tick/snapshot rates; a co-op campaign fight adds `campaign` {name, encounter, rule_tags, format, stand_in, run_id, node, tier} and carries the campaign's own fixed rules, checked by `NetProtocol.campaign_match_problem` instead of the rules editor's validator) |
| 71 | SNAPSHOT | S->C (ch 2) | | match id, tick, input ack, body (§6) |
| 72 | EVENTS | S->C (ch 1) | | base tick, events (§6) |
| 73 | MATCH_END | S->C (ch 1) | | result (winner, rounds, stats, players, entry, aborted) |
| 74 | APP | S->C | | from id, type, payload |
| 75 | CLOSING | S->C | | reason, message, restarting flag |
| 76 | KICKED | S->C | | reason code, reason text |
| 77 | PONG | S->C | | echo, server ms |
| 78 | ROSTER | S->C (ch 1) | | tick, changed slots (§6) |

**Handshake.** ENet connect -> server sends CHALLENGE (a fresh nonce, plus its gameplay content
hash and gameplay package list) -> the client checks the protocol version and the game version
(a different build is "update the game", never reported as a content problem), then compares
content on its own side with `Mods.compare(server packages)` (MOD-05, below). If that fails it stops right there with
`content_mismatch` and the Mods wording ("Missing mod: moon_rules 1.0.0 (install it, then enable
it)", "You have X enabled but the host does not (disable it to join)", "Different version of X: you
have A, the host has B") and closes with that reason code, which the server logs. Otherwise it
answers HELLO with `sha256(nonce + "critterweight:" + password)` (the password never travels in
clear) -> the server checks, in order: protocol version, game version, content (the same verdict
over `Mods.compare(client packages)` - the authority, so a modified client cannot skip it; its
REJECT lists the differences from the player's side), kick bans, password, capacity (players, then
spectators) -> WELCOME or REJECT. A valid rejoin token skips the capacity check and rebinds the
player's reserved slot. Handshakes must finish within 5 s; at most 24 pending (8 per address). The
challenge prefix (protocol, game version, name, nonce, flags) is the same in every protocol
version, so a mismatched protocol is always recognised and never misread as a content problem.

**Content verdict** (`NetProtocol.content_verdict(Mods.compare(theirs), theirs, same_gameplay_hash)`,
symmetric, unit-tested): a gameplay package that is missing, extra or of another version blocks;
`client_only` (presentation-only) packages never count and never travel (lists carry at most 64
gameplay packages, core included; more is refused up front with a clear message); a package with the same version but a
different package hash (a folder install vs. the same package as an archive, edited textures)
passes only when both gameplay content hashes are equal - the simulation cannot diverge - and is
logged; identical package lists with different gameplay hashes are refused as "same packages and
versions, but their gameplay files differ". The client's `connection_failed` reason then carries
`details` (the UI lines above) and `mods` {`missing`, `extra`, `mismatched`, `modified`} (ids, e.g.
for a button that opens the Mods screen).

**Rejection and disconnect reasons** (`NetProtocol.describe(code, details)` returns
`{code, title, message, details}` ready for a dialog):

| Code | Name | Title / message (abridged) | Details |
|---|---|---|---|
| 1 | incompatible_protocol | Incompatible build: different network protocol | both versions |
| 2 | incompatible_build | Incompatible build: different game version | both versions |
| 3 | content_mismatch | Content mismatch | `Mods.compare` lines per package (missing / enabled here but not on the host / different version / modified copy), or "same packages, different files"; plus `mods` {missing, extra, mismatched, modified} |
| 4 | server_full | Server full | player/spectator counts |
| 5 | bad_password | Wrong password | |
| 6 | kicked | Kicked (with reason); also returned while banned | seconds until rejoin allowed |
| 7 | handshake_timeout | Connection failed | |
| 8 | protocol_violation | Disconnected (invalid data) | |
| 9 | server_shutdown | Server closed (admin message) | "restarting" hint |
| 10 | host_left | The host left the session | |
| 11 | timeout | Connection lost (timed out) | |
| 12 | flood | Too much data (flood protection) | |
| 13 | left | You left the session | |
| 20 | connect_failed | Could not reach the server (address/port/port forwarding) | |
| 21 | local_error | Network session could not start (port in use ...) | |
| 22 | replaced | Connected again from another session | |

**Limits and abuse handling (server).** Per player token buckets: input 150/s (burst 60), control
30/s, chat 1/s (burst 5), app 40/s, bytes 128 KB/s (burst 640 KB -> immediate kick, "flood").
A relayed party message costs the sender one app token and its size in bytes per recipient (the
server sends one copy each), and may be at most 16 KB, so the relay cannot multiply a client's
upload. Buckets refill with the larger of wall-clock and simulated time: the
same thing in real-time runs, and under `--fixed-fps` test runs (faster than real time) a client's
60 inputs per simulated second are not mistaken for a flood.
Violations add points (unknown id 6, malformed 3-5, rate excess 0.25-0.5, host-only request 2)
that decay at 2/s; 20 points = kick (`protocol_violation`) and a temporary ban. Oversized packets
kick immediately. Input samples are clamped (move length <= 1, undefined held bits masked).
ENet itself accepts reliable packets up to 32 MB before the application sees them; the server
kicks on the first oversized one, but the per-peer ENet buffer is not configurable from GDScript
(known limit).

## 6. Serialization

**Primitives** (little endian): u8/i8/u16/i16/u32/i32/u64/f32, LEB128 varint and zig-zag svarint,
length-prefixed UTF-8 strings (u8 or u16 length, truncated on a character boundary), blobs.
Quantized: `vec3q` = 3 x int16 at 1/1024 m (+-32 m, <= 0.5 mm error); `quat32` = smallest-three
quaternion (2-bit index + 3 x 10 bits, < 0.15 deg error, measured 0.125 deg worst over 5000 random
rotations). The reader never reads past the end: the first failure flags the whole decode.

**Snapshot body** (`NetSnapshot`, full state - any snapshot may be lost):

```
[u8 slots] per slot: [u8 generation (0 = empty/despawned)]
   [u8 state][u8 flags: juiced, evading, crash, guard, grounded, ai, hidden][vec3q root]
   [u8 n][quat32 x n segment rotations]
   [u16 x6 health/max, stamina/max, poise/max (x10)][u8 hype][i8 lives][i8 target]
   [cooldowns: u8 n x (str slot, u16 s x100)] [statuses: u8 n x (str id, str element, u16 s x100)]
[u8 entities] per: [u16 id][u8 kind][str zone_kind/prop][str vfx][vec3q pos][u16 radius][str element][i8 team]
[u8 dynamic props] per: [u8 index][vec3q pos][quat32 rot]
mode: [u8 phase][u8 round][u16 timer x10][u8 flags][i8 winner][i8 round winner]
      [teams: u8 n x (i8 team, u8 wins, i16 score)] [str hud status]
      [tagged value: MatchMode.view_state()] [tagged value: MatchMode.hud_state()]
```

Segment **positions are not sent**: every rigid body sits on its joint pivot (BodyDef invariant), so
clients rebuild them by forward kinematics (`origin_child = origin_parent + rot_parent *
(pivot_child - pivot_parent)`). Measured against the live simulation: worst segment error
under 2 mm / 0.125 deg (`test_net_snapshot.gd`). Static props and hazard zones are not sent (the arena
definition in MATCH_START builds them).

**Roster** (`ROSTER` and MATCH_START): per slot `{generation, creature id, body scale, team, name,
controller kind, despawned, tags}`. The server bumps a slot's generation whenever its body changes
(spawn into a reused slot, despawn, rebuild with a scaled creature such as the Absolute Unit);
clients only interpolate between snapshots of the same generation and rebuild a creature view when
the generation changes. `tags` are the fighter's true boolean flags (`headliner`, `boss`,
`resting`, ...) for presentation.

**Events** (`NetEventCodec`): `[u32 base tick][u8 n]`, per event `[type: u8 table index | 0xFF +
string][svarint tick delta][u8 fields]`, per field `[key: u8 table index | 0xFF + string][tagged
value]`. Tagged values: null, bool, int (svarint), f32 (non-finite allowed), string (u8) or common
string (u8 index), Vector2, Vector3 (vec3q, or 3 x f32 when out of range/non-finite), Color (4 x u8),
Array (<= 256), Dictionary (<= 128 entries, String or int keys); depth <= 8, <= 4096 values per decode.
Unknown types/keys travel as strings, so events added by other systems replicate without protocol
changes (the parity test lists those without a 1-byte id). `seq` is implicit; `seed` never leaves
the server.

**Input sample**: `[i8 move.x x127][i8 move.z x127][u16 held][u8 x BUTTON_COUNT press counters]`
(same layout as `FighterInput.encode`; 15 bytes with the TAG button).

**Lobby, MATCH_START, MATCH_END** use Godot `var_to_bytes` of plain dictionaries (never objects;
`bytes_to_var` refuses objects) inside our framing; they come only from the server. **App
payloads** in both directions use the same encoding and are validated (`NetProtocol.decode_payload`:
dictionary root, only plain value types, finite numbers, strings <= 8192 chars, depth <= 12,
<= 8192 values, <= 64 KB).

## 7. Client presentation

`NetMatchScene` reuses the local views: `ArenaView` (built from the arena definition the client
checked before the match: its own copy, or the host's layout package, see §13), `CreatureView` per
roster slot, `Vfx`,
`FightCamera`, `FightHud`, `ModeView` and the audio bridge. A **presentation mirror**
(`NetHudMirror`) is a `MatchSim` with `Fighter` objects that are never stepped: it carries
replicated vitals, statuses, cooldowns, targets, mode timers/scores/`hud_state()`/`view_state()`,
effect entities, a rig stand-in (root position and velocity) and the replicated events, so
`FightHud`, `ModeView` and `AudioMatchBridge` (`Audio.attach_match`) run unchanged. Event feedback
mirrors `MatchScene._on_event`; `test_net_parity.gd` fails if `MatchScene` reacts to an event that
`NetMatchScene` does not. Large jumps (> 2.5 m between snapshots: respawn, round reset, blink) snap
instead of sliding. Mode choices offered to the local player (Chum Rush supplement picks) open the
same pick panel and are sent as a `mode.pick` request that the server validates; the server takes
the first offer for a remote player who has not answered after 20 s, and a dropped player's bot
takes it at once, so nobody can stall the break between waves. Damage numbers
follow `gameplay.damage_numbers`; achievements tied to the local player's own fighter (JUICE KO,
hat trick, wave 20) unlock from the server's events, like local play. **Spectators** get the
broadcast auto-director (`SpectatorDirector` on the mirror) and the same controls as local
AI-vs-AI spectating: Y / R director or free camera, LB/RB (Q/E) lock on a fighter, X / Delete hide
the HUD. Playback speed stays 1x online. KO stars and callouts match local play; the F3 combat
debug drawing needs the simulation's bodies, so it exists for local players and the
listen host only.

**Aim assist** (`access.target_assist`: low 0.5, normal 1.0, high 1.8) is an accessibility option
that changes how attacks snap toward the target, so it lives in the authoritative simulation
(fighter entry `mods["assist"]`, exactly as `MatchScene` does for local players) - it cannot be
presentation-only. A client sends its level in HELLO and again (`LQ_ASSIST`) when the setting
changes (used from the next match). The server never takes a number from the client: it snaps the
request to one of the setting's three levels (what any player can pick), and with
`match.player_assist = false` (or `Net.host({"player_assist": false})`) it gives every remote
player the normal level instead. Nothing else gameplay-related comes from clients.

**Cosmetics** (presentation only): each player's equipped cosmetics - wearables, the name-card
frame, the JUICE colour (Sizzle) - travel as `{slot: id}` with the player info: the active
profile's owned, equipped items (the Cannery locker, `camp.hub.loadout.cosmetics`) go out after
the join (`LQ_COSMETICS`; `Net.set_cosmetics()` changes them, `Net.session_cosmetics()` reads
them; a listen host's own come with `Net.host()`). The authority keeps only known items worn in
their own slot (`NetProtocol.clean_cosmetics`: content kind `hub`, `type: cosmetic`, matching
`slot`; in `frame`, also the headliner badge of an installed fighter), shows them in every lobby
player row (`players[].cosmetics`) and puts each human fighter's set into MATCH_START
(`cosmetics` {fighter index: {slot: id}}) and into the listen host's fighter entries. The
simulation never reads them. Views dress from them: NetMatchScene dresses every human fighter
(`FighterCosmetics.dress` with the stand-in profile `NetProtocol.cosmetics_profile`), the listen
host's MatchScene dresses its guests from their fighter entries, and a lobby row's framed name card
is `ProfileFrame.wrap(content, ProfileFrame.style(Net.cosmetics_profile(row)))` (a row without a
frame shows none - never this machine's). Ownership cannot be proven without accounts, so a player
could show any known item - harmless, it is looks only. Tested:
`test_net_loopback::test_cosmetics_travel_with_players_inprocess` (validation, lobby rows,
MATCH_START, nothing in the simulation, host's own, name-card frame) and
`test_net_multiprocess::test_dedicated_match_two_clients` (Bob's lobby and rendered match show
Alice's gold tooth and Sizzle glow; a made-up id is dropped).

Diagnostics overlay: `Settings diag.show_net` shows RTT, loss, snapshot rate, interpolation delay
and jitter, buffer depth and KB/s in the match; the same values come from `Net.stats()`.

## 8. Lobby and sessions

Lobby state (dictionary, `Net.lobby()` / `lobby_changed`): `phase` (`idle`, `lobby`, `match`,
`results`), `countdown`, `name`, `motd`, `dedicated`, `max_players`, `max_spectators`, `password`,
`host_id`, `players` [{id, name, slot, team, creature, ready, spectator, host, connected, fighter,
ping, vote}], `settings` {rules, rules_name, arena, arena_name, mode, bots, bot_difficulty,
rules_override, bot_policy}, `vote` {open, candidates [{index, key, name, rules_name, arena_name,
mode, weight, min_players, max_players}], tally}, `playlist` {id, name, valid, invalid, errors},
`entry`, `match_id`, `options` {creatures, rules, arenas, bot_difficulties, bot_policies [{id,
name, creature, hash}]} (listen hosts; dedicated servers list only creatures), `last_result`,
`party` (an open co-op party run, see "Party runs" in §14).

* Players get stable session ids (1 = server/listen host, joiners from 2) and lobby slots; joiners
  beyond `max_players` become spectators when spectator slots are free, otherwise `server_full`.
* Characters, teams (`-1` = automatic), ready and spectator are per player; the server validates
  creature ids against the playable roster (`Content.playable_creatures()`): hidden `npc_only`
  creatures such as the dev biped are never a player's pick - a join naming one gets the first
  playable fighter, an explicit pick of one is refused and scored as a protocol violation - while
  bots driven by an AI Lab policy may still fight as the policy's own (even hidden) creature. There
  is deliberately no switch to allow hidden creatures: the network tests name roster fighters.
* Match composition: humans who sat out longest first, capped at the entry's `max_players`; bots
  fill to `min_players` where allowed (listen host: plus the host's bot count). Bots are scripted
  (`BotBrain`) or **AI Lab policies** (`bot_policy`: host setting, playlist entry or
  `match.bot_policy`; used in turn across bot slots, each bot fights as its policy's creature, a
  missing or incompatible policy falls back to the scripted AI). Policies run only on the server;
  clients see a fighter of kind `policy` and need nothing (policies are not gameplay content and
  not part of the join content hash; the creature they drive is). Each policy is identified by its
  own content hash, the sha256 checksum of its canonical file form that `PolicyIO` verifies on load:
  the lobby options carry it, MATCH_START lists `policies` [{fighter, id, name, hash}] (hash empty
  when the policy was unavailable and a scripted bot fought), and the server logs it per match.
  Teams follow the
  local setup: duel/ffa own team each, teams/tag round-robin honouring requests, co-op humans on
  team 0 (bots join them, or oppose them when the preset has 2+ teams). Presets' `players: [min,
  max]` bound everything.
* Phases: `idle` -> (join) -> `lobby` (vote + countdown; all ready -> 3 s) -> `match` -> `results`
  (`results_time`) -> `lobby` / `idle`, fully automatic on dedicated servers. A listen host starts
  matches with `Net.host_start()`. A listen host can also run **playlist voting**
  (`host_set("playlist", id)`, "" = off): the lobby then offers the playlist's candidates, players
  vote, and `host_start()` plays the winning entry (it opens a vote first when none is open, and
  says why when no entry fits the number of players).
* Leave: `Net.leave()` (graceful, no reservation). Kick: `Net.host_kick(id, reason)` / admin `kick`.
* Chat: optional, rate-limited, cleaned, logged.

## 9. Robustness

| Situation | Behaviour (tested) |
|---|---|
| Link dies | No packet for `timeout` s -> both sides disconnect with `timeout` (5 s setting measured at 5.0 s) |
| Client crashes / drops mid-match | Slot reserved for `rejoin_grace` s; a bot (server bot difficulty) plays the fighter; others get a notice |
| Rejoin | HELLO with the token -> same player id, slot and fighter; control and press counters re-based; MATCH_START (and MATCH_END if in results) resent |
| Same player connects twice | The new session replaces the old one (`replaced`) |
| Malformed / oversized / flooding input | Dropped, scored, kicked (`protocol_violation`/`flood`), temporarily banned; the server keeps serving others |
| Forged damage / server messages / app "damage" requests | No code path accepts them; victim health unchanged (multi-process test) |
| Incompatible build / content | Rejected with both versions, or refused on the client with the `Mods.compare` lines (the server repeats the verdict) |
| Server shutdown | CLOSING with message and restart hint, delivered before the disconnect (server waits for acknowledgements, max 3 s) |
| Host leaves a listen session | Clients get `host_left`; the host's game continues offline. Quit to menu from the pause menu leaves the session (`MatchFlow.quit_to_menu`) |
| The listen host's match scene is removed by another path | The match ends for everyone with an aborted result; the session returns to the lobby |
| A player never answers a mode pick | Taken for them after 20 s - remote players and the listen host's own player alike (a dropped player's bot takes it at once) |
| Everyone leaves (dedicated, `idle`) | Running match aborted, server idles |

## 10. Connectivity

* **Direct**: address (IPv4 or hostname, resolved before connecting) + UDP port (`network.port`,
  default 7777).
* **LAN discovery**: servers broadcast a beacon (protocol, name, port, players, password flag,
  dedicated, phase, rules, arena, build, content hash prefix) once per second to
  255.255.255.255, the x.y.z.255 broadcast address of every local IPv4 interface (Windows sends a
  limited broadcast out of one interface only) and 127.0.0.1, on ports `discovery_port`..+3.
  Browsers bind the first free of those ports (several game instances per PC can browse), dedupe
  by the server's random instance id, mark incompatible builds/content, and expire silent entries
  after 4.5 s. Since protocol 4 a beacon also lists the server's gameplay packages (id, version,
  hash prefix; up to 12, with a "more" flag), so the browser can show *which* mods differ in the
  `Mods.compare` wording (`compat_lines`) before anyone tries to join. Beacons are untrusted:
  bounded (1200 B), validated, display only.
* **Remote user-hosted server**: forward the UDP port (§11) and share the public address.
* **Invites**: `Net.invite_text(address := "")` returns `Platform.invite_text(address, port,
  has_password)` for the session this machine hosts, ready to copy into a chat; without an address
  it uses the first LAN address of `Net.local_addresses()` (private IPv4 first, loopback and
  link-local left out). The public internet address belongs to the router and is not known
  locally: for internet play the host passes it (or a DNS name) explicitly.
* **Setting `network.lan_discovery`** (applied live): off = a listen host stops announcing at once
  and `Net.start_lan_discovery()` returns `ERR_UNAVAILABLE` (status text says the setting is off);
  switching it on resumes the host's beacons and starts the browsing the UI asked for. Dedicated
  servers use `server.lan_discovery`.

## 11. NAT and port forwarding (limits)

There is no relay, matchmaking or NAT traversal service. To accept internet players the host (or
dedicated server) must have the UDP game port reachable: forward it on the router to the hosting
machine and allow it in the OS firewall. Hosts behind carrier-grade NAT, strict corporate NAT or
some mobile networks cannot host for internet players; players can still join reachable servers.
IPv6 is not supported by the current code paths (IPv4 resolution). None of this has been tested
off-machine here: all evidence is loopback on one PC.

## 12. Network conditioner and diagnostics

`NetConditioner` is an in-process UDP relay (own thread, ~1 ms resolution) that adds one-way
latency, uniform jitter, random loss (each direction) and an optional blackhole, below ENet - so
ENet's real acknowledgements, retransmissions and timeouts are exercised. Flags (client or server):

```text
--net-latency <ms one-way>  --net-jitter <+-ms>  --net-loss <0..1>  [--net-reorder]
```

(A profile of 80 +- 20 ms one-way means roughly 160 ms RTT.) Client side it relays to the server;
server side it owns the public port. Its counters (packets and bytes per direction, drops) are
exact and are used for the bandwidth measurements in §15.

`Net.stats()`: `rtt_ms`, `rtt_var_ms`, `rtt_max_ms`, `loss`, `snapshot_rate`, `in_kbps`,
`out_kbps`, `interp_delay_ms`, `jitter_ms`, `buffer_ms`, `snapshots`, `late`, `starved_frames`,
`frames`, `events`, `roster_updates`, `inputs_sent`, `malformed`, wire/payload totals, per-channel
bytes, `conditioner` {...} and, on a server, `server` = `NetServer.status()` (phase, players, tick
cost, traffic, memory, objects/nodes/orphans).

## 13. Version compatibility

* `NetProtocol.VERSION` (now **5**: co-op campaign fights on the session - MATCH_START `campaign`
  with the campaign's own rules/mode, the arena's look as its variant - and packed party payloads;
  4 = party seats, cosmetics, arena packages and policy hashes in MATCH_START; 3 = content package
  lists with hashes in the challenge and hello, aim assist; 2 = 11-button input samples, roster
  generations, mode view/HUD state) must match exactly; it is bumped whenever any layout changes.
* The game version (`application/config/version`) must match exactly.
* Content: the content verdict above over `Mods.compare()` (gameplay packages, ids, versions,
  package hashes) and `Content.content_hash()` (all gameplay kinds of every loaded package).
  Presentation-only (`client_only`) packages are allowed on either side; any package with gameplay
  data (creatures, rules, modes, arenas, upgrades, ...) is required on both sides in the same
  version. Players enable the same mods (Mods screen, or `--mods id1,id2`); dedicated servers load
  exactly `server.mods` (SERVER.md).
* **Player-made rules presets** (`user:<name>`, saved on one machine and registered as runtime
  content) are not part of the content hash: MATCH_START carries the full rules dictionary, so
  clients never need the preset file (tested: a listen host plays its own `user:` preset with a
  guest that does not have it). Creatures must exist locally.
* **Player-made arenas** (`user:<slug>` layouts from the arena editor, `ArenaLibrary`) travel as
  an **arena package**: the host exports the layout with `ArenaPackage.export_package` (schema
  checked, hashed; cached per content hash; about 1.2 KB for a typical layout, capped at 512 KB)
  and MATCH_START carries the bytes plus `arena_hash` (`ArenaDef.content_hash()`). Before
  anything is built, the client (`NetClient._prepare_arena`) refuses oversized packages unopened,
  imports the package with `ArenaPackage.import_bytes` (zip pre-scan, path whitelist, size and
  ratio caps, sha256 per file, schema, `ArenaDef` checks, package hash) into a sandbox folder
  (`downloads/net_arenas`, emptied before each import; never the player's own arena list, so
  nothing is registered as the player's content), loads it through `ArenaLibrary.load_layout`
  and rebuilds the `ArenaDef`. If the import fails, the package lacks the announced arena, the
  layout has errors or its content hash differs from `arena_hash`, the client leaves with a
  content reason that says so. Arenas from packages use the local copy and the same hash comparison (a different
  copy blocks the match). Tested: `test_net_loopback::test_arena_checks_before_the_match` and the
  listen-host process test (`--user-arena`).
* **No mod downloads.** Servers never send mod package files: rules presets and player-made
  arenas travel as data (above), and mod packages must be installed by the player (the join error
  names each one).
  The former setting `network.allow_downloads` did nothing and was removed from Settings. A future
  download path would stream the server's `.critmod` (data-only, D-016) into the user `downloads`
  folder and hand it to `Mods.import_package()` after the player confirms, so every package check
  in docs/MODDING.md still applies.
* Playlists and AI Lab policies are server-only data and are not part of the hash (each policy
  in a match is named with its own checksum, §8).
* **Rules are validated twice** with the rules editor's own validator (`RulesValidator`, via
  `NetProtocol.rules_problem`): the host/server refuses invalid presets or overrides
  (`host_set` returns the reason, playlist entries are skipped with it, `start_match` refuses), and
  a client checks the rules dictionary in MATCH_START again and leaves with a clear reason if it
  fails. A co-op campaign fight is the exception: its rules are the campaign's fixed one-round set
  (`rounds`, `round_time` 10-900 s, `mode` campaign/boss, `friendly_fire`, `lives`; nothing else
  may ride along), checked on both sides by `NetProtocol.campaign_match_problem`.

## 14. API for UI and systems (`Net` autoload)

**Lifecycle**: `host(cfg) -> Error` (cfg keys: name, port, max_players, max_spectators, password,
lan_discovery, player_name, creature, cosmetics, rules, rules_override, arena, bots,
bot_difficulty, bot_policy, playlist, rejoin_grace, results_time, timeout; defaults from Settings
`network.*`; a rejected lobby setting is logged and the session still starts), `join(address, port, password, options)
-> Error` (options: name, spectator, creature, timeout_s, conditioner_args, assist - default from
Settings), `can_rejoin()`, `rejoin()`, `leave()`, `shutdown()` (App.quit), `start_dedicated(cfg)`,
`start_dedicated_from_cli(args)`, `start_from_cli(args)`.

**Settings that act live** (Net listens to `Settings.changed`): `network.interp` (client smoothing),
`network.timeout` (client and listen host), `network.lan_discovery` (browsing and the listen
host's beacons), `network.send_rate` (snapshots per second the listen host sends, 20-60),
`network.party_relay` (the listen host relays co-op party messages), `access.target_assist` (sent
to the server for the next match). `network.port`, `network.max_players`, `network.password` and
`network.player_name` are read when hosting/joining. The simulation rate is not a setting: combat
is tuned at 120 Hz (dedicated servers can change `server.tick_rate`, with a warning).

**Signals**: `status_changed(text)`, `session_state_changed(state)` (`offline`, `connecting`,
`lobby`, `match`, `results`), `connection_failed(reason)`, `disconnected(reason)`,
`joined(welcome)`, `lobby_changed(lobby)`, `chat_received(from_id, name, text)`, `notice(text)`,
`match_starting(info)`, `match_started(scene)`, `match_ended(result)`, `returned_to_lobby()`,
`peer_joined(info)`, `peer_left(info, reason)`, `app_message(from_id, type, payload)`,
`app_request(from_id, type, payload)`, `lan_sessions_changed(sessions)`, `member_joined(id)`,
`member_left(id, reason)` (party membership, below).

**Queries**: `role` (`offline`/`host`/`client`/`dedicated`), `is_online()`, `is_authority()`
(offline, host, dedicated), `is_server()`, `is_client()`, `is_host()`, `is_dedicated()`,
`local_peer_id()` (1 for server/host), `local_fighter()`, `peers()`, `player(id)`, `lobby()`,
`stats()`, `session_state()`, `last_failure`, `invite_text(address := "")` (host: copyable invite
line via `Platform.invite_text`), `local_addresses()` (this PC's IPv4 addresses, LAN first),
`local_member_id()`, `member_ids()` (party members, below).

**Lobby actions** (host or client): `set_ready(bool)`, `set_creature(id)`, `set_team(team)`,
`set_spectator(bool)`, `send_chat(text)`, `vote(index)`, `set_input_enabled(bool)` (neutral input
while a menu overlay is open; online matches never pause). **Host only**: `host_set(key, value)`
(rules - any preset the host has, including the player's own `user:` presets; rules_override;
arena; bots; bot_difficulty; bot_policy - AI Lab policy id or list; playlist - content playlist
id or "" for off) -> error text (validated), `host_start()` -> error text, `host_kick(id, reason)`.

**LAN**: `start_lan_discovery(port := 7779)` (`ERR_UNAVAILABLE` while the setting is off; starts by
itself when it is switched on; logs the port it listens on, or that all four are busy),
`stop_lan_discovery()`, `is_lan_discovery_active()`, `lan_sessions()` -> [{name, address, port,
players, max_players, spectators, max_spectators, password, dedicated, in_match, rules, arena,
phase, game_version, compatible, incompatible_reason, compat_lines}].

**Recent servers**: `recent_servers()` -> [{address, port, name, dedicated, last}] (newest first,
at most 8, `profiles/recent_servers.json` through `Saves`), `remember_server(address, port, name,
dedicated)` (done automatically when a join is admitted), `forget_server(address, port)`;
`Net.parse_address(text, default_port)` -> {address, port, error} reads "host", "host:port" and
"[v6]:port" with a player-facing error text.

**Scene handling**: on match start Net installs the scene itself (clients: `App.clear_screens()` +
`App.set_scene(NetMatchScene)`; host: `App.start_match`), and removes it when the server returns to
the lobby. UI screens show lobby/results in response to the signals.

**Screens** (`src/ui/screens/online_screen.gd`, `lobby_screen.gd`, `src/ui/online_flow.gd`; layout
and widgets in docs/UI.md). The **Online** screen hosts (`Net.host(OnlineScreen.host_config())`,
whose values come from the form and Settings `network.*`), joins by address
(`Net.parse_address`), from the recent list or from the LAN list (`compat_lines` explain an
incompatible session; a password session asks first), and shows the connection state with this
PC's addresses or, while hosting, the invite line. Players enter a lobby with the first playable
non-development fighter (`OnlineScreen.default_creature()`) and change it there. **OnlineFlow**
follows a session started from these screens with static state only (no node-bound callables, see
AGENTS.md): `match_ended` -> the results card (online variant: "Back to the lobby in N s", Back
to lobby, Leave session), `returned_to_lobby` -> the lobby again, `disconnected` -> the Online
screen plus a dialog built from the reason (`NetProtocol.describe`: title, message, details),
except after the player's own leave. Refused joins (`connection_failed`) use the same dialog. The
**Lobby** reads `Net.lobby()` (rebuilt on shape changes, refreshed in place twice a second for
pings and countdowns), sends the player's choices (`set_creature`, `set_team`, `set_spectator`,
`set_ready`, `vote`), drives the host settings through `host_set` (errors shown as toasts),
starts with `host_start` (errors in a dialog), copies `invite_text()`, explains the active rules
and the online restrictions (`LobbyScreen.rules_explained`), and drives party runs through
`NetPartyRuns` (deal a new one - campaign, co-op format, difficulty -, offer a suspended one,
take or rejoin a seat, start it, suspend / leave it); once a run is on, the campaign screens
take over (below).

**App message channel (co-op campaign, custom systems)** - plain-data messages with server
authority:

* `send_app(target, type, payload) -> bool`: on the authority, `target` is a player id or `ALL` (0);
  the listen host's own player receives `ALL`/`SERVER_ID` messages locally too. On a client the
  target must be `SERVER_ID` (1): it becomes an `app_request` on the authority.
* `request(type, payload)`: client -> authority (on the listen host delivered locally as
  `app_request(1, ...)`).
* `broadcast_app(type, payload)`: authority -> everyone.
* `app_request(from_id, type, payload)` fires only where the authority runs; `app_message(from_id,
  type, payload)` on receivers. Types match `[a-z0-9_.:/-]{1,64}`; payloads <= 64 KB, plain data.
* Clients never talk to each other directly: everything goes through the authority (route voting,
  reward picks, checkpoint sync and party resume are built this way: clients request, the server
  decides and broadcasts). `mode.*` request types are reserved for modes (`mode.pick`).
* **Party messages** (the co-op campaign's transport contract, `NetPartyTransport`):
  `send_app("" | "<member id>", type, payload)` with a String target reaches every other
  connected member or one member, from any member - clients send it to the authority
  (`net.relay`), which passes it on with the sender's id; receivers get
  `app_message(sender id, type, payload)`, never an echo. Member ids are the session player ids
  as strings (`local_member_id()`, `member_ids()` = the other connected players, spectators
  excluded); `member_joined(id)` / `member_left(id, "disconnected" | "left" | "session ended")`
  follow the lobby and the end of the session. Delivery is reliable and ordered per sender;
  `net.*` and `mode.*` types are never relayed; relayed messages are limited to 16 KB and charged
  per recipient; dedicated servers can switch relaying off (`server.party_relay`).
* **Sender identity is authenticated by the connection, never taken from a message.** The
  authority maps every ENet peer to the player it admitted (password, version and content checks)
  and relays with that player's id (`relay_app(p.id, ...)`); fields in or around the payload
  (`from`, `host`, ...) are never read for it. A client's network host accepts exactly one peer
  (its server), so `S_APP` sender ids come only from the authority. Only the listen host's own
  messages carry member id 1. Member ids are never reused while the server process runs (a
  rejoin keeps its id; a new join gets a new one); they start again after a server restart, so
  identity across sessions needs the campaign's own check. A direct request to the authority
  (`Net.request`, `app_request`) never reaches the party channel. Tested in
  `test_net_loopback::test_party_relay_inprocess` (a member's message dressed up as the host's
  still arrives with the member's id). Receivers still decide *who may send what*: members accept
  host-only messages (run state, tickets, run end) only from the current host's member id.
* **Party runs (resuming a co-op campaign run online).** A suspended party run keeps the member
  ids it was played with (its player ids), but a new session gives everyone new session ids. The
  listen host therefore offers the run in the lobby and every run player becomes a **seat**:
  `Net.party_open(run_id, seats [{id, name, fighter}], host_seat, info)` (host only; seat ids are
  the run's player ids, which runs started online have as 1-9 digit numbers; at most 4 seats;
  `info` <= 2 KB of plain data) publishes `lobby.party` {run_id, info, host_seat, seats [{id,
  name, fighter, session, connected}]}; `Net.party_claim(seat)` asks for a seat (the request
  names the run id, so it never lands in another run); `Net.party_leave()` gives it up;
  `Net.party_close()` withdraws the offer; `Net.party()` / `Net.party_seat()` read it; signals
  `party_changed(party)` and `party_claim_failed(reason)`. The authority refuses wrong-run, taken
  (also: held by a player whose rejoin reservation is still running), double and spectator
  claims; a seat frees when its holder leaves the session. While the offer is open, party member
  ids are seat ids everywhere: `local_member_id()`, `member_ids()` and `member_joined/left` report
  seats, relayed party messages carry the sender's seat (stamped by the authority from the
  connection) and are routed by seat, and players without a seat neither send nor receive party
  messages. NetPartyTransport and CoopSession therefore run unchanged with the run's own ids.
  `NetPartyRuns` (src/net/net_party_runs.gd) is the lobby glue the UI drives: the host calls
  `open_as_host(run_id)` (loads its party save `party_<run id>`, opens the seats, finds its own by
  profile id / name or takes the one the player picked) and `start_host()` once `missing_seats()`
  is empty (CoopSession.host_resume over NetPartyTransport), or `start_new_as_host(cfg)` to deal a
  NEW run for the players in the session (CoopSession.host_new; their session ids become the
  run's member ids, and the offer's `info.new` lets members take a seat without a save of their
  own); a member calls `claim(seat)` when the
  lobby offers a run it holds in its own party save ("rejoins by run id") and then `tick(dt)`
  every frame, which starts CoopSession.member_join once seated, repeats its hello until the run
  arrives and asks for its fighter back. The member re-verifies the first state the host sends
  against its own save (`check_resumed`: same run id and seed, follows from its own decision log
  via `RunController.verify`, continues the member's log - the host may be further along, never
  behind or different) and otherwise leaves the party run with the reason (`failed`); CoopSession
  itself accepts host-only messages only from the host's seat and verifies every later ticket and
  the final result. Dedicated servers do not host party runs. Tested:
  `test_net_loopback::test_party_seats_inprocess` (seat ids swapped against session ids, claim
  rules, outsiders kept out), `test_net_loopback::test_party_run_member_checks` (same run, ahead,
  behind, another run under the same id, a forged state) and
  `test_net_multiprocess::test_party_run_resumed_through_the_lobby`
  (independent processes: Ben resumes the run Ann hosted, Ann claims seat 1 by run id, both vote,
  the run moves on identically on both machines).
* **Party runs played online** (COOP-01..06; both campaigns, both co-op formats, 2-4 humans on a
  listen host). The whole run is played on the session:
  * **Start.** The host deals a run in the lobby (Off the Street / Fight Camp, simultaneous /
    tag-team, difficulty; each player's lobby fighter; for Fight Camp each player's own Cannery
    levels, which members send once per session as the request `party.meta` and the host clamps
    to the installed upgrades) or offers a suspended one; the run is HELD (`CoopSession.held`,
    nothing decided) while members take their seats, then Start releases it (absent seats: bots
    until they rejoin). `run_state` says `live`, and every machine's `CoopFlow` moves from the lobby
    to the campaign screens. `NetPartyRuns.start_ticking()` ticks the run from a node under Net
    whatever the screen.
  * **Between fights** every machine shows the real campaign screens (map with the route vote and
    its votes per stop, reward picks, events, shop, rest, run summary) bound to its view of the
    run: the host's authoritative RunController, a member's replica from `run_state`. Every
    decision is `CoopSession.act` - applied at once on the host with the same rules as a member's
    intent, sent from a member (the screen waits; a refusal comes back as a notice and the screen
    is rebuilt). Screens rebuild only when this player's own part changed (others' purchases and
    votes update a party line: who is shopping, picking, voting, the Captain, the vote timer). An
    event's outcome reaches every member (`run_state.event`: title, choice, who decided, lines)
    and stays on screen until CONTINUE. Host-only: suspending the run for everyone, forfeiting a
    fight, retrying / forfeiting a fight that could not be built; the Captain may "move on" for
    absent players after the absent time.
  * **Fights.** At a fight node the host builds the match from the run
    (`RunController.match_config`: every member's fighter with their build and carried HP, the
    encounter, the party format) and plays it on the session
    (`NetServer.start_campaign_match(config, owners, info, bot_maker)`): its own fighter is its
    local player, a connected member's fighter is driven by a NetRemoteInput from that member's
    input stream, an absent member's by the run's bot (tier capped at Contender), handed back if
    they reconnect mid-fight (`_bind_rejoin`; a member who drops mid-fight gets the run's bot,
    `bot_maker`). Members present it with NetMatchScene (campaign creatures that are not content
    creatures - minion loadouts, dev stand-ins - resolve through the campaign resolver,
    presentation only; a benched tag partner's camera follows the teammate who is in and a hint
    names Switch Target = tag in, Taunt = cheer, Ability 1 = assist). Tag-outs, assists, cheers,
    downed/revive and waves are the campaign mode's own rules on the host's simulation. The
    authoritative result goes into `CoopSession.complete_fight` once (the fight's claim key);
    members verify the run that follows from it against their decision logs (tickets). A fight the
    host's game never finished (its match scene removed) is played again from its start; an event
    spar is played by its decider alone (the others watch). Campaign fights have a 4 s results
    phase and no versus results card; when the session is back in its lobby, OnlineFlow returns
    every machine to the screen the run calls for.
  * **Ref timeouts** (pause menu during a party fight, everyone): `CoopSession`'s per-player
    30 s budget; the host freezes the match (`NetServer.set_frozen`: no simulation steps, physics
    space inactive, snapshots keep going) and every machine shows a REF TIMEOUT banner with the
    caller and the time left; the caller may end it early. Menus never pause.
  * **Disconnect / rejoin / host departure.** A member who drops keeps their seat for the rejoin
    grace: their fighter is the run's bot, their decisions are auto-chosen; reconnecting with the
    rejoin token gives the fighter back at once and the lobby takes the seat again
    automatically (decisions return at the next map, CoopSession). A member whose reservation ran
    out rejoins by run id from the lobby (their party save). When the listen host leaves (SESSION >
    Leave, the pause menu's Quit during a fight, or closing the game), the session ends for everyone
    (no host migration on Net): the host's leave does not withdraw the run first (`OnlineFlow.leave`
    / a session that went offline → `NetPartyRuns.close(false)`),
    so every member's dialog says the run is saved at its last stop and how to resume it (rejoin
    when offered again, or host it from their own party save). A host leaving mid-fight ends that
    match unscored: the run stays at the fight, which is played again after the resume.
  * **Save / resume.** Every node boundary saves the run on the host and a verified ticket on
    every member (`party_<run id>` plus `party_<run id>.seat`: which player this machine is,
    because profile ids repeat between machines); the host's "Suspend" ends it for everyone; any
    member can later offer the run from the lobby and the others take their seats by run id.
  * **End.** Each member credits only their own profile once (CoopSession, CampaignProgression
    keyed by run and player) and sees the run summary with every member's line; the party save is
    cleared.
  * **Payload size.** A whole run state is ~55 KB / ~5000 values for two players late in a run
    (more with four), near the app channel's 64 KB / 8192-value limits: party payloads above 4 KB
    travel deflated (`{_z, _n}`, `NetProtocol.pack_party_payload`), unpacked with a 2 MB cap and
    the same plain-data checks (`unpack_party_payload`).
  Tested (all LOOPBACK): `test_net_party_play.gd` (in-process: fights on the session in both
  formats, a member's tag-in and assist from the bench over the network, a member reviving a
  downed ally by holding Grab with her own controller, a ref timeout freezing the match, the
  result applied once, per-player picks, a member dropping and reconnecting mid-fight, a lost host
  scene replaying the fight, held runs, member-side views, packed payloads) and
  `test_net_party_campaign.gd` (independent processes through the real lobby and campaign screens:
  an Off the Street run in the simultaneous format - fights, a ref timeout from the member's pause
  menu freezing the host's match with the banner on both screens and her budget charged,
  per-player picks, an event the member decides, a shop where only the host buys, a member
  dropping mid-fight and rejoining, the host forfeiting, the run's end credited once per member on
  disk -, and a Fight Camp run in the tag format - each member's Cannery levels, tag-ins / assists /
  cheers from the bench, the host suspending, a new session resuming the run from the party saves
  through the lobby's seats (an event the member answers, rest for both, the next fight), then the
  host leaving the session mid-fight: the member is told why and that the run is saved, and the run
  stays at that fight).

## 15. Measured bandwidth and server cost

All numbers are **LOOPBACK on one machine** (i7-7700K, Windows 10): the processes talk through
127.0.0.1, so they show what the protocol sends and what the server costs, not real-network
latency. The machine was also running other test suites at the time, which inflates frame-time
maxima and interpolation delays; ranges give the spread over the runs on 2026-10-15.

**Per-client bandwidth and server cost** (`test_net_measure.gd`: dedicated server, bots fill, one
scripted human client through the conditioner relay at 1 ms, whose counters see every datagram;
20 s window in the fight; "wire" adds 28 B IPv4 + UDP header per packet):

| Scenario | Down per client | Up per client | Packets/s down / up | Snapshot | Sim logic per tick | Net per tick | Server CPU |
|---|---|---|---|---|---|---|---|
| Duel, 2 fighters | 6.5-8.5 KB/s (7.5-9.5 wire) | 4.1-5.0 KB/s (5.8-6.9 wire) | 33-38 / 61-71 | 209-285 B | 0.68-1.01 ms (up to 1.30 under load) | 0.19-0.42 ms | 20-27 % of one core |
| Free-for-all, 8 fighters | 16.8-28.8 KB/s (17.8-29.9 wire) | 4.4-5.3 KB/s (6.3-7.5 wire) | 35-46 / 69-81 | 663-893 B | 2.7-3.7 ms (4.1-6.8 with the CPU saturated by parallel jobs) | 0.39-0.77 ms | 52-68 % of one core |
| Duel, 2026-10-16, quiet, packaged server | 9.3-10.4 KB/s (10.3-11.5 wire) | 4.7-4.8 KB/s (6.6 wire) | 36-38 / 67-69 | 289-311 B | 0.49-0.55 ms | 0.14-0.17 ms | **10.2-11.5 % main-thread load** |
| Free-for-all, 2026-10-16, quiet, packaged server | 29.6-31.8 KB/s (30.7-33.1 wire) | 4.7-5.0 KB/s (6.7-7.1 wire) | 41-45 / 74-79 | 951-1033 B | 1.75-1.91 ms | 0.28-0.30 ms | **29.5-31.9 % main-thread load** |

* Downstream grows with fighters (a fighter's 13 segment rotations + vitals are most of a
  snapshot); upstream is flat (60 input packets/s, 4 samples each, plus pings and ENet acks).
  The upper ends of the 8-fighter row (719-893 B snapshots, 23-29 KB/s) are the runs after the
  newer roster kits were merged (bot slots draw from the whole playable roster, so the mix of
  fighters, statuses and effects in a snapshot changes from run to run).
* The longest physics frame (simulation + Jolt step, average of the per-second maxima) was
  2.5-8.2 ms (duel) and 15.6-28.1 ms (8 fighters); the upper ends are runs with other jobs
  saturating the CPU.
* **Server load target met (2026-10-16)**. DESIGN.md asks for < 35 % of one core with 8 fighters. The
  rows dated 2026-10-15 come from loaded machines (52-68 %). They are also inflated by two engine effects,
  both fixed:
  - Godot's frame limiter busy-waits part of every frame on Windows. The dedicated server now paces its own
    frames (DECISIONS D-031); an idle server went from 8.3 % to 0.1 %.
  - The physics worker pool woke all 8 threads for small Jolt jobs. The server export runs one worker
    thread (D-030).

  The dated quiet-machine rows measure the dedicated server package (`CritterweightServer.exe`, 1 client +
  7 bots). Their load is the main thread's busy share, from the server's own pacing: 1 − time slept ÷ wall
  time. Windows' sampled process-CPU accounting under-counts a thread that works in short bursts and then
  sleeps (2-4 % reported for a 10 % duel), so it is printed only for reference.
* `test_net_measure.gd` asserts bandwidth limits and that the 8-fighter server keeps real time
  (simulation + networking under the 8.33 ms tick); the quiet-machine simulation figure is printed
  as a reference, because parallel jobs on a shared machine inflate wall-clock tick times.

**Snapshot encoding** (`test_net_snapshot.gd`): positions rebuilt by forward kinematics are within
2 mm (1.96-1.99 mm) / 0.125 deg of the live simulation; snapshot bodies are 259 B with 2 fighters
and 889 B with 8 (13-segment test creature, every vital and status filled).

**Smoothing and degraded links** (`test_net_multiprocess.gd`, adaptive interpolation): plain
loopback duel 39-89 ms interpolation delay depending on machine load; packaged release builds
(`tools/verify/net_session_check.ps1`, last run on fresh exports of the final tree, protocol 4:
7/7 steps, RTT 14 ms, 30.0 snapshots/s, 58 ms) 30 snapshots/s and 49-90 ms over all runs; with the conditioner at
80 +- 20 ms one-way and 2 % loss: RTT max 180-250 ms, interpolation 80-116 ms, jitter p95 34-76 ms,
about 2 % of packets dropped (as configured), 1-2 % of rendered frames starved - the match still
completes with the correct result.

**Soak** (`test_net_soak.gd --soak-minutes 10`, LOOPBACK): a dedicated server rotates the
playlist (duel, free-for-all, 2v2, Spotlight Hog, Chum Rush; voting, bot fill, 30-35 s rounds)
for 10 minutes while a scripted fighter and a presenting spectator stay connected; the server's
status and the OS view of its process are sampled every 15 s (40 samples), then it is shut down
through the TCP admin.

| Run (2026-10-15) | Matches | Server static memory | Working set | Server CPU (10-min average) | Logs after exit | Exit |
|---|---|---|---|---|---|---|
| commit 597ade7 (final tree) | 13 | 70.2 MB in the first lobby, 104-106 MB from the first match on; slope -0.11 MB/min (2nd half) | 195 -> 196 MB, slope 0.00 MB/min | 29.6 % of one core | 8998 B, 1 file | 0 (graceful) |
| before the arenas merge | 14 | 61.2 MB in the first lobby, 95-97 MB from the first match on; slope -0.02 MB/min | 183 -> 186 MB, slope 0.00 MB/min | 28.9 % of one core | 9220 B, 1 file | 0 (graceful) |

In the final run the simulation took 1.24 ms per tick on average over the samples (highest
one-second average 2.90 ms), the server sent 29.5 KB/s on average to the two clients (peak
47.2 KB/s in 8-fighter modes) and received 4.3 KB/s; orphan nodes stayed at 0 and the object
count moved with the mode's fighters (1636-2337) without a trend; the presenting spectator's
working set was 130-231 MB. The step in static memory at the first match is what that match
loads and keeps cached (content definitions, scripts, physics resources); it stays flat for the
remaining nine minutes, so it is not growth.

## 16. Tests

One command runs the whole network suite (unit, in-process, multi-process, measurements, short
soak); add `--soak-minutes 10` for the requirement-level soak:

```powershell
$g = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe"
& $g --headless --path game --fixed-fps 120 -- --test net                    # whole suite, 2-minute soak
& $g --headless --path game --fixed-fps 120 -- --test net --soak-minutes 10  # whole suite, 10-minute soak
& $g --headless --path game --fixed-fps 120 -- --test test_net_soak --soak-minutes 10   # soak only
```

| File | Covers |
|---|---|
| `test_net_codec.gd` | Writer/reader, bounds, quantization error, event codec round trip, 3000-buffer fuzz + every truncation, input clamping, remote-input redundancy/jitter buffer, payload sanitizer, beacons (+ package list, older beacons, truncation), LAN compatibility lines, address parsing, recent-server list, reasons, password proof, config parser (incl. `server.mods`), package-list codec, content verdict over `Mods.compare`, assist clamping, rate limiter |
| `test_net_playlist.gd` | Weight distribution (10 000 draws), distinct candidates, repeat avoidance + relaxation, vote/tie/no-vote rules, min players + bot fill, invalid entries/missing content messages, persistence, shipped playlists |
| `test_net_snapshot.gd` | FK reconstruction vs live sim, snapshot sizes, roster generations, interpolation/teleport/generation switch, event scheduling, mirror driving the real FightHud |
| `test_net_loopback.gd` | In-process server + clients: handshake, app channel both ways, authoritative input, drop + bot takeover + rejoin, results + lobby return, shutdown message, rejections, kick/ban, violation kick, oversized/flood, host leaving, timeout, LAN discovery, host scene removed mid-match, mode picks for remote players (+ pick timeout), party relay (authenticated sender ids, limits, session end), party seats (claims, seat-stamped and seat-routed messages, outsiders kept out), a new party run dealt from the lobby (session ids as seats, "new" offer, second offer refused), arena checks before the match (local hash, mismatch, damaged and oversized packages, sandboxed import round trip), AI Lab policy bots (policy hash in the options and MATCH_START) + rules validation, server-side content check (forged package list refused, client_only allowed), aim assist into fighter mods (`LQ_ASSIST`, snapped levels, `match.player_assist`), live network settings + invite text |
| `test_net_multiprocess.gd` | Independent processes: dedicated match (hits, KO, results, presenting client), rejections (password, full, protocol, build, content refused on the client with Mods.compare wording), server mods (`server.mods` + client `--mods`, vanilla client refused, modded client plays the mod's preset, admin status lists packages), damage injection, disconnect + rejoin, stdin console shutdown, TCP admin auth/kick/ban/shutdown, 80 +- 20 ms / 2 % loss match, listen host (own `user:` rules preset sent in full and own `user:` arena sent as a package to a guest without either, guest aim assist applied, party messages) + remote client + app round trip, bonus modes (Chum Rush, Absolute Unit), LAN discovery, playlist rotation + votes + invalid entries + restart persistence, a suspended co-op party run resumed through the lobby (seat claimed by run id, CoopSession on both machines, route vote) |
| `test_online_ui.gd` | The Online and Lobby screens driven with controller events, focus checked after every step: tabs and back; host through the Online screen, a guest joins, copy invite, rules dialog, Y starts the match, online results card, automatic return to the lobby, leave; join a host running in another process through the Join tab's recent entry, ready with Y, play its match, come back; refusal dialogs (wrong password, another game version, full, nobody answering) and a kick with its reason; LAN tab (listed session, password prompt); a dedicated server's lobby joined by a typed address:port (playlist vote, ready); layout (footer on screen, text >= 18 px at 1280x800 and 1920x1080) |
| `test_net_party_play.gd` | Online party runs in-process (listen host + an emulated member speaking the party protocol through the relay): CoopSession views on every machine (held run, votes, refused acts, ref timeout, shared event outcome); campaign fights on the session in the simultaneous and tag formats (member drives her own fighter, presents the fight, tags in and calls an assist from the bench, revives a downed ally by holding Grab), a ref timeout freezing the match, the result applied once, per-player picks and the claim ledger, a member dropping and reconnecting mid-fight (run's bot, then her input again), a lost host scene replaying the fight; packed party payloads, campaign MATCH_START checks |
| `test_net_party_campaign.gd` | Online party runs between independent processes through the real lobby + campaign screens (scripted pilot pressing the buttons, scripted fight input, fixed map routes): Off the Street / simultaneous (fights, the member's ref timeout freezing the host's match, per-player picks, member-decided event, shop where only the host buys, member drop + token rejoin, host forfeit, run end credited once per member on disk) and Fight Camp / tag (members' Cannery levels, tag-ins / assists / cheers from the bench, suspend, a new session resuming the run through the lobby's seats, event, rest for both, next fight, host leaving mid-fight with the member's dialog and the run kept at that fight) |
| `test_net_parity.gd` | NetMatchScene handles every event MatchScene reacts to; reports event types without a codec id |
| `test_net_server_examples.gd` | Example configs and the playlist template stay valid |
| `test_net_measure.gd` | Bandwidth and server cost (duel, 8-fighter FFA) |
| `test_net_soak.gd` | Long run with bots and bonus modes; memory/CPU/log trends |

**Packaged builds** (exported executables, not the editor binary): `tools/verify/net_session_check.ps1`
starts the packaged dedicated server from a config, lets two packaged scripted clients play a duel
to the end, has a windowed packaged spectator save a rendered frame of the online match, checks the
TCP admin (`status`, a wrong token is refused) and the graceful shutdown (exit code 0), and scans
every log for errors. `tools/verify/run_verification.ps1` runs it as step 2b (`-SkipNet` skips it).
Also LOOPBACK on one PC.

## 17. Known gaps

* Internet play is untested off-machine (no second host was available); no relay/NAT traversal.
* No client-side prediction: input-to-visual latency is the network RTT plus the interpolation
  delay (40-90 ms measured over loopback). This is the designed trade-off for active ragdolls (D-014).
* IPv4 only. No encryption (ENet has no TLS here); the password is protected by a challenge proof,
  but traffic is readable on the path.
* The ENet per-peer receive buffer limit (32 MB) is not configurable from GDScript.
* No host migration: when a listen host leaves, the session ends with a clear reason.
* Rejoin tokens live in memory: a restarted client within the same game session can rejoin
  (`Net.rejoin()`), a restarted game cannot.
* No in-game mod download: players install missing mods themselves (the join error names
  them); rules presets travel in full and player-made arenas as checked layout packages (§13).
* Server CPU with 8 fighters is about 30 % of one core, inside the < 35 % target. It was 52-68 % before the server
  paced its own frames and used one worker thread (D-030, D-031); the cost is the simulation, not networking (§15).
* Event types added after the event codec's id table was fixed (arena hazards and props, bosses, ring-out return,
  campaign events; `test_net_parity` lists them) travel with their type name instead of a 1-byte
  id: they work, the event packets are just a little larger. Giving them ids is a protocol bump.
* Co-op party runs are played online end to end (§14 "Party runs played online"), tested between
  processes on one machine (LOOPBACK) with two humans; three- and four-player parties are covered
  only by the loopback-transport tests (test_campaign_coop) and in-process code paths. Party runs
  need a listen host (dedicated servers do not host them). When the listen host leaves, the
  session ends: the run is recovered from the party saves (no live host migration on Net, by
  design). A member's own decisions return at the next map after a reconnect (their fighter at
  once). Fights are not verified bit-exactly between machines - members verify the run that follows
  from the host's logged result, not the fight itself (the host is the authority). A member who is
  away when the run ends is credited only if they reconnect while the host is still on the run
  summary; otherwise their party save keeps the run at the last stop they saw.
* The Online and Lobby screens are tested headless with injected controller events and LOOPBACK
  sessions (one process, and a host in a second process); not tested with a second machine or a
  real controller on a real network.

## Reference: Project Reclaimer (inspected 2026-10-16)

The brief asks for Project Reclaimer's hosting and playlist documentation to be inspected for ideas. Its
local dedicated-hosting notes were read only: no live server was touched and nothing was copied. Their
ideas are already part of this design:
- weighted playlists with display names (the playlists section);
- content verified by hash before play (the content handshake);
- the admin console on loopback only (TCP admin on 127.0.0.1 with a token);
- a machine-readable status file (the dedicated server's `status.json`);
- direct connect as the fallback when discovery fails.
