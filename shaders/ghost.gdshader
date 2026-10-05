shader_type spatial;
// ゴースト（自己ベスト・開発者）とリプレイの体（ghost_body.gd）。ホログラムのように縁が光り、横の走査線が流れる半透明の人形。
// 正面はほとんど透け、輪郭（視線と面が平行な所）ほど濃く光るので、走る姿が線で読める。
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.416, 0.102, 0.38);
uniform float rim_power = 2.2;

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - ndv, rim_power);
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float scan = 0.65 + 0.35 * smoothstep(0.3, 0.7, abs(fract(world.y * 14.0 - TIME * 1.6) - 0.5) * 2.0);
	float body = 0.12 + rim * 1.6;
	ALBEDO = color.rgb * body * scan * (color.a / 0.38);
}
