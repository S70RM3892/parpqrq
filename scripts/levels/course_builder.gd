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
##   detour R jump     右へ回り込む主ルート。真っすぐ越えれば近道（jump / wallrun / vault / swing。近道は色を付けない）。
##                     `detour R jump 4 3 4.5` のように 穴の長さ・穴の半幅・手前の床 を上書きできる（既定は DETOUR）
##   mark swing        次の手が教える技（MOVES）の床の印（ボタンの印と矢印）。技が主ルートに初めて出る所の手前に置く（wallrun は L / R で矢印を壁へ）
##   vjump 4.8         ヴォルトジャンプの導入：ルートカラーの室外機の列と、それを越えて跳ばないと届かない隙間
##   swingbar 11       スイングバーの導入：隙間の上にルートカラーの横棒
##   zipline 18 3      ジップラインの導入：高い屋上の縁から、18 m先の3 m低い屋上へルートカラーの線
##   up 4.6            4.1 mを超える壁は、縦ウォールランの頂点の蹴り上がりで登る導入になる
## 隠れた近道のある区間（主ルートは色付きで迷わず走れる。近道は色を付けず、屋上の物の中に隠す：仕様書 7章）:
##   swinggap 11       主ルートは斜めに横へずれて、一段低い屋上へ飛び降り、向こうの壁を登る。足場の横棒でスイングすれば上のまま越える
##   zipjog R          主ルートは角を曲がって横へずれ、谷に架かる橋を渡って一段下り、斜めに戻る（角2つ）。塔屋に登って電線（ジップライン）で谷を真っすぐ渡れば近道
##   kickwall 4.6      高い壁。主ルートは遠い横の木箱を段にして3回で登る（角2つ）。縦ウォールランの頂点で壁を蹴り上がれば正面から登れる
##   width 6           これからの屋上の幅
##   floor gravel      これからの屋上の床（concrete / gravel / metal / glass）
##   cp                チェックポイント
## 区間（4つ）はルートの長さで均等に置く。チェックポイントは cp の指定を守り、間隔が CP_MAX_GAP を超える所に足して
## 均等に置く（3つ以上。シルバーのペースで走って20秒以下になる長さ）。

const STREET_Y := -45.0
## チェックポイントの間隔の上限（m）と最低の数（スタート→cp→…→ゴールのルート距離で測る）
const CP_MAX_GAP := 150.0
const CP_MIN := 3
## 隠れた近道を1本作るレシピの手（CourseCatalog.shortcut_count もこれで数える）
const SHORTCUT_STEPS: PackedStringArray = ["detour", "swinggap", "zipjog", "kickwall"]
## 技の名前（教える技・近道が要る技。表は docs/BALANCE.md）。jump = ジャンプ / vault = ヴォルト / roll = 2 m以上の着地のローリング /
## climb = よじ登り / ledge = 縁を掴んで登る / wallclimb = 縦ウォールラン / wallrun = 横ウォールラン / walljump = 壁ジャンプ / slide = スライド /
## vaultjump = ヴォルトジャンプ / swing = スイングバー / zipline = ジップライン / wallkick = 縦ウォールランの頂点の蹴り上がり
const MOVES: PackedStringArray = ["jump", "vault", "roll", "climb", "ledge", "wallclimb", "wallrun", "walljump", "slide", "vaultjump",
		"swing", "zipline", "wallkick"]
## 近道の型（shortcuts の type）ごとに、通るのに要る技。主ルートで先に教えていないと course_test が落とす
const SHORTCUT_NEEDS: Dictionary[String, PackedStringArray] = {
	"detour_jump": ["jump"], "detour_wallrun": ["wallrun"], "detour_vault": ["vaultjump"], "detour_swing": ["swing"],
	"swing": ["swing"], "zipline": ["climb", "zipline"], "wall_kick": ["wallclimb", "wallkick"],
}
## 近道の型ごとの段（人の模型の短縮：段1 0.4〜0.8 / 段2 0.8〜1.6 / 段3 1.6〜3.0 s。course_test が調べる）
const SHORTCUT_TIER: Dictionary[String, int] = {
	"detour_jump": 1,
	"detour_vault": 2, "detour_wallrun": 2, "detour_swing": 2, "swing": 2,
	"wall_kick": 3, "zipline": 3,
}
## 2 m以上の落下・着地でローリング（MovementParams.roll_min_drop と同じ）。縦ウォールランで届く高さを超える壁は蹴り上がりが要る
const ROLL_MIN_DROP := 2.0
const KICK_FROM := 4.1
## 床の印の中心から障害物までの距離（m）。ボタンの印は 3〜6 m 手前
const MARK_AT := 5.0
## 印の置き場所：カーソルから障害物の始まりまでの距離（壁ジャンプの回廊は5 m先から始まる）
const MARK_AHEAD: Dictionary[String, float] = {"walljump": 5.0}
## 印のボタン：jump = ジャンプ（白い円）、crouch = しゃがみ（白い角丸の四角）、double = 2回押す（円2つ：ヴォルトジャンプ・スイング・ジップライン・蹴り上がり）
const MARK_BUTTON: Dictionary[String, String] = {
	"jump": "jump", "vault": "jump", "roll": "crouch", "climb": "jump", "ledge": "jump", "wallclimb": "jump", "wallrun": "jump",
	"walljump": "jump", "slide": "crouch", "vaultjump": "double", "swing": "double", "zipline": "double", "wallkick": "double",
}
const LANE := 4.0
const STEP_RISE := 0.4
const STEP_RUN := 0.8
const Mat := LevelStyle.Mat
const NC := LevelGeometry.NO_COLLIDE

## 道しるべで自動走行がする操作。
## VAULT_JUMP = ヴォルトに入り、障害物の上でもう一度押す / SWING = スイング中、理想の角度で離す /
## ZIP = ジップラインの終点の少し手前で離す / CLIMB_KICK = 縦ウォールランの頂点で壁を蹴り上がる /
## WALLRUN_JUMP = 横ウォールラン中、道しるべに着いたら壁を蹴る
enum Act { NONE, JUMP, CROUCH, WALLJUMP, VAULT_JUMP, SWING, ZIP, CLIMB_KICK, WALLRUN_JUMP }

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
## チェックポイントごとのルート距離（checkpoints と同じ並び）と、ゴールのルート距離
var checkpoint_dists: Array[float] = []
var goal_dist: float = 0.0
var splits: Array[Transform3D] = []
var route_points: PackedVector3Array = []
## 隠れた近道（色を付けない）。{name, type: 型（SHORTCUT_NEEDS のキー）, needs: 通るのに要る技, from: 主ルートの道しるべの番号（ここから分かれる）,
##  to: 戻る主ルートの道しるべの番号, nodes: 近道の道しるべ, found_xf / found_size: ここを通ったら発見（向きつきの箱）,
##  found_states: 発見に数える状態の名前（Player.State のキー。空 = どれでも）,
##  then_xf / then_size: あれば、その後にここも通ったら発見（穴に落ちただけでは数えない）, hint: 金メダルの後に目印を出す所}
## name は区間の種類と通し番号（"swing_2"）。同じ種類が2つあっても別に数える
var shortcuts: Array[Dictionary] = []
## 掴める棒と線（スイングバー・ジップライン）。Course が GrabLines に渡す（GrabLines.bar / zip の形）
var grab_lines: Array[Dictionary] = []

