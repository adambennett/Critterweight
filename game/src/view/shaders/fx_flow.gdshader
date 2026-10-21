shader_type spatial;
// v0.9.17 ability VFX (docs/art/VFX.md): animated surfaces of 3D effect pieces: shockwave walls,
// tidal crests, vortex funnels, flame tongues, steam jets, spectral bands. Noise scrolls along the
// mesh UVs (u around / along the flow, v across it); `dissolve` eats the surface away from its
// thin parts as the piece dies, so effects break up instead of just fading.
// Premultiplied alpha: `color` is painted (`cover` = opacity, so it reads on the bright canvas) and
// `color2` glows on top (`glow_k`, HDR: the arena's glow pass blooms it), strongest in the core.
render_mode unshaded, cull_disabled, depth_draw_never, blend_premul_alpha, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.5, 0.2, 1.0);
uniform vec4 color2 : source_color = vec4(1.0, 0.95, 0.7, 1.0);   // core / crest colour
uniform float cover = 0.8;
uniform float glow_k = 0.8;
uniform float alpha = 1.0;
uniform vec2 scroll = vec2(0.0, -1.0);      // UV units per second
uniform vec2 noise_scale = vec2(4.0, 2.0);
uniform float dissolve = 0.0;               // 0 whole .. 1 gone
uniform float edge_v = 0.25;                // soft fade at v = 0 and v = 1 (fraction of v)
uniform float edge_u = 0.0;                 // soft fade at u = 0 and u = 1 (open sheets)
uniform float core = 0.5;                   // where along v the bright core sits (0..1)
uniform float core_width = 0.3;
uniform float fresnel = 0.0;                // >0: edges of rounded pieces glow (ghosts, bubbles)
uniform float bands = 0.0;                  // >0: hard streak bands along u (wind lines, rays)
uniform float seed = 0.0;
uniform float jag = 0.0;                    // >0: zigzag the bright core (static)

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
	for (int k = 0; k < 3; k++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(11.3, 4.7);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	vec2 nuv = uv * noise_scale + scroll * TIME + vec2(seed * 13.1, seed * 7.7);
	// noise wraps around u (closed rings): sample on a circle so the seam does not show
	float n = fbm(nuv);
	float ev = smoothstep(0.0, edge_v, uv.y) * smoothstep(0.0, edge_v, 1.0 - uv.y);
	float eu = edge_u > 0.0 ? smoothstep(0.0, edge_u, uv.x) * smoothstep(0.0, edge_u, 1.0 - uv.x) : 1.0;
	float c = core;
	if (jag > 0.0) {
		float step_u = floor(uv.x * 24.0 + floor(TIME * 14.0) * 3.0);
		c += (hash(vec2(step_u, seed)) - 0.5) * jag;
	}
	float corev = smoothstep(core_width, 0.0, abs(uv.y - c));
	float body = clamp(n * 1.3 - 0.15 + corev * 0.6, 0.0, 1.0);
	if (bands > 0.0) {
		float b = smoothstep(0.6, 1.0, sin((uv.x + seed) * bands * 6.2831 + n * 2.0));
		body *= 0.35 + 0.65 * b;
	}
	float fr = 1.0;
	if (fresnel > 0.0) {
		fr = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), fresnel) * 1.4 + 0.15;
	}
	// dissolve: the thin, noisy parts go first
	float keep = smoothstep(dissolve - 0.08, dissolve + 0.08, n * 0.85 + corev * 0.25 + 0.1 * (1.0 - dissolve));
	// vertex colour (ribbons fade their tails through it; plain meshes have white)
	float a = clamp(body * ev * eu * fr * keep * alpha * COLOR.a, 0.0, 1.0);
	float hot = clamp(corev * 0.9 + n * 0.25, 0.0, 1.0);
	vec3 paint = mix(color.rgb, color2.rgb, hot * 0.35) * COLOR.rgb;
	ALBEDO = paint * a * cover * color.a + color2.rgb * a * (0.25 + 0.75 * hot) * glow_k;
	ALPHA = a * cover * color.a;
}
