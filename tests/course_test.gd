extends Node
## 全コースを自動走行で走りきれるか確かめる（M4）。1.1 から近道も、1.1.1 から人の模型も確かめる。
##   godot --headless --path . --fixed-fps 60 res://tests/course_test.tscn [-- --only=2-3] [--runs=pm,ps,hm,hs]
## 各コースを4回走る：完璧な走り（Perfect を狙う）の主ルート pm と近道を全部通る走り ps、
## 人の模型（押す瞬間が4〜8フレーム遅れる。縁のジャンプだけ早い：autopilot.gd）の主ルート hm と近道を全部通る走り hs。
## 合格：4回とも落ちずにゴール、完璧な走りでは近道はどれも主ルートより速い（MIN_SAVE 秒以上）、
## メダルが走りに合っている（下の _suggest の式と一致。コースを変えたら出てきた数をカタログに写す）、
## 近道の発見：主ルートの走りでは1本も見つからず、近道の走りでは全部見つかる（完璧な走りも人の模型も）、
## 近道の目印：主ルートの走りはシルバー以内なので最初の近道に目印が出る、
## チェックポイント：3つ以上、間隔は 150 m 以下で、シルバーのペースで走って 20 秒以下。
## 終了コード 0 = 全コース合格。各コースのタイムとメダルの目安を出す。--runs は調べる時だけ（絞ると走りの比べる検査を飛ばす）。
## 記録は "test_<id>" のIDで取る（持ち主の自己ベストを上書きしない）。

const COURSE_SCENE := preload("res://scenes/levels/course.tscn")
## 近道1本で縮まる時間の最低（秒）。完璧な走りどうしで比べる
const MIN_SAVE := 0.25
## チェックポイントの間隔の上限（m）と、シルバーのペースで走った時の上限（秒）
const MAX_CP_GAP := 150.0
const MAX_CP_SECONDS := 20.0
const MIN_CHECKPOINTS := 3
## 人の模型の乱数の種（コースの並び順を足す）
const HUMAN_SEED := 20261004
const ALL_RUNS: PackedStringArray = ["pm", "ps", "hm", "hs"]

var _failed: int = 0
var _runs: PackedStringArray = ALL_RUNS
## 一部のコースだけ走った時（--only）は、Jolt の履歴の違いで数フレームずれるので、メダルの食い違いは警告だけにする
var _partial: bool = false
## 人の模型の Perfect の種類ごとの数（表の後ろに出す）
var _human_kinds: Dictionary = {}


func _ready() -> void:
	Settings.hitstop_slowmo = false
	var only := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
			_partial = true
		elif a.begins_with("--runs="):
			_runs = a.trim_prefix("--runs=").split(",")
			_partial = true
	await _check_hint_rule()
	var results: Array[String] = []
	var weak: PackedStringArray = []
	var soft: PackedStringArray = []
	for i: int in CourseCatalog.COURSES.size():
		var c: Dictionary = CourseCatalog.COURSES[i]
		if only != "" and c.id != only:
			continue
		var r := await _run_course(c, i)
		results.append(r.text)
		if r.weak:
			weak.append(c.id)
		if r.soft:
			soft.append(c.id)
	print("\n".join(results))
	if not weak.is_empty():
		print("shortcuts too weak for humans (ACE would not fit under GOLD, ACE = GOLD - 0.5): %s" % ", ".join(weak))
	if not soft.is_empty():
		print("ACE reachable on the main route (human main run <= ACE, the shortcuts barely help humans): %s" % ", ".join(soft))
	var kinds: PackedStringArray = []
	for k: String in _human_kinds:
		kinds.append("%s %d" % [k, _human_kinds[k]])
	if not kinds.is_empty():
		print("human perfects by kind: %s" % ", ".join(kinds))
	print("COURSE TEST: %s" % ("PASS" if _failed == 0 else "FAIL (%d)" % _failed))
	Audio.quit_game(1 if _failed > 0 else 0)


