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
