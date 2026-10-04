shader_type spatial;
// 街の材質（仕様書 6章：白い街に1色だけ差す）。level_geometry.gd がまとめたメッシュ用。
// 頂点データ:
//   UV      = 面の中の位置 0〜1（側面は v=0 が下）
//   UV2     = 面の大きさ m
//   CUSTOM0 = (部品の底からの高さ m, 面の種類 0=側面 1=上面 2=下面, 部品ごとの乱数, 0)
//   COLOR   = 色味（LIGHT は発光色）
// ベイクした光（LightmapGI）の代わりに、接地の陰と縁の線をここで描く（実行時に組むコースは焼けないため。描画の追加コストなし）

global uniform float route_strength; // 1 = ルートカラーON、0 = OFF（設定）
global uniform float night;          // 0 = 昼 〜 1 = 夜（窓・照明が灯る）

uniform int pattern = 0; // 0 無地 1 コンクリ 2 金属 3 ガラス 4 砂利 5 ビル 6 ルート 7 照明 8 工事の縞
uniform vec3 albedo : source_color = vec3(0.92, 0.92, 0.9);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float specular_value : hint_range(0.0, 1.0) = 0.5;
uniform float emission_energy = 0.0;
uniform vec3 route_color : source_color = vec3(1.0, 0.416, 0.102);
uniform vec3 stripe_color : source_color = vec3(0.12, 0.12, 0.13);
uniform vec3 window_color : source_color = vec3(0.30, 0.36, 0.44);
uniform vec3 window_light : source_color = vec3(1.0, 0.8, 0.55);

varying vec4 v_custom;

void vertex() {
	v_custom = CUSTOM0;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// 格子の線（太さ w は格子1つに対する割合）。遠くでは消してちらつかせない
float grid_line(vec2 g, float w, float fade) {
	vec2 f = abs(fract(g) - 0.5);
	return smoothstep(0.5 - w, 0.5 - w * 0.4, max(f.x, f.y)) * fade;
}

void fragment() {
	vec2 size = max(UV2, vec2(0.001));
	vec2 p = UV * size;
	float edge_d = min(min(p.x, size.x - p.x), min(p.y, size.y - p.y));
	float h = v_custom.x;
	bool side = v_custom.y < 0.5;
	bool top = v_custom.y > 0.5 && v_custom.y < 1.5;
	float rnd = v_custom.z;
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = length(VERTEX);
	float near = 1.0 - smoothstep(25.0, 70.0, dist);

	vec3 col = albedo * COLOR.rgb;
	float rough = roughness_value;
	float metal = metallic_value;
	float spec = specular_value;
	vec3 emit = vec3(0.0);

	if (pattern == 1 || pattern == 5) {
		// コンクリ：屋上は1.5 mの目地とタイルごとのわずかなムラ（走ると床が流れて速さが分かる）
		if (top) {
			vec2 g = world.xz / 1.5;
			col *= 0.965 + 0.05 * hash12(floor(g));
			col *= 1.0 - grid_line(g, 0.025, near) * 0.10;
		} else if (side && pattern == 1) {
			col *= 1.0 - grid_line(vec2(0.25, world.y / 1.2), 0.03, near) * 0.06;
		}
	}
	if (pattern == 5 && side && size.y - p.y > 1.3) {
		// ビル：上端の手すり壁（1.3 m）より下に窓。夜は所々灯る
		vec2 c = vec2(p.x / 3.0, (size.y - p.y - 1.3) / 3.4);
		vec2 f = fract(c);
		float win = step(0.16, f.x) * step(f.x, 0.84) * step(0.22, f.y) * step(f.y, 0.86);
		float lit = step(0.52, hash12(floor(c) + rnd * 91.7)) * night;
		col = mix(col, window_color * (0.85 + 0.3 * hash12(floor(c) + 7.0)), win);
		rough = mix(rough, 0.12, win);
		spec = mix(spec, 0.9, win);
		emit += window_light * win * lit * 2.2;
	} else if (pattern == 2) {
		// 金属：細いリブ
		col *= 1.0 - grid_line(vec2(0.25, p.y / 0.14), 0.12, near) * 0.12;
	} else if (pattern == 3) {
		// ガラス：枠と映り込み（反射は空の放射輝度マップ。画面空間反射はMobileで使えない）
		vec2 g = p / vec2(1.5, 1.5);
		float frame = grid_line(g, 0.05, 1.0);
		col = mix(col, vec3(0.22, 0.23, 0.25), frame);
		rough = mix(0.04, 0.5, frame);
		metal = mix(0.25, 0.6, frame);
		spec = 1.0;
		emit += vec3(0.6, 0.75, 1.0) * night * (1.0 - frame) * 0.25;
	} else if (pattern == 4) {
		// 砂利：細かい粒
		float n = hash12(floor(world.xz / 0.06));
		col *= 0.8 + 0.32 * n * near + 0.16 * (1.0 - near);
	} else if (pattern == 6) {
		// ルートカラー：遠くからは強く光り、近づくと淡くなる（仕様書 6章）。OFFなら白
		col = mix(vec3(0.92, 0.92, 0.9) * COLOR.rgb, route_color, route_strength);
		float far_k = smoothstep(8.0, 45.0, dist);
		emit += route_color * route_strength * mix(0.08, 0.9, far_k) * (1.0 + night * 1.2);
	} else if (pattern == 7) {
		// 照明・ネオン：頂点色で光る。夜に強く
		col = COLOR.rgb;
		emit += COLOR.rgb * emission_energy * mix(0.35, 1.0, night);
	} else if (pattern == 8) {
		// 工事の縞
		float s = step(0.5, fract((p.x + p.y) / 0.5));
		col = mix(col, stripe_color, s);
	}

	// 面の境目を少し暗く（形の輪郭を読みやすく）
	col *= 1.0 - (1.0 - smoothstep(0.0, 0.035, edge_d)) * 0.14;
	if (side) {
		// 床に接する所の陰と、上端のすぐ下の細い影（縁が読める）
		col *= mix(0.66, 1.0, smoothstep(0.0, 1.3, h));
		float lip = size.y - p.y;
		col *= 1.0 - (smoothstep(0.09, 0.11, lip) - smoothstep(0.14, 0.2, lip)) * 0.16;
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = emit;
}
