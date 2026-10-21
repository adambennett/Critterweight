class_name RulesValidator
## The single description of every editable match rule (MCH-05): type, range, default, which
## modes use it, and a plain-language explanation. The rules editor builds its rows from FIELDS,
## presets are normalized and validated here before they are saved, hosted or put in playlists,
## and every problem comes back as {field, severity ("error"|"warning"), text}.

const GROUPS := ["General", "Rounds & winning", "Fighters", "Respawn & revive", "Arena", "Bots", "Mode options"]
const FORMATS := ["duel", "ffa", "teams", "tag", "coop", "practice"]
const WIN := ["ko", "score", "survive", "none"]
const EDITABLE_MODES := ["standard", "spotlight_hog", "chumball", "absolute_unit", "chum_rush", "tag_team", "practice"]

## key: {group, label, help, type (int|float|bool|enum|text), def, min, max, step, options, modes}
const FIELDS := {
	"name": {"group": "General", "label": "Name", "type": "text", "def": "My rules", "max": 40,
		"help": "Shown in menus, lobbies and playlists."},
	"mode": {"group": "General", "label": "Mode", "type": "enum", "def": "standard", "options": EDITABLE_MODES,
		"help": "Standard fights, or one of the bonus modes. Changing it shows that mode's own options."},
	"format": {"group": "General", "label": "Format", "type": "enum", "def": "duel", "options": FORMATS,
		"help": "Duel: 1v1. FFA: everyone for themselves. Teams: fixed sides. Tag: one active fighter per team, partners tag in. Co-op: players together against the house (bots or waves). Practice: you and a dummy."},
	"teams": {"group": "General", "label": "Teams", "type": "int", "def": 2, "min": 0, "max": 4,
		"help": "Number of sides. 0 means free-for-all."},
	"players_min": {"group": "General", "label": "Minimum fighters", "type": "int", "def": 2, "min": 1, "max": 8,
		"help": "A match will not start with fewer fighters (bots count)."},
	"players_max": {"group": "General", "label": "Maximum fighters", "type": "int", "def": 2, "min": 1, "max": 8,
		"help": "The cage holds at most 8 fighters."},
	"description": {"group": "General", "label": "Description", "type": "text", "def": "", "max": 200,
		"help": "One or two sentences for the lobby and playlist screens."},
	"rounds": {"group": "Rounds & winning", "label": "Rounds", "type": "int", "def": 3, "min": 1, "max": 9,
		"help": "Best of this many rounds. Odd numbers avoid ties. With 10-point scoring every round is fought and judged."},
	"round_time": {"group": "Rounds & winning", "label": "Round time (s)", "type": "float", "def": 99.0, "min": 0.0, "max": 600.0, "step": 10.0,
		"help": "0 = no timer. When time runs out the round goes to score, then remaining health. With 10-point scoring the judges score the round at the bell (a timer is required)."},
	"win": {"group": "Rounds & winning", "label": "Win condition", "type": "enum", "def": "ko", "options": WIN,
		"help": "KO: last side standing. Score: first to the score target (KOs or mode points). Survive: co-op modes, last as long as you can. None: practice, nobody wins."},
	"score_target": {"group": "Rounds & winning", "label": "Score target", "type": "int", "def": 5, "min": 1, "max": 200,
		"help": "Points needed to win a round when the win condition is Score."},
	"ko_points": {"group": "Rounds & winning", "label": "Points per KO", "type": "int", "def": 1, "min": 0, "max": 10,
		"help": "Score awarded for knocking someone out (score modes)."},
	"sudden_death": {"group": "Rounds & winning", "label": "Sudden death", "type": "bool", "def": true,
		"help": "A tied round (with 10-point scoring: drawn cards) is settled by the next clean hit instead of a draw."},
	# standard 1v1 only (MCH-07/08); rules without these keys play Health scoring with no referee
	"scoring": {"group": "Rounds & winning", "label": "Scoring", "type": "enum", "def": "hp", "options": ["hp", "ten_point"],
		"modes": ["standard"],
		"help": "Health: at time the healthier fighter wins the round. 10-point must: fighters can't be knocked out by damage; three judges score every round and the cards decide unless the referee stops it."},
	"referee": {"group": "Rounds & winning", "label": "Referee", "type": "bool", "def": false, "modes": ["standard"],
		"help": "A referee counts knockdowns, keeps the attacker off a downed fighter (no hits while down) and waves it off after 5 knockdowns in one round: with 10-point scoring that ends the fight (T.K.O.), with Health scoring it ends the round."},
	"health_mult": {"group": "Fighters", "label": "Health", "type": "float", "def": 1.0, "min": 0.25, "max": 4.0, "step": 0.05,
		"help": "Multiplies every fighter's health."},
	"damage_mult": {"group": "Fighters", "label": "Damage", "type": "float", "def": 1.0, "min": 0.25, "max": 4.0, "step": 0.05,
		"help": "Multiplies all damage dealt."},
	"knockback_mult": {"group": "Fighters", "label": "Knockback", "type": "float", "def": 1.0, "min": 0.25, "max": 3.0, "step": 0.05,
		"help": "How far hits send fighters flying."},
	"regen_mult": {"group": "Fighters", "label": "Stamina regeneration", "type": "float", "def": 1.0, "min": 0.25, "max": 3.0, "step": 0.05,
		"help": "Faster stamina means more guarding, dodging and attacking."},
	"cooldown_rate": {"group": "Fighters", "label": "Ability recharge speed", "type": "float", "def": 1.0, "min": 0.25, "max": 4.0, "step": 0.05,
		"help": "2.0 recharges abilities twice as fast."},
	"hype_mult": {"group": "Fighters", "label": "Hype gain", "type": "float", "def": 1.0, "min": 0.0, "max": 5.0, "step": 0.1,
		"help": "How fast the JUICE meter fills. 0 = no JUICE from Hype."},
	"start_hype": {"group": "Fighters", "label": "Starting Hype", "type": "float", "def": 0.0, "min": 0.0, "max": 100.0, "step": 5.0,
		"help": "100 = everyone can pop their JUICE right away."},
	# v0.9.18 (docs/design/MOVESET_COMBAT.md): every built-in game type uses Movesets; Classic keeps
	# the v0.9.17 combat whole. A real rule: sent with the match, validated by server and clients.
	"combat": {"group": "Fighters", "label": "Combat style", "type": "enum", "def": "moves", "options": ["moves", "classic"],
		"help": "Movesets: each fighter fights with its four equipped named moves (plus guard, dodge, grapple and JUICE). Classic: the original light / heavy / grab and two-ability combat."},
	"abilities": {"group": "Fighters", "label": "Abilities", "type": "bool", "def": true,
		"help": "Off: fighters only have strikes, guard, dodge and grabs."},
	"juice": {"group": "Fighters", "label": "JUICE", "type": "bool", "def": true, "help": "Allow the JUICE ultimate."},
	"grabs": {"group": "Fighters", "label": "Grabs and throws", "type": "bool", "def": true, "help": "Off: Grab does nothing."},
	"friendly_fire": {"group": "Fighters", "label": "Friendly fire", "type": "bool", "def": false,
		"help": "Teammates can hurt each other with strikes."},
	"ally_reaction_damage_mult": {"group": "Fighters", "label": "Ally element reactions", "type": "float", "def": 0.25, "min": 0.0, "max": 1.0, "step": 0.05,
		"help": "Damage teammates take from your element reactions."},
	"lives": {"group": "Respawn & revive", "label": "Lives", "type": "int", "def": 1, "min": 0, "max": 9, "not_modes": ["tag_team", "chum_rush", "practice"],
		"help": "Knockouts a fighter can take before elimination (needs Respawn). 0 = unlimited. Score modes without a lives count respawn without limit."},
	"respawn": {"group": "Respawn & revive", "label": "Respawn", "type": "bool", "def": false, "not_modes": ["tag_team", "chum_rush", "practice"],
		"help": "Knocked-out fighters come back after a delay while they have lives left."},
	"respawn_delay": {"group": "Respawn & revive", "label": "Respawn delay (s)", "type": "float", "def": 3.0, "min": 1.0, "max": 15.0, "step": 0.5, "not_modes": ["tag_team", "chum_rush", "practice"],
		"help": "Seconds out of the fight before respawning."},
	"revive": {"group": "Respawn & revive", "label": "Revives", "type": "bool", "def": false,
		"help": "Team formats: a downed fighter can be revived by a teammate holding Grab nearby."},
	"downed_time": {"group": "Respawn & revive", "label": "Downed time (s)", "type": "float", "def": 15.0, "min": 5.0, "max": 60.0, "step": 1.0,
		"help": "How long a downed fighter can wait for a revive."},
	"revive_health": {"group": "Respawn & revive", "label": "Revive health", "type": "float", "def": 0.35, "min": 0.1, "max": 1.0, "step": 0.05,
		"help": "Fraction of health a revived fighter gets back."},
	"ringout_damage": {"group": "Respawn & revive", "label": "Ring-out damage", "type": "float", "def": 0.08, "min": 0.0, "max": 0.5, "step": 0.01,
		"help": "Fraction of max health lost when you fall off an open edge."},
	"ringout_eliminates": {"group": "Respawn & revive", "label": "Ring-out eliminates", "type": "bool", "def": false,
		"help": "Falling off an open edge knocks you out immediately."},
	"gravity_mult": {"group": "Arena", "label": "Gravity", "type": "float", "def": 1.0, "min": 0.3, "max": 2.0, "step": 0.05,
		"help": "Below 1: floaty jumps and long launches. Combines with the arena's own gravity."},
	"max_zones": {"group": "Arena", "label": "Element zone limit", "type": "int", "def": 24, "min": 4, "max": 48,
		"help": "Cap on simultaneous element zones (puddles, fires, gusts) for readability and performance."},
	"hazards": {"group": "Arena", "label": "Arena hazards", "type": "bool", "def": true,
		"help": "The arena's timed hazards (Drydock flood and crane, Crusher plates and magnet, Rooftop wind). Off: props and pickups stay, nothing fires on a timer."},
	"hazard_timer_mult": {"group": "Arena", "label": "Hazard timers", "type": "float", "def": 1.0, "min": 0.25, "max": 4.0, "step": 0.25,
		"help": "Multiplies the time between arena hazard events: 2.0 = half as often, 0.5 = twice as often."},
	"ringouts": {"group": "Arena", "label": "Ring-outs", "type": "bool", "def": true,
		"help": "Off: invisible guard walls line open edges (Rooftop), so nobody falls off the roof. Pits still drop you."},
	"bot_tier": {"group": "Bots", "label": "Bot skill", "type": "enum", "def": "journeyman",
		"options": ["punching_bag", "journeyman", "contender", "headliner", "hall_of_famer"],
		"help": "Skill of bots that fill empty slots (local, hosted and dedicated matches)."},
	"bots": {"group": "Bots", "label": "Fill with bots", "type": "int", "def": 0, "min": 0, "max": 7,
		"help": "Bots added to every match with these rules (never past the maximum fighters), at the bot skill above."},
	# ---- mode options ----
	"light_radius": {"group": "Mode options", "label": "Spotlight size (m)", "type": "float", "def": 2.0, "min": 1.0, "max": 4.0, "step": 0.1,
		"modes": ["spotlight_hog"], "help": "Radius of the scoring light."},
	"dwell": {"group": "Mode options", "label": "Spotlight stays (s)", "type": "float", "def": 25.0, "min": 8.0, "max": 90.0, "step": 1.0,
		"modes": ["spotlight_hog"], "help": "Seconds before the light swings somewhere else."},
	"contest": {"group": "Mode options", "label": "Contested light", "type": "enum", "def": "strict", "options": ["strict", "majority"],
		"modes": ["spotlight_hog"], "help": "Strict: nobody scores while two sides share the light. Majority: the side with more fighters inside scores (a tie scores nothing)."},
	"hot_light": {"group": "Mode options", "label": "Hot light", "type": "bool", "def": false,
		"modes": ["spotlight_hog"], "help": "Standing in the light slowly scorches you."},
	"ball_mass": {"group": "Mode options", "label": "Ball weight (kg)", "type": "float", "def": 25.0, "min": 8.0, "max": 80.0, "step": 1.0,
		"modes": ["chumball"], "help": "Heavier balls need real hits to move."},
	"goal_width": {"group": "Mode options", "label": "Goal width (m)", "type": "float", "def": 3.0, "min": 1.5, "max": 5.0, "step": 0.1,
		"modes": ["chumball"], "help": "Width of each goal mouth."},
	"own_goals": {"group": "Mode options", "label": "Own goals count", "type": "bool", "def": true, "modes": ["chumball"],
		"help": "Knocking the ball into your own goal scores for the other team."},
	"carry": {"group": "Mode options", "label": "Carrying", "type": "bool", "def": true, "modes": ["chumball"],
		"help": "Grab picks the ball up; attack buttons throw it."},
	"hot_ball": {"group": "Mode options", "label": "Hot ball", "type": "bool", "def": false, "modes": ["chumball"],
		"help": "A fast-moving ball hurts (4 damage) whoever it hits."},
	"chaos": {"group": "Mode options", "label": "Chaos", "type": "bool", "def": false, "modes": ["chumball"],
		"help": "Fighters are not sent back to their spawns after a goal."},
	"unit_scale": {"group": "Mode options", "label": "Unit size", "type": "float", "def": 1.6, "min": 1.2, "max": 2.0, "step": 0.05,
		"modes": ["absolute_unit"], "help": "How much bigger the Absolute Unit gets."},
	"unit_hp": {"group": "Mode options", "label": "Unit health", "type": "float", "def": 2.5, "min": 1.0, "max": 5.0, "step": 0.1,
		"modes": ["absolute_unit"], "help": "Health multiplier while crowned."},
	"unit_juice": {"group": "Mode options", "label": "Unit can JUICE", "type": "bool", "def": false, "modes": ["absolute_unit"],
		"help": "Let the Absolute Unit use its JUICE."},
	"hot_potato": {"group": "Mode options", "label": "Hot potato", "type": "bool", "def": false, "modes": ["absolute_unit"],
		"help": "The Unit loses a point for every 5 s it goes without hitting anyone."},
	"start_wave": {"group": "Mode options", "label": "Starting wave", "type": "int", "def": 1, "min": 1, "max": 60,
		"modes": ["chum_rush"], "help": "Skip ahead to tougher waves."},
	"wave_size_mult": {"group": "Mode options", "label": "Wave size", "type": "float", "def": 1.0, "min": 0.5, "max": 3.0, "step": 0.1,
		"modes": ["chum_rush"], "help": "Multiplies how many enemies each wave sends."},
	"enemy_health_mult": {"group": "Mode options", "label": "Enemy health", "type": "float", "def": 1.0, "min": 0.25, "max": 4.0, "step": 0.05,
		"modes": ["chum_rush"], "help": "Multiplies wave enemies' health."},
	"headliner_interval": {"group": "Mode options", "label": "Headliner every N waves", "type": "int", "def": 10, "min": 0, "max": 20,
		"modes": ["chum_rush"], "help": "0 = no headliner bosses."},
	"picks": {"group": "Mode options", "label": "Supplement picks", "type": "bool", "def": true, "modes": ["chum_rush"],
		"help": "Pick a supplement every fifth break."},
	"night_shift": {"group": "Mode options", "label": "Night shift", "type": "bool", "def": false, "modes": ["chum_rush"],
		"help": "Every enemy attack carries an element."},
	"last_call": {"group": "Mode options", "label": "Last call", "type": "bool", "def": false, "modes": ["chum_rush"],
		"help": "A 10-minute limit: score as many waves as you can."},
	"tag_cooldown": {"group": "Mode options", "label": "Tag cooldown (s)", "type": "float", "def": 4.0, "min": 1.0, "max": 15.0, "step": 0.5,
		"modes": ["tag_team"], "help": "Minimum time between tags."},
	"tagged_regen": {"group": "Mode options", "label": "Resting regeneration (HP/s)", "type": "float", "def": 4.0, "min": 0.0, "max": 15.0, "step": 0.5,
		"modes": ["tag_team"], "help": "Health the partner on the apron recovers per second."},
}

