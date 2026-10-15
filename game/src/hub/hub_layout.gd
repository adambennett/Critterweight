class_name HubLayout
extends RefCounted
## THE CANNERY as data (docs/design/HUB.md §1, docs/HUB_SYSTEMS.md §2): spaces, walls with door
## openings, solid blocks, ramps (real stairs), fighter-only blockers, nav points, transitions and
## the fixed spots of NPCs, stations and secrets. HubWorld builds physics from it, HubView builds
## visuals from it, HubMode/HubNav/tests read it. Nothing here touches nodes.
##
## Frame: metres, +X east, -Z north (the harbor side), +Y up. Everything sits at y >= 0 so the
## match simulation's ring-out check (root below -2.5 m) can never fire. The basement (Boiler Room),
## the secret Roof, the Pier under the dock and the crawlspace's far end are reached through
## hatches/ladders/the elevator with a short fade; the Boiler Room, Roof and Pier live in their own
## regions of the same physics world (x >= 20) and are dressed as below-ground / up-top places.

const WALL_T := 0.3
const DOOR_H := 2.4

## id -> {name, rect: Rect2 (x, z, width, depth), floor, height, room (Audio.set_room id), area,
##        exterior, secret, cam: [pitch_deg, distance, yaw_deg = 0 (camera south of you)], arrive: [Vector3, yaw_deg], landmark}
## (The Locker Room and the Office look south, at the lockers and at Snappington, who face their
## doors; the Loading Dock looks west along the quay. HubCamera keeps your walking heading while it
## turns, until you let go of the stick.)
const SPACES := {
	"main_floor": {"name": "Main Floor", "rect": Rect2(-12, -8, 24, 16), "floor": 0.0, "height": 7.0, "room": "main", "area": "cannery",
		"cam": [54.0, 10.5], "arrive": [Vector3(-4.0, 0, -0.5), 180.0], "landmark": "the heavy bags"},
	"juice_bar": {"name": "The Juice Bar", "rect": Rect2(-22, -8, 10, 8), "floor": 0.0, "height": 4.0, "room": "juice_bar", "area": "cannery",
		"cam": [58.0, 8.5], "arrive": [Vector3(-14.2, 0, -4.0), 270.0], "landmark": "the JUICE neon can"},
	"med_bay": {"name": "Med Bay", "rect": Rect2(12, -8, 8, 8), "floor": 0.0, "height": 4.0, "room": "med_bay", "area": "cannery",
		"cam": [58.0, 8.5], "arrive": [Vector3(14.0, 0, -2.6), 90.0], "landmark": "the dumpster ice bath"},
	"loading_dock": {"name": "Loading Dock", "rect": Rect2(-10, -18.6, 20, 10.6), "floor": 0.0, "height": 0.0, "room": "dock", "area": "cannery", "exterior": true,
		"cam": [56.0, 11.5, 90.0], "arrive": [Vector3(0.0, 0, -10.2), 0.0], "landmark": "the chum cannon"},
	"locker_room": {"name": "Locker Room", "rect": Rect2(-12, 8, 12, 8), "floor": 0.0, "height": 3.5, "room": "locker", "area": "cannery",
		"cam": [58.0, 8.5, 180.0], "arrive": [Vector3(-7.0, 0, 10.4), 0.0], "landmark": "the belt case"},
	"office": {"name": "Commissioner's Office", "rect": Rect2(6, 8, 8, 6), "floor": 4.0, "height": 3.0, "room": "office", "area": "cannery",
		"cam": [58.0, 8.0, 180.0], "arrive": [Vector3(10.5, 4.0, 9.9), 0.0], "landmark": "Snappington's desk"},
	"booth": {"name": "Broadcast Booth", "rect": Rect2(0, 8, 6, 4), "floor": 3.0, "height": 2.6, "room": "booth", "area": "cannery",
		"cam": [60.0, 7.0], "arrive": [Vector3(2.1, 3.0, 10.9), 90.0], "landmark": "the ON AIR sign"},
	"boiler_room": {"name": "Boiler Room", "rect": Rect2(40, -5, 14, 10), "floor": 0.0, "height": 4.0, "room": "boiler", "area": "basement",
		"cam": [57.0, 9.5], "arrive": [Vector3(42.7, 0, 3.0), 90.0], "landmark": "the boiler"},
	"roof": {"name": "The Roof", "rect": Rect2(40, -36, 16, 12), "floor": 0.0, "height": 0.0, "room": "roof", "area": "roof", "exterior": true, "secret": true,
		"cam": [48.0, 11.5], "arrive": [Vector3(42.4, 0, -26.3), 180.0], "landmark": "the GLANDCO sign"},
	"pier": {"name": "The Pier", "rect": Rect2(20, -44, 8, 4), "floor": 0.0, "height": 0.0, "room": "dock", "area": "pier", "exterior": true, "secret": true,
		"cam": [55.0, 8.0], "arrive": [Vector3(22.2, 0, -42.0), 90.0], "landmark": "the fishing rod"},
	"crawlspace": {"name": "The Crawlspace", "rect": Rect2(-15.4, 3.7, 3.4, 2.4), "floor": 0.0, "height": 2.1, "room": "locker", "area": "cannery", "secret": true,
		"cam": [62.0, 7.0], "arrive": [Vector3(-12.9, 0, 4.9), 270.0], "landmark": "a jar on a shelf"},
}

## Spaces the "first tour" needs before the corkboard's Fast walk unlocks (secret spaces excluded).
const TOUR := ["main_floor", "juice_bar", "med_bay", "loading_dock", "locker_room", "office", "booth", "boiler_room"]

## Physical walk-through openings between spaces (connectivity test + nav). pos = threshold point.
const DOORS := [
	{"id": "roller_door", "a": "main_floor", "b": "loading_dock", "pos": Vector3(0, 0, -8), "width": 4.0},
	{"id": "juice_door", "a": "main_floor", "b": "juice_bar", "pos": Vector3(-12, 0, -4), "width": 2.0},
	{"id": "med_door", "a": "main_floor", "b": "med_bay", "pos": Vector3(12, 0, -2.5), "width": 2.0},
	{"id": "locker_door", "a": "main_floor", "b": "locker_room", "pos": Vector3(-7, 0, 8), "width": 2.0},
	{"id": "office_door", "a": "main_floor", "b": "office", "pos": Vector3(10.5, 4, 8), "width": 2.0},
	{"id": "panel_hole", "a": "main_floor", "b": "crawlspace", "pos": Vector3(-12, 0, 4.9), "width": 1.6, "needs": "panel_open"},
]