## 主ルートの手が教える技。{move: 技の名前（MOVES）, dist: その手のルート距離, marked: 手前に床の印がある}。
## course_test が「近道が要る技は先に教えてある」「技が初めて出る所には床の印がある」を調べる
var taught: Array[Dictionary] = []
## 床の印（技が初めて主ルートに出る所の手前）。{move, dist: 印を描いた時のルート距離, glyph: 印の中心から障害物までの距離, floor_back: 印の後ろの床の長さ}
var marks: Array[Dictionary] = []

var _pending_mark: String = ""
var _mark_used: bool = false
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
## 飾りを置かない所（近道の通り道）。{a: Vector2, b: Vector2, r: float}（水平面の線分と半径）
var _clear: Array[Dictionary] = []
## 近道のある区間の途中（主ルートだけが通る所に区間の印・チェックポイントを置かない）
var _in_section: bool = false


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
	goal_dist = route_len
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
			_detour(1.0 if s.call(1, "R") == "R" else -1.0, s.call(2, "jump"), a.call(3, 0.0), a.call(4, 0.0), a.call(5, 0.0))
		"swinggap":
			_swing_gap(a.call(1, 11.0), a.call(2, 0.0), a.call(3, 0.0))
		"zipjog":
			_zip_jog(1.0 if s.call(1, "R") == "R" else -1.0, a.call(2, 0.0), a.call(3, 0.0))
		"kickwall":
			_kick_wall(a.call(1, 4.6), int(a.call(2, 0.0)), a.call(3, 0.0))
		"width":
			width = a.call(1, 10.0)
		"floor":
			floor_kind = StringName(s.call(1, "concrete"))
		"cp":
			_cp_requests.append(route_len)
		"mark":
			_mark(s.call(1, "jump"), s.call(2, "-"))
		"vjump":
			_vault_jump_gap(a.call(1, 4.8))
		"swingbar":
			_swing_bar(a.call(1, 11.0))
		"zipline":
			_zip_line(a.call(1, 18.0), a.call(2, 3.0))
		_:
			push_error("CourseBuilder: unknown step '%s'" % " ".join(t))
	if not t[0] in ["mark", "floor", "width", "cp"] and _pending_mark != "":
		if not _mark_used:
			push_error("CourseBuilder: mark %s is not followed by a step that teaches it ('%s')" % [_pending_mark, " ".join(t)])
		_pending_mark = ""
		_mark_used = false


# --- 自動走行の道しるべ ------------------------------------------------------

func _node(p: Vector3, act: Act = Act.NONE, lead_t: float = 0.0, lead_c: float = 0.0) -> void:
	var last := start_xf.origin if nodes.is_empty() else (nodes[-1].p as Vector3)
	route_len += last.distance_to(p)
	nodes.append({"p": p, "act": act, "lead_t": lead_t, "lead_c": lead_c, "dist": route_len})
	route_points.append(p)


## 主ルートの手が技を教える（course_test が表にする）。直前の mark がその技なら印あり
func _teach(move: String) -> void:
	var marked := _pending_mark == move
	if marked:
		_mark_used = true
	taught.append({"move": move, "dist": route_len, "marked": marked})


## 床の印：次の手が教える技のボタンの印と、障害物の方を指す矢印を、障害物の MARK_AT 手前に描く（docs/BALANCE.md）。
## side = L / R なら矢印をその側へ傾ける（横ウォールランの壁の方）
func _mark(move: String, side_name: String) -> void:
	if not move in MOVES:
		push_error("CourseBuilder: mark of unknown move '%s'" % move)
		return
	var ahead: float = MARK_AHEAD.get(move, 0.0)
	var behind := (pos - _floor_start).dot(dir())
	if not _floor_open or behind < MARK_AT + 1.2 - ahead:
		push_error("CourseBuilder: no floor for the mark of %s (%.1f m behind)" % [move, behind])
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos + dir() * (ahead - MARK_AT))
	var arrow := 0.0
	if side_name == "R":
		arrow = -32.0
	elif side_name == "L":
		arrow = 32.0
	CourseProps.floor_mark(geo, xf, MARK_BUTTON[move], arrow)
	marks.append({"move": move, "dist": route_len, "glyph": MARK_AT, "floor_back": behind + ahead})
	_pending_mark = move
	_mark_used = false


func _safe_here() -> void:
	if not _busy and not _in_section:
		safe.append({"xf": frame(), "dist": route_len})


## 近道の道しるべ（主ルートの距離には数えない）
func _bn(p: Vector3, act: Act = Act.NONE, lead_t: float = 0.0, lead_c: float = 0.0) -> Dictionary:
	return {"p": p, "act": act, "lead_t": lead_t, "lead_c": lead_c, "dist": -1.0}


## 近道を登録する。from / to = 主ルートの道しるべの番号。found = 発見の判定の箱（向きつき）。
## then = その後に通る2つ目の箱（無ければ大きさ 0）
func _shortcut(sc_name: String, from: int, to: int, sc_nodes: Array[Dictionary], found_xf: Transform3D,
		found_size: Vector3, found_states: Array[String], hint: Vector3,
		then_xf: Transform3D = Transform3D.IDENTITY, then_size: Vector3 = Vector3.ZERO) -> void:
	shortcuts.append({"name": "%s_%d" % [sc_name, shortcuts.size() + 1], "type": sc_name, "needs": SHORTCUT_NEEDS[sc_name], "from": from, "to": to, "nodes": sc_nodes,
			"found_xf": found_xf, "found_size": found_size, "found_states": found_states, "hint": hint,
			"then_xf": then_xf, "then_size": then_size})


