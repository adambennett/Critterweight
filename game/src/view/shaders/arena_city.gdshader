shader_type spatial;
// Skyline / building facades with procedurally lit windows (UV in metres on the faces).
// Used for the Rooftop's bay skyline and the cannery facade below the roof edge.

uniform vec4 wall : source_color = vec4(0.08, 0.09, 0.13, 1.0);
uniform vec4 lit_a : source_color = vec4(1.0, 0.8, 0.45, 1.0);
uniform vec4 lit_b : source_color = vec4(0.55, 0.8, 1.0, 1.0);
uniform vec2 window = vec2(1.6, 2.4);
uniform float lit_ratio = 0.35;
uniform float glow = 1.6;
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 3.17) * 43758.5453); }

void fragment() {
	vec2 g = UV / window;
	vec2 c = floor(g);
	vec2 f = fract(g);
	float frame = step(0.18, f.x) * step(f.x, 0.82) * step(0.22, f.y) * step(f.y, 0.78);
	float h = hash(c);
	float lit = step(1.0 - lit_ratio, h) * frame;
	vec3 lc = mix(lit_a.rgb, lit_b.rgb, step(0.7, hash(c + 7.0)));
	float up = abs(NORMAL.y) > 0.9 ? 0.0 : 1.0;
	ALBEDO = wall.rgb * (0.85 + hash(vec2(c.x, 0.0)) * 0.3);
	EMISSION = lc * lit * glow * up * (0.6 + 0.4 * hash(c + 2.0));
	ROUGHNESS = 0.9;
}