## Interaction-driven transitions (hatch, ladders, elevator): a short fade, then the fighter is
## placed at `to` facing `yaw`. `needs` names a world condition (HubMode.condition()).
const TRANSITIONS := {
	"hatch_down": {"from": Vector3(6.5, 0, 6.9), "to": Vector3(42.7, 0, 3.0), "yaw": 90.0, "space": "main_floor", "dest": "boiler_room", "prompt": "Climb down the hatch"},
	"hatch_up": {"from": Vector3(41.2, 0, 4.0), "to": Vector3(6.5, 0, 6.1), "yaw": 180.0, "space": "boiler_room", "dest": "main_floor", "prompt": "Climb up to the Main Floor"},
	"ladder_up": {"from": Vector3(-0.9, 0, 10.2), "to": Vector3(2.1, 3.0, 10.9), "yaw": 90.0, "space": "locker_room", "dest": "booth", "prompt": "Climb the ladder to the booth"},
	"ladder_down": {"from": Vector3(0.6, 3.0, 11.3), "to": Vector3(-2.0, 0, 11.4), "yaw": 270.0, "space": "booth", "dest": "locker_room", "prompt": "Climb down to the Locker Room"},
	"elevator_up": {"from": Vector3(10.5, 0, -6.6), "to": Vector3(42.4, 0, -26.3), "yaw": 180.0, "space": "main_floor", "dest": "roof", "prompt": "Ride the freight elevator up", "needs": "elevator_fixed"},
	"elevator_down": {"from": Vector3(41.6, 0, -24.9), "to": Vector3(10.4, 0, -4.6), "yaw": 180.0, "space": "roof", "dest": "main_floor", "prompt": "Ride the elevator down"},
	"pier_down": {"from": Vector3(-7.1, 0, -17.8), "to": Vector3(22.2, 0, -42.0), "yaw": 90.0, "space": "loading_dock", "dest": "pier", "prompt": "Climb down the pier ladder", "needs": "pier_revealed"},
	"pier_up": {"from": Vector3(20.6, 0, -40.6), "to": Vector3(-7.1, 0, -16.9), "yaw": 180.0, "space": "pier", "dest": "loading_dock", "prompt": "Climb up to the dock"},
}

## Navigation graph (straight segments between linked points are clear of furniture). Used by the
## connectivity/wander tests, Ludlow's rounds, the Scrapling's escape and Fast walk.
const NAV := {
	"mf_center": Vector3(-4.0, 0, -0.6), "mf_mats_s": Vector3(-4.0, 0, 1.8), "mf_north": Vector3(0.0, 0, -6.4),
	"mf_west": Vector3(-8.4, 0, -3.6), "mf_west_door": Vector3(-10.9, 0, -4.0), "mf_granny": Vector3(-8.0, 0, -4.6),
	"mf_bag3": Vector3(-8.6, 0, 3.0), "mf_panel": Vector3(-11.0, 0, 3.9),
	"mf_east": Vector3(7.8, 0, -2.5), "mf_east_door": Vector3(10.9, 0, -2.5), "mf_cage_gate": Vector3(-0.2, 0, -1.4),
	"mf_cage_in": Vector3(3.6, 0, -1.4), "mf_ne": Vector3(7.9, 0, -6.0), "mf_elevator": Vector3(10.5, 0, -6.6),
	"mf_south_door": Vector3(-7.0, 0, 6.6), "mf_sw": Vector3(-7.0, 0, 3.4), "mf_stairs_bottom": Vector3(-3.4, 0, 6.4),
	"mf_stairs_mid": Vector3(3.0, 2.0, 6.4), "mf_stairs_top": Vector3(8.6, 4.0, 6.4), "mf_landing": Vector3(10.5, 4.0, 6.6),
	"mf_under_stairs": Vector3(6.5, 0, 4.8), "mf_hatch": Vector3(6.5, 0, 6.6),
	"dock_door": Vector3(0.0, 0, -9.8), "dock_center": Vector3(-1.0, 0, -13.4), "dock_west": Vector3(-7.0, 0, -13.6),
	"dock_east": Vector3(7.2, 0, -13.0), "dock_bench": Vector3(-8.0, 0, -12.2), "dock_crates": Vector3(-6.6, 0, -10.4),
	"dock_edge": Vector3(-7.1, 0, -17.2), "dock_cannon_sq": Vector3(4.0, 0, -14.4), "dock_forklift": Vector3(7.6, 0, -9.4),
	"jb_door": Vector3(-13.2, 0, -4.0), "jb_center": Vector3(-16.0, 0, -4.2), "jb_counter": Vector3(-18.7, 0, -4.4),
	"mb_door": Vector3(13.2, 0, -2.5), "mb_center": Vector3(14.4, 0, -3.4), "mb_doc": Vector3(17.6, 0, -3.4), "mb_bath": Vector3(17.0, 0, -3.3),
	"lr_door": Vector3(-7.0, 0, 9.6), "lr_center": Vector3(-5.0, 0, 12.2), "lr_case": Vector3(-4.8, 0, 11.7), "lr_ladder": Vector3(-1.4, 0, 10.7),
	"lr_lockers": Vector3(-8.4, 0, 13.8), "lr_wall": Vector3(-10.4, 0, 12.4),
	"of_door": Vector3(10.5, 4.0, 9.3), "of_center": Vector3(10.0, 4.0, 10.4), "of_cabinet": Vector3(7.4, 4.0, 9.6),
	"bo_arrive": Vector3(2.1, 3.0, 10.9), "bo_center": Vector3(2.2, 3.0, 10.0), "bo_desk": Vector3(1.4, 3.0, 9.6),
	"br_arrive": Vector3(42.7, 0, 3.0), "br_center": Vector3(46.4, 0, 1.0), "br_table": Vector3(45.0, 0, -1.4), "br_boiler": Vector3(47.8, 0, -2.0),
	"br_terminal": Vector3(51.8, 0, 3.2),
	"rf_arrive": Vector3(42.4, 0, -26.3), "rf_center": Vector3(47.5, 0, -30.0), "rf_sign": Vector3(48.0, 0, -33.6), "rf_tower": Vector3(51.0, 0, -28.6),
	"pr_arrive": Vector3(22.2, 0, -42.0), "pr_center": Vector3(24.0, 0, -42.0), "pr_fish": Vector3(26.0, 0, -42.2),
	"cs_in": Vector3(-12.9, 0, 4.9), "cs_end": Vector3(-14.5, 0, 4.9),
}

