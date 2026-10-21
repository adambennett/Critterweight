class_name CareerDefaults
extends RefCounted
## Code defaults for the persistent Career (CMP-08): the Cage Rules career (js/career.js) with every
## formula and constant kept, translated to Critterweight (no grappling: BJJ and wrestling became
## Clinch and Defence; original promotion, ring-name and home-town lists; 10-point bouts).
## The shipped data lives under the top-level key "career" of
## content/core/ladder/campaign_rules.json (design contract D1) and carries the same values; this
## class only guarantees a playable career when that block is missing or partial. rules() deep-
## merges the catalog's block over these defaults key by key (CampaignCatalog._merge_rules):
## nested objects merge, ARRAYS (orgs, facilities, name lists, bot_tiers...) are replaced whole.
## Invariants: STATS order is the display and save order; orgs are listed from the lowest tier up
## and "belt_org" names the promotion that holds the only title (Cage Rules: the last org).

const STATS := ["stamina", "chin", "speed", "power", "clinch", "defence"]
const REGIONS := ["head", "body", "legs"]
const FACILITY_EXTRA := ["recovery", "coach"]


## The career rules for a catalog: content block over the code defaults.
static func for_catalog(catalog: CampaignCatalog) -> Dictionary:
	var r := rules()
	if catalog != null:
		var block = catalog.rules.get("career", {})
		if typeof(block) == TYPE_DICTIONARY:
			CampaignCatalog._merge_rules(r, block)
	return r


