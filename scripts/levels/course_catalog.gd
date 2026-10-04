class_name CourseCatalog
extends RefCounted
## コース一覧（仕様書 7章「コース構成（v1.0）」：4エリア×4コース＋フリーラン）。
## コースは「型（モチーフ）」の並びで書き、決まった乱数で数値を振ってレシピ（course_builder.gd の書き方）に展開する。
## 原則（仕様書 7章）:
## - 技は1つずつ教える：エリアの1本目は新しい技を安全な所で単独で出し、次から既存の技と組み合わせる
## - リズム：同じ間隔で技を置く（ヴォルト→ヴォルト→…）
## - 高さで緊張と解放：高所の細い足場 → 大ジャンプで広い屋上へ、を1コースに2〜3回
## - 主ルート＋近道：近道（detour）は色を付けない
## メダル（開発者・ゴールド・シルバー・ブロンズ）は自動走行のタイム（Perfectを狙って走る）から決めた。

const FREE_RUN := "free_run"

const AREAS: Array[Dictionary] = [
	{
		"name": "Morning Rooftops", "jp": "朝の屋上", "time": &"morning", "teach": "run / jump / vault / roll",
		"deco": ["ac", "ac", "tank", "antenna", "house", "pipes", "skylight", "tower", "ac"],
		"building_tints": [Color(1, 1, 1), Color(0.95, 0.94, 0.9), Color(0.9, 0.92, 0.95), Color(0.97, 0.93, 0.88)],
		"power_lines": 0.45, "lit": false, "sign_colors": [Color(0.3, 0.55, 0.85), Color(0.9, 0.35, 0.3)],
	},
	{
		"name": "Construction Highrise", "jp": "工事中の高層", "time": &"noon", "teach": "climb / ledge grab / vertical wall run",
		"deco": ["scaffold", "steel", "barrier", "ac", "tank", "house", "steel", "barrier"],
		"building_tints": [Color(0.86, 0.86, 0.84), Color(0.8, 0.8, 0.79), Color(0.9, 0.88, 0.84)],
		"power_lines": 0.2, "lit": false, "sign_colors": [Color(0.98, 0.78, 0.12)], "accent": Color(0.98, 0.78, 0.12),
	},
	{
		"name": "Evening Downtown", "jp": "夕方の繁華街", "time": &"evening", "teach": "wall run / wall jump",
		"deco": ["billboard", "neon", "ac", "neon", "tank", "antenna", "billboard", "ac"],
		"building_tints": [Color(0.95, 0.9, 0.88), Color(0.88, 0.86, 0.9), Color(0.92, 0.92, 0.9)],
		"power_lines": 0.5, "lit": true,
		"sign_colors": [Color(1.0, 0.3, 0.55), Color(0.2, 0.85, 1.0), Color(1.0, 0.85, 0.25), Color(0.5, 1.0, 0.45)],
	},
	{
		"name": "Station at Night", "jp": "夜の駅前", "time": &"night", "teach": "slide / long downhill / everything",
		"deco": ["lamp", "ac", "neon", "skylight", "pipes", "lamp", "tank", "billboard"],
		"building_tints": [Color(0.85, 0.87, 0.92), Color(0.9, 0.9, 0.9), Color(0.8, 0.82, 0.88)],
		"power_lines": 0.35, "lit": true,
		"sign_colors": [Color(0.3, 0.7, 1.0), Color(1.0, 0.45, 0.3), Color(0.95, 0.95, 1.0), Color(0.4, 1.0, 0.7)],
	},
	{
		"name": "Free Run", "jp": "フリーラン", "time": &"morning", "teach": "no timer, big district",
		"deco": ["ac", "tank", "antenna", "house", "pipes", "skylight", "billboard", "tower"],
		"building_tints": [Color(1, 1, 1), Color(0.95, 0.94, 0.9), Color(0.9, 0.92, 0.95)],
		"power_lines": 0.4, "lit": false, "sign_colors": [Color(0.3, 0.55, 0.85), Color(0.9, 0.35, 0.3)],
	},
]

