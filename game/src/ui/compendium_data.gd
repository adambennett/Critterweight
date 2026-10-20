class_name CompendiumData
extends RefCounted
## Read-only field guide. Stats/cooldowns/status values come from the loaded content, including mods.
const ABILITIES := {
	"f_varga": ["Slip a short distance in your movement direction with brief evasion, then deal 18% more damage for two seconds.", "Take a breath: stamina regeneration doubles and poise regeneration rises by 50% for four seconds. It restores resources over time, not HP.", "Push nearby rivals, then attack 20% faster with 20% more damage and 50% faster stamina regeneration for seven seconds, in addition to the standard JUICE bonus."],
	"f_knell": ["Send a violet ghost-light toward your target. It gently tracks them, deals Spectral damage and builds Haunted.", "Vanish briefly, then emerge 3.2 metres in the movement direction. A small pulse punishes enemies near your exit. Mired prevents the dive.", "Ring three expanding pulses around yourself, building Haunted. For six seconds, take 20% less damage and 25% less knockback. The pulses can be escaped or interrupted."],
	"f_stoke": ["Vent a short cone of steam in front of you, pushing enemies and destroying incoming projectiles.", "A four-second self buff: attacks animate 25% faster and hits add Scorch. Stamina stops regenerating and you lose 1 HP per second (cannot kill you). Use it before a combo; it does not shoot anything.", "Burst around you, then gain armor against everything except heavy hits for six seconds. Hits add Scorch and leave burning ground. Costs 30 stamina when it ends."],
	"f_dredge": ["Spit a Brine glob that leaves a puddle when it expires.", "Plant yourself for a 2.5-second counter stance. Incoming knockback is halved and frontal attacks trigger a Brine counter. Bait an enemy into hitting you; pressing it at range will not fire a shot.", "Release a knockdown wave and flood the arena for eight seconds. Move faster and throw farther while the tide lasts."],
	"f_gusto": ["Fire a wind projectile with strong knockback; it bursts into a pushing gust.", "Hover above the floor for 1.2 seconds. Move during the hover to reposition or escape ground hazards. Jolted and Mired can prevent hovering.", "Push a cone of opponents away, then gain speed and free dodges for seven seconds. Dodges leave vortices and taunts heal you."],
	"f_dozer": ["Charge ahead with armor, carrying opponents into walls. Steering is limited: line up the charge first.", "Raise a dust cloud around yourself for four seconds. It follows you, destroys nearby projectiles, grants armor against light attacks and stops nearby enemies regenerating poise. Close the distance while it is active.", "Slam a line through opponents, then gain full armor and refresh Bulldoze after each use for six seconds. Charged opponents leave boulders."],
	"f_slurry": ["Lob Sludge toward the opponent and leave a damaging puddle. Stores two charges.", "Dive, then emerge 4.5 metres in the movement direction after half a second, hitting nearby enemies. Aim with the movement stick; without movement it uses your facing. Mired can prevent the dive.", "Send a Sludge wave and lay a trail of puddles. For six seconds, light attacks spit projectiles, standing in Sludge heals you, and Gunked opponents take extra damage."],
	"f_jitters": ["Launch a slowly homing Static orb that ends with a small pulse.", "Throw a spring pad onto the floor ahead of you. It lasts ten seconds; at most two can exist. Stepping on one launches a fighter, and enemies are stunned. Look for the pad on the ground rather than a direct hit.", "Burst Static around you, then gain light armor for eight seconds. Landings pulse and light hits chain lightning to nearby enemies."],
}
const MODES := {
	"standard": "Knock out the opposition. Rounds, lives, time limits and teams come from the selected preset. When time expires, the mode resolves the surviving teams.",
	"spotlight_hog": "Stand in the moving spotlight to earn points. Push rivals out of it while keeping yourself inside. Reach the score target to win.",
	"chumball": "Drive the chum ball into the opposing goal. Attacks and body contact move the ball; defend your goal while disrupting the other team.",
	"absolute_unit": "The oversized Unit earns one point per second. Knock it out to become the next Unit after a two-second transformation. First to the score target, or the highest score when time expires, wins. The default Unit has 2.5x health, light-attack armor and stronger hits, but moves slower, cannot dodge and has longer ability cooldowns.",
	"chum_rush": "Survive successive enemy waves. Clear enemies to advance; use the breaks to recover and choose supplements when offered.",
	"tag_team": "Teams alternate the active fighter. Tag strategically to let a battered teammate rest; eliminate the other team. Tag uses D-pad Down / G with a four-second cooldown. Resting partners can taunt to cheer, or use Ability 1 for an assist.",
	"practice": "A training cage with no meaningful win/loss stakes. Use the practice options to set the opponent and work on specific moves.",
}
const REACTIONS := {
	"bell_ringer": "Consumes Rattled and Haunted for a short stun, damage and a burst of poise damage.",
	"grave_chill": "Consumes Soaked and slows movement for two seconds.",
	"crack_guard": "Consumes Caked to deal damage and briefly open the target's guard.",
	"steam_burst": "Consumes both statuses, damages and pushes nearby fighters, and leaves steam that obscures bots' sight.",
	"flare_up": "Burns away Sludge in an explosive launch. Nearby fighters, including the attacker, can take damage and Scorch build-up.",
	"backdraft": "Refreshes Scorch, spreads its build-up to nearby fighters and doubles the push.",
	"short_out": "Consumes Soaked for damage and a stun. Fighters sharing the puddle can also be shocked.",
	"mudbound": "Consumes both statuses and leaves mud. Mud slows movement and dashes and prevents leaps, hovering and dives.",
	"dilute": "Washes off Sludge, dealing half its remaining damage immediately, capped at 5 HP.",
	"catalyze": "Consumes Static, accelerates the remaining Sludge damage into one second, and splashes Static build-up nearby.",
	"stormfront": "Marks a delayed lightning strike: move out of the marked area before it lands.",
	"crust": "Consumes both statuses to form a shell that reduces damage and knockback but prevents dodging and diving; grabs stick more strongly.",
	"spray": "Consumes Sludge and sprays its build-up onto nearby fighters, leaving a puddle.",
	"sandblast": "Consumes Grit, deals damage, prevents guarding briefly and sprays Grit behind the target.",
}
const GUIDE := {
	"Combat basics": "Light attacks chain; heavy attacks can be charged. Guard faces forward, and a precisely timed guard parries. Dodges have brief evasion windows. Grabs beat passive defense. Damage depends on physical contact and closing speed, so spacing matters.\n\nAbilities use stamina and cooldowns. You cannot start one while knocked down, stunned or committed to an uninterruptible action. The HUD shows the binding, move name and cooldown. Defensive abilities need the right situation to show their benefit. JUICE requires a full Hype meter.",
	"Campaign & saves": "Career is one persistent fighter: take fights, train between them and climb to the belt; it saves after every action in one of three slots. Off the Street is a fresh three-act run. Fight Camp adds the Cannery and permanent upgrades. Select a connected node on the map, resolve its fight or encounter, collect any reward, then choose the next route. Progress saves after committed choices and completed fights. Resume returns to the pending reward, shop, event, rest or map. In a run, quitting during an unfinished fight restarts that fight; in a Career, quitting a bout from the pause menu pulls you out (no purse, minus 4 popularity) unless the judges or the referee have already decided it, and only a crash re-fights it.",
	"Career": "Create a fighter from any playable creature, give them a ring name and pick a difficulty. Each week you train one stat (Stamina, Chin, Speed, Power, Clinch, Defence) or rest to heal. Promoters send two or three fight offers; accept one, train through the camp, then fight on fight week. Wins and finishes raise popularity, which opens bigger promotions (popularity caps per tier: 42, 66, 88), and at 92 the Grand Circuit offers a five-round title shot. Purses buy gym upgrades that make training count for more or heal injuries faster. Injuries from a fight carry into training and the next bout until they heal. Bouts use Cage Rules: 10-point judges and a referee, three rounds (five for titles), and a draw is possible. Quitting a bout from the pause menu pulls you out: no purse and minus 4 popularity.",
	"Ten-point scoring": "With 10-point must scoring nobody can be knocked out by damage: health stays full and the HP bars are hidden. Three judges score every round. Even card weighs everything evenly; Volume leans toward clean strikes landed and parries; Impact leans toward damage and knockdowns. Each judge gives the better fighter 10-9, a round too close to call 10-10 and a dominant round 10-8. The round line under the timer shows each judge's running total; the cards appear between rounds. After the last round the judges decide: Unanimous, Majority or Split Decision, or a Draw. A drawn decision goes to sudden death (next clean hit wins) when Sudden death is on.",
	"Referee": "With the referee on, nobody can hit a fighter who is down. The referee counts a knockdown from a strike; you can get up at once, or stay down to recover stamina faster until he waves you up after four seconds. Five knockdowns in one round and he stops it: with 10-point scoring that is a T.K.O. win, with Health scoring it wins the round. Throws and hazards never count as knockdowns. He also holds the attacker back, waves off stoppages and raises the winner's arm.",
	"Needles, Scrip & Clout": "Scrip is money for the current run. Shop nodes on the campaign map sell supplements, consumables and one service per stall. Rub-down removes side effects; Antidote gives a consumable for later; Restock rerolls the stall once. Selling returns half price.\n\nNeedles' Cannery board is a preview catalog: purchases happen on campaign Shop nodes. Clout buys permanent Fight Camp upgrades and cosmetics; it is not spent at campaign shops.",
	"Cannery challenges": "Chum Cannon: select Warm-up, Pressure or Homing hell. Block, dodge or parry buckets for 45 seconds. Harder settings fire faster and predict your movement; Homing hell also steers early in flight. A parry adds five to the streak. Clout milestones are shared.\n\nCrate Toss: ten throws from behind the line. Near, middle and far rings score 5, 10 and 20. The called ring rotates after each throw. Hit it for +25, plus up to +20 for a consecutive streak. Light tosses and partially charged heaves help hit nearer rings. Fouls, water and misses break your streak. Crates reset when the game ends.",
	"Watching fights": "Spectate offers FOLLOW (automatic director), LOCKED (one fighter) and FREE. Camera cycles with Y / R. LB / RB chooses a fighter. In FREE, use the left stick or WASD to move, right stick or right-mouse drag to look, A / Space to rise and LT / Shift to descend. D-pad or arrow keys adjust playback speed.\n\nThe Bookie's Table can show every AI fight, run it at 1–4x speed or skip ahead at 8x. Watch fights returns to the same bout immediately. Taking over hands you the campaign decisions; the AI still fights.",
	"Profile & controls": "Open Profile from the main menu to rename your profile. Dialogue and fight cards use that name, with Rookie as the default.\n\nFocused text panels scroll with the right stick. Left/right moves between panels; LB/RB changes tabs. In the Arena Editor, View switches between locked map controls and the side panels; Palette and Details buttons hide those panels. Help lists all editing controls.",
}

