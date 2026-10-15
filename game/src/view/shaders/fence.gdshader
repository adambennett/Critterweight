shader_type spatial;
// Procedural chain-link cage fence. Wire diamonds are computed from UV in metres, so the
// fence never needs a texture. Near the camera the wire dithers away to keep fighters visible.
render_mode cull_disabled;

uniform vec4 wire_color : source_color = vec4(0.62, 0.64, 0.68, 1.0);
uniform float cell = 0.075;
uniform float wire = 0.09;
uniform float fade_near = 1.2;
uniform float fade_far = 3.0;
uniform float min_alpha = 0.18;

float dither4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int idx = x + y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[idx] + 0.5) / 16.0;
}

varying vec2 local_m;

void vertex() {
	local_m = VERTEX.xy;
}

void fragment() {
	vec2 p = local_m / cell;
	vec2 d = vec2(p.x + p.y, p.x - p.y);
	vec2 f = abs(fract(d) - 0.5);
	float line = min(f.x, f.y);
	float w = smoothstep(wire, wire * 0.4, line);
	float cam_dist = length(VERTEX);
	float fade = mix(min_alpha, 1.0, smoothstep(fade_near, fade_far, cam_dist));
	if (w * fade < dither4(FRAGCOORD.xy) * 0.999 + 0.001) {
		discard;
	}
	ALBEDO = wire_color.rgb;
	METALLIC = 0.8;
	ROUGHNESS = 0.35;
}
