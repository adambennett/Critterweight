# CRITTERWEIGHT dedicated server

A headless, authoritative game server that runs matches around the clock on a weighted playlist
with player voting, bot fill, rejoin protection and local-only administration. It is the same engine
binary as the game (Godot 4.5.1) started with `--server`; networking design and protocol are in
[NETWORKING.md](NETWORKING.md).

> Verification status: everything below has been run on **one Windows 10 machine over loopback
> (127.0.0.1)** by the automated tests (`-- --test net`); the packaged Windows server and game
> executables were checked the same way (`tools/verify/net_session_check.ps1`: config start, a
> full duel between two packaged clients, a spectator frame, TCP admin, graceful shutdown). Linux commands come from the same code
> paths and the official Linux export template but have not been run on a Linux host here;
> off-machine internet play (NAT, port forwarding, real packet loss) has not been tested.

## 1. Install

**Packaged server** (export presets "Windows Server" / "Linux Server" in `game/export_presets.cfg`):

| Platform | Folder | Executable |
|---|---|---|
| Windows x64 | `dist/Critterweight-server-windows-x64/` | `CritterweightServer.exe` (+ `CritterweightServer.console.exe` wrapper for a console window) |
| Linux x86_64 | `dist/Critterweight-server-linux-x86_64/` | `CritterweightServer.x86_64` (`chmod +x` it) |

Copy one of the example configs from `game/server/` next to the executable and edit it:

| File | Purpose |
|---|---|
| `server.example.cfg` | Every key with comments and the defaults |
| `lan_party.cfg` | Password-protected LAN server, Fight Night playlist |
| `always_on.cfg` | Public always-on server: Bargain Bin rotation, bots, showcase matches when empty |
| `playlists/custom_rotation.example.json` | Template for a server-local playlist file |

The packages carry these files inside the executable only. To get the commented reference config
(and the playlist template next to it) as editable files in a packaged install, run:

```text
CritterweightServer.console.exe --headless -- --server --write-example-config server.cfg
```

It writes `server.cfg` and `custom_rotation.example.json` and never overwrites existing files.

**From source** (no export needed): use the editor binary with the project folder:

```powershell
$g = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe"
& $g --headless --path game -- --server --config game\server\lan_party.cfg
```