## Extra lines for a rules preset that uses 10-point scoring or a referee (empty otherwise).
static func officials_text(rules: Dictionary) -> String:
	if str(rules.get("mode", "standard")) != "standard":
		return ""
	var lines := ""
	if str(rules.get("scoring", "hp")) == "ten_point":
		lines += "\nScoring: 10-point must (three judges; no knockouts, every round is fought)"
	if bool(rules.get("referee", false)):
		lines += "\nReferee: on (knockdown count, no hits on a downed fighter, stops it after five knockdowns in a round)"
	return lines


static func entries(section: String) -> Array:
	var result: Array = []
	match section:
		"fighters":
			var ids: Array = []
			for kind in Content.CREATURE_KINDS:
				ids.append_array(Content.ids(kind))
			for id in ids:
				var c := Content.creature(str(id))
				if c and not str(id).begins_with("dev_"):
					result.append({"id": id, "name": c.display_name, "text": fighter_text(c)})
		"elements":
			for id in Elements.defs:
				var d: Dictionary = Elements.defs[id]
				var body := "Build-up reaches %s to apply %s. It decays after %.1f seconds without new build-up.\n\n" % [Elements.rules.get("threshold", 100), d.get("status_name", id), float(Elements.rules.get("decay_delay", 1.5))]
				body += describe_status(d.get("status", {}))
				body += "\n\n[b]Elemental damage matchups[/b]\n"
				for other in Elements.defs:
					var mult := Elements.damage_mult(str(id), str(other))
					if not is_equal_approx(mult, 1.0):
						body += "%s: %+.0f%% damage\n" % [Elements.display_name(str(other)), (mult - 1.0) * 100]
				body += "\n[b]Reactions[/b]\n"
				for r: Dictionary in Elements.reactions.values():
					if r.get("a") == id or r.get("b") == id:
						var other := str(r["b"] if r["a"] == id else r["a"])
						body += "[b]%s + %s: %s[/b]\n%s\n\n" % [d["name"], Elements.display_name(other), str(r["name"]), REACTIONS.get(str(r.get("id", "")), "Combines these elemental statuses.")]
				result.append({"id": id, "name": d["name"], "text": body})
		"arenas":
			for id in Content.ids("arenas"):
				var d := Content.get_entry("arenas", str(id))
				result.append({"id": id, "name": d.get("name", id), "text": "%s\n\nBase: %s\nHazards: %s\nProps: %s\n\nUse Arena Editor to inspect the layout and make a separate custom version." % [str(d.get("description", d.get("desc", "Fight space with its own geometry, hazards and sight lines."))), str(d.get("base", "custom")).capitalize(), readable(d.get("hazards", [])), readable(d.get("props", []))]})
		"rules":
			for id in Content.ids("rules"):
				var d := Content.get_entry("rules", str(id))
				result.append({"id": id, "name": d.get("name", id), "text": "%s\n\n%s\n\nRounds: %s\nRound timer: %s seconds (0 = unlimited)\nLives: %s\nScore target: %s%s" % [d.get("description", d.get("desc", "")), MODES.get(str(d.get("mode", "standard")), MODES["standard"]), d.get("rounds", 1), d.get("round_time", 0), d.get("lives", 1), d.get("score_target", "see objective HUD"), officials_text(d)]})
		"field":
			for id in Elements.zones:
				var d: Dictionary = Elements.zones[id]
				var body := "Ground effect · %s\nRadius %.1f m · duration %.1f s\n" % [Elements.display_name(str(d.get("element", ""))), float(d.get("radius", 0)), float(d.get("duration", 0))]
				if d.has("buildup"):
					body += "%s build-up every %s s\n" % [d["buildup"], d.get("tick", 0.5)]
				if d.has("tick_damage"):
					body += "%s damage per tick\n" % d["tick_damage"]
				body += describe_status(d.get("status", {}))
				result.append({"id": id, "name": str(id).capitalize(), "text": body})
			for tab in ArenaCatalog.TABS:
				for d: Dictionary in ArenaCatalog.palette(str(tab)):
					result.append({"id": d.get("id", ""), "name": d.get("name", "Prop"), "text": str(d.get("desc", d.get("description", "Arena object")))})
		"guide":
			for title in GUIDE:
				result.append({"id": title, "name": title, "text": GUIDE[title]})
	return result

