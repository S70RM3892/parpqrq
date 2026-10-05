class_name CourseCatalog
extends RefCounted
## コース一覧（仕様書 7章「コース構成（v1.0）」：4エリア×4コース＋フリーラン）。
## コースは「型（モチーフ）」の並びで書き、決まった乱数で数値を振ってレシピ（course_builder.gd の書き方）に展開する。
## 原則（仕様書 7章）:
## - 技は1つずつ教える：エリアの1本目は新しい技を安全な所で単独で出し、次から既存の技と組み合わせる
## - リズム：同じ間隔で技を置く（ヴォルト→ヴォルト→…）
## - 高さで緊張と解放：高所の細い足場 → 大ジャンプで広い屋上へ、を1コースに2〜3回
## - 主ルート＋近道：近道は色を付けず、屋上の物（室外機・足場・塔屋と電線・高い壁・電車の屋根）の中に隠す。1コースに2〜6本。
##   近道が要る技は、前のコースか同じコースの手前の主ルートで先に教える（intro_* の型。技が初めて出る所の手前の床に印を描く）。
##   エリア1は走り・ジャンプ・ヴォルト・ローリングだけで通れる近道（detour_jump / stair_drop / vault_cut）にする。近道の型ごとの得は段で決めてある
##   （人の模型で 段1 0.4〜0.8 / 段2 0.8〜1.6 / 段3 1.6〜3.0 s。docs/BALANCE.md）
## - 近道の型は散らす（審査 #5。course_test が調べる）：どの型も4コース以下／各エリアに「そのエリアにしか出ない型」が3つ以上／
##   どのコースにも2コース以下にしか出ない型の近道が1本以上。型を足す・動かす時は docs/BALANCE.md の表（型 × コース）を見直す。
##   速さが高いと得が減るので、近道は downhill / alley の直後に置かない（stair_drop・canopy_slide・chimney・billboard_kick・detour_swing は特に）
## メダル（開発者・エース・ゴールド・シルバー・ブロンズ）は自動走行のタイムから決めた（式は tests/course_test.gd の _suggest、表は docs/BALANCE.md）。
## 開発者は完璧な走りで近道を全部通った時、エースは人の模型で近道を全部通った時、ゴールド・シルバー・ブロンズは人の模型の主ルートの走りで取れる
## （近道を見つけないと開発者・エースには届かない）。

const FREE_RUN := "free_run"

const AREAS: Array[Dictionary] = [
	{
		"name": "Morning Rooftops", "jp": "朝の屋上", "time": &"morning", "teach": "run / jump / vault / roll",
		"deco": ["ac", "ac", "tank", "antenna", "house", "pipes", "skylight", "tower", "ac"],
		"building_tints": [Color(1, 1, 1), Color(0.95, 0.94, 0.9), Color(0.9, 0.92, 0.95), Color(0.97, 0.93, 0.88)],
		"power_lines": 0.45, "lit": false, "sign_colors": [Color(0.3, 0.55, 0.85), Color(0.9, 0.35, 0.3)],
		"floors": ["concrete", "concrete", "concrete", "gravel"],
	},
	{
		"name": "Construction Highrise", "jp": "工事中の高層", "time": &"noon", "teach": "climb / ledge grab / vertical wall run",
		"deco": ["scaffold", "steel", "barrier", "ac", "tank", "house", "steel", "barrier"],
		"building_tints": [Color(0.86, 0.86, 0.84), Color(0.8, 0.8, 0.79), Color(0.9, 0.88, 0.84)],
		"power_lines": 0.2, "lit": false, "sign_colors": [Color(0.98, 0.78, 0.12)], "accent": Color(0.98, 0.78, 0.12),
		"floors": ["concrete", "metal", "metal", "gravel"],
	},
	{
		"name": "Evening Downtown", "jp": "夕方の繁華街", "time": &"evening", "teach": "wall run / wall jump",
		"deco": ["billboard", "neon", "ac", "neon", "tank", "antenna", "billboard", "ac"],
		"building_tints": [Color(0.95, 0.9, 0.88), Color(0.88, 0.86, 0.9), Color(0.92, 0.92, 0.9)],
		"power_lines": 0.5, "lit": true,
		"sign_colors": [Color(1.0, 0.3, 0.55), Color(0.2, 0.85, 1.0), Color(1.0, 0.85, 0.25), Color(0.5, 1.0, 0.45)],
		"floors": ["concrete", "concrete", "gravel", "metal"],
	},
	{
		"name": "Station at Night", "jp": "夜の駅前", "time": &"night", "teach": "slide / long downhill / everything",
		"deco": ["lamp", "ac", "neon", "skylight", "pipes", "lamp", "tank", "billboard"],
		"building_tints": [Color(0.85, 0.87, 0.92), Color(0.9, 0.9, 0.9), Color(0.8, 0.82, 0.88)],
		"power_lines": 0.35, "lit": true,
		"sign_colors": [Color(0.3, 0.7, 1.0), Color(1.0, 0.45, 0.3), Color(0.95, 0.95, 1.0), Color(0.4, 1.0, 0.7)],
		"floors": ["concrete", "metal", "glass", "concrete"],
	},
	{
		"name": "Free Run", "jp": "フリーラン", "time": &"morning", "teach": "no timer, big district",
		"deco": ["ac", "tank", "antenna", "house", "pipes", "skylight", "billboard", "tower"],
		"building_tints": [Color(1, 1, 1), Color(0.95, 0.94, 0.9), Color(0.9, 0.92, 0.95)],
		"power_lines": 0.4, "lit": false, "sign_colors": [Color(0.3, 0.55, 0.85), Color(0.9, 0.35, 0.3)],
	},
]

