class_name CampaignMatchMode
extends MatchMode
## Rules of a campaign fight (CAMPAIGN.md §5, §11). One round; the player side (team 0, "player"
## roles) wins when every enemy-side fighter is out and no wave/tag partner is waiting; loses
## when no party fighter is standing. Implements:
##   * carried run state: start HP, start statuses, next-fight rules, campaign-only fighter mods
##     (prevent_knockdowns, revive_speed, assist_rate) and the "round_start" hook at the bell;
##   * waves (later groups parked out of the world, released when <= trigger enemies remain) and
##     sequential entries; the active-fighter cap of 8;
##   * enemy tag bouts (one active, partners regenerate, swap on low HP / KO) and the party
##     tag-team format (Switch Target = tag, benched Taunt = Cheer, benched Ability 1 = Assist);
##     the solo player's one free Granny cameo in tag bouts;
##   * simultaneous co-op downed/revive on MatchMode's revive machinery (hold Grab next to the
##     downed ally for 2 s; revive at 30%; the 15 s timer shrinks 5 s per prior down; expiry = Out);
##   * timed sudden death (everyone to 1 HP, decision after a grace period), low gravity,
##     hype x2, puddles x2, ffa enemies, hazards (CampaignHazards);
##   * per-fighter campaign stats (biggest hit, KOs, minion KOs, knockdowns suffered, taunts,
##     downs, hit by the boss) reported in build_result()["campaign"].
## Roles come from EncounterBuilder.build_match: cfg.roles[i] = {role: player|enemy|minion|boss,
## player_id, start_hp, statuses, next_rules, wave, tag, kind}.

const PARK_DEPTH := -60.0

var cfg := {}
var roles: Array = []
var hazards: CampaignHazards
var stats := {}                  ## fighter index -> campaign stats
var outcome := ""                ## "win" | "loss" once decided
var _sd_time := 0.0
var _event_cursor := 0
var _waves: Array = []           ## wave index -> [fighter indices]
var _wave := 0
var _wave_trigger := 1
var _parked := {}                ## fighter index -> true
var _groups := {}                ## "enemy" / "party" -> tag group state
var _trackers := {}              ## fighter index -> FighterInput.PressTracker (mode-side press detection)
var _down_counts := {}           ## fighter index -> times downed this fight (shrinks the timer)
var _granny_available := false
var _zone_seen := {}
var _bell_done := false
var _sd_hp := {}                 ## fighter index -> health when sudden death began


func _init(config := {}) -> void:
	cfg = config


func id() -> String:
	return "campaign"


func role_of(f: Fighter) -> Dictionary:
	return roles[f.index] if f.index < roles.size() else {"role": "enemy"}


func is_party(f: Fighter) -> bool:
	return str(role_of(f).get("role", "")) == "player"


func is_enemy_side(f: Fighter) -> bool:
	return str(role_of(f).get("role", "")) in ["enemy", "minion", "boss"]


