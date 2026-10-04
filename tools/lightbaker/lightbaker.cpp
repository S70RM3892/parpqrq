// 光の焼き込み（ベイク）。コースの屋上・小物の面ごとに「空の見え方（AO）」と「照り返し（2回まで跳ね返った光）」を計算して
// ライトマップのアトラスに書く。Mirror's Edge の白い街の見た目の核（Beast による間接光と色の滲み）の代わり。
// Godot の LightmapGI はスクリプトから焼けず（実行時に組むコースには使えない）、ここで自前に焼く。
//
// 入力：tools/bake_lighting.gd が書くバイナリ（下の read_input）。出力：RGBA float のアトラス（write_output）。
//   R,G,B = 照り返し（他の面から来る光の、余弦で重みを付けた平均の明るさ。表示の単位＝その面の色を掛ける前の値）
//   A     = 空の見え方（余弦で重みを付けた、空に抜ける割合。Godot の環境光に掛ける AO）
// 直射日光は焼かない（実行時の太陽と影がそのまま担う）。
//
// ビルド: g++ -O3 -march=native -fopenmp -std=c++17 -o lightbaker lightbaker.cpp
// 使い方: lightbaker <in.bin> <out.bin>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#ifdef _OPENMP
#include <omp.h>
#endif

struct V3 {
	float x, y, z;
	V3() : x(0), y(0), z(0) {}
	V3(float a, float b, float c) : x(a), y(b), z(c) {}
	V3 operator+(const V3 &o) const { return {x + o.x, y + o.y, z + o.z}; }
	V3 operator-(const V3 &o) const { return {x - o.x, y - o.y, z - o.z}; }
	V3 operator*(float s) const { return {x * s, y * s, z * s}; }
	V3 operator*(const V3 &o) const { return {x * o.x, y * o.y, z * o.z}; }
	V3 &operator+=(const V3 &o) { x += o.x; y += o.y; z += o.z; return *this; }
	float operator[](int i) const { return i == 0 ? x : (i == 1 ? y : z); }
};
static inline float dot(const V3 &a, const V3 &b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
static inline V3 cross(const V3 &a, const V3 &b) { return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}; }
static inline float len(const V3 &a) { return std::sqrt(dot(a, a)); }
static inline V3 norm(const V3 &a) { float l = len(a); return l > 1e-12f ? a * (1.0f / l) : V3(0, 1, 0); }
static inline V3 vmin(const V3 &a, const V3 &b) { return {std::min(a.x, b.x), std::min(a.y, b.y), std::min(a.z, b.z)}; }
static inline V3 vmax(const V3 &a, const V3 &b) { return {std::max(a.x, b.x), std::max(a.y, b.y), std::max(a.z, b.z)}; }

struct Face {
	V3 c[4];   // 角：uv (0,0) (1,0) (1,1) (0,1)
	V3 n;
	int rx, ry, rw, rh;  // アトラスの中の場所（内側の画素数）。rw < 0 = 焼かない面（遮るだけ）
	V3 albedo, emission;
};

struct Tri {
	V3 a, e1, e2;  // a, b-a, c-a
	V3 n;          // 面の外向き
	int face;      // Face の番号（-1 = 面でない遮る三角形）
	int half;      // 0 = 角 0,1,2 / 1 = 角 0,2,3
	V3 albedo, emission;
};

struct Input {
	int atlas_w = 0, atlas_h = 0;
	V3 sun_dir, sun_color;              // 太陽の方向（太陽へ向く）、表示の単位の明るさ（色×強さ）
	V3 sky_top, sky_horizon, sky_ground; // 表示の単位の空の明るさ
	int samples = 128;
	std::vector<Face> faces;
	std::vector<Tri> tris;
};

// --- 読み書き ----------------------------------------------------------------

static bool rd(FILE *f, void *p, size_t n) { return fread(p, 1, n, f) == n; }
static V3 rv3(FILE *f) { float v[3]; rd(f, v, 12); return {v[0], v[1], v[2]}; }