## コース：id, area (0〜3), 名前, 乱数の種, 型の並び, メダル [開発者, エース, ゴールド, シルバー, ブロンズ]（秒）
const COURSES: Array[Dictionary] = [
	# --- 1. 朝の屋上（走り・ジャンプ・ヴォルト・ローリング）40〜60秒 ---
	{"id": "1-1", "area": 0, "name": "First Light", "seed": 101,
		"motifs": ["intro_jump", "intro_vault", "intro_roll", "gap_rhythm", "vault_rhythm", "turn", "detour_jump", "stairs_up", "release", "vault_rhythm", "stair_drop", "gap_rhythm"],
		"medals": [38.8, 41.9, 44.5, 52.0, 62.0]},
	{"id": "1-2", "area": 0, "name": "Laundry Lines", "seed": 102,
		"motifs": ["vault_rhythm", "gap_rhythm", "turn", "detour_jump", "vault_rhythm", "vault_cut", "gap_rhythm", "turn", "detour_jump", "stairs_up", "release", "mix_a"],
		"medals": [36.8, 38.8, 41.5, 48.0, 58.0]},
	{"id": "1-3", "area": 0, "name": "Water Towers", "seed": 103,
		"motifs": ["gap_rhythm", "detour_jump", "stairs_up", "tension", "turn", "mix_a", "stair_drop", "vault_rhythm", "detour_jump", "release"],
		"medals": [35.0, 37.3, 40.0, 47.0, 56.0]},
	{"id": "1-4", "area": 0, "name": "Sunrise Line", "seed": 104,
		"motifs": ["mix_a", "vault_cut", "turn", "detour_jump", "tension", "vault_cut", "mix_a", "detour_jump", "stairs_up", "release", "vault_rhythm", "mix_a"],
		"medals": [38.9, 41.6, 45.5, 52.0, 63.0]},
	# --- 2. 工事中の高層（クライム・レッジグラブ・縦ウォールラン）60〜90秒 ---
	{"id": "2-1", "area": 1, "name": "Scaffold Steps", "seed": 201,
		"motifs": ["intro_climb", "gap_rhythm", "intro_ledge", "intro_wallclimb", "intro_swing", "turn", "climb_rhythm", "beam_cross", "scaffold_climb", "release", "climb_rhythm", "swing_gap"],
		"medals": [48.5, 50.6, 54.5, 63.0, 76.0]},
	{"id": "2-2", "area": 1, "name": "Steel Frames", "seed": 202,
		"motifs": ["climb_rhythm", "swing_gap", "turn", "ledge_rhythm", "intro_kick", "tower", "kick_wall", "turn", "gap_rhythm", "climb_rhythm", "scaffold_climb", "release", "mix_b"],
		"medals": [59.5, 62.2, 68.5, 80.0, 96.0]},
	{"id": "2-3", "area": 1, "name": "Crane Yard", "seed": 203,
		"motifs": ["mix_b", "swing_gap", "turn", "tower", "kick_wall", "climb_rhythm", "intro_zip", "crane_swing", "mix_b", "beam_cross", "tower", "vault_rhythm"],
		"medals": [53.9, 57.2, 64.0, 74.0, 89.0]},
	{"id": "2-4", "area": 1, "name": "Topping Out", "seed": 204,
		"motifs": ["climb_rhythm", "kick_wall", "tower", "turn", "intro_vjump", "swing_gap", "beam_cross", "mix_b", "crane_swing", "detour_vault", "tower", "beam_cross", "climb_rhythm", "release", "mix_b"],
		"medals": [64.1, 67.8, 75.5, 88.0, 106.0]},
	# --- 3. 夕方の繁華街（横ウォールラン・壁ジャンプ）60〜90秒 ---
	{"id": "3-1", "area": 2, "name": "Neon Alley", "seed": 301,
		"motifs": ["intro_wallrun", "vault_rhythm", "gap_rhythm", "intro_walljump", "chimney", "wallrun_rhythm", "climb_rhythm", "detour_wallrun", "release", "wallrun_rhythm"],
		"medals": [41.1, 44.9, 51.5, 59.0, 72.0]},
	{"id": "3-2", "area": 2, "name": "Billboard Run", "seed": 302,
		"motifs": ["wallrun_rhythm", "mix_c", "detour_wallrun", "billboard_kick", "alley", "tower", "detour_wallrun", "turn", "wallrun_rhythm", "detour_vault", "release", "mix_c"],
		"medals": [50.1, 56.4, 64.5, 75.0, 90.0]},
	{"id": "3-3", "area": 2, "name": "Rush Hour", "seed": 303,
		"motifs": ["mix_c", "chimney", "alley", "wallrun_rhythm", "detour_wallrun", "mix_c", "turn", "alley", "detour_vault", "tension", "wallrun_rhythm", "detour_wallrun", "mix_c"],
		"medals": [54.1, 59.6, 68.0, 79.0, 95.0]},
	{"id": "3-4", "area": 2, "name": "Last Light", "seed": 304,
		"motifs": ["wallrun_rhythm", "alley", "mix_c", "detour_wallrun", "tower", "billboard_kick", "detour_wallrun", "mix_b", "turn", "detour_swing", "mix_c", "release", "wallrun_rhythm", "mix_c"],
		"medals": [64.4, 69.1, 77.5, 90.0, 108.0]},
	# --- 4. 夜の駅前（スライド・長い下り坂・全部の組み合わせ）90〜150秒 ---
	{"id": "4-1", "area": 3, "name": "Last Train", "seed": 401,
		"motifs": ["intro_slide", "vault_rhythm", "intro_slope", "detour_vault", "slide_rhythm", "zip_jog", "wallrun_rhythm", "climb_rhythm", "canopy_slide", "downhill", "mix_d", "turn", "slide_rhythm", "release", "mix_d"],
		"medals": [72.1, 76.2, 84.0, 97.0, 117.0]},
	{"id": "4-2", "area": 3, "name": "Platform Seven", "seed": 402,
		"motifs": ["mix_d", "downhill", "zip_jog", "alley", "slide_rhythm", "tower", "train_roof", "mix_d", "detour_swing", "wallrun_rhythm", "downhill", "kick_wall", "slide_rhythm", "release", "mix_d", "mix_c"],
		"medals": [86.7, 91.6, 102.0, 118.0, 142.0]},
	{"id": "4-3", "area": 3, "name": "Overpass", "seed": 403,
		"motifs": ["slide_rhythm", "canopy_slide", "turn", "tower", "downhill", "alley", "mix_d", "mix_c", "zip_jog", "mix_b", "detour_swing", "downhill", "turn", "tension", "canopy_slide", "mix_d", "release", "mix_d"],
		"medals": [89.7, 95.2, 102.0, 118.0, 142.0]},
	{"id": "4-4", "area": 3, "name": "Terminal", "seed": 404,
		"motifs": ["mix_d", "downhill", "alley", "zip_jog", "tower", "slide_rhythm", "train_roof", "mix_c", "turn", "zip_jog", "mix_b", "detour_swing", "train_roof", "tension", "mix_b", "turn", "slide_rhythm", "downhill", "release", "mix_d"],
		"medals": [103.4, 107.0, 118.5, 137.0, 165.0]},
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
		return {"id": FREE_RUN, "area": 4, "name": "Free Run", "seed": 501, "motifs": [], "medals": [0.0, 0.0, 0.0, 0.0, 0.0]}
	return {}


static func area_of(id: String) -> Dictionary:
	var c := get_course(id)
	return AREAS[int(c.get("area", 0))]


## 隠れた近道の数（レシピの近道のある区間の行を数える。コースを組み立てずに分かる）
static func shortcut_count(id: String) -> int:
	var n := 0
	for line: String in recipe(id):
		if line.get_slice(" ", 0) in CourseBuilder.SHORTCUT_STEPS:
			n += 1
	return n


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
	g.floors = AREAS[int(c.get("area", 0))].get("floors", ["concrete"])
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
	## 屋上の床の素材（足音が変わる）。形の乱数とは別に振る（床を変えてもコースの形とメダルが変わらない）
	var floors: Array = ["concrete"]
	var floor_rng := RandomNumberGenerator.new()

	func _init(seed_value: int, p_area: int) -> void:
		rng.seed = seed_value
		floor_rng.seed = seed_value * 31 + 7
		area = p_area

	func add(line: String) -> void:
		var head := line.get_slice(" ", 0)
		if head in ["gap", "drop", "up", "ledge", "stairs", "wallrun", "walljump", "beam", "slope", "vjump", "swingbar", "zipline"] or head in CourseBuilder.SHORTCUT_STEPS:
			out.append("floor " + str(floors[floor_rng.randi() % floors.size()]))
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
			"zipjog":
				y -= 3.0
			"zipline":
				y -= f.call(2)
			"kickwall":
				y += f.call(1)
			"stairdrop":
				y -= CourseBuilder.STEP_RISE * 7.0
			"craneswing":
				y -= 1.8
			"trainroof":
				y -= 1.2
			"billboardkick":
				y += 4.7
			"chimney":
				y += CourseBuilder.STEP_RISE * 6.0

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
				add("mark jump")
				add("gap 2.5")
				walk(10, 12)
				add("gap 3.2")
				walk(10, 12)
			"intro_vault":
				add("mark vault")
				add("vault 1.0 wall")
				walk(11, 12)
				add("vault 0.8 wall")
				walk(11, 12)
				add("vault 0.75 ac")
				walk(10, 12)
			"intro_roll":
				walk(6, 8)
				add("mark roll")
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
			"detour_vault":
				walk(5, 7)
				add("detour %s vault" % side())
				walk(7, 9)
			"detour_swing":
				walk(5, 7)
				add("detour %s swing" % side())
				walk(7, 9)
			# --- 近道のある区間（エリア2から：主ルートによじ登り・縦ウォールランを使う）---
			"swing_gap":
				walk(7, 9)
				add("swinggap %.1f" % rng.randf_range(10.5, 11.5))
				walk(8, 10)
			"zip_jog":
				walk(8, 10)
				add("zipjog %s" % side())
				walk(6, 8)
			"kick_wall":
				walk(7, 9)
				add("kickwall 4.6")
				walk(6, 8)
				if y > 6.0:
					add("drop 3.0")
					walk(8, 10)
			# --- 型を増やした近道（1.1.3：エリアごとに違う型。docs/BALANCE.md）---
			"stair_drop":
				walk(7, 9)
				add("stairdrop %s" % side())
				walk(7, 9)
			"vault_cut":
				walk(7, 9)
				add("vaultcut %s" % side())
				walk(7, 9)
			"crane_swing":
				walk(7, 9)
				add("craneswing %s" % side())
				walk(10, 12)
			"scaffold_climb":
				walk(7, 9)
				add("scaffoldclimb %s" % side())
				walk(10, 12)
			"billboard_kick":
				walk(7, 9)
				add("billboardkick %s" % side())
				walk(10, 12)
				if y > 6.0:
					add("drop 3.0")
					walk(8, 10)
			"chimney":
				walk(7, 9)
				add("chimney %s" % side())
				walk(10, 12)
				if y > 6.0:
					add("drop 3.0")
					walk(8, 10)
			"train_roof":
				walk(7, 9)
				add("trainroof %s" % side())
				walk(10, 12)
			"canopy_slide":
				walk(7, 9)
				add("canopyslide %s" % side())
				walk(10, 12)
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
				add("mark climb")
				add("up 1.8")
				walk(10, 12)
				add("up 2.2")
				walk(10, 12)
				add("drop 3.0")
				walk(10, 12)
			"intro_ledge":
				walk(8, 10)
				add("mark ledge")
				add("ledge 3.8 2.6")
				walk(10, 12)
				add("drop 3.0")
				walk(9, 11)
			"intro_wallclimb":
				walk(10, 12)
				add("mark wallclimb")
				add("up 3.6")
				walk(10, 12)
				add("drop 3.5")
				walk(10, 12)
			# --- 1.1 の技の導入（主ルートで色付き。cp の直後で単独に出す：失敗してもすぐ戻れる）---
			"intro_swing":
				walk(10, 12)
				add("cp")
				add("mark swing")
				add("swingbar %.1f" % rng.randf_range(10.0, 11.0))
				walk(10, 12)
				add("swingbar %.1f" % rng.randf_range(10.0, 11.0))
				walk(10, 12)
			"intro_kick":
				walk(10, 12)
				add("cp")
				add("mark wallkick")
				add("up 4.6")
				walk(8, 10)
				add("drop 3.0")
				walk(10, 12)
				add("up 4.6")
				walk(8, 10)
				add("drop 3.0")
				walk(10, 12)
			"intro_zip":
				walk(10, 12)
				add("cp")
				add("mark zipline")
				add("zipline %.1f 3.0" % rng.randf_range(17.0, 19.0))
				walk(10, 12)
			"intro_vjump":
				walk(10, 12)
				add("cp")
				add("mark vaultjump")
				add("vjump 4.8")
				walk(10, 12)
				add("vjump 4.8")
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
				add("mark wallrun R")
				add("wallrun 8 R")
				walk(12, 14)
				add("wallrun 10 L")
				walk(12, 14)
			"intro_walljump":
				walk(10, 12)
				add("mark walljump")
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
				add("mark slide")
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