func setup(match_sim) -> void:
	super.setup(match_sim)
	roles = cfg.get("roles", [])
	var r: Dictionary = cfg.get("rules", {})
	for f: Fighter in sim.fighters:
		var role := role_of(f)
		var rn := str(role.get("role", "enemy"))
		f.flags["campaign_role"] = rn
		if rn == "minion":
			f.flags["minion"] = true
		if rn == "boss":
			f.flags["boss"] = true
		stats[f.index] = {"biggest_hit": 0.0, "kos": 0, "minion_kos": 0, "knockdowns": 0, "taunts": 0, "downs": 0,
			"damage_dealt": 0.0, "damage_taken": 0.0, "hit_by_boss": false}
		if rn == "player" and float(role.get("start_hp", -1.0)) > 0.0:
			f.health = clampf(float(role["start_hp"]), 1.0, f.max_health)
		if float(r.get("gravity", 1.0)) < 0.999:
			for rb in f.rig.bodies:
				rb.gravity_scale = float(r["gravity"])
		if float(r.get("hype_mult", 1.0)) != 1.0:
			f.mods["hype_gain"] = float(f.mods["hype_gain"]) * float(r["hype_mult"])
		_trackers[f.index] = FighterInput.PressTracker.new()
	# waves (explicit wave numbers from the plan); wave 0 = present at the bell
	var max_wave := 0
	for i in roles.size():
		max_wave = maxi(max_wave, int(roles[i].get("wave", -1)))
	_waves = []
	for w in max_wave + 1:
		_waves.append([])
	for i in roles.size():
		var w2 := int(roles[i].get("wave", -1))
		if w2 >= 1 and i < sim.fighters.size():
			_waves[w2].append(i)
			_park(sim.fighters[i])
	_wave_trigger = int(r.get("waves", {}).get("trigger_alive", 1))
	# tag groups
	var enemy_tag: Array = []
	var party_tag: Array = []
	for f2: Fighter in sim.fighters:
		var role2 := role_of(f2)
		if bool(role2.get("tag", false)):
			if is_party(f2):
				party_tag.append(f2.index)
			elif not _parked.has(f2.index):
				enemy_tag.append(f2.index)
	if enemy_tag.size() >= 2:
		var et: Dictionary = r.get("enemy_tag", {})
		_groups["enemy"] = {"members": enemy_tag, "active": enemy_tag[0], "cd_until": 0.0, "regen": float(et.get("regen", 3.0)),
			"stamina_regen": 10.0, "swap_below": float(et.get("swap_below", 0.45)), "cooldown": float(et.get("cooldown", 8.0)),
			"entry_invuln": float(et.get("entry_invuln", 1.5))}
		for i2 in range(1, enemy_tag.size()):
			_park(sim.fighters[enemy_tag[i2]], true)
	if party_tag.size() >= 2:
		var pt: Dictionary = cfg.get("coop", {}).get("tag", {})
		_groups["party"] = {"members": party_tag, "active": party_tag[0], "cd_until": 0.0, "regen": float(pt.get("regen", 3.0)),
			"stamina_regen": float(pt.get("stamina_regen", 10.0)), "cooldown": float(pt.get("cooldown", 8.0)),
			"entry_invuln": float(pt.get("entry_invuln", 1.5)), "assist_cd": float(pt.get("assist_cooldown", 20.0)),
			"cheer_cd": float(pt.get("cheer_cooldown", 3.0)), "cheer_hype": float(pt.get("cheer_hype", 5.0)),
			"assist_ready": {}, "cheer_ready": {}}
		for i3 in range(1, party_tag.size()):
			_park(sim.fighters[party_tag[i3]], true)
	_granny_available = bool(r.get("granny_assist", false))
	hazards = CampaignHazards.new(self, r.get("hazards", []), cfg.get("hazard_defs", {}))
	if _revive_enabled():
		# downed / revive run on MatchMode's machinery (_downed_at, _tick_revives, bot_objective)
		var coop: Dictionary = cfg.get("coop", {})
		rules["revive"] = true
		rules["downed_time"] = float(coop.get("downed_time", 15.0))
		rules["revive_health"] = float(coop.get("revive_frac", 0.3))


# =============================================================================================
# Parking (waves, tag partners): out of the world, frozen, INACTIVE (not targetable)
# =============================================================================================

## `resting`: a tag partner on the bench (the HUD shows it RESTING, as in the versus Tag Team
## mode, instead of DOWN; the flag is replicated to network clients with the roster).
func _park(f: Fighter, resting := false) -> void:
	if _parked.has(f.index):
		return
	_parked[f.index] = true
	if resting:
		f.flags["resting"] = true
	f.set_inactive(true)
	f.rig.place(Vector3(f.index * 4.0, PARK_DEPTH, 0.0), 0.0)
	for rb in f.rig.bodies:
		rb.freeze = true


func _unpark(f: Fighter, pos: Vector3, yaw: float, invuln: float) -> void:
	if not _parked.has(f.index):
		return
	_parked.erase(f.index)
	f.flags.erase("resting")
	for rb in f.rig.bodies:
		rb.freeze = false
	f.rig.place(pos, yaw)
	f.rig.freeze_motion()
	f.motor.reset_feet()
	f.set_inactive(false)
	f.invuln_until = f.time + invuln
	sim.emit_event({"type": "enter", "fighter": f.index, "pos": pos})


func is_parked(f: Fighter) -> bool:
	return _parked.has(f.index)


# =============================================================================================
# Tick
# =============================================================================================

func tick(dt: float) -> void:
	var was_intro := phase == Phase.INTRO
	super.tick(dt)
	if was_intro and phase == Phase.FIGHT and not _bell_done:
		_on_bell()


func _on_bell() -> void:
	_bell_done = true
	for f: Fighter in sim.fighters:
		if _parked.has(f.index):
			continue
		_fighter_bell(f)
	hazards.on_bell()
	sim.emit_event({"type": "campaign_rules", "tags": cfg.get("rule_tags", [])})
	# knockouts during the intro (bots may fire abilities before the bell) end the fight now
	check_round_over()


