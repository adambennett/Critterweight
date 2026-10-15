extends HubTestCase
## The Cannery's cosmetics actually show (docs/HUB_SYSTEMS.md §16), view-only:
##   * gold tooth / trash-can lid / replica belt / rooftop scarf attach to every roster body and the
##     dev biped, on the right part, fitted to the forged model (on the skin, rings hugging it, the
##     mouth left clear), follow the body, carry no collision; the gold tooth is the gag piece;
##     walkout pieces are put away while the round is live
##   * only the profile owner's fighter wears them in a real (headless) MatchScene; Sizzle recolours
##     Stoke's JUICE and glow, nobody else's
##   * the equipped profile frame wraps the owner's name card in the fight HUD, results and profile
##   * the locker only offers slots that show; fished cans sit on the locker-room shelf
## User data is redirected to a temporary root.

const ROSTER := ["f_stoke", "f_gusto", "f_dredge", "f_dozer", "f_slurry", "f_jitters", "dev_biped"]
const WEAR := {"piece": "hub_gold_tooth", "idle_prop": "hub_trash_lid", "back": "hub_replica_belt", "neck": "hub_rooftop_scarf",
	"frame": "hub_frame_sign_fixer", "juice": "hub_juice_sizzle"}

var _root := ""
var _profile := {}


func before_each() -> void:
	App.clear_screens()
	_root = Paths.root
	Paths.root = temp_dir("hub_cos_%d" % Time.get_ticks_usec())
	_profile = Profiles.current
	Profiles.current = Profiles.default_profile("hub_cos", "Cosmo")
	CampaignProgression.ensure_fields(Profiles.current)


func after_each() -> void:
	App.clear_screens()
	if App.current_scene != null:
		App.set_scene(null)
	Paths.root = _root
	Profiles.current = _profile


## The active profile wearing everything in WEAR.
func _dress_profile() -> HubState:
	var st := HubState.new(Profiles.current)
	for slot in WEAR:
		st.unlock_cosmetic(str(WEAR[slot]))
		st.equip(str(slot), str(WEAR[slot]))
	return st


func _items() -> Array:
	var out := []
	for slot in ["piece", "idle_prop", "back", "neck"]:
		var att: Dictionary = HubContent.cosmetic(str(WEAR[slot])).get("attach", {})
		var e := att.duplicate()
		e["id"] = str(WEAR[slot])
		out.append(e)
	return out


## Rest-pose world transforms of a body (fighter at `xf`).
func _rest(c: CreatureDef, xf := Transform3D.IDENTITY) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for s: BodyDef.Seg in c.body.segments:
		out.append(xf * Transform3D(Basis.IDENTITY, s.pivot))
	return out


func _view(cid: String) -> CreatureView:
	var holder := fresh_world()
	var v := CreatureView.new()
	holder.add_child(v)
	v.setup(Content.creature(cid))
	return v


