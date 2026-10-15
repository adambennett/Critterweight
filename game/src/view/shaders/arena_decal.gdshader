shader_type spatial;
// Hazard footprint decal (ARENAS.md §1/§5, ART_DIRECTION §10): every hazard's footprint is drawn
// at all times as a hatched outline at ~40% alpha, plus its icon SHAPE (readable without colour:
// ELEMENTS.md §1 flame / wave / bolt / blob / hex / swirl, and hook / arrow / spiral / star /
// chevrons / magnet for the non-element hazards). `glow` drives the ~1 s telegraph (pulsing
// outline), `active` the live state (stronger fill). Mesh: a flat quad whose UV spans `size`.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.85, 0.2, 1.0);
uniform int shape = 0;            // 0 rect, 1 circle, 2 cone (from the -Z edge toward +Z), 3 ring
uniform vec2 size = vec2(2.0, 2.0);
uniform float cone_deg = 70.0;
uniform int icon = 0;             // 0 none 1 flame 2 wave 3 bolt 4 blob 5 hex 6 swirl 7 hook 8 arrow 9 spiral 10 star 11 chevrons 12 magnet
uniform float icon_spacing = 1.8;
uniform float icon_size = 0.55;
uniform float base_alpha = 0.4;
uniform float hatch_period = 0.32;
uniform float hatch_angle = 0.785;
uniform float outline_w = 0.07;
uniform float glow = 0.0;
uniform float active = 0.0;
uniform vec2 hole = vec2(0.0);    // rect shapes: hollow centre (pit rims)

float sd_seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}
float sd_hex(vec2 p, float r) {
	const vec3 k = vec3(-0.866025404, 0.5, 0.577350269);
	p = abs(p);
	p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy;
	p -= vec2(clamp(p.x, -k.z * r, k.z * r), r);
	return length(p) * sign(p.y);
}
float sd_star(vec2 p, float r) {
	float a = atan(p.x, p.y);
	float seg = 6.2831853 / 5.0;
	float d = cos(floor(0.5 + a / seg) * seg - a) * length(p);
	float spike = mix(r * 0.45, r, pow(abs(cos(a * 2.5)), 6.0));
	return length(p) - spike + 0.0 * d;
}

// icon mask in [-1, 1]^2 cell space
float icon_mask(int id, vec2 p) {
	float w = 0.11;
	float d = 1e3;
	if (id == 1) {          // flame: tall pointed teardrop with an inner notch
		vec2 q = p - vec2(0.0, -0.25);
		float body = length(q * vec2(1.0, 0.9)) - 0.42;
		float tip = sd_seg(p, vec2(-0.32, -0.1), vec2(0.05, 0.85)) - 0.08;
		float tip2 = sd_seg(p, vec2(0.32, -0.1), vec2(0.05, 0.85)) - 0.08;
		float fill = min(body, min(tip, tip2));
		float notch = length(p - vec2(0.04, -0.28)) - 0.15;
		return step(fill, 0.0) * (1.0 - step(notch, 0.0));
	} else if (id == 2) {   // wave: one rolling crest with a curl
		float y = sin(p.x * 3.2) * 0.25;
		d = abs(p.y - y) - w;
		float curl = abs(length(p - vec2(0.48, 0.2)) - 0.22) - w * 0.8;
		if (p.x > 0.3) d = min(d, curl);
		return step(d, 0.0) * step(abs(p.x), 0.95);
	} else if (id == 3) {   // bolt: three-segment zigzag
		d = min(sd_seg(p, vec2(-0.35, 0.85), vec2(0.15, 0.05)), sd_seg(p, vec2(0.15, 0.05), vec2(-0.2, -0.05)));
		d = min(d, sd_seg(p, vec2(-0.2, -0.05), vec2(0.35, -0.85)));
		return step(d, 0.13);
	} else if (id == 4) {   // blob: circle with three drips
		d = length(p - vec2(0.0, 0.2)) - 0.5;
		d = min(d, length((p - vec2(-0.3, -0.45)) * vec2(1.0, 0.6)) - 0.13);
		d = min(d, length((p - vec2(0.0, -0.55)) * vec2(1.0, 0.55)) - 0.14);
		d = min(d, length((p - vec2(0.3, -0.42)) * vec2(1.0, 0.65)) - 0.12);
		return step(d, 0.0);
	} else if (id == 5) {   // hex nugget with a crack
		float h = sd_hex(p * vec2(1.0, 1.25), 0.62);
		float crack = sd_seg(p, vec2(-0.1, 0.5), vec2(0.15, -0.5)) - 0.06;
		return step(h, 0.0) * step(0.0, crack);
	} else if (id == 6) {   // swirl: spiral with tails
		float rr = length(p);
		float a = atan(p.y, p.x);
		float s = abs(fract((rr * 3.2 - a / 6.2831853) + 0.25) - 0.5);
		return step(s, 0.13) * step(rr, 0.9) * step(0.08, rr);
	} else if (id == 7) {   // hook
		d = sd_seg(p, vec2(0.25, 0.9), vec2(0.25, -0.15));
		float arc = abs(length(p - vec2(-0.05, -0.15)) - 0.3);
		if (p.y < -0.1) d = min(d, arc);
		d = min(d, sd_seg(p, vec2(-0.35, -0.15), vec2(-0.45, 0.1)));
		return step(d, 0.12);
	} else if (id == 8) {   // arrow (up / forward)
		d = min(sd_seg(p, vec2(0.0, -0.8), vec2(0.0, 0.7)), min(sd_seg(p, vec2(-0.5, 0.25), vec2(0.0, 0.8)), sd_seg(p, vec2(0.5, 0.25), vec2(0.0, 0.8))));
		return step(d, 0.13);
	} else if (id == 9) {   // drain spiral
		float rr2 = length(p);
		float a2 = atan(p.y, p.x);
		float s2 = abs(fract(rr2 * 2.2 + a2 / 6.2831853) - 0.5);
		return step(s2, 0.16) * step(rr2, 0.95);
	} else if (id == 10) {  // star
		return step(sd_star(p, 0.85), 0.0);
	} else if (id == 11) {  // chevrons pointing inward (pit / edge)
		vec2 q2 = vec2(abs(p.x), p.y);
		d = min(sd_seg(q2, vec2(0.0, 0.25), vec2(0.6, 0.75)), sd_seg(q2, vec2(0.0, -0.45), vec2(0.6, 0.05)));
		return step(d, 0.12);
	} else if (id == 12) {  // horseshoe magnet
		float ring = abs(length(p - vec2(0.0, 0.15)) - 0.45) - 0.14;
		if (p.y < 0.15) ring = min(abs(abs(p.x) - 0.45) - 0.14, 1e3) + max(-0.75 - p.y, 0.0);
		return step(ring, 0.0) * step(-0.75, p.y);
	}
	return 0.0;
}