## 自動走行の道：主ルートだけ、または全部の近道を通る道
func route(take_shortcuts: bool) -> Array[Dictionary]:
	if not take_shortcuts:
		return nodes
	var out: Array[Dictionary] = []
	var i := 0
	while i < nodes.size():
		out.append(nodes[i])
		var next := i + 1
		for sc: Dictionary in shortcuts:
			if int(sc.from) == i:
				out.append_array(sc.nodes)
				next = int(sc.to)
				break
		i = next
	return out


## 飾りを置かない通り道（a→b、半径 r）
func _keep_clear(a: Vector3, b: Vector3, r: float) -> void:
	_clear.append({"a": Vector2(a.x, a.z), "b": Vector2(b.x, b.z), "r": r})


func _is_clear(p: Vector3, margin: float) -> bool:
	var q := Vector2(p.x, p.z)
	for c: Dictionary in _clear:
		var a: Vector2 = c.a
		var b: Vector2 = c.b
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		if q.distance_to(a + ab * t) < float(c.r) + margin:
			return false
	return true


## 擦り跡（近道の踏み切り・手を着く所に、先に通った人の靴跡が残っている。色は付けない：気づいた人へのご褒美）。
## xf の足元の面に n 個、横 spread × 奥 depth に散らす。wall = true なら xf の -Z 向きの壁面に縦に付ける
func _scuffs(xf: Transform3D, n: int, spread: float, depth: float, wall: bool = false) -> void:
	for i: int in n:
		var x := rng.randf_range(-spread, spread) * 0.5
		var z := rng.randf_range(-depth, depth) * 0.5
		var len := rng.randf_range(0.18, 0.32)
		var tint := Color(0.55, 0.55, 0.55)
		if wall:
			var c := xf * Vector3(x, 0.4 + z + depth * 0.5, 0.012)
			geo.add_box(c, Vector3(0.09, len, 0.01), Mat.DARK, Vector3(0, rad_to_deg(xf.basis.get_euler().y), rng.randf_range(-25, 25)),
					NC | LevelGeometry.NO_SHADOW, tint)
		else:
			var c2 := xf * Vector3(x, 0.006, z)
			geo.add_box(c2, Vector3(0.1, 0.01, len), Mat.DARK, Vector3(0, rad_to_deg(xf.basis.get_euler().y) + rng.randf_range(-20, 20), 0),
					NC | LevelGeometry.NO_SHADOW, tint)


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
	_teach("vault")
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
	_teach("jump")
	if dy <= -ROLL_MIN_DROP:
		_teach("roll")
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
	if h >= ROLL_MIN_DROP:
		_teach("roll")
	_node(pos)
	_close_floor()
	pos += dir() * 0.01 + Vector3.DOWN * h
	_open_floor()
	_busy = true
	_walk(3.0)
	_busy = false


func _up(h: float) -> void:
	var climb := h <= 2.4
	var kick := h > KICK_FROM   # 縦ウォールランだけでは縁に届かない壁は、頂点で蹴り上がる
	if climb:
		_teach("climb")
	else:
		_teach("wallclimb")
		if kick:
			_teach("wallkick")
	_node(pos, Act.JUMP, 0.12 if climb else 0.1, 0.5)
	if kick:
		_node(pos, Act.CLIMB_KICK)
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
	_teach("ledge")
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
	_teach("slide")
	var xf := frame()
	var half := LANE * 0.5 + 0.6
	CourseProps.box(geo, xf, Vector3(0, 1.15 + 0.22, -0.25), Vector3(half * 2.0, 0.45, 0.5), Mat.ROUTE)
	for sx: float in [-1.0, 1.0]:
		CourseProps.box(geo, xf, Vector3(sx * (half + 0.15), 0.8, -0.25), Vector3(0.3, 1.6, 0.3), Mat.DARK)
	_node(pos, Act.CROUCH, 0.3, 0.0)
	pos += dir() * 0.5
	_node(pos)


func _duct(length: float) -> void:
	_teach("slide")
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
	_teach("slide")
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
	_teach("wallrun")
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
	_teach("walljump")
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


## 曲がり角：今の屋上を角の先まで延ばして閉じ、向きを変えて角の端から次の屋上を始める。
## extra = 角の先へ延ばす長さ（既定は幅の半分 = 角の正方形）
func _turn(sign_value: float, extra: float = -1.0) -> void:
	_node(pos)
	var w := _floor_width
	var ext := w * 0.5 if extra < 0.0 else extra
	_floor_parapet = false
	_close_floor(ext, ext + w * 0.5 + 1.0)
	yaw -= sign_value * PI * 0.5
	_open_floor(pos + dir() * (w * 0.5))
	_floor_parapet = false
	_busy = true
	_walk(w * 0.5 + 1.0)
	_busy = false


## 回り込みの寸法（kind ごと）。hole = 穴の長さ、hw = 穴の半幅（広いほど主ルートの回り込みが長く、近道が得になる）、near = 穴の手前・向こうの床の長さ。
## 人の模型で短縮が段に収まるように決めた（docs/BALANCE.md）。レシピの `detour R jump 4.6 4.2 6` で上書きできる（hole hw near）
const DETOUR: Dictionary[String, Dictionary] = {
	"jump": {"hole": 4.0, "hw": 3.0, "near": 4.5},
	"wallrun": {"hole": 10.0, "hw": 5.0, "near": 3.0},
	"vault": {"hole": 4.8, "hw": 4.8, "near": 3.0},
	"swing": {"hole": 11.0, "hw": 5.0, "near": 3.0},
}