## Format each mode needs (or allows).
const MODE_FORMATS := {"standard": ["duel", "ffa", "teams", "coop"], "spotlight_hog": ["ffa", "teams"], "chumball": ["teams"],
	"absolute_unit": ["ffa"], "chum_rush": ["coop"], "tag_team": ["tag"], "practice": ["practice"]}

## The fighter modifiers a rules preset may set in "fighter_mods" (docs/MODDING.md): numbers with
## their allowed range [min, max] (multipliers on the fighter's own value; "_add" keys and
## start_hype are added), or true/false flags. Anything else is dropped by normalize(), reported
## by validate() and ignored by MatchSim, which clamps every value again when it applies them.
const FIGHTER_MODS := {
	"damage": [0.1, 4.0], "defense": [0.1, 4.0], "speed": [0.1, 3.0], "move_speed": [0.1, 3.0],
	"stamina_regen": [0.1, 4.0], "knockback_taken": [0.1, 4.0], "knockback_dealt": [0.1, 4.0],
	"cooldown": [0.1, 4.0], "hype_gain": [0.0, 5.0], "poise": [0.1, 4.0], "heal": [0.0, 4.0],
	"max_health": [0.25, 4.0], "stamina_cost": [0.1, 4.0], "dodge_cost": [0.1, 4.0],
	"dodge_distance": [0.25, 3.0], "throw_distance": [0.25, 3.0], "getup_speed": [0.25, 4.0],
	"held_time_mult": [0.25, 4.0], "buildup_taken": [0.0, 4.0], "reach_radius": [0.5, 2.0],
	"vmin_mult": [0.25, 4.0], "charge_distance": [0.25, 3.0], "charge_speed": [0.25, 3.0],
	"charge_steer": [0.0, 4.0], "hover_duration": [0.25, 4.0], "zone_size": [0.25, 3.0],
	"guard_absorb_mult": [0.0, 4.0], "status_duration_taken": [0.0, 4.0],
	"start_hype": [0.0, 100.0], "max_health_add": [0.0, 200.0], "stamina_add": [0.0, 100.0],
	"poise_add": [0.0, 100.0], "parry_window_add": [0.0, 0.3], "dodge_iframes_add": [0.0, 0.3],
	"wakeup_invuln_add": [0.0, 1.0], "grab_hold_add": [0.0, 2.0], "grab_escape_add": [0.0, 10.0],
	"splat_damage_add": [0.0, 20.0], "splat_poise_add": [0.0, 50.0], "zone_duration_add": [0.0, 10.0],
	"no_grabs": "flag", "no_juice": "flag", "no_abilities": "flag", "auto_charge": "flag", "all_moves_elemental": "flag",
}


