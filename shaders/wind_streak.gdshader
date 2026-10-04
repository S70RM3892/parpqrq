shader_type spatial;
// 風に舞う塵（仕様書 6章）：速いほど長く伸びる線。wind_streaks.gd がインスタンスの向きと長さを決める
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 0.5);

void fragment() {
	// 長さ方向（UV.x）の両端と幅方向（UV.y）をぼかす
	float a = smoothstep(0.0, 0.35, UV.x) * (1.0 - smoothstep(0.65, 1.0, UV.x));
	a *= 1.0 - abs(UV.y - 0.5) * 2.0;
	ALBEDO = color.rgb * COLOR.rgb;
	ALPHA = color.a * a * COLOR.a;
}
