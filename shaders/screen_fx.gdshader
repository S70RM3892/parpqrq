shader_type canvas_item;
// 画面に重ねる演出を1枚にまとめる（モバイルは重ねる枚数だけ画面全体を読み書きするので：仕様書 6章）
// - 勢い値：画面の縁がうっすら光る（数字なし：仕様書 8章）。Perfect で一瞬強く
// - スピードライン：画面の端だけに放射状の線（モーションブラーの代わり）
// - 速度ビネット：速いほど周辺が暗く、視線が中央に集まる

uniform vec4 glow_color : source_color = vec4(1.0, 0.416, 0.102, 1.0);
uniform vec4 line_color : source_color = vec4(0.42, 0.47, 0.58, 0.6); // 白い街でも見える色（夜は明るく）
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float lines : hint_range(0.0, 1.0) = 0.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.7778;
uniform float line_time = 0.0;  // スローの間も実時間で流すためスクリプトから渡す

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void fragment() {
	vec2 d = abs(UV - 0.5) * 2.0;
	float a_glow = smoothstep(0.82, 1.0, max(d.x, d.y)) * intensity;

	vec2 q = (UV - 0.5) * vec2(aspect, 1.0);
	float r = length(q) / (0.5 * length(vec2(aspect, 1.0)));
	float a_lines = 0.0;
	if (lines > 0.001 && r > 0.5) {
		float ang = atan(q.y, q.x) / 6.2831853 + 0.5;
		float bins = 150.0;
		float id = floor(ang * bins);
		float rnd = hash11(id + 1.0);
		float thin = 1.0 - smoothstep(0.1, 0.55, abs(fract(ang * bins) - 0.5) * 2.0);
		float spd = 1.6 + rnd * 1.8;
		float seg = fract(r * 1.3 - line_time * spd + rnd * 7.0);
		float streak = smoothstep(0.0, 0.06, seg) * (1.0 - smoothstep(0.18 + rnd * 0.2, 0.4 + rnd * 0.2, seg));
		float on = step(0.5, hash11(id * 1.37 + floor(line_time * 2.5 + rnd * 5.0)));
		a_lines = thin * streak * on * smoothstep(0.55, 0.98, r) * lines * line_color.a;
	}
	float a_vig = smoothstep(0.62, 1.15, r) * vignette * 0.5;

	float a = clamp(a_glow + a_lines + a_vig, 0.0, 1.0);
	vec3 col = (glow_color.rgb * a_glow + line_color.rgb * a_lines) / max(a, 0.0001);
	COLOR = vec4(col, a);
}