## Per-fighter start-of-fight effects (also run when a parked fighter first enters; `late`
## fighters also get the "round_start" hooks then — MatchMode fires them for everyone at the bell).
func _fighter_bell(f: Fighter, late := false) -> void:
	if f.flags.get("_belled", false):
		return
	f.flags["_belled"] = true
	var role := role_of(f)
	for st in role.get("statuses", []):
		var sc: Dictionary = (st as Dictionary).duplicate(true)
		sc["source"] = f
		f.statuses.add(sc)
	var nr: Dictionary = role.get("next_rules", {})
	if bool(nr.get("soaked", false)) and Elements.defs.has("brine"):
		var soak: Dictionary = Elements.defs["brine"].get("status", {}).duplicate(true)
		soak["element"] = "brine"
		soak["source"] = null
		f.statuses.add(soak)
	if bool(nr.get("waive_knockdown", false)):
		f.mods["prevent_knockdowns"] = float(f.mods.get("prevent_knockdowns", 0.0)) + 1.0
	if late:
		f.hooks.fire("round_start", {})


func tick_fight(dt: float) -> void:
	_scan_events()
	_tick_zone_lifetimes()
	_tick_waves()
	_tick_groups(dt)
	hazards.tick(dt)
	if sudden_death and sim.time - _sd_time > float(cfg.get("rules", {}).get("sudden_death_grace", 45.0)):
		_decide_by_health()
	check_round_over()


func _scan_events() -> void:
	for ev in sim.events_since(_event_cursor):
		_event_cursor = int(ev["seq"])
		match str(ev.get("type", "")):
			"hit":
				var a := int(ev.get("fighter", -1))
				var t := int(ev.get("target", -1))
				var dmg := float(ev.get("damage", 0.0))
				if a >= 0 and stats.has(a) and not bool(ev.get("blocked", false)):
					stats[a]["damage_dealt"] = float(stats[a]["damage_dealt"]) + dmg
					stats[a]["biggest_hit"] = maxf(float(stats[a]["biggest_hit"]), dmg)
				if t >= 0 and stats.has(t):
					stats[t]["damage_taken"] = float(stats[t]["damage_taken"]) + dmg
					if a >= 0 and a < sim.fighters.size() and str(role_of(sim.fighters[a]).get("role", "")) == "boss" and dmg > 0.0:
						stats[t]["hit_by_boss"] = true
			"taunt":
				var f1 := int(ev.get("fighter", -1))
				if stats.has(f1):
					stats[f1]["taunts"] = int(stats[f1]["taunts"]) + 1
			"knockdown":
				var f2 := int(ev.get("fighter", -1))
				if stats.has(f2):
					stats[f2]["knockdowns"] = int(stats[f2]["knockdowns"]) + 1
			"ko":
				var by := int(ev.get("by", -1))
				var victim := int(ev.get("fighter", -1))
				if by >= 0 and stats.has(by) and victim != by:
					stats[by]["kos"] = int(stats[by]["kos"]) + 1
					if victim >= 0 and victim < sim.fighters.size() and sim.fighters[victim].flags.get("minion", false):
						stats[by]["minion_kos"] = int(stats[by]["minion_kos"]) + 1
			"downed":
				var f3 := int(ev.get("fighter", -1))
				if stats.has(f3):
					stats[f3]["downs"] = int(stats[f3]["downs"]) + 1


func _tick_zone_lifetimes() -> void:
	var m := float(cfg.get("rules", {}).get("zone_duration_mult", 1.0))
	if m == 1.0:
		return
	for ent in sim.effects.entities:
		if ent["kind"] == "zone" and int(ent["owner"]) >= 0 and not _zone_seen.has(int(ent["id"])):
			_zone_seen[int(ent["id"])] = true
			ent["life"] = float(ent["life"]) * m


# ---------------------------------------------------------------------------------------------
# Waves
# ---------------------------------------------------------------------------------------------

func _tick_waves() -> void:
	if _wave + 1 >= _waves.size():
		return
	var alive := 0
	for f: Fighter in sim.fighters:
		if is_enemy_side(f) and not f.is_out() and not _parked.has(f.index):
			alive += 1
	if alive <= _wave_trigger:
		_wave += 1
		var idx: Array = _waves[_wave]
		for i in idx.size():
			var f2: Fighter = sim.fighters[idx[i]]
			var sp: Array = sim.safe_spawn_for(f2)
			_unpark(f2, sp[0], sp[1], 0.6)
			_fighter_bell(f2, true)
		sim.emit_event({"type": "wave", "wave": _wave + 1, "count": idx.size()})


