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
| Client view | No local simulation, no prediction/rollback: active ragdolls cannot be reconciled, so clients render an **interpolated** past (adaptive buffer, ~40 ms on LAN) and fire event feedback when the render clock reaches the event's tick. |
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

## 5. Protocol (version 3)

Every packet: `[u8 message id][payload]`. Ids 1-63 client->server, 64-127 server->client; the wrong
direction, an unknown id, the wrong channel, an oversized payload or a failed bounds-checked decode
is a **protocol violation**. Layouts are documented in `src/net/net_protocol.gd`,
`net_snapshot.gd`, `net_event_codec.gd`; primitives in `net_writer.gd`/`net_reader.gd`.

| Id | Name | Dir | Max | Payload |
|---|---|---|---|---|
| 1 | HELLO | C->S | 16 KB | protocol, game version, gameplay content hash, packages (<= 64) [{id, version, hash, client_only}], name, password proof, rejoin token, flags, creature, aim assist (x100) |
| 2 | LEAVE | C->S | 16 B | - (graceful leave: no rejoin reservation) |
| 3 | LOBBY | C->S | 512 B | kind (ready, creature, team, spectate, assist) + value |
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
| 70 | MATCH_START | S->C (ch 1) | | match info (arena dictionary, rules, mode, roster, your fighter, tick/snapshot rates) |
| 71 | SNAPSHOT | S->C (ch 2) | | match id, tick, input ack, body (§6) |
| 72 | EVENTS | S->C (ch 1) | | base tick, events (§6) |
| 73 | MATCH_END | S->C (ch 1) | | result (winner, rounds, stats, players, entry, aborted) |
| 74 | APP | S->C | | from id, type, payload |
| 75 | CLOSING | S->C | | reason, message, restarting flag |
| 76 | KICKED | S->C | | reason code, reason text |
| 77 | PONG | S->C | | echo, server ms |
| 78 | ROSTER | S->C (ch 1) | | tick, changed slots (§6) |

**Handshake.** ENet connect -> server sends CHALLENGE (a fresh nonce, plus its gameplay content
hash and package list) -> the client checks the protocol version, then compares content on its own
side with `Mods.compare(server packages)` (MOD-05, below). If that fails it stops right there with
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
`client_only` (presentation-only) packages never count; a package with the same version but a
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
1.96 mm / 0.125 deg (`test_net_snapshot.gd`). Static props and hazard zones are not sent (the arena
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

`NetMatchScene` reuses the local views: `ArenaView` (built from the arena dictionary in
MATCH_START, so authored layouts need no download), `CreatureView` per roster slot, `Vfx`,
`FightCamera`, `FightHud`, `ModeView` and the audio bridge. A **presentation mirror**
(`NetHudMirror`) is a `MatchSim` with `Fighter` objects that are never stepped: it carries
replicated vitals, statuses, cooldowns, targets, mode timers/scores/`hud_state()`/`view_state()`,
effect entities, a rig stand-in (root position and velocity) and the replicated events, so
`FightHud`, `ModeView` and `AudioMatchBridge` (`Audio.attach_match`) run unchanged. Event feedback
mirrors `MatchScene._on_event`; `test_net_parity.gd` fails if `MatchScene` reacts to an event that
`NetMatchScene` does not. Large jumps (> 2.5 m between snapshots: respawn, round reset, blink) snap
instead of sliding. Mode choices offered to the local player (Chum Rush supplement picks) open the
same pick panel and are sent as a `mode.pick` request that the server validates. Damage numbers
follow `gameplay.damage_numbers`; achievements tied to the local player's own fighter (JUICE KO,
hat trick, wave 20) unlock from the server's events, like local play. **Spectators** get the
broadcast auto-director (`SpectatorDirector` on the mirror) and the same controls as local
AI-vs-AI spectating: Y / R director or free camera, LB/RB (Q/E) lock on a fighter, X / Delete hide
the HUD. Playback speed stays 1x online.

**Aim assist** (`access.target_assist`: low 0.5, normal 1.0, high 1.8) is part of the fighter's
modifiers in the authoritative simulation: a client sends its level in HELLO and again
(`LQ_ASSIST`) when the setting changes (used from the next match); the server clamps it to the
setting's maximum and puts it into the fighter entry `mods["assist"]`, exactly as `MatchScene`
does for local players (the listen host's own fighter uses the host's setting).

Diagnostics overlay: `Settings diag.show_net` shows RTT, loss, snapshot rate, interpolation delay
and jitter, buffer depth and KB/s in the match; the same values come from `Net.stats()`.

## 8. Lobby and sessions

