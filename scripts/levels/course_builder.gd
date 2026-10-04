class_name CourseBuilder
extends RefCounted
## コースをレシピ（文字列の配列）から組み立てる（仕様書 7章「レベルデザイン」）。
## カーソル（足元の位置と向き）を進めながら、屋上・隙間・障害物を置いていく。屋上はビルの箱（谷底の通りから立つ）。
##
## レシピの書き方（1行1手。数字は m、向きは L / R）:
##   walk 8            屋上を8 m進む
##   vault 1.0 [種類]  ヴォルトの障害物（高さ。種類 = wall / ac / pipe / skylight）
##   gap 4 [-2.5]      4 mの隙間を跳ぶ（向こうは2.5 m低い。2 m以上落ちるならローリング）
##   drop 3            3 m下の屋上へ飛び降りる
##   up 2.2            壁を登る（2.4 mまでクライム、それより高いと縦ウォールラン）
##   ledge 3.8 2.6     3.8 mの隙間の向こうの、2.6 m高い縁を掴んで登る
##   stairs 6          6段上る（見えない坂を重ねて滑らかに）
##   slide             1.15 mの高さのバーをスライドでくぐる
##   duct 7            7 mの低いダクトをスライドで抜ける
##   slope 30 14       長さ30 m・14°の下り坂（スライドで加速）
##   wallrun 10 R [-1] 右の壁を走って10 mの隙間を越える
##   walljump 3 L      左右の壁を交互に3回蹴って隙間を越える
##   beam 12           細い梁（幅1 m）を渡る
##   turn L            左へ曲がる（広い屋上の角）
##   detour R jump     右へ回り込む主ルート。真っすぐ跳べば近道（jump / wallrun。近道は色を付けない）
##   width 6           これからの屋上の幅
##   floor gravel      これからの屋上の床（concrete / gravel / metal / glass）
##   cp                チェックポイント
## 区間（4つ）とチェックポイント（指定が無ければ3つ）はルートの長さで均等に置く。

const STREET_Y := -45.0
const LANE := 4.0
const STEP_RISE := 0.4
const STEP_RUN := 0.8
const Mat := LevelStyle.Mat
const NC := LevelGeometry.NO_COLLIDE

enum Act { NONE, JUMP, CROUCH, WALLJUMP }

var geo: LevelGeometry
var theme: Dictionary
var rng := RandomNumberGenerator.new()

## カーソル
var pos: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var width: float = 10.0
var floor_kind: StringName = &"concrete"

# 出力
## 自動走行の道しるべ。{p: Vector3, act: Act, lead_t: 秒, lead_c: m, dist: スタートからのルート距離}
var nodes: Array[Dictionary] = []
## 立てる場所（チェックポイント・区間の候補）。{xf: Transform3D, dist: float}
var safe: Array[Dictionary] = []
var route_len: float = 0.0
var min_floor_y: float = 0.0
var start_xf: Transform3D
var goal_xf: Transform3D
var checkpoints: Array[Transform3D] = []
var splits: Array[Transform3D] = []
var route_points: PackedVector3Array = []

var _floor_open: bool = false
var _floor_start: Vector3
var _floor_y: float = 0.0
var _floor_width: float = 10.0
var _floor_kind: StringName = &"concrete"
var _floor_parapet: bool = true
var _floor_tint: Color = Color.WHITE
var _cp_requests: Array[float] = []
var _decor: Array[Dictionary] = []
## 区間の印・チェックポイントを置かない範囲（技の途中）
var _busy: bool = false


func _init(p_geo: LevelGeometry, p_theme: Dictionary, seed_value: int) -> void:
	geo = p_geo
	theme = p_theme
	rng.seed = seed_value


func dir() -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3.FORWARD


func right() -> Vector3:
	return dir().cross(Vector3.UP)


func frame() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), pos)


## レシピを全部組み立てる
func build(recipe: PackedStringArray) -> void:
	start_xf = frame()
	_open_floor()
	_walk(12.0)
	for line: String in recipe:
		var t := line.strip_edges().split(" ", false)
		if t.is_empty():
			continue
		_step(t)
	# ゴール：少し走った先に門
	_walk(8.0)
	goal_xf = Transform3D(Basis(Vector3.UP, yaw), pos)
	CourseProps.goal_gate(geo, goal_xf, LANE + 1.0)
	_walk(10.0)
	_close_floor(0.0, 22.0)
	_place_markers()
	_decorate()
	_backdrop_points()


