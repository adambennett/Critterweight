shader_type sky;
// Stylized arena skies: vertical gradient + (night) stars and a soft moon, or (day) a broad
// overcast cloud band. Cheap: no textures, no volumetrics.

uniform vec4 top : source_color = vec4(0.06, 0.08, 0.14, 1.0);
uniform vec4 horizon : source_color = vec4(0.16, 0.13, 0.22, 1.0);
uniform vec4 bottom : source_color = vec4(0.03, 0.03, 0.05, 1.0);
uniform float stars = 0.0;
uniform float clouds = 0.0;
uniform vec4 cloud_color : source_color = vec4(0.85, 0.88, 0.9, 1.0);
uniform vec3 moon_dir = vec3(-0.4, 0.55, -0.73);
uniform float moon = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 col = y > 0.0 ? mix(horizon.rgb, top.rgb, pow(clamp(y, 0.0, 1.0), 0.55)) : mix(horizon.rgb, bottom.rgb, clamp(-y * 4.0, 0.0, 1.0));
	if (stars > 0.0 && y > 0.02) {
		vec2 sp = d.xz / (y + 0.35) * 60.0;
		vec2 c = floor(sp);
		float h = hash(c);
		float st = step(0.985, h) * smoothstep(0.35, 0.0, length(fract(sp) - 0.5));
		col += vec3(st * stars * (0.6 + 0.4 * sin(TIME * 2.0 + h * 40.0)));
	}
	if (clouds > 0.0 && y > -0.05) {
		vec2 cp = d.xz / (y + 0.25) * 1.6 + vec2(TIME * 0.01, 0.0);
		float n = noise(cp) * 0.6 + noise(cp * 2.3) * 0.3 + noise(cp * 5.1) * 0.1;
		col = mix(col, cloud_color.rgb, smoothstep(0.45, 0.75, n) * clouds * smoothstep(-0.05, 0.25, y));
	}
	if (moon > 0.0) {
		float md = dot(normalize(d), normalize(moon_dir));
		col += vec3(1.0, 0.97, 0.88) * (smoothstep(0.9993, 0.9996, md) * 1.5 + pow(max(md, 0.0), 300.0) * 0.25) * moon;
	}
	COLOR = col;
}