void fragment() {
	vec2 lp = (UV - 0.5) * size;          // metres, x right, y = local +Z
	float inside = 0.0;
	float edge_d = 0.0;
	if (shape == 1 || shape == 3) {
		float rr = length(lp);
		float R = size.x * 0.5;
		inside = step(rr, R);
		edge_d = R - rr;
		if (shape == 3) {
			inside *= step(R * 0.55, rr);
			edge_d = min(edge_d, rr - R * 0.55);
		}
	} else if (shape == 2) {
		vec2 c = lp + vec2(0.0, size.y * 0.5);   // apex at the -Z edge
		float ang = abs(atan(c.x, c.y));
		float half_a = radians(cone_deg) * 0.5;
		float rr2 = length(c);
		inside = step(ang, half_a) * step(rr2, size.y);
		edge_d = min(size.y - rr2, (half_a - ang) * rr2);
	} else {
		vec2 h = size * 0.5 - abs(lp);
		inside = step(0.0, min(h.x, h.y));
		edge_d = min(h.x, h.y);
		if (hole.x > 0.0) {
			vec2 hh = abs(lp) - hole * 0.5;
			inside *= step(0.0, max(hh.x, hh.y));
			edge_d = min(edge_d, max(hh.x, hh.y));
		}
	}
	if (inside < 0.5) {
		discard;
	}
	float outline = 1.0 - smoothstep(outline_w * 0.6, outline_w, edge_d);
	vec2 rp = vec2(cos(hatch_angle) * lp.x - sin(hatch_angle) * lp.y, sin(hatch_angle) * lp.x + cos(hatch_angle) * lp.y);
	float hatch = step(0.62, fract(rp.x / hatch_period));
	float ic = 0.0;
	if (icon > 0) {
		vec2 cellp = lp / icon_spacing;
		vec2 fc = fract(cellp + 0.5) - 0.5;
		float small = min(size.x, size.y);
		if (small < icon_spacing * 1.2) {
			fc = lp / max(small * 0.62, 0.3);
			ic = icon_mask(icon, fc / max(icon_size, 0.05) * 0.55);
		} else {
			ic = icon_mask(icon, fc * icon_spacing / max(icon_size, 0.05));
		}
	}
	float pulse = 0.5 + 0.5 * sin(TIME * 12.0);
	float a = base_alpha * max(outline, max(hatch * 0.55, ic * 0.95));
	a += glow * (0.35 + 0.45 * pulse) * max(outline * 1.4, 0.35 + ic * 0.4);
	a += active * (0.35 + hatch * 0.15 + ic * 0.3);
	vec3 col = color.rgb * (1.0 + glow * pulse * 0.6 + active * 0.4);
	col = mix(col, vec3(1.0), ic * 0.15);
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 0.95);
}
