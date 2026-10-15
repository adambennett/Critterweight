class_name NetPlayer
extends RefCounted
## Server-side record of one session participant (human player, spectator or the listen host).
## The player id is stable for the whole session (also across disconnect + rejoin); transport
## peer ids are not. Id 1 is the server itself (and the listen host's own player).

var id := 0
var peer := 0                    ## transport peer id; 0 = not connected; -1 = local (listen host)
var name := "Rookie"
var slot := -1                   ## lobby slot (0..max_players-1), -1 for spectators
var team := -1                   ## requested team (-1 = automatic)
var creature := ""
var assist := 1.0                ## aim-assist multiplier from the player's settings (fighter mods)
var cosmetics := {}              ## equipped cosmetics {slot: id} (NetProtocol.clean_cosmetics; presentation only)
var ready := false
var spectator := false
var is_host := false
var connected := true
var left_voluntarily := false
var token := PackedByteArray()   ## rejoin secret (only ever sent to this player)
var address := ""
var joined_ms := 0
var disconnected_ms := 0
var fighter := -1                ## fighter index in the running match, -1 = not fighting
var match_seen := 0              ## match id whose MATCH_START this player received
var input: NetRemoteInput = null
var vote := -1
var sat_out := 0                 ## matches sat out because the format had no room (fair rotation)
var rtt_ms := 0.0
var loss := 0.0
var violations := 0.0
var violation_ms := 0
var violation_log := 0
var last_input_seq := -1
var last_ack_tick := 0
var last_rx_ms := 0              ## last packet from this player (application-level timeout)
var bytes_in := 0
var rl_input := NetRateLimiter.new(150.0, 60.0)
var rl_control := NetRateLimiter.new(30.0, 60.0)
var rl_chat := NetRateLimiter.new(1.0, 5.0)
var rl_app := NetRateLimiter.new(40.0, 80.0)
var rl_bytes := NetRateLimiter.new(128.0 * 1024.0, 640.0 * 1024.0)


func is_human_player() -> bool:
	return not spectator


## Lobby view sent to every client (never includes the token or the address).
func to_public() -> Dictionary:
	return {"id": id, "name": name, "slot": slot, "team": team, "creature": creature, "ready": ready,
		"spectator": spectator, "host": is_host, "connected": connected, "fighter": fighter,
		"ping": roundi(rtt_ms), "vote": vote, "cosmetics": cosmetics.duplicate()}