const NAV_LINKS := [
	["mf_center", "mf_mats_s"], ["mf_center", "mf_north"], ["mf_center", "mf_west"], ["mf_west", "mf_west_door"], ["mf_west", "mf_granny"],
	["mf_center", "mf_cage_gate"], ["mf_cage_gate", "mf_cage_in"], ["mf_north", "mf_ne"], ["mf_ne", "mf_elevator"], ["mf_ne", "mf_east"],
	["mf_east", "mf_east_door"], ["mf_mats_s", "mf_sw"], ["mf_sw", "mf_south_door"], ["mf_sw", "mf_bag3"],
	["mf_bag3", "mf_panel"], ["mf_mats_s", "mf_stairs_bottom"], ["mf_stairs_bottom", "mf_stairs_mid"], ["mf_stairs_mid", "mf_stairs_top"],
	["mf_stairs_top", "mf_landing"], ["mf_east", "mf_under_stairs"], ["mf_under_stairs", "mf_hatch"], ["mf_mats_s", "mf_under_stairs"],
	["mf_north", "dock_door"], ["dock_door", "dock_center"], ["dock_center", "dock_west"], ["dock_center", "dock_east"], ["dock_west", "dock_bench"],
	["dock_west", "dock_crates"], ["dock_crates", "dock_door"], ["dock_west", "dock_edge"], ["dock_center", "dock_cannon_sq"],
	["dock_door", "dock_forklift"], ["dock_east", "dock_cannon_sq"],
	["mf_west_door", "jb_door"], ["jb_door", "jb_center"], ["jb_center", "jb_counter"],
	["mf_east_door", "mb_door"], ["mb_door", "mb_center"], ["mb_center", "mb_doc"], ["mb_center", "mb_bath"],
	["mf_south_door", "lr_door"], ["lr_door", "lr_center"], ["lr_center", "lr_case"], ["lr_center", "lr_ladder"], ["lr_center", "lr_lockers"],
	["lr_center", "lr_wall"],
	["mf_landing", "of_door"], ["of_door", "of_center"], ["of_center", "of_cabinet"],
	["bo_arrive", "bo_center"], ["bo_center", "bo_desk"],
	["br_arrive", "br_center"], ["br_center", "br_table"], ["br_center", "br_boiler"], ["br_center", "br_terminal"],
	["rf_arrive", "rf_center"], ["rf_center", "rf_sign"], ["rf_center", "rf_tower"],
	["pr_arrive", "pr_center"], ["pr_center", "pr_fish"],
	["mf_panel", "cs_in"], ["cs_in", "cs_end"],
]

## Fixed spots. NPC home positions (yaw in degrees, model faces +Z at 0).
const NPC_SPOTS := {
	"granny": {"pos": Vector3(-9.4, 0, -5.4), "yaw": 48.0, "space": "main_floor"},
	"snappington": {"pos": Vector3(10.0, 4.0, 12.5), "yaw": 180.0, "space": "office"},
	"needles": {"pos": Vector3(-20.9, 0, -4.4), "yaw": 90.0, "space": "juice_bar"},
	"doc": {"pos": Vector3(18.5, 0, -5.9), "yaw": 300.0, "space": "med_bay"},
	"kid": {"pos": Vector3(-6.0, 0, 14.6), "yaw": 180.0, "space": "locker_room"},
	"ludlow": {"pos": Vector3(-8.2, 0, -11.6), "yaw": 60.0, "space": "loading_dock"},
	"teddy": {"pos": Vector3(45.0, 0, -3.3), "yaw": 0.0, "space": "boiler_room"},
	"barnaby": {"pos": Vector3(3.6, 3.0, 10.4), "yaw": 180.0, "space": "booth"},
}

## Ludlow's mop round (nav point names); he dwells at each stop.
const LUDLOW_ROUND := ["dock_bench", "dock_center", "dock_door", "mf_north", "mf_center", "mf_mats_s", "mf_center", "mf_north", "dock_door", "dock_center", "dock_bench"]

## The Scrapling's escape route from under the stairs to the dock (secret #3).
const SCRAPLING_RUN := [Vector3(10.4, 0, 7.0), Vector3(6.5, 0, 4.8), Vector3(7.4, 0, -2.5), Vector3(7.6, 0, -6.2), Vector3(0.0, 0, -6.4),
	Vector3(0.0, 0, -9.8), Vector3(-1.0, 0, -13.4), Vector3(-7.0, 0, -16.6)]
const SCRAPLING_DOOR_Z := -8.0          ## caught before crossing this line = +25 Clout