static func field(key: String) -> Dictionary:
	return FIELDS.get(key, {})


## Fields shown for a mode (mode options only for their modes), in group order.
static func fields_for(mode: String) -> Array:
	var out := []
	for g in GROUPS:
		for k in FIELDS:
			var f: Dictionary = FIELDS[k]
			if f["group"] != g:
				continue
			if f.has("modes") and not mode in f["modes"]:
				continue
			if f.has("not_modes") and mode in f["not_modes"]:
				continue
			out.append(k)
	return out


## Value of `key` in a rules dictionary (players_min/max live in "players": [min, max]).
static func get_value(rules: Dictionary, key: String):
	var f := field(key)
	if key == "players_min" or key == "players_max":
		var pl: Array = rules.get("players", [f.get("def", 2), f.get("def", 2)])
		return int(pl[0] if key == "players_min" else pl[mini(1, pl.size() - 1)])
	return rules.get(key, f.get("def"))


static func set_value(rules: Dictionary, key: String, v) -> void:
	if key == "players_min" or key == "players_max":
		var pl: Array = rules.get("players", [2, 2]).duplicate()
		if pl.size() < 2:
			pl = [int(pl[0]) if not pl.is_empty() else 2, int(pl[0]) if not pl.is_empty() else 2]
		pl[0 if key == "players_min" else 1] = int(v)
		rules["players"] = pl
		return
	rules[key] = coerce(key, v)