static Tri make_tri(const V3 &a, const V3 &b, const V3 &c, const V3 &n, int face, int half, const V3 &al, const V3 &em) {
	Tri t;
	t.a = a; t.e1 = b - a; t.e2 = c - a; t.n = n; t.face = face; t.half = half; t.albedo = al; t.emission = em;
	return t;
}

static bool read_input(const char *path, Input &in) {
	FILE *f = fopen(path, "rb");
	if (!f) { fprintf(stderr, "cannot open %s\n", path); return false; }
	char magic[4];
	rd(f, magic, 4);
	if (memcmp(magic, "LMB1", 4) != 0) { fprintf(stderr, "bad magic\n"); fclose(f); return false; }
	int32_t wh[2]; rd(f, wh, 8);
	in.atlas_w = wh[0]; in.atlas_h = wh[1];
	in.sun_dir = norm(rv3(f)); in.sun_color = rv3(f);
	in.sky_top = rv3(f); in.sky_horizon = rv3(f); in.sky_ground = rv3(f);
	int32_t s; rd(f, &s, 4); in.samples = s;
	int32_t nf; rd(f, &nf, 4);
	in.faces.resize(nf);
	for (int i = 0; i < nf; i++) {
		Face &fa = in.faces[i];
		for (int k = 0; k < 4; k++) fa.c[k] = rv3(f);
		fa.n = norm(rv3(f));
		int32_t r[4]; rd(f, r, 16);
		fa.rx = r[0]; fa.ry = r[1]; fa.rw = r[2]; fa.rh = r[3];
		fa.albedo = rv3(f); fa.emission = rv3(f);
		in.tris.push_back(make_tri(fa.c[0], fa.c[1], fa.c[2], fa.n, i, 0, fa.albedo, fa.emission));
		in.tris.push_back(make_tri(fa.c[0], fa.c[2], fa.c[3], fa.n, i, 1, fa.albedo, fa.emission));
	}
	int32_t nt; rd(f, &nt, 4);
	for (int i = 0; i < nt; i++) {
		V3 a = rv3(f), b = rv3(f), c = rv3(f);
		V3 al = rv3(f), em = rv3(f);
		V3 n = norm(cross(b - a, c - a));
		in.tris.push_back(make_tri(a, b, c, n, -1, 0, al, em));
	}
	fclose(f);
	return true;
}

// --- BVH ----------------------------------------------------------------------

struct Node {
	V3 lo, hi;
	int left;   // 内部：左の子（右は left+1）。葉：最初の三角形
	int count;  // 葉の三角形の数（0 = 内部）
};

struct BVH {
	std::vector<Node> nodes;
	std::vector<int> idx;
	const std::vector<Tri> *tris = nullptr;

	void build(const std::vector<Tri> &t) {
		tris = &t;
		idx.resize(t.size());
		for (size_t i = 0; i < t.size(); i++) idx[i] = (int)i;
		std::vector<V3> cen(t.size()), lo(t.size()), hi(t.size());
		for (size_t i = 0; i < t.size(); i++) {
			V3 a = t[i].a, b = t[i].a + t[i].e1, c = t[i].a + t[i].e2;
			lo[i] = vmin(a, vmin(b, c));
			hi[i] = vmax(a, vmax(b, c));
			cen[i] = (lo[i] + hi[i]) * 0.5f;
		}
		nodes.reserve(t.size() * 2);
		nodes.push_back({});
		split(0, 0, (int)t.size(), cen, lo, hi);
	}

