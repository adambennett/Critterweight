shader_type spatial;
// Neon tube / emissive sign element with an occasional cheap-sign flicker (Rooftop Glandco
// sign, sponsor lamps). flicker = 0 keeps it steady (flashing-reduction friendly).
render_mode cull_back;

uniform vec4 tube : source_color = vec4(1.0, 0.3, 0.75, 1.0);
uniform float intensity = 3.0;
uniform float flicker = 0.0;
uniform float seed = 0.0;
uniform float on = 1.0;

float hash(float x) { return fract(sin(x * 91.3 + seed * 13.7) * 43758.5453); }

void fragment() {
	float slot = floor(TIME * 9.0);
	float f = 1.0;
	if (flicker > 0.0) {
		float h = hash(slot);
		f = h < flicker * 0.12 ? 0.15 : (h < flicker * 0.2 ? 0.6 : 1.0);
	}
	float core = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 0.6);
	ALBEDO = tube.rgb * 0.25;
	EMISSION = tube.rgb * intensity * f * on * (0.6 + 0.4 * core);
	ROUGHNESS = 0.3;
}