## 目印を出す条件：自己ベストがシルバー以内、または同じコースを5回ゴールした
func _check_hint_rule() -> void:
	var medals := PackedFloat32Array([40.0, 41.0, 45.0, 50.0, 60.0])
	var cases: Array[Array] = [[INF, 0, false], [INF, CourseTimer.HINT_FINISHES - 1, false], [INF, CourseTimer.HINT_FINISHES, true],
			[50.0, 0, true], [50.5, 0, false], [50.5, CourseTimer.HINT_FINISHES, true], [39.0, 0, true]]
	for k: Array in cases:
		if CourseTimer.hint_for(float(k[0]), medals, int(k[1])) != bool(k[2]):
			_failed += 1
			print("FAIL hint rule: best %s finishes %d should be %s" % [str(k[0]), int(k[1]), str(k[2])])
	# コースの目印：まだ何も取っていなくても、5回ゴールすれば出る（4回では出ない）
	Course.pending_id = "1-1"
	var course := COURSE_SCENE.instantiate() as Course
	add_child(course)
	await get_tree().physics_frame
	course.timer.use_records("test_hint_rule", true)
	for n: int in CourseTimer.HINT_FINISHES:
		course.timer.count_finish()
		course.update_shortcut_hint()
		var want := n + 1 >= CourseTimer.HINT_FINISHES
		if (course.hint_shortcut != "") != want:
			_failed += 1
			print("FAIL hint rule: after %d finishes the hint should be %s (got '%s')" % [n + 1, "on" if want else "off", course.hint_shortcut])
	if CourseTimer.finish_count("test_hint_rule") != CourseTimer.HINT_FINISHES:
		_failed += 1
		print("FAIL hint rule: finish count is not saved (%d)" % CourseTimer.finish_count("test_hint_rule"))
	course.timer.use_records("test_hint_rule", true)  # 記録を消す
	course.queue_free()
	await get_tree().physics_frame


func _run_course(c: Dictionary, index: int) -> Dictionary:
	var runs: Dictionary = {}
	for mode: String in _runs:
		runs[mode] = await _run_once(c, mode.ends_with("s"), mode.begins_with("h"), HUMAN_SEED + index)
	var ok := true
	for mode: String in runs:
		ok = ok and runs[mode].ok
	var full := _runs.size() == ALL_RUNS.size()
	var pm: Dictionary = runs.get("pm", {})
	var ps: Dictionary = runs.get("ps", {})
	var hm: Dictionary = runs.get("hm", {})
	var hs: Dictionary = runs.get("hs", {})
	var any: Dictionary = runs[_runs[0]]
	if not any.lightmap_ok:
		_failed += 1
		ok = false
		print("FAIL %s: lightmap stale or missing (run: godot --headless --path . res://tools/bake_lighting.tscn -- --only=%s)" % [c.id, c.id])
	var saves := ""
	var saves_h := ""
	var sug := {"medals": [], "weak": false}
	var soft := false
	if full:
		# 近道ごとに縮んだ時間：分かれる道しるべ → 戻る道しるべ までの時間を2つの走りで比べる。完璧な走りは MIN_SAVE 以上、人は表示だけ
		var s1 := _saves(c, pm, ps, ok, MIN_SAVE)
		var s2 := _saves(c, hm, hs, ok, -INF)
		saves = s1.text
		saves_h = s2.text
		ok = ok and s1.ok and s2.ok
		# 発見の判定の箱が近道の上だけにあるか（主ルートの走りは1本も見つからず、近道の走りは全部見つかる）
		for pair: Array in [["perfect", pm, ps], ["human", hm, hs]]:
			var main_run: Dictionary = pair[1]
			var short_run: Dictionary = pair[2]
			var total: int = main_run.shortcuts.size()
			if ok and (main_run.found != 0 or short_run.found != total):
				_failed += 1
				ok = false
				print("FAIL %s: %s shortcuts found main %d (want 0), shortcuts run %d (want %d)" % [c.id, pair[0], main_run.found, short_run.found, total])
		# 近道の目印：主ルートの走りはシルバー以内なので、最初の近道に目印が出る
		for pair: Array in [["perfect", pm], ["human", hm]]:
			var m: Dictionary = pair[1]
			if ok and not (m.shortcuts as Array).is_empty() and m.hint != str(m.shortcuts[0].name):
				_failed += 1
				ok = false
				print("FAIL %s: after a %s main run (SILVER or better) the hint should mark %s (got '%s')" % [c.id, pair[0], m.shortcuts[0].name, m.hint])
		# メダル：開発者・エース・ゴールド・シルバー・ブロンズが走りから決めた数と同じ
		if ok:
			sug = _suggest(float(ps.time), float(hm.time), float(hs.time))
			soft = float(hm.time) <= float((sug.medals as Array)[1])
			var medals: Array = c.medals
			if not _same(medals, sug.medals):
				if not _partial:
					_failed += 1
					ok = false
				print("%s %s: medal times %s do not fit the runs, want %s (perfect main %.2f, perfect shortcuts %.2f, human main %.2f, human shortcuts %.2f) (update CourseCatalog%s)" % [
						"WARN" if _partial else "FAIL", c.id, str(medals), _fmt(sug.medals), pm.time, ps.time, hm.time, hs.time,
						", copy the numbers from a full run: --only shifts times by a frame or two" if _partial else ""])
	# チェックポイント：3つ以上、間隔が 150 m 以下、シルバーのペースで 20 秒以下
	var gap: float = any.cp_gap
	var gap_s: float = gap * float((c.medals as Array)[3]) / maxf(float(any.goal_dist), 1.0)
	if int(any.cp_count) < MIN_CHECKPOINTS or gap > MAX_CP_GAP + 0.01 or gap_s > MAX_CP_SECONDS:
		_failed += 1
		ok = false
		print("FAIL %s: checkpoints %d, longest gap %.0f m = %.1f s at SILVER pace (want >= %d, <= %.0f m, <= %.0f s)" % [
				c.id, any.cp_count, gap, gap_s, MIN_CHECKPOINTS, MAX_CP_GAP, MAX_CP_SECONDS])
	var text := "%s %-4s %-16s time pm %6.2f  ps %6.2f  hm %6.2f  hs %6.2f   perfects %2d/%2d/%2d/%2d   crashes %d/%d/%d/%d   route %4.0f m  cp %d  gap %3.0f m (%4.1f s)  medals %s  build %d ms" % [
			"ok  " if ok else "FAIL", c.id, c.name, _t(pm), _t(ps), _t(hm), _t(hs), _n(pm, "perfect"), _n(ps, "perfect"), _n(hm, "perfect"),
			_n(hs, "perfect"), _n(pm, "crash"), _n(ps, "crash"), _n(hm, "crash"), _n(hs, "crash"), any.goal_dist, any.cp_count, gap, gap_s,
			_fmt(sug.medals) if full else "-", any.build_ms]
	if full:
		text += "\n       perfect saves: %s\n       human saves:   %s" % [saves if saves != "" else "(no shortcuts)", saves_h if saves_h != "" else "(no shortcuts)"]
	return {"text": text, "weak": sug.weak, "soft": soft}