func _step(t: PackedStringArray) -> void:
	var a := func(i: int, def: float) -> float: return t[i].to_float() if t.size() > i else def
	var s := func(i: int, def: String) -> String: return t[i] if t.size() > i else def
	match t[0]:
		"walk":
			_walk(a.call(1, 8.0))
		"vault":
			_vault(a.call(1, 1.0), s.call(2, "wall"))
		"gap":
			_gap(a.call(1, 4.0), a.call(2, 0.0))
		"drop":
			_drop(a.call(1, 2.5))
		"up":
			_up(a.call(1, 2.0))
		"ledge":
			_ledge(a.call(1, 3.8), a.call(2, 2.6))
		"stairs":
			_stairs(int(a.call(1, 6.0)))
		"slide":
			_slide_bar()
		"duct":
			_duct(a.call(1, 7.0))
		"slope":
			_slope(a.call(1, 24.0), a.call(2, 12.0))
		"wallrun":
			_wallrun(a.call(1, 10.0), 1.0 if s.call(2, "R") == "R" else -1.0, a.call(3, 0.0))
		"walljump":
			_walljump(int(a.call(1, 3.0)), 1.0 if s.call(2, "L") == "R" else -1.0)
		"beam":
			_beam(a.call(1, 10.0), a.call(2, 1.0))
		"turn":
			_turn(1.0 if s.call(1, "R") == "R" else -1.0)
		"detour":
			_detour(1.0 if s.call(1, "R") == "R" else -1.0, s.call(2, "jump"))
		"width":
			width = a.call(1, 10.0)
		"floor":
			floor_kind = StringName(s.call(1, "concrete"))
		"cp":
			_cp_requests.append(route_len)
		_:
			push_error("CourseBuilder: unknown step '%s'" % " ".join(t))


# --- 自動走行の道しるべ ------------------------------------------------------

func _node(p: Vector3, act: Act = Act.NONE, lead_t: float = 0.0, lead_c: float = 0.0) -> void:
	var last := start_xf.origin if nodes.is_empty() else (nodes[-1].p as Vector3)
	route_len += last.distance_to(p)
	nodes.append({"p": p, "act": act, "lead_t": lead_t, "lead_c": lead_c, "dist": route_len})
	route_points.append(p)


func _safe_here() -> void:
	if not _busy:
		safe.append({"xf": frame(), "dist": route_len})


# --- 屋上 --------------------------------------------------------------------

func _open_floor(start: Vector3 = Vector3.INF) -> void:
	_floor_open = true
	_floor_start = pos if start == Vector3.INF else start
	_floor_y = pos.y
	_floor_width = width
	_floor_kind = floor_kind
	_floor_parapet = width > LANE + 2.0
	var tints: Array = theme.get("building_tints", [Color.WHITE])
	_floor_tint = tints[rng.randi() % tints.size()]
	min_floor_y = minf(min_floor_y, pos.y)


## 今の屋上をビルにして閉じる。extra = カーソルより先まで延ばす長さ（曲がり角を覆う）
func _close_floor(extra: float = 0.0, end_clear: float = 1.5) -> void:
	if not _floor_open:
		return
	_floor_open = false
	var d := dir()
	var end := pos + d * extra
	var length := (end - _floor_start).dot(d)
	if length < 0.05:
		return
	var center := _floor_start + d * (length * 0.5)
	var yaw_deg := rad_to_deg(yaw)
	var top := _floor_y
	var slab := _floor_kind != &"concrete"
	var b_top := top - (0.08 if slab else 0.0)
	geo.add_box(Vector3(center.x, (b_top + STREET_Y) * 0.5, center.z), Vector3(_floor_width, b_top - STREET_Y, length),
			Mat.BUILDING, Vector3(0, yaw_deg, 0), 0, _floor_tint)
	if slab:
		var m := {&"gravel": Mat.GRAVEL, &"metal": Mat.METAL, &"glass": Mat.GLASS}.get(_floor_kind, Mat.WHITE) as int
		geo.add_box(Vector3(center.x, top - 0.04, center.z), Vector3(_floor_width - 0.4, 0.08, length - 0.2), m, Vector3(0, yaw_deg, 0))
	if _floor_parapet and length > 3.0:
		for side: float in [-1.0, 1.0]:
			var c := center + right() * side * (_floor_width * 0.5 - 0.15) + Vector3.UP * 0.25
			geo.add_box(Vector3(c.x, top + 0.25, c.z), Vector3(0.3, 0.5, length), Mat.WHITE, Vector3(0, yaw_deg, 0), 0, _floor_tint)
	_decor.append({"start": _floor_start, "end": end, "yaw": yaw, "w": _floor_width, "y": top, "parapet": _floor_parapet,
			"end_clear": end_clear})