static func fighter_text(c: CreatureDef) -> String:
	var text := "[b]%s[/b]\n%s · %s\n\n" % [c.title, Elements.display_name(c.element), "Opponent / NPC" if c.npc_only else "Playable fighter"]
	for pair in [["health", "Health"], ["stamina", "Stamina"], ["walk_speed", "Move speed"], ["poise", "Poise"], ["power", "Power"], ["defense", "Defense"]]:
		text += "%s: %s\n" % [pair[1], str(c.stats.get(pair[0], 0))]
	var i := 0
	for slot in ["ability1", "ability2", "juice"]:
		if c.abilities.has(slot):
			var a: MoveDef = c.abilities[slot]
			text += "\n[b]%s · %s[/b]\n" % [Controls.prompt_for(MartialControls.action(slot, c)), a.display_name]
			text += str(ABILITIES[c.id][i]) if ABILITIES.has(c.id) else ability_summary(a)
			text += "\n" + ("Requires full Hype" if slot == "juice" else "Cooldown %s s · stamina %s · charges %s" % [c.cooldowns.get(slot, 0), a.stamina, c.ability_charges.get(slot, 1)]) + "\n"
		i += 1
	if c.tags.has("martial"):
		text += "\n" + MartialControls.description()
	return text

static func ability_summary(a: MoveDef) -> String:
	var lines := PackedStringArray()
	if not a.windows.is_empty():
		lines.append("Physical attack: %s base damage; %s poise damage." % [a.damage, a.poise])
	for e: Dictionary in a.effects:
		var kind := str(e.get("type", ""))
		if kind == "buff" or kind == "juice_state":
			lines.append("Self effect: " + describe_status(e.get("status", {})))
		elif kind == "counter_stance":
			lines.append("Counter stance: bait a frontal hit for %s seconds." % e.get("duration", 0))
		else:
			lines.append("%s%s%s." % [kind.capitalize(), " · %s damage" % e["damage"] if e.has("damage") else "", " · %.1f m radius" % float(e["radius"]) if e.has("radius") else ""])
	return "\n".join(lines) if not lines.is_empty() else "Uses this fighter's physical moveset."

