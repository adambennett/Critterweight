shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// The Cannery's level surfaces (docs/HUB_SYSTEMS.md §6). One material for every batched static
// mesh: albedo = vertex colour, UV.x = pattern id, UV.y = 1 for surfaces the camera may see
// through (walls, furniture) and 0 for floors. Patterns are procedural, world-space and
// clean-edged (ART_DIRECTION: grit, not grime). The see-through cylinder dithers away anything
// between the camera and the player so walls never hide your fighter; the shadow pass keeps it
// (its camera is the light, not cut_camera).

uniform vec3 cut_player = vec3(0.0, -1000.0, 0.0);
uniform vec3 cut_camera = vec3(0.0, 0.0, 0.0);
uniform float cut_radius = 2.4;
uniform float roughness_v : hint_range(0.0, 1.0) = 0.82;
uniform vec4 rim_tint : source_color = vec4(1.0, 0.92, 0.8, 1.0);
uniform float rim_strength = 0.08;
uniform float wear = 1.0;            // dirt/wear amount (lower after the hub gets fixed up)

varying vec3 world_pos;
varying vec3 world_nrm;
varying float pattern_id;
varying float cuttable;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	pattern_id = UV.x;
	cuttable = UV.y;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float bayer4(vec2 fc) {
	int x = int(mod(fc.x, 4.0));
	int y = int(mod(fc.y, 4.0));
	int idx = x + y * 4;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[idx] + 0.5) / 16.0;
}

// line mask: 1 on a grout/mortar line of width w (in cell units) of a grid with cell size c
float grid_line(vec2 uv, vec2 c, float w) {
	vec2 g = fract(uv / c);
	vec2 d = min(g, 1.0 - g) * c;
	return 1.0 - step(w, min(d.x, d.y));
}

void fragment() {
	// ---- see-through cylinder (main camera only) ----
	if (cuttable > 0.5 && distance(CAMERA_POSITION_WORLD, cut_camera) < 0.5) {
		vec3 ab = cut_player - cut_camera;
		float len = length(ab);
		if (len > 0.5) {
			vec3 dir = ab / len;
			vec3 ap = world_pos - cut_camera;
			float t = dot(ap, dir);
			if (t > 0.0 && t < len - 0.45) {
				float d = length(ap - dir * t);
				float r = cut_radius * clamp((len - t) / 1.6, 0.35, 1.0);
				if (d < r) {
					float edge = clamp((r - d) / 0.55, 0.0, 1.0);
					if (edge > bayer4(FRAGCOORD.xy) * 0.999) {
						discard;
					}
				}
			}
		}
	}
	vec3 base = COLOR.rgb;
	vec3 n = normalize(world_nrm);
	// surface coordinates: floors use XZ, walls use the horizontal axis along the wall + Y
	vec2 suv = abs(n.y) > 0.6 ? world_pos.xz : (abs(n.x) > abs(n.z) ? world_pos.zy : world_pos.xy);
	int pid = int(pattern_id + 0.5);
	float shade = 1.0;
	if (pid == 1) {            // brick (running bond)
		vec2 b = suv / vec2(0.5, 0.22);
		b.x += step(1.0, mod(floor(b.y), 2.0)) * 0.5;
		vec2 g = fract(b);
		float mortar = 1.0 - step(0.06, min(min(g.x, 1.0 - g.x) * 2.27, min(g.y, 1.0 - g.y)));
		float tone = hash12(floor(b)) * 0.14;
		shade = mix(0.92 + tone, 0.62, mortar);
	} else if (pid == 2) {     // white tiles
		shade = mix(1.0, 0.8, grid_line(suv, vec2(0.4), 0.015));
	} else if (pid == 3) {     // blue tiles (smaller)
		shade = mix(1.0 - hash12(floor(suv / 0.3)) * 0.06, 0.78, grid_line(suv, vec2(0.3), 0.012));
	} else if (pid == 4) {     // planks
		vec2 p = suv / vec2(1.6, 0.18);
		p.x += hash12(vec2(floor(p.y), 3.0)) * 3.0;
		vec2 g = fract(p);
		float seam = 1.0 - step(0.05, min(g.y, 1.0 - g.y) * 1.0);
		float joint = 1.0 - step(0.012, min(g.x, 1.0 - g.x));
		shade = mix(0.9 + hash12(floor(p)) * 0.14, 0.66, max(seam, joint));
	} else if (pid == 5) {     // concrete slabs with clean-edged stains
		float seams = grid_line(suv, vec2(2.4), 0.012);
		float stain = step(0.72, vnoise(suv * 0.45 + 7.0)) * 0.08 * wear;
		shade = mix(0.97 - stain, 0.78, seams);
	} else if (pid == 6) {     // plaster with a scuffed dado band near the floor
		float band = 1.0 - step(1.05, world_pos.y);
		shade = 1.0 - band * 0.12 * wear - step(0.8, vnoise(suv * 1.3)) * 0.04 * wear;
	} else if (pid == 7) {     // corrugated metal
		shade = 0.84 + 0.16 * smoothstep(-1.0, 1.0, sin(suv.x * 28.0));
	} else if (pid == 8) {     // gym mats / checker
		vec2 c = floor(suv / 1.2);
		shade = mix(1.0, 0.86, mod(c.x + c.y, 2.0)) * mix(1.0, 0.75, grid_line(suv, vec2(1.2), 0.02));
	} else if (pid == 9) {     // hazard stripes
		float s = step(0.5, fract((suv.x + suv.y) * 1.6));
		base = mix(vec3(0.1, 0.09, 0.08), vec3(0.95, 0.76, 0.12), s);
	} else if (pid == 10) {    // wood floor (wide boards)
		vec2 p2 = suv / vec2(2.2, 0.24);
		p2.x += hash12(vec2(floor(p2.y), 9.0)) * 4.0;
		vec2 g2 = fract(p2);
		float seam2 = 1.0 - step(0.04, min(g2.y, 1.0 - g2.y));
		shade = mix(0.88 + hash12(floor(p2)) * 0.16, 0.62, seam2);
	} else if (pid == 11) {    // painted line / emissive-ish trims keep their colour
		shade = 1.0;
	} else {
		shade = 0.96 + vnoise(suv * 0.7) * 0.06;
	}
	ALBEDO = base * shade;
	ROUGHNESS = roughness_v;
	METALLIC = 0.0;
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	EMISSION = rim_tint.rgb * pow(1.0 - ndv, 4.0) * rim_strength * base;
}
