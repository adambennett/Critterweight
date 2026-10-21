class_name MovesKitCase
extends TestCase
## Shared harness for the v0.9.18 per-fighter Movesets tests (test_moves_<fighter>.gd): a duel in
## Movesets with a chosen loadout against a standing opponent, helpers to use a loadout slot (tap,
## hold or sustain) and to read what that move did (its effect events, hits, zones, projectiles).

const DT := 1.0 / 120.0


## A Movesets duel: fighter 0 = `cid` with `loadout`, fighter 1 = `foe` standing `gap` metres away,
## facing each other. Nobody has an input source: the test presses buttons itself.
func duel(cid: String, loadout: Array, foe := "f_dredge", gap := 2.0, rules := {}) -> MatchSim:
	var arena := ArenaDef.from_dict({"id": "t", "base": "octagon", "radius": 7.0, "spawns": [[0, -gap * 0.5, 0], [0, gap * 0.5, 180]]})
	var r := {"rounds": 1, "round_time": 0, "intro_time": 0.2, "combat": "moves"}
	r.merge(rules, true)
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	sim.setup({"arena": arena, "rules": r, "seed": 7, "fighters": [
		{"creature": Content.creature(cid), "team": 0, "source": null, "loadout": loadout},
		{"creature": Content.creature(foe), "team": 1, "source": null}]})
	return sim


## Uses loadout slot `i` (0..3) of fighter `fi`: a press, held `hold` seconds when > 0 (charge /
## sustain), then `after` more seconds of simulation.
func use_slot(sim: MatchSim, fi: int, i: int, hold := 0.0, after := 1.0) -> void:
	var f := sim.fighters[fi]
	var b: int = Fighter.MOVE_BUTTONS[i]
	f.input.press(b)
	if hold > 0.0:
		await step_sim(sim, hold)
	else:
		await step_sim(sim, 2.0 * DT)
	f.input.set_held(b, false)
	await step_sim(sim, after)


## Events of a type caused by fighter `fi` with pool move `pool` (effect events, hits, abilities...).
func pool_events(sim: MatchSim, type: String, pool: String, fi := 0) -> Array:
	return sim.events.filter(func(e: Dictionary) -> bool:
		return str(e.get("type", "")) == type and int(e.get("fighter", -1)) == fi and str(e.get("pool", "")) == pool)


## Damage fighter `fi` dealt with pool move `pool` (hit events).
func pool_damage(sim: MatchSim, pool: String, fi := 0) -> float:
	var total := 0.0
	for e in pool_events(sim, "hit", pool, fi):
		total += float(e.get("damage", 0.0))
	return total


## Entities (projectiles, zones, props) currently alive whose effect came from `pool`.
func pool_entities(sim: MatchSim, pool: String, kind := "") -> Array:
	return sim.effects.entities.filter(func(ent: Dictionary) -> bool:
		var e: Dictionary = ent.get("e", {}) if typeof(ent.get("e", {})) == TYPE_DICTIONARY else {}
		return str(e.get("pool", "")) == pool and (kind == "" or str(ent.get("kind", "")) == kind))


## The content of a creature's pool move, checked for the basics every move must have.
func check_pool_move(cid: String, id: String) -> PoolMove:
	var c := Content.creature(cid)
	check(c != null and c.is_valid(), "%s parses: %s" % [cid, str(c.errors) if c else "missing"])
	var pm: PoolMove = c.pool.get(id) if c else null
	if not check(pm != null, "%s has the move %s" % [cid, id]):
		return null
	check(pm.display_name != "" and pm.short != "" and pm.desc.length() > 40, "%s.%s has a name, a short line and a description" % [cid, id])
	check(pm.move != null, "%s.%s performs a move" % [cid, id])
	# basic strings and heavy strikes are stamina-gated; everything else has a cooldown
	check(pm.role in ["basic", "heavy"] or pm.cooldown > 0.0, "%s.%s: a special or support move has a cooldown" % [cid, id])
	check(pm.styles.size() == 2, "%s.%s has two styles to drill" % [cid, id])
	return pm