static func describe_status(d: Dictionary) -> String:
	var text := ""
	if d.has("duration"):
		text += "Duration: %s seconds\n" % d["duration"]
	var labels := {"speed": "Movement speed", "move_speed": "Attack animation speed", "dash": "Dash distance", "stamina_regen": "Stamina regeneration", "knockback_taken": "Knockback received", "heal": "Healing received", "guard_cost": "Guard stamina cost", "poise_max": "Maximum poise", "poise_regen": "Poise regeneration", "dodge_cost": "Dodge stamina cost", "heavy_poise_taken": "Heavy poise damage received", "cooldown_rate": "Cooldown recovery", "push_taken": "Push strength received"}
	for key in labels:
		if d.has(key):
			text += "%s: %s%% of normal\n" % [labels[key], snappedf(float(d[key]) * 100, 0.1)]
	if d.has("dps"):
		text += "Damage: %s HP per second\n" % d["dps"]
	if d.has("pulse_stun"):
		text += "Stun: %s s every %s s\n" % [d["pulse_stun"], d.get("pulse_interval", 1)]
	for key in ["no_hover", "no_leap", "no_blink"]:
		if bool(d.get(key, false)):
			text += {"no_hover": "Prevents hovering", "no_leap": "Prevents leaping", "no_blink": "Prevents diving / blinking"}[key] + "\n"
	for el in d.get("buildup_received", {}):
		text += "%s build-up received: %s%%\n" % [Elements.display_name(str(el)), float(d["buildup_received"][el]) * 100]
	return text.strip_edges()

static func readable(value) -> String:
	if value is Array:
		var parts := PackedStringArray()
		for item in value:
			parts.append(str(item.get("type", item.get("kind", item.get("id", "Object")))).capitalize() if item is Dictionary else str(item).capitalize())
		return ", ".join(parts) if not parts.is_empty() else "None"
	return str(value)
