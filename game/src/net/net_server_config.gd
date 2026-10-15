class_name NetServerConfig
## Dedicated-server configuration: a small INI-style text file (docs/SERVER.md has the full
## reference and game/server/*.cfg are examples).
##
##   # comment (also ;)
##   [server]
##   name = My Critter Server        ; strings may be quoted ("...") or bare
##   port = 7777
##
## Every key is declared in SCHEMA with a type, default and range; unknown keys are reported
## (and ignored), invalid values are errors (the server refuses to start rather than silently
## running with something else). Values are plain data only: nothing in a config is executed.
## Command-line flags (--port, --name, --password, --max-players, --playlist, --log-level,
## --admin-port, --admin-token, --mods, --mods-dir, ...; see CLI) override the file.

const SCHEMA := {
	"server.name": {"t": "string", "def": "Critterweight Server", "max_len": 40},
	"server.port": {"t": "int", "def": 7777, "min": 1024, "max": 65535},
	"server.bind": {"t": "string", "def": "*", "max_len": 64},
	"server.max_players": {"t": "int", "def": 8, "min": 1, "max": 8},
	"server.max_spectators": {"t": "int", "def": 4, "min": 0, "max": 8},
	"server.password": {"t": "string", "def": "", "max_len": 32},
	"server.motd": {"t": "string", "def": "", "max_len": 200},
	"server.lan_discovery": {"t": "bool", "def": true},
	"server.discovery_port": {"t": "int", "def": 7779, "min": 1024, "max": 65535},
	"server.timeout": {"t": "int", "def": 10, "min": 5, "max": 60},
	"server.rejoin_grace": {"t": "int", "def": 60, "min": 0, "max": 600},
	"server.tick_rate": {"t": "int", "def": 120, "min": 60, "max": 240},
	"server.snapshot_rate": {"t": "int", "def": 30, "min": 10, "max": 60},
	"server.log_level": {"t": "enum", "def": "info", "opts": ["debug", "info", "warn", "error"]},
	"server.kick_ban_seconds": {"t": "int", "def": 300, "min": 0, "max": 86400},
	"server.stats_interval": {"t": "int", "def": 60, "min": 5, "max": 3600},
	"server.mods": {"t": "string", "def": "", "max_len": 1024},
	"server.mods_dir": {"t": "string", "def": "", "max_len": 260},
	"server.party_relay": {"t": "bool", "def": true},
	"match.playlist": {"t": "string", "def": "fight_night", "max_len": 260},
	"match.bots": {"t": "bool", "def": true},
	"match.bot_difficulty": {"t": "enum", "def": "regular", "opts": ["rookie", "regular", "pro", "champion"]},
	"match.lobby_time": {"t": "int", "def": 30, "min": 3, "max": 600},
	"match.results_time": {"t": "int", "def": 12, "min": 2, "max": 120},
	"match.empty_behavior": {"t": "enum", "def": "idle", "opts": ["idle", "showcase"]},
	"match.vote_candidates": {"t": "int", "def": 3, "min": 1, "max": 5},
	"match.bot_policy": {"t": "string", "def": "", "max_len": 1024},
	"match.player_assist": {"t": "bool", "def": true},
	"admin.console": {"t": "bool", "def": true},
	"admin.port": {"t": "int", "def": 0, "min": 0, "max": 65535},
	"admin.token": {"t": "string", "def": "", "max_len": 128},
}

## Flat runtime keys (config dictionaries passed around use these names).
const FLAT := {
	"server.name": "name", "server.port": "port", "server.bind": "bind", "server.max_players": "max_players",
	"server.max_spectators": "max_spectators", "server.password": "password", "server.motd": "motd",
	"server.lan_discovery": "lan_discovery", "server.discovery_port": "discovery_port",
	"server.timeout": "timeout", "server.rejoin_grace": "rejoin_grace", "server.tick_rate": "tick_rate",
	"server.snapshot_rate": "snapshot_rate", "server.log_level": "log_level",
	"server.kick_ban_seconds": "kick_ban_seconds", "server.stats_interval": "stats_interval",
	"server.mods": "mods", "server.mods_dir": "mods_dir", "server.party_relay": "party_relay",
	"match.playlist": "playlist", "match.bots": "bots", "match.bot_difficulty": "bot_difficulty",
	"match.lobby_time": "lobby_time", "match.results_time": "results_time",
	"match.empty_behavior": "empty_behavior", "match.vote_candidates": "vote_candidates",
	"match.bot_policy": "bot_policy", "match.player_assist": "player_assist",
	"admin.console": "admin_console", "admin.port": "admin_port", "admin.token": "admin_token",
}