## 着地する縁をルートカラーで縁取る（使える縁：仕様書 6章）
func _lip() -> void:
	var xf := frame()
	CourseProps.box(geo, xf, Vector3(0, -0.14, 0.03), Vector3(LANE, 0.3, 0.2), Mat.ROUTE, NC)


# --- 手 -----------------------------------------------------------------------

func _walk(length: float) -> void:
	var steps := maxi(1, int(length / 6.0))
	for i: int in steps:
		pos += dir() * (length / steps)
		_node(pos)
	_safe_here()


func _vault(h: float, kind: String) -> void:
	var xf := frame()
	var depth := 0.5
	match kind:
		"ac":
			depth = 0.65
			for x: float in [-1.45, -0.48, 0.48, 1.45]:
				CourseProps.ac_unit(geo, xf * Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0, -depth * 0.5)), true)
			h = 0.75
		"pipe":
			depth = 0.6
			for x: float in [-1.6, 1.6]:
				CourseProps.box(geo, xf, Vector3(x, h * 0.4, -0.3), Vector3(0.3, h * 0.8, 0.5), Mat.DARK)
			var a := xf * Vector3(-LANE * 0.5 - 0.3, h - 0.18, -0.3)
			var b := xf * Vector3(LANE * 0.5 + 0.3, h - 0.18, -0.3)
			geo.add_beam(a, b, 0.18, Mat.ROUTE, 0, 10)
			# 当たり判定は箱（丸い管は上面の判定がずれる）
			CourseProps.box(geo, xf, Vector3(0, (h - 0.02) * 0.5, -0.3), Vector3(LANE + 0.6, h - 0.02, 0.36), Mat.METAL, LevelGeometry.NO_VISUAL)
		"skylight":
			depth = 1.0
			h = 0.8
			CourseProps.box(geo, xf, Vector3(0, h * 0.5, -0.5), Vector3(LANE, h, 1.0), Mat.GLASS)
			CourseProps.box(geo, xf, Vector3(0, h + 0.01, -0.06), Vector3(LANE, 0.03, 0.12), Mat.ROUTE, NC)
		_:
			CourseProps.box(geo, xf, Vector3(0, h * 0.5, -depth * 0.5), Vector3(LANE, h, depth), Mat.ROUTE)
	_node(pos, Act.JUMP, 0.15, 0.35)
	pos += dir() * depth
	_node(pos)


func _gap(g: float, dy: float) -> void:
	_node(pos, Act.JUMP, 0.03, 0.25)
	_close_floor()
	var from := pos
	pos += dir() * g + Vector3.UP * dy
	_open_floor()
	_lip()
	if g >= 3.0 and rng.randf() < float(theme.get("power_lines", 0.3)):
		var side := right() * (width * 0.5 - 0.6) * (1.0 if rng.randf() < 0.5 else -1.0)
		CourseProps.power_line(geo, from - dir() * 1.0 + side, pos + dir() * 1.0 + side, 7.0)
	_busy = true
	_walk(2.0)
	_busy = false


func _drop(h: float) -> void:
	_node(pos)
	_close_floor()
	pos += dir() * 0.01 + Vector3.DOWN * h
	_open_floor()
	_busy = true
	_walk(3.0)
	_busy = false


func _up(h: float) -> void:
	var climb := h <= 2.4
	_node(pos, Act.JUMP, 0.12 if climb else 0.1, 0.5)
	_close_floor()
	var base := pos.y
	pos += Vector3.UP * h
	_open_floor()
	var xf := frame()
	# 縁を縁取る。縦ウォールランの壁は面もルートカラー
	CourseProps.box(geo, xf, Vector3(0, -0.1, 0.06), Vector3(LANE, 0.2, 0.14), Mat.ROUTE, NC)
	if not climb:
		CourseProps.box(geo, xf, Vector3(0, (base - pos.y) * 0.5, 0.03), Vector3(2.6, h - 0.3, 0.06), Mat.ROUTE, NC)
	_busy = true
	_walk(2.0)
	_busy = false


