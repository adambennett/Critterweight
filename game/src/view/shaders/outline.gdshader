shader_type spatial;
// Inverted-hull outline pass (next_pass of creature/prop materials).
render_mode unshaded, cull_front, depth_draw_opaque, skip_vertex_transform;

uniform float width = 0.012;
uniform vec4 color : source_color = vec4(0.05, 0.03, 0.07, 1.0);

void vertex() {
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// keep outlines roughly constant on screen, thinner up close
	float dist_scale = clamp(-view_pos.z * 0.12, 0.6, 2.2);
	view_pos.xyz += view_n * width * dist_scale;
	VERTEX = view_pos.xyz;
	NORMAL = view_n;
}

void fragment() {
	ALBEDO = color.rgb;
}
