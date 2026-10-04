class_name VaultProbe
extends RefCounted
## 周りの地形を調べる（仕様書 3章「パルクール技」）。
## probe: ヴォルト（奥行きが vault_max_depth 以下なら飛び越え、深ければ上に乗る）
## ledge: クライム・レッジグラブの縁 / side_wall・front_wall: ウォールランの壁

## 判定結果。位置はすべてワールド座標の足元
class Result:
	var start: Vector3
	var land: Vector3
	var hand: Vector3        ## 手を着く点（上面の手前の縁）
	var dir: Vector3         ## 越える向き（水平・単位）
	var front_dist: float    ## start→前面（dir方向）
	var back_dist: float     ## start→背面。乗るだけなら上面の着地点まで
	var back_face: float     ## start→障害物の奥の面（手で押し切る所。ヴォルトジャンプのPerfectの基準）
	var top_y: float
	var onto: bool           ## true = 上に乗る（深い障害物）
	var land_on_ground: bool ## 着地点の下に床があるか


static func probe(body: CharacterBody3D, move_dir: Vector3, speed: float, p: MovementParams,
		radius: float, height: float) -> Result:
	if move_dir.length_squared() < 0.01:
		return null
	var space := body.get_world_3d().direct_space_state
	var feet := body.global_position
	var excl: Array[RID] = [body.get_rid()]
	var reach := radius + maxf(0.6, speed * p.vault_reach_time)

	# 1. 前面：膝の高さで前方へ
	var knee := feet + Vector3.UP * minf(0.35, p.vault_min_height - 0.1)
	var hit := _ray(space, knee, knee + move_dir * reach, excl)
	if hit.is_empty():
		return null
	var n: Vector3 = hit.normal
	n.y = 0.0
	if n.length() < 0.7:
		return null  # 壁ではなく斜面
	var dir := -n.normalized()
	# 自動補正：±auto_align 以内なら障害物に正対する向きで越える
	if rad_to_deg(dir.angle_to(move_dir)) > p.vault_auto_align_deg:
		return null
	var front: Vector3 = hit.position

	# 2. 上面：前面の少し奥を上から下へ
	var top_xz := front + dir * 0.12
	var from_y := feet.y + p.vault_max_height + 0.3
	var top_hit := _ray(space, Vector3(top_xz.x, from_y, top_xz.z), Vector3(top_xz.x, feet.y + 0.1, top_xz.z), excl)
	if top_hit.is_empty() or top_hit.normal.y < 0.8:
		return null
	var top_y: float = top_hit.position.y
	var h := top_y - feet.y
	if h < p.vault_min_height or h > p.vault_max_height:
		return null

	var r := Result.new()
	r.start = feet
	r.dir = dir
	r.hand = top_hit.position
	r.top_y = top_y
	r.front_dist = (front - feet).dot(dir)

	# 3. 背面：奥から手前へ水平に
	var probe_y := top_y - 0.08
	var far := front + dir * (p.vault_max_depth + 0.12)
	var back_hit := _ray(space, Vector3(far.x, probe_y, far.z), Vector3(front.x, probe_y, front.z) + dir * 0.02, excl)
	var mid: Vector3
	if back_hit.is_empty():
		# 深い：上に乗る
		r.onto = true
		r.back_dist = r.front_dist + radius + 0.35
		r.back_face = r.back_dist
		r.land = feet + dir * r.back_dist
		r.land.y = top_y
		r.land_on_ground = true
		mid = r.land
	else:
		var back_dist: float = (back_hit.position - feet).dot(dir)
		var after := radius + clampf(speed * 0.1, 0.4, 1.2)
		r.back_face = back_dist
		r.back_dist = back_dist + after
		r.land = feet + dir * r.back_dist
		mid = feet + dir * (r.front_dist + back_dist) * 0.5
		mid.y = top_y
		var ground := _ray(space, r.land + Vector3.UP * (h + 0.1), r.land + Vector3.DOWN * 3.0, excl)
		r.land_on_ground = not ground.is_empty() and ground.normal.y > 0.7
		r.land.y = ground.position.y if r.land_on_ground else feet.y

	# 4. 体が通る空間：上面の上と着地点にカプセルを置いてみる
	if _blocked(space, mid + Vector3.UP * (p.vault_clearance + 0.03), radius, height, excl):
		return null
	if _blocked(space, r.land + Vector3.UP * 0.05, radius, height, excl):
		return null
	return r