static func rules() -> Dictionary:
	return {
		"start": {"money": 2000, "pop": 2.0, "week": 1},
		"name_max": 14,
		"nick_max": 16,
		"stat_cap": 0.99,
		"stat_info": {
			"stamina": {"label": "Stamina", "short": "STAM", "desc": "Cardio: a bigger tank and faster stamina recovery late in a fight."},
			"chin": {"label": "Chin", "short": "CHIN", "desc": "How much it takes to put you down: more poise before a knockdown, and a quicker get-up."},
			"speed": {"label": "Speed", "short": "SPD", "desc": "Footwork and dashes, and how fast your strikes come out."},
			"power": {"label": "Power", "short": "POW", "desc": "Damage and knockdown force behind every strike."},
			"clinch": {"label": "Clinch", "short": "CLN", "desc": "The grab game: longer holds that are harder to escape, bigger throws and slams, and quicker escapes when they grab you."},
			"defence": {"label": "Defence", "short": "DEF", "desc": "Guard, parries and dodges: less chip through the guard, a wider parry window, cheaper and safer dodges."},
		},
		# starting stats per fighter: round(base + shape * scale, 2) (Cage Rules startingStats: ~0.33-0.49)
		"start_from_shape": {"base": 0.16, "scale": 0.36},
		# each playable fighter's stat shape (Cage Rules ROSTER stats: mean ~0.66). Shapes the
		# player's starting stats and every generated opponent of that fighter.
		"fighters": {
			"f_stoke": {"stamina": 0.70, "chin": 0.66, "speed": 0.66, "power": 0.74, "clinch": 0.62, "defence": 0.62},
			"f_dredge": {"stamina": 0.60, "chin": 0.90, "speed": 0.44, "power": 0.62, "clinch": 0.82, "defence": 0.72},
			"f_gusto": {"stamina": 0.82, "chin": 0.42, "speed": 0.92, "power": 0.56, "clinch": 0.50, "defence": 0.74},
			"f_dozer": {"stamina": 0.60, "chin": 0.84, "speed": 0.48, "power": 0.92, "clinch": 0.74, "defence": 0.50},
			"f_slurry": {"stamina": 0.76, "chin": 0.62, "speed": 0.60, "power": 0.56, "clinch": 0.82, "defence": 0.66},
			"f_jitters": {"stamina": 0.68, "chin": 0.44, "speed": 0.90, "power": 0.54, "clinch": 0.62, "defence": 0.82},
			"f_varga": {"stamina": 0.62, "chin": 0.70, "speed": 0.80, "power": 0.90, "clinch": 0.48, "defence": 0.50},
			"f_knell": {"stamina": 0.72, "chin": 0.74, "speed": 0.56, "power": 0.70, "clinch": 0.58, "defence": 0.70},
		},
		"default_shape": 0.66,
		# Cage Rules trainGain: base x (1 + room x lvl) x (1 + coach x lvl) x ((1 - s)^exp + floor) x
		# max(injury_floor, 1 - injury_total / injury_div)
		"training": {"base": 0.026, "room_per_level": 0.3, "coach_per_level": 0.12, "dimin_exp": 1.2,
			"dimin_floor": 0.1, "injury_div": 260.0, "injury_floor": 0.35},
		# Cage Rules healWeek: (base + recovery x lvl) x (rest ? rest_mult : 1) off every region
		"healing": {"base": 10.0, "recovery_per_level": 4.0, "rest_mult": 2.5},
		# v0.9.18 Movesets: "Learn a move" offers at most this many unlearned pool moves a week
		# (CareerMoves.learn_options); learning and drilling each take a training week
		"moves": {"learn_choices": 3},
		"idle_week_pop": 0.6,
		"withdraw_pop": 4.0,
		"facility_max": 5,
		"facility_cost": [1500, 4000, 10000, 25000, 60000],
		"coach_cost": [6000, 25000, 90000, 250000, 600000],
		"facilities": [
			{"id": "stamina", "name": "Cardio Loft", "stat": "stamina", "desc": "Rusty bikes, skipping ropes and nine flights of stairs. Stamina training."},
			{"id": "chin", "name": "Iron Pit", "stat": "chin", "desc": "Neck harness, a sled and a pile of scrap plates. Chin training."},
			{"id": "speed", "name": "Speed Bag Corner", "stat": "speed", "desc": "Speed bags, mitts and a footwork ladder painted on the floor. Speed training."},
			{"id": "power", "name": "Heavy Bag Row", "stat": "power", "desc": "Heavy bags, pads and a tractor tyre. Power training."},
			{"id": "clinch", "name": "Clinch Pit", "stat": "clinch", "desc": "A padded wall, a grappling dummy and a throwing mat. Clinch training."},
			{"id": "defence", "name": "Sparring Ring", "stat": "defence", "desc": "Head guards, pad drills and a partner who swings back. Defence training."},
			{"id": "recovery", "name": "Recovery Tank", "stat": "", "desc": "Ice baths, a physio table and a sleep pod. Injuries heal faster every week."},
			{"id": "coach", "name": "Head Coach", "stat": "", "desc": "A sharper corner makes every training week count for more."},
		],
		"tiers": ["Regional", "National", "Major", "The Big League"],
		"tier_pop_cap": [42, 66, 88, 100],
		"tier_pop_mult": [1.0, 1.4, 1.8, 2.4],
		"title_pop": 92.0,
		"belt_org": "grand_circuit",
		"belt_name": "Grand Circuit Champion",
		# Cage Rules ORGS numbers, original Critterweight names (no real promotions)
		"orgs": [
			{"id": "gutter_league", "name": "Gutter League Brawls", "tier": 0, "pop": 0, "purse": [500, 1100], "level": [0.25, 0.40]},
			{"id": "bait_shop", "name": "Bait Shop Bash", "tier": 0, "pop": 0, "purse": [400, 900], "level": [0.20, 0.38]},
			{"id": "rust_bucket", "name": "Rust Bucket Fight Series", "tier": 0, "pop": 6, "purse": [700, 1600], "level": [0.30, 0.45]},
			{"id": "iron_lung", "name": "Iron Lung Circuit", "tier": 1, "pop": 24, "purse": [3000, 7000], "level": [0.42, 0.58]},
			{"id": "tidewater", "name": "Tidewater Fight League", "tier": 1, "pop": 28, "purse": [3500, 8500], "level": [0.45, 0.60]},
			{"id": "scrapyard", "name": "Scrapyard Nation", "tier": 1, "pop": 34, "purse": [5000, 12000], "level": [0.50, 0.65]},
			{"id": "smokestack", "name": "Smokestack Fighting Championship", "tier": 2, "pop": 50, "purse": [15000, 40000], "level": [0.58, 0.74]},
			{"id": "gold_gill", "name": "Gold Gill Grand Prix", "tier": 2, "pop": 56, "purse": [20000, 55000], "level": [0.62, 0.78]},
			{"id": "grand_circuit", "name": "The Grand Circuit", "tier": 3, "pop": 74, "purse": [60000, 220000], "level": [0.72, 0.92]},
		],
		"offers": {"min": 2, "extra_chance": 0.6, "weeks_min": 4, "weeks_max": 10, "title_weeks": 10,
			"short_notice_per_week": 0.03, "title_purse_mult": 2.5, "bonus_frac": 0.6, "top_bonus_frac": 1.0,
			"purse_round": 50, "pop_in_div": 30.0, "pop_in_weight": 0.7, "top_tier_weight": 1.5,
			"pop_weight_div": 40.0, "reuse_weight": 0.15, "short_notice_weeks": 5, "long_camp_weeks": 9},
		"rounds": 3,
		"title_rounds": 5,
		"round_time": 99.0,
		"rules_preset": "cage_rules",
		# campaign arena keys (campaign_rules.arenas) career bouts are booked in; titles at title_arena
		"arenas": ["gullet_day", "gullet_night", "drydock", "crusher", "rooftop"],
		"title_arena": "gullet_title",
		# Cage Rules makeOpponent: level from the org band (titles 0.90-0.96), stat = clamp(level +
		# (shape - center) x scale +- noise/2, min, max); record fights round(base + per_level x lvl +
		# rand x r), win share clamp(win_base + win_per_level x lvl +- win_noise/2, win_min, win_max)
		"opponents": {"title_level": [0.90, 0.96], "shape_center": 0.66, "shape_scale": 0.55, "noise": 0.08,
			"stat_min": 0.15, "stat_max": 0.99, "fights_base": 2.0, "fights_per_level": 24.0, "fights_rand": 6.0,
			"win_base": 0.45, "win_per_level": 0.45, "win_noise": 0.2, "win_min": 0.3, "win_max": 0.95,
			"nick_chance": 0.7},
		# design contract D5: the opponent's level picks the bot tier (first "below" it is under)
		"bot_tiers": [{"below": 0.33, "tier": "punching_bag"}, {"below": 0.48, "tier": "journeyman"},
			{"below": 0.63, "tier": "contender"}, {"below": 9.0, "tier": "headliner"}],
		"bot_tier_order": ["punching_bag", "journeyman", "contender", "headliner", "hall_of_famer"],
		"difficulties": {
			"easy": {"name": "Easy", "order": 0, "shift": -1, "max_tier": "headliner", "desc": "Opponents' corners send in one bot tier lower."},
			"normal": {"name": "Normal", "order": 1, "shift": 0, "max_tier": "headliner", "desc": "Bot tiers follow the opponent's level, up to Headliner."},
			"hard": {"name": "Hard", "order": 2, "shift": 1, "max_tier": "hall_of_famer", "desc": "One bot tier higher; title fights can bring a Hall-of-Famer."},
		},
		"difficulty_default": "normal",
		# Cage Rules applyResult popularity
		"popularity": {"win": 4.0, "finish": 3.0, "finish_per_round_left": 2.5, "split_mult": 0.75,
			"title_win": 6.0, "streak_min": 2, "streak_bonus": 1.5, "draw": 0.5, "loss": 3.0, "loss_per_mult": 1.5,
			"r1_finish_loss": 2.0, "title_loss": 3.0, "action_bonus": 1.5,
			# fight-of-the-night pace = combined clean strikes landed per round. Cage Rules uses 45 for
			# its 180 s rounds; 44 is the 85th percentile measured in same-tier 10-point bot duels with
			# 99 s rounds (DECISIONS D-045, design contract D6).
			"action_landed_per_round": 44.0},
		"pop_labels": [{"min": 92, "label": "Superstar"}, {"min": 74, "label": "Household name"},
			{"min": 50, "label": "Rising contender"}, {"min": 24, "label": "Regional champion material"},
			{"min": 8, "label": "Local draw"}, {"min": 0, "label": "Unknown"}],
		"pop_marks": [24, 50, 74, 92],
		# standing in the top tier: contender #worst at pop "from", #1 at pop "to"
		"contender": {"from": 74.0, "to": 92.0, "worst": 15},
		# design contract D7 / Cage Rules danger tags: opponent rating - your rating
		"danger": [{"max": -8, "tag": "FAVOURED"}, {"max": 6, "tag": "EVEN"}, {"max": 16, "tag": "UNDERDOG"}],
		"danger_else": "LONG SHOT",
		# design contract D2 "injuries in": `carry` of each region's injury becomes a fight-start
		# handicap (HP is unlimited under 10-point scoring).
		"injury_in": {"carry": 0.5, "head_poise_per_point": 0.3, "head_poise_max": 15.0,
			"body_regen_div": 160.0, "legs_speed_div": 200.0, "min_mult": 0.7},
		# injuries out of a fight (Cage Rules: 55% of the damage taken per region, +10 head on a
		# finish loss). From the judges' tally: damage taken by part as % of max HP x per_hp_pct,
		# + per_knockdown head per knockdown suffered, + stoppage_loss_head when stopped.
		# Calibrated on 52 same-tier 10-point bot duels (DECISIONS D-045): about 28 total after a
		# decision win, 46 after a decision loss, 53 after a stoppage loss, 13 after a stoppage win,
		# which keeps Cage Rules' scale (a hard fight costs a few weeks of healing).
		"injury_out": {"per_hp_pct": 0.07, "per_knockdown": 2.0, "stoppage_loss_head": 10.0,
			"region_cap": 100.0, "fallback_split": {"head": 0.4, "body": 0.4, "legs": 0.2}},
		"condition": {"injured": 40.0, "sore": 10.0, "hurt_total": 30.0},
		# design contract D2: fixed stat -> Fighter mod mapping (CareerBuild.MAP), these are the
		# per-unit coefficients of (stat - 0.5): mul keys become 1 + c x (s - 0.5), add keys
		# c x (s - 0.5). Negative c means the stat LOWERS that mod.
		"build": {
			"stamina": {"stamina_add": 40.0, "stamina_regen": 0.5},
			"chin": {"poise_add": 40.0, "getup_speed": 0.3},
			"speed": {"speed": 0.16, "move_speed": 0.12},
			"power": {"damage": 0.4, "moves.*.poise": 0.4},
			"clinch": {"grab_hold_add": 0.6, "grab_escape_add": 4.0, "throw_distance": 0.3, "splat_damage_add": 4.0, "held_time_mult": -0.3},
			"defence": {"guard_absorb_mult": -0.5, "parry_window_add": 0.05, "dodge_iframes_add": 0.06, "dodge_cost": -0.4},
		},
		"news_cap": 60,
		"names": {
			"first": ["Bolt", "Mudge", "Gristle", "Pip", "Rook", "Barnaby", "Cinder", "Dabble", "Fennick", "Gully",
				"Hobb", "Ivo", "Jolt", "Kettle", "Lugnut", "Mossy", "Nib", "Oakum", "Pudge", "Quill",
				"Rivet", "Sprocket", "Tansy", "Umber", "Vex", "Wick", "Yarrow", "Zinc", "Bramble", "Clem",
				"Dross", "Ember", "Flint", "Grub", "Hask", "Juno", "Knox", "Lark", "Mags", "Nettle"],
			"last": ["Barnacle", "Bilgewater", "Boltwick", "Cinderby", "Cogsworth", "Drainwell", "Dredgely", "Fathomly",
				"Flotsam", "Gravelgut", "Grimewood", "Hinchcliff", "Hopsworth", "Kettleby", "Krillick", "Mudlark",
				"Oilcan", "Pebbleton", "Puddlesby", "Rustwhistle", "Saltmarsh", "Scuttleby", "Siltmore", "Slagford",
				"Sludgeworth", "Sprocketti", "Tarbuckle", "Tidewell", "Tinplate", "Wrenchley", "Bogsworth", "Clamshaw",
				"Ducton", "Eelbridge", "Ferrow", "Gasketti", "Hullabee", "Mosswick", "Nettlefold", "Wadsworth"],
			"nicks": ["The Boiler", "Rust Bucket", "Low Tide", "The Gasket", "Fizz", "Short Fuse", "The Sump Pump",
				"Two Buckets", "Scrap Heap", "The Drain", "Loose Bolt", "The Kettle", "Slick", "Puddle Jumper",
				"The Undertow", "Hot Pipe", "The Crowbar", "Wet Paint", "Static Cling", "Mudslide", "The Landfill",
				"Lid Flipper", "The Plunger", "Spare Parts", "Old Rope", "The Grease Trap", "Night Shift", "Tin Can",
				"Bottom Feeder", "The Bilge Pump"],
			"towns": ["Gullet Docks", "Canal Street", "Lower Sump", "Rivet Row", "Tin Town", "Brine Flats", "Cinder Yard",
				"Old Cannery", "Gravel Pits", "Sludge Bay", "Rooftop Nine", "Pier Seven", "Slag Hill", "Kelp Hollow",
				"Crusher Yard", "Static Heights", "Drain Point", "Mudlark Lane", "Scrapton", "Boiler End",
				"Fathom Reach", "Tidewell", "Rust Hollow", "Saltmarsh"],
		},
	}