## Interactables placed in the world (behaviour lives in HubMode; text in content/core/hub).
## kind: npc | station | transition | activity | object | secret
const INTERACTS := [
	{"id": "npc_granny", "kind": "npc", "npc": "granny", "pos": Vector3(-9.4, 0, -5.4), "r": 2.2},
	{"id": "npc_snappington", "kind": "npc", "npc": "snappington", "pos": Vector3(10.0, 4.0, 10.9), "r": 1.2},
	{"id": "npc_needles", "kind": "npc", "npc": "needles", "pos": Vector3(-18.7, 0, -4.4), "r": 1.6},
	{"id": "npc_doc", "kind": "npc", "npc": "doc", "pos": Vector3(18.5, 0, -5.9), "r": 2.2},
	{"id": "npc_kid", "kind": "npc", "npc": "kid", "pos": Vector3(-6.0, 0, 14.6), "r": 2.2},
	{"id": "npc_ludlow", "kind": "npc", "npc": "ludlow", "pos": Vector3(-8.2, 0, -11.6), "r": 2.2, "moves": true},
	{"id": "npc_teddy", "kind": "npc", "npc": "teddy", "pos": Vector3(46.3, 0, -2.6), "r": 1.5},
	{"id": "npc_barnaby", "kind": "npc", "npc": "barnaby", "pos": Vector3(3.6, 3.0, 10.4), "r": 1.8},
	{"id": "st_gym_floor", "kind": "station", "station": "gym_floor", "pos": Vector3(-8.0, 0, -6.6), "r": 1.6, "prompt": "Granny's clipboard (Gym Floor upgrades)"},
	{"id": "st_juice_bar", "kind": "station", "station": "juice_bar", "pos": Vector3(-18.8, 0, -6.4), "r": 1.6, "prompt": "Needles' menu (Juice Bar upgrades)"},
	{"id": "st_med_bay", "kind": "station", "station": "med_bay", "pos": Vector3(19.0, 0, -3.2), "r": 1.6, "prompt": "Doc's chart (Med Bay upgrades)"},
	{"id": "st_office", "kind": "station", "station": "office", "pos": Vector3(11.3, 4.0, 11.0), "r": 0.9, "prompt": "Snappington's ledger (Office upgrades)"},
	{"id": "st_loading_dock", "kind": "station", "station": "loading_dock", "pos": Vector3(-8.6, 0, -14.4), "r": 1.6, "prompt": "Ludlow's workbench (Dock upgrades)"},
	{"id": "st_boiler_room", "kind": "station", "station": "boiler_room", "pos": Vector3(43.0, 0, -3.4), "r": 1.6, "prompt": "Teddy's ledger (Boiler Room upgrades)"},
	{"id": "run_desk", "kind": "service", "service": "start_run", "pos": Vector3(8.8, 4.0, 11.0), "r": 0.9, "prompt": "Sign up for a fight card"},
	{"id": "cage_gate", "kind": "service", "service": "sparring", "pos": Vector3(-0.2, 0, -1.4), "r": 1.6, "prompt": "Ring sparring"},
	{"id": "bookie_table", "kind": "service", "service": "bookie", "pos": Vector3(45.0, 0, -1.1), "r": 1.2, "prompt": "Take a seat at the Bookie's Table"},
	{"id": "ai_terminal", "kind": "service", "service": "ai_lab", "pos": Vector3(51.9, 0, 3.4), "r": 1.6, "prompt": "AI Lab terminal"},
	{"id": "corkboard", "kind": "service", "service": "map", "pos": Vector3(3.4, 0, -6.9), "r": 1.6, "prompt": "Corkboard map (hold for Fast walk)"},
	{"id": "lockers", "kind": "service", "service": "lockers", "pos": Vector3(-9.6, 0, 14.2), "r": 1.6, "prompt": "Your locker (fighter and cosmetics)"},
	{"id": "wall_of_fame", "kind": "service", "service": "records", "pos": Vector3(-10.7, 0, 12.0), "r": 1.6, "prompt": "Wall of Fame / Shame"},
	{"id": "booth_desk", "kind": "service", "service": "booth", "pos": Vector3(4.8, 3.0, 9.6), "r": 1.3, "prompt": "Announcer settings and replay booth"},
	{"id": "bag_light", "kind": "activity", "activity": "bag", "bag": "light", "pos": Vector3(-8.9, 0, -1.8), "r": 1.0, "prompt": "Start the Light bag challenge (30 s)"},
	{"id": "bag_heavy", "kind": "activity", "activity": "bag", "bag": "heavy", "pos": Vector3(-8.9, 0, 1.0), "r": 1.0, "prompt": "Start the Heavy bag challenge (30 s)"},
	{"id": "bag_body", "kind": "activity", "activity": "bag", "bag": "body", "pos": Vector3(-8.3, 0, 4.9), "r": 0.9, "prompt": "Start the Body bag challenge (30 s)"},
	{"id": "chum_cannon", "kind": "activity", "activity": "drill", "pos": Vector3(7.6, 0, -12.4), "r": 1.6, "prompt": "Chum Cannon dodge drill (45 s)"},
	{"id": "crate_pile", "kind": "activity", "activity": "crates", "pos": Vector3(-6.4, 0, -10.0), "r": 1.6, "prompt": "Crate Toss (10 crates)"},
	{"id": "vending", "kind": "object", "pos": Vector3(-13.4, 0, -6.6), "r": 1.3, "prompt": "Vending machine"},
	{"id": "radio", "kind": "object", "pos": Vector3(-18.8, 0, -2.0), "r": 1.2, "prompt": "Juice Bar radio"},
	{"id": "doc_cot", "kind": "service", "service": "rest_preview", "pos": Vector3(13.8, 0, -5.6), "r": 1.3, "prompt": "Doc's cot (Rest preview)"},
	{"id": "belt_case", "kind": "secret", "pos": Vector3(-4.8, 0, 11.2), "r": 1.6, "prompt": "The belt case"},
	{"id": "booth_chair", "kind": "secret", "pos": Vector3(1.4, 3.0, 9.4), "r": 0.9, "prompt": "Reach under the desk"},
	{"id": "filing_cabinet_2", "kind": "secret", "pos": Vector3(7.3, 4.0, 10.5), "r": 1.0, "prompt": "Rummage in the second filing cabinet"},
	{"id": "crawl_jar", "kind": "secret", "pos": Vector3(-14.5, 0, 4.9), "r": 1.1, "prompt": "Take the jar off the shelf"},
	{"id": "ice_bath", "kind": "secret", "pos": Vector3(17.0, 0.25, -1.45), "r": 1.6, "prompt": "Reach for the bottom of the ice bath"},
	{"id": "fishing_rod", "kind": "secret", "pos": Vector3(26.0, 0, -42.2), "r": 1.4, "prompt": "Fish off the pier (20 s)"},
	{"id": "roof_trunk", "kind": "secret", "pos": Vector3(54.4, 0, -34.2), "r": 1.4, "prompt": "Open the old steamer trunk"},
	{"id": "roof_ring", "kind": "service", "service": "rooftop_practice", "pos": Vector3(46.0, 0, -29.0), "r": 1.6, "prompt": "Rooftop practice (chalk ring)"},
	{"id": "elevator_gate", "kind": "object", "pos": Vector3(10.5, 0, -4.8), "r": 1.4, "prompt": "The freight elevator"},
]