func _t(r: Dictionary) -> float:
	return float(r.get("time", -1.0))


func _n(r: Dictionary, key: String) -> int:
	return int(r.get(key, 0))


## 近道ごとの短縮の表示 {text: "名前 -0.57, ...", ok: min_save を下回る近道が無い}。下回ればここで失敗に数える
func _saves(c: Dictionary, main: Dictionary, short: Dictionary, ok: bool, min_save: float) -> Dictionary:
	var out: PackedStringArray = []
	var good := true
	for sc: Dictionary in main.shortcuts:
		var a: float = sc.from_dist
		var b: float = sc.to_dist
		var tm := _span(main.passed, a, b)
		var tsc := _span(short.passed, a, b)
		var save := tm - tsc
		out.append("%s %+.2f" % [sc.name, -save])
		if ok and good and not (save >= min_save):
			_failed += 1
			good = false
			print("FAIL %s: shortcut %s is not faster (main %.2f s, shortcut %.2f s)" % [c.id, sc.name, tm, tsc])
	return {"text": ", ".join(out), "ok": good}


## 道しるべ a → b（dist）の間の時間（秒）
func _span(passed: Dictionary, a: float, b: float) -> float:
	if not passed.has(a) or not passed.has(b):
		return INF
	return (int(passed[b]) - int(passed[a])) / 60.0