## 回り込み：真ん中に穴（中庭）があり、主ルートは片側の通路を回る。真っすぐ越えれば近道（色を付けない）。
## kind = jump（5 mの穴を跳ぶ）/ wallrun（10 mの穴を横切る壁を走る）/
## vault（7.2 mの穴の縁に室外機。ヴォルトジャンプで越える）/ swing（11 mの穴の上に足場の横棒。スイングで越える）
func _detour(side: float, kind: String, hole_arg: float = 0.0, hw_arg: float = 0.0, near_arg: float = 0.0) -> void:
	var dim: Dictionary = DETOUR.get(kind, DETOUR.jump)
	var hole: float = hole_arg if hole_arg > 0.0 else dim.hole
	var hw: float = hw_arg if hw_arg > 0.0 else dim.hw   # 穴の半分の幅（主ルートの中心から反対側へ）
	var near: float = near_arg if near_arg > 0.0 else dim.near   # 穴の手前の床（曲がり始める余裕）
	var far := near
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
	var act := Act.JUMP
	var lead := Vector2(0.03, 0.25)
	var takeoff := -near
	match kind:
		"wallrun":
			# 穴を横切る壁（色なし）
			CourseProps.box(geo, xf, Vector3(-side * 1.0, (STREET_Y - y + 4.5) * 0.5, -(near + hole * 0.5)),
					Vector3(0.5, 4.5 - STREET_Y + y, hole + 2.0), Mat.BUILDING, 0, tint)
		"vault":
			# 穴の縁に並んだ室外機（色なし）。普通に跳ぶには遠い。上でもう一度跳べば届く
			for x: float in [-1.45, -0.48, 0.48, 1.45]:
				CourseProps.ac_unit(geo, xf * Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0, -(near - 0.33))))
			# 当たり判定は列ごと1つ（室外機の隙間をすり抜けてヴォルトが出ないことがないように）
			CourseProps.box(geo, xf, Vector3(0, 0.375, -(near - 0.33)), Vector3(3.8, 0.75, 0.62), Mat.METAL, LevelGeometry.NO_VISUAL)
			_scuffs(Transform3D(xf.basis, xf * Vector3(0, 0.75, -(near - 0.33))), 4, 1.6, 0.4)
			act = Act.VAULT_JUMP
			lead = Vector2(0.15, 0.35)
			takeoff = -(near - 0.64)
		"swing":
			# 穴の上の足場：横棒（色なし）と支柱。支柱は通りから立つ
			var bz := near + 4.5
			var bh := 2.45
			var bar_a := xf * Vector3(-2.8, bh, -bz)
			var bar_b := xf * Vector3(2.8, bh, -bz)
			geo.add_beam(bar_a, bar_b, 0.05, Mat.METAL, NC, 10)
			grab_lines.append(GrabLines.bar(bar_a, bar_b))
			for sx: float in [-1.0, 1.0]:
				var post := Vector3(sx * 3.05, 0, -bz)
				geo.add_beam(xf * Vector3(post.x, STREET_Y - y, post.z), xf * Vector3(post.x, bh + 0.5, post.z), 0.06, Mat.METAL, 0, 8)
				geo.add_beam(xf * Vector3(post.x, bh, post.z), xf * Vector3(post.x, bh, post.z - 1.8), 0.04, Mat.METAL, NC, 6)
				geo.add_beam(xf * Vector3(post.x, STREET_Y - y, post.z - 1.8), xf * Vector3(post.x, bh + 0.5, post.z - 1.8), 0.045, Mat.METAL, NC, 8)
			geo.add_beam(xf * Vector3(-3.05, bh + 0.5, -bz - 1.8), xf * Vector3(3.05, bh + 0.5, -bz - 1.8), 0.04, Mat.METAL, NC, 6)
	_busy = true
	var from := nodes.size() - 1
	var c := side * (hw + corridor * 0.5)
	_node(pos + dir() * (near * 0.5) + right() * c * 0.5)
	_node(pos + dir() * near + right() * c)
	_node(pos + dir() * (near + hole) + right() * c)
	_node(pos + dir() * (near + hole + far * 0.5) + right() * c * 0.5)
	pos += dir() * (near + hole + far)
	_node(pos)
	var to := nodes.size() - 1
	_open_floor()
	_walk(3.0)
	_busy = false
	# 近道：穴を真っすぐ越える
	# 壁を走る近道は壁の方へ少し寄って走る（壁を感じる距離は壁面から0.05 mしかなく、横にずれると壁を走れない）
	var bias := -side * 0.3 if kind == "wallrun" else 0.0
	var sc: Array[Dictionary] = [_bn(xf * Vector3(bias, 0, takeoff), act, lead.x, lead.y)]
	if kind == "swing":
		sc.append(_bn(xf * Vector3(0, 0, -(near + 4.5)), Act.SWING))
	sc.append(_bn(xf * Vector3(bias, 0, -(near + hole + 2.0))))
	# 穴の上を通り、向こうの縁（主ルートの通路からは離れた真ん中）に着いたら発見。落ちただけでは数えない
	_shortcut("detour_" + kind, from, to, sc, Transform3D(xf.basis, xf * Vector3(0, 2.0, -(near + hole * 0.5))),
			Vector3(hw * 2.0 - 1.0, 3.0, hole - 1.0), [], xf * Vector3(0, 1.0, -near),
			Transform3D(xf.basis, xf * Vector3(0, 1.6, -(near + hole + 1.6))), Vector3(4.0, 3.6, 3.2))
	if kind != "vault":
		_scuffs(Transform3D(xf.basis, xf * Vector3(0, 0, -(near - 0.6))), 5, 1.4, 1.0)
	_keep_clear(xf * Vector3(0, 0, -near), xf * Vector3(0, 0, -(near + hole)), 1.0)


# --- 1.1 の技の導入（主ルート。色付きで、その技を単独で安全に出す：docs/BALANCE.md）-----------------------
# 失敗しても谷底へ落ちるだけ（チェックポイントへすぐ戻る）。導入の手の前に cp を置く。

## ヴォルトジャンプの導入：ルートカラーの室外機の列を越えて、そのまま奥の縁でもう一度跳ばないと届かない隙間（g m）
func _vault_jump_gap(g: float) -> void:
	_teach("vaultjump")
	var xf := frame()
	for x: float in [-1.45, -0.48, 0.48, 1.45]:
		CourseProps.ac_unit(geo, xf * Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0, -0.31)), true)
	# 当たり判定は列ごと1つ（室外機の隙間をすり抜けてヴォルトが出ないことがないように）
	CourseProps.box(geo, xf, Vector3(0, 0.375, -0.31), Vector3(3.8, 0.75, 0.62), Mat.METAL, LevelGeometry.NO_VISUAL)
	_node(pos, Act.VAULT_JUMP, 0.15, 0.35)
	pos += dir() * 0.64
	_close_floor()
	pos += dir() * g
	_open_floor()
	_lip()
	_busy = true
	_walk(3.0)
	_busy = false


## スイングバーの導入：g m の隙間の上にルートカラーの横棒（縁から4.5 m・高さ2.45 m）。跳んで掴み、振って離せば向こうへ着く
func _swing_bar(g: float) -> void:
	const BAR_Z := 4.5
	const BAR_H := 2.45
	const POST_X := 3.05
	_teach("swing")
	var xf := frame()
	var y := pos.y
	_node(pos, Act.JUMP, 0.03, 0.25)
	var bar_a := xf * Vector3(-POST_X + 0.15, BAR_H, -BAR_Z)
	var bar_b := xf * Vector3(POST_X - 0.15, BAR_H, -BAR_Z)
	geo.add_beam(bar_a, bar_b, 0.07, Mat.ROUTE, NC, 10)
	grab_lines.append(GrabLines.bar(bar_a, bar_b))
	for sx: float in [-1.0, 1.0]:
		geo.add_beam(xf * Vector3(sx * POST_X, STREET_Y - y, -BAR_Z), xf * Vector3(sx * POST_X, BAR_H + 0.5, -BAR_Z), 0.06, Mat.METAL, 0, 8)
		geo.add_beam(xf * Vector3(sx * POST_X, BAR_H, -BAR_Z), xf * Vector3(sx * (POST_X - 0.2), BAR_H, -BAR_Z), 0.04, Mat.METAL, NC, 6)
	_close_floor()
	_node(xf * Vector3(0, 0, -BAR_Z), Act.SWING)
	pos += dir() * g
	_open_floor()
	_lip()
	_busy = true
	_walk(4.0)
	_busy = false


