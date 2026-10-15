shader_type spatial;
// Stylized water: tidal gutter flood (foam line telegraph, Brine ripples) and the harbour / bay
// backdrops (big swell, light glitter). Ripple rings are the Brine zone language (ART §6).
render_mode cull_disabled, depth_draw_opaque;

uniform vec4 deep : source_color = vec4(0.1, 0.36, 0.55, 1.0);
uniform vec4 shallow : source_color = vec4(0.18, 0.61, 0.88, 1.0);
uniform vec4 foam : source_color = vec4(0.92, 0.97, 1.0, 1.0);
uniform float foam_band = 0.0;      // telegraph: foam line strength 0..1
uniform float ripple_scale = 3.0;
uniform float speed = 1.0;
uniform float glitter = 0.0;        // night bay sparkles
uniform vec4 glitter_color : source_color = vec4(1.0, 0.85, 0.55, 1.0);
uniform float opacity = 0.88;
uniform vec2 half_size = vec2(8.0, 0.75);   // gutter: foam hugs the long edges

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME * speed;
	float w1 = sin(p.x * ripple_scale + t * 1.7 + sin(p.y * 1.3 + t) * 1.5);
	float w2 = sin(p.y * ripple_scale * 1.3 - t * 1.3 + sin(p.x * 0.9 - t * 0.6) * 1.2);
	float h = (w1 + w2) * 0.25 + 0.5;
	vec3 col = mix(deep.rgb, shallow.rgb, h);
	// ripple rings (Brine pattern)
	vec2 cell = floor(p * 0.5);
	vec2 c = (cell + vec2(hash(cell), hash(cell + 3.1))) * 2.0;
	float rr = length(p - c);
	float ring = smoothstep(0.05, 0.0, abs(fract(rr * 1.6 - t * 0.6) - 0.5) - 0.42) * smoothstep(1.4, 0.2, rr);
	col = mix(col, foam.rgb, ring * 0.25);
	// foam line along the gutter edges (telegraph) and crest flecks
	vec2 lp = abs(UV - 0.5) * 2.0;
	float edge = smoothstep(0.72, 0.98, lp.y) * foam_band;
	float fleck = step(0.86, fract(sin(dot(floor(p * 9.0 + vec2(t * 2.0, 0.0)), vec2(12.9, 78.2))) * 43758.5)) * foam_band;
	col = mix(col, foam.rgb, clamp(edge + fleck * 0.6, 0.0, 1.0));
	float spark = 0.0;
	if (glitter > 0.0) {
		vec2 g = floor(p * 1.5);
		spark = step(0.9965, hash(g + floor(t * 2.0))) * glitter * 0.7;
		spark += smoothstep(0.97, 1.0, sin(p.x * 0.35 + t) * sin(p.y * 1.1 - t * 1.3)) * glitter * 0.15;
	}
	ALBEDO = col;
	EMISSION = glitter_color.rgb * spark * 2.0 + foam.rgb * edge * 0.25;
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALPHA = clamp(opacity + fres * 0.1 + edge * 0.2, 0.0, 1.0);
}