func _run_once(c: Dictionary, take_shortcuts: bool, human: bool, seed_value: int) -> Dictionary:
	Course.pending_id = c.id
	var course := COURSE_SCENE.instantiate() as Course
	add_child(course)
	await get_tree().physics_frame
	course.timer.use_records("test_" + c.id, true)
	var p := course.player
	var bot := Autopilot.new()
	bot.human = human
	bot.seed_value = seed_value
	add_child(bot)
	var counts := {"crash": 0, "perfect": 0}
	var kinds: Dictionary = {}
	var trace := OS.get_environment("COURSE_TRACE") != ""
	p.crashed.connect(func(spd: float) -> void:
		counts.crash += 1
		if trace and counts.crash <= 3:
			var col := p.get_last_slide_collision()
			print("  crash %.1f m/s at %s state %d node %d collider %s normal %s" % [spd, p.global_position, p.state, bot.idx,
					col.get_collider().name if col else "-", col.get_normal() if col else Vector3.ZERO]))
	p.perfect.connect(func(k: StringName) -> void:
		counts.perfect += 1
		kinds[k] = int(kinds.get(k, 0)) + 1)
	var route := course.builder.route(take_shortcuts)
	bot.start(p, route)
	var limit := 60 * 240
	var frames := 0
	var tn := OS.get_environment("TRACE_NODES").split("-")
	var trace_mode := OS.get_environment("TRACE_MODE")  # main / short（空なら両方）
	var tracing := tn.size() == 2 and (trace_mode == "" or (trace_mode == "short") == take_shortcuts)
	while frames < limit:
		await get_tree().physics_frame
		frames += 1
		if tracing and bot.idx >= tn[0].to_int() and bot.idx <= tn[1].to_int():
			print("  f%d pos (%.2f, %.2f, %.2f) st %d t %.2f v (%.2f, %.2f, %.2f) node %d" % [frames, p.global_position.x, p.global_position.y, p.global_position.z, p.state, p.state_time, p.velocity.x, p.velocity.y, p.velocity.z, bot.idx])
		if not course.timer.last_result.is_empty() or bot.stuck or bot.falls > 0:
			break
	bot.stop()
	if human:
		for k: StringName in kinds:
			_human_kinds[String(k)] = int(_human_kinds.get(String(k), 0)) + int(kinds[k])
	var res := course.timer.last_result
	var ok := not res.is_empty() and bot.falls == 0 and not bot.stuck
	var label := "%s %s%s" % [c.id, "human" if human else "perfect", " (shortcuts)" if take_shortcuts else ""]
	if not ok:
		_failed += 1
		var pos := p.global_position
		print("FAIL %s: stopped at node %d/%d after %.1f s, pos (%.1f, %.1f, %.1f), state %d, falls %d, stuck %s" % [
				label, bot.idx, bot.nodes.size(), frames / 60.0, pos.x, pos.y, pos.z, p.state, bot.falls, bot.stuck])
		if bot.fall_info != "":
			print("     " + bot.fall_info)
	elif CourseTimer.finish_count("test_" + c.id) != 1:
		_failed += 1
		ok = false
		print("FAIL %s: finish count should be 1 after one goal (got %d)" % [label, CourseTimer.finish_count("test_" + c.id)])
	var shortcuts: Array[Dictionary] = []
	for sc: Dictionary in course.builder.shortcuts:
		shortcuts.append({"name": sc.name, "from_dist": float(course.builder.nodes[int(sc.from)].dist),
				"to_dist": float(course.builder.nodes[int(sc.to)].dist)})
	var out := {"ok": ok, "time": float(res.get("time", -1.0)), "passed": bot.passed, "crash": counts.crash,
			"perfect": counts.perfect, "route_len": course.builder.route_len, "build_ms": course.build_ms,
			"goal_dist": course.builder.goal_dist, "cp_count": course.builder.checkpoints.size(), "cp_gap": course.builder.max_checkpoint_gap(),
			"shortcuts": shortcuts, "found": course.timer.shortcuts_found(), "hint": course.hint_shortcut,
			"lightmap_ok": course.lightmap_ok}
	bot.queue_free()
	course.queue_free()
	await get_tree().physics_frame
	return out


## 走りからメダルの目安 [開発者, エース, ゴールド, シルバー, ブロンズ]（秒）。t_ps = 完璧な近道の走り、t_hm = 人の主ルート、t_hs = 人の近道
##   開発者 = t_ps を 0.1 秒単位で切り上げ（余裕は 0.1 秒以内）
##   エース = t_hs × 1.02 を 0.1 秒単位で切り上げ（近道を全部通る上手い人の走り）
##   ゴールド = t_hm × 1.04 を 0.5 秒単位、シルバー = ×1.20・ブロンズ = ×1.45 を 1 秒単位で切り上げ
## 順に増える（DEV < ACE < GOLD < SILVER < BRONZE）ように、エースがゴールド以上なら ゴールド − 0.5 にして weak = true（近道が人には弱い）
func _suggest(t_ps: float, t_hm: float, t_hs: float) -> Dictionary:
	var dev := _ceil_to(t_ps, 0.1)
	var ace := _ceil_to(t_hs * 1.02, 0.1)
	var gold := _ceil_to(t_hm * 1.04, 0.5)
	var silver := _ceil_to(t_hm * 1.20, 1.0)
	var bronze := _ceil_to(t_hm * 1.45, 1.0)
	var weak := ace >= gold
	if weak:
		ace = gold - 0.5
	return {"medals": [dev, ace, gold, silver, bronze], "weak": weak}


## step 単位で切り上げ（浮動小数の誤差で 36.0000001 が 36.1 にならないよう少しだけ引く）
func _ceil_to(x: float, step: float) -> float:
	return ceilf(x / step - 0.001) * step


func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i: int in a.size():
		if absf(float(a[i]) - float(b[i])) > 0.001:
			return false
	return true


func _fmt(m: Array) -> String:
	if m.is_empty():
		return "-"
	var parts: PackedStringArray = []
	for v: Variant in m:
		parts.append("%.1f" % float(v))
	return "[" + ", ".join(parts) + "]"
