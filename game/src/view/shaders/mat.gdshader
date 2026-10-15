shader_type spatial;
// Canvas fight mat: woven grain, scuffs, the painted octagon border, centre logo texture.

uniform vec4 base_color : source_color = vec4(0.83, 0.8, 0.74, 1.0);
uniform vec4 line_color : source_color = vec4(0.72, 0.16, 0.12, 1.0);
uniform sampler2D logo : source_color, filter_linear_mipmap, repeat_disable;
uniform float logo_size = 3.4;
uniform float apothem = 5.0;
uniform float border = 0.35;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

varying vec3 local_pos;
void vertex() { local_pos = VERTEX; }

void fragment() {
	vec2 p = local_pos.xz;
	float grain = noise(p * 38.0) * 0.06 + noise(p * 3.0) * 0.07;
	vec3 col = base_color.rgb * (0.94 + grain);
	// octagon distance (apothem metric)
	float oct = 0.0;
	for (int i = 0; i < 8; i++) {
		float a = 6.2831853 * float(i) / 8.0 + 0.3926991;
		oct = max(oct, dot(p, vec2(cos(a), sin(a))));
	}
	float edge = smoothstep(apothem - border - 0.02, apothem - border + 0.02, oct);
	col = mix(col, line_color.rgb * (0.9 + grain), edge);
	vec2 luv = vec2(-p.x, p.y) / logo_size + 0.5;
	if (luv.x > 0.0 && luv.x < 1.0 && luv.y > 0.0 && luv.y < 1.0) {
		vec4 l = texture(logo, luv);
		col = mix(col, l.rgb, l.a * 0.92);
	}
	float scuff = smoothstep(0.62, 0.9, noise(p * 1.7 + 4.0)) * 0.12;
	col *= 1.0 - scuff;
	ALBEDO = col;
	ROUGHNESS = 0.92;
}
