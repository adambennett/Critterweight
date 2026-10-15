class_name Tuning
## Global combat tuning. Defaults live here; content/core/tuning.json (and balance mods) may
## override any key. Values are read through `Tuning.v("key")` so tests and mods see one source.
## Invariant: every Content reload calls reset() before applying the merged tuning.json, so values
## from a mod that has since been disabled never linger.

const DEFAULTS := {
	# input
	"input_buffer": 0.15,
	# guard / parry
	"guard_blend_time": 0.08,
	"guard_damage_mult": 0.25,
	"guard_stamina_per_damage": 0.6,
	"guard_stamina_cost_mult": 0.5,
	"guard_front_arc_deg": 80.0,
	"guard_move_mult": 0.45,
	"parry_window": 0.12,
	"parry_stun": 0.6,
	"parry_free_cancel": 0.4,
	"parry_hype": 10.0,
	"guard_break_stun": 0.9,
	# dodge
	"dodge_cooldown": 0.32,
	"dodge_stamina": 12.0,
	"dodge_evade_start": 0.05,
	"dodge_evade_end": 0.25,
	"dodge_recovery": 0.12,
	# stamina / poise
	"stamina_regen_delay": 0.55,
	"stamina_low": 20.0,
	"stamina_low_speed": 0.8,
	"poise_regen_delay": 1.5,
	"whiff_stamina_extra": 0.25,
	"hit_stamina_refund": 0.35,
	# damage model
	"min_clean": 0.3,
	"counter_mult": 1.25,
	"counter_stun_bonus": 0.12,
	"ref_mass": 80.0,
	"max_single_hit": 40.0,
	# combo protection
	"combo_window": 1.1,
	"combo_dmg_step": 0.08,
	"combo_dmg_min": 0.5,
	"combo_stun_step": 0.12,
	"combo_stun_min": 0.35,
	"stun_budget": 2.2,
	"burst_knockback": 5.0,
	"burst_invuln": 0.6,
	# knockdown
	"knockdown_min": 1.0,
	"knockdown_auto_getup": 0.8,
	"getup_time": 0.8,
	"wakeup_invuln": 0.5,
	"otg_damage_mult": 0.4,
	"otg_max_hits": 2,
	"ko_muscle": 0.0,
	"knockdown_muscle": 0.06,
	# hitstun physics
	"stagger_muscle": 0.35,
	"stagger_recover": 0.25,
	# hype / juice
	"hype_per_damage_dealt": 0.9,
	"hype_per_damage_taken": 0.5,
	"taunt_hype": 8.0,
	"taunt_cooldown": 2.0,
	"juice_duration": 6.0,
	"juice_crash": 2.0,
	"juice_crash_speed": 0.75,
	# grabs
	"grab_hold_max": 2.0,
	"grab_escape_presses": 6,
	"grab_mash_reduce": 0.12,
	"grab_whiff_recovery": 0.4,
	"throw_speed": 7.5,
	"throw_up": 3.2,
	"throw_damage": 9.0,
	"pummel_damage": 3.0,
	"pummel_max": 3,
	"slam_min_speed": 4.0,
	"slam_damage_per_ms": 2.2,
	"slam_damage_max": 16.0,
	# assistance
	"soft_lock_range": 7.0,
	"soft_lock_arc_deg": 110.0,
	"attack_snap_deg": 70.0,
	"strike_height_follow": 1.0,     # 0..1: how much strikes re-aim to the target's size (CMB-09)
	"target_sticky": 1.0,
	# debug toggles for rig tuning
	"dbg_ff": 1.0,
	"dbg_gain": 1.0,
	"dbg_reaction": 1.0,
}

static var values := DEFAULTS.duplicate()


static func v(key: String) -> float:
	return float(values.get(key, 0.0))


## Back to the built-in defaults (Content.reload() calls this before applying tuning.json).
static func reset() -> void:
	values = DEFAULTS.duplicate()


## Applies tuning.json overrides. Returns one problem per rejected key: "unknown key 'k'" or
## "'k' must be a finite number" (those keys keep their current value).
static func apply_overrides(d: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	for k in d:
		if not values.has(k):
			problems.append("unknown key '%s'" % str(k))
			continue
		var x = d[k]
		if (typeof(x) != TYPE_FLOAT and typeof(x) != TYPE_INT) or not is_finite(float(x)):
			problems.append("'%s' must be a finite number" % str(k))
			continue
		values[k] = float(x)
	return problems