## コース：id, area (0〜3), 名前, 乱数の種, 型の並び, メダル [開発者, ゴールド, シルバー, ブロンズ]（秒）
const COURSES: Array[Dictionary] = [
	# --- 1. 朝の屋上（走り・ジャンプ・ヴォルト・ローリング）40〜60秒 ---
	{"id": "1-1", "area": 0, "name": "First Light", "seed": 101,
		"motifs": ["intro_jump", "intro_vault", "gap_rhythm", "intro_roll", "vault_rhythm", "turn", "gap_rhythm", "stairs_up", "release", "vault_rhythm", "drop_roll", "gap_rhythm"],
		"medals": [34.5, 38.0, 45.0, 56.0]},
	{"id": "1-2", "area": 0, "name": "Laundry Lines", "seed": 102,
		"motifs": ["vault_rhythm", "gap_rhythm", "turn", "detour_jump", "vault_rhythm", "drop_roll", "gap_rhythm", "turn", "stairs_up", "release", "vault_rhythm", "mix_a"],
		"medals": [34.5, 38.0, 45.0, 56.0]},
	{"id": "1-3", "area": 0, "name": "Water Towers", "seed": 103,
		"motifs": ["gap_rhythm", "vault_rhythm", "stairs_up", "tension", "turn", "mix_a", "detour_jump", "gap_rhythm", "turn", "vault_rhythm", "release"],
		"medals": [37.0, 40.5, 48.0, 60.0]},
	{"id": "1-4", "area": 0, "name": "Sunrise Line", "seed": 104,
		"motifs": ["mix_a", "gap_rhythm", "turn", "vault_rhythm", "tension", "detour_jump", "mix_a", "turn", "gap_rhythm", "stairs_up", "release", "vault_rhythm", "mix_a"],
		"medals": [42.5, 46.5, 56.0, 69.0]},
	# --- 2. 工事中の高層（クライム・レッジグラブ・縦ウォールラン）60〜90秒 ---
	{"id": "2-1", "area": 1, "name": "Scaffold Steps", "seed": 201,
		"motifs": ["intro_climb", "gap_rhythm", "intro_ledge", "vault_rhythm", "intro_wallclimb", "turn", "climb_rhythm", "beam_cross", "release", "gap_rhythm", "climb_rhythm"],
		"medals": [39.5, 43.0, 52.0, 64.0]},
	{"id": "2-2", "area": 1, "name": "Steel Frames", "seed": 202,
		"motifs": ["climb_rhythm", "beam_cross", "turn", "ledge_rhythm", "vault_rhythm", "tower", "turn", "gap_rhythm", "climb_rhythm", "detour_jump", "release", "mix_b"],
		"medals": [49.0, 53.5, 64.0, 79.0]},
	{"id": "2-3", "area": 1, "name": "Crane Yard", "seed": 203,
		"motifs": ["mix_b", "ledge_rhythm", "turn", "tower", "gap_rhythm", "climb_rhythm", "turn", "beam_cross", "mix_b", "detour_jump", "tower", "vault_rhythm"],
		"medals": [50.0, 55.0, 65.0, 81.0]},
	{"id": "2-4", "area": 1, "name": "Topping Out", "seed": 204,
		"motifs": ["climb_rhythm", "mix_b", "tower", "turn", "ledge_rhythm", "beam_cross", "mix_b", "turn", "gap_rhythm", "tower", "detour_jump", "climb_rhythm", "release", "mix_b"],
		"medals": [61.0, 66.5, 80.0, 98.0]},
	# --- 3. 夕方の繁華街（横ウォールラン・壁ジャンプ）60〜90秒 ---
	{"id": "3-1", "area": 2, "name": "Neon Alley", "seed": 301,
		"motifs": ["intro_wallrun", "vault_rhythm", "gap_rhythm", "intro_walljump", "turn", "wallrun_rhythm", "climb_rhythm", "detour_wallrun", "release", "wallrun_rhythm"],
		"medals": [40.5, 44.0, 53.0, 65.0]},
	{"id": "3-2", "area": 2, "name": "Billboard Run", "seed": 302,
		"motifs": ["wallrun_rhythm", "mix_c", "turn", "alley", "gap_rhythm", "tower", "detour_wallrun", "turn", "wallrun_rhythm", "vault_rhythm", "release", "mix_c"],
		"medals": [47.0, 51.5, 61.0, 76.0]},
	{"id": "3-3", "area": 2, "name": "Rush Hour", "seed": 303,
		"motifs": ["mix_c", "alley", "turn", "wallrun_rhythm", "ledge_rhythm", "detour_wallrun", "mix_c", "turn", "alley", "tension", "wallrun_rhythm", "mix_c"],
		"medals": [54.5, 59.5, 71.0, 88.0]},
	{"id": "3-4", "area": 2, "name": "Last Light", "seed": 304,
		"motifs": ["wallrun_rhythm", "alley", "mix_c", "turn", "tower", "wallrun_rhythm", "detour_wallrun", "mix_b", "turn", "alley", "mix_c", "release", "wallrun_rhythm", "mix_c"],
		"medals": [62.0, 67.5, 81.0, 100.0]},
	# --- 4. 夜の駅前（スライド・長い下り坂・全部の組み合わせ）90〜150秒 ---
	{"id": "4-1", "area": 3, "name": "Last Train", "seed": 401,
		"motifs": ["intro_slide", "vault_rhythm", "intro_slope", "gap_rhythm", "slide_rhythm", "turn", "wallrun_rhythm", "climb_rhythm", "downhill", "detour_wallrun", "mix_d", "turn", "slide_rhythm", "release", "mix_d"],
		"medals": [67.0, 73.0, 87.0, 108.0]},
	{"id": "4-2", "area": 3, "name": "Platform Seven", "seed": 402,
		"motifs": ["mix_d", "downhill", "turn", "alley", "slide_rhythm", "tower", "detour_jump", "mix_d", "turn", "wallrun_rhythm", "downhill", "ledge_rhythm", "slide_rhythm", "release", "mix_d", "mix_c"],
		"medals": [80.5, 87.5, 104.0, 129.0]},
	{"id": "4-3", "area": 3, "name": "Overpass", "seed": 403,
		"motifs": ["slide_rhythm", "mix_d", "turn", "tower", "downhill", "alley", "detour_wallrun", "mix_d", "turn", "mix_b", "downhill", "wallrun_rhythm", "tension", "slide_rhythm", "mix_d", "release", "mix_d"],
		"medals": [82.0, 89.5, 106.0, 132.0]},
	{"id": "4-4", "area": 3, "name": "Terminal", "seed": 404,
		"motifs": ["mix_d", "downhill", "alley", "turn", "tower", "slide_rhythm", "detour_jump", "mix_c", "turn", "downhill", "mix_b", "wallrun_rhythm", "detour_wallrun", "tension", "mix_d", "turn", "slide_rhythm", "downhill", "release", "mix_d"],
		"medals": [94.5, 103.0, 123.0, 152.0]},
]