func _ledge(g: float, h: float) -> void:
	_node(pos, Act.JUMP, 0.03, 0.25)
	_close_floor()
	pos += dir() * g + Vector3.UP * h
	_open_floor()
	CourseProps.box(geo, frame(), Vector3(0, -0.1, 0.06), Vector3(LANE, 0.2, 0.14), Mat.ROUTE, NC)
	_busy = true
	_walk(2.0)
	_busy = false


## 階段：段の角を結ぶ見えない坂を重ねる（段だけだと1段ごとに体が跳ねる：greybox.gd と同じ）
func _stairs(n: int) -> void:
	var xf := frame()
	for i: int in n:
		var h := STEP_RISE * (i + 1)
		CourseProps.box(geo, xf, Vector3(0, h * 0.5, -STEP_RUN * (i + 0.5)), Vector3(LANE + 1.0, h, STEP_RUN),
				Mat.ROUTE if i == n - 1 else Mat.WHITE)
	var a := Vector2(STEP_RUN, 0.0)
	var b := Vector2(-STEP_RUN * (n - 1), STEP_RISE * n)
	var length := a.distance_to(b)
	var angle := atan2(STEP_RISE, STEP_RUN)
	var thick := 0.3
	var mid := (a + b) * 0.5
	var c := Vector3(0, mid.y - cos(angle) * thick * 0.5, mid.x - sin(angle) * thick * 0.5)
	CourseProps.box(geo, xf, c, Vector3(LANE + 1.0, thick, length), Mat.WHITE, LevelGeometry.NO_VISUAL, Color.WHITE, rad_to_deg(angle))
	_busy = true
	pos += dir() * (STEP_RUN * n)
	_node(pos + Vector3.UP * STEP_RISE * n)
	_close_floor()
	pos += Vector3.UP * STEP_RISE * n
	_open_floor()
	_walk(2.0)
	_busy = false


func _slide_bar() -> void:
	var xf := frame()
	var half := LANE * 0.5 + 0.6
	CourseProps.box(geo, xf, Vector3(0, 1.15 + 0.22, -0.25), Vector3(half * 2.0, 0.45, 0.5), Mat.ROUTE)
	for sx: float in [-1.0, 1.0]:
		CourseProps.box(geo, xf, Vector3(sx * (half + 0.15), 0.8, -0.25), Vector3(0.3, 1.6, 0.3), Mat.DARK)
	_node(pos, Act.CROUCH, 0.3, 0.0)
	pos += dir() * 0.5
	_node(pos)


func _duct(length: float) -> void:
	var xf := frame()
	var half := LANE * 0.5
	CourseProps.box(geo, xf, Vector3(0, 1.15 + 0.3, -length * 0.5), Vector3(LANE + 1.0, 0.6, length), Mat.METAL)
	for sx: float in [-1.0, 1.0]:
		CourseProps.box(geo, xf, Vector3(sx * (half + 0.25), 0.6, -length * 0.5), Vector3(0.5, 1.2, length), Mat.METAL)
	CourseProps.box(geo, xf, Vector3(0, 1.17, 0.02), Vector3(LANE + 1.0, 0.08, 0.06), Mat.ROUTE, NC)
	_node(pos, Act.CROUCH, 0.25, 0.0)
	_busy = true
	pos += dir() * length
	_node(pos)
	_busy = false


## 下り坂：屋根のように斜めに架かる（駅の大屋根・エスカレーターの上）
func _slope(length: float, deg: float) -> void:
	_node(pos, Act.CROUCH, 0.06, 0.0)
	_close_floor()
	var run := length * cos(deg_to_rad(deg))
	var drop := length * sin(deg_to_rad(deg))
	var xf := frame()
	var thick := 0.5
	var mid := Vector3(0, -drop * 0.5, -run * 0.5)
	var n := Basis(Vector3.RIGHT, deg_to_rad(-deg)) * Vector3.UP
	CourseProps.box(geo, xf, mid - n * thick * 0.5, Vector3(LANE + 2.0, thick, length + 0.02), Mat.WHITE, 0, Color.WHITE, -deg)
	CourseProps.box(geo, xf, Vector3(0, 0.0, -0.1), Vector3(LANE + 2.0, 0.04, 0.2), Mat.ROUTE, NC)
	# 両側の手すり
	for sx: float in [-1.0, 1.0]:
		var a := xf * Vector3(sx * (LANE * 0.5 + 0.9), 0.0, 0.0)
		var b := xf * Vector3(sx * (LANE * 0.5 + 0.9), -drop, -run)
		CourseProps.railing(geo, a, b)
	_busy = true
	pos += dir() * run + Vector3.DOWN * drop
	_node(pos)
	_open_floor()
	_walk(3.0)
	_busy = false