	void split(int ni, int start, int end, std::vector<V3> &cen, std::vector<V3> &lo, std::vector<V3> &hi) {
		V3 blo(1e30f, 1e30f, 1e30f), bhi(-1e30f, -1e30f, -1e30f), clo = blo, chi = bhi;
		for (int i = start; i < end; i++) {
			int k = idx[i];
			blo = vmin(blo, lo[k]); bhi = vmax(bhi, hi[k]);
			clo = vmin(clo, cen[k]); chi = vmax(chi, cen[k]);
		}
		nodes[ni].lo = blo; nodes[ni].hi = bhi;
		int n = end - start;
		if (n <= 4) { nodes[ni].left = start; nodes[ni].count = n; return; }
		// 一番長い軸で、16区切りの SAH
		V3 ext = chi - clo;
		int axis = ext.x > ext.y ? (ext.x > ext.z ? 0 : 2) : (ext.y > ext.z ? 1 : 2);
		float amin = clo[axis], aext = ext[axis];
		if (aext < 1e-6f) { nodes[ni].left = start; nodes[ni].count = n; return; }
		const int B = 16;
		int bc[B] = {0};
		V3 bl[B], bh[B];
		for (int b = 0; b < B; b++) { bl[b] = V3(1e30f, 1e30f, 1e30f); bh[b] = V3(-1e30f, -1e30f, -1e30f); }
		auto bin_of = [&](int k) { int b = (int)((cen[k][axis] - amin) / aext * B); return std::min(B - 1, std::max(0, b)); };
		for (int i = start; i < end; i++) {
			int k = idx[i], b = bin_of(k);
			bc[b]++; bl[b] = vmin(bl[b], lo[k]); bh[b] = vmax(bh[b], hi[k]);
		}
		auto area = [](const V3 &l, const V3 &h) { V3 d = h - l; if (d.x < 0) return 0.0f; return d.x * d.y + d.y * d.z + d.z * d.x; };
		float best = 1e30f; int best_b = -1;
		for (int s = 1; s < B; s++) {
			V3 l0(1e30f, 1e30f, 1e30f), h0(-1e30f, -1e30f, -1e30f), l1 = l0, h1 = h0;
			int c0 = 0, c1 = 0;
			for (int b = 0; b < s; b++) if (bc[b]) { c0 += bc[b]; l0 = vmin(l0, bl[b]); h0 = vmax(h0, bh[b]); }
			for (int b = s; b < B; b++) if (bc[b]) { c1 += bc[b]; l1 = vmin(l1, bl[b]); h1 = vmax(h1, bh[b]); }
			if (c0 == 0 || c1 == 0) continue;
			float cost = c0 * area(l0, h0) + c1 * area(l1, h1);
			if (cost < best) { best = cost; best_b = s; }
		}
		int mid;
		if (best_b < 0) {
			mid = (start + end) / 2;
			std::nth_element(idx.begin() + start, idx.begin() + mid, idx.begin() + end,
					[&](int a, int b) { return cen[a][axis] < cen[b][axis]; });
		} else {
			mid = (int)(std::partition(idx.begin() + start, idx.begin() + end, [&](int k) { return bin_of(k) < best_b; }) - idx.begin());
			if (mid == start || mid == end) mid = (start + end) / 2;
		}
		int l = (int)nodes.size();
		nodes.push_back({});
		nodes.push_back({});
		nodes[ni].left = l; nodes[ni].count = 0;
		split(l, start, mid, cen, lo, hi);
		split(l + 1, mid, end, cen, lo, hi);
	}

	static inline bool box_hit(const Node &n, const V3 &o, const V3 &inv, float tmax) {
		float t0 = 0.0f, t1 = tmax;
		for (int a = 0; a < 3; a++) {
			float ta = (n.lo[a] - o[a]) * inv[a], tb = (n.hi[a] - o[a]) * inv[a];
			if (ta > tb) std::swap(ta, tb);
			t0 = std::max(t0, ta); t1 = std::min(t1, tb);
			if (t0 > t1) return false;
		}
		return true;
	}