const CLI := {"--port": "server.port", "--name": "server.name", "--password": "server.password",
	"--max-players": "server.max_players", "--playlist": "match.playlist", "--log-level": "server.log_level",
	"--admin-port": "admin.port", "--admin-token": "admin.token", "--bind": "server.bind",
	"--discovery-port": "server.discovery_port", "--lobby-time": "match.lobby_time",
	"--results-time": "match.results_time", "--empty": "match.empty_behavior", "--mods": "server.mods",
	"--mods-dir": "server.mods_dir"}


## Flat config with every default.
static func defaults() -> Dictionary:
	var out := {}
	for k in SCHEMA:
		out[FLAT[k]] = SCHEMA[k]["def"]
	return out


## Parses INI text. Returns {cfg: flat dict, errors: [..], warnings: [..]}.
static func parse_text(text: String, source := "config") -> Dictionary:
	var cfg := defaults()
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var section := ""
	var line_no := 0
	for raw_line in text.split("\n"):
		line_no += 1
		var line := raw_line.strip_edges()
		if line == "" or line.begins_with("#") or line.begins_with(";"):
			continue
		if line.begins_with("["):
			if not line.ends_with("]"):
				errors.append("%s:%d: malformed section header '%s'" % [source, line_no, line])
				continue
			section = line.substr(1, line.length() - 2).strip_edges().to_lower()
			if not section in ["server", "match", "admin"]:
				warnings.append("%s:%d: unknown section [%s] (its keys are ignored)" % [source, line_no, section])
			continue
		var eq := line.find("=")
		if eq <= 0:
			errors.append("%s:%d: expected 'key = value', got '%s'" % [source, line_no, line])
			continue
		var key := line.substr(0, eq).strip_edges().to_lower()
		var value := _strip_comment(line.substr(eq + 1).strip_edges())
		var full := key if key.contains(".") else "%s.%s" % [section, key]
		if not SCHEMA.has(full):
			warnings.append("%s:%d: unknown key '%s' (ignored)" % [source, line_no, full])
			continue
		var res := coerce(full, value)
		if res.has("error"):
			errors.append("%s:%d: %s" % [source, line_no, res["error"]])
		else:
			cfg[FLAT[full]] = res["value"]
	_cross_check(cfg, errors, warnings)
	return {"cfg": cfg, "errors": errors, "warnings": warnings}


