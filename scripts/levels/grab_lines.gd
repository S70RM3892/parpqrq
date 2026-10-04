class_name GrabLines
extends Node
## 掴める棒と線：スイングバー（水平の棒）とジップライン（斜めの線）。
## CourseBuilder / Greybox が置き、Player が空中で手の届くものを探す（細い棒は物理のレイで拾いにくいので、位置で持つ）。
## 見た目と当たり判定は LevelGeometry に積む（ここは位置だけ。描画の呼び出しは増えない）。

enum Kind { BAR, ZIP }

const GROUP := &"grab_lines"
## 端からこれより内側だけ掴める（m）
const END_MARGIN := 0.35

## {kind: Kind, a: Vector3, b: Vector3}。ZIP は a が高い端、b が低い端
var lines: Array[Dictionary] = []


func _enter_tree() -> void:
	add_to_group(GROUP)


func add_bar(a: Vector3, b: Vector3) -> void:
	lines.append(bar(a, b))


## high → low に滑り降りる
func add_zip(high: Vector3, low: Vector3) -> void:
	lines.append(zip(high, low))


## 線のデータだけ作る（CourseBuilder が集めて、Course が GrabLines に渡す）
static func bar(a: Vector3, b: Vector3) -> Dictionary:
	return {"kind": Kind.BAR, "a": a, "b": b}


static func zip(high: Vector3, low: Vector3) -> Dictionary:
	return {"kind": Kind.ZIP, "a": high, "b": low}


## 足元 feet の真上あたりで手が届く線を探す。
## バー：進む向き dir とおおむね直交し、体の前後 reach 以内、足元から lo〜hi の高さ。
## ジップライン：体の軸から横 zip_reach 以内、足元から lo〜hi の高さ（終点の手前2 mまで）。
## 戻り値 {index, kind, point, d（a からの距離）, length}。無ければ空
func find(feet: Vector3, dir: Vector3, reach: float, zip_reach: float, lo: float, hi: float, skip: int) -> Dictionary:
	var best := {}
	var best_score := INF
	for i: int in lines.size():
		if i == skip:
			continue
		var l := lines[i]
		var a: Vector3 = l.a
		var b: Vector3 = l.b
		var ab := b - a
		var length := ab.length()
		if length < 0.5:
			continue
		var u := ab / length
		var uh := Vector3(u.x, 0.0, u.z)
		if uh.length() < 0.2:
			continue  # 縦の線は掴めない
		var uh_n := uh.normalized()
		# 足元を線の水平の投影へ下ろし、そこでの線上の点
		var along_h := Vector3(feet.x - a.x, 0.0, feet.z - a.z).dot(uh_n)
		var d := along_h / uh.length()
		var p := a + u * d
		var rel := p - feet
		var side := Vector3(rel.x, 0.0, rel.z)
		if rel.y < lo or rel.y > hi:
			continue
		if int(l.kind) == Kind.BAR:
			if d < END_MARGIN or d > length - END_MARGIN:
				continue
			if absf(dir.dot(uh_n)) > 0.77:
				continue  # 棒に沿って進んでいる（40°より浅い）
			var fwd := (dir - uh_n * dir.dot(uh_n)).normalized()
			var off := side.dot(fwd)
			if off < -reach * 0.6 or off > reach:
				continue
			var score := absf(off) + absf(rel.y - 2.0) * 0.3
			if score < best_score:
				best_score = score
				best = {"index": i, "kind": Kind.BAR, "point": p, "d": d, "length": length}
		else:
			if d < 0.0 or d > length - 2.0:
				continue
			if side.length() > zip_reach:
				continue
			var score2 := side.length() + absf(rel.y - 2.0) * 0.3
			if score2 < best_score:
				best_score = score2
				best = {"index": i, "kind": Kind.ZIP, "point": p, "d": d, "length": length}
	return best


## 全ての GrabLines から探す
static func find_all(tree: SceneTree, feet: Vector3, dir: Vector3, reach: float, zip_reach: float,
		lo: float, hi: float, skip_node: GrabLines, skip: int) -> Dictionary:
	for n: Node in tree.get_nodes_in_group(GROUP):
		var g := n as GrabLines
		if g == null:
			continue
		var r := g.find(feet, dir, reach, zip_reach, lo, hi, skip if g == skip_node else -1)
		if not r.is_empty():
			r["owner"] = g
			return r
	return {}