## 横のウォールラン：隙間に沿った壁（体の中心から0.75 mに壁面）
func _wallrun(g: float, side: float, dy: float) -> void:
	var xf := frame()
	var top := 4.5
	var len := g + 4.0
	CourseProps.box(geo, xf, Vector3(side * 1.0, (top - 1.0) * 0.5, -(g * 0.5 - 1.0)), Vector3(0.5, top + 1.0, len), Mat.ROUTE)
	CourseProps.box(geo, xf, Vector3(side * 1.0, (STREET_Y - pos.y - 1.0) * 0.5, -(g * 0.5 - 1.0)),
			Vector3(0.5, -(STREET_Y - pos.y) - 1.0, len), Mat.BUILDING, 0, _floor_tint)
	_node(pos, Act.JUMP, 0.03, 0.25)
	_close_floor()
	_busy = true
	pos += dir() * g + Vector3.UP * dy
	_open_floor()
	_lip()
	_walk(5.0)  # 速く着地してローリングしても、次の技の前に転がり終わる
	_busy = false


## 壁ジャンプの回廊：左右の壁（面は ±1.75 m）を交互に蹴る。
## 手前の5 mで最初の壁の側へ寄ってから跳ぶ。壁 k は side×(-1)^k の側
func _walljump(n: int, side: float) -> void:
	var approach := 5.0
	var g := 6.0 * n + 1.0
	var top := 8.0
	var len := g + 4.0
	_node(pos + dir() * (approach - 2.5) + right() * side * 0.6)
	pos += dir() * approach
	var xf := frame()
	for sx: float in [-1.0, 1.0]:
		CourseProps.box(geo, xf, Vector3(sx * 2.0, top * 0.5 - 0.5, -(g * 0.5 - 1.0)), Vector3(0.5, top + 1.0, len), Mat.ROUTE)
		CourseProps.box(geo, xf, Vector3(sx * 2.0, (STREET_Y - pos.y - 1.0) * 0.5, -(g * 0.5 - 1.0)),
				Vector3(0.5, -(STREET_Y - pos.y) - 1.0, len), Mat.BUILDING, 0, _floor_tint)
	_node(pos + right() * side * 1.0, Act.JUMP, 0.03, 0.25)
	_close_floor()
	_busy = true
	# 跳んだら最初の壁へ寄る
	_node(pos + dir() * 1.5 + right() * side * 1.3)
	var s := side
	for k: int in n:
		# 壁 k で蹴る。位置は壁 k の側（蹴った後は次の道しるべ = 反対の壁へ向かう）
		_node(pos + dir() * (6.0 * k + 3.0) + right() * s * 1.0, Act.WALLJUMP)
		s = -s
	pos += dir() * g
	_open_floor()
	_lip()
	_walk(6.0)
	_busy = false


func _beam(length: float, bw: float) -> void:
	_node(pos)
	_close_floor()
	var xf := frame()
	CourseProps.box(geo, xf, Vector3(0, -0.06, -length * 0.5), Vector3(bw, 0.12, length), Mat.ROUTE)
	CourseProps.box(geo, xf, Vector3(0, -0.4, -length * 0.5), Vector3(0.14, 0.56, length), Mat.METAL)
	CourseProps.box(geo, xf, Vector3(0, -0.74, -length * 0.5), Vector3(bw, 0.12, length), Mat.METAL)
	_busy = true
	var steps := maxi(1, int(length / 3.0))
	for i: int in steps:
		pos += dir() * (length / steps)
		_node(pos)
	_open_floor()
	_walk(2.0)
	_busy = false


## 曲がり角：今の屋上を角の先まで延ばして閉じ、向きを変えて角の端から次の屋上を始める
func _turn(sign_value: float) -> void:
	_node(pos)
	var w := _floor_width
	_floor_parapet = false
	_close_floor(w * 0.5, w + 1.0)
	yaw -= sign_value * PI * 0.5
	_open_floor(pos + dir() * (w * 0.5))
	_floor_parapet = false
	_busy = true
	_walk(w * 0.5 + 1.0)
	_busy = false