## Carryable props: id -> {kind, pos, mass, size, space}
const ITEMS := {
	"fuse": {"kind": "part", "pos": Vector3(48.7, 0.9, -1.0), "size": Vector3(0.3, 0.42, 0.3), "mass": 6.0, "name": "a fuse"},
	"cable_spool": {"kind": "part", "pos": Vector3(5.4, 0.35, -8.7), "size": Vector3(0.6, 0.6, 0.5), "mass": 14.0, "name": "a cable spool"},
	"button": {"kind": "part", "pos": Vector3(7.0, 4.95, 10.4), "size": Vector3(0.3, 0.22, 0.3), "mass": 3.0, "name": "a big red button", "hidden": true},
	"letter_a": {"kind": "letter", "pos": Vector3(51.6, 0.35, -27.7), "size": Vector3(0.9, 1.0, 0.18), "mass": 9.0, "name": "the letter A"},
	"trash_lid": {"kind": "lid", "pos": Vector3(10.4, 0.06, 7.4), "size": Vector3(0.7, 0.08, 0.7), "mass": 3.0, "name": "a trash-can lid", "hidden": true},
}

## Crate Toss lane (Loading Dock): crates spawn at the pile, rings are painted ahead (north).
const CRATE_PILE := Vector3(-7.2, 0, -9.6)
const CRATE_LINE_Z := -9.6
const CRATE_LANE_X := -4.0
const CRATE_RINGS := [{"dist": 3.0, "r": 0.9, "points": 5}, {"dist": 5.0, "r": 0.9, "points": 10}, {"dist": 8.0, "r": 0.8, "points": 20}]
const WATER_EDGE_Z := -18.6
const WATER_Y := -0.9

## Chum Cannon drill square (Loading Dock) and the cannon.
const DRILL_SQUARE := Rect2(2.0, -16.4, 4.0, 4.0)
const CANNON_POS := Vector3(8.6, 0, -14.4)

## The three hanging bags: hang point (ceiling chain) and the bag's swing body.
const BAGS := {
	"light": {"hang": Vector3(-10.3, 2.55, -1.8), "radius": 0.26, "length": 1.0, "bottom": 0.75, "mass": 25.0, "name": "Light bag"},
	"heavy": {"hang": Vector3(-10.3, 2.55, 1.0), "radius": 0.34, "length": 1.35, "bottom": 0.45, "mass": 60.0, "name": "Heavy bag"},
	"body": {"hang": Vector3(-9.4, 2.55, 4.9), "radius": 0.38, "length": 1.45, "bottom": 0.35, "mass": 70.0, "name": "Body bag"},
}

## Practice cage on the Main Floor (a mini-Gullet, octagon apothem 3 m).
const CAGE_CENTER := Vector3(3.6, 0, -1.4)
const CAGE_APOTHEM := 3.0
const CAGE_GATE_SIDE := 3          ## octagon side index of the gate (the west side, see cage_points)

## Secret spots.
const PANEL_RECT := Rect2(-12.15, 3.7, 0.3, 2.4)
## The stairs to the Office: centre line and width (wide enough for Dredge's claws).
const STAIRS_Z := 6.4
const STAIRS_W := 2.9
const BOILER_POS := Vector3(50.5, 0, -2.0)
const BOILER_R := 1.5
const ICE_BATH := Rect2(15.6, -2.15, 2.8, 1.4)     ## inside of the dumpster tub
const BELT_CASE_POS := Vector3(-4.8, 0, 10.2)
const SIGN_SLOT := Vector3(46.6, 2.9, -35.2)       ## the missing "A" of GL_NDCO
const PIER_LADDER := Vector3(-7.1, 0, -18.4)
const ELEVATOR_RECT := Rect2(9.2, -7.8, 2.6, 2.4)


static func space(id: String) -> Dictionary:
	return SPACES.get(id, {})


static func space_ids() -> Array:
	return SPACES.keys()


## Space containing a world point (root position of a fighter); "" when outside every space.
## Raised floors win when the point is at or above them.
static func space_at(p: Vector3) -> String:
	var best := ""
	var best_floor := -INF
	for id in SPACES:
		var s: Dictionary = SPACES[id]
		var r: Rect2 = s["rect"]
		if p.x < r.position.x or p.x > r.end.x or p.z < r.position.y or p.z > r.end.y:
			continue
		var fl := float(s["floor"])
		if p.y < fl - 0.3:
			continue
		if fl > best_floor:
			best_floor = fl
			best = id
	# the landing at +4 m inside the Main Floor's footprint still belongs to the Main Floor
	return best


static func arrive_of(space_id: String) -> Array:
	var s := space(space_id)
	if s.is_empty():
		return [Vector3.ZERO, 0.0]
	var a: Array = s["arrive"]
	return [a[0], deg_to_rad(float(a[1]))]


static func interact_def(id: String) -> Dictionary:
	for d in INTERACTS:
		if str(d["id"]) == id:
			return d
	return {}


static func station_interact(station: String) -> String:
	for d in INTERACTS:
		if str(d.get("station", "")) == station:
			return str(d["id"])
	return ""


## ---- geometry used by HubWorld (physics) and HubView (visuals) ----------------------------

## Wall along X at z (from x0 to x1) or along Z at x (from z0 to z1). openings: [[from, to, y0, y1, kind]]
## measured on the wall's axis; kind "door" cuts collision, "window"/"glass" is visual only.
static func _wx(z: float, x0: float, x1: float, y0: float, y1: float, style: String, openings: Array = [], space_id := "") -> Dictionary:
	return {"axis": "x", "c": z, "from": x0, "to": x1, "y0": y0, "y1": y1, "style": style, "openings": openings, "space": space_id}


static func _wz(x: float, z0: float, z1: float, y0: float, y1: float, style: String, openings: Array = [], space_id := "") -> Dictionary:
	return {"axis": "z", "c": x, "from": z0, "to": z1, "y0": y0, "y1": y1, "style": style, "openings": openings, "space": space_id}