static func coerce(key: String, v):
	var f := field(key)
	match str(f.get("type", "")):
		"int":
			return clampi(int(v), int(f.get("min", -1000000)), int(f.get("max", 1000000)))
		"float":
			return clampf(float(v), float(f.get("min", -1e9)), float(f.get("max", 1e9)))
		"bool":
			return bool(v)
		"enum":
			return str(v) if str(v) in f.get("options", []) else str(f.get("def", ""))
		"text":
			return str(v).strip_edges().substr(0, int(f.get("max", 200)))
	return v


## A full rules dictionary for `mode` with every default filled in.
static func defaults_for(mode: String) -> Dictionary:
	var r := {}
	for k in fields_for(mode):
		if k in ["players_min", "players_max", "mode"]:
			continue
		r[k] = FIELDS[k]["def"]
	r["mode"] = mode
	var fmt: Array = MODE_FORMATS.get(mode, ["duel"])
	r["format"] = fmt[0]
	match str(r["format"]):
		"duel":
			r["teams"] = 2
			r["players"] = [2, 2]
		"ffa":
			r["teams"] = 0
			r["players"] = [2, 8]
		"teams":
			r["teams"] = 2
			r["players"] = [4, 8]
		"tag":
			r["teams"] = 2
			r["players"] = [4, 4]
			r["rounds"] = 3
		"coop":
			r["teams"] = 1
			r["players"] = [1, 4]
			r["win"] = "survive"
			r["revive"] = true
			r["round_time"] = 0.0
			r["rounds"] = 1
		"practice":
			r["teams"] = 2
			r["players"] = [1, 2]
			r["win"] = "none"
			r["rounds"] = 1
			r["round_time"] = 0.0
	if mode in ["spotlight_hog", "chumball", "absolute_unit"]:
		r["win"] = "score"
		r["respawn"] = true
		r["lives"] = 0          # unlimited: score modes keep everyone in the fight
		r["rounds"] = 1
	return r


