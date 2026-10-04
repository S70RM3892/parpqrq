shader_type spatial;
// 1人称の機械の手（scripts/player/body/hand_model.gd）。部品を関節ごとに1つのメッシュにまとめ、材質を頂点色で描き分ける。
// COLOR.rgb = 色（sRGB）、COLOR.a = 材質の番号 / 4（0 白い装甲、1 黒い関節、2 オレンジの光、3 手のひらのゴム、4 袖の布）
render_mode cull_back;

void fragment() {
	int id = int(round(COLOR.a * 4.0));
	vec3 col = pow(COLOR.rgb, vec3(2.2));
	float rough = 0.85;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float rim = 0.0;
	if (id == 0) {
		rough = 0.3;
		rim = 0.25;
		CLEARCOAT = 0.6;
		CLEARCOAT_ROUGHNESS = 0.2;
	} else if (id == 1) {
		rough = 0.38;
		metal = 0.75;
		rim = 0.3;
	} else if (id == 2) {
		rough = 0.4;
		emit = col * 1.6;
	} else if (id == 3) {
		rough = 0.85;
	} else {
		rough = 0.95;
		rim = 0.45;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
	RIM = rim;
	RIM_TINT = 0.5;
}