static func walls() -> Array:
	var w := []
	# Main Floor shell (7 m)
	w.append(_wx(-8.0, -12.0, 12.0, 0.0, 7.0, "brick", [[-2.0, 2.0, 0.0, 4.2, "door"], [-9.5, -6.5, 3.6, 5.6, "window"], [6.5, 9.0, 3.6, 5.6, "window"]], "main_floor"))
	w.append(_wz(-12.0, -8.0, 8.0, 0.0, 7.0, "brick", [[-5.0, -3.0, 0.0, DOOR_H, "door"], [3.7, 6.1, 0.0, 2.2, "panel"], [1.0, 3.6, 4.6, 6.2, "window"]], "main_floor"))
	w.append(_wz(12.0, -8.0, 8.0, 0.0, 7.0, "brick", [[-3.5, -1.5, 0.0, DOOR_H, "door"], [1.0, 4.0, 4.6, 6.2, "window"]], "main_floor"))
	w.append(_wx(8.0, -12.0, 12.0, 0.0, 7.0, "brick", [[-8.0, -6.0, 0.0, DOOR_H, "door"], [9.5, 11.5, 4.0, 4.0 + DOOR_H, "door"],
		[0.3, 5.7, 3.4, 5.3, "glass"], [6.6, 9.0, 5.0, 6.5, "glass"]], "main_floor"))
	# Juice Bar (4 m)
	w.append(_wx(-8.0, -22.0, -12.0, 0.0, 4.0, "plaster_green", [[-19.5, -17.0, 1.4, 2.8, "window"]], "juice_bar"))
	w.append(_wz(-22.0, -8.0, 0.0, 0.0, 4.0, "plaster_green", [], "juice_bar"))
	w.append(_wx(0.0, -22.0, -12.0, 0.0, 4.0, "plaster_green", [[-17.5, -15.0, 1.4, 2.8, "window"]], "juice_bar"))
	# Med Bay (4 m)
	w.append(_wx(-8.0, 12.0, 20.0, 0.0, 4.0, "tile_white", [[15.0, 17.5, 1.4, 2.8, "window"]], "med_bay"))
	w.append(_wz(20.0, -8.0, 0.0, 0.0, 4.0, "tile_white", [], "med_bay"))
	w.append(_wx(0.0, 12.0, 20.0, 0.0, 4.0, "tile_white", [], "med_bay"))
	# Locker Room (3.5 m)
	w.append(_wz(-12.0, 8.0, 16.0, 0.0, 3.5, "tile_blue", [], "locker_room"))
	w.append(_wx(16.0, -12.0, 0.0, 0.0, 3.5, "tile_blue", [[-5.0, -2.5, 1.8, 2.8, "window"]], "locker_room"))
	w.append(_wz(0.0, 8.0, 16.0, 0.0, 3.5, "tile_blue", [], "locker_room"))
	# Broadcast Booth shell (on a solid block, floor +3 m; north face is the Main Floor's south wall)
	w.append(_wz(6.0, 8.0, 14.0, 0.0, 7.0, "plaster_dark", [], "office"))
	w.append(_wx(12.0, 0.0, 6.0, 0.0, 5.6, "plaster_dark", [], "booth"))
	w.append(_wz(0.0, 8.0, 12.0, 3.5, 5.6, "plaster_dark", [], "booth"))
	# Commissioner's Office (floor +4 m, walls to 7 m)
	w.append(_wx(8.0, 12.0, 14.0, 0.0, 7.0, "wood_panel", [], "office"))
	w.append(_wz(14.0, 8.0, 14.0, 0.0, 7.0, "wood_panel", [], "office"))
	w.append(_wx(14.0, 6.0, 14.0, 0.0, 7.0, "wood_panel", [[8.5, 11.5, 5.0, 6.4, "window"]], "office"))
	# Crawlspace (secret #2): a 3 m tunnel behind bag 3
	w.append(_wx(3.7, -15.5, -12.0, 0.0, 2.2, "plank", [], "crawlspace"))
	w.append(_wx(6.1, -15.5, -12.0, 0.0, 2.2, "plank", [], "crawlspace"))
	w.append(_wz(-15.5, 3.7, 6.1, 0.0, 2.2, "plank", [], "crawlspace"))
	# Boiler Room (basement region)
	w.append(_wx(-5.0, 40.0, 54.0, 0.0, 4.0, "brick_dark", [], "boiler_room"))
	w.append(_wx(5.0, 40.0, 54.0, 0.0, 4.0, "brick_dark", [], "boiler_room"))
	w.append(_wz(40.0, -5.0, 5.0, 0.0, 4.0, "brick_dark", [], "boiler_room"))
	w.append(_wz(54.0, -5.0, 5.0, 0.0, 4.0, "brick_dark", [], "boiler_room"))
	# Roof parapet (0.9 m)
	w.append(_wx(-36.0, 40.0, 56.0, 0.0, 0.9, "parapet", [], "roof"))
	w.append(_wx(-24.0, 40.0, 56.0, 0.0, 0.9, "parapet", [], "roof"))
	w.append(_wz(40.0, -36.0, -24.0, 0.0, 0.9, "parapet", [], "roof"))
	w.append(_wz(56.0, -36.0, -24.0, 0.0, 0.9, "parapet", [], "roof"))
	return w


