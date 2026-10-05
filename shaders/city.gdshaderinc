// 街の材質の共通部品（level.gdshader と backdrop.gdshader が使う）。

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

struct Window {
	float mask;      // 1 = 窓（ガラス・枠・窓台）
	vec3 albedo;
	float rough;
	float metal;
	vec3 emission;   // 部屋の中の光（昼は薄く、夜は灯った部屋だけ明るい）
	vec2 nxy;        // 接空間の法線の傾き（窓台・枠の角）
	float cavity;    // 窓の奥まり（凹みの陰）
};

// ビルの窓。px = 壁の横の位置 m、py = 窓の帯の上端から下へ m、seed = ビルごとの乱数。
// 窓の奥の部屋は interior mapping（ガラスの面から視線を部屋の箱に伸ばし、当たった壁・床・天井の色を出す）で描く。
// view_pos・tangent・binormal・normal はビュー空間（fragment の VERTEX・TANGENT・BINORMAL・NORMAL）
Window city_window(float px, float py, float seed, vec3 view_pos, vec3 tangent, vec3 binormal, vec3 normal, float night_k) {
	Window w;
	w.mask = 0.0;
	w.albedo = vec3(0.0);
	w.rough = 0.8;
	w.metal = 0.0;
	w.emission = vec3(0.0);
	w.nxy = vec2(0.0);
	w.cavity = 1.0;
	const float CW = 3.0;   // 1部屋の幅
	const float CH = 3.4;   // 1階の高さ
	const float L = 0.5, R = 2.5, T = 0.72, B = 2.9;  // 窓の左・右・上・下（部屋の中の位置 m。上・下は階の上端から）
	const float FR = 0.06;  // 枠の太さ
	vec2 cell = floor(vec2(px / CW, py / CH));
	vec2 q = vec2(px - cell.x * CW, py - cell.y * CH);
	float dist = length(view_pos);
	float sill_d = q.y - B;  // 窓台：窓の下 0〜0.1 m
	if (q.x > L - 0.08 && q.x < R + 0.08 && sill_d > 0.0 && sill_d < 0.1) {
		w.mask = 1.0;
		w.albedo = vec3(0.78, 0.78, 0.76);
		w.rough = 0.6;
		w.nxy = vec2(0.0, 0.55 * (1.0 - sill_d / 0.1));
		return w;
	}
	if (q.x < L || q.x > R || q.y < T || q.y > B) {
		return w;
	}
	w.mask = 1.0;
	float r = hash12(cell + seed * 91.7);
	float r2 = hash12(cell * 1.7 + seed * 13.3 + 5.0);
	float r3 = hash12(cell * 2.3 + seed * 7.1 + 11.0);
	// 枠と真ん中の縦枠
	float fx = min(q.x - L, R - q.x);
	float fy = min(q.y - T, B - q.y);
	float mull = abs(q.x - (L + R) * 0.5);
	if (min(fx, fy) < FR || mull < FR * 0.5) {
		w.albedo = vec3(0.32, 0.34, 0.36);
		w.rough = 0.35;
		w.metal = 0.6;
		return w;
	}
	// 窓の奥まり（縁ほど暗い）
	w.cavity = mix(0.55, 1.0, smoothstep(0.0, 0.22, min(fx, fy)));
	// ガラス：黒に近く、つるつる（空が映る）
	w.albedo = vec3(0.015, 0.018, 0.022);
	w.rough = 0.04 + r3 * 0.05;
	w.metal = 0.0;
	// 部屋の箱の中の座標（x = 窓の幅で 0〜1、y = 下から 0〜1、z = 奥へ 0〜1）
	vec3 rd = normalize(view_pos);
	vec3 d = vec3(dot(rd, tangent) / (R - L), dot(rd, binormal) / (B - T), -dot(rd, normal) / 3.2);
	vec3 o = vec3((q.x - L) / (R - L), 1.0 - (q.y - T) / (B - T), 0.0);
	float tx = d.x > 0.0 ? (1.0 - o.x) / d.x : -o.x / min(d.x, -1e-4);
	float ty = d.y > 0.0 ? (1.0 - o.y) / d.y : -o.y / min(d.y, -1e-4);
	float tz = 1.0 / max(d.z, 1e-4);
	float t = min(min(tx, ty), tz);
	vec3 hit = o + d * t;
	vec3 wall = mix(vec3(0.82, 0.8, 0.74), vec3(0.62, 0.7, 0.78), r2);
	vec3 room;
	if (t == tz) {
		room = wall * (0.85 + 0.15 * step(0.7, fract(hit.x * 2.0 + r3)));  // 奥の壁（棚や扉の影）
	} else if (t == ty) {
		room = d.y < 0.0 ? vec3(0.32, 0.28, 0.24) * (0.8 + 0.4 * r3) : vec3(0.9, 0.9, 0.88);  // 床 / 天井
	} else {
		room = wall * 0.78;
	}
	room *= mix(1.0, 0.55, hit.z);  // 奥ほど暗い
	// ブラインド（上から何割か下りている部屋）
	float blind = r2 > 0.55 ? (r3 * 0.75) : 0.0;
	bool blinds = o.y > 1.0 - blind;
	if (blinds) {
		room = vec3(0.86, 0.84, 0.78) * (0.85 + 0.15 * step(0.5, fract(o.y * 26.0)));
	}
	// 遠くでは部屋の細部を平均にする（ちらつき防止）
	float far_k = smoothstep(45.0, 110.0, dist);
	room = mix(room, wall * 0.6, far_k);
	bool lit = r > 0.5;
	vec3 lamp = r3 > 0.4 ? vec3(1.0, 0.78, 0.52) : vec3(0.82, 0.9, 1.0);
	// 天井の照明の明るさ（真ん中が明るい）
	float spot = 1.0;
	if (!blinds && t == ty && d.y > 0.0) {
		spot = 1.0 + 2.5 * (1.0 - smoothstep(0.0, 0.25, length(hit.xz - vec2(0.5, 0.35))));
	}
	vec3 day = room * 0.09;
	vec3 nite = lit ? room * lamp * 2.4 * spot : room * 0.015;
	w.emission = mix(day, nite, night_k);
	return w;
}

