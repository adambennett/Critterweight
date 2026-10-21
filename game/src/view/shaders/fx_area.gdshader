shader_type spatial;
// v0.9.17 ability VFX (docs/art/VFX.md): the TRUE footprint of an area attack or a lingering zone,
// drawn on the floor in its element's pattern (docs/design/ART_DIRECTION.md §6). The shape is
// computed per pixel from the effect's own numbers (radius, cone angle, line length/width, ring
// inner radius), so what the player sees is exactly what can hit.
//   style: 0 plain, 1 scorch licks, 2 brine ripples, 3 gale spiral streaks, 4 grit hex cracks,
//          5 sludge blobs, 6 static forks, 7 spectral wisps, 8 scrap starburst
// Premultiplied alpha, so one pass both paints and glows: `color` is painted over the floor
// (`cover` = how opaque the paint is; it must read on the bright cage canvas), `stain` darkens the
// whole footprint a little (scorch marks, wet floor, goo), and `color2` is added on top as HDR glow
// (`glow_k`; the arena's glow pass blooms it on dark floors).
render_mode unshaded, cull_disabled, depth_draw_never, blend_premul_alpha, shadows_disabled, fog_disabled;

uniform int shape = 0;              // 0 circle, 1 cone, 2 line, 3 ring, 4 cone behind
uniform float radius = 2.0;
uniform float half_angle = 0.52;    // cone half angle (radians)
uniform float length_m = 3.0;
uniform float width_m = 1.0;
uniform float inner = 0.0;
uniform float size_m = 4.0;         // the quad's edge length (metres); centred on the origin
uniform float progress = 1.0;       // 0..1: how far the front has travelled out from the origin
uniform float front = 0.0;          // brightness of the travelling front band
uniform float fade = 1.0;           // overall strength (fades out at the end)
uniform float fill = 0.35;          // interior strength relative to the rim
uniform vec4 color : source_color = vec4(1.0, 0.5, 0.2, 1.0);
uniform vec4 color2 : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform vec4 stain : source_color = vec4(0.2, 0.1, 0.05, 1.0);
uniform float cover = 0.8;
uniform float glow_k = 0.8;
uniform float stain_a = 0.25;
uniform int style = 0;
uniform float speed = 1.0;
uniform float seed = 0.0;
uniform float pulse = 0.0;          // zones: slow breathing of the rim

varying vec3 local;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

// distance to the nearest hexagon edge (grit cracks)
float hex_edge(vec2 p) {
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	vec2 q = abs(g);
	return 0.5 - max(dot(q, normalize(vec2(1.0, 1.7320508))), q.x);
}

void vertex() {
	// the mesh is a unit quad: grow it to the footprint's size in metres (the node is never scaled)
	VERTEX *= size_m;
	local = VERTEX;
}

