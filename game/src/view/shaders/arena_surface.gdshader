shader_type spatial;
// Procedural arena surfaces (ART_DIRECTION §4): desaturated low-frequency floors, clean-edged
// painted stains/chips (never noisy grime), metre-based coordinates so every surface tiles at
// the same scale. One uber-shader keeps every arena in the same material language.
// mode: 0 canvas · 1 concrete · 2 steel tread plates · 3 tar & gravel · 4 wet planks ·
//       5 riveted steel · 6 brick · 7 ribbed rubber · 8 painted metal (chipped) · 9 crate wood

uniform int mode = 0;
uniform vec4 color_a : source_color = vec4(0.91, 0.89, 0.81, 1.0);
uniform vec4 color_b : source_color = vec4(0.55, 0.55, 0.53, 1.0);
uniform vec4 color_c : source_color = vec4(0.17, 0.18, 0.2, 1.0);
uniform vec4 accent : source_color = vec4(0.55, 0.83, 0.15, 1.0);
uniform float scale = 1.0;
uniform float wet = 0.0;
uniform float rough = 0.8;
uniform float metal = 0.0;
uniform bool use_uv = false;          // UV is in metres (walls / props); otherwise world XZ
uniform sampler2D logo : source_color, filter_linear_mipmap, repeat_disable;
uniform float logo_size = 0.0;
uniform float apothem = 0.0;          // canvas: octagon apothem for the painted border (0 = none)
uniform float border = 0.45;
uniform vec4 border_color : source_color = vec4(0.11, 0.13, 0.2, 1.0);
uniform vec4 stripe_color : source_color = vec4(0.55, 0.83, 0.15, 1.0);
uniform vec2 cell = vec2(4.0, 4.0);   // steel plates / concrete joints / panels
uniform vec2 grid_origin = vec2(-6.0, -6.0);
uniform float seam = 0.24;            // hazard-stripe band between steel plates
uniform vec4 seam_a : source_color = vec4(0.97, 0.88, 0.29, 1.0);
uniform vec4 seam_b : source_color = vec4(0.12, 0.12, 0.14, 1.0);
uniform float seed = 0.0;

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.13) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
// clean-edged blotch mask (painted stains, chips) from low-frequency noise
float blotch(vec2 p, float freq, float thr) { return smoothstep(thr, thr + 0.025, noise(p * freq) * 0.65 + noise(p * freq * 2.3 + 7.1) * 0.35); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = (use_uv ? UV : wpos.xz) / max(scale, 0.001);
	vec3 col = color_a.rgb;
	float r = rough;
	float m = metal;
	vec3 emit = vec3(0.0);
	if (mode == 0) {
		// canvas: faint weave, low-frequency tone, painted octagon border + pinstripe, logo, scuffs
		float weave = (abs(sin(p.x * 140.0)) * 0.5 + abs(sin(p.y * 140.0)) * 0.5) * 0.025;
		col *= 0.95 + noise(p * 0.35) * 0.07 - weave;
		if (apothem > 0.0) {
			float oct = 0.0;
			for (int i = 0; i < 8; i++) {
				float a = 6.2831853 * float(i) / 8.0;
				oct = max(oct, dot(wpos.xz, vec2(cos(a), sin(a))));
			}
			float band = smoothstep(apothem - border - 0.015, apothem - border + 0.015, oct);
			float pin = smoothstep(apothem - border - 0.16, apothem - border - 0.145, oct) * (1.0 - smoothstep(apothem - border - 0.075, apothem - border - 0.06, oct));
			col = mix(col, border_color.rgb, band);
			col = mix(col, stripe_color.rgb, pin);
		}
		if (logo_size > 0.0) {
			vec2 luv = vec2(wpos.x, wpos.z) / logo_size + 0.5;
			if (luv.x > 0.0 && luv.x < 1.0 && luv.y > 0.0 && luv.y < 1.0) {
				vec4 l = texture(logo, luv);
				col = mix(col, l.rgb, l.a * 0.9);
			}
		}
		col *= 1.0 - blotch(p + 3.0, 0.45, 0.68) * 0.09;
		r = 0.92;
	} else if (mode == 1) {
		// concrete: tone plates, expansion joints, painted stains, rust bleed, wet sheen
		vec2 g = (wpos.xz - grid_origin) / cell;
		vec2 fj = abs(fract(g) - 0.5) * cell;
		float joint = 1.0 - smoothstep(0.0, 0.035, min(cell.x * 0.5 - fj.x, cell.y * 0.5 - fj.y));
		float tone = noise(floor(g) * 1.7) * 0.06 + noise(p * 0.6) * 0.05;
		col = mix(color_a.rgb, color_b.rgb, 0.35 + tone * 3.0);
		col *= 1.0 - blotch(p, 0.5, 0.66) * 0.12;
		col = mix(col, color_c.rgb, blotch(p + 11.0, 0.3, 0.74) * 0.35);
		col *= 1.0 - joint * 0.45;
		float w = clamp(wet + blotch(p + 5.0, 0.4, 0.7) * wet * 0.5, 0.0, 1.0);
		col *= 1.0 - w * 0.28;
		r = mix(0.88, 0.32, w);
	} else if (mode == 2) {
		// steel tread plates with hazard-stripe seams
		vec2 g2 = (wpos.xz - grid_origin) / cell;
		vec2 local = fract(g2) * cell;
		float edge = min(min(local.x, cell.x - local.x), min(local.y, cell.y - local.y));
		// diamond tread: short raised lenses, orientation alternating on a checker
		vec2 q = wpos.xz * 7.0;
		vec2 cq = floor(q);
		vec2 f2 = fract(q) - 0.5;
		float parity = mod(cq.x + cq.y, 2.0);
		vec2 dg = parity < 0.5 ? vec2(f2.x + f2.y, f2.x - f2.y) : vec2(f2.x - f2.y, f2.x + f2.y);
		float lens = smoothstep(0.34, 0.26, length(dg * vec2(0.62, 2.1)));
		float plate_tone = noise(floor(g2) * 3.1) * 0.08;
		col = color_a.rgb * (0.9 + plate_tone + lens * 0.16);
		col *= 1.0 - blotch(wpos.xz + floor(g2) * 3.0, 0.7, 0.7) * 0.18;
		col = mix(col, color_c.rgb, blotch(wpos.xz + 21.0, 0.25, 0.76) * 0.5);   // rust bloom
		float scratch = smoothstep(0.965, 1.0, noise(vec2(wpos.x * 0.6 + wpos.z * 9.0, wpos.z * 0.3) )) * 0.12;
		col += scratch;
		r = 0.42 - lens * 0.12;
		m = 0.55;
		if (edge < seam * 0.5) {
			float st = step(0.5, fract((wpos.x + wpos.z) * 2.2));
			col = mix(seam_b.rgb, seam_a.rgb, st) * (0.9 + noise(wpos.xz * 2.0) * 0.1);
			r = 0.7;
			m = 0.1;
		}
	} else if (mode == 3) {
		// tar & gravel: dark tar, sparse gravel stones (cell-random), roof seams, damp patches
		vec2 c = floor(p * 11.0);
		float h1 = hash(c);
		vec2 o = fract(p * 11.0) - vec2(hash(c + 1.3), hash(c + 2.7)) * 0.6 - 0.2;
		float stone = smoothstep(0.24, 0.17, length(o)) * step(0.45, h1);
		vec3 gravel = mix(color_b.rgb, color_b.rgb * vec3(1.15, 1.08, 0.95), hash(c + 5.1));
		col = mix(color_a.rgb * (0.9 + noise(p * 0.4) * 0.12), gravel, stone);
		float seam_l = 1.0 - smoothstep(0.0, 0.04, abs(fract(wpos.z / 1.8) - 0.5) * 1.8);
		col = mix(col, color_a.rgb * 1.5, seam_l * 0.6);
		float damp = blotch(p, 0.35, 0.7);
		col *= 1.0 - damp * 0.2;
		r = mix(0.9, 0.55, damp) - stone * 0.1;
	} else if (mode == 4) {
		// planks along local/world X: boards, gaps, grain, nails, wet sheen
		vec2 q2 = use_uv ? UV : wpos.xz;
		float bw = 0.19;
		float board = floor(q2.y / bw);
		float in_b = fract(q2.y / bw);
		float seg_len = 2.4 + hash(vec2(board, 1.0)) * 1.6;
		float seg = floor((q2.x + hash(vec2(board, 3.0)) * 3.0) / seg_len);
		float tone = hash(vec2(board, seg)) * 0.18;
		float grain = sin((q2.x + hash(vec2(board, seg)) * 9.0) * 3.0 + sin(q2.x * 0.7 + board) * 2.0 + in_b * 5.0) * 0.03;
		col = mix(color_a.rgb, color_b.rgb, tone) * (1.0 + grain);
		float gap = smoothstep(0.06, 0.0, in_b) + smoothstep(0.94, 1.0, in_b);
		float endgap = 1.0 - smoothstep(0.0, 0.02, abs(fract((q2.x + hash(vec2(board, 3.0)) * 3.0) / seg_len) * seg_len));
		col *= 1.0 - max(gap, endgap) * 0.6;
		col *= 1.0 - wet * 0.3;
		r = mix(0.8, 0.22, wet);
	} else if (mode == 5) {
		// riveted steel panels (walls): panel seams, rivet rows, rust drips under rivets
		vec2 q3 = (use_uv ? UV : wpos.xz) ;
		vec2 pc = q3 / cell;
		vec2 pf = fract(pc) * cell;
		float seam_d = min(min(pf.x, cell.x - pf.x), min(pf.y, cell.y - pf.y));
		float panel_tone = hash(floor(pc)) * 0.1;
		col = color_a.rgb * (0.9 + panel_tone);
		col *= 1.0 - (1.0 - smoothstep(0.0, 0.03, seam_d)) * 0.5;
		vec2 rv = vec2(fract(q3.x / 0.25) - 0.5, (seam_d - 0.09) / 0.25);
		float rivet = smoothstep(0.24, 0.17, length(rv * vec2(1.0, 4.0))) * step(seam_d, 0.13);
		col = mix(col, color_a.rgb * 1.35, rivet);
		float drip = blotch(vec2(q3.x * 3.0, q3.y * 0.35), 1.2, 0.72) * (1.0 - smoothstep(0.0, 1.6, seam_d));
		col = mix(col, color_c.rgb, drip * 0.55);
		col = mix(col, color_c.rgb, blotch(q3 + 4.0, 0.6, 0.74) * 0.4);
		r = 0.5;
		m = 0.6;
	} else if (mode == 6) {
		// brick facade
		vec2 q4 = (use_uv ? UV : wpos.xz) / vec2(0.5, 0.18);
		q4.x += step(1.0, mod(floor(q4.y), 2.0)) * 0.5;
		vec2 bf = fract(q4);
		float mortar = 1.0 - smoothstep(0.0, 0.06, min(min(bf.x, 1.0 - bf.x) * 2.7, min(bf.y, 1.0 - bf.y)));
		col = mix(color_a.rgb, color_b.rgb, hash(floor(q4)) * 0.5) * (1.0 - mortar * 0.55);
		col = mix(col, color_c.rgb, blotch(q4 * 0.2, 0.5, 0.7) * 0.4);
		r = 0.9;
	} else if (mode == 7) {
		// ribbed rubber mat with a safety border
		vec2 q5 = use_uv ? UV : wpos.xz;
		float rib = smoothstep(0.35, 0.5, abs(fract(q5.x * 9.0) - 0.5) * 2.0);
		col = color_a.rgb * (0.85 + rib * 0.3);
		r = 0.85;
	} else if (mode == 8) {
		// painted metal: base paint with clean chips showing rust/metal beneath, edge wear
		vec2 q6 = use_uv ? UV : wpos.xz;
		float chip = blotch(q6 * 3.0 + seed, 1.4, 0.74);
		col = mix(color_a.rgb * (0.94 + noise(q6 * 2.0) * 0.08), color_c.rgb, chip);
		r = mix(rough, 0.6, chip);
		m = mix(metal, 0.7, chip);
	} else if (mode == 10) {
		// hazard stripes (edge bands): diagonal yellow / black in world space, worn paint
		float sd = step(0.5, fract((wpos.x + wpos.z) * 1.6));
		col = mix(seam_b.rgb, seam_a.rgb, sd);
		col *= 1.0 - blotch(wpos.xz * 2.0, 0.8, 0.72) * 0.25;
		r = 0.7;
	} else if (mode == 9) {
		// crate wood boards (UV metres, boards along U)
		vec2 q7 = UV;
		float bwid = 0.16;
		float bi = floor(q7.y / bwid);
		float fy = fract(q7.y / bwid);
		col = mix(color_a.rgb, color_b.rgb, hash(vec2(bi, seed)) * 0.6);
		col *= 1.0 + sin(q7.x * 18.0 + sin(q7.x * 3.0 + bi) * 2.5 + fy * 4.0) * 0.035;
		col *= 1.0 - (smoothstep(0.08, 0.0, fy) + smoothstep(0.92, 1.0, fy)) * 0.5;
		r = 0.85;
	}
	ALBEDO = col;
	ROUGHNESS = clamp(r, 0.05, 1.0);
	METALLIC = m;
	EMISSION = emit;
}