## 回り込み：真ん中に穴（中庭）があり、主ルートは片側の通路を回る。真っすぐ越えれば近道（色を付けない）
## kind = jump（5 mの穴を跳ぶ）/ wallrun（10 mの穴を横切る壁を走る）
func _detour(side: float, kind: String) -> void:
	var hole := 5.0 if kind == "jump" else 10.0
	var near := 6.0   # 穴の手前の床（曲がり始める余裕）
	var far := 6.0
	var hw := 3.0     # 穴の半分の幅（主ルートの中心から反対側へ）
	var corridor := 4.5
	_node(pos)
	_close_floor()
	var xf := frame()
	var y := pos.y
	var tint := _floor_tint
	var lat_lo := -hw - 1.0
	var lat_hi := hw + corridor
	var w := lat_hi - lat_lo
	var mid_lat := (lat_lo + lat_hi) * 0.5
	# 手前・向こうの床（全幅）と片側の通路
	for f: Array in [[0.0, near], [near + hole, near + hole + far]]:
		var fc: float = (f[0] + f[1]) * 0.5
		var fl: float = f[1] - f[0]
		CourseProps.box(geo, xf, Vector3(side * mid_lat, (STREET_Y - y) * 0.5, -fc), Vector3(w, y - STREET_Y, fl), Mat.BUILDING, 0, tint)
	CourseProps.box(geo, xf, Vector3(side * (hw + corridor * 0.5), (STREET_Y - y) * 0.5, -(near + hole * 0.5)),
			Vector3(corridor, y - STREET_Y, hole), Mat.BUILDING, 0, tint)
	if kind == "wallrun":
		# 穴を横切る壁（近道。色なし）
		CourseProps.box(geo, xf, Vector3(-side * 1.0, (STREET_Y - y + 4.5) * 0.5, -(near + hole * 0.5)),
				Vector3(0.5, 4.5 - STREET_Y + y, hole + 2.0), Mat.BUILDING, 0, tint)
	_busy = true
	var c := side * (hw + corridor * 0.5)
	_node(pos + dir() * (near * 0.5) + right() * c * 0.7)
	_node(pos + dir() * near + right() * c)
	_node(pos + dir() * (near + hole) + right() * c)
	_node(pos + dir() * (near + hole + far * 0.5) + right() * c * 0.7)
	pos += dir() * (near + hole + far)
	_node(pos)
	_open_floor()
	_walk(3.0)
	_busy = false


# --- 区間・チェックポイント ---------------------------------------------------------

func _place_markers() -> void:
	var total := route_len
	for i: int in 4:
		var at := total * (i + 1) / 5.0
		splits.append(_safe_after(at))
	var cps := _cp_requests.duplicate()
	if cps.is_empty():
		cps = [total * 0.25, total * 0.5, total * 0.75]
	for d: float in cps:
		checkpoints.append(_safe_after(d))


func _safe_after(d: float) -> Transform3D:
	for s: Dictionary in safe:
		if (s.dist as float) >= d:
			return s.xf
	return safe[-1].xf


# --- 飾り --------------------------------------------------------------------

## 屋上の両脇（走る道の外）に小物を置く
func _decorate() -> void:
	var kinds: Array = theme.get("deco", ["ac"])
	for z: Dictionary in _decor:
		var y_rot: float = z.yaw
		var b := Basis(Vector3.UP, y_rot)
		var d := b * Vector3.FORWARD
		var r := d.cross(Vector3.UP)
		var start: Vector3 = z.start
		var length := ((z.end as Vector3) - start).dot(d)
		var w: float = z.w
		var room := w * 0.5 - LANE * 0.5 - 0.8 - (0.3 if z.parapet else 0.0)
		var usable := length - float(z.end_clear)
		if room < 1.0 or usable < 3.0:
			continue
		for side: float in [-1.0, 1.0]:
			var f := rng.randf_range(1.5, 4.0)
			while f < usable:
				var lat := side * (LANE * 0.5 + 0.8 + room * 0.5)
				var p := start + d * f + r * lat
				p.y = z.y
				# facing = 前（-Z）が道のほうを向く。along = 前がルートの進む向き
				var facing := Transform3D(Basis(Vector3.UP, y_rot + (PI * 0.5 if side > 0.0 else -PI * 0.5)), p)
				var along := Transform3D(b, p)
				var kind: String = kinds[rng.randi() % kinds.size()]
				f += _prop(kind, facing, along, room, usable - f) + rng.randf_range(2.0, 5.0)


