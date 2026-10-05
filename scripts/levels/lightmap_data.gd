class_name LightmapData
extends Resource
## 焼いた光（tools/bake_lighting.tscn が書く）。
## image: RGBA8。RGB = 照り返しの明るさを sqrt(値 / 4) で詰めたもの、A = 空の見え方（AO）
## fingerprint: 焼いた時の LevelGeometry.lightmap_hash（面の並びの指紋）

@export var image: Image
@export var fingerprint: String = ""
@export var sun_dir: Vector3 = Vector3.UP
