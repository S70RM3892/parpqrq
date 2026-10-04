class_name VaultProbe
extends RefCounted
## 前方の障害物をヴォルトできるかを調べる（仕様書 3章「パルクール技」）。
## 奥行きが vault_max_depth 以下なら飛び越え、それより深ければ上に乗る。

## 判定結果。位置はすべてワールド座標の足元
class Result:
	var start: Vector3
	var land: Vector3
	var hand: Vector3        ## 手を着く点（上面の手前の縁）
	var dir: Vector3         ## 越える向き（水平・単位）
	var front_dist: float    ## start→前面（dir方向）
	var back_dist: float     ## start→背面。乗るだけなら上面の着地点まで
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
		r.land = feet + dir * r.back_dist
		r.land.y = top_y
		r.land_on_ground = true
		mid = r.land
	else:
		var back_dist: float = (back_hit.position - feet).dot(dir)
		var after := radius + clampf(speed * 0.1, 0.4, 1.2)
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


static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, excl: Array[RID]) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = excl
	return space.intersect_ray(q)


static func _blocked(space: PhysicsDirectSpaceState3D, feet: Vector3, radius: float, height: float, excl: Array[RID]) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (height * 0.5))
	q.exclude = excl
	return not space.intersect_shape(q, 1).is_empty()