## 小物を1つ置く。戻り値 = 使った奥行き（ルート方向）
func _prop(kind: String, xf: Transform3D, along: Transform3D, room: float, left: float) -> float:
	match kind:
		"ac":
			var n := rng.randi_range(1, 3)
			for i: int in n:
				CourseProps.ac_unit(geo, xf * Transform3D(Basis.IDENTITY, Vector3(-0.95 * i + 0.95, 0, 0)))
			return 1.0
		"tank":
			if room >= 2.2 and left > 3.0:
				CourseProps.water_tank(geo, xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO), rng)
				return 2.6
		"tower":
			if room >= 3.0 and left > 4.0:
				CourseProps.water_tower(geo, xf)
				return 3.2
		"antenna":
			CourseProps.antenna(geo, xf, rng.randf_range(3.0, 6.0))
			return 1.0
		"house":
			if room >= 3.2 and left > 4.0:
				CourseProps.stair_house(geo, xf * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.2)), 3.0, minf(room, 3.4), 2.6)
				return 3.4
		"pipes":
			var l := minf(left - 1.0, rng.randf_range(4.0, 9.0))
			if l > 2.0:
				CourseProps.pipes(geo, along, l)
				return l
		"skylight":
			if room >= 1.8:
				CourseProps.skylight(geo, xf, minf(room, 2.4), 1.6)
				return 2.4
		"billboard":
			var colors: Array = theme.get("sign_colors", [Color(0.3, 0.6, 0.9)])
			CourseProps.billboard(geo, xf * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, room * 0.3)),
					rng.randf_range(3.0, 5.0), rng.randf_range(1.6, 2.6), colors[rng.randi() % colors.size()], bool(theme.get("lit", false)))
			return 4.0
		"neon":
			var colors2: Array = theme.get("sign_colors", [Color(1.0, 0.3, 0.6)])
			CourseProps.neon(geo, xf, rng.randf_range(3.0, 6.0), colors2[rng.randi() % colors2.size()])
			return 1.5
		"lamp":
			CourseProps.lamp(geo, xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 0, -room * 0.4 + 0.3)))
			return 4.0
		"scaffold":
			if room >= 2.0:
				CourseProps.scaffold(geo, along * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 0, -minf(left - 1.0, 7.0) * 0.5)), minf(left - 1.0, 7.0), 5.6, 1.4)
				return minf(left - 1.0, 7.0)
		"steel":
			for i: int in rng.randi_range(2, 4):
				CourseProps.box(geo, along, Vector3(0, 0.15 + i * 0.3, -2.0), Vector3(0.6, 0.28, 4.0), Mat.METAL, 0, Color(0.7, 0.5, 0.4))
			return 4.2
		"barrier":
			CourseProps.box(geo, along, Vector3(0, 0.45, -0.9), Vector3(0.4, 0.9, 1.8), Mat.HAZARD)
			return 2.0
	return 1.0


## 遠景のビルを置く範囲（ルートの点）
func _backdrop_points() -> void:
	route_points.append(goal_xf.origin)


## フリーラン：時間制限なしの大きい区画（仕様書 7章）。手触りを味わう場所で、テスト場も兼ねる。
## n×n のビルを路地（3〜5 m）で区切って並べる。高さはなめらかな乱れで決め、隣との段差に応じて
## 足場（木箱）・ウォールランの壁・梁・下り坂を置いて、どこからでもどこかへ行けるようにする。
func build_district(n: int = 7) -> void:
	var pitch := 21.0
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.18
	var heights: Array[PackedFloat32Array] = []
	var sizes: Array[PackedFloat32Array] = []
	var half := (n - 1) * 0.5
	for i: int in n:
		var row := PackedFloat32Array()
		var srow := PackedFloat32Array()
		for j: int in n:
			var h := snappedf(noise.get_noise_2d(i, j) * 9.0, 0.5)
			if i == int(half) and j == int(half):
				h = 0.0
			row.append(h)
			srow.append(rng.randf_range(15.5, 18.0))
		heights.append(row)
		sizes.append(srow)
	var center := func(i: int, j: int) -> Vector3:
		return Vector3((i - half) * pitch, heights[i][j], (j - half) * pitch)
	for i: int in n:
		for j: int in n:
			var c: Vector3 = center.call(i, j)
			var sz := sizes[i][j]
			width = sz
			yaw = 0.0
			pos = c + Vector3(0, 0, sz * 0.5)
			floor_kind = [&"concrete", &"concrete", &"gravel", &"metal"][rng.randi() % 4]
			_open_floor()
			pos = c - Vector3(0, 0, sz * 0.5)
			_close_floor(0.0, 1.5)
			route_points.append(c)
			min_floor_y = minf(min_floor_y, c.y)
			# 隣（+x と +z）へのつなぎ
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var ni := i + d.x
				var nj := j + d.y
				if ni >= n or nj >= n:
					continue
				_connect(c, sz, center.call(ni, nj), sizes[ni][nj], Vector3(d.x, 0, d.y))
	# 真ん中のビルから始める
	var mid: Vector3 = center.call(int(half), int(half))
	yaw = 0.0
	pos = mid + Vector3(0, 0, 4.0)
	start_xf = frame()
	goal_xf = start_xf
	safe.append({"xf": start_xf, "dist": 0.0})
	_place_markers()
	checkpoints.clear()
	_decorate()