The server needs no account, no internet access and no administrator rights. All its files go to
the user-data folder (`%APPDATA%\Critterweight\` on Windows, `~/.local/share/Critterweight/` on
Linux) or the folder given with `--user-root <dir>`.

## 2. Run

```text
Windows:  CritterweightServer.console.exe --headless -- --server --config server.cfg
Linux:    ./CritterweightServer.x86_64 --headless -- --server --config server.cfg
```

* Everything after `--` belongs to the game. Without `--config` the server starts with the
  built-in defaults (and says so in the log).
* Command-line overrides (validated like the file): `--port N`, `--name "Text"`, `--password X`,
  `--max-players N`, `--playlist <id|path>`, `--log-level <level>`, `--admin-port N`,
  `--admin-token X`, `--bind <ip>`, `--discovery-port N`, `--lobby-time S`, `--results-time S`,
  `--empty idle|showcase`, `--mods id1,id2`, `--mods-dir <dir>`, `--user-root <dir>`.
* Debug network conditioner for testing (adds delay/jitter/loss in both directions on the server's
  public port): `--net-latency <ms one-way> --net-jitter <ms> --net-loss <0..1>`.
* Exit codes: `0` normal shutdown, `2` invalid configuration (errors are printed with file and
  line) or a configured mod that is not installed / cannot load, `3` the UDP port could not be
  bound (in use, or not permitted).

Running as a service: start the command above from your service manager (Task Scheduler / NSSM on
Windows, a systemd unit on Linux). Stop it gracefully through the TCP admin (`shutdown`, see §6)
before stopping the service; a killed process skips the shutdown notice (clients then report a
timeout after `timeout` seconds) but loses no state, because playlist state is saved after every
match with atomic writes.

Example systemd unit (Linux, not run here):

```ini
[Unit]
Description=Critterweight dedicated server
After=network-online.target
[Service]
WorkingDirectory=/opt/critterweight-server
ExecStart=/opt/critterweight-server/CritterweightServer.x86_64 --headless -- --server --config always_on.cfg
Restart=on-failure
User=critter
[Install]
WantedBy=multi-user.target
```

## 3. Ports and firewall

| Port | Protocol | Purpose | Exposure |
|---|---|---|---|
| `server.port` (7777) | UDP | Game traffic (ENet) | Open/forward for players outside the LAN |
| `server.discovery_port` .. +3 (7779-7782) | UDP broadcast | LAN beacons (outgoing only) | LAN only; not needed for internet play |
| `admin.port` (off by default) | TCP | Admin console | **127.0.0.1 only** - never exposed; use an SSH tunnel |

Internet play needs the UDP game port reachable from outside: forward it on the router to the
server machine and allow it in the OS firewall. There is no relay or NAT punch-through; players
behind carrier-grade NAT cannot host for internet players. See NETWORKING.md §11.

## 4. Configuration reference

INI-style: `[section]` headers, `key = value`, `#`/`;` comments, quotes optional. Values are plain
data - nothing in a config is executed. Unknown keys are warned about and ignored; out-of-range or
mistyped values stop the server with `file:line` errors.

### [server]

| Key | Type | Default | Range | Meaning |
|---|---|---|---|---|
| `name` | text | Critterweight Server | <= 40 chars | Shown in browsers, lobby, status |
| `port` | int | 7777 | 1024-65535 | UDP game port |
| `bind` | text | `*` | IP or `*` | Interface to bind |
| `max_players` | int | 8 | 1-8 | Human fighters |
| `max_spectators` | int | 4 | 0-8 | Extra spectator slots (joiners become spectators when players are full) |
| `password` | text | (empty) | <= 32 chars | Session password; empty = open |
| `motd` | text | (empty) | <= 200 chars | Message shown on join |
| `lan_discovery` | bool | true | | Send LAN beacons |
| `discovery_port` | int | 7779 | 1024-65535 | First LAN beacon port (beacons go to 4 consecutive ports) |
| `timeout` | int | 10 | 5-60 s | No packet for this long = disconnected (both directions; heartbeat 1 s) |
| `rejoin_grace` | int | 60 | 0-600 s | Disconnected players keep their slot (a bot plays their fighter) |
| `tick_rate` | int | 120 | 60-240 Hz | Simulation rate; combat is tuned for 120 (other values warn) |
| `snapshot_rate` | int | 30 | 10-60 Hz | Snapshots per second per client |
| `log_level` | enum | info | debug/info/warn/error | Log detail |
| `kick_ban_seconds` | int | 300 | 0-86400 | Kicked/violating players cannot rejoin for this long |
| `stats_interval` | int | 60 | 5-3600 s | Period of the `stats:` log line |
| `mods` | text | (empty) | mod ids, comma separated | Exactly the mods this server loads (core is always loaded); see below |
| `mods_dir` | text | (empty) | folder | Mods folder to use instead of `<user data>/mods` |
| `party_relay` | bool | true | | Relay co-op party messages between players (off = players can only talk to the server) |

**Mods.** A server loads exactly the mods named by `mods` (or `--mods id1,id2`) - never a player's
mod set - from `mods_dir` when given, else from the `mods` folder of its user-data directory
(install packages there as `.critmod` files or folders; the bundled examples such as `moon_rules`
are always available). Mods are data only (docs/MODDING.md: no scripts, archives checked before
extraction). Listing a mod counts as the operator's consent to its capabilities (for example
`replaces_core`), which a headless server cannot ask for. A listed mod that is missing or fails to
load stops the server with exit code 2 and the reason. At most 64 gameplay packages (core
included) can be listed in the handshake; more stops the server with a clear error. The log names the loaded packages and the gameplay hash (`content: core 1.0.0,
moon_rules 1.0.0; gameplay hash ...`), and `status` lists them. Players need the same gameplay
mods in the same versions: a client without them is refused before it joins, with lines like
"Missing mod: moon_rules 1.0.0 (install it, then enable it)" (NETWORKING.md §5); presentation-only
(`client_only`) mods never matter. Rules presets and arenas a server uses are sent to clients in
full, so playlists may use mod presets as long as the players have the mod.

### [match]