void fragment() {
	vec2 p = vec2(local.x, local.z);     // +z = the attacker's forward
	float d = length(p);
	float edge = -1.0;                  // metres inside the shape (negative = outside)
	float along = 0.0;                  // 0 at the origin, 1 at the far edge
	if (shape == 1 || shape == 4) {
		vec2 q = shape == 4 ? -p : p;
		float ang = abs(atan(q.x, q.y));
		edge = min(radius - d, (half_angle - ang) * max(d, 0.05));
		along = d / max(radius, 0.01);
	} else if (shape == 2) {
		edge = min(min(p.y, length_m - p.y), width_m * 0.5 - abs(p.x));
		along = p.y / max(length_m, 0.01);
	} else if (shape == 3) {
		edge = min(radius - d, d - inner);
		along = d / max(radius, 0.01);
	} else {
		edge = radius - d;
		along = d / max(radius, 0.01);
	}
	float soft = 0.05;
	float mask = smoothstep(-soft, soft, edge);
	if (mask <= 0.0) {
		discard;
	}
	// the front travels from the origin; nothing beyond it yet
	float reach = smoothstep(progress + 0.04, progress - 0.04, along);
	float band = front * smoothstep(0.16, 0.0, abs(along - progress)) * step(0.001, progress);
	float rim = 1.0 - smoothstep(0.0, 0.16 + pulse * 0.05 * sin(TIME * 3.0 + seed), edge);
	float t = TIME * speed + seed * 7.0;
	vec2 dir = d > 0.001 ? p / d : vec2(0.0, 1.0);
	float ang2 = atan(p.x, p.y);
	float pat = 0.5;
	if (style == 1) {
		// scorch: radial flame licks rising outward, hatched with ticks
		float licks = fbm(vec2(ang2 * 3.0, d * 1.4 - t * 1.6));
		pat = smoothstep(0.38, 0.75, licks) * (0.6 + 0.4 * sin(ang2 * 18.0 + d * 2.0 - t * 4.0));
	} else if (style == 2) {
		// brine: concentric ripple rings travelling out
		float rr = fract(d * 1.5 - t * 0.7);
		pat = smoothstep(0.08, 0.0, abs(rr - 0.5) - 0.38) + 0.35 * fbm(p * 1.8 + t * 0.3);
	} else if (style == 3) {
		// gale: spiral swirl streaks
		float sp = sin(ang2 * 3.0 + d * 3.2 - t * 5.0);
		pat = smoothstep(0.55, 1.0, sp) * (0.5 + 0.5 * fbm(vec2(ang2 * 2.0 - t, d * 2.0)));
	} else if (style == 4) {
		// grit: hex-cell cracks
		float he = hex_edge(p * 1.6 + vec2(seed * 3.0));
		pat = smoothstep(0.06, 0.0, he) * (0.7 + 0.3 * vnoise(p * 6.0)) + 0.25 * fbm(p * 3.0);
	} else if (style == 5) {
		// sludge: lumpy blobs with bubbles
		float bl = fbm(p * 1.4 + vec2(t * 0.15, -t * 0.1));
		pat = smoothstep(0.42, 0.6, bl) * 0.8;
		vec2 cell = floor(p * 2.4);
		vec2 c = (cell + vec2(hash(cell + seed), hash(cell + 5.3))) / 2.4;
		float bub = smoothstep(0.07, 0.04, length(p - c)) * step(0.6, hash(cell + floor(t * 0.7)));
		pat += bub;
	} else if (style == 6) {
		// static: lightning forks in a radial burst, flickering
		float fl = floor(t * 12.0);
		float n = fbm(vec2(ang2 * 4.0 + hash(vec2(fl, seed)) * 6.0, d * 1.2));
		pat = smoothstep(0.035, 0.0, abs(n - 0.5)) * (0.6 + 0.4 * hash(vec2(fl, 3.0)));
		pat += 0.25 * smoothstep(0.02, 0.0, abs(fract(d * 1.2 - t * 1.5) - 0.5) - 0.47);
	} else if (style == 7) {
		// spectral: drifting wisps turning around the centre
		float w = fbm(vec2(ang2 * 2.0 + t * 0.4, d * 1.5 - t * 0.3));
		pat = smoothstep(0.45, 0.85, w) + 0.3 * smoothstep(0.03, 0.0, abs(fract(d * 0.9 - t * 0.35) - 0.5) - 0.45);
	} else if (style == 8) {
		// scrap: a crisp star-burst of rays
		float rays = abs(sin(ang2 * 4.0));
		pat = smoothstep(0.9, 1.0, rays) * (1.0 - along * 0.5) + 0.2 * step(0.97, abs(sin(ang2 * 12.0)));
	} else {
		pat = 0.4 + 0.3 * fbm(p * 2.0 + t * 0.2);
	}
	float k = mask * reach * fade;
	float paint = clamp(rim * 0.85 + fill * pat + band, 0.0, 1.0) * k * cover * color.a;
	float st = stain_a * k * (0.65 + 0.35 * pat) * (1.0 - paint);
	float glow = clamp(band * 1.3 + rim * 0.35 + fill * pat * 0.45, 0.0, 2.0) * k * glow_k;
	ALBEDO = color.rgb * paint + stain.rgb * st + color2.rgb * glow;
	ALPHA = clamp(paint + st, 0.0, 1.0);
}
