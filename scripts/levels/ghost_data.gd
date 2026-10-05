class_name GhostData
extends Resource
## 開発者のゴースト（tools/record_dev_ghosts.tscn が自動走行の近道を全部通る走りを記録して書く）。
## run = RunRecording.to_dict()、time = その走りのタイム、fingerprint = 記録した時のコースの形（LevelGeometry.lightmap_hash）

@export var run: Dictionary = {}
@export var time: float = 0.0
@export var fingerprint: String = ""


static func path_for(id: String) -> String:
	return "res://assets/ghosts/%s.res" % id
