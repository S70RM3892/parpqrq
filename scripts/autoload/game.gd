extends Node
## ゲームの流れ（タイトル ↔ コース）と記録の読み出し（仕様書 8章「メニュー」）。
## 記録そのもの（自己ベスト・区間・ゴースト）は CourseTimer が書く。ここは一覧を出すために読むだけ。

const TITLE_SCENE := "res://scenes/ui/title.tscn"
const COURSE_SCENE := "res://scenes/levels/course.tscn"

## 最後に遊んだコース（タイトルの「続ける」に出す）
var last_course: String = ""
## タイトルに戻った時、コース選択を開く
var open_course_select: bool = false


func play(id: String) -> void:
	last_course = id
	Course.pending_id = id
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(COURSE_SCENE)


func to_title(course_select: bool = true) -> void:
	open_course_select = course_select
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(TITLE_SCENE)


## コースの記録 {best: 秒 or INF, medal: "DEV"/"GOLD"/"SILVER"/"BRONZE"/"", route_off: bool, ghost: bool,
##  shortcuts: 見つけた近道の数, shortcuts_total: 近道の数}
func record(id: String) -> Dictionary:
	var cfg := ConfigFile.new()
	var best := INF
	var route_off := false
	var found := PackedStringArray()
	if cfg.load(CourseTimer.SAVE_PATH) == OK:
		best = cfg.get_value("best", id, INF)
		route_off = cfg.get_value("route_off", id, false)
		found = cfg.get_value("shortcuts", id, PackedStringArray())
	var medals: Array = CourseCatalog.get_course(id).get("medals", [])
	return {
		"best": best,
		"medal": CourseTimer.medal_for(best, PackedFloat32Array(medals)),
		"route_off": route_off,
		"ghost": FileAccess.file_exists("user://ghost_%s.dat" % id),
		"shortcuts": found.size(),
		"shortcuts_total": CourseCatalog.shortcut_count(id),
	}


## 「続ける」で始めるコース：最後に遊んだコースにメダルが無ければそれ、あれば次、全部取っていれば最後に遊んだもの
func recommended() -> String:
	if last_course == "":
		for c: Dictionary in CourseCatalog.COURSES:
			if record(c.id).medal == "":
				return c.id
		return CourseCatalog.COURSES[0].id
	if record(last_course).medal != "":
		var nxt := CourseCatalog.next_id(last_course)
		if nxt != "":
			return nxt
	return last_course