## Clamps every known field and fills missing ones; unknown keys (hooks, mod data) are kept,
## except inside "fighter_mods", which keeps only FIGHTER_MODS keys with clamped values.
static func normalize(rules: Dictionary) -> Dictionary:
	var mode := str(rules.get("mode", "standard"))
	var out := defaults_for(mode)
	for k in rules:
		out[k] = rules[k]
	for k in FIELDS:
		if out.has(k):
			out[k] = coerce(k, out[k])
	var pl: Array = out.get("players", [2, 2]) if typeof(out.get("players")) == TYPE_ARRAY else [2, 2]
	var lo := clampi(int(pl[0]) if pl.size() > 0 and _is_number(pl[0]) else 2, 1, 8)
	var hi := clampi(int(pl[1]) if pl.size() > 1 and _is_number(pl[1]) else lo, 1, 8)
	out["players"] = [lo, maxi(lo, hi)]
	if out.has("fighter_mods"):
		out["fighter_mods"] = clean_fighter_mods(out["fighter_mods"])
	return out


static func _is_number(v) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))


## A numeric rules field as the simulation may use it: its default when missing or not a finite
## number, otherwise clamped to the field's range.
static func field_num(rules: Dictionary, key: String) -> float:
	var f := field(key)
	var v = rules.get(key)
	if not _is_number(v):
		return float(f.get("def", 0.0))
	return clampf(float(v), float(f.get("min", -1e9)), float(f.get("max", 1e9)))