# ---------------------------------------------------------------------------------------------
# Tag groups (enemy tag bouts, party tag-team format) and assists
# ---------------------------------------------------------------------------------------------

func _tick_groups(dt: float) -> void:
	for gname in _groups:
		var g: Dictionary = _groups[gname]
		# benched partners regenerate
		for i in g["members"]:
			var f: Fighter = sim.fighters[i]
			if _parked.has(i) and f.health > 0.0:
				f.health = minf(f.max_health, f.health + float(g["regen"]) * dt)
				f.stamina = minf(f.max_stamina, f.stamina + float(g["stamina_regen"]) * dt)
		var active: Fighter = sim.fighters[int(g["active"])]
		if gname == "enemy":
			if not active.is_out() and sim.time >= float(g["cd_until"]) and active.health_frac() < float(g["swap_below"]) and _can_tag_out(active):
				var best := _best_partner(g, active)
				if best >= 0 and sim.fighters[best].health_frac() > active.health_frac() + 0.2:
					_swap(g, best)
		else:
			_tick_party_tag(g)
	# solo Granny cameo (tag bouts): Switch Target once
	if _granny_available:
		for f2: Fighter in sim.fighters:
			if is_party(f2) and not f2.is_out() and not _parked.has(f2.index):
				var pressed: int = _presses(f2)
				if (pressed >> FighterInput.TARGET) & 1 == 1 and f2.target != null:
					_granny_available = false
					_assist_hit(null, f2, {"damage": 10.0, "knockback": 3.0, "poise": 30.0, "stun": 0.5}, "Granny Haymaker")


func _presses(f: Fighter) -> int:
	var tr: FighterInput.PressTracker = _trackers.get(f.index)
	return tr.consume(f.input) if tr else 0


func _can_tag_out(f: Fighter) -> bool:
	return f.state in [Fighter.State.NEUTRAL, Fighter.State.GUARD] and f.held_by == null and f.holding == null


func _best_partner(g: Dictionary, active: Fighter) -> int:
	var best := -1
	var best_frac := -1.0
	for i in g["members"]:
		if i == active.index:
			continue
		var f: Fighter = sim.fighters[i]
		if _parked.has(i) and f.health > 0.0 and f.health_frac() > best_frac:
			best_frac = f.health_frac()
			best = i
	return best


func _swap(g: Dictionary, incoming: int) -> void:
	var out_f: Fighter = sim.fighters[int(g["active"])]
	var in_f: Fighter = sim.fighters[incoming]
	var pos: Vector3 = out_f.ground_pos() if not out_f.is_out() else sim.safe_spawn_for(in_f)[0]
	var yaw := out_f.facing_yaw
	if not out_f.is_out():
		_park(out_f, true)
	_unpark(in_f, sim.clamp_to_arena(pos, 0.8), yaw, float(g.get("entry_invuln", 1.5)))
	_fighter_bell(in_f, true)
	g["active"] = incoming
	g["cd_until"] = sim.time + float(g.get("cooldown", 8.0))
	sim.emit_event({"type": "tag", "fighter": incoming, "out": out_f.index})


func _tick_party_tag(g: Dictionary) -> void:
	var active: Fighter = sim.fighters[int(g["active"])]
	for i in g["members"]:
		var f: Fighter = sim.fighters[i]
		var pressed := _presses(f)
		var bot := sim.input_sources[i] is BotBrain
		if i == int(g["active"]):
			var wants_tag := (pressed >> FighterInput.TARGET) & 1 == 1
			if bot and not f.is_out() and f.health_frac() < 0.35:
				var bp := _best_partner(g, f)
				wants_tag = bp >= 0 and sim.fighters[bp].health_frac() > f.health_frac() + 0.25
			if wants_tag and sim.time >= float(g["cd_until"]) and _can_tag_out(f):
				var bp2 := _best_partner(g, f)
				if bp2 >= 0:
					_swap(g, bp2)
					return
			continue
		if not _parked.has(i) or f.health <= 0.0:
			continue
		# benched partner: request tag, cheer, assist
		if (pressed >> FighterInput.TARGET) & 1 == 1 and sim.time >= float(g["cd_until"]) and _can_tag_out(active):
			_swap(g, i)
			return
		if (pressed >> FighterInput.TAUNT) & 1 == 1 and sim.time >= float(g["cheer_ready"].get(i, 0.0)):
			g["cheer_ready"][i] = sim.time + float(g["cheer_cd"])
			active.gain_hype(float(g["cheer_hype"]))
			sim.emit_event({"type": "cheer", "fighter": i, "to": active.index})
		var want_assist := (pressed >> FighterInput.AB1) & 1 == 1
		if bot and active.target != null and active.pos().distance_to(active.target.pos()) < 3.0:
			want_assist = true
		if want_assist and sim.time >= float(g["assist_ready"].get(i, 0.0)) and active.target != null and not active.is_out():
			var rate := maxf(0.1, float(f.mods.get("assist_rate", 1.0)))
			g["assist_ready"][i] = sim.time + float(g["assist_cd"]) / rate
			var mv: MoveDef = f.creature.moves.get("dash_attack", f.creature.moves.get("heavy"))
			var pkg := {"damage": mv.damage if mv else 8.0, "knockback": mv.knockback if mv else 3.0,
				"poise": mv.poise if mv else 15.0, "stun": mv.stun if mv else 0.4,
				"element": f.element_for(mv) if mv else "", "buildup": mv.buildup if mv else 0.0}
			_assist_hit(f, active, pkg, f.display_name)


