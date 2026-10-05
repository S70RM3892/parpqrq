shader_type spatial;
// 1人称の脚（機械脚のモデル）を手（hand.gdshader）と同じ「白い装甲と黒い関節」にそろえる。
// 元のテクスチャの明るさで、明るい所を白い装甲、暗い所を黒い金属の関節に塗り分ける（法線・粗さはそのまま）。

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_tex : filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform vec3 armor : source_color = vec3(0.88, 0.88, 0.86);
uniform vec3 joint : source_color = vec3(0.06, 0.065, 0.075);
uniform vec3 accent : source_color = vec3(1.0, 0.42, 0.1);

void fragment() {
	vec3 a = texture(albedo_tex, UV).rgb;
	float lum = dot(a, vec3(0.2126, 0.7152, 0.0722));
	float plate = smoothstep(0.16, 0.3, lum);
	// 元の青く光る所はオレンジの光に
	float glow = smoothstep(0.12, 0.3, a.b - max(a.r, a.g));
	vec3 orm = texture(orm_tex, UV).rgb;
	ALBEDO = mix(joint, armor * (0.85 + 0.3 * lum), plate);
	ROUGHNESS = mix(0.4, 0.3, plate) * mix(0.8, 1.2, orm.g);
	METALLIC = mix(0.75, 0.0, plate);
	CLEARCOAT = plate * 0.5;
	CLEARCOAT_ROUGHNESS = 0.25;
	EMISSION = accent * glow * 1.5;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	RIM = 0.25;
	RIM_TINT = 0.5;
}
