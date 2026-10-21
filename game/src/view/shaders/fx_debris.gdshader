shader_type particles;
// v0.9.17 ability VFX (docs/art/VFX.md): solid pieces thrown by an effect: grit chunks, brine
// droplets, sludge gobs, scrap shards, cinders, feathers. Ballistic flight in WORLD space,
// tumbling about a random axis, bouncing and settling on the floor, shrinking away at the end.
// Draw pass: a small mesh (rock, drop, shard, quad) whose material uses the particle COLOR.
render_mode disable_force;

uniform vec3 direction = vec3(0.0, 1.0, 0.0);   // world space
uniform float spread = 0.6;                      // radians around `direction`
uniform float speed_min = 2.0;
uniform float speed_max = 5.0;
uniform float gravity = 9.8;
uniform float bounce = 0.35;
uniform float floor_y = 0.0;
uniform float spin = 8.0;                        // max tumble (rad/s)
uniform float scale_min = 0.05;
uniform float scale_max = 0.12;
uniform vec4 color_a : source_color = vec4(1.0);
uniform vec4 color_b : source_color = vec4(1.0);
uniform float drag = 0.0;
uniform float emit_radius = 0.0;                 // spawn disc radius (horizontal, metres)
uniform vec3 emit_box = vec3(0.0);               // or a box (half extents) instead of a disc
uniform float shrink_from = 0.7;                 // life fraction where shrinking starts
uniform float stretch = 0.0;                     // >0: stretch along the velocity (drops, streaks)
uniform float emit_seed = 0.0;
uniform float buoyancy = 0.0;                    // cinders rise instead of falling

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

mat3 axis_angle(vec3 n, float a) {
	float c = cos(a);
	float s = sin(a);
	float t = 1.0 - c;
	return mat3(vec3(t * n.x * n.x + c, t * n.x * n.y + s * n.z, t * n.x * n.z - s * n.y),
		vec3(t * n.x * n.y - s * n.z, t * n.y * n.y + c, t * n.y * n.z + s * n.x),
		vec3(t * n.x * n.z + s * n.y, t * n.y * n.z - s * n.x, t * n.z * n.z + c));
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
		float rr = sqrt(rnd(s)) * emit_radius;
		origin += vec3(cos(ang) * rr, 0.0, sin(ang) * rr);
	}
	VELOCITY = d * mix(speed_min, speed_max, rnd(s));
	float sc = mix(scale_min, scale_max, rnd(s));
	CUSTOM = vec4(rnd(s) * 6.2831853, 0.0, sc, rnd(s));
	TRANSFORM = mat4(vec4(sc, 0.0, 0.0, 0.0), vec4(0.0, sc, 0.0, 0.0), vec4(0.0, 0.0, sc, 0.0), vec4(origin, 1.0));
	COLOR = mix(color_a, color_b, rnd(s));
}

void process() {
	CUSTOM.y += DELTA / max(LIFETIME, 0.001);
	if (CUSTOM.y >= 1.0) {
		ACTIVE = false;
	}
	float sc = CUSTOM.z;
	VELOCITY.y += (buoyancy - gravity) * DELTA;
	VELOCITY *= 1.0 / (1.0 + drag * DELTA);
	float rest = floor_y + sc * 0.45;
	bool grounded = false;
	if (TRANSFORM[3].y < rest && gravity > buoyancy) {
		TRANSFORM[3].y = rest;
		if (VELOCITY.y < 0.0) {
			VELOCITY.y = -VELOCITY.y * bounce;
			VELOCITY.xz *= 0.55;
		}
		if (abs(VELOCITY.y) < 0.4) {
			VELOCITY.y = 0.0;
			VELOCITY.xz *= 1.0 / (1.0 + 6.0 * DELTA);
			grounded = true;
		}
	}
	float w = CUSTOM.w;
	vec3 axis = normalize(vec3(sin(w * 12.9898) + 0.05, cos(w * 78.233), sin(w * 37.719 + 1.0)));
	CUSTOM.x += spin * (w - 0.5) * 2.0 * DELTA * (grounded ? 0.0 : 1.0);
	float k = 1.0 - smoothstep(shrink_from, 1.0, CUSTOM.y);
	mat3 rot = axis_angle(axis, CUSTOM.x);
	if (stretch > 0.0 && length(VELOCITY) > 0.2) {
		// long axis (local y) along the flight direction
		vec3 yv = normalize(VELOCITY);
		vec3 xv = normalize(abs(yv.y) < 0.95 ? cross(yv, vec3(0.0, 1.0, 0.0)) : cross(yv, vec3(1.0, 0.0, 0.0)));
		vec3 zv = cross(xv, yv);
		float st = 1.0 + stretch * min(length(VELOCITY) * 0.15, 2.0);
		rot = mat3(xv, yv * st, zv);
	}
	TRANSFORM[0].xyz = rot[0] * sc * k;
	TRANSFORM[1].xyz = rot[1] * sc * k;
	TRANSFORM[2].xyz = rot[2] * sc * k;
}