Lobby state (dictionary, `Net.lobby()` / `lobby_changed`): `phase` (`idle`, `lobby`, `match`,
`results`), `countdown`, `name`, `motd`, `dedicated`, `max_players`, `max_spectators`, `password`,
`host_id`, `players` [{id, name, slot, team, creature, ready, spectator, host, connected, fighter,
ping, vote}], `settings` {rules, rules_name, arena, arena_name, mode, bots, bot_difficulty,
rules_override}, `vote` {open, candidates [{index, key, name, rules_name, arena_name, mode, weight,
min_players, max_players}], tally}, `playlist` {id, name, valid, invalid, errors}, `entry`,
`match_id`, `options` {creatures, rules, arenas, bot_difficulties}, `last_result`.

* Players get stable session ids (1 = server/listen host, joiners from 2) and lobby slots; joiners
  beyond `max_players` become spectators when spectator slots are free, otherwise `server_full`.
* Characters, teams (`-1` = automatic), ready and spectator are per player; the server validates
  creature ids against the playable roster.
* Match composition: humans who sat out longest first, capped at the entry's `max_players`; bots
  fill to `min_players` where allowed (listen host: plus the host's bot count). Teams follow the
  local setup: duel/ffa own team each, teams/tag round-robin honouring requests, co-op humans on
  team 0 (bots join them, or oppose them when the preset has 2+ teams). Presets' `players: [min,
  max]` bound everything.
* Phases: `idle` -> (join) -> `lobby` (vote + countdown; all ready -> 3 s) -> `match` -> `results`
  (`results_time`) -> `lobby` / `idle`, fully automatic on dedicated servers. A listen host starts
  matches with `Net.host_start()`.
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
| Incompatible build / content | Rejected with versions or the package diff |
| Server shutdown | CLOSING with message and restart hint, delivered before the disconnect (server waits for acknowledgements, max 3 s) |
| Host leaves a listen session | Clients get `host_left`; the host's game continues offline |
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
  after 4.5 s. Beacons are untrusted: bounded, validated, display only.
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

* `NetProtocol.VERSION` (now **3**: content package lists with hashes in the challenge and hello,
  aim assist; 2 = 11-button input samples, roster generations, mode view/HUD state) must match
  exactly; it is bumped whenever any layout changes.
* The game version (`application/config/version`) must match exactly.
* Content: the content verdict above over `Mods.compare()` (gameplay packages, ids, versions,
  package hashes) and `Content.content_hash()` (all gameplay kinds of every loaded package).
  Presentation-only (`client_only`) packages are allowed on either side; any package with gameplay
  data (creatures, rules, modes, arenas, upgrades, ...) is required on both sides in the same
  version. Players enable the same mods (Mods screen, or `--mods id1,id2`); dedicated servers load
  exactly `server.mods` (SERVER.md).
* **Player-made rules presets** (`user:<name>`, saved on one machine and registered as runtime
  content) and arenas are not part of the content hash: MATCH_START carries the full rules and
  arena dictionaries, so clients never need those files (tested: a listen host plays its own
  `user:` preset with a guest that does not have it). Creatures must exist locally.
* **No content downloads.** Servers never send package files: rules presets and arenas already
  travel in full, and mod packages must be installed by the player (the join error names each one).
  The former setting `network.allow_downloads` did nothing and was removed from Settings. A future
  download path would stream the server's `.critmod` (data-only, D-016) into the user `downloads`
  folder and hand it to `Mods.import_package()` after the player confirms, so every package check
  in docs/MODDING.md still applies.
* Playlists are server-only data and are not part of the hash.

## 14. API for UI and systems (`Net` autoload)

**Lifecycle**: `host(cfg) -> Error` (cfg keys: name, port, max_players, max_spectators, password,
lan_discovery, player_name, creature, rules, arena, bots, bot_difficulty, rejoin_grace,
results_time, timeout; defaults from Settings `network.*`), `join(address, port, password, options)
-> Error` (options: name, spectator, creature, timeout_s, conditioner_args, assist - default from
Settings), `can_rejoin()`, `rejoin()`, `leave()`, `shutdown()` (App.quit), `start_dedicated(cfg)`,
`start_dedicated_from_cli(args)`, `start_from_cli(args)`.

**Settings that act live** (Net listens to `Settings.changed`): `network.interp` (client smoothing),
`network.timeout` (client and listen host), `network.lan_discovery` (browsing and the listen
host's beacons), `access.target_assist` (sent to the server for the next match). `network.port`,
`network.max_players`, `network.password` and `network.player_name` are read when hosting/joining.

**Signals**: `status_changed(text)`, `session_state_changed(state)` (`offline`, `connecting`,
`lobby`, `match`, `results`), `connection_failed(reason)`, `disconnected(reason)`,
`joined(welcome)`, `lobby_changed(lobby)`, `chat_received(from_id, name, text)`, `notice(text)`,
`match_starting(info)`, `match_started(scene)`, `match_ended(result)`, `returned_to_lobby()`,
`peer_joined(info)`, `peer_left(info, reason)`, `app_message(from_id, type, payload)`,
`app_request(from_id, type, payload)`, `lan_sessions_changed(sessions)`.

**Queries**: `role` (`offline`/`host`/`client`/`dedicated`), `is_online()`, `is_authority()`
(offline, host, dedicated), `is_server()`, `is_client()`, `is_host()`, `is_dedicated()`,
`local_peer_id()` (1 for server/host), `local_fighter()`, `peers()`, `player(id)`, `lobby()`,
`stats()`, `session_state()`, `last_failure`, `invite_text(address := "")` (host: copyable invite
line via `Platform.invite_text`), `local_addresses()` (this PC's IPv4 addresses, LAN first).

**Lobby actions** (host or client): `set_ready(bool)`, `set_creature(id)`, `set_team(team)`,
`set_spectator(bool)`, `send_chat(text)`, `vote(index)`, `set_input_enabled(bool)` (neutral input
while a menu overlay is open; online matches never pause). **Host only**: `host_set(key, value)`
(rules, arena, bots, bot_difficulty, rules_override) -> error text, `host_start()` -> error text,
`host_kick(id, reason)`.

**LAN**: `start_lan_discovery(port := 7779)` (`ERR_UNAVAILABLE` while the setting is off; starts by
itself when it is switched on), `stop_lan_discovery()`, `is_lan_discovery_active()`, `lan_sessions()` ->
[{name, address, port, players, max_players, spectators, max_spectators, password, dedicated,
in_match, rules, arena, phase, game_version, compatible, incompatible_reason}].

**Scene handling**: on match start Net installs the scene itself (clients: `App.clear_screens()` +
`App.set_scene(NetMatchScene)`; host: `App.start_match`), and removes it when the server returns to
the lobby. UI screens show lobby/results in response to the signals.

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
* Clients cannot message each other directly; the authority validates and relays (route voting,
  reward picks, checkpoint sync and party resume are built this way: clients request, the server
  decides and broadcasts). `mode.*` request types are reserved for modes (`mode.pick`).

## 15. Measured bandwidth and server cost

MEASUREMENTS_PLACEHOLDER

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
| `test_net_codec.gd` | Writer/reader, bounds, quantization error, event codec round trip, 3000-buffer fuzz + every truncation, input clamping, remote-input redundancy/jitter buffer, payload sanitizer, beacons, reasons, password proof, config parser (incl. `server.mods`), package-list codec, content verdict over `Mods.compare`, assist clamping, rate limiter |
| `test_net_playlist.gd` | Weight distribution (10 000 draws), distinct candidates, repeat avoidance + relaxation, vote/tie/no-vote rules, min players + bot fill, invalid entries/missing content messages, persistence, shipped playlists |
| `test_net_snapshot.gd` | FK reconstruction vs live sim, snapshot sizes, roster generations, interpolation/teleport/generation switch, event scheduling, mirror driving the real FightHud |
| `test_net_loopback.gd` | In-process server + clients: handshake, app channel both ways, authoritative input, drop + bot takeover + rejoin, results + lobby return, shutdown message, rejections, kick/ban, violation kick, timeout, LAN discovery, server-side content check (forged package list refused, client_only allowed), aim assist into fighter mods (+ clamp, `LQ_ASSIST`), live network settings + invite text |
| `test_net_multiprocess.gd` | Independent processes: dedicated match (hits, KO, results, presenting client), rejections (password, full, protocol, build, content refused on the client with Mods.compare wording), server mods (`server.mods` + client `--mods`, vanilla client refused, modded client plays the mod's preset, admin status lists packages), damage injection, disconnect + rejoin, stdin console shutdown, TCP admin auth/kick/ban/shutdown, 80 +- 20 ms / 2 % loss match, listen host (own `user:` rules preset sent in full to a guest without it, guest aim assist applied) + remote client + app round trip, bonus modes (Chum Rush, Absolute Unit), LAN discovery, playlist rotation + votes + invalid entries + restart persistence |
| `test_net_parity.gd` | NetMatchScene handles every event MatchScene reacts to; reports event types without a codec id |
| `test_net_server_examples.gd` | Example configs and the playlist template stay valid |
| `test_net_measure.gd` | Bandwidth and server cost (duel, 8-fighter FFA) |
| `test_net_soak.gd` | Long run with bots and bonus modes; memory/CPU/log trends |

## 17. Known gaps

* Internet play is untested off-machine (no second host was available); no relay/NAT traversal.
* No client-side prediction: input-to-visual latency is the network RTT plus the interpolation
  delay (~40 ms on LAN). This is the designed trade-off for active ragdolls (D-014).
* IPv4 only. No encryption (ENet has no TLS here); the password is protected by a challenge proof,
  but traffic is readable on the path.
* The ENet per-peer receive buffer limit (32 MB) is not configurable from GDScript.
* No host migration: when a listen host leaves, the session ends with a clear reason.
* Rejoin tokens live in memory: a restarted client within the same game session can rejoin
  (`Net.rejoin()`), a restarted game cannot.
* No in-game content download: players install missing mods themselves (the join error names
  them); rules presets and arenas need none (sent in full).
