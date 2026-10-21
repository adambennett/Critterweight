class_name TutorialHook
extends RefCounted
## The hand-off between the UI's tutorial menu and the tutorial gameplay (owned by the lead/tutorial
## owner). The tutorial menu lists lessons and calls TutorialHook.launch(lesson_id, fighter_id).
##
## To wire tutorial gameplay, set the launcher once at startup, e.g.:
##     TutorialHook.launcher = func(lesson_id: String, fighter_id: String) -> void:
##         MyTutorial.start(lesson_id, fighter_id)
## Lesson data comes from Content kind "tutorial" ({id, name, goal, order, skippable}) when present,
## otherwise from DEFAULT_LESSONS (docs/design/ANNOUNCER_AND_TUTORIAL.md §2.1).
## v0.9.18: two courses, "moves" (Movesets: the fighter's equipped moves) and "classic"; a lesson's
## "style" names its course (none = both) and "moves_order" its place in the Movesets course. The
## launcher receives the combat style too: launcher(lesson_id, fighter_id, combat).

static var launcher: Callable

const DEFAULT_LESSONS := [
	{"id": "tut_01_footwork", "name": "Footwork", "goal": "Move around the cage; the soft lock-on keeps you facing your opponent."},
	{"id": "tut_02_hands", "name": "Hands", "goal": "Land a full three-hit Light string."},
	{"id": "tut_03_heavy", "name": "The Big One", "goal": "Land a Heavy, then a Charged Heavy."},
	{"id": "tut_04_guard", "name": "Hands Up", "goal": "Guard through a three-hit string."},
	{"id": "tut_05_dodge", "name": "Not There", "goal": "Dodge a Heavy, then land a Dash Attack."},
	{"id": "tut_06_ability", "name": "Your Trick", "goal": "Use Ability 1 and make it connect."},
	{"id": "tut_07_grab", "name": "Hands On", "goal": "Grab through a guard and throw."},
	{"id": "tut_08_parry", "name": "The Read", "goal": "Parry a Light and a Heavy.", "skippable": true},
	{"id": "tut_09_juice", "name": "Close It", "goal": "Land a Finisher, then hit the JUICE.", "skippable": true},
	{"id": "tut_10_freestyle", "name": "Freestyle", "goal": "Win a 60-second round against Kid Lamprey.", "skippable": true},
]


static func is_wired() -> bool:
	return launcher.is_valid()


## The lessons of a course ("moves" | "classic"), in course order.
static func lessons(course := "moves") -> Array:
	var ids := Content.ids("tutorial")
	if ids.is_empty():
		return DEFAULT_LESSONS.duplicate(true)
	var out := []
	for id in ids:
		var d := Content.get_entry("tutorial", str(id))
		if d.has("name") and str(d.get("style", "")) in ["", course]:
			out.append(d)
	var key := "moves_order" if course == "moves" else "order"
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get(key, a.get("order", 0))) < int(b.get(key, b.get("order", 0))))
	return out if not out.is_empty() else DEFAULT_LESSONS.duplicate(true)


## Returns false when no tutorial gameplay is wired yet (the menu explains this to the player).
static func launch(lesson_id: String, fighter_id := "", combat := "moves") -> bool:
	if not launcher.is_valid():
		Log.w("ui", "tutorial lesson '%s' requested but TutorialHook.launcher is not set" % lesson_id)
		return false
	launcher.call(lesson_id, fighter_id, combat)
	return true