static func all_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for c: Dictionary in COURSES:
		out.append(c.id)
	out.append(FREE_RUN)
	return out


static func get_course(id: String) -> Dictionary:
	for c: Dictionary in COURSES:
		if c.id == id:
			return c
	if id == FREE_RUN:
		return {"id": FREE_RUN, "area": 4, "name": "Free Run", "seed": 501, "motifs": [], "medals": [0.0, 0.0, 0.0, 0.0]}
	return {}


static func area_of(id: String) -> Dictionary:
	var c := get_course(id)
	return AREAS[int(c.get("area", 0))]


## 次のコース（無ければ空）
static func next_id(id: String) -> String:
	for i: int in COURSES.size() - 1:
		if COURSES[i].id == id:
			return COURSES[i + 1].id
	return ""


## 型の並びをレシピに展開する（同じ種なら毎回同じコースになる）
static func recipe(id: String) -> PackedStringArray:
	var c := get_course(id)
	var g := _Gen.new(int(c.get("seed", 1)), int(c.get("area", 0)))
	for m: String in c.get("motifs", []):
		g.motif(m)
	return g.out


## 型の展開。高さを一定の範囲に保つ（下がりすぎたら登る型、上がりすぎたら降りる型を選ぶ）
class _Gen:
	var out: PackedStringArray = []
	var rng := RandomNumberGenerator.new()
	var area: int = 0
	var y: float = 0.0
	var last_turn: String = "L"
	var last_side: String = "R"

	func _init(seed_value: int, p_area: int) -> void:
		rng.seed = seed_value
		area = p_area

	func add(line: String) -> void:
		out.append(line)
		# 屋上の高さを追う（上がりすぎ・下がりすぎを避けるため）
		var t := line.split(" ", false)
		var f := func(i: int) -> float: return t[i].to_float() if t.size() > i else 0.0
		match t[0]:
			"up":
				y += f.call(1)
			"drop":
				y -= f.call(1)
			"gap":
				y += f.call(2)
			"ledge":
				y += f.call(2)
			"stairs":
				y += f.call(1) * 0.4
			"slope":
				y -= f.call(1) * sin(deg_to_rad(f.call(2)))
			"wallrun":
				y += f.call(3)

	func walk(lo: float, hi: float) -> void:
		add("walk %.1f" % rng.randf_range(lo, hi))

	func side() -> String:
		last_side = "L" if last_side == "R" else "R"
		return last_side

	func vault_line() -> String:
		var kinds := ["wall", "ac", "pipe", "skylight", "wall"]
		var k: String = kinds[rng.randi() % kinds.size()]
		var h := rng.randf_range(0.7, 1.2)
		return "vault %.2f %s" % [h, k]

	## 隙間：高さに応じて上下を選ぶ
	func gap_line() -> String:
		var dy := 0.0
		var r := rng.randf()
		if y > 8.0 or (y > -4.0 and r < 0.35):
			dy = -rng.randf_range(1.0, 3.2)
		elif r < 0.55 and y < 6.0:
			dy = rng.randf_range(0.3, 0.6)
		var g := rng.randf_range(2.8, 4.2) if dy > -2.0 else rng.randf_range(3.5, 5.0)
		if dy > 0.0:
			g = minf(g, 3.4)
		return "gap %.1f %.1f" % [g, dy]

	func motif(m: String) -> void:
		match m:
			"intro_jump":
				walk(10, 12)
				add("gap 2.5")
				walk(10, 12)
				add("gap 3.2")
				walk(10, 12)
			"intro_vault":
				add("vault 1.0 wall")
				walk(11, 12)
				add("vault 0.8 wall")
				walk(11, 12)
				add("vault 0.75 ac")
				walk(10, 12)
			"intro_roll":
				walk(6, 8)
				add("drop 2.5")
				walk(10, 12)
				add("gap 4.0 -2.5")
				walk(10, 12)
			"vault_rhythm":
				var n := rng.randi_range(3, 4)
				var spacing := rng.randf_range(8.5, 10.5)
				for i: int in n:
					add(vault_line())
					add("walk %.1f" % spacing)
			"gap_rhythm":
				for i: int in rng.randi_range(2, 3):
					add(gap_line())
					walk(8, 11)
			"drop_roll":
				walk(4, 6)
				var h := rng.randf_range(2.2, 3.4)
				add("drop %.1f" % h)
				walk(9, 11)
			"stairs_up":
				walk(5, 7)
				var n := rng.randi_range(4, 7)
				add("stairs %d" % n)
				walk(7, 9)
			"turn":
				walk(5, 7)
				last_turn = "R" if last_turn == "L" else "L"
				add("turn " + last_turn)
				walk(6, 8)
			"detour_jump":
				walk(5, 7)
				add("detour %s jump" % side())
				walk(7, 9)
			"detour_wallrun":
				walk(5, 7)
				add("detour %s wallrun" % side())
				walk(7, 9)
			"tension":
				# 階段で上がり、細い屋上を走って、広い屋上へ大きく跳び降りる
				walk(4, 6)
				add("stairs 6")
				add("width 4.5")
				walk(10, 14)
				add("gap 3.0 0")
				walk(8, 10)
				add("width 12")
				add("gap 4.5 -3.5")
				add("width 10")
				walk(10, 12)
			"release":
				walk(6, 8)
				add("width 13")
				var h := rng.randf_range(3.0, 3.8)
				add("gap %.1f %.1f" % [rng.randf_range(4.5, 5.5), -h])
				add("width 10")
				walk(10, 12)
			"mix_a":
				add(vault_line())
				walk(8, 10)
				add(gap_line())
				walk(8, 10)
				add(vault_line())
				walk(8, 10)
				if y > -6.0:
					var h := rng.randf_range(2.2, 3.0)
					add("drop %.1f" % h)
					walk(8, 10)
			"intro_climb":
				walk(8, 10)
				add("up 1.8")
				walk(10, 12)
				add("up 2.2")
				walk(10, 12)
				add("drop 3.0")
				walk(10, 12)
			"intro_ledge":
				walk(8, 10)
				add("ledge 3.8 2.6")
				walk(10, 12)
				add("drop 3.0")
				walk(9, 11)
			"intro_wallclimb":
				walk(10, 12)
				add("up 3.6")
				walk(10, 12)
				add("drop 3.5")
				walk(10, 12)
			"climb_rhythm":
				var h1 := rng.randf_range(1.5, 2.3)
				add("up %.1f" % h1)
				walk(8, 10)
				add(vault_line())
				walk(8, 10)
				var h2 := rng.randf_range(1.5, 2.3)
				add("up %.1f" % h2)
				walk(8, 10)
				var d := rng.randf_range(2.4, 3.4)
				add("drop %.1f" % d)
				walk(8, 10)
				if y > 6.0:
					add("drop 3.0")
					walk(8, 10)
			"ledge_rhythm":
				add("ledge 3.8 2.6")
				walk(8, 10)
				add("gap %.1f 0" % rng.randf_range(3.0, 3.8))
				walk(8, 10)
				add("ledge 4.0 2.5")
				walk(8, 10)
				add("drop 3.2")
				walk(8, 10)
			"beam_cross":
				walk(5, 7)
				add("beam %.1f" % rng.randf_range(10.0, 16.0))
				walk(8, 10)
			"tower":
				# 縦ウォールランで高所へ、細い梁を渡って、広い屋上へ跳び降りる（緊張と解放）
				walk(5, 7)
				var h := rng.randf_range(3.2, 3.9)
				add("up %.1f" % h)
				add("width 6")
				walk(8, 10)
				add("beam %.1f" % rng.randf_range(9.0, 13.0))
				walk(6, 8)
				add("width 13")
				add("gap 4.8 %.1f" % (-h - 0.3))
				add("width 10")
				walk(10, 12)
			"mix_b":
				add("up %.1f" % rng.randf_range(1.6, 2.2))
				walk(8, 10)
				add(gap_line())
				walk(8, 10)
				add(vault_line())
				walk(8, 10)
				add("ledge 3.8 2.6")
				walk(8, 10)
				add("drop %.1f" % rng.randf_range(3.0, 3.6))
				walk(8, 10)
			"intro_wallrun":
				walk(10, 12)
				add("wallrun 8 R")
				walk(12, 14)
				add("wallrun 10 L")
				walk(12, 14)
			"intro_walljump":
				walk(10, 12)
				add("walljump 2 L")
				walk(12, 14)
			"wallrun_rhythm":
				add("wallrun %.1f %s" % [rng.randf_range(8.0, 11.0), side()])
				walk(8, 10)
				add(vault_line())
				walk(8, 10)
				var dy := -rng.randf_range(0.0, 1.5) if y > -8.0 else 0.0
				add("wallrun %.1f %s %.1f" % [rng.randf_range(9.0, 11.0), side(), dy])
				walk(9, 11)
			"alley":
				walk(6, 8)
				add("walljump %d %s" % [rng.randi_range(2, 3), side()])
				walk(9, 11)
			"mix_c":
				add("wallrun %.1f %s" % [rng.randf_range(8.0, 10.0), side()])
				walk(8, 10)
				add(gap_line())
				walk(8, 10)
				add(vault_line())
				walk(7, 9)
				add("up %.1f" % rng.randf_range(1.6, 2.2))
				walk(8, 10)
				add("drop 3.0")
				walk(8, 10)
			"intro_slide":
				walk(10, 12)
				add("slide")
				walk(12, 14)
				add("slide")
				walk(12, 14)
				add("duct 7")
				walk(12, 14)
			"intro_slope":
				walk(8, 10)
				add("slope 28 13")
				walk(10, 12)
			"slide_rhythm":
				walk(7, 9)  # 前の技の着地でローリングしても、転がり終わってからバーに着く
				add("slide")
				walk(9, 11)
				add(vault_line())
				walk(8, 10)
				add("duct %.1f" % rng.randf_range(5.0, 8.0))
				walk(9, 11)
				add("slide")
				walk(9, 11)
			"downhill":
				# 長い下り坂：スライドで加速し続ける
				walk(6, 8)
				if y < -6.0:
					add("stairs 7")
					walk(6, 8)
				var length := rng.randf_range(26.0, 36.0)
				var deg := rng.randf_range(11.0, 15.0)
				add("slope %.1f %.1f" % [length, deg])
				walk(6, 8)
				add("slide")
				walk(9, 11)
			"mix_d":
				add(vault_line())
				walk(8, 10)
				add("slide")
				walk(8, 10)
				add("wallrun %.1f %s" % [rng.randf_range(8.0, 10.0), side()])
				walk(8, 10)
				add(gap_line())
				walk(8, 10)
				add("up %.1f" % rng.randf_range(1.6, 2.2))
				walk(7, 9)
				add("drop 3.0")
				walk(8, 10)
			_:
				push_error("CourseCatalog: unknown motif " + m)
