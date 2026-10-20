shader_type spatial;
// Creature skin (docs/ART_DIRECTION.md §4, docs/ART_PIPELINE.md §5): toon-ramped lighting over
// vertex-colour albedo, readable rim light, hit flash, JUICE glow, status tint and localized cosmetic
// bruises. Bruise points are WORLD-space positions updated each frame by CreatureView.
// v0.9.17 finish pass: per-surface material classes (material_kind) with their own lighting response
// (wrap-lit hide with a warm terminator, matte cloth, metal with a fake environment reflection,
// glossy eyes with a crisp catchlight, jelly with a soft inner glow, lacquered shell with a clearcoat
// highlight, spectral glow surfaces), cool shadow sides, and animated emission per glow_mode (fire
// flicker, bioluminescent pulse, ghostly shimmer, steady lamp). Same uniforms as before plus these;
// a material that sets none of them looks like the v0.9.16 shader.

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
// v0.9.17
uniform int material_kind = 0;   // 0 hide/skin, 1 cloth, 2 metal, 3 eye, 4 jelly, 5 lacquer (shell, enamel, glass), 6 spectral
uniform int glow_mode = 0;       // 0 steady, 1 flicker (fire), 2 pulse (charge, bioluminescence), 3 shimmer (spectral), 4 lamp
uniform float finish = 1.0;      // 0 = the v0.9.16 look (legacy skins keep their original finish)
uniform vec4 terminator_color : source_color = vec4(1.0, 0.42, 0.28, 1.0);   // warm light bleeding past the shadow line
uniform vec4 shadow_tint : source_color = vec4(0.17, 0.19, 0.27, 1.0);        // ART_DIRECTION: shadows are cool, never black
uniform vec4 env_top : source_color = vec4(1.0, 0.9, 0.74, 1.0);              // fake reflection: the arena lights above
uniform vec4 env_bottom : source_color = vec4(0.18, 0.16, 0.15, 1.0);         // ... and the floor below

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float glow_wave(float t) {
	if (glow_mode == 1) {
		// fire: two incommensurate flickers plus a slow breath, varying along the surface
		return 0.74 + 0.16 * sin(t * 13.1 + world_pos.y * 9.0) + 0.1 * sin(t * 23.7 + world_pos.x * 7.0) + 0.08 * sin(t * 2.1);
	} else if (glow_mode == 2) {
		return 0.72 + 0.28 * (0.5 + 0.5 * sin(t * 3.4));
	} else if (glow_mode == 3) {
		return 0.62 + 0.38 * (0.5 + 0.5 * sin(t * 2.2 + world_pos.y * 5.5 + 1.7 * sin(t * 1.3 + world_pos.x * 3.0)));
	} else if (glow_mode == 4) {
		return 1.08;
	}
	return 1.0;
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
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 3.0);
	vec3 extra = vec3(0.0);
	float rough = roughness_v;
	float metal = metallic_v;
	if (finish > 0.0) {
		vec3 r = (INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).xyz;
		vec3 env = mix(env_bottom.rgb, env_top.rgb, smoothstep(-0.25, 0.55, r.y));
		if (material_kind == 2) {
			// metal: darker albedo, the "reflection" of the arena carries the brightness
			extra += env * base * (0.55 - 0.3 * rough) * finish;
			base *= mix(1.0, 0.72, finish);
			metal = max(metal, 0.5 * finish);
			rough = mix(rough, min(rough, 0.45), finish);
		} else if (material_kind == 5) {
			extra += env * (0.06 + 0.22 * fres) * finish;
			rough = mix(rough, min(rough, 0.3), finish);
		} else if (material_kind == 3) {
			extra += env * 0.08 * fres * finish;
			rough = mix(rough, 0.12, finish);
		} else if (material_kind == 4) {
			// jelly: light seems to come through the thin edges and from inside
			extra += base * (0.18 + 0.35 * fres) * finish;
			rough = mix(rough, 0.18, finish);
		} else if (material_kind == 6) {
			extra += base * (0.25 + 0.6 * fres) * finish;
		} else if (material_kind == 1) {
			// cloth: a soft sheen at grazing angles
			extra += base * 0.1 * fres * finish;
			rough = mix(rough, max(rough, 0.85), finish);
		}
		// cool shadow sides: a touch of ambient tint so unlit areas never go muddy
		extra += shadow_tint.rgb * 0.05 * finish;
	}
	ALBEDO = base;
	ROUGHNESS = rough;
	METALLIC = metal;
	vec3 emit = rim_color.rgb * fres * rim_strength + extra;
	emit += flash_color.rgb * flash * 1.6;
	float t = TIME + time_offset;
	emit += glow_rgb * COLOR.a * vertex_glow * 2.2 * mix(1.0, glow_wave(t), finish);
	if (juice > 0.0) {
		float jp = 0.6 + 0.4 * sin(TIME * 9.0 + time_offset);
		emit += juice_color.rgb * juice * (0.25 + fres * 1.2) * jp;
	}
	EMISSION = emit;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// organic surfaces wrap the light a little past the terminator (soft, fleshy), cloth less
	float wrap = 0.0;
	if (finish > 0.0) {
		if (material_kind == 0) { wrap = 0.22; } else if (material_kind == 4) { wrap = 0.45; } else if (material_kind == 1) { wrap = 0.12; }
		wrap *= finish;
	}
	float ndl_w = (ndl + wrap) / (1.0 + wrap);
	float ramp = smoothstep(-0.08, 0.1, ndl_w) * 0.72 + smoothstep(0.45, 0.6, ndl_w) * 0.28;
	vec3 lit = ATTENUATION * LIGHT_COLOR;
	vec3 diffuse = ramp * lit;
	if (finish > 0.0 && (material_kind == 0 || material_kind == 4)) {
		// a warm band where light turns to shadow (painted subsurface)
		float term = smoothstep(-0.25, 0.02, ndl) * (1.0 - smoothstep(0.02, 0.3, ndl));
		diffuse += lit * terminator_color.rgb * term * 0.22 * finish;
	}
	DIFFUSE_LIGHT += diffuse / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
	float spec = pow(ndh, mix(8.0, 96.0, 1.0 - roughness_v));
	float band = smoothstep(0.45, 0.55, spec);
	float strength = (1.0 - roughness_v) * 0.35;
	vec3 spec_col = vec3(1.0);
	if (finish > 0.0) {
		if (material_kind == 2) {
			band = smoothstep(0.2, 0.65, pow(ndh, mix(16.0, 120.0, 1.0 - roughness_v)));
			strength = mix(strength, 0.85, finish);
			spec_col = mix(vec3(1.0), ALBEDO * 1.6 + 0.15, 0.7 * finish);
		} else if (material_kind == 3) {
			band = smoothstep(0.55, 0.6, pow(ndh, 260.0));
			strength = mix(strength, 1.4, finish);
		} else if (material_kind == 5) {
			band = max(band * 0.5, smoothstep(0.52, 0.58, pow(ndh, 110.0)));
			strength = mix(strength, 0.75, finish);
		} else if (material_kind == 4) {
			band = smoothstep(0.42, 0.5, pow(ndh, 70.0));
			strength = mix(strength, 0.7, finish);
		} else if (material_kind == 0) {
			// soft sheen on hide, not plastic
			band = smoothstep(0.3, 0.7, spec) * 0.6;
		}
	}
	SPECULAR_LIGHT += band * lit * strength * spec_col;
}