	// 一番近い交点。戻り値：三角形の番号（-1 = 当たらない）、t、重心座標 u,v
	int closest(const V3 &o, const V3 &d, float tmax, float &t_out, float &u_out, float &v_out) const {
		V3 inv(1.0f / (std::fabs(d.x) > 1e-12f ? d.x : 1e-12f), 1.0f / (std::fabs(d.y) > 1e-12f ? d.y : 1e-12f),
				1.0f / (std::fabs(d.z) > 1e-12f ? d.z : 1e-12f));
		int stack[96];
		int sp = 0;
		stack[sp++] = 0;
		int hit = -1;
		float best = tmax;
		while (sp) {
			const Node &n = nodes[stack[--sp]];
			if (!box_hit(n, o, inv, best)) continue;
			if (n.count) {
				for (int i = n.left; i < n.left + n.count; i++) {
					const Tri &t = (*tris)[idx[i]];
					V3 p = cross(d, t.e2);
					float det = dot(t.e1, p);
					if (std::fabs(det) < 1e-10f) continue;
					float id = 1.0f / det;
					V3 s = o - t.a;
					float u = dot(s, p) * id;
					if (u < 0.0f || u > 1.0f) continue;
					V3 q = cross(s, t.e1);
					float v = dot(d, q) * id;
					if (v < 0.0f || u + v > 1.0f) continue;
					float tt = dot(t.e2, q) * id;
					if (tt > 1e-4f && tt < best) { best = tt; hit = idx[i]; u_out = u; v_out = v; }
				}
			} else {
				if (sp < 94) { stack[sp++] = n.left; stack[sp++] = n.left + 1; }
			}
		}
		t_out = best;
		return hit;
	}

	bool any(const V3 &o, const V3 &d, float tmax) const {
		float t, u, v;
		return closest(o, d, tmax, t, u, v) >= 0;
	}
};

// --- 光 -----------------------------------------------------------------------

static inline float smoothstep(float a, float b, float x) {
	float t = std::min(1.0f, std::max(0.0f, (x - a) / (b - a)));
	return t * t * (3.0f - 2.0f * t);
}

static inline V3 lerp(const V3 &a, const V3 &b, float t) { return a + (b - a) * t; }

// shaders/sky.gdshader と同じ空のグラデーション（太陽の円盤とハロは直射に含めるので入れない）
static V3 sky_radiance(const Input &in, const V3 &d) {
	if (d.y >= 0.0f) return lerp(in.sky_horizon, in.sky_top, std::pow(smoothstep(0.0f, 0.35f, d.y), 0.7f));
	return lerp(in.sky_horizon, in.sky_ground, smoothstep(0.0f, 0.2f, -d.y));
}

static inline uint32_t hash_u32(uint32_t x) {
	x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
	return x;
}

static inline float radical_inverse(uint32_t b) {
	b = (b << 16u) | (b >> 16u);
	b = ((b & 0x55555555u) << 1u) | ((b & 0xAAAAAAAAu) >> 1u);
	b = ((b & 0x33333333u) << 2u) | ((b & 0xCCCCCCCCu) >> 2u);
	b = ((b & 0x0F0F0F0Fu) << 4u) | ((b & 0xF0F0F0F0u) >> 4u);
	b = ((b & 0x00FF00FFu) << 8u) | ((b & 0xFF00FF00u) >> 8u);
	return (float)b * 2.3283064365386963e-10f;
}

static void basis(const V3 &n, V3 &t, V3 &b) {
	V3 up = std::fabs(n.y) < 0.95f ? V3(0, 1, 0) : V3(1, 0, 0);
	t = norm(cross(up, n));
	b = cross(n, t);
}

// 余弦で重みを付けた半球の方向（Hammersley を画素ごとにずらす）
static inline V3 cos_dir(const V3 &n, const V3 &t, const V3 &b, int i, int count, float r0, float r1) {
	float u1 = std::fmod((i + 0.5f) / count + r0, 1.0f);
	float u2 = std::fmod(radical_inverse((uint32_t)i) + r1, 1.0f);
	float r = std::sqrt(u1), phi = 6.2831853f * u2;
	float x = r * std::cos(phi), y = r * std::sin(phi), z = std::sqrt(std::max(0.0f, 1.0f - u1));
	return norm(t * x + b * y + n * z);
}