## 隣どうしのビルをつなぐ：段差が小さければ跳び移れる。段差に応じて足場・壁・坂を足す
func _connect(a: Vector3, sa: float, b: Vector3, sb: float, axis: Vector3) -> void:
	var lo := a if a.y <= b.y else b
	var hi := b if a.y <= b.y else a
	var s_lo := sa if a.y <= b.y else sb
	var s_hi := sb if a.y <= b.y else sa
	var toward := (hi - lo) * Vector3(1, 0, 1)
	toward = toward.normalized()
	var dh := hi.y - lo.y
	var gap_mid := (a + b) * 0.5
	var y_deg := rad_to_deg(atan2(-toward.x, -toward.z))
	var lateral := toward.cross(Vector3.UP)
	var offset := lateral * rng.randf_range(-4.0, 4.0)
	var r := rng.randf()
	if dh > 2.4 and dh <= 4.0:
		# 低い側の屋上、高い壁の手前に木箱（ヴォルトで乗ってからクライム）
		var foot := hi - toward * (s_hi * 0.5 + (pitch_gap(a, b, sa, sb)) + 1.2) + offset
		foot.y = lo.y
		geo.add_box(foot + Vector3.UP * 0.6, Vector3(2.4, 1.2, 1.6), Mat.ROUTE, Vector3(0, y_deg, 0))
	elif dh > 4.0 and dh < 9.0 and r < 0.6:
		# 下り坂（高い側から低い側へ。スライドで下る）
		var start := hi - toward * (s_hi * 0.5) + offset
		var end := lo + toward * (s_lo * 0.5) + offset
		end.y = lo.y
		var length := start.distance_to(end)
		var pitch_deg := rad_to_deg(asin((start.y - end.y) / length))
		var mid := (start + end) * 0.5
		var nrm := Basis.from_euler(Vector3(deg_to_rad(-pitch_deg), deg_to_rad(y_deg + 180.0), 0)) * Vector3.UP
		geo.add_box(mid - nrm * 0.25, Vector3(4.0, 0.5, length + 0.4), Mat.ROUTE, Vector3(-pitch_deg, y_deg + 180.0, 0))
	if dh < 1.0 and r < 0.35:
		# 路地をまたぐ看板の壁（ウォールラン）
		var wall_c := gap_mid + lateral * rng.randf_range(-5.0, 5.0)
		var top := maxf(a.y, b.y) + 4.5
		var bottom := STREET_Y
		geo.add_box(Vector3(wall_c.x, (top + bottom) * 0.5, wall_c.z), Vector3(0.5, top - bottom, pitch_gap(a, b, sa, sb) + 10.0),
				Mat.ROUTE, Vector3(0, y_deg, 0))
	elif dh < 1.5 and r < 0.6:
		# 梁
		var p0 := a + offset
		var p1 := b + offset
		var y := minf(a.y, b.y)
		var mid2 := (p0 + p1) * 0.5
		geo.add_box(Vector3(mid2.x, y - 0.06, mid2.z), Vector3(1.0, 0.12, p0.distance_to(p1)), Mat.ROUTE, Vector3(0, y_deg, 0))


func pitch_gap(a: Vector3, b: Vector3, sa: float, sb: float) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length() - (sa + sb) * 0.5