| Key | Type | Default | Range | Meaning |
|---|---|---|---|---|
| `playlist` | text | fight_night | id or path | Content playlist id or a playlist JSON file |
| `bots` | bool | true | | Fill missing fighters with bots when an entry allows it |
| `bot_difficulty` | enum | regular | rookie/regular/pro/champion | Bot skill |
| `lobby_time` | int | 30 | 3-600 s | Lobby/vote countdown (drops to 3 s when all players are ready) |
| `results_time` | int | 12 | 2-120 s | Results display before the next lobby |
| `empty_behavior` | enum | idle | idle/showcase | Without players: no simulation, or bot matches on the rotation |
| `vote_candidates` | int | 3 | 1-5 | Entries offered per vote (also capped by the playlist) |
| `bot_policy` | text | (empty) | policy ids, comma separated | AI Lab policies for bot slots (used in turn; each bot fights as its policy's creature; unavailable ones fall back to the scripted AI). Policies come from the server's user data folder (`policies/`, e.g. copied from a player's AI Lab export), the built-ins and loaded mods; the log names each policy with the first 16 characters of its checksum per match. Entries can set their own `bot_policy` |
| `player_assist` | bool | true | | true: each remote player's aim-assist level (low/normal/high, snapped to those) applies to their fighter; false: everyone gets normal |

### [admin]

| Key | Type | Default | Range | Meaning |
|---|---|---|---|---|
| `console` | bool | true | | Read admin commands from standard input |
| `port` | int | 0 | 0 or 1024-65535 | TCP admin on 127.0.0.1; 0 = off |
| `token` | text | (empty) | >= 16 chars when `port` is set | Shared secret for TCP admin |

## 5. Playlists

A playlist is JSON (schema `game/content/schemas/playlist.schema.json`). Shipped examples live in
`game/content/core/playlists/` (`fight_night`, `bargain_bin`, `cannery_coop`) and follow
`docs/design/MODES.md` §4; mods can add their own; a server can also load a file by path.

```json
{"id": "my_rotation", "name": "My Rotation",
 "voting": {"enabled": true, "candidates": 3}, "repeat_avoidance": 2,
 "entries": [
   {"id": "duel", "rules": "duel", "arena": "the_gullet", "weight": 4},
   {"id": "hog", "rules": "spotlight_hog", "arena": "the_gullet", "weight": 2, "min_players": 3, "bots": 2,
    "rules_override": {"round_time": 180}}]}
```

| Entry field | Meaning |
|---|---|
| `rules`, `arena` | Content ids (rules preset, arena) |
| `weight` | Relative chance of being drawn; 0 disables the entry |
| `id`, `name` | Stable key for history/repeat avoidance; vote card title |
| `min_players` | Fighters needed to start (default: the preset's `players` minimum) |
| `max_players` | Maximum human fighters; extra humans spectate that match and get priority next time |
| `bots` | Bots this entry may add; `0` = humans only; absent = the server's `bots` setting |
| `bot_policy` | AI Lab policy id or list of ids for this entry's bots (absent = `match.bot_policy`) |
| `rules_override` | Rules keys applied on top of the preset (`round_time`, `rounds`, `lives`, `damage_mult`, ...) |

**Selection rules** (implemented in `src/net/net_playlist.gd`, tested in
`src/test/net/test_net_playlist.gd`):

1. *Eligible* entries are valid entries with weight > 0 that can start with the current number of
   humans (bots fill up to `min_players` where allowed).
2. *Repeat avoidance*: the last `repeat_avoidance` played entries are excluded. If that leaves
   nothing, only the very last entry is excluded; if that still leaves nothing, all are allowed.
3. *Candidates*: up to `candidates` (capped by `vote_candidates`) are drawn by weight **without
   replacement**. With voting disabled one entry is drawn - weight is then the probability of
   being played next.
4. *Vote*: each player may vote (and change it) until the countdown ends; the countdown drops to
   3 s once everyone is ready. Most votes wins. **Tie** -> the tied candidate with the higher
   weight, then the one drawn first. **No votes** -> the highest-weight candidate (then the one
   drawn first).
5. *Not enough players* (no candidate can start): the lobby keeps waiting and says so; it redraws
   when the countdown ends.
6. *Empty server*: `idle` stops simulating until someone joins; `showcase` keeps playing the
   rotation with bots so joiners can watch at once.
7. *Automatic advance*: after `results_time` the next lobby/vote starts by itself.

**Validation**: at startup (and on `playlist reload`), every entry is checked against the loaded
content - unknown rules preset, rules that fail the rules editor's validation (with the entry's
overrides), unknown arena, mode not installed, impossible player counts, negative weight,
malformed fields. Invalid entries are skipped and logged with their number, e.g.

```text
[WARN] playlist: entry 4 (d_missing_arena): arena 'missing_arena' not found - skipped
```

Content that disappears later (mods reloaded) is re-checked when a match starts; the entry is then
skipped with a notice. A playlist without valid entries falls back to a built-in duel rotation
(logged as an error) so the server stays useful.

**Persistence**: the played history and match count are saved after every match to
`<user data>/server/playlist_state_<id>.json` (versioned, checksummed, atomic write with `.bak`).
After a restart the log says `restored playlist state: N matches played, recent: ...` and repeat
avoidance continues across the restart.

## 6. Administration

Commands (stdin console and TCP admin share one whitelist; nothing else is reachable):

| Command | Effect |
|---|---|
| `status` | Phase, uptime, players, current entry, tick cost, traffic, memory, loaded content packages |
| `players` | Players with id, slot, team, fighter, ping, loss, connection state, address |
| `kick <id\|name> [reason]` | Remove a player; they see the reason; temporary ban (`kick_ban_seconds`) |
| `next` | Lobby: start now - Match: end now (no winner) - Results: continue now |
| `playlist [show]` | Entries, validation errors, history |
| `playlist reload` / `playlist set <id\|path>` | Re-read / switch playlist (applies from the next vote) |
| `say <text>` | Broadcast a server notice |
| `shutdown [--restart] [message]` | Notify clients (with an optional "back soon" hint), save state, exit 0 |
| `help` | List commands |

**TCP admin**: enabled with `admin.port` + `admin.token` (>= 16 characters), bound to
**127.0.0.1 only** (there is no setting to bind it elsewhere). Line protocol: the first line must
be `AUTH <token>` (answer `OK` or `ERR auth`); then one command per line, each answer ends with a
line containing a single `.`. Limits: 2 connections, 512-byte lines, 120 s idle timeout, 5 failed
logins in a minute lock the endpoint for 60 s. For remote administration use an SSH tunnel
(`ssh -L 7780:127.0.0.1:7780 server`). Example:

```powershell
$t = New-Object Net.Sockets.TcpClient("127.0.0.1", 7780); $s = $t.GetStream()
$w = New-Object IO.StreamWriter($s); $r = New-Object IO.StreamReader($s); $w.AutoFlush = $true
$r.ReadLine(); $w.WriteLine("AUTH my-long-secret-token"); $r.ReadLine(); $w.WriteLine("status")
while (($l = $r.ReadLine()) -ne ".") { $l }
```

## 7. Logs and status

| File (under the user-data folder) | Content |
|---|---|
| `logs/server.log` (+ `.1`, `.2`) | All server log lines, written to disk at least once a second; rotates at 2 MB, 3 generations kept (bounded) |
| `server/status.json` | Rewritten every 5 s: state, phase, players, tick cost, traffic, memory, pid |
| `server/playlist_state_<id>.json` | Playlist history (restart persistence) |

A `stats:` line is logged every `stats_interval` seconds:

```text
stats: phase=match players=2 spect=0 match=1 fighters=2 sim_ms(1s avg/max)=0.60/1.57 phys_frame_max_ms=2.45 out=14.6KB/s in=8.8KB/s mem=72.7MB objects=1802 nodes=118 orphans=0
```

`sim_ms` is the simulation logic per tick; `phys_frame_max_ms` is Godot's longest physics frame in
the last second (logic + Jolt step).

## 8. Shutdown and restart behaviour

* `shutdown [--restart] [message]` (console or TCP): every client receives the reason and message
  ("The server shut down: Back in five minutes", plus "The server is restarting; try again
  shortly" with `--restart`), the server keeps servicing the network until they acknowledged (at
  most 3 s), saves the playlist state, writes `status.json` (`"state": "stopped"`) and exits with
  code 0.
* A killed or crashed server sends nothing: clients detect the silence after `timeout` seconds and
  show "Connection lost (timed out)". Nothing is corrupted (atomic writes).
* After a restart: the playlist history is restored; running matches, lobby state, votes and
  rejoin tokens are not (players reconnect normally and the server starts a new lobby).
* Listen servers (a player hosting from the game) close with "The host left the session".

## 9. Resource bounds and safety

* One match per process, at most 8 human fighters + 8 spectators (+ bots/minions up to the
  simulation's 24 fighter slots); ENet peers capped at players + spectators + 8.
* Bounded memory: event ring (512), snapshot buffers, chat (rate-limited, not stored), bans (256),
  logs (3 x 2 MB). The 10-minute soak test records memory and CPU trends (NETWORKING.md §15).
* Inbound limits per player: packet size per message type, token-bucket rates for input/control/
  chat/app messages and bytes per second, violation score with automatic kick, handshake
  timeout (5 s), at most 24 pending handshakes (8 per address).
* The server never loads code or content from clients; app messages are plain data (no objects),
  <= 64 KB, depth/size checked.
* Safe defaults: TCP admin off, LAN beacons on (LAN only), no password (set one for private
  servers), bots on.

## 10. Troubleshooting

| Symptom | Likely cause |
|---|---|
| Exit code 3, "cannot bind UDP port" | Another server/game uses the port; pick another `port` |
| Exit code 2 with `file:line` errors | Invalid config value; fix the named line |
| Clients: "Could not reach the server" | Wrong address/port, firewall, or the port is not forwarded (internet) |
| Clients: "Content mismatch" with a package list | Client and server have different gameplay mods; the lines name each missing / extra / different package - install or enable the same ones (`mods` here, Mods screen or `--mods` on the client) |
| Exit code 2, "mods: not installed in ..." | A `mods` entry is not in the mods folder (or `mods_dir`); install the package or fix the id |
| Clients: "Incompatible build" | Different game version or network protocol; update both sides |
| Playlist entries "skipped" in the log | Entry references content that is not installed; fix or remove it |
| Lobby says "Waiting for players" | No entry can start with this many humans (bots disallowed); lower `min_players` or allow bots |