## ジップラインの導入：高い屋上の縁から、谷の向こうの低い屋上（drop m下）へ張ったルートカラーの線。跳んで掴み、滑って終点で離す
func _zip_line(length: float, drop: float) -> void:
	const CABLE_H := 2.6     # 縁の床から線まで
	const END_H := 3.3       # 終点の線の高さ（着く屋上から）
	_teach("zipline")
	var xf := frame()
	var y0 := pos.y
	_node(pos, Act.JUMP, 0.03, 0.25)
	_close_floor()
	pos += dir() * length + Vector3.DOWN * drop
	var land := pos
	_open_floor()
	_lip()
	var a := xf * Vector3(0, CABLE_H, 0.15)
	var b := land + dir() * 4.0 + Vector3.UP * END_H
	_zip_cable(a, b, xf.basis * Vector3.RIGHT, y0, land.y, true)
	pos = b - Vector3.UP * END_H
	_node(pos, Act.ZIP)
	_busy = true
	_walk(5.0)
	_busy = false


# --- 近道のある区間（仕様書 7章「主ルート＋近道」）--------------------------------------------
# 主ルートは今までどおり色付きで迷わず走れる。近道は色を付けず、屋上の物（足場・室外機・塔屋・電線・看板）の
# 中に隠す。近道は難しいが速い。失敗しても主ルートに落ちるだけにして、即死にしない（試しやすい）。

## スイングバーの近道（一段低い谷をはさんだ向こう岸へ）。g = 谷の幅、lat = 主ルートが横へずれる距離、near = 谷の手前・向こうの床の長さ。
## 主ルート：手前の屋上を斜めに横へずれ、縁から谷の屋上（3.6 m下）へ飛び降り（ローリング）、谷を走って向こう岸の壁を縦ウォールランで登り、斜めに戻る。
## 近道：縁の真ん中から跳んで工事の足場の横棒（縁から4.5 m・高さ2.45 m）を掴み、振って離せば上の高さのまま向こうへ着く（失敗しても谷の屋上に落ちるだけ）
func _swing_gap(g: float, lat_arg: float = 0.0, near_arg: float = 0.0) -> void:
	const DROP := 3.6
	const BAR_Z := 4.5     # 縁から棒まで
	const BAR_H := 2.45
	const POST_X := 3.05
	var lat: float = lat_arg if lat_arg > 0.0 else SWINGGAP_LAT
	var near: float = near_arg if near_arg > 0.0 else SWINGGAP_NEAR
	var far := near
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	_teach("roll")
	_teach("wallclimb")
	_node(pos)
	var from := nodes.size() - 1
	_close_floor()
	var xf := frame()
	var y := pos.y
	var tint := _floor_tint
	var c := side * lat
	var w := lat + 10.0
	var mid_lat := lat * 0.5
	# 手前・向こうの床と谷の屋上（3 つとも全幅）
	for f: Array in [[0.0, near], [near + g, near + g + far]]:
		var fc: float = (f[0] + f[1]) * 0.5
		var fl: float = f[1] - f[0]
		CourseProps.box(geo, xf, Vector3(side * mid_lat, (STREET_Y - y) * 0.5, -fc), Vector3(w, y - STREET_Y, fl), Mat.BUILDING, 0, tint)
	CourseProps.box(geo, xf, Vector3(side * mid_lat, (STREET_Y - y - DROP) * 0.5, -(near + g * 0.5)), Vector3(w, y - STREET_Y - DROP, g),
			Mat.BUILDING, 0, tint)
	# 向こう岸の壁の主ルート側（縦ウォールランの壁は面もルートカラー）と、登った先の縁
	CourseProps.box(geo, xf, Vector3(c, -DROP * 0.5, -(near + g) + 0.03), Vector3(2.6, DROP - 0.3, 0.06), Mat.ROUTE, NC)
	CourseProps.box(geo, xf, Vector3(c, -0.1, -(near + g) - 0.06), Vector3(LANE, 0.2, 0.14), Mat.ROUTE, NC)
	_busy = true
	_node(pos + dir() * (near * 0.5) + right() * c * 0.5)
	_node(pos + dir() * near + right() * c)
	_node(pos + dir() * (near + g - 5.5) + right() * c + Vector3.DOWN * DROP)   # 壁へは真っすぐ入る（斜めだと横ウォールランになる）
	_node(pos + dir() * (near + g) + right() * c + Vector3.DOWN * DROP, Act.JUMP, 0.1, 0.5)
	_node(pos + dir() * (near + g + 2.0) + right() * c)
	_node(pos + dir() * (near + g + far * 0.5) + right() * c * 0.5)
	pos += dir() * (near + g + far)
	_node(pos)
	var to := nodes.size() - 1
	_open_floor()
	_walk(3.0)
	_busy = false
	# 足場：谷の屋上から立つ支柱2本と、掴める横棒（色なし）。その下に腰の高さの手すりと足場板（見た目だけ）
	var bz := near + BAR_Z
	var bar_a := xf * Vector3(-POST_X + 0.15, BAR_H, -bz)
	var bar_b := xf * Vector3(POST_X - 0.15, BAR_H, -bz)
	geo.add_beam(bar_a, bar_b, 0.05, Mat.METAL, NC, 10)
	grab_lines.append(GrabLines.bar(bar_a, bar_b))
	for sx: float in [-1.0, 1.0]:
		for dz: float in [0.0, 1.8]:
			var foot := xf * Vector3(sx * POST_X, -DROP, -bz - dz)
			var top := xf * Vector3(sx * POST_X, BAR_H + 0.5, -bz - dz)
			geo.add_beam(foot, top, 0.045, Mat.METAL, 0, 8)
		geo.add_beam(xf * Vector3(sx * POST_X, -DROP + 1.0, -bz), xf * Vector3(sx * POST_X, -DROP + 1.0, -bz - 1.8), 0.03, Mat.METAL, NC, 6)
		geo.add_beam(xf * Vector3(sx * POST_X, -DROP + 0.2, -bz), xf * Vector3(sx * POST_X, BAR_H - 0.3, -bz - 1.8), 0.025, Mat.METAL, NC, 5)
		geo.add_beam(xf * Vector3(sx * POST_X, BAR_H, -bz), xf * Vector3(sx * POST_X, BAR_H, -bz - 1.8), 0.04, Mat.METAL, NC, 6)
		CourseProps.box(geo, xf, Vector3(sx * (POST_X + 0.45), -DROP + 2.0, -bz - 0.9), Vector3(0.9, 0.05, 2.2), Mat.HAZARD, NC)
		for k: int in 3:
			CourseProps.box(geo, xf, Vector3(sx * (POST_X - 0.06), BAR_H, -bz + 0.0 - 0.6 * k), Vector3(0.14, 0.14, 0.1), Mat.DARK, NC)
	geo.add_beam(xf * Vector3(-POST_X, BAR_H + 0.5, -bz - 1.8), xf * Vector3(POST_X, BAR_H + 0.5, -bz - 1.8), 0.04, Mat.METAL, NC, 6)
	var edge := xf * Vector3(0, 0, -near)
	var land := xf * Vector3(0, 0, -(near + g + 2.0))
	var sc: Array[Dictionary] = [
		_bn(edge, Act.JUMP, 0.03, 0.25),
		_bn(xf * Vector3(0, 0, -bz), Act.SWING),
		_bn(land),
	]
	_shortcut("swing", from, to, sc, Transform3D(xf.basis, xf * Vector3(0, BAR_H - 0.8, -bz)), Vector3(5.0, 3.0, 4.0),
			["SWING"], xf * Vector3(0, BAR_H, -bz))
	_scuffs(Transform3D(xf.basis, xf * Vector3(0, 0, -(near - 0.7))), 5, 1.4, 1.0)
	_keep_clear(edge, land, 3.2)


