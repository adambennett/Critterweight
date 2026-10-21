shader_type particles;
// v0.9.17 ability VFX (docs/art/VFX.md): soft volumes made of camera-facing puffs: steam, smoke,
// dust, flame tongues, spray, spectral mist. Puffs leave along a cone, slow down, grow, drift
// (buoyancy or gravity), swirl about the emitter's vertical axis, fade in fast and out slowly.
// Draw pass: a QuadMesh with a billboard (particles) material using the particle COLOR.
render_mode disable_force;

uniform vec3 direction = vec3(0.0, 1.0, 0.0);   // world space
uniform float spread = 0.8;
uniform float speed_min = 0.5;
uniform float speed_max = 2.0;
uniform float drag = 2.0;
uniform float buoyancy = 0.6;                   // + up, - falls
uniform float swirl = 0.0;                      // rad/s about the emitter's vertical axis
uniform float size_min = 0.2;
uniform float size_max = 0.45;
uniform float grow = 1.8;                       // size multiplier reached at the end of life
uniform vec4 color_a : source_color = vec4(1.0);
uniform vec4 color_b : source_color = vec4(1.0);
uniform float fade_in = 0.08;                   // life fraction
uniform float emit_radius = 0.0;
uniform float emit_height = 0.0;
uniform vec3 emit_box = vec3(0.0);
uniform float emit_seed = 0.0;
uniform float spin = 1.0;
uniform float ring = 0.0;                       // 1: spawn on the rim of emit_radius (shock rings)

uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

float rnd(inout uint s) {
	s = hash_u(s + 0x9e3779b9u);
	return float(s & 0x00FFFFFFu) / 16777216.0;
}

void start() {
	uint s = hash_u(INDEX * 7919u + uint(emit_seed * 1000.0) + RANDOM_SEED);
	vec3 tz = normalize(direction);
	vec3 tx = normalize(abs(tz.y) < 0.95 ? cross(tz, vec3(0.0, 1.0, 0.0)) : cross(tz, vec3(1.0, 0.0, 0.0)));
	vec3 ty = cross(tz, tx);
	float ct = mix(1.0, cos(spread), rnd(s));
	float st = sqrt(max(0.0, 1.0 - ct * ct));
	float ph = 6.2831853 * rnd(s);
	vec3 d = tx * cos(ph) * st + ty * sin(ph) * st + tz * ct;
	vec3 origin = EMISSION_TRANSFORM[3].xyz;
	if (emit_box != vec3(0.0)) {
		vec3 b = vec3(rnd(s), rnd(s), rnd(s)) * 2.0 - 1.0;
		origin += mat3(EMISSION_TRANSFORM) * (b * emit_box);
	} else {
		float ang = rnd(s) * 6.2831853;
		float rr = ring > 0.5 ? emit_radius : sqrt(rnd(s)) * emit_radius;
		origin += vec3(cos(ang) * rr, rnd(s) * emit_height, sin(ang) * rr);
		if (ring > 0.5) {
			d = normalize(vec3(cos(ang), 0.15, sin(ang)));
		}
	}
	VELOCITY = d * mix(speed_min, speed_max, rnd(s));
	float sz = mix(size_min, size_max, rnd(s));
	// x: billboard angle (the particle material reads it), y: age, z: unused (anim frame), w: size
	CUSTOM = vec4(rnd(s) * 6.2831853, 0.0, 0.0, sz);
	TRANSFORM = mat4(vec4(sz, 0.0, 0.0, 0.0), vec4(0.0, sz, 0.0, 0.0), vec4(0.0, 0.0, sz, 0.0), vec4(origin, 1.0));
	COLOR = mix(color_a, color_b, rnd(s));
	COLOR.a = 0.0;
}

void process() {
	CUSTOM.y += DELTA / max(LIFETIME, 0.001);
	float life = CUSTOM.y;
	if (life >= 1.0) {
		ACTIVE = false;
	}
	VELOCITY *= 1.0 / (1.0 + drag * DELTA);
	VELOCITY.y += buoyancy * DELTA;
	if (swirl != 0.0) {
		vec3 c = EMISSION_TRANSFORM[3].xyz;
		vec3 r = TRANSFORM[3].xyz - c;
		vec3 tang = normalize(vec3(-r.z, 0.0, r.x) + vec3(0.0001));
		VELOCITY += tang * swirl * length(r.xz) * DELTA * 2.0;
	}
	CUSTOM.x += spin * DELTA * (fract(CUSTOM.w * 37.0) - 0.5) * 2.0;
	float sz = CUSTOM.w * mix(1.0, grow, sqrt(clamp(life, 0.0, 1.0)));
	TRANSFORM[0].xyz = vec3(sz, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, sz, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, sz);
	float a = smoothstep(0.0, fade_in, life) * (1.0 - smoothstep(0.35, 1.0, life));
	COLOR.a = mix(color_a.a, color_b.a, 0.5) * a;
}
