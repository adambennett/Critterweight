shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Harbor water for the Loading Dock and the Pier: flat, slightly transparent, clean-edged
// ripple bands (no noise textures), brighter where the dock's shadow is not.

uniform vec4 deep : source_color = vec4(0.09, 0.2, 0.26, 1.0);
uniform vec4 shallow : source_color = vec4(0.2, 0.42, 0.48, 1.0);
uniform vec4 foam : source_color = vec4(0.82, 0.9, 0.9, 1.0);
uniform float time_offset = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float w1 = sin(p.x * 0.9 + time_offset * 0.8) * sin(p.y * 0.7 - time_offset * 0.6);
	float w2 = sin((p.x + p.y) * 1.7 - time_offset * 1.3);
	float bands = step(0.82, w1 * 0.6 + w2 * 0.4);
	float shore = clamp(1.0 - abs(world_pos.z + 18.6) / 3.0, 0.0, 1.0);
	vec3 c = mix(deep.rgb, shallow.rgb, 0.35 + 0.25 * w1);
	c = mix(c, foam.rgb, bands * 0.35 + step(0.75, shore * (0.6 + 0.4 * w2)) * 0.25);
	ALBEDO = c;
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