## Only the allowed fighter modifiers, each a finite number clamped to its range or a bool flag.
## Safe on any input (non-dictionaries give {}); MatchSim applies only what this returns.
static func clean_fighter_mods(fm) -> Dictionary:
	var out := {}
	if typeof(fm) != TYPE_DICTIONARY:
		return out
	for k in fm:
		var spec = FIGHTER_MODS.get(str(k))
		var v = fm[k]
		if spec == null:
			continue
		if typeof(spec) == TYPE_STRING:
			if typeof(v) == TYPE_BOOL:
				out[str(k)] = v
		elif _is_number(v):
			out[str(k)] = clampf(float(v), float(spec[0]), float(spec[1]))
	return out


## Why a fighter_mods entry is not accepted as written ("" when it is).
static func fighter_mod_problem(key: String, v) -> String:
	var spec = FIGHTER_MODS.get(key)
	if spec == null:
		return "'%s' is not a fighter modifier rules can change." % key
	if typeof(spec) == TYPE_STRING:
		return "" if typeof(v) == TYPE_BOOL else "'%s' must be true or false." % key
	if not _is_number(v):
		return "'%s' must be a number." % key
	if float(v) < float(spec[0]) or float(v) > float(spec[1]):
		return "'%s' must be between %s and %s." % [key, str(spec[0]), str(spec[1])]
	return ""