## スイングバーの近道の寸法：主ルートが横へずれる距離と、谷の手前・向こうの床の長さ
const SWINGGAP_LAT := 4.0
const SWINGGAP_NEAR := 3.0


## ジップラインの近道の寸法：主ルートが横へずれる距離と、谷に架かる橋の長さ（短いほど近道の得が小さい）
const ZIP_LAT := 7.5
const ZIP_BEAM := 18.0
## 谷を渡った後、斜めに戻る長さ
const ZIP_DIAG := 12.0
## ウォールキックの近道の寸法：木箱の段の数と、段までの横の距離
const KICK_STEPS := 3
const KICK_LAT := 11.0


## ジップラインの近道。主ルート：角を曲がって横へずれ、谷に架かる橋（梁）を渡って一段下り、戻る（角4つ）。
## 近道：角の先の塔屋によじ登り、屋上の端から跳んで電線（ジップライン）を掴み、谷を真っすぐ滑り降りる
func _zip_jog(side: float, lat_arg: float = 0.0, beam_arg: float = 0.0) -> void:
	const HOUSE_H := 2.2      # 塔屋の屋根の上面は +0.1（よじ登れる2.4 mより低く）
	const HOUSE_Z := 6.0      # 塔屋の中心（角から）
	const CABLE_H := 2.7      # 塔屋の屋根から線まで
	const DROP := 3.0
	const END_H := 3.3        # 終点の線の高さ（着く屋上から）
	_in_section = true
	var lat: float = lat_arg if lat_arg > 0.0 else ZIP_LAT   # 主ルートが横へずれる距離
	var beam: float = beam_arg if beam_arg > 0.0 else ZIP_BEAM   # 谷に架かる橋の長さ
	var w := _floor_width
	var from := nodes.size() - 1
	var xf := frame()
	var y0 := pos.y
	_turn(side, HOUSE_Z + 3.5)
	_walk(maxf(lat - (w * 0.5 + 1.0), 1.0))
	_turn(-side)
	_beam(beam, 1.4)
	# 一段下りた屋上は広く取って、角を曲がらず斜めに戻る
	var lateral_off := absf((pos - xf.origin).dot(xf.basis * Vector3.RIGHT))
	width = lateral_off * 2.0 + w
	_drop(DROP)
	width = w
	var back_from := pos
	var p4 := pos + dir() * ZIP_DIAG - right() * side * lateral_off
	_keep_clear(back_from, p4, 3.5)
	pos = p4
	_node(pos)
	_close_floor()
	_open_floor()
	_busy = true
	_walk(12.0)
	_busy = false
	var to := nodes.size() - 1
	_in_section = false
	# 塔屋（扉が角の方を向く）と、屋根の上の柱から谷の向こうへ張った線
	var house_xf := xf * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -HOUSE_Z))
	CourseProps.stair_house(geo, house_xf, 3.0, 3.0, HOUSE_H)
	_scuffs(Transform3D(xf.basis, xf * Vector3(0, 0, -(HOUSE_Z - 1.5))), 4, 1.6, 1.4, true)
	var top := HOUSE_H + 0.1
	var a := xf * Vector3(0, top + CABLE_H, -(HOUSE_Z + 1.5))
	var north := xf.basis * Vector3.FORWARD
	var b := p4 + north * (w * 0.5 + 4.0) + Vector3.UP * END_H
	_zip_cable(a, b, xf.basis * Vector3.RIGHT * side, y0, p4.y)
	var sc: Array[Dictionary] = [
		_bn(xf * Vector3(0, 0, -(HOUSE_Z - 1.5)), Act.JUMP, 0.12, 0.5),
		_bn(xf * Vector3(0, top, -HOUSE_Z)),
		_bn(xf * Vector3(0, top, -(HOUSE_Z + 1.4)), Act.JUMP, 0.03, 0.25),
		_bn(b - Vector3.UP * END_H, Act.ZIP),
	]
	var mid := (a + b) * 0.5
	_shortcut("zipline", from, to, sc, Transform3D(xf.basis, Vector3(mid.x, y0 + 0.5, mid.z)), Vector3(4.0, 9.0, 10.0),
			["ZIPLINE"], a - north * 1.0)
	_keep_clear(a, b, 2.5)


