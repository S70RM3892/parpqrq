shader_type spatial;
// 街の材質（仕様書 6章：白い街に1色だけ差す）。level_geometry.gd がまとめたメッシュ用。
// 頂点データ:
//   UV      = 面の中の位置 0〜1（側面は v=0 が下）
//   UV2     = 面の大きさ m
//   CUSTOM0 = (部品の底からの高さ m, 面の種類 0=側面 1=上面 2=下面, 部品ごとの乱数, 0)
//   CUSTOM1 = 焼いた光（ライトマップ）のアトラスの uv（焼かない面は -1）
//   TANGENT = 面の u の向き（BINORMAL = v の向き）
//   COLOR   = 色味（LIGHT は発光色）
// 白い街の「色」は材質の albedo が決め、写真のテクスチャ（assets/textures、CC0）は明るさのムラ・粗さ・凹み・法線だけを足す。
// 焼いた光（tools/bake_lighting.tscn → LevelLighting）：A = 空の見え方（環境光と映り込みに AO として掛ける）、
// RGB = 照り返し（白い壁に日向の床やオレンジの壁の色が滲む。Mirror's Edge の見た目の核）。
// 箱の角は法線を曲げて丸く見せる（光が角に乗る。頂点は増やさない）。ビルの窓は奥に部屋が見える（interior mapping）。

#include "res://shaders/city.gdshaderinc"

global uniform float route_strength; // 1 = ルートカラーON、0 = OFF（設定）
global uniform float night;          // 0 = 昼 〜 1 = 夜（窓・照明が灯る）
global uniform sampler2D level_lightmap : filter_linear, repeat_disable;
global uniform float lightmap_on;    // 1 = このコースの焼いた光がある
global uniform float wet;            // 0 = 乾いた屋上 〜 1 = 雨上がり（水たまり）

uniform int pattern = 0; // 0 無地 1 コンクリ 2 金属 3 ガラス 4 砂利 5 ビル 6 ルート 7 照明 8 工事の縞
uniform vec3 albedo : source_color = vec3(0.92, 0.92, 0.9);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float specular_value : hint_range(0.0, 1.0) = 0.5;
uniform float emission_energy = 0.0;
uniform vec3 route_color : source_color = vec3(1.0, 0.416, 0.102);
uniform vec3 stripe_color : source_color = vec3(0.12, 0.12, 0.13);

// 写真のテクスチャ（R = 明るさのムラ 0.5 が平均、G = 粗さ、B = 凹み）。上面用と側面用
uniform sampler2D detail_tex : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D side_detail_tex : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D side_normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m = 2.0;               // テクスチャ1枚の実寸 m
uniform float side_tile_m = 2.0;
uniform float detail_strength = 0.0;      // 明るさのムラの強さ（0 = テクスチャなし）
uniform float side_detail_strength = 0.0;
uniform float normal_strength = 0.0;
uniform float tex_rough = 0.0;            // 粗さをテクスチャに寄せる割合
uniform float bevel_m = 0.03;             // 角の丸み m
uniform float grime = 0.0;                // 上端からの雨だれ・足元の汚れ

uniform float bounce_strength = 1.0;  // 照り返しの強さ
uniform float ao_strength = 1.0;      // 空の見え方を環境光に掛ける強さ

varying vec4 v_custom;
varying vec2 v_lm;

void vertex() {
	v_custom = CUSTOM0;
	v_lm = CUSTOM1.xy;
}

// 格子の線（太さ w は格子1つに対する割合）。遠くでは消してちらつかせない
float grid_line(vec2 g, float w, float fade) {
	vec2 f = abs(fract(g) - 0.5);
	return smoothstep(0.5 - w, 0.5 - w * 0.4, max(f.x, f.y)) * fade;
}

