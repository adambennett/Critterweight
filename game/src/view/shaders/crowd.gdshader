shader_type spatial;
// Crowd silhouettes (MultiMesh): per-instance colour, energy-driven bounce, coloured rim.

uniform vec4 rim : source_color = vec4(1.0, 0.55, 0.25, 1.0);
uniform float energy = 0.3;

varying float seed;

void vertex() {
	seed = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
	float hop = max(0.0, sin(TIME * (5.0 + seed * 4.0) + seed * 30.0));
	VERTEX.y += hop * energy * 0.18;
	VERTEX.x += sin(TIME * 1.3 + seed * 20.0) * 0.03;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
	float r = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	EMISSION = rim.rgb * r * (0.15 + energy * 0.35);
}