## ウォールキックの近道。h m の高い壁（縦ウォールランだけでは縁に届かない）。
## 主ルート：屋上の片側の張り出しに木箱が3段（ルートカラー）。横へ寄って1段ずつよじ登り、上で戻る（遅いが確実）。
## 近道：正面の壁を縦ウォールランで駆け上がり、頂点で壁の方へ倒したままジャンプ（壁を蹴り上がる）→ 縁を掴む
func _kick_wall(h: float, steps_arg: int = 0, lat_arg: float = 0.0) -> void:
	const STEP_D := 2.4
	var steps: int = steps_arg if steps_arg > 0 else KICK_STEPS   # 木箱の段の数
	var lat: float = lat_arg if lat_arg > 0.0 else KICK_LAT   # 木箱の段までの横の距離
	var wall_z := 8.2 + STEP_D * (steps - 1)   # 壁まで
	var wing := maxf(16.0, 2.0 * lat + 7.0)    # この区間の屋上の幅（木箱の段は張り出しに置く）
	_in_section = true
	_teach("climb")
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var from := nodes.size() - 1
	_close_floor()
	var keep_width := width
	width = wing
	_open_floor()
	var xf := frame()
	var sx := side * lat
	var rise := h / steps
	# 木箱の段（主ルート）：k 段目の上面は rise × (k + 1)、奥の段ほど壁に近い
	# 1段目の正面へまっすぐ入る（よじ登りは正対から±25°まで）
	var first := wall_z - STEP_D * (steps - 1)
	if first < 8.0:
		push_error("kickwall: steps start too close to the section start")
	_node(xf * Vector3(sx, 0, -1.0))   # 先に横へ（角を曲がる分だけ主ルートが遅い）
	_node(xf * Vector3(sx, 0, -(first - 4.0)))
	_keep_clear(xf * Vector3(0, 0, 0), xf * Vector3(sx, 0, -(first - 4.0)), 2.0)
	_keep_clear(xf * Vector3(sx, 0, -(first - 4.0)), xf * Vector3(sx, 0, -wall_z), 2.0)
	for k: int in steps:
		var front := wall_z - STEP_D * (steps - 1 - k)   # この段の前面。段は壁の方へ STEP_D の奥行き（最後の段は壁そのもの）
		var base := rise * k
		_node(xf * Vector3(sx, base, -front), Act.JUMP, 0.12, 0.5)
		if k < steps - 1:
			var top := rise * (k + 1)
			CourseProps.box(geo, xf, Vector3(sx, top * 0.5, -(front + STEP_D * 0.5)), Vector3(2.4, top, STEP_D), Mat.ROUTE)
			_node(xf * Vector3(sx, top, -(front + STEP_D * 0.6)))
	pos = xf * Vector3(0, 0, -wall_z)
	_close_floor()
	pos += Vector3.UP * h
	_open_floor()
	width = keep_width
	var top_xf := frame()
	CourseProps.box(geo, top_xf, Vector3(sx, -0.1, 0.06), Vector3(2.4, 0.2, 0.14), Mat.ROUTE, NC)
	_node(top_xf * Vector3(sx, 0, -2.0))
	_node(top_xf * Vector3(0, 0, -2.0))
	_busy = true
	_walk(7.0)
	_busy = false
	var to := nodes.size() - 1
	_in_section = false
	# 近道：正面（木箱と反対寄り）の壁を駆け上がって蹴り上がる。壁に靴跡
	var kx := -side * 0.8
	_scuffs(Transform3D(xf.basis, xf * Vector3(kx, 0, -wall_z)), 6, 1.0, 2.6, true)
	var sc: Array[Dictionary] = [
		_bn(xf * Vector3(kx, 0, -wall_z), Act.JUMP, 0.1, 0.5),
		_bn(xf * Vector3(kx, 0, -wall_z), Act.CLIMB_KICK),
		_bn(top_xf * Vector3(kx, 0, -2.5)),
	]
	_shortcut("wall_kick", from, to, sc, Transform3D(xf.basis, xf * Vector3(kx, h - 0.6, -(wall_z - 0.5))), Vector3(2.6, 1.6, 1.4),
			[], xf * Vector3(kx, h * 0.5, -(wall_z - 0.2)))


## ジップラインの線：両端に柱（線の横 lateral の向きへ2.6 mずらして立て、腕で吊る）。ground_a / ground_b = 柱を立てる床の高さ
func _zip_cable(a: Vector3, b: Vector3, lateral: Vector3, ground_a: float, ground_b: float, route: bool = false) -> void:
	geo.add_beam(a, b, 0.05 if route else 0.035, Mat.ROUTE if route else Mat.DARK, NC | LevelGeometry.NO_SHADOW, 6)
	grab_lines.append(GrabLines.zip(a, b))
	# 線の目印の玉（電線の標識のように遠くから線があると分かる。ルートカラーではない）
	var n := maxi(2, int(a.distance_to(b) / 7.0))
	for i: int in range(1, n):
		var p := a.lerp(b, float(i) / n) + Vector3.UP * 0.2
		geo.add_cylinder(p, 0.2, 0.36, Mat.HAZARD, Vector3.ZERO, NC | LevelGeometry.NO_SHADOW, Color.WHITE, 10)
	var along := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	for end: Array in [[a, -along, ground_a], [b, along, ground_b]]:
		var p: Vector3 = end[0]
		var out: Vector3 = end[1]
		var foot := p + out * 0.4 + lateral * 2.6
		var post_top := Vector3(foot.x, p.y + 0.5, foot.z)
		geo.add_beam(Vector3(foot.x, float(end[2]), foot.z), post_top, 0.09, Mat.DARK, 0, 8)
		geo.add_beam(post_top - Vector3.UP * 0.3, p + out * 0.4 + Vector3.UP * 0.2, 0.05, Mat.DARK, NC, 6)
		geo.add_beam(p, p + out * 0.4 + Vector3.UP * 0.2, 0.03, Mat.DARK, NC, 5)


# --- 区間・チェックポイント ---------------------------------------------------------

func _place_markers() -> void:
	var total := route_len
	for i: int in 4:
		var at := total * (i + 1) / 5.0
		splits.append(_safe_after(at))
	checkpoint_dists = _spread_checkpoints()
	for d: float in checkpoint_dists:
		checkpoints.append(_safe_after(d - 0.001))


