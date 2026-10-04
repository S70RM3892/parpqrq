class_name Checkpoint
extends Area3D
## 通ると、落下した時の戻り先がここになる（向きはこのノードの向き）。リトライはスタートへ戻る。


func _ready() -> void:
	body_entered.connect(func(body: Node3D) -> void:
		if body is Player:
			(body as Player).checkpoint = global_transform)
