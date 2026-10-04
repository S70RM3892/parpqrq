shader_type canvas_item;
// 勢い値の表示（仕様書 8章：数字なし。画面の縁がうっすら光る強さで表す）

uniform vec4 glow_color : source_color = vec4(1.0, 0.416, 0.102, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 d = abs(UV - 0.5) * 2.0;
	float edge = max(d.x, d.y);
	float a = smoothstep(0.82, 1.0, edge) * intensity;
	COLOR = vec4(glow_color.rgb, a);
}
