shader_type spatial;
// 流れる雲（仕様書 6章：雲のスクロール）。カメラを中心にした半球の内側に描く。
// 空のシェーダーで TIME を使わないためにここへ分けた（sky.gdshader 参照）。
render_mode unshaded, cull_front, depth_draw_never, fog_disabled, shadows_disabled, blend_mix;

uniform sampler2D noise : repeat_enable, filter_linear_mipmap;
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 0.9);
uniform vec3 shade_color : source_color = vec3(0.78, 0.8, 0.86);
uniform float coverage = 0.5;
uniform float speed = 0.004;

varying vec3 v_dir;

void vertex() {
	v_dir = VERTEX;
}

void fragment() {
	vec3 d = normalize(v_dir);
	float up = max(d.y, 0.0);
	vec2 uv = d.xz / (up + 0.12) * 0.22;
	float t = TIME * speed;
	float n = texture(noise, uv + vec2(t, t * 0.35)).r * 0.65 + texture(noise, uv * 2.7 + vec2(-t * 1.6, t * 0.5)).r * 0.35;
	float a = smoothstep(coverage, coverage + 0.22, n) * smoothstep(0.01, 0.2, up);
	ALBEDO = mix(cloud_color.rgb, shade_color, smoothstep(coverage + 0.12, coverage + 0.45, n));
	ALPHA = a * cloud_color.a;
}
