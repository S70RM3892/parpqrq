shader_type spatial;
// 谷底の通り（backdrop.gd）。ビルの格子の間に道路と歩道。夕方・夜は車のライトが流れる（白 = こちら向き、赤 = 向こう向き）。
// 高さフォグで白く・暗く消える所なので、模様は粗くてよい。

global uniform float night;

uniform float cell = 24.0;
uniform vec2 origin = vec2(0.0);

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

// 1本の道（along = 道に沿った位置、across = 道の中心からの横の位置）の車。戻り値：rgb = 光、a = 車体
vec4 cars(float along, float across, float road_id) {
	float lane = sign(across);
	float in_lane = 1.0 - step(0.85, abs(abs(across) - 1.7));
	float spacing = 16.0 + 14.0 * hash11(road_id * 3.1 + lane * 7.0);
	float speed = (9.0 + 6.0 * hash11(road_id * 1.7 + lane)) * lane;
	float s = (along + TIME * speed) / spacing + hash11(road_id + lane * 13.0);
	float car_i = floor(s);
	float f = fract(s) * spacing;
	float present = step(0.35, hash11(car_i * 1.31 + road_id * 5.0 + lane));
	float body = step(f, 4.2) * in_lane * present;
	// 前の端（進む向き）にライト
	float head = lane > 0.0 ? step(f, 0.6) : step(3.6, f) * step(f, 4.2);
	vec3 light = lane > 0.0 ? vec3(1.0, 0.95, 0.85) * 2.6 : vec3(1.0, 0.08, 0.04) * 1.8;
	return vec4(light * head * body, body);
}

void fragment() {
	vec2 w = v_world.xz - origin;
	vec2 g = w / cell - 0.5;
	vec2 id = floor(g + 0.5);
	vec2 f = (g - id) * cell;  // 道の中心（ビルの格子の間）からの位置 m
	float road_x = 1.0 - step(4.5, abs(f.x));
	float road_z = 1.0 - step(4.5, abs(f.y));
	float road = max(road_x, road_z);
	vec3 col = mix(vec3(0.34, 0.34, 0.33), vec3(0.13, 0.135, 0.14), road);
	vec3 emit = vec3(0.0);
	// 白線
	float dash = step(0.5, fract(w.y / 6.0)) * (1.0 - step(0.08, abs(f.x))) * road_x * (1.0 - road_z)
			+ step(0.5, fract(w.x / 6.0)) * (1.0 - step(0.08, abs(f.y))) * road_z * (1.0 - road_x);
	col = mix(col, vec3(0.7), dash * 0.6);
	if (road > 0.5) {
		vec4 a = road_x * (1.0 - road_z) > 0.5 ? cars(w.y, f.x, id.x) : vec4(0.0);
		vec4 b = road_z * (1.0 - road_x) > 0.5 ? cars(w.x, -f.y, id.y + 101.0) : vec4(0.0);
		vec4 c = a + b;
		col = mix(col, vec3(0.2, 0.22, 0.25), min(c.a, 1.0));
		emit += c.rgb * smoothstep(0.15, 0.6, night);
	}
	// 夜は街灯で道がうっすら明るい
	emit += vec3(1.0, 0.75, 0.45) * road * 0.05 * night;
	ALBEDO = col;
	ROUGHNESS = 0.9;
	EMISSION = emit;
}