## What the attachment is fitted to, in segment `si`'s rest frame: the forged model's vertices (or
## the body shapes) of the segment and its neighbours (rest pose: frames differ by pivots only).
func _surface(c: CreatureDef, v: CreatureView, si: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var s: BodyDef.Seg = c.body.segments[si]
	var near: Array[int] = [si]
	if s.parent >= 0:
		near.append(s.parent)
	for ch in s.children:
		near.append(ch)
	for k in near:
		var o: BodyDef.Seg = c.body.segments[k]
		for p in CosmeticAttachments._pts(o, v._vis_points):
			out.append(p + o.pivot - s.pivot)
	return out


func _nearest(pts: PackedVector3Array, q: Vector3) -> float:
	var best := INF
	for p in pts:
		best = minf(best, p.distance_to(q))
	return best


## 24 points round a ring anchor, in the anchor segment's frame.
func _ring_points(anc: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	var xf: Transform3D = anc["xf"]
	var r: Vector2 = anc["radii"]
	for k in 24:
		var a := TAU * float(k) / 24.0
		out.append(xf * Vector3(r.x * sin(a), 0, r.y * cos(a)))
	return out


func _has_physics(n: Node) -> bool:
	if n is CollisionObject3D or n is CollisionShape3D:
		return true
	for ch in n.get_children():
		if _has_physics(ch):
			return true
	return false


func test_attachments_fit_every_body_and_follow_it() -> void:
	for cid in ROSTER:
		var c := Content.creature(str(cid))
		if c == null:
			continue
		var v := _view(str(cid))
		# reading a model back is not free: an undressed fighter (every bot, every minion) never does
		check(v._vis_points.is_empty(), "%s: no model read-back for a view without cosmetics" % cid)
		v.set_cosmetics(_items())
		if str(c.art.get("model", "")) != "":
			# the anchors are fitted to the model the player sees, not to the (smaller) collision shapes
			var with_pts := 0
			for s0: BodyDef.Seg in c.body.segments:
				if (v._vis_points.get(s0.index, PackedVector3Array()) as PackedVector3Array).size() > 20:
					with_pts += 1
			check(with_pts * 2 >= c.body.segments.size(), "%s: the forged model's vertices are collected per segment (%d of %d)" % [cid, with_pts, c.body.segments.size()])
		var rest := _rest(c)
		v.snap_transforms(rest)
		v.render(1.0)
		var by_kind := {}
		for a in v.cosmetics():
			by_kind[str(a["kind"])] = a
		for kind in CosmeticAttachments.KINDS:
			if not check(by_kind.has(kind), "%s wears the %s" % [cid, kind]):
				continue
			var node: Node3D = by_kind[kind]["node"]
			check(not _has_physics(node), "%s: the %s has no collision (view-only)" % [cid, kind])
			check(node.visible, "%s: the %s shows in the hub" % [cid, kind])
		if by_kind.size() < 4:
			continue
		var head := CosmeticAttachments._head(c.body)
		var core := CosmeticAttachments._upper_core(c.body)
		var tooth: Vector3 = (by_kind["tooth"]["node"] as Node3D).global_position
		var lid: Vector3 = (by_kind["lid"]["node"] as Node3D).global_position
		var belt: Vector3 = (by_kind["belt"]["node"] as Node3D).global_position
		var scarf: Vector3 = (by_kind["scarf"]["node"] as Node3D).global_position
		var face := head if head != null else core
		check(tooth.z > face.pivot.z - 0.02 and absf(tooth.y - face.pivot.y) < 0.7, "%s: the tooth sits at the front of the head (%s, head pivot %s)" % [cid, str(tooth), str(face.pivot)])
		if CosmeticAttachments._left_arm(c.body) != null:
			check(lid.x > 0.12, "%s: the lid is strapped to the left arm/wing (%s)" % [cid, str(lid)])
		elif c.body.gait in ["quadruped", "crab"]:
			check(lid.y > core.pivot.y, "%s: armless and horizontal: the lid rides on top (%s)" % [cid, str(lid)])
		else:
			check(lid.z < core.pivot.z, "%s: armless and upright: the lid is slung on the back (%s)" % [cid, str(lid)])
		check(belt.distance_to(core.pivot) < 0.9, "%s: the belt goes round the torso (%s vs %s)" % [cid, str(belt), str(core.pivot)])
		var neck := head.pivot if head != null else core.pivot + Vector3(0, 0.3, 0)
		check(scarf.distance_to(neck) < 0.55, "%s: the scarf sits at the neck (%s vs %s)" % [cid, str(scarf), str(neck)])
		# fitted to the visible body (the forged model's vertices): on the skin, rings hugging it, and
		# nothing over the mouth
		var anc := {}
		for kind1 in CosmeticAttachments.KINDS:
			anc[kind1] = CosmeticAttachments.anchor(c, str(kind1), v._vis_points)
		var tooth_a: Dictionary = anc["tooth"]
		var tooth_off := _nearest(_surface(c, v, int(tooth_a["seg"])), (tooth_a["xf"] as Transform3D).origin)
		check(tooth_off < 0.05, "%s: the tooth sits on the face (%.3f m off the skin)" % [cid, tooth_off])
		var lid_a: Dictionary = anc["lid"]
		var lid_off := _nearest(_surface(c, v, int(lid_a["seg"])), (lid_a["xf"] as Transform3D).origin)
		check(lid_off < 0.1, "%s: the lid is strapped on, not floating (%.3f m off the skin)" % [cid, lid_off])
		var tooth_w := (c.body.segments[int(tooth_a["seg"])] as BodyDef.Seg).pivot + (tooth_a["xf"] as Transform3D).origin
		for ring_kind in ["belt", "scarf"]:
			var ra: Dictionary = anc[ring_kind]
			var surf := _surface(c, v, int(ra["seg"]))
			var worst := 0.0
			var to_mouth := INF
			var pivot := (c.body.segments[int(ra["seg"])] as BodyDef.Seg).pivot
			for q in _ring_points(ra):
				worst = maxf(worst, _nearest(surf, q))
				to_mouth = minf(to_mouth, (pivot + q).distance_to(tooth_w))
			check(worst < (0.2 if ring_kind == "belt" else 0.12), "%s: the %s hugs the body (at most %.3f m off the skin)" % [cid, ring_kind, worst])
			check(to_mouth > (0.15 if ring_kind == "belt" else 0.07), "%s: the %s keeps clear of the mouth (%.3f m)" % [cid, ring_kind, to_mouth])
		# the pieces ride the body: move and turn the fighter, they come along
		var moved := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(5, 0, 3))
		v.snap_transforms(_rest(c, moved))
		v.render(1.0)
		for kind2 in by_kind:
			var a: Dictionary = by_kind[kind2]
			var want: Vector3 = (moved * Transform3D(Basis.IDENTITY, (c.body.segments[int(a["seg"])] as BodyDef.Seg).pivot) * (a["local"] as Transform3D)).origin
			check((a["node"] as Node3D).global_position.distance_to(want) < 0.001, "%s: the %s follows its segment" % [cid, kind2])
		# while the round is live the walkout pieces are put away
		v.cosmetic_combat = true
		v.render(1.0)
		check(not (by_kind["lid"]["node"] as Node3D).visible and not (by_kind["belt"]["node"] as Node3D).visible, "%s: lid and belt put away mid-round" % cid)
		check((by_kind["tooth"]["node"] as Node3D).visible and (by_kind["scarf"]["node"] as Node3D).visible, "%s: tooth and scarf stay on" % cid)
		v.get_parent().queue_free()
	await wait_frames(1)


func test_the_gold_tooth_is_the_gag_piece() -> void:
	var v := _view("f_stoke")
	v.set_cosmetics([{"kind": "tooth", "color": "#E8B923", "id": "hub_gold_tooth"}])
	v.snap_transforms(_rest(v.creature))
	v.render(1.0)
	var tooth: Node3D = v.cosmetics()[0]["node"]
	var piece := v.detach_piece(Vector3.FORWARD)
	check(piece != null and piece.name == "GoldTooth", "the end-of-fight gag piece is the gold tooth")
	check(not tooth.visible, "it left the mouth")
	if piece != null:
		check(piece.find_children("*", "MeshInstance3D", true, false).size() > 0, "and looks like it")
		check(piece.collision_layer == Rig.LAYER_DEBRIS, "debris only: the simulation never sees it")
	v.clear_bruises()
	v.render(1.0)
	check(tooth.visible, "next round it is back")
	await wait_frames(1)


func test_only_the_profile_owner_is_dressed_in_a_match() -> void:
	_dress_profile()
	var cfg := App.resolve_match_config({"arena": "the_gullet", "rules": {"rounds": 1, "round_time": 30}, "seed": 9,
		"fighters": [{"creature": "f_stoke", "team": 0, "kind": "player", "name": "Cosmo"},
			{"creature": "f_dredge", "team": 1, "kind": "bot", "difficulty": "rookie"}]})
	var scene := MatchScene.new()
	add_child(scene)
	scene.start(cfg)
	await wait_frames(3)
	var me: CreatureView = scene.views[0]
	var bot: CreatureView = scene.views[1]
	check_eq(me.cosmetics().size(), 4, "the owner wears tooth, lid, belt and scarf")
	check(bot.cosmetics().is_empty(), "the bot wears nothing of yours")
	check(scene.sim.mode.phase == MatchMode.Phase.INTRO, "on the walkout")
	var lid: Node3D = me.cosmetics().filter(func(a): return str(a["kind"]) == "lid")[0]["node"]
	check(lid.visible, "the lid is out on the walkout")
	# Sizzle: Stoke's JUICE and furnace go white-hot
	var sizzle := Color.from_string(str(HubContent.cosmetic("hub_juice_sizzle")["juice"]["juice_color"]), Color.WHITE)
	check(me.juice_color.is_equal_approx(Color(sizzle.r, sizzle.g, sizzle.b, 1.0)), "Stoke's JUICE colour is Sizzle (%s)" % str(me.juice_color))
	check(me.glow_color.a > 0.5, "his glowing parts shift white-hot")
	check(bot.juice_color.is_equal_approx(CreatureView.DEFAULT_JUICE), "the bot keeps the stock JUICE colour")
	# the owner's name card wears the Sign Fixer frame
	var frames := scene.hud.find_children(ProfileFrame.NODE_NAME, "PanelContainer", true, false)
	check_eq(frames.size(), 1, "one framed name card in the HUD (yours)")
	if frames.size() == 1:
		check_eq(str((frames[0] as Node).get_meta("frame_id", "")), "hub_frame_sign_fixer", "the Sign Fixer frame")
	# once the round is live the walkout pieces are put away
	await wait_physics(int((MatchMode.INTRO_TIME + 0.6) * Engine.physics_ticks_per_second))
	await wait_frames(2)
	check(scene.sim.mode.phase == MatchMode.Phase.FIGHT, "the round is live")
	check(not lid.visible, "the lid is put away while fighting")
	scene.queue_free()
	await wait_frames(2)


func test_sizzle_is_stoke_only_and_frames_show_on_results_and_profile() -> void:
	_dress_profile()
	check(not FighterCosmetics.juice_style(Profiles.current, "f_stoke").is_empty(), "Sizzle applies to Stoke")
	check(FighterCosmetics.juice_style(Profiles.current, "f_dredge").is_empty(), "and to nobody else")
	var fighters := [{"index": 0, "team": 0, "creature": "f_stoke", "name": "Cosmo", "health": 50.0, "out": false, "kind": "player",
		"stats": {"damage_dealt": 30.0, "damage_taken": 20.0, "hits": 5, "blocks": 1, "parries": 0, "knockdowns": 0, "kos": 1}},
		{"index": 1, "team": 1, "creature": "f_dredge", "name": "Bot", "health": 0.0, "out": true, "kind": "bot",
		"stats": {"damage_dealt": 20.0, "damage_taken": 30.0, "hits": 3, "blocks": 0, "parries": 0, "knockdowns": 0, "kos": 0}}]
	App.push("results", {"result": {"winner_team": 0, "round_wins": {0: 1}, "rounds": 1, "time": 60.0, "fighters": fighters},
		"config": {"fighters": [{"kind": "player", "team": 0}], "ui": {"mode": "quick"}}})
	await wait_frames(4)
	var fr := App.top_screen().find_children(ProfileFrame.NODE_NAME, "PanelContainer", true, false)
	check_eq(fr.size(), 1, "the results table frames your row only")
	App.clear_screens()
	App.push("profile", {})
	await wait_frames(4)
	check_eq(App.top_screen().find_children(ProfileFrame.NODE_NAME, "PanelContainer", true, false).size(), 1, "the profile card is framed")
	App.clear_screens()
	# no frame equipped: plain cards everywhere
	HubState.new(Profiles.current).equip("frame", "")
	App.push("profile", {})
	await wait_frames(4)
	check(App.top_screen().find_children(ProfileFrame.NODE_NAME, "PanelContainer", true, false).is_empty(), "no frame, no plate")
	App.clear_screens()
	await wait_frames(2)


func test_the_locker_only_offers_what_shows() -> void:
	for s in HubBoardSpar.SLOTS:
		var slot := str(s[0])
		check(slot != "can", "supplement cans are a shelf collection, not an equippable slot")
		for id in HubContent.cosmetics_in_slot(slot):
			var d := HubContent.cosmetic(str(id))
			var shows := d.has("attach") or d.has("frame") or d.has("juice") or slot == "pet"
			check(shows, "%s (%s) has something to show" % [id, slot])
	# every equippable wearable attaches somewhere on every body
	for id2 in ["hub_gold_tooth", "hub_trash_lid", "hub_replica_belt", "hub_rooftop_scarf"]:
		var kind := str((HubContent.cosmetic(id2)["attach"] as Dictionary)["kind"])
		for cid in ROSTER:
			var c := Content.creature(str(cid))
			if c != null:
				check(not CosmeticAttachments.anchor(c, kind).is_empty(), "%s has a place on %s" % [id2, cid])


func test_fished_cans_sit_on_the_locker_shelf() -> void:
	make_hub("f_stoke")
	state.unlock_cosmetic("hub_fish_tonic")
	var view := HubView.new()
	add_child(view)
	view.build(mode, state)
	check(view.props.catch_nodes.size() == HubSecrets.FISH_POOL.size(), "a place for every can")
	check((view.props.catch_nodes["hub_fish_tonic"] as Node3D).visible, "the tonic you caught is on the shelf")
	check(not (view.props.catch_nodes["hub_fish_jerky"] as Node3D).visible, "the jerky you didn't, isn't")
	state.unlock_cosmetic("hub_fish_jerky")
	view.props.refresh_world()
	check((view.props.catch_nodes["hub_fish_jerky"] as Node3D).visible, "a new catch joins it")
	view.queue_free()
	await wait_frames(1)