## チェックポイントのルート距離（立てる所 safe の距離）。cp の指定を残し、間隔が CP_MAX_GAP を超える所を均等に埋め、CP_MIN に足りなければ一番長い間隔を割る
func _spread_checkpoints() -> Array[float]:
	var end := goal_dist if goal_dist > 0.0 else route_len
	var out: Array[float] = []
	for d: float in _cp_requests:
		var s := _safe_dist_after(d)
		if s > 0.0 and s < end and not out.has(s):
			out.append(s)
	out.sort()
	var edges: Array[float] = [0.0]
	edges.append_array(out)
	edges.append(end)
	# 指定が無ければ、全体を均等に割る（最低 CP_MIN 個）
	var at_least := CP_MIN if out.is_empty() else 0
	out.clear()
	for i: int in edges.size() - 1:
		out.append_array(_fill_gap(edges[i], edges[i + 1], at_least))
		if i + 1 < edges.size() - 1:
			out.append(edges[i + 1])
	# 数が足りなければ、一番長い間隔を割る
	while out.size() < CP_MIN:
		var chain: Array[float] = [0.0]
		chain.append_array(out)
		chain.append(end)
		var wide := 0
		for i: int in chain.size() - 1:
			if chain[i + 1] - chain[i] > chain[wide + 1] - chain[wide]:
				wide = i
		var mid := _nearest_safe(chain[wide], chain[wide + 1], (chain[wide] + chain[wide + 1]) * 0.5)
		if mid < 0.0:
			break
		out.append(mid)
		out.sort()
	return out


## a〜b の間（どちらも含まない）に、間隔が CP_MAX_GAP 以下になるよう均等に置くチェックポイントの距離（at_least 個以上）
func _fill_gap(a: float, b: float, at_least: int) -> Array[float]:
	var none: Array[float] = []
	if b - a <= CP_MAX_GAP and at_least == 0:
		return none
	var best: Array[float] = none
	var best_gap := INF
	var n := maxi(at_least, ceili((b - a) / CP_MAX_GAP) - 1)
	# 立てる所に寄せると間隔が広がるので、超えたら1つ増やして置き直す
	for extra: int in 8:
		var pts: Array[float] = []
		for i: int in n + extra:
			var d := _nearest_safe(a, b, a + (b - a) * (i + 1) / float(n + extra + 1))
			if d >= 0.0 and not pts.has(d):
				pts.append(d)
		pts.sort()
		var gap := 0.0
		var prev := a
		for d: float in pts:
			gap = maxf(gap, d - prev)
			prev = d
		gap = maxf(gap, b - prev)
		if gap < best_gap:
			best_gap = gap
			best = pts
		if gap <= CP_MAX_GAP:
			break
	return best


## a〜b の間（どちらも含まない）で、距離 d にいちばん近い立てる所の距離（無ければ -1）
func _nearest_safe(a: float, b: float, d: float) -> float:
	var best := -1.0
	for s: Dictionary in safe:
		var sd: float = s.dist
		if sd <= a + 0.5 or sd >= b - 0.5:
			continue
		if best < 0.0 or absf(sd - d) < absf(best - d):
			best = sd
	return best


## ルート距離 d 以降で最初に立てる所の距離（無ければ -1）
func _safe_dist_after(d: float) -> float:
	for s: Dictionary in safe:
		if (s.dist as float) >= d:
			return s.dist
	return -1.0


## スタート→チェックポイント→ゴールの一番長い間隔（m）
func max_checkpoint_gap() -> float:
	var gap := 0.0
	var prev := 0.0
	for d: float in checkpoint_dists:
		gap = maxf(gap, d - prev)
		prev = d
	return maxf(gap, goal_dist - prev)


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
				if not _is_clear(p, room * 0.5 + 0.8):
					f += 2.0  # 近道の通り道には置かない
					continue
				f += _prop(kind, facing, along, room, usable - f, side) + rng.randf_range(2.0, 5.0)


## 小物を1つ置く。戻り値 = 使った奥行き（ルート方向）
func _prop(kind: String, xf: Transform3D, along: Transform3D, room: float, left: float, side: float = 1.0) -> float:
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
			# 発光面（-Z）を道へ向け、さらに走ってくる人のほうへ35°振る（真横だと走りながら見えない）
			CourseProps.billboard(geo, xf * Transform3D(Basis(Vector3.UP, deg_to_rad(35.0 * side)), Vector3(0, 0, room * 0.3)),
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
## 足場（木箱）・ウォールランの壁・梁・下り坂・ジップライン（高い屋上から低い屋上へ）・スイングバー（路地の上）を置いて、
## どこからでもどこかへ行けるようにする。
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
	checkpoint_dists.clear()
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
	if dh > 3.0 and rng.randf() < 0.55:
		# ジップライン：高い屋上の縁から跳んで掴み、低い屋上の奥まで滑り降りる（木箱・坂とは横にずらす）
		offset = lateral * (rng.randf_range(4.5, 6.5) * (1.0 if rng.randf() < 0.5 else -1.0))
		var top := hi - toward * (s_hi * 0.5 - 1.0) + offset
		top.y = hi.y + 2.6
		var low := lo + toward * (s_lo * 0.5 - 6.0) + offset
		low.y = lo.y + 3.3
		_zip_cable(top, low, lateral, hi.y, lo.y)
	if dh < 1.0 and r < 0.35:
		# 路地をまたぐ看板の壁（ウォールラン）
		var wall_c := gap_mid + lateral * rng.randf_range(-5.0, 5.0)
		var top := maxf(a.y, b.y) + 4.5
		var bottom := STREET_Y
		geo.add_box(Vector3(wall_c.x, (top + bottom) * 0.5, wall_c.z), Vector3(0.5, top - bottom, pitch_gap(a, b, sa, sb) + 10.0),
				Mat.ROUTE, Vector3(0, y_deg, 0))
	elif dh < 1.5 and r > 0.75 and pitch_gap(a, b, sa, sb) > 3.0:
		# 路地の上のスイングバー（両端の支柱は通りから立つ）
		var bc := gap_mid + lateral * rng.randf_range(-4.0, 4.0)
		var by := maxf(a.y, b.y) + 2.45
		var ba := Vector3(bc.x, by, bc.z) - lateral * 2.8
		var bb := Vector3(bc.x, by, bc.z) + lateral * 2.8
		geo.add_beam(ba, bb, 0.05, Mat.METAL, NC, 10)
		grab_lines.append(GrabLines.bar(ba, bb))
		for e: Vector3 in [ba - lateral * 0.25, bb + lateral * 0.25]:
			geo.add_beam(Vector3(e.x, STREET_Y, e.z), Vector3(e.x, by + 0.5, e.z), 0.06, Mat.METAL, 0, 8)
	elif dh < 1.5 and r < 0.6:
		# 梁
		var p0 := a + offset
		var p1 := b + offset
		var y := minf(a.y, b.y)
		var mid2 := (p0 + p1) * 0.5
		geo.add_box(Vector3(mid2.x, y - 0.06, mid2.z), Vector3(1.0, 0.12, p0.distance_to(p1)), Mat.ROUTE, Vector3(0, y_deg, 0))


func pitch_gap(a: Vector3, b: Vector3, sa: float, sb: float) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length() - (sa + sb) * 0.5