## A one-hit cameo (tag Assist / Granny): an effect hit on the active fighter's target.
func _assist_hit(from: Fighter, active: Fighter, pkg: Dictionary, label_text: String) -> void:
	var tgt := active.target
	if tgt == null or tgt.is_out():
		return
	var e := pkg.duplicate()
	e["id"] = "assist"
	e["class"] = "ability"
	sim.effects.effect_hit(from, tgt, e, active.pos())
	sim.emit_event({"type": "assist", "fighter": from.index if from else -1, "for": active.index, "target": tgt.index,
		"pos": tgt.pos(), "name": label_text})


# ---------------------------------------------------------------------------------------------
# Downed / revive (simultaneous co-op)
# ---------------------------------------------------------------------------------------------

func _revive_enabled() -> bool:
	return str(cfg.get("party", "solo")) == "coop" and not bool(cfg.get("spar", false)) and not _groups.has("party")


## Downs a party member. MatchMode._tick_revives then handles reviving (an ally holding Grab
## next to them; bots get the revive objective from MatchMode.bot_objective) and bleeding out;
## a shorter timer for repeat downs is expressed as an earlier "downed at" time.
func _down(f: Fighter) -> void:
	var coop: Dictionary = cfg.get("coop", {})
	var prior := int(_down_counts.get(f.index, 0))
	_down_counts[f.index] = prior + 1
	var full := float(rules.get("downed_time", 15.0))
	var t := maxf(5.0, full - float(coop.get("downed_shrink", 5.0)) * prior)
	f.set_downed()
	_downed_at[f.index] = sim.time - (full - t)
	_revive.erase(f.index)
	sim.emit_event({"type": "downed_timer", "fighter": f.index, "seconds": t})


## Campaign sudden death: everyone drops to 1 HP and a decision follows after a grace period
## (tick_fight); MatchMode's "next clean hit wins" check does not apply.
func tick_sudden_death() -> void:
	pass


# ---------------------------------------------------------------------------------------------
# Outcome
# ---------------------------------------------------------------------------------------------

func on_depleted(f: Fighter, attacker: Fighter, _hit: Dictionary) -> void:
	if f.is_out():
		return
	if is_party(f) and _revive_enabled() and _party_standing(f) > 0:
		_down(f)
		check_round_over()
		return
	var group_name := "party" if is_party(f) else "enemy"
	f.knock_out(attacker)
	if attacker and attacker != f:
		attacker.stats_record["kos"] += 1
	sim.emit_event({"type": "elimination", "fighter": f.index, "by": attacker.index if attacker else -1})
	if _groups.has(group_name) and int(_groups[group_name]["active"]) == f.index:
		var g: Dictionary = _groups[group_name]
		var nxt := _best_partner(g, f)
		if nxt >= 0:
			_swap(g, nxt)
	check_round_over()


func _party_standing(exclude: Fighter = null) -> int:
	var n := 0
	for f: Fighter in sim.fighters:
		if f == exclude or not is_party(f):
			continue
		if _parked.has(f.index):
			if f.health > 0.0:
				n += 1
		elif not is_beaten(f):
			n += 1
	return n


func enemies_remaining() -> int:
	var n := 0
	for f: Fighter in sim.fighters:
		if not is_enemy_side(f):
			continue
		if _parked.has(f.index):
			if f.health > 0.0:
				n += 1
		elif not is_beaten(f):
			n += 1
	return n