struct Texel {
	V3 pos, n;
	int face;
	bool valid;
};

int main(int argc, char **argv) {
	if (argc < 3) { fprintf(stderr, "usage: lightbaker in.bin out.bin\n"); return 2; }
	Input in;
	if (!read_input(argv[1], in)) return 1;
	const int W = in.atlas_w, H = in.atlas_h;
	BVH bvh;
	bvh.build(in.tris);

	// 焼く画素の位置と向き
	std::vector<int> owner(W * H, -1);  // 画素 → 面
	std::vector<Texel> texels;
	std::vector<int> texel_at(W * H, -1);
	for (int fi = 0; fi < (int)in.faces.size(); fi++) {
		const Face &f = in.faces[fi];
		if (f.rw <= 0) continue;
		for (int y = 0; y < f.rh; y++) {
			for (int x = 0; x < f.rw; x++) {
				float u = f.rw > 1 ? (float)x / (f.rw - 1) : 0.5f;
				float v = f.rh > 1 ? (float)y / (f.rh - 1) : 0.5f;
				// 縁の画素は少し内側から（隣の面と交わる線の上から撃たない）
				float m = 0.35f;
				float uu = f.rw > 1 ? std::min(std::max(u, m / (f.rw - 1)), 1.0f - m / (f.rw - 1)) : 0.5f;
				float vv = f.rh > 1 ? std::min(std::max(v, m / (f.rh - 1)), 1.0f - m / (f.rh - 1)) : 0.5f;
				V3 p = lerp(lerp(f.c[0], f.c[1], uu), lerp(f.c[3], f.c[2], uu), vv);
				int px = f.rx + x, py = f.ry + y;
				texel_at[py * W + px] = (int)texels.size();
				owner[py * W + px] = fi;
				texels.push_back({p + f.n * 0.01f, f.n, fi, true});
			}
		}
	}
	const int T = (int)texels.size();
	fprintf(stderr, "lightbaker: %d faces, %zu tris, %d texels (%dx%d), %d samples\n", (int)in.faces.size(), in.tris.size(), T, W, H, in.samples);

	// 1回目：空の見え方・空の光・日の当たり（照り返しの元）
	std::vector<float> skyvis(T, 0.0f);
	std::vector<V3> sky_e(T), sun_e(T), bounce(T), bounce2(T);
	const int S = std::max(8, in.samples);
	const float RAY_MAX = 400.0f;

	// 当たった所の、面から出ていく光（表示の単位）。lit = 当たった面の画素の今の照らされ方
	auto exitant = [&](int tri, float u, float v, const V3 &dir, const std::vector<V3> &extra) -> V3 {
		const Tri &t = in.tris[tri];
		if (dot(dir, t.n) > 0.0f) return V3(0, 0, 0);  // 裏から当たった（中に入っている）
		if (t.face >= 0 && in.faces[t.face].rw > 0) {
			const Face &f = in.faces[t.face];
			float fu, fv;
			if (t.half == 0) { fu = u + v; fv = v; } else { fu = u; fv = u + v; }
			int x = std::min(f.rw - 1, std::max(0, (int)std::lround(fu * (f.rw - 1))));
			int y = std::min(f.rh - 1, std::max(0, (int)std::lround(fv * (f.rh - 1))));
			int k = texel_at[(f.ry + y) * W + f.rx + x];
			if (k >= 0 && texels[k].valid) {
				V3 e = sun_e[k] + sky_e[k];
				if (!extra.empty()) e += extra[k];
				return t.albedo * e + t.emission;
			}
		}
		// 焼かない面（細い棒など）：太陽が当たる向きなら日向とみなす
		float ndl = std::max(0.0f, dot(t.n, in.sun_dir));
		return t.albedo * (in.sun_color * (ndl * 0.8f) + (in.sky_top + in.sky_horizon) * 0.5f) + t.emission;
	};

	std::atomic<int> done{0};
#pragma omp parallel for schedule(dynamic, 256)
	for (int i = 0; i < T; i++) {
		Texel &tx = texels[i];
		V3 tt, bb;
		basis(tx.n, tt, bb);
		uint32_t h = hash_u32((uint32_t)i * 9781u + 17u);
		float r0 = (h & 0xffff) / 65536.0f, r1 = (h >> 16) / 65536.0f;
		int escape = 0, inside = 0;
		V3 sky(0, 0, 0);
		for (int s = 0; s < S; s++) {
			V3 d = cos_dir(tx.n, tt, bb, s, S, r0, r1);
			float t, u, v;
			int hit = bvh.closest(tx.pos, d, RAY_MAX, t, u, v);
			if (hit < 0) { escape++; sky += sky_radiance(in, d); }
			else if (dot(d, in.tris[hit].n) > 0.0f) inside++;  // 裏から当たった = 閉じた箱の中にいる
		}
		if (inside * 4 > S) tx.valid = false;  // 他の箱の中に埋まっている画素
		skyvis[i] = (float)escape / S;
		sky_e[i] = sky * (1.0f / S);
		float ndl = dot(tx.n, in.sun_dir);
		float vis = (ndl > 0.0f && !bvh.any(tx.pos, in.sun_dir, RAY_MAX)) ? 1.0f : 0.0f;
		sun_e[i] = in.sun_color * (std::max(0.0f, ndl) * vis);
		int d = ++done;
		if (d % 200000 == 0) fprintf(stderr, "  pass 1: %d / %d\n", d, T);
	}

	// 2回目・3回目：照り返し（1回跳ね返り、その結果を使って2回目の跳ね返り）
	for (int pass = 0; pass < 2; pass++) {
		std::vector<V3> &out = pass == 0 ? bounce : bounce2;
		const std::vector<V3> empty;
		const std::vector<V3> &extra = pass == 0 ? empty : bounce;
		int SB = std::max(8, S / 2);
#pragma omp parallel for schedule(dynamic, 256)
		for (int i = 0; i < T; i++) {
			Texel &tx = texels[i];
			if (!tx.valid) continue;
			V3 tt, bb;
			basis(tx.n, tt, bb);
			uint32_t h = hash_u32((uint32_t)i * 7919u + 101u + pass * 3u);
			float r0 = (h & 0xffff) / 65536.0f, r1 = (h >> 16) / 65536.0f;
			V3 acc(0, 0, 0);
			for (int s = 0; s < SB; s++) {
				V3 d = cos_dir(tx.n, tt, bb, s, SB, r0, r1);
				float t, u, v;
				int hit = bvh.closest(tx.pos, d, RAY_MAX, t, u, v);
				if (hit >= 0) acc += exitant(hit, u, v, d, extra);
			}
			out[i] = acc * (1.0f / SB);
		}
		fprintf(stderr, "  bounce %d done\n", pass + 1);
	}

	// アトラスに書く（埋まった画素は隣の有効な画素で埋める。面の外の縁取り1画素も埋める）
	std::vector<float> img((size_t)W * H * 4, 0.0f);
	std::vector<uint8_t> ok(W * H, 0);
	for (int py = 0; py < H; py++) {
		for (int px = 0; px < W; px++) {
			int k = texel_at[py * W + px];
			if (k < 0 || !texels[k].valid) continue;
			V3 b = bounce2[k];
			float *o = &img[((size_t)py * W + px) * 4];
			o[0] = b.x; o[1] = b.y; o[2] = b.z; o[3] = skyvis[k];
			ok[py * W + px] = 1;
		}
	}
	// 面の中で：無効な画素を有効な隣の平均で埋める（数回）
	for (int it = 0; it < 24; it++) {
		std::vector<uint8_t> ok2 = ok;
		bool any = false;
		for (int py = 0; py < H; py++) {
			for (int px = 0; px < W; px++) {
				int fi = owner[py * W + px];
				if (fi < 0 || ok[py * W + px]) continue;
				float acc[4] = {0, 0, 0, 0};
				int c = 0;
				for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++) {
					int qx = px + dx, qy = py + dy;
					if (qx < 0 || qy < 0 || qx >= W || qy >= H) continue;
					if (owner[qy * W + qx] != fi || !ok[qy * W + qx]) continue;
					const float *q = &img[((size_t)qy * W + qx) * 4];
					for (int k = 0; k < 4; k++) acc[k] += q[k];
					c++;
				}
				if (c) {
					float *o = &img[((size_t)py * W + px) * 4];
					for (int k = 0; k < 4; k++) o[k] = acc[k] / c;
					ok2[py * W + px] = 1;
					any = true;
				}
			}
		}
		ok = ok2;
		if (!any) break;
	}
	// 面ごとに軽くぼかす（ノイズ取り。面の外には滲ませない）
	{
		std::vector<float> src = img;
		for (int py = 0; py < H; py++) {
			for (int px = 0; px < W; px++) {
				int fi = owner[py * W + px];
				if (fi < 0 || !ok[py * W + px]) continue;
				float acc[4] = {0, 0, 0, 0};
				float wsum = 0;
				for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++) {
					int qx = px + dx, qy = py + dy;
					if (qx < 0 || qy < 0 || qx >= W || qy >= H) continue;
					if (owner[qy * W + qx] != fi || !ok[qy * W + qx]) continue;
					float w = (dx == 0 && dy == 0) ? 4.0f : ((dx == 0 || dy == 0) ? 2.0f : 1.0f);
					const float *q = &src[((size_t)qy * W + qx) * 4];
					for (int k = 0; k < 4; k++) acc[k] += q[k] * w;
					wsum += w;
				}
				float *o = &img[((size_t)py * W + px) * 4];
				for (int k = 0; k < 4; k++) o[k] = acc[k] / wsum;
			}
		}
	}
	// 面の外の縁取り（双線形の補間で隣の面の色を拾わないように）
	std::vector<uint8_t> pad(W * H, 0);
	for (int fi = 0; fi < (int)in.faces.size(); fi++) {
		const Face &f = in.faces[fi];
		if (f.rw <= 0) continue;
		for (int y = -1; y <= f.rh; y++) {
			for (int x = -1; x <= f.rw; x++) {
				if (x >= 0 && y >= 0 && x < f.rw && y < f.rh) continue;
				int px = f.rx + x, py = f.ry + y;
				if (px < 0 || py < 0 || px >= W || py >= H) continue;
				int sx = f.rx + std::min(f.rw - 1, std::max(0, x)), sy = f.ry + std::min(f.rh - 1, std::max(0, y));
				memcpy(&img[((size_t)py * W + px) * 4], &img[((size_t)sy * W + sx) * 4], 16);
				pad[py * W + px] = 1;
			}
		}
	}
	// 面に属さない画素は「空が全部見えて照り返しなし」
	for (int py = 0; py < H; py++) for (int px = 0; px < W; px++) {
		float *o = &img[((size_t)py * W + px) * 4];
		if (owner[py * W + px] < 0 && !pad[py * W + px]) o[3] = 1.0f;
	}

	FILE *f = fopen(argv[2], "wb");
	if (!f) { fprintf(stderr, "cannot write %s\n", argv[2]); return 1; }
	fwrite("LMO1", 1, 4, f);
	int32_t wh[2] = {W, H};
	fwrite(wh, 4, 2, f);
	fwrite(img.data(), 4, img.size(), f);
	fclose(f);
	fprintf(stderr, "lightbaker: wrote %s\n", argv[2]);
	return 0;
}
