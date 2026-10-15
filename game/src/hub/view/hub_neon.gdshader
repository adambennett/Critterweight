shader_type spatial;
render_mode unshaded, cull_disabled;
// Neon tubes, lamp bulbs, screens: emissive colour (HDR, feeds the glow) whose brightness follows
// the time of day (instance uniform `neon`, set by HubView) with optional dead/flickering states
// per instance (the Main Floor's fluorescents until 12 upgrades are bought).

uniform vec4 color : source_color = vec4(0.55, 0.83, 0.15, 1.0);
uniform float energy = 2.5;
instance uniform float neon = 1.0;
instance uniform float lit = 1.0;          // 0 = dead tube, 1 = on
instance uniform float flicker = 0.0;      // 0..1 flicker amount

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	float f = 1.0;
	if (flicker > 0.0) {
		float k = floor(TIME * 9.0) + NODE_POSITION_WORLD.x * 13.1 + NODE_POSITION_WORLD.z * 7.7;
		f = mix(1.0, step(0.35, hash(k)) * 0.85 + 0.1, flicker);
	}
	float on = lit * f;
	ALBEDO = mix(color.rgb * 0.2, color.rgb * max(1.0, energy * neon), on);
}