struct Facade {
	vec3 albedo;
	float rough;
	float metal;
	vec3 emission;
	float ao;
	vec2 bend;      // 接空間の法線の傾き（x = 横、y = 上）
};

// ビルの外壁（窓の帯の上端から下の部分）。kind: 0 普通の窓、1 ガラスのカーテンウォール、2 ベランダのある集合住宅、
// 4 古いビル、5 黒いガラス。u = 壁の横の位置 m、down = 窓の帯の上端から下へ m、base = 壁の色
Facade city_facade(int kind, float u, float down, float rnd, vec3 base, vec3 view_pos, vec3 tangent, vec3 binormal,
		vec3 normal, float night_k) {
	Facade f;
	f.albedo = base;
	f.rough = 0.85;
	f.metal = 0.0;
	f.emission = vec3(0.0);
	f.ao = 1.0;
	f.bend = vec2(0.0);
	if (kind == 1 || kind == 5) {
		// ガラスのカーテンウォール（1.5 m の縦枠、各階に不透明の帯）
		float bay = fract(u / 1.5);
		float flr = fract(down / 3.6);
		float mull = 1.0 - step(0.04, min(bay, 1.0 - bay) * 1.5);
		float spandrel = step(0.78, flr);
		f.albedo = kind == 1 ? mix(vec3(0.05, 0.08, 0.1), vec3(0.06, 0.1, 0.09), rnd) : vec3(0.015, 0.016, 0.02);
		f.rough = 0.05;
		if (spandrel > 0.5 || mull > 0.5) {
			f.albedo = kind == 1 ? vec3(0.7, 0.72, 0.74) : vec3(0.08, 0.08, 0.09);
			f.rough = 0.4;
			f.metal = 0.5;
			f.bend.x = mull > 0.5 ? (bay < 0.5 ? 0.4 : -0.4) : 0.0;
		} else {
			vec2 cell = floor(vec2(u / 1.5, down / 3.6));
			float lit = step(kind == 1 ? 0.45 : 0.8, hash12(vec2(floor(cell.x / 4.0), cell.y) + rnd * 37.0));
			vec3 office = vec3(0.85, 0.92, 1.0) * (0.7 + 0.3 * hash12(cell + 3.0));
			f.emission = mix(office * 0.04, office * lit * 1.6, night_k);
		}
	} else if (kind == 2) {
		// 集合住宅：各階のベランダ（床の小口と手すり壁）、奥に窓とカーテン、戸境の壁
		const float FH = 2.9;
		float fy = fract(down / FH) * FH;
		vec2 cell = floor(vec2(u / 5.4, down / FH));
		float unit_x = fract(u / 5.4) * 5.4;
		float slab = 1.0 - step(0.18, fy);
		float rail = step(FH - 1.1, fy) * (1.0 - slab);
		float wall = 1.0 - step(0.25, min(unit_x, 5.4 - unit_x));
		f.albedo = base * (0.92 + 0.1 * rnd);
		if (slab < 0.5 && rail < 0.5 && wall < 0.5) {
			vec3 curtain = mix(vec3(0.75, 0.7, 0.62), vec3(0.55, 0.62, 0.7), hash12(cell + rnd * 11.0));
			f.albedo = mix(vec3(0.05, 0.06, 0.07), curtain * 0.6, step(0.6, hash12(cell * 1.3 + 7.0)));
			f.ao = 0.55;
			f.rough = 0.2;
			float lit = step(0.55, hash12(cell + rnd * 91.0));
			f.emission = mix(curtain * 0.03, curtain * vec3(1.0, 0.82, 0.6) * lit * 1.3, night_k);
		} else if (rail > 0.5) {
			f.albedo *= 0.93;
			f.bend.y = 0.25 * (1.0 - smoothstep(FH - 1.1, FH - 1.0, fy));
		} else if (slab > 0.5) {
			f.albedo *= 1.05;
			f.bend.y = -0.5;
		}
	} else {
		// 0 普通の窓・4 古いビル（くすんだ色と雨の染み、小さめの窓）
		bool old = kind == 4;
		if (old) {
			f.albedo = base * mix(vec3(0.72, 0.7, 0.66), vec3(0.64, 0.66, 0.7), rnd);
			float streak = hash12(vec2(floor(u / 0.6), rnd * 13.0));
			f.albedo *= 1.0 - 0.2 * smoothstep(0.5, 1.0, streak) * (1.0 - smoothstep(0.0, 8.0, down));
		}
		Window w = old ? city_window(u * 1.15, down * 1.1, rnd + 0.37, view_pos, tangent, binormal, normal, night_k)
				: city_window(u, down, rnd, view_pos, tangent, binormal, normal, night_k);
		f.albedo = mix(f.albedo, w.albedo, w.mask);
		f.rough = mix(f.rough, w.rough, w.mask);
		f.metal = mix(f.metal, w.metal, w.mask);
		f.emission = w.emission * (old ? 0.8 : 1.0);
		f.ao = w.cavity;
		f.bend = w.nxy;
	}
	return f;
}