func check_round_over() -> void:
	if phase != Phase.FIGHT or outcome != "":
		return
	if enemies_remaining() == 0:
		_finish(true)
	elif _party_standing() == 0:
		_finish(false)


func _finish(win: bool) -> void:
	outcome = "win" if win else "loss"
	end_round(EncounterBuilder.PLAYER_TEAM if win else EncounterBuilder.ENEMY_TEAM)


func on_timeout() -> void:
	if outcome != "":
		return
	if not sudden_death:
		sudden_death = true
		_sd_time = sim.time
		for f: Fighter in sim.fighters:
			var standing := (not is_beaten(f) and not _parked.has(f.index)) or (_parked.has(f.index) and f.health > 0.0)
			if standing:
				_sd_hp[f.index] = f.health
				f.health = minf(f.health, 1.0)
		sim.emit_event({"type": "sudden_death"})
		round_timer = 0.0


func _decide_by_health() -> void:
	if outcome != "":
		return
	var party_hp := 0.0
	var enemy_hp := 0.0
	for f: Fighter in sim.fighters:
		if is_beaten(f) and not _parked.has(f.index):
			continue
		# after sudden death everyone sits at 1 HP: judge by the health they had when time ran out
		var frac := f.health_frac()
		if _sd_hp.has(f.index):
			frac = float(_sd_hp[f.index]) / maxf(1.0, f.max_health)
		if is_party(f):
			party_hp += frac
		elif is_enemy_side(f):
			enemy_hp += frac
	sim.emit_event({"type": "decision", "party": party_hp, "enemy": enemy_hp})
	_finish(party_hp > enemy_hp)


## Modes may cancel knockdowns: campaign fighters can carry one-shot knockdown protection
## (Pocket Ref, "A Word With the Ref"). Bosses are handled by BossMode.
func intercept_knockdown(f: Fighter, reason: String, _by: Fighter) -> bool:
	if reason in ["poise", "move", "hit"] and float(f.mods.get("prevent_knockdowns", 0.0)) >= 1.0:
		f.mods["prevent_knockdowns"] = float(f.mods["prevent_knockdowns"]) - 1.0
		f.poise = f.effective_max_poise()
		sim.emit_event({"type": "knockdown_prevented", "fighter": f.index})
		return true
	return false


func build_result() -> Dictionary:
	var res := super.build_result()
	var players := {}
	var enemies_total := 0
	var enemies_kod := 0
	for f: Fighter in sim.fighters:
		var role := role_of(f)
		var st: Dictionary = stats.get(f.index, {})
		if is_party(f):
			var out := is_beaten(f) and not _parked.has(f.index)
			var hp := maxf(0.0, f.health)
			if _sd_hp.has(f.index) and outcome == "win":
				hp = maxf(hp, float(_sd_hp[f.index]))      # the 1-HP drop is a rule of this fight only
			players[str(role.get("player_id", ""))] = {"hp": hp if not out else 0.0, "max_hp": f.max_health,
				"hype": f.hype, "out": out, "knockdowns": int(st.get("knockdowns", 0)), "kos": int(st.get("kos", 0)),
				"minion_kos": int(st.get("minion_kos", 0)), "damage_dealt": float(st.get("damage_dealt", 0.0)),
				"damage_taken": float(st.get("damage_taken", 0.0)), "biggest_hit": float(st.get("biggest_hit", 0.0)),
				"taunts": int(st.get("taunts", 0)), "downs": int(st.get("downs", 0)), "hit_by_boss": bool(st.get("hit_by_boss", false))}
		elif is_enemy_side(f):
			enemies_total += 1
			if is_beaten(f) and not _parked.has(f.index):
				enemies_kod += 1
	res["campaign"] = {"won": outcome == "win", "outcome": outcome, "time": sim.time, "sudden_death": sudden_death,
		"players": players, "enemies_total": enemies_total, "enemies_kod": enemies_kod}
	return res


func hud_status() -> String:
	var parts := []
	if sudden_death:
		parts.append("SUDDEN DEATH")
	if _waves.size() > 1:
		parts.append("WAVE %d/%d" % [_wave + 1, _waves.size()])
	parts.append("%d LEFT" % enemies_remaining())
	return "  ·  ".join(parts)


## Visible rule tags for the HUD / pre-fight card (COOP-06: participants see active rules).
func rule_tags() -> Array:
	return cfg.get("rule_tags", [])