// 滑らかな値ノイズ 0〜1（水たまりの形）
float vnoise(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 size = max(UV2, vec2(0.001));
	vec2 p = UV * size;
	float h = v_custom.x;
	bool side = v_custom.y < 0.5;
	bool top = v_custom.y > 0.5 && v_custom.y < 1.5;
	float rnd = v_custom.z;
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = length(VERTEX);
	float near = 1.0 - smoothstep(25.0, 70.0, dist);
	float nfade = 1.0 - smoothstep(35.0, 110.0, dist);
	// 縁までの距離（左・右・下・上）
	vec4 ed = vec4(p.x, size.x - p.x, p.y, size.y - p.y);
	float edge_d = min(min(ed.x, ed.y), min(ed.z, ed.w));

	vec3 col = albedo * COLOR.rgb;
	float rough = roughness_value;
	float metal = metallic_value;
	float spec = specular_value;
	vec3 emit = vec3(0.0);
	float cavity = 1.0;
	vec2 nxy = vec2(0.0);  // 接空間の法線の傾き（テクスチャ＋角の丸み）

	// --- 写真のテクスチャ ---
	bool use_side = !top && side_detail_strength > 0.0;
	float dstr = use_side ? side_detail_strength : detail_strength;
	if (dstr > 0.0 && pattern != 7) {
		float tm = use_side ? side_tile_m : tile_m;
		// 面ごとに少しずらす（同じ模様が並んで見えないように）
		vec2 st = vec2(p.x, -p.y) / tm + vec2(rnd * 7.31, rnd * 3.17);
		vec3 dt = use_side ? texture(side_detail_tex, st).rgb : texture(detail_tex, st).rgb;
		// 大きなムラ（タイルの繰り返しを崩す）
		float macro = use_side ? texture(side_detail_tex, st * 0.173 + vec2(0.31, 0.71)).r : texture(detail_tex, st * 0.173 + vec2(0.31, 0.71)).r;
		col *= clamp(mix(1.0, dt.r * 2.0, dstr), 0.0, 1.6) * mix(1.0, 0.85 + macro * 0.3, dstr);
		rough = mix(rough, mix(rough, dt.g, 0.6), tex_rough);
		cavity = mix(1.0, dt.b, dstr);
		vec2 tn = use_side ? texture(side_normal_tex, st).rg : texture(normal_tex, st).rg;
		nxy += (tn * 2.0 - 1.0) * normal_strength * nfade;
	}

	if (pattern == 1 || pattern == 5) {
		// コンクリ：屋上は1.5 mの目地（走ると床が流れて速さが分かる）。目地は少し凹む
		if (top) {
			vec2 g = world.xz / 1.5;
			col *= 0.97 + 0.05 * hash12(floor(g));
			float gl = grid_line(g, 0.022, near);
			col *= 1.0 - gl * 0.16;
			cavity *= 1.0 - gl * 0.3;
		} else if (side && pattern == 1) {
			col *= 1.0 - grid_line(vec2(0.25, world.y / 1.2), 0.03, near) * 0.05;
		}
	}
	if (pattern == 5 && side && size.y - p.y > 1.3) {
		// ビル：上端の手すり壁（1.3 m）より下に窓。ビルごとに外壁の種類が違う（普通の窓・ベランダ・ガラス・古いビル）。
		// 奥に部屋が見え、夜は所々灯る（city.gdshaderinc）
		int fk = rnd < 0.5 ? 0 : (rnd < 0.7 ? 2 : (rnd < 0.85 ? 1 : 4));
		Facade f = city_facade(fk, p.x, size.y - p.y - 1.3, rnd, col, VERTEX, TANGENT, BINORMAL, NORMAL, night);
		col = f.albedo;
		rough = f.rough;
		metal = f.metal;
		spec = mix(spec, 0.5, step(rough, 0.3));
		emit += f.emission;
		nxy += f.bend;
		cavity *= f.ao;
	} else if (pattern == 2) {
		// 金属：側面は細いリブ
		if (!top) {
			nxy.y += (smoothstep(0.0, 0.5, fract(p.y / 0.14)) - 0.5) * 0.25 * nfade;
		}
	} else if (pattern == 3) {
		// ガラス：枠と映り込み（反射は空の放射輝度マップ。画面空間反射はMobileで使えない）
		vec2 g = p / vec2(1.5, 1.5);
		float frame = grid_line(g, 0.05, 1.0);
		col = mix(vec3(0.05, 0.07, 0.08), vec3(0.22, 0.23, 0.25), frame);
		rough = mix(0.03, 0.45, frame);
		metal = mix(0.0, 0.7, frame);
		spec = 0.5;
		emit += vec3(0.55, 0.7, 0.95) * night * (1.0 - frame) * 0.22;
	} else if (pattern == 6) {
		// ルートカラー：遠くからは強く光り、近づくと淡くなる（仕様書 6章）。OFFなら白。塗装は角が擦れて下地が出る
		vec3 base = mix(vec3(0.92, 0.92, 0.9) * COLOR.rgb, route_color, route_strength);
		// 塗装した鋼板のパネル（1.2 m × 2.4 m）。継ぎ目は凹み、パネルごとに色がわずかに違う
		vec2 pg = p / vec2(1.2, top ? 1.2 : 2.4);
		vec2 pc = floor(pg);
		vec2 pf = fract(pg) * vec2(1.2, top ? 1.2 : 2.4);
		vec2 pd = min(pf, vec2(1.2, top ? 1.2 : 2.4) - pf);
		float seam = (1.0 - smoothstep(0.006, 0.018, min(pd.x, pd.y))) * nfade;
		base *= 0.93 + 0.12 * hash12(pc + rnd * 5.3);
		vec2 sk = 1.0 - smoothstep(vec2(0.0), vec2(0.035), pd);
		nxy -= vec2(sign(pf.x - 0.6) * sk.x, sign(pf.y - (top ? 0.6 : 1.2)) * sk.y) * 0.35 * nfade;
		float wear = (1.0 - smoothstep(0.0, 0.05, edge_d)) * step(0.5, hash12(floor(p * 9.0) + rnd * 13.0) + 0.3);
		col = mix(base * mix(1.0, col.r / max(albedo.r, 0.01), 0.7), vec3(0.62, 0.6, 0.57), wear * 0.55 * route_strength);
		col *= 1.0 - seam * 0.45;
		cavity *= 1.0 - seam * 0.5;
		rough = mix(0.45, 0.75, wear);
		float far_k = smoothstep(8.0, 45.0, dist);
		emit += route_color * route_strength * mix(0.06, 0.9, far_k) * (1.0 + night * 1.2) * (1.0 - wear * 0.6);
	} else if (pattern == 7) {
		// 照明・ネオン：頂点色で光る。夜に強く。大きな面（看板）には広告の絵（グラデーション・丸い印・文字の帯・縁）
		col = COLOR.rgb;
		vec3 e = COLOR.rgb;
		if (size.x > 2.0 && size.y > 1.2 && !top) {
			vec2 a = p / size;
			float r1 = hash12(vec2(rnd * 41.0, 3.0));
			vec3 c2 = mix(vec3(1.0), COLOR.rgb.gbr, 0.65);
			e = mix(COLOR.rgb * 0.55, COLOR.rgb, a.y);                                   // 下から上へのグラデーション
			vec2 lc = vec2(r1 > 0.5 ? 0.24 : 0.76, 0.55);
			float logo = 1.0 - smoothstep(0.17, 0.19, length((a - lc) * vec2(size.x / size.y, 1.0)));
			e = mix(e, c2 * 1.4, logo);
			float tx = r1 > 0.5 ? 0.5 : 0.08;
			for (int i = 0; i < 3; i++) {
				float y0 = 0.62 - float(i) * 0.17;
				float wbar = (i == 0 ? 0.42 : 0.3) * (0.7 + 0.3 * hash12(vec2(rnd * 9.0, float(i))));
				float bar = step(tx, a.x) * step(a.x, tx + wbar) * step(y0, a.y) * step(a.y, y0 + (i == 0 ? 0.09 : 0.05));
				e = mix(e, vec3(1.0), bar * 0.9);
			}
			float border = 1.0 - step(0.03, min(min(a.x, 1.0 - a.x), min(a.y, 1.0 - a.y)) * size.y);
			e = mix(e, vec3(0.08), border);
			col = e;
			e *= 0.42;  // 広告の面は小さな照明より暗く（夜に白く飛ばさない）
		}
		emit += e * emission_energy * mix(0.35, 1.0, night);
	} else if (pattern == 8) {
		// 工事の縞
		float s = step(0.5, fract((p.x + p.y) / 0.5));
		col = mix(col, stripe_color, s);
	}

	// 雨上がりの水たまり（時間帯の wet）：広い屋上の面だけ。縁からは離し、まわりは湿って暗い。
	// 水面は平らでつるつる（空・看板・街灯が映る。映り込みは空の放射輝度マップと反射プローブ）
	if (wet > 0.0 && top && (pattern == 1 || pattern == 5) && min(size.x, size.y) > 3.0) {
		float n = vnoise(world.xz / 3.4 + rnd * 17.0) * 0.72 + vnoise(world.xz / 0.9) * 0.28;
		float th = mix(0.86, 0.52, wet);
		float inner = smoothstep(0.5, 1.4, edge_d);
		float puddle = smoothstep(th, th + 0.035, n) * inner;
		float damp = smoothstep(th - 0.14, th, n) * inner;
		col *= mix(1.0, 0.55, max(damp * 0.55, puddle));
		rough = mix(mix(rough, 0.4, damp * 0.7), 0.04, puddle);
		nxy *= 1.0 - puddle * 0.95;
		cavity = mix(cavity, 1.0, puddle);
	}
	if (wet > 0.0 && top && pattern != 7) {
		rough *= 1.0 - wet * 0.25;  // 全体に少し湿る
	}

	// 汚れ：側面の上端から垂れる雨だれと、足元のはね（白い壁が真っ白にならない）
	if (grime > 0.0 && side) {
		float col_id = floor(p.x / 0.35 + rnd * 17.0);
		float streak = hash12(vec2(col_id, rnd * 31.0));
		float len = 0.6 + streak * 3.2;
		float drip = (1.0 - smoothstep(0.0, len, ed.w)) * smoothstep(0.35, 0.9, streak);
		float splash = 1.0 - smoothstep(0.0, 0.35, h);
		col *= 1.0 - grime * (drip * 0.22 + splash * 0.18);
	}

	// 角の丸み：縁に近いほど法線を外へ曲げる（光が角に乗る）。画面で細すぎる所は消す（ちらつき防止）
	if (pattern != 7 && bevel_m > 0.0) {
		float r = min(bevel_m, 0.12 * min(size.x, size.y));
		vec2 fw = max(fwidth(p), vec2(1e-5));
		float vis = smoothstep(0.6, 2.0, r / max(fw.x, fw.y));
		vec4 k = 1.0 - smoothstep(vec4(0.0), vec4(r), ed);
		vec2 b = vec2(k.y - k.x, k.w - k.z) * 0.75 * vis;
		nxy += b;
	}

	bool baked = lightmap_on > 0.5 && v_lm.x >= 0.0;
	if (side && !baked) {
		// 焼いた光が無い時：床に接する所の陰と、上端のすぐ下の細い影（縁が読める）
		col *= mix(0.66, 1.0, smoothstep(0.0, 1.3, h));
		float lip = size.y - p.y;
		col *= 1.0 - (smoothstep(0.09, 0.11, lip) - smoothstep(0.14, 0.2, lip)) * 0.16;
	}

	float ao = cavity;
	if (baked) {
		vec4 lm = texture(level_lightmap, v_lm);
		ao *= mix(1.0, lm.a, ao_strength);
		emit += col * (1.0 - metal) * (lm.rgb * lm.rgb * 4.0) * bounce_strength * cavity;
	}

	nxy = clamp(nxy, vec2(-0.85), vec2(0.85));
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = emit;
	AO = ao;
	AO_LIGHT_AFFECT = 0.0;
	NORMAL_MAP = vec3(nxy * 0.5 + 0.5, 1.0);
}
