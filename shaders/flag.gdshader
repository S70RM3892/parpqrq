shader_type spatial;
// 屋上の旗（backdrop.gd）。ポールの側（x = 0）を止め、先へ行くほど大きく波打つ。
// INSTANCE_CUSTOM.r = 柄（0〜1：白地に帯・白地に丸・色地）、.g = 色の選び
render_mode cull_disabled;

varying vec2 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM.rg;
	float x = VERTEX.x / 2.4;  // 0 = ポール、1 = 先
	float ph = INSTANCE_CUSTOM.g * 6.2831;
	float wave = sin(VERTEX.x * 2.3 - TIME * 6.0 + ph) * 0.18 + sin(VERTEX.x * 4.1 - TIME * 9.0 + ph) * 0.06;
	VERTEX.z += wave * x;
	VERTEX.y -= x * x * 0.12;
	NORMAL = normalize(vec3(-cos(VERTEX.x * 2.3 - TIME * 6.0 + ph) * 0.4 * x, 0.0, 1.0));
}

void fragment() {
	float pick = v_custom.x;
	vec3 c = mix(vec3(0.85, 0.15, 0.12), vec3(0.15, 0.35, 0.8), step(0.5, v_custom.y));
	c = mix(c, vec3(0.1, 0.6, 0.35), step(0.8, v_custom.y));
	vec3 col = vec3(0.92);
	if (pick < 0.33) {
		col = mix(col, c, step(0.35, UV.y) * step(UV.y, 0.65));        // 白地に帯
	} else if (pick < 0.66) {
		col = mix(col, c, 1.0 - step(0.22, length((UV - vec2(0.45, 0.5)) * vec2(1.6, 1.0))));  // 白地に丸
	} else {
		col = c;
	}
	ALBEDO = col;
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.35);
}
