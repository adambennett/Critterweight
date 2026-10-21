class_name MoveCard
extends CombatPrompt
## FightHud card of one equipped Movesets move: its input glyph with the cooldown veil and seconds
## (CombatPrompt), the move's name, a HOLD / HOLD+AIM tag for held moves, the charges left (×2) for
## multi-charge moves, a stamina-short state while the fighter cannot afford it (tinted, with the
## word TIRED: colour is never the only cue) and a flash when a press was denied (Fighter
## `move_denied`). `update_from(fighter)` reads only replicated values (loadout, cooldown_left,
## charges_left, stamina, the rules), so a NetHudMirror fighter renders exactly the same card.

const FLASH_TIME := 0.35
const SHORT_TINT := Color(1.0, 0.5, 0.42)

var pool_id := ""
var slot := ""                      ## loadout slot "m1".."m4"
var max_charges := 1
var charges := 1
var affordable := true
var locked := false                 ## the rules switched specials off ("Abilities" off)
var _hold_chip: PanelContainer = null
var _charges_label: Label
var _state_label: Label
var _flash := 0.0
var _flash_color := Color.WHITE


func _init(action: String = "", pm: PoolMove = null, slot_ := "", glyph_du := 40.0) -> void:
	super([action] if action != "" else [], pm.display_name if pm else "", glyph_du)
	name = "MoveCard_" + slot_
	slot = slot_
	if pm == null:
		return
	pool_id = pm.id
	max_charges = maxi(1, pm.charges)
	charges = max_charges
	var tag := MovesUi.hold_tag(pm)
	if tag != "":
		_hold_chip = MovesUi.chip(tag, UiTheme.WARM, 22)
		_hold_chip.name = "HoldTag"
		add_child(_hold_chip)
	_charges_label = _small("", UiTheme.GOLD_HI)
	_charges_label.name = "Charges"
	_charges_label.visible = max_charges > 1
	add_child(_charges_label)
	_state_label = _small("", SHORT_TINT)
	_state_label.name = "MoveState"
	_state_label.visible = false
	add_child(_state_label)
	tooltip_text = "%s: %s" % [pm.display_name, MovesUi.how_to_use(pm)]


func _small(text_: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text_
	l.add_theme_font_override("font", UiTheme.font("label"))
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.08))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## The hold tag shown on the card ("" for a tap move).
func hold_text() -> String:
	if _hold_chip == null:
		return ""
	return (_hold_chip.get_child(0) as Label).text


## Refreshes the card from the fighter holding the move (local or mirrored) under the match's
## `rules` (a mirror fighter has no sim of its own: FightHud passes its sim's rules).
func update_from(f: Fighter, rules: Dictionary = {}) -> void:
	var pm := f.slot_move(slot)
	if pm == null:
		return
	max_charges = maxi(1, f.slot_max_charges(slot))
	charges = clampi(int(f.charges_left.get(slot, max_charges)), 0, max_charges)
	var has_charge := charges > 0
	var left := 0.0 if has_charge else float(f.cooldown_left.get(slot, 0.0))
	var abilities_on := not bool(f.mods.get("no_abilities", false)) and bool(rules.get("abilities", true))
	locked = not abilities_on and not pm.role in ["basic", "heavy"]
	# a press below half the move's stamina is denied (Fighter._try_moves); basics always start
	affordable = pm.role == "basic" or f.stamina >= pm.stamina_cost() * 0.5
	set_state(left, maxf(0.01, f.slot_cooldown(slot)), has_charge and not locked, charges, max_charges, affordable)


## The card's look for a cooldown state (seconds left of `total`), the charges and whether the
## fighter can afford the move now.
func set_state(seconds: float, total: float, usable: bool, charges_left: int, max_c: int, can_afford: bool) -> void:
	charges = charges_left
	max_charges = max_c
	affordable = can_afford
	set_cooldown(seconds, total, usable)
	if _charges_label:
		_charges_label.visible = max_charges > 1
		_charges_label.text = "×%d" % charges
		_charges_label.add_theme_color_override("font_color", UiTheme.GOLD_HI if charges > 0 else UiTheme.MUTED)
	var short := usable and not can_afford
	if _state_label:
		_state_label.visible = short or locked
		_state_label.text = "OFF" if locked else "TIRED"
	if short:
		_label.modulate = SHORT_TINT
	for g in _glyph_box.get_children():
		(g as CanvasItem).self_modulate = SHORT_TINT if short else Color.WHITE
	_apply_flash()


## A press that could not start: red for stamina, grey for the cooldown. The flash belongs to the
## card (FightHud's tutorial highlight resets the card's own modulate every frame).
func flash_denied(why: String) -> void:
	_flash_color = Color(1.0, 0.3, 0.25) if why == "stamina" else Color(0.7, 0.7, 0.78)
	_flash = FLASH_TIME
	set_process(true)
	_apply_flash()


func is_flashing() -> bool:
	return _flash > 0.0


func _process(dt: float) -> void:
	if _flash <= 0.0:
		set_process(false)
		return
	_flash = maxf(0.0, _flash - dt)
	_apply_flash()


func _apply_flash() -> void:
	var k := clampf(_flash / FLASH_TIME, 0.0, 1.0)
	_glyph_box.modulate = Color.WHITE.lerp(_flash_color, k)
	if _hold_chip:
		_hold_chip.modulate = Color.WHITE.lerp(_flash_color, k)
	if k > 0.0:
		_label.modulate = _label.modulate.lerp(_flash_color, k)
