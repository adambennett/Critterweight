shader_type spatial;
// v0.9.17 ability VFX (docs/art/VFX.md): how one fx_puff particle looks. A camera-facing quad that
// keeps the particle's size and turns by its angle (INSTANCE_CUSTOM.x).
//   look: 0 cloud (steam, smoke, dust, mist), 1 flame tongue (tall, pointed, upward), 2 mote / bubble,
//         3 wisp (gale streak, spectral mist), 4 droplet, 5 four-point glint (scrap, sparkle)
// Premultiplied alpha: the particle colour is painted (`cover` = opacity, reads on the bright
// canvas) and glows on top (`glow_k`, HDR, bloomed by the arena's glow pass).
render_mode unshaded, cull_disabled, depth_draw_never, blend_premul_alpha, shadows_disabled, fog_disabled;

uniform int look = 0;
uniform float cover = 1.0;
uniform float glow_k = 0.0;
uniform float hot = 0.0;            // flames: white-hot core strength

varying float v_seed;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	float ang = look == 1 ? 0.0 : INSTANCE_CUSTOM.x;
	vec3 scl = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	mat4 mat_world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	mat_world = mat_world * mat4(vec4(cos(ang), -sin(ang), 0.0, 0.0), vec4(sin(ang), cos(ang), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	float stretch_y = look == 1 ? 1.7 : (look == 3 ? 0.55 : 1.0);
	float stretch_x = look == 3 ? 1.8 : 1.0;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world * mat4(vec4(scl.x * stretch_x, 0.0, 0.0, 0.0), vec4(0.0, scl.y * stretch_y, 0.0, 0.0), vec4(0.0, 0.0, scl.z, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_seed = INSTANCE_CUSTOM.w * 13.7 + INSTANCE_CUSTOM.x;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;                      // +y up on screen
	float r = length(p);
	float a = 0.0;
	vec3 col = COLOR.rgb;
	if (look == 1) {
		// tall pointed tongue: wide round base, tapering tip, flickering edges
		float w = mix(0.75, 0.04, clamp((p.y + 0.85) / 1.7, 0.0, 1.0));
		float n = vnoise(vec2(p.x * 3.0 + v_seed, p.y * 2.5 - TIME * 7.0));
		float edge = w * (0.75 + 0.5 * n) - abs(p.x);
		a = smoothstep(0.0, 0.18, edge) * smoothstep(-1.0, -0.6, p.y) * smoothstep(1.0, 0.55, p.y);
		float coreb = smoothstep(0.3, 0.0, abs(p.x)) * smoothstep(0.6, -0.5, p.y);
		col = mix(col, vec3(1.0, 0.95, 0.75), coreb * hot);
	} else if (look == 2) {
		a = smoothstep(1.0, 0.2, r);
		a *= a;
	} else if (look == 3) {
		float n = vnoise(vec2(p.x * 2.0 + v_seed + TIME * 0.6, p.y * 3.0));
		a = smoothstep(1.0, 0.0, r) * smoothstep(0.25, 0.75, n);
	} else if (look == 4) {
		a = smoothstep(0.95, 0.7, r);
		float hl = smoothstep(0.35, 0.0, length(p - vec2(-0.3, 0.35)));
		col = mix(col, vec3(1.0), hl * 0.8);
	} else if (look == 5) {
		float star = max(smoothstep(0.16, 0.0, abs(p.x)) * smoothstep(1.0, 0.0, abs(p.y)), smoothstep(0.16, 0.0, abs(p.y)) * smoothstep(1.0, 0.0, abs(p.x)));
		a = max(star, smoothstep(0.45, 0.0, r));
	} else {
		// cloud: soft round mass with a lumpy edge
		float n = vnoise(p * 2.2 + vec2(v_seed, v_seed * 0.7)) * 0.5 + vnoise(p * 4.7 + v_seed) * 0.25;
		a = smoothstep(1.0, 0.25, r + (n - 0.38) * 0.7);
		col *= 0.85 + 0.3 * (1.0 - r);
	}
	a = clamp(a * COLOR.a, 0.0, 1.0);
	ALBEDO = col * a * cover + col * a * glow_k;
	ALPHA = a * cover;
}
