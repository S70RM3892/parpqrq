shader_type spatial;
// 朝の鳥の群れ（backdrop.gd）。1羽 = 横に寝かせた板1枚。群れの中心の周りを回り、羽の先を上下させる。
// INSTANCE_CUSTOM.r = 回る位置のずれ、.g = 半径・羽ばたきのずれ
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.16, 0.17, 0.2);

void vertex() {
	float ph = INSTANCE_CUSTOM.r * 6.2831;
	float rad = 26.0 + INSTANCE_CUSTOM.g * 14.0;
	float a = TIME * 0.22 + ph;
	vec3 center = vec3(cos(a), sin(TIME * 0.7 + ph) * 0.15, sin(a)) * rad;
	vec3 heading = normalize(vec3(-sin(a), 0.0, cos(a)));
	vec3 span = normalize(cross(vec3(0.0, 1.0, 0.0), heading));
	// 板の x = 翼の広がり、y = 体の長さ（QuadMesh）
	float wing = VERTEX.x;
	float flap = sin(TIME * 11.0 + ph * 3.0) * 0.32 * abs(wing) / 0.45;
	VERTEX = center + span * wing + heading * VERTEX.y + vec3(0.0, flap, 0.0);
}

void fragment() {
	ALBEDO = color;
}
