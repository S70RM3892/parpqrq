shader_type sky;
// 空（仕様書 6章：グラデーション空。時間帯はコースごとに固定）。
// TIME を使うと空の放射輝度マップが毎フレーム作り直されて重い（Godot の sky.cpp）。ここでは使わず、
// 流れる雲は別の半球（clouds.gdshader）で描く。

uniform vec3 top_color : source_color = vec3(0.36, 0.58, 0.88);
uniform vec3 horizon_color : source_color = vec3(0.92, 0.9, 0.88);
uniform vec3 ground_color : source_color = vec3(0.8, 0.8, 0.8);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.75);
uniform vec3 sun_dir = vec3(0.0, 0.5, -0.8);  // 太陽の方向（空のほうへ向く単位ベクトル）
uniform float sun_size = 0.9994;               // 太陽の円盤：方向との内積がこれより大きい所
uniform float sun_halo = 0.6;
uniform float stars = 0.0;
uniform float horizon_height = 0.35;            // 地平の明るい帯の広さ

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 c;
	if (y >= 0.0) {
		c = mix(horizon_color, top_color, pow(smoothstep(0.0, horizon_height, y), 0.7));
	} else {
		c = mix(horizon_color, ground_color, smoothstep(0.0, 0.2, -y));
	}
	vec3 s = normalize(sun_dir);
	float sd = max(dot(d, s), 0.0);
	c += sun_color * pow(sd, 10.0) * sun_halo;
	c += sun_color * pow(sd, 120.0) * sun_halo * 1.5;
	if (!AT_CUBEMAP_PASS) {
		c += sun_color * smoothstep(sun_size, sun_size + 0.0003, sd) * 6.0;
		if (stars > 0.0 && y > 0.0) {
			vec3 g = floor(d * 220.0);
			float h = hash13(g);
			c += vec3(0.85, 0.9, 1.0) * step(0.9978, h) * stars * smoothstep(0.02, 0.3, y) * (0.4 + 0.6 * hash13(g + 3.0));
		}
	}
	COLOR = c;
}
