shader_type spatial;
// Creature skin (docs/ART_DIRECTION.md): toon-ramped lighting over vertex-colour albedo,
// readable rim light, hit flash, JUICE glow, status tint and localized cosmetic bruises.
// Bruise points are WORLD-space positions updated each frame by CreatureView.

uniform vec4 tint : source_color = vec4(1.0);
uniform float roughness_v : hint_range(0.0, 1.0) = 0.65;
uniform float metallic_v : hint_range(0.0, 1.0) = 0.0;
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float rim_strength = 0.35;
uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float juice = 0.0;
uniform vec4 juice_color : source_color = vec4(1.0, 0.55, 0.1, 1.0);
uniform vec4 status_color : source_color = vec4(0.0);
uniform vec4 bruises[8];
uniform vec4 bruise_color : source_color = vec4(0.45, 0.08, 0.18, 1.0);
uniform float time_offset = 0.0;
// Forged models store an emissive strength in vertex alpha (COLOR.a) on glowing surfaces
// (furnace door, barnacles, coil, headlamp...). vertex_glow scales it: 0 = off (fallback
// meshes / non-glowing surfaces), 0.3..1.0 = driven by Hype (CreatureView.hype).
uniform float vertex_glow = 0.0;
// Cosmetic colour variant of the glowing surfaces (e.g. Stoke's white-hot "Sizzle"): rgb = target,
// a = amount. 0 keeps the model's own colours.
uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = COLOR.rgb * tint.rgb;
	vec3 glow_rgb = mix(COLOR.rgb, glow_color.rgb, glow_color.a);
	if (vertex_glow > 0.0 && glow_color.a > 0.0) {
		base = mix(base, glow_color.rgb, clamp(COLOR.a * glow_color.a * 1.4, 0.0, 1.0));
	}
	float bruise = 0.0;
	for (int i = 0; i < 8; i++) {
		vec4 b = bruises[i];
		if (b.w > 0.001) {
			float d = distance(world_pos, b.xyz);
			bruise = max(bruise, (1.0 - smoothstep(0.02, 0.09 + b.w * 0.06, d)) * clamp(b.w, 0.0, 1.0));
		}
	}
	base = mix(base, bruise_color.rgb * (0.6 + 0.4 * base), bruise * 0.75);
	if (status_color.a > 0.0) {
		float pulse = 0.5 + 0.5 * sin(TIME * 7.0 + time_offset);
		base = mix(base, status_color.rgb, status_color.a * (0.25 + 0.2 * pulse));
	}
	ALBEDO = base;
	ROUGHNESS = roughness_v;
	METALLIC = metallic_v;
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - ndv, 3.0);
	vec3 emit = rim_color.rgb * rim * rim_strength;
	emit += flash_color.rgb * flash * 1.6;
	emit += glow_rgb * COLOR.a * vertex_glow * 2.2;
	if (juice > 0.0) {
		float jp = 0.6 + 0.4 * sin(TIME * 9.0 + time_offset);
		emit += juice_color.rgb * juice * (0.25 + rim * 1.2) * jp;
	}
	EMISSION = emit;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float ramp = smoothstep(-0.08, 0.1, ndl) * 0.72 + smoothstep(0.45, 0.6, ndl) * 0.28;
	DIFFUSE_LIGHT += ramp * ATTENUATION * LIGHT_COLOR / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float spec = pow(clamp(dot(NORMAL, h), 0.0, 1.0), mix(8.0, 96.0, 1.0 - roughness_v));
	SPECULAR_LIGHT += smoothstep(0.45, 0.55, spec) * ATTENUATION * LIGHT_COLOR * (1.0 - roughness_v) * 0.35;
}