static func parse_file(path: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if not FileAccess.file_exists(path):
		errors.append("config file not found: %s" % path)
		return {"cfg": defaults(), "errors": errors, "warnings": warnings}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("cannot read config file %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return {"cfg": defaults(), "errors": errors, "warnings": warnings}
	if f.get_length() > 256 * 1024:
		errors.append("config file %s is larger than 256 KB" % path)
		return {"cfg": defaults(), "errors": errors, "warnings": warnings}
	return parse_text(f.get_as_text(), path.get_file())


## Applies command-line overrides (validated like file values).
static func apply_cli(cfg: Dictionary, args: PackedStringArray, errors: Array[String]) -> void:
	for flag in CLI:
		var i := args.find(flag)
		if i < 0:
			continue
		if i + 1 >= args.size():
			errors.append("%s needs a value" % flag)
			continue
		var full: String = CLI[flag]
		var res := coerce(full, args[i + 1])
		if res.has("error"):
			errors.append("%s: %s" % [flag, res["error"]])
		else:
			cfg[FLAT[full]] = res["value"]


static func _strip_comment(v: String) -> String:
	if v.begins_with("\""):
		var close := v.find("\"", 1)
		if close > 0:
			return v.substr(0, close + 1)
		return v
	for marker in [" #", " ;", "\t#", "\t;"]:
		var at := v.find(marker)
		if at >= 0:
			v = v.substr(0, at)
	return v.strip_edges()


## Validates one value for a schema key. Returns {value} or {error}.
static func coerce(full: String, raw: String) -> Dictionary:
	var s: Dictionary = SCHEMA[full]
	var v := raw.strip_edges()
	if v.length() >= 2 and v.begins_with("\"") and v.ends_with("\""):
		v = v.substr(1, v.length() - 2)
	match str(s["t"]):
		"int":
			if not v.is_valid_int():
				return {"error": "%s must be a whole number (got '%s')" % [full, raw]}
			var iv := v.to_int()
			if iv < int(s["min"]) or iv > int(s["max"]):
				if full == "admin.port" and iv == 0:
					return {"value": 0}
				return {"error": "%s must be between %d and %d (got %d)" % [full, int(s["min"]), int(s["max"]), iv]}
			return {"value": iv}
		"bool":
			var lv := v.to_lower()
			if lv in ["true", "yes", "on", "1"]:
				return {"value": true}
			if lv in ["false", "no", "off", "0"]:
				return {"value": false}
			return {"error": "%s must be true or false (got '%s')" % [full, raw]}
		"enum":
			var opts: Array = s["opts"]
			if not opts.has(v.to_lower()):
				return {"error": "%s must be one of %s (got '%s')" % [full, ", ".join(PackedStringArray(opts)), raw]}
			return {"value": v.to_lower()}
		"string":
			if v.length() > int(s.get("max_len", 256)):
				return {"error": "%s is longer than %d characters" % [full, int(s.get("max_len", 256))]}
			for ch in v:
				if ch.unicode_at(0) < 32:
					return {"error": "%s contains control characters" % full}
			return {"value": v}
	return {"error": "%s: unsupported type" % full}


static func _cross_check(cfg: Dictionary, errors: Array[String], warnings: Array[String]) -> void:
	var port := int(cfg["admin_port"])
	if port != 0 and port < 1024:
		errors.append("admin.port must be 0 (off) or between 1024 and 65535")
	if port != 0 and str(cfg["admin_token"]).length() < 16:
		errors.append("admin.port is set but admin.token is shorter than 16 characters; TCP admin needs a strong token (or set admin.port = 0)")
	if port != 0 and port == int(cfg["port"]):
		errors.append("admin.port must differ from server.port")
	if int(cfg["tick_rate"]) != 120:
		warnings.append("server.tick_rate = %d: combat is tuned and tested at 120 Hz; other rates change physics behaviour" % int(cfg["tick_rate"]))
	if int(cfg["snapshot_rate"]) > int(cfg["tick_rate"]):
		errors.append("server.snapshot_rate cannot exceed server.tick_rate")
	for id in mod_ids(cfg):
		if RegEx.create_from_string("^[a-z0-9_]{3,32}$").search(id) == null:
			errors.append("server.mods: '%s' is not a mod id (3-32 lowercase letters, digits or _)" % id)


## AI Lab policy ids named by match.bot_policy ("id1, id2"), in order, without duplicates.
static func policy_ids(cfg: Dictionary) -> Array:
	var out: Array = []
	for part in str(cfg.get("bot_policy", "")).split(",", false):
		var id := part.strip_edges()
		if id != "" and not out.has(id):
			out.append(id)
	return out


## Mod ids named by server.mods ("id1, id2"), in order, without duplicates.
static func mod_ids(cfg: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for part in str(cfg.get("mods", "")).split(",", false):
		var id := part.strip_edges()
		if id != "" and not out.has(id):
			out.append(id)
	return out


## Re-validates a complete flat config (e.g. a listen-server config built from Settings).
static func check(cfg: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	_cross_check(cfg, errors, warnings)
	return errors
