shader_type spatial;
// A furnace jet, with tongues advecting from the mouth (v=1) to its true cone edge (v=0).
// Painted orange survives the bright mat; only the inner ridges glow. No screen texture or light.
render_mode unshaded, cull_disabled, depth_draw_never, blend_premul_alpha, shadows_disabled, fog_disabled;

uniform float alpha = 1.0;
uniform float dissolve = 0.0;
uniform float inner = 0.0;
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	float a = UV.x * 6.2831853;
	float flow = UV.y * 25.0 + TIME * 15.0 + seed;
	float ripple = 0.88 + 0.07 * sin(flow + sin(a * 3.0)) + 0.04 * sin(flow * 1.7 - a * 2.0);
	VERTEX.xz *= ripple;
}

void fragment() {
	float angle = UV.x * 6.2831853;
	float travel = UV.y * 5.0 + TIME * 6.0 + seed;
	// Circular noise coordinates keep the closed cone's seam invisible.
	vec2 cylinder = vec2(cos(angle), sin(angle)) * 2.5;
	float broad = noise(cylinder + vec2(travel * 0.55, travel));
	float fine = noise(cylinder * 2.3 + vec2(-travel * 0.4, travel * 1.7));
	float n = broad * 0.72 + fine * 0.28;
	float tongues = smoothstep(0.28, 0.64, n + UV.y * 0.28);
	// Ragged tips, dense ignition, then holes and detached licks at the wide end.
	float tip = smoothstep(0.02, 0.3, UV.y + (broad - 0.5) * 0.4);
	float root = smoothstep(1.0, 0.93, UV.y);
	float alive = smoothstep(dissolve - 0.06, dissolve + 0.2, n + UV.y * 0.3);
	float a = clamp(tongues * tip * root * alive * alpha * (0.85 - inner * 0.12), 0.0, 1.0);
	float heat = clamp(n * 1.1 + UV.y * 0.35 + inner * 0.35, 0.0, 1.0);
	// Literal shader colours are linear: low green values keep the outer flame saturated orange.
	vec3 rim = vec3(0.42, 0.004, 0.0003);
	vec3 body = vec3(0.95, 0.065, 0.001);
	vec3 core = vec3(1.0, 0.48, 0.04);
	vec3 paint = mix(rim, body, smoothstep(0.3, 0.64, heat));
	paint = mix(paint, core, smoothstep(0.78, 1.0, heat));
	ALBEDO = paint * a + core * a * smoothstep(0.86, 1.0, heat) * 0.24;
	ALPHA = a;
}
