shader_type spatial;
// 流れる雲（仕様書 6章：雲のスクロール）。カメラを中心にした半球の内側に描く。
// 空のシェーダーで TIME を使わないためにここへ分けた（sky.gdshader 参照）。
// 雲の層を高さのある平面とみなし、太陽の方へずらした所の濃さと比べて陰を付ける（太陽側の縁が明るく、真ん中と底が陰る）。
// 太陽の近くでは薄い縁が光る（前方散乱の銀の縁）。上空に薄い巻雲の層も重ねる。
render_mode unshaded, cull_front, depth_draw_never, fog_disabled, shadows_disabled, blend_mix;

uniform sampler2D noise : repeat_enable, filter_linear_mipmap;
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 0.9);
uniform vec3 shade_color : source_color = vec3(0.78, 0.8, 0.86);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.75);
uniform vec3 sun_dir = vec3(0.0, 0.5, -0.8);
uniform float coverage = 0.5;
uniform float speed = 0.004;

varying vec3 v_dir;

void vertex() {
	v_dir = VERTEX;
}

float density(vec2 uv, float t) {
	float n = texture(noise, uv + vec2(t, t * 0.35)).r * 0.6
			+ texture(noise, uv * 2.3 + vec2(-t * 1.4, t * 0.5)).r * 0.3
			+ texture(noise, uv * 5.7 + vec2(t * 2.0, -t)).r * 0.1;
	return smoothstep(coverage, coverage + 0.18, n);
}

void fragment() {
	vec3 d = normalize(v_dir);
	float up = max(d.y, 0.0);
	vec3 s = normalize(sun_dir);
	// 雲の層（高さ一定の平面）の上の位置。地平線ほど遠く・細かく見える
	vec2 uv = d.xz / (up + 0.1) * 0.2;
	float t = TIME * speed;
	float dens = density(uv, t);
	// 太陽の方へ少しずらした所の濃さ：濃いほど光が遮られて陰る
	vec2 toward = normalize(s.xz + vec2(1e-4)) * 0.035;
	float occl = density(uv + toward, t) * 0.6 + density(uv + toward * 2.0, t) * 0.4;
	float lit = clamp(1.0 - occl * 0.85 + (1.0 - dens) * 0.3, 0.0, 1.0);
	vec3 col = mix(shade_color, cloud_color.rgb * mix(vec3(1.0), sun_color, 0.35), lit);
	// 銀の縁：太陽の近くで、薄い所ほど光る
	float fwd = pow(max(dot(d, s), 0.0), 6.0);
	col += sun_color * fwd * (1.0 - dens) * 1.2 * lit;
	// 巻雲（上空の薄い筋）
	vec2 uv2 = d.xz / (up + 0.25) * vec2(0.05, 0.12);
	float ci = smoothstep(0.55, 0.85, texture(noise, uv2 + vec2(t * 0.6, 0.0)).r) * 0.35;
	float a = max(dens, ci * (1.0 - dens)) * smoothstep(0.015, 0.22, up);
	col = mix(mix(cloud_color.rgb, sun_color, 0.25), col, dens / max(a, 1e-3));
	ALBEDO = col;
	ALPHA = a * cloud_color.a;
}
