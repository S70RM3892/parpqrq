shader_type spatial;
// 遠景のビル（backdrop.gd の MultiMesh 1つで描く）。窓は世界座標の格子から作る（UVを持たない箱のため）。
// INSTANCE_CUSTOM.r = ビルごとの乱数
render_mode cull_back;

global uniform float night;

uniform vec3 wall_color : source_color = vec3(0.82, 0.83, 0.85);
uniform vec3 window_color : source_color = vec3(0.42, 0.48, 0.56);
uniform vec3 window_light : source_color = vec3(1.0, 0.8, 0.55);

varying float v_rnd;
varying vec3 v_wnormal;

void vertex() {
	v_rnd = INSTANCE_CUSTOM.r;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 col = wall_color * (0.88 + 0.2 * v_rnd);
	vec3 emit = vec3(0.0);
	if (abs(v_wnormal.y) < 0.5) {
		float u = abs(v_wnormal.x) > 0.5 ? world.z : world.x;
		vec2 c = vec2(u / 3.2, world.y / 3.4);
		vec2 f = fract(c);
		float win = step(0.18, f.x) * step(f.x, 0.82) * step(0.25, f.y) * step(f.y, 0.85);
		col = mix(col, window_color, win * 0.85);
		float lit = step(0.6, hash12(floor(c) + v_rnd * 57.0)) * night;
		emit = window_light * win * lit * 1.8;
	}
	ALBEDO = col;
	ROUGHNESS = 0.8;
	EMISSION = emit;
}