## 手の届く縁を探す（クライム・レッジグラブ）。上面が足元から lo〜hi の高さにあり、上に立てる場所。
## 戻り値は onto=true の Result（hand = 縁、land = 上面の立ち位置、front_dist = 前面まで）。
static func ledge(body: CharacterBody3D, move_dir: Vector3, reach: float, lo: float, hi: float,
		align_deg: float, radius: float, height: float) -> Result:
	if move_dir.length_squared() < 0.01:
		return null
	var space := body.get_world_3d().direct_space_state
	var feet := body.global_position
	var excl: Array[RID] = [body.get_rid()]
	var hit := {}
	for h: float in [minf(lo, 1.0), 1.2, 1.7]:
		var from := feet + Vector3.UP * h
		hit = _ray(space, from, from + move_dir * (radius + reach), excl)
		if not hit.is_empty() and absf((hit.normal as Vector3).y) < 0.3:
			break
		hit = {}
	if hit.is_empty():
		return null
	var n: Vector3 = hit.normal
	n.y = 0.0
	var dir := -n.normalized()
	if rad_to_deg(dir.angle_to(move_dir)) > align_deg:
		return null
	var front: Vector3 = hit.position
	var top_xz := front + dir * 0.12
	var top_hit := _ray(space, Vector3(top_xz.x, feet.y + hi + 0.3, top_xz.z), Vector3(top_xz.x, feet.y + lo - 0.05, top_xz.z), excl)
	if top_hit.is_empty() or (top_hit.normal as Vector3).y < 0.8:
		return null
	var top_y: float = top_hit.position.y
	if top_y - feet.y < lo or top_y - feet.y > hi:
		return null
	var r := Result.new()
	r.start = feet
	r.dir = dir
	r.hand = top_hit.position
	r.top_y = top_y
	r.onto = true
	r.land_on_ground = true
	r.front_dist = (front - feet).dot(dir)
	r.back_dist = r.front_dist + radius + 0.3
	r.back_face = r.back_dist
	r.land = feet + dir * r.back_dist
	r.land.y = top_y
	if _blocked(space, r.land + Vector3.UP * 0.05, radius, height, excl):
		return null
	return r


## 進行方向の左右の壁。{normal, point, side(+1=右, -1=左)}、無ければ空
static func side_wall(body: CharacterBody3D, move_dir: Vector3, dist: float) -> Dictionary:
	var space := body.get_world_3d().direct_space_state
	var chest := body.global_position + Vector3.UP * 1.0
	var right := move_dir.cross(Vector3.UP).normalized()
	for side: float in [1.0, -1.0]:
		var hit := _ray(space, chest, chest + right * side * dist, [body.get_rid()] as Array[RID])
		if not hit.is_empty() and absf((hit.normal as Vector3).y) < 0.3:
			return {"normal": hit.normal, "point": hit.position, "side": side}
	return {}


## 正面の壁。無ければ空
static func front_wall(body: CharacterBody3D, dir: Vector3, dist: float, height: float = 1.0) -> Dictionary:
	var space := body.get_world_3d().direct_space_state
	var from := body.global_position + Vector3.UP * height
	var hit := _ray(space, from, from + dir * dist, [body.get_rid()] as Array[RID])
	if hit.is_empty() or absf((hit.normal as Vector3).y) > 0.3:
		return {}
	return hit


## 体の周りで一番近い壁（ウォールキック）。dirs の向きへ胸の高さから探す。
## {normal: 水平の単位ベクトル, dist: 体の中心から壁面までの垂直距離}、無ければ空
static func nearest_wall(body: CharacterBody3D, dirs: Array[Vector3], dist: float, height: float = 1.0) -> Dictionary:
	var space := body.get_world_3d().direct_space_state
	var from := body.global_position + Vector3.UP * height
	var excl: Array[RID] = [body.get_rid()]
	var best := {}
	var best_d := INF
	for d: Vector3 in dirs:
		var hit := _ray(space, from, from + d * dist, excl)
		if hit.is_empty() or absf((hit.normal as Vector3).y) > 0.3:
			continue
		var n: Vector3 = hit.normal
		n = Vector3(n.x, 0.0, n.z).normalized()
		var perp := (from - (hit.position as Vector3)).dot(n)
		if perp < best_d:
			best_d = perp
			best = {"normal": n, "dist": perp}
	return best


## 足元から depth 以内に床があるか（着地の直前）
static func floor_below(body: CharacterBody3D, depth: float) -> bool:
	var from := body.global_position + Vector3.UP * 0.1
	var hit := _ray(body.get_world_3d().direct_space_state, from, from + Vector3.DOWN * (depth + 0.1), [body.get_rid()] as Array[RID])
	return not hit.is_empty() and (hit.normal as Vector3).y > 0.7


## 立てるか（スライド後に起き上がれるか）
static func can_stand(body: CharacterBody3D, radius: float, height: float) -> bool:
	return not _blocked(body.get_world_3d().direct_space_state, body.global_position + Vector3.UP * 0.02,
			radius, height, [body.get_rid()] as Array[RID])


static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, excl: Array[RID]) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = excl
	return space.intersect_ray(q)


## 体の形の問い合わせは使い回す（毎フレーム呼ばれる：照準点の先読み・技の判定）
static var _shape: CapsuleShape3D
static var _query: PhysicsShapeQueryParameters3D


static func _blocked(space: PhysicsDirectSpaceState3D, feet: Vector3, radius: float, height: float, excl: Array[RID]) -> bool:
	if _query == null:
		_shape = CapsuleShape3D.new()
		_query = PhysicsShapeQueryParameters3D.new()
		_query.shape = _shape
	_shape.radius = radius
	_shape.height = height
	_query.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (height * 0.5))
	_query.exclude = excl
	return not space.intersect_shape(_query, 1).is_empty()