## Solid furniture/structure blocks (collide with fighters and props). {box: AABB, style, name, visible}
static func solids() -> Array:
	var s := []
	# raised floors: the booth (+3 m) and office (+4 m) sit on solid blocks
	s.append({"name": "booth_block", "box": AABB(Vector3(0.0, 0.0, 8.0), Vector3(6.0, 3.0, 4.0)), "style": "plaster_dark"})
	s.append({"name": "office_block", "box": AABB(Vector3(6.0, 0.0, 8.0), Vector3(8.0, 4.0, 6.0)), "style": "wood_panel"})
	# Juice Bar counter, tables, vending machine
	s.append({"name": "jb_counter", "box": AABB(Vector3(-20.2, 0.0, -7.4), Vector3(0.8, 1.05, 6.2)), "style": "counter"})
	s.append({"name": "jb_vending", "box": AABB(Vector3(-13.9, 0.0, -7.9), Vector3(1.0, 1.95, 0.8)), "style": "vending"})
	s.append({"name": "jb_table_a", "box": AABB(Vector3(-15.5, 0.0, -6.9), Vector3(0.8, 0.75, 0.8)), "style": "table"})
	s.append({"name": "jb_table_b", "box": AABB(Vector3(-15.5, 0.0, -2.2), Vector3(0.8, 0.75, 0.8)), "style": "table"})
	# Med Bay: exam table, cot, the dumpster ice bath (walls only; you step in through the gap)
	s.append({"name": "mb_table", "box": AABB(Vector3(15.6, 0.0, -6.0), Vector3(2.0, 0.85, 0.9)), "style": "steel_light"})
	s.append({"name": "mb_cot", "box": AABB(Vector3(12.4, 0.0, -7.6), Vector3(2.2, 0.55, 0.9)), "style": "cot"})
	s.append({"name": "bath_n_w", "box": AABB(Vector3(15.4, 0.0, -2.35), Vector3(1.0, 1.0, 0.18)), "style": "dumpster"})
	s.append({"name": "bath_n_e", "box": AABB(Vector3(17.6, 0.0, -2.35), Vector3(1.0, 1.0, 0.18)), "style": "dumpster"})
	s.append({"name": "bath_s", "box": AABB(Vector3(15.4, 0.0, -0.75), Vector3(3.2, 1.0, 0.18)), "style": "dumpster"})
	s.append({"name": "bath_w", "box": AABB(Vector3(15.4, 0.0, -2.35), Vector3(0.18, 1.0, 1.78)), "style": "dumpster"})
	s.append({"name": "bath_e", "box": AABB(Vector3(18.42, 0.0, -2.35), Vector3(0.18, 1.0, 1.78)), "style": "dumpster"})
	s.append({"name": "bath_floor", "box": AABB(Vector3(15.58, 0.0, -2.17), Vector3(2.84, 0.22, 1.42)), "style": "dumpster_in"})
	s.append({"name": "bath_step", "box": AABB(Vector3(16.4, 0.0, -2.9), Vector3(1.2, 0.18, 0.56)), "style": "steel"})
	# Locker Room: lockers, bench, belt case
	s.append({"name": "lockers", "box": AABB(Vector3(-11.6, 0.0, 15.3), Vector3(9.0, 2.0, 0.55)), "style": "lockers"})
	s.append({"name": "lr_bench", "box": AABB(Vector3(-10.6, 0.0, 10.9), Vector3(2.0, 0.45, 0.45)), "style": "bench"})
	s.append({"name": "belt_case", "box": AABB(Vector3(-5.4, 0.0, 9.9), Vector3(1.2, 1.3, 0.6)), "style": "case"})
	# Office: the Commissioner's desk and her shell behind it, filing cabinet #1
	s.append({"name": "of_desk", "box": AABB(Vector3(9.2, 4.0, 11.5), Vector3(1.6, 0.8, 0.75)), "style": "none", "visible": false})
	s.append({"name": "of_snap", "box": AABB(Vector3(9.3, 4.0, 12.4), Vector3(1.4, 1.2, 1.5)), "style": "none", "visible": false})
	s.append({"name": "of_cabinet_1", "box": AABB(Vector3(6.15, 4.0, 8.6), Vector3(0.6, 1.4, 0.7)), "style": "cabinet"})
	# Booth: the mixing desk along the glass
	s.append({"name": "bo_desk", "box": AABB(Vector3(2.4, 3.0, 8.15), Vector3(3.2, 0.95, 0.75)), "style": "desk"})
	# Main Floor: bleachers, Granny's chair + cooler, elevator shaft walls, cage posts handled by HubWorld
	s.append({"name": "bleacher_1", "box": AABB(Vector3(8.4, 0.0, -0.6), Vector3(1.0, 0.45, 3.8)), "style": "bleacher"})
	s.append({"name": "bleacher_2", "box": AABB(Vector3(9.4, 0.0, -0.6), Vector3(1.0, 0.9, 3.8)), "style": "bleacher"})
	s.append({"name": "bleacher_3", "box": AABB(Vector3(10.4, 0.0, -0.6), Vector3(1.4, 1.35, 3.8)), "style": "bleacher"})
	s.append({"name": "granny_chair", "box": AABB(Vector3(-11.3, 0.0, -7.2), Vector3(0.6, 0.5, 0.6)), "style": "chair"})
	s.append({"name": "granny_cooler", "box": AABB(Vector3(-10.4, 0.0, -7.6), Vector3(0.7, 0.5, 0.45)), "style": "cooler"})
	# Loading Dock: containers bounding the sides, the forklift, Ludlow's workbench, the cannon
	s.append({"name": "container_w", "box": AABB(Vector3(-11.4, 0.0, -18.6), Vector3(1.4, 2.6, 10.6)), "style": "container_red"})
	s.append({"name": "container_e", "box": AABB(Vector3(10.0, 0.0, -18.6), Vector3(1.4, 2.6, 10.6)), "style": "container_blue"})
	s.append({"name": "forklift", "box": AABB(Vector3(4.6, 0.0, -11.6), Vector3(1.6, 1.6, 2.0)), "style": "none", "visible": false})
	s.append({"name": "workbench", "box": AABB(Vector3(-9.9, 0.0, -15.6), Vector3(0.8, 0.95, 2.4)), "style": "workbench"})
	s.append({"name": "cannon", "box": AABB(Vector3(8.1, 0.0, -15.0), Vector3(1.1, 1.0, 1.2)), "style": "none", "visible": false})
	s.append({"name": "curb", "box": AABB(Vector3(-10.0, 0.0, -18.75), Vector3(20.0, 0.22, 0.2)), "style": "curb"})
	# Boiler Room: boiler (cylinder in HubWorld), Teddy's table, ledger desk, terminal, pipes
	s.append({"name": "br_table", "box": AABB(Vector3(44.4, 0.0, -2.8), Vector3(1.2, 0.72, 1.0)), "style": "none", "visible": false})
	s.append({"name": "br_ledger_desk", "box": AABB(Vector3(42.3, 0.0, -4.8), Vector3(1.4, 0.85, 0.6)), "style": "desk"})
	s.append({"name": "br_terminal", "box": AABB(Vector3(52.9, 0.0, 2.6), Vector3(0.9, 1.3, 1.6)), "style": "terminal"})
	# Roof: water tower legs, AC units, the sign frame
	s.append({"name": "rf_tower", "box": AABB(Vector3(52.0, 0.0, -28.4), Vector3(2.2, 0.4, 2.2)), "style": "steel"})
	s.append({"name": "rf_ac_1", "box": AABB(Vector3(43.0, 0.0, -31.5), Vector3(1.6, 1.1, 1.2)), "style": "steel_light"})
	s.append({"name": "rf_ac_2", "box": AABB(Vector3(50.2, 0.0, -25.4), Vector3(1.6, 1.1, 1.0)), "style": "steel_light"})
	s.append({"name": "rf_trunk", "box": AABB(Vector3(54.4, 0.0, -35.4), Vector3(1.0, 0.6, 0.6)), "style": "trunk"})
	# Pier: a crate of bait and the rod stand
	s.append({"name": "pr_bait", "box": AABB(Vector3(26.9, 0.0, -43.6), Vector3(0.7, 0.5, 0.6)), "style": "crate"})
	# Crawlspace shelf
	s.append({"name": "cs_shelf", "box": AABB(Vector3(-15.4, 0.0, 4.2), Vector3(0.35, 1.0, 1.4)), "style": "plank"})
	return s


