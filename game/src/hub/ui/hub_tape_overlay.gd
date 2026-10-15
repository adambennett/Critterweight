extends Control
## The 1973 tape (secret #5): an old broadcast look over a 40 s AI-vs-AI replay — sepia, grain,
## scan lines and a vignette — the challenger drawn as a silhouette, and Barnaby's "Vintage
## Bellows" calls (the line pack the tape unlocks). Skippable back to the booth.

const LINES := [
	"Ladies, gentlemen, and assorted critters... in the year of our Lord nineteen-seventy-three...",
	"In the shell: the snapping sensation of the waterfront, SNAPPINGTON!",
	"And her challenger... nobody remembers his name! Nobody DARES!",
	"Oh! The gavel! She brought the GAVEL!",
	"Folks, I have a full head of hair and I am losing it!",
	"The Cannery has never been this LOUD!",
	"Somebody tell my mother I called it first!",
]

var scene: MatchScene
var _t := 0.0
var _next_line := 1.0
var _line := 0
var _left := false


func bind(s: MatchScene) -> void:
	scene = s
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var film := ColorRect.new()
	film.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	film.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 sepia = vec3(l * 1.07, l * 0.86, l * 0.62);
	float grain = (hash(SCREEN_UV * 900.0 + vec2(TIME * 37.0, TIME * 11.0)) - 0.5) * 0.12;
	float scan = 0.94 + 0.06 * sin(SCREEN_UV.y * 900.0);
	vec2 d = UV - 0.5;
	float vig = smoothstep(0.85, 0.35, length(d * vec2(1.3, 1.0)));
	COLOR = vec4((sepia + grain) * scan * vig, 1.0);
}
"""
	sm.shader = sh
	film.material = sm
	add_child(film)
	var m := UiTheme.margin(48, 40, 48)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(m)
	var col := UiTheme.vbox(UiTheme.GAP_S)
	m.add_child(col)
	var cap := UiTheme.panel("PanelChip", 12.0)
	cap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var hb := UiTheme.hbox(UiTheme.GAP_M)
	hb.add_child(UiTheme.label("THE CANNERY · 1973 · TITLE FIGHT", "BodyStrong"))
	var back := ButtonPrompt.new(["scoreboard"], "Back to the booth", 36.0)
	back.pressed.connect(_leave)
	hb.add_child(back)
	cap.add_child(hb)
	col.add_child(cap)
	# the challenger is a silhouette (rim light only)
	if scene.views.size() > 1 and scene.views[1] != null:
		var cv: CreatureView = scene.views[1]
		for mat in cv._materials:
			mat.set_shader_parameter("tint", Color(0.02, 0.02, 0.03))
			mat.set_shader_parameter("rim_strength", 0.9)


func _process(dt: float) -> void:
	_t += dt
	if _t >= _next_line and _line < LINES.size():
		Audio.say("barnaby", str(LINES[_line]), 75)
		_line += 1
		_next_line = _t + 5.5


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("scoreboard") and App.top_screen() == null:
		get_viewport().set_input_as_handled()
		_leave()


func _leave() -> void:
	if _left:
		return
	_left = true
	Cannery.enter({"spot": "booth", "from": "tape"})
