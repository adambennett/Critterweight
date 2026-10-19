class_name MartialControls
## Layout descriptions shared by the fighter sheet and HUD; core bindings stay untouched.
const MAP := {
	"mma_lh": FighterInput.LIGHT, "mma_rh": FighterInput.HEAVY,
	"mma_ll": FighterInput.MMA_LL, "mma_rl": FighterInput.MMA_RL,
	"mma_mod1": FighterInput.MMA_MOD1, "mma_mod2": FighterInput.MMA_MOD2, "mma_mod3": FighterInput.MMA_MOD3,
	"mma_guard": FighterInput.GUARD, "mma_dodge": FighterInput.DODGE, "mma_grab": FighterInput.GRAB,
	"mma_stance": FighterInput.MMA_STANCE, "mma_check": FighterInput.MMA_CHECK,
	"mma_ability1": FighterInput.AB1, "mma_ability2": FighterInput.AB2, "mma_juice": FighterInput.JUICE,
	"mma_target": FighterInput.TARGET, "mma_tag": FighterInput.TAG, "mma_taunt": FighterInput.TAUNT,
}
static func action(slot: String, c: CreatureDef) -> String:
	return "mma_" + slot if c and c.tags.has("martial") and slot in ["ability1", "ability2", "juice"] else slot
static func description() -> String:
	return "Cage Rules layout: forward/back closes or opens distance to your opponent.\nFour limb buttons select left hand, right hand, left leg, right leg. No modifier: uppercuts / lead teep / rear knee. Hold Hooks for hooks / body kicks; Straights for jab-cross / head kicks; Overhands for overhands / low kicks.\nSwitch stance changes your lead side. Hold Guard + Overhands for a body shell. Check lifts the lead shin. Slip dodges; double-tap Guard to shove.\nTakedown catches a clinch; limb buttons pummel, Takedown + direction throws. Opponents escape using the normal grab rules. Full Cage Rules ground positions and submissions do not run inside Critterweight's multi-fighter bouts.\nKeyboard: U I J K limbs; Q E R modifiers; L guard; Shift slip; Space grapple; X stance; O check.\nController: X Y A B limbs; LB RB LT modifiers; RT guard; RS slip; LS grapple; D-left stance; D-down check.\nNew abilities: F1 / D-up, F2 / D-right, release V / View for JUICE. Tab switches target; G tags partners; T touches gloves. Hold View + D-left to switch target, View + D-down to tag, or View + D-up to taunt on controller."
