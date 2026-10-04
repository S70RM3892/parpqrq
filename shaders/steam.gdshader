shader_type spatial;
// 室外機の湯気（backdrop.gd）。玉が昇りながら風に流され、膨らんで薄れる。いつもカメラを向く板
// INSTANCE_CUSTOM.r = 玉の時間のずれ（0〜1）、.g = 湯気ごとの乱数
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

uniform vec4 tint : source_color = vec4(0.95, 0.93, 0.9, 0.5);
uniform vec3 wind = vec3(0.8, 0.0, 0.6);

varying float v_t;

void vertex() {
	float t = fract(TIME * 0.11 + INSTANCE_CUSTOM.r + INSTANCE_CUSTOM.g * 3.0);
	v_t = t;
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 center = base + vec3(0.0, t * 9.0, 0.0) + wind * (t * t * 7.0)
			+ vec3(sin(t * 7.0 + INSTANCE_CUSTOM.g * 9.0), 0.0, cos(t * 5.0)) * 0.4 * t;
	float size = mix(0.8, 4.2, sqrt(t));
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = center + (right * VERTEX.x + up * VERTEX.y) * size;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float soft = (1.0 - smoothstep(0.2, 1.0, r));
	float fade = sin(3.14159 * v_t) * (1.0 - v_t * 0.4);
	ALBEDO = tint.rgb;
	ALPHA = soft * fade * tint.a;
}