## Problems with a preset: [{field, severity, text}]. Errors block saving/hosting; warnings explain.
static func validate(rules: Dictionary) -> Array:
	var out := []
	var err := func(k: String, t: String) -> void: out.append({"field": k, "severity": "error", "text": t})
	var warn := func(k: String, t: String) -> void: out.append({"field": k, "severity": "warning", "text": t})
	var mode := str(rules.get("mode", "standard"))
	var fmt := str(rules.get("format", "duel"))
	var teams := int(rules.get("teams", 2))
	var pl: Array = rules.get("players", [2, 2])
	var lo := int(pl[0]) if pl.size() > 0 else 2
	var hi := int(pl[1]) if pl.size() > 1 else lo
	if str(rules.get("name", "")).strip_edges() == "":
		err.call("name", "Give the rules a name.")
	if not ModeRegistry.has(mode):
		err.call("mode", "Unknown mode '%s' (a mod that adds it may be missing)." % mode)
	elif not fmt in MODE_FORMATS.get(mode, FORMATS):
		err.call("format", "%s needs the %s format." % [mode.capitalize(), " or ".join(MODE_FORMATS.get(mode, []))])
	match fmt:
		"duel":
			if teams != 2 or lo != 2 or hi != 2:
				err.call("players_max", "A duel is exactly two fighters on two sides.")
		"ffa":
			if teams != 0:
				err.call("teams", "Free-for-all has no teams: set Teams to 0.")
		"teams", "tag":
			if teams < 2:
				err.call("teams", "Team formats need at least 2 teams.")
			elif hi < teams:
				err.call("players_max", "%d teams need at least %d fighters." % [teams, teams])
			if fmt == "tag" and hi < teams * 2:
				err.call("players_max", "Tag needs two fighters per team (%d)." % (teams * 2))
		"coop":
			if teams < 1 or teams > 2:
				err.call("teams", "Co-op uses 1 team (waves) or 2 (players against a bot side).")
		"practice":
			if hi > 2:
				err.call("players_max", "Practice is you and one dummy.")
	if lo > hi:
		err.call("players_min", "The minimum is above the maximum.")
	if hi > 8:
		err.call("players_max", "At most 8 fighters fit in the cage.")
	if mode == "chumball" and teams != 2:
		err.call("teams", "Chumball is played by exactly two teams.")
	var win := str(rules.get("win", "ko"))
	if win == "survive" and fmt != "coop":
		err.call("win", "'Survive' only works in co-op formats.")
	if win == "none" and fmt != "practice":
		err.call("win", "Only practice can have no winner.")
	if win == "score" and int(rules.get("score_target", 0)) < 1:
		err.call("score_target", "Set a score target of at least 1.")
	if win == "score" and mode == "standard" and int(rules.get("ko_points", 1)) == 0:
		err.call("ko_points", "With 0 points per KO nobody can score in Standard.")
	if mode in ["chum_rush", "practice"] and int(rules.get("rounds", 1)) != 1:
		err.call("rounds", "%s is played as a single round." % mode.capitalize())
	# 10-point scoring and the referee: standard 1v1 only (the sim also checks, MatchMode)
	var ten_point := mode == "standard" and str(rules.get("scoring", "hp")) == "ten_point"
	if ten_point:
		if fmt != "duel":
			err.call("scoring", "10-point scoring judges a 1v1: set the format to Duel.")
		if float(rules.get("round_time", 99.0)) <= 0.0:
			err.call("round_time", "10-point scoring needs a round timer: the judges score each round at the bell.")
		if win != "ko":
			err.call("win", "With 10-point scoring the judges' cards decide: set the win condition to Last standing (KO).")
		if bool(rules.get("ringout_eliminates", false)):
			warn.call("ringout_eliminates", "With 10-point scoring a ring-out is only a short absence (nobody is knocked out).")
	if mode == "standard" and bool(rules.get("referee", false)) and fmt != "duel":
		err.call("referee", "The referee officiates a 1v1: set the format to Duel.")
	if int(rules.get("rounds", 1)) % 2 == 0 and not ten_point:
		warn.call("rounds", "An even number of rounds can end in a tie (sudden death settles it if enabled).")
	var unlimited := float(rules.get("round_time", 99.0)) <= 0.0
	var respawn := bool(rules.get("respawn", false))
	if unlimited and respawn and win != "score" and int(rules.get("lives", 1)) >= 9 and fmt != "coop":
		warn.call("round_time", "No timer, respawns and 9 lives can make very long matches.")
	if respawn and int(rules.get("lives", 1)) == 1 and win != "score":
		warn.call("respawn", "With 1 life, respawning has no effect (raise Lives, set 0 for unlimited, or use Score).")
	if bool(rules.get("revive", false)) and not fmt in ["teams", "tag", "coop"]:
		warn.call("revive", "Revives only work when teammates exist.")
	if float(rules.get("damage_mult", 1.0)) >= 3.0 and float(rules.get("health_mult", 1.0)) <= 0.5:
		warn.call("damage_mult", "Very high damage with low health: most hits will knock out.")
	if not bool(rules.get("abilities", true)) and float(rules.get("cooldown_rate", 1.0)) != 1.0:
		warn.call("cooldown_rate", "Ability recharge speed does nothing while abilities are off.")
	if not bool(rules.get("juice", true)) and (float(rules.get("hype_mult", 1.0)) != 1.0 or float(rules.get("start_hype", 0.0)) > 0.0):
		warn.call("hype_mult", "Hype settings do nothing while JUICE is off.")
	if hi + int(rules.get("bots", 0)) > 8 and int(rules.get("bots", 0)) > 0:
		warn.call("bots", "Bots only fill slots up to the maximum fighters.")
	var hooks = rules.get("fighter_hooks", [])
	if typeof(hooks) == TYPE_ARRAY:
		for h in hooks:
			if typeof(h) == TYPE_DICTIONARY:
				for e in Hooks.validate(h):
					err.call("fighter_hooks", e)
	if rules.has("fighter_mods"):
		var fm = rules["fighter_mods"]
		if typeof(fm) != TYPE_DICTIONARY:
			err.call("fighter_mods", "Fighter modifiers must be a list of name: value pairs.")
		else:
			for k in fm:
				var problem := fighter_mod_problem(str(k), fm[k])
				if problem != "":
					err.call("fighter_mods", problem)
	return out


static func has_errors(problems: Array) -> bool:
	return problems.any(func(p): return str(p["severity"]) == "error")


## One-line summary for lists and lobbies.
static func describe(rules: Dictionary) -> String:
	var bits := [str(rules.get("mode", "standard")).capitalize(), str(rules.get("format", "")).to_upper()]
	var rt := float(rules.get("round_time", 99.0))
	bits.append("%d round%s" % [int(rules.get("rounds", 1)), "" if int(rules.get("rounds", 1)) == 1 else "s"])
	bits.append("no timer" if rt <= 0.0 else "%ds" % int(rt))
	if str(rules.get("win", "ko")) == "score":
		bits.append("first to %d" % int(rules.get("score_target", 5)))
	for k in ["health_mult", "damage_mult", "gravity_mult"]:
		if absf(float(rules.get(k, 1.0)) - 1.0) > 0.01:
			bits.append("%s ×%.2f" % [str(FIELDS[k]["label"]).to_lower(), float(rules[k])])
	if str(rules.get("mode", "standard")) == "standard":
		if str(rules.get("scoring", "hp")) == "ten_point":
			bits.append("10-point")
		if bool(rules.get("referee", false)):
			bits.append("referee")
	return " · ".join(bits)
