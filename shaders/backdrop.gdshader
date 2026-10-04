shader_type spatial;
// 遠景の街（backdrop.gd の MultiMesh 1つで描く）。箱の種類（INSTANCE_CUSTOM.g）ごとに外壁を描き分ける。
// INSTANCE_CUSTOM.r = ビルごとの乱数、.g = 種類（backdrop.gd の Kind）
// 窓の奥の部屋は level.gdshader と同じ interior mapping（city.gdshaderinc）。箱の角は法線を曲げて光らせる。
render_mode cull_back;

#include "res://shaders/city.gdshaderinc"

global uniform float night;

varying float v_seed;
varying float v_kind;
varying vec3 v_local;
varying vec3 v_size;
varying vec3 v_lnormal;
varying vec3 v_tan;
varying vec3 v_bin;

void vertex() {
	v_seed = INSTANCE_CUSTOM.r;
	v_kind = INSTANCE_CUSTOM.g;
	v_local = VERTEX;
	v_lnormal = NORMAL;
	v_size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	// 面の右向き（外から見て）
	vec3 t = abs(NORMAL.x) > 0.5 ? vec3(0.0, 0.0, -sign(NORMAL.x)) : vec3(sign(NORMAL.z), 0.0, 0.0);
	v_tan = (MODELVIEW_MATRIX * vec4(t, 0.0)).xyz;
	v_bin = (MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

float stripes(float x, float w) {
	return step(0.5, fract(x / w));
}

void fragment() {
	int kind = int(v_kind + 0.5);
	bool side = abs(v_lnormal.y) < 0.5;
	vec3 tl = abs(v_lnormal.x) > 0.5 ? vec3(0.0, 0.0, -sign(v_lnormal.x)) : vec3(sign(v_lnormal.z), 0.0, 0.0);
	float size_u = abs(v_lnormal.x) > 0.5 ? v_size.z : v_size.x;
	float u = (dot(v_local, tl) + 0.5) * size_u;          // 面の左端からの横の位置 m
	float up = (v_local.y + 0.5) * v_size.y;              // 下からの高さ m
	float down = (0.5 - v_local.y) * v_size.y;            // 上端からの深さ m
	vec2 face_size = side ? vec2(size_u, v_size.y) : vec2(v_size.x, v_size.z);
	vec2 fp = side ? vec2(u, up) : (v_local.xz + 0.5) * vec2(v_size.x, v_size.z);
	float dist = length(VERTEX);
	vec3 tan_v = normalize(v_tan);
	vec3 bin_v = normalize(v_bin);
	vec3 nrm = NORMAL;
	float rnd = v_seed;

	vec3 col = vec3(0.84, 0.84, 0.82) * (0.9 + 0.16 * rnd);
	float rough = 0.85;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float ao = 1.0;

	if (side) {
		if (kind == 0 && down > 1.0) {
			// 板状のビル：普通の窓
			Window w = city_window(u, down - 1.0, rnd, VERTEX, tan_v, bin_v, nrm, night);
			col = mix(col, w.albedo, w.mask);
			rough = mix(rough, w.rough, w.mask);
			metal = mix(metal, w.metal, w.mask);
			emit += w.emission;
			ao *= w.cavity;
		} else if (kind == 1 || kind == 5) {
			// ガラスのカーテンウォール（1.5 m の縦枠、各階に不透明の帯）。5 = 黒いガラス
			float bay = fract(u / 1.5);
			float flr = fract(down / 3.6);
			float mull = 1.0 - step(0.04, min(bay, 1.0 - bay) * 1.5);
			float spandrel = step(0.78, flr);
			vec3 glass = kind == 1 ? mix(vec3(0.05, 0.08, 0.1), vec3(0.06, 0.1, 0.09), rnd) : vec3(0.015, 0.016, 0.02);
			col = glass;
			rough = 0.05;
			metal = 0.0;
			if (spandrel > 0.5 || mull > 0.5) {
				col = kind == 1 ? vec3(0.7, 0.72, 0.74) : vec3(0.08, 0.08, 0.09);
				rough = 0.4;
				metal = 0.5;
			} else {
				vec2 cell = floor(vec2(u / 1.5, down / 3.6));
				float lit = step(kind == 1 ? 0.45 : 0.8, hash12(vec2(floor(cell.x / 4.0), cell.y) + rnd * 37.0));
				vec3 office = vec3(0.85, 0.92, 1.0) * (0.7 + 0.3 * hash12(cell + 3.0));
				emit += mix(office * 0.04, office * lit * 1.6, night);
			}
		} else if (kind == 2) {
			// 集合住宅：各階のベランダ（床の帯と手すり壁）、奥に窓とカーテン
			float flr_h = 2.9;
			float fy = fract(down / flr_h) * flr_h;   // 階の上端から
			vec2 cell = floor(vec2(u / 5.4, down / flr_h));
			float unit_x = fract(u / 5.4) * 5.4;
			float slab = 1.0 - step(0.18, fy);                         // ベランダの床の小口
			float rail = step(flr_h - 1.1, fy) * (1.0 - slab);          // 手すり壁
			float wall = 1.0 - step(0.25, min(unit_x, 5.4 - unit_x));   // 戸境の壁
			col = vec3(0.86, 0.85, 0.82) * (0.92 + 0.1 * rnd);
			if (slab < 0.5 && rail < 0.5 && wall < 0.5) {
				// 奥の窓（暗い）とカーテン
				vec3 curtain = mix(vec3(0.75, 0.7, 0.62), vec3(0.55, 0.62, 0.7), hash12(cell + rnd * 11.0));
				col = mix(vec3(0.05, 0.06, 0.07), curtain * 0.6, step(0.6, hash12(cell * 1.3 + 7.0)));
				ao = 0.55;
				rough = 0.2;
				float lit = step(0.55, hash12(cell + rnd * 91.0));
				emit += mix(curtain * 0.03, curtain * vec3(1.0, 0.82, 0.6) * lit * 1.3, night);
			} else if (rail > 0.5) {
				col *= 0.93;
				nrm = normalize(nrm + bin_v * 0.25 * (1.0 - smoothstep(flr_h - 1.1, flr_h - 1.0, fy)));
			} else if (slab > 0.5) {
				col *= 1.05;
				nrm = normalize(nrm - bin_v * 0.5);
			}
		} else if (kind == 3) {
			// 細長い雑居ビル：タイル貼り、小さな窓、片側に縦の看板（夜は光る）
			col = mix(vec3(0.72, 0.62, 0.5), vec3(0.62, 0.6, 0.58), rnd);
			col *= 1.0 - 0.06 * stripes(u + down, 0.2) * (1.0 - smoothstep(20.0, 60.0, dist));
			vec2 cell = floor(vec2(u / 2.4, down / 3.2));
			vec2 cf = fract(vec2(u / 2.4, down / 3.2));
			float win = step(0.25, cf.x) * step(cf.x, 0.75) * step(0.3, cf.y) * step(cf.y, 0.75);
			col = mix(col, vec3(0.06, 0.07, 0.08), win);
			float lit = step(0.5, hash12(cell + rnd * 51.0)) * win;
			emit += vec3(1.0, 0.8, 0.55) * lit * night * 1.2;
			if (u < 1.6 && down > 2.0 && down < v_size.y * 0.75) {
				vec3 sc = vec3(1.0, 0.3, 0.55);
				if (rnd > 0.33) sc = vec3(0.2, 0.85, 1.0);
				if (rnd > 0.66) sc = vec3(1.0, 0.85, 0.25);
				float glyph = step(0.35, hash12(floor(vec2(u / 0.5, down / 0.9)) + rnd * 7.0));
				col = mix(vec3(0.95), sc, glyph);
				emit += mix(vec3(0.95), sc, glyph) * mix(0.15, 2.4, night);
			}
		} else if (kind == 4 && down > 1.0) {
			// 古いビル：くすんだ色、雨の染み、小さめの窓
			col = mix(vec3(0.62, 0.6, 0.56), vec3(0.55, 0.57, 0.6), rnd);
			float streak = hash12(vec2(floor(u / 0.6), rnd * 13.0));
			col *= 1.0 - 0.2 * smoothstep(0.5, 1.0, streak) * (1.0 - smoothstep(0.0, 8.0, down));
			Window w = city_window(u * 1.15, (down - 1.0) * 1.1, rnd + 0.37, VERTEX, tan_v, bin_v, nrm, night);
			col = mix(col, w.albedo, w.mask);
			rough = mix(rough, w.rough, w.mask);
			emit += w.emission * 0.8;
			ao *= w.cavity;
		} else if (kind == 7) {
			// 屋上の物（塔屋・水槽・室外機）
			col = mix(vec3(0.8, 0.8, 0.78), vec3(0.62, 0.7, 0.78), step(0.5, fract(rnd * 7.0)));
			col *= 1.0 - 0.12 * stripes(up, 0.25) * step(0.7, fract(rnd * 3.0));
		} else if (kind == 9) {
			// 大きな画面：流れる色の帯と、ゆっくり動く丸
			vec2 a = vec2(u / face_size.x, up / face_size.y);
			float t = TIME * 0.15;
			vec3 c1 = 0.5 + 0.5 * cos(6.2831 * (vec3(0.0, 0.33, 0.67) + a.x * 0.6 + t));
			float circle = 1.0 - smoothstep(0.18, 0.2, length((a - vec2(0.5 + 0.3 * sin(t * 3.0), 0.55)) * vec2(face_size.x / face_size.y, 1.0)));
			vec3 img = mix(c1, vec3(1.0), circle * 0.85);
			img *= 0.8 + 0.2 * step(0.5, fract(a.y * face_size.y / 0.25));  // 走査線
			col = img;
			emit += img * mix(0.6, 2.2, max(night, 0.35));
		} else if (kind == 10) {
			// 鉄骨：電波塔は赤白の帯、クレーンは黄色
			bool crane = rnd > 0.85;
			vec3 band = stripes(up + floor(rnd * 3.0) * 12.0, 24.0) > 0.5 ? vec3(0.85, 0.18, 0.12) : vec3(0.92, 0.92, 0.9);
			col = crane ? vec3(0.95, 0.72, 0.1) : band;
			rough = 0.5;
			metal = 0.3;
		} else if (kind == 11 || kind == 6) {
			// 高架・笠木・柱（コンクリ）
			col = vec3(0.7, 0.7, 0.68) * (0.95 + 0.08 * rnd);
		} else if (kind == 12) {
			// 電車：銀の車体、窓の帯（夜は灯る）、裾の色帯
			col = vec3(0.78, 0.8, 0.82);
			metal = 0.6;
			rough = 0.3;
			float win_band = step(0.48, v_local.y + 0.5) * step(v_local.y + 0.5, 0.78);
			float pane = step(0.12, fract(u / 1.6));
			col = mix(col, vec3(0.05, 0.06, 0.07), win_band * pane);
			emit += vec3(0.95, 0.95, 0.85) * win_band * pane * mix(0.05, 1.8, night);
			float stripe = step(0.2, v_local.y + 0.5) * step(v_local.y + 0.5, 0.3);
			col = mix(col, vec3(0.1, 0.55, 0.3), stripe);
		}
	} else {
		// 上面：屋上の防水シート・床（少し暗く、ムラ）
		col = vec3(0.7, 0.7, 0.68) * (0.9 + 0.15 * hash12(floor(fp / 3.0) + rnd * 9.0));
		if (kind == 9 || kind == 12) {
			col = vec3(0.3, 0.32, 0.34);
		}
	}
	if (kind == 8) {
		// 航空障害灯：夜に赤く点滅
		col = vec3(0.6, 0.05, 0.03);
		float blink = step(0.5, fract(TIME * 0.5 + rnd * 3.0));
		emit = vec3(1.0, 0.06, 0.03) * (0.4 + 3.0 * blink) * mix(0.3, 1.0, night);
	}

	// 角の丸み（光が角に乗る）。遠いと細すぎるので消す
	vec2 fw = max(fwidth(fp), vec2(1e-4));
	float r = min(0.12, 0.1 * min(face_size.x, face_size.y));
	float vis = smoothstep(0.6, 2.0, r / max(fw.x, fw.y));
	vec4 ed = vec4(fp.x, face_size.x - fp.x, fp.y, face_size.y - fp.y);
	vec4 k = 1.0 - smoothstep(vec4(0.0), vec4(r), ed);
	if (side && vis > 0.0) {
		nrm = normalize(nrm + (tan_v * (k.y - k.x) + bin_v * (k.w - k.z)) * 0.7 * vis);
	}
	// 足元（谷底）は暗く：通りに落ちる陰の代わり
	if (side) {
		ao *= mix(0.55, 1.0, smoothstep(0.0, 25.0, up));
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
	AO = ao;
	NORMAL = nrm;
}