## Floor slabs (top surface at `y`). Ground-level areas of the Cannery share one big yard slab.
static func floors() -> Array:
	return [
		{"name": "yard", "rect": Rect2(-34, -18.6, 68, 46), "y": 0.0, "style": "none"},
		{"name": "boiler_floor", "rect": Rect2(39.5, -5.5, 15, 11), "y": 0.0, "style": "none"},
		{"name": "roof_floor", "rect": Rect2(39.5, -36.5, 17, 13), "y": 0.0, "style": "none"},
		{"name": "pier_floor", "rect": Rect2(20, -44, 8, 4), "y": 0.0, "style": "none"},
		{"name": "landing", "rect": Rect2(8, 4.95, 4, 3.05), "y": 4.0, "style": "none", "thick": 0.35},
	]


## Real stairs: a ramp from `a` (bottom centre) to `b` (top centre). The thick part is boxed in.
static func ramps() -> Array:
	return [
		{"name": "stairs_low", "a": Vector3(-2.0, 0.0, STAIRS_Z), "b": Vector3(4.0, 2.4, STAIRS_Z), "width": STAIRS_W, "thick": 2.4},
		{"name": "stairs_high", "a": Vector3(4.0, 2.4, STAIRS_Z), "b": Vector3(8.0, 4.0, STAIRS_Z), "width": STAIRS_W, "thick": 0.35},
	]


## Fighter-only invisible blockers (thrown crates and other props fly over/through them).
static func blockers() -> Array:
	return [
		{"name": "dock_edge", "box": AABB(Vector3(-10.0, 0.0, -19.4), Vector3(20.0, 3.0, 0.6))},
		{"name": "stair_rail", "a": Vector3(-2.0, 0.0, STAIRS_Z - STAIRS_W * 0.5 - 0.15), "b": Vector3(8.0, 4.0, STAIRS_Z - STAIRS_W * 0.5 - 0.15), "h": 1.3},
		{"name": "landing_rail", "box": AABB(Vector3(8.0, 4.0, STAIRS_Z - STAIRS_W * 0.5 - 0.3), Vector3(4.0, 1.3, 0.3))},
		{"name": "roof_edge_n", "box": AABB(Vector3(40.0, 0.0, -36.6), Vector3(16.0, 3.0, 0.6))},
		{"name": "roof_edge_s", "box": AABB(Vector3(40.0, 0.0, -24.0), Vector3(16.0, 3.0, 0.6))},
		{"name": "roof_edge_w", "box": AABB(Vector3(39.4, 0.0, -36.0), Vector3(0.6, 3.0, 12.0))},
		{"name": "roof_edge_e", "box": AABB(Vector3(56.0, 0.0, -36.0), Vector3(0.6, 3.0, 12.0))},
		{"name": "pier_n", "box": AABB(Vector3(20.0, 0.0, -44.6), Vector3(8.0, 3.0, 0.6))},
		{"name": "pier_s", "box": AABB(Vector3(20.0, 0.0, -40.0), Vector3(8.0, 3.0, 0.6))},
		{"name": "pier_w", "box": AABB(Vector3(19.4, 0.0, -44.0), Vector3(0.6, 3.0, 4.0))},
		{"name": "pier_e", "box": AABB(Vector3(28.0, 0.0, -44.0), Vector3(0.6, 3.0, 4.0))},
	]


## Octagon corner points of the practice cage (XZ), CCW from the east side.
static func cage_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var circ := CAGE_APOTHEM / cos(PI / 8.0)
	for i in 8:
		var a := TAU * i / 8.0 + PI / 8.0
		pts.append(Vector2(CAGE_CENTER.x + cos(a) * circ, CAGE_CENTER.z + sin(a) * circ))
	return pts


## Shortest nav path (point names) between two nav points (BFS over NAV_LINKS).
static func nav_path(from: String, to: String) -> Array:
	if from == to:
		return [from]
	var adj := {}
	for l in NAV_LINKS:
		var a := str(l[0])
		var b := str(l[1])
		if not adj.has(a):
			adj[a] = []
		if not adj.has(b):
			adj[b] = []
		(adj[a] as Array).append(b)
		(adj[b] as Array).append(a)
	var prev := {from: ""}
	var queue := [from]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == to:
			break
		for n in adj.get(cur, []):
			if not prev.has(n):
				prev[n] = cur
				queue.append(n)
	if not prev.has(to):
		return []
	var path := []
	var c := to
	while c != "":
		path.push_front(c)
		c = str(prev[c])
	return path


## Nearest nav point to a world position (same height band).
static func nearest_nav(p: Vector3) -> String:
	var best := ""
	var bd := INF
	for k in NAV:
		var q: Vector3 = NAV[k]
		if absf(q.y - p.y) > 1.6 and absf(q.y - (p.y - 0.8)) > 1.6:
			continue
		var d := Vector2(q.x - p.x, q.z - p.z).length()
		if d < bd:
			bd = d
			best = str(k)
	return best
