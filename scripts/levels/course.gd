class_name Course
extends Node3D
## 1本のコース（仕様書 7章）。CourseCatalog のレシピから実行時に組み立てる（読み込み画面なしで数百ms）。
## 子: Atmosphere（空・霧・太陽）、Geometry（屋上と小物）、Backdrop（遠景）、CourseTimer、Checkpoint、Player

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const CHECKPOINT_SIZE := Vector3(16, 8, 2)

## 次に開くコース（メニューが入れる。空ならシーンの course_id）
static var pending_id: String = ""

@export var course_id: String = "1-1"

var def: Dictionary
var area: Dictionary
var builder: CourseBuilder
var player: Player
var timer: CourseTimer
var free_run: bool = false
var build_ms: int = 0


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	if pending_id != "":
		course_id = pending_id
	def = CourseCatalog.get_course(course_id)
	area = CourseCatalog.area_of(course_id)
	free_run = course_id == CourseCatalog.FREE_RUN
	if area.has("accent"):
		LevelStyle.set_accent(area.accent)

	var geo := LevelGeometry.new()
	geo.name = "Geometry"
	builder = CourseBuilder.new(geo, area, int(def.get("seed", 1)))
	if free_run:
		builder.build_district()
	else:
		builder.build(CourseCatalog.recipe(course_id))
	geo.build()
	add_child(geo)

	var atmo := Atmosphere.new()
	atmo.name = "Atmosphere"
	atmo.preset = area.time
	atmo.fog_floor = builder.min_floor_y - 6.0
	add_child(atmo)

	var backdrop := Backdrop.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	backdrop.build(builder.route_points, CourseBuilder.STREET_Y, builder.start_xf.origin.y, int(def.get("seed", 1)))

	for i: int in builder.checkpoints.size():
		var cp := Checkpoint.new()
		cp.name = "Checkpoint%d" % (i + 1)
		cp.transform = builder.checkpoints[i]
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = CHECKPOINT_SIZE
		cs.shape = box
		cs.position = Vector3(0, CHECKPOINT_SIZE.y * 0.5 - 1.0, 0)
		cp.add_child(cs)
		add_child(cp)

	if not free_run:
		timer = CourseTimer.create(course_id, PackedFloat32Array(def.get("medals", [])), builder.start_xf, builder.goal_xf, builder.splits)
		add_child(timer)

	player = PLAYER_SCENE.instantiate() as Player
	player.transform = builder.start_xf
	add_child(player)
	player.kill_y = builder.min_floor_y - 10.0
	build_ms = Time.get_ticks_msec() - t0
	print("course %s: %d primitives, %d backdrop buildings, route %.0f m, built in %d ms" % [
			course_id, geo.primitive_count, backdrop.building_count, builder.route_len, build_ms])
