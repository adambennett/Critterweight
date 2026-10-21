extends TestCase
## CreatureFxRig springs (v0.9.17, docs/ART_PIPELINE.md §5b) on a small hand-built skeleton: one
## segment bone ("head") carrying a crest that points up and a gill that points sideways (single
## links: they point on from the head's pivot through their own heads) and a two-link chain that
## hangs down (it points to its next link). View bones carry no direction of their own, so every
## link must trail its parent's acceleration whichever way it points, rest in its modelled pose when
## nothing moves, and droop toward the ground when the body tips over. Frames are composed the way
## CreatureView.render() does it.

const DT := 1.0 / 60.0
const LINKS := ["the crest (up)", "the gill (sideways)", "chain link 0 (down)", "chain link 1 (down)"]

var _globals: Array[Transform3D] = []


## head 0; crest 1 (15 cm above the head's pivot); gill 2 (12 cm to the left); chain 3 -> 4 (its
## next link 12 cm below it)
func _skeleton() -> Skeleton3D:
	var sk := Skeleton3D.new()
	add_child(sk)
	for n in ["head", "fx_spring_crest_0", "fx_spring_gill_0", "fx_spring_chain_0", "fx_spring_chain_1"]:
		sk.add_bone(n)
	sk.set_bone_parent(1, 0)
	sk.set_bone_parent(2, 0)
	sk.set_bone_parent(3, 0)
	sk.set_bone_parent(4, 3)
	sk.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0)))
	sk.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(0, 0.15, 0)))
	sk.set_bone_rest(2, Transform3D(Basis.IDENTITY, Vector3(0.12, 0, 0)))
	sk.set_bone_rest(3, Transform3D(Basis.IDENTITY, Vector3(0, -0.1, 0.05)))
	sk.set_bone_rest(4, Transform3D(Basis.IDENTITY, Vector3(0, -0.12, 0)))
	_globals.clear()
	_globals.resize(sk.get_bone_count())
	return sk


## The bone_global callback CreatureView hands the rig: world transforms as last placed.
func _bone_global(b: int) -> Transform3D:
	return _globals[b] if b >= 0 and b < _globals.size() else Transform3D.IDENTITY


## One rendered frame: the segment bone at `seg` (a segment's world transform), the rig, then the fx
## bones parents first, rest * fx local on top of their parent.
func _frame(sk: Skeleton3D, rig: CreatureFxRig, seg: Transform3D) -> void:
	_globals[0] = seg
	rig.update(DT, _bone_global)
	for b in range(1, sk.get_bone_count()):
		_globals[b] = _globals[sk.get_bone_parent(b)] * (rig.rest[b] as Transform3D) * (rig.local[b] as Transform3D)


## The links' tips in world space, as the rig posed them or straight from the rest layout (the
## modelled pose) at the head's current transform.
func _tips(sk: Skeleton3D, rig: CreatureFxRig, posed: bool) -> Array[Vector3]:
	var g: Array[Transform3D] = []
	g.resize(sk.get_bone_count())
	g[0] = _globals[0]
	for b in range(1, sk.get_bone_count()):
		var fx: Transform3D = rig.local[b] if posed else Transform3D.IDENTITY
		g[b] = g[sk.get_bone_parent(b)] * sk.get_bone_rest(b) * fx
	var out: Array[Vector3] = [g[1] * Vector3(0, 0.1, 0), g[2] * Vector3(0.08, 0, 0), g[4].origin, g[4] * Vector3(0, -0.12, 0)]
	return out


func test_every_link_trails_a_forward_push_whichever_way_it_points() -> void:
	var sk := _skeleton()
	var rig := CreatureFxRig.new(sk, {}, 1)
	check(rig.has_bones(), "the rig finds its fx bones")
	var push := 6.0                     # m/s^2 along +Z, the fighter's forward
	for i in 120:                       # 2 s of a sustained push: the springs settle on it
		var t := i * DT
		_frame(sk, rig, Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0.5 * push * t * t)))
	var posed := _tips(sk, rig, true)
	var modelled := _tips(sk, rig, false)
	for k in posed.size():
		var d := posed[k] - modelled[k]
		check(d.z < -0.005, "%s trails behind the push (%.4f m along it)" % [LINKS[k], d.z])


func test_links_rest_in_their_modelled_pose() -> void:
	var sk := _skeleton()
	var rig := CreatureFxRig.new(sk, {}, 1)
	# standing still, turned about the vertical (a segment bone at upright rest is a pure yaw)
	var seg := Transform3D(Basis(Vector3.UP, 1.1), Vector3(2.0, 1.2, -1.0))
	for i in 60:
		_frame(sk, rig, seg)
	var posed := _tips(sk, rig, true)
	var modelled := _tips(sk, rig, false)
	for k in posed.size():
		var off := posed[k].distance_to(modelled[k])
		check(off < 1e-4, "%s stays where it was modelled (%.5f m off)" % [LINKS[k], off])


func test_a_tipped_body_lets_its_links_droop() -> void:
	var sk := _skeleton()
	var rig := CreatureFxRig.new(sk, {}, 1)
	# flat on its back and still: the head bone pitched 90 degrees, its up now pointing backward
	var seg := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.3, 0))
	for i in 120:
		_frame(sk, rig, seg)
	var posed := _tips(sk, rig, true)
	var modelled := _tips(sk, rig, false)
	for k in posed.size():
		var drop := modelled[k].y - posed[k].y
		check(drop > 0.005, "%s droops toward the ground (%.4f m below its modelled place)" % [LINKS[k], drop])
