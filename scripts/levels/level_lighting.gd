class_name LevelLighting
extends RefCounted
## 焼いた光（ライトマップ）を読み込んで街の材質（level.gdshader）に渡す。
## 中身は tools/bake_lighting.tscn が焼いた assets/lightmaps/<id>.res（LightmapData：画像と面の並びの指紋）。
## 形が焼いた時と違えば（レシピを変えて焼き直していない）使わない。焼いていない時と同じ見た目に戻る。

const DIR := "res://assets/lightmaps/"


static func path_for(id: String) -> String:
	return DIR + id + ".res"


## geo の形に合うライトマップがあれば渡して true。無ければ切って false
static func apply(geo: LevelGeometry, id: String) -> bool:
	var data: LightmapData = null
	var path := path_for(id)
	if geo.lightmap_hash != "" and ResourceLoader.exists(path):
		data = load(path) as LightmapData
	var ok := data != null and data.fingerprint == geo.lightmap_hash and data.image != null
	if ok:
		RenderingServer.global_shader_parameter_set(&"level_lightmap", ImageTexture.create_from_image(data.image))
	RenderingServer.global_shader_parameter_set(&"lightmap_on", 1.0 if ok else 0.0)
	return ok


## 今のライトマップが形に合っているか（テスト用。焼き直しを忘れたら落とす）
static func is_current(geo: LevelGeometry, id: String) -> bool:
	var path := path_for(id)
	if geo.lightmap_hash == "" or not ResourceLoader.exists(path):
		return false
	var data := load(path) as LightmapData
	return data != null and data.fingerprint == geo.lightmap_hash
