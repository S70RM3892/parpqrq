# 1人称パルクールゲーム

仕様書: https://claude.ai/artifact/BCSZ8Yp2NGFhR3yBnQEdz6 （判断基準は 手触り > 爽快さ > グラフィック。60fpsを割る強化は採用しない）

## エンジンと言語
- **Godot 4.7・GDScript。Godot 3の書き方は禁止。** 例:
  - `KinematicBody` → `CharacterBody3D`、`move_and_slide(vel)` → `velocity` に代入して `move_and_slide()`
  - `export var` → `@export var`、`onready var` → `@onready var`、`yield` → `await`
  - `connect("sig", self, "f")` → `sig.connect(f)`、`Spatial` → `Node3D`、`rand_range` → `randf_range`
- 変数・引数・戻り値には必ず型注釈を付ける（`untyped_declaration` 警告を有効にしてある）。
- C#は使わない。
- レンダラーは Mobile。SSR・SSAO・ボリュメトリックフォグ・SDFGI・VoxelGI は使えない前提で書く。

## 構成
- `scripts/player/player.gd` — 状態機械（GROUND / AIR / VAULT / CLIMB / LEDGE_HANG / WALL_RUN / WALL_CLIMB / SLIDE / ROLL / HARD_LAND）。速度計算は自前、`move_and_slide()` は衝突処理だけ
- `scripts/player/vault_probe.gd` — 地形の判定（ヴォルト・縁・横/正面の壁・立てるか）
- `scripts/player/camera_rig.gd` — top_level のカメラリグ。演出は Bob/Dip/Tilt/Shake 層ごとに分ける
- `scripts/player/body/arms.gd`, `legs.gd` — 1人称の手と脚（骨格なしの剛体パーツを手続き的に動かす）
- `scripts/player/movement_params.gd` + `resources/movement_default.tres` — 動きの数値は全部ここ
- `scripts/autoload/settings.gd` — プレイヤー設定（FOV・感度・演出の強さ・手触り4層のON/OFF）
- `scripts/autoload/haptics.gd` — コントローラー振動
- `scenes/ui/debug_overlay.tscn` — FPS・フレーム時間・ゲート判定（F3 / Back）
- `scenes/ui/tuning_panel.tscn` — 数値の調整パネル（F1 / R3）
- `scripts/ui/flow_hud.gd` + `shaders/flow_edge.gdshader` — 勢い値（画面の縁の光）とPerfect表示・スロー
- `scripts/levels/greybox.gd` — 白箱テストコース（配列で定義、開発用）、`course_timer.gd` — 計測・区間タイム・メダル・記録（`run_recording.gd`）、`checkpoint.gd` — 落下時の戻り先
- `scripts/levels/course_catalog.gd` — 16コース＋フリーランの一覧（型の並び→レシピ）とメダル、`course_builder.gd` — レシピから屋上を組み立てる（書き方は先頭）、`course_props.gd` — 屋上の小物、`course.gd` + `scenes/levels/course.tscn` — 1本のコース（一時停止・結果・リプレイもここ）
- `scripts/levels/level_geometry.gd` — 箱・円柱を材質×区画ごとに1メッシュへまとめる、`level_style.gd` + `shaders/level.gdshader` — 街の材質とルートカラー、`atmosphere.gd` — 時間帯（空・太陽・霧）、`backdrop.gd` — 遠景
- `scripts/autoload/game.gd` — タイトル↔コースの流れと記録の読み出し、`audio.gd` — BGM（勢い値で3層）とメニューの音、`scripts/player/player_audio.gd` — プレイヤーの音
- `scripts/ui/` — `title.gd`（タイトル・コース選択・操作説明・初回の酔い対策）、`settings_menu.gd`、`pause_menu.gd`、`results_panel.gd`、`replay_viewer.gd`、`ui_theme.gd`
- `tools/build_audio.gd` — 効果音とBGMを合成して `assets/audio/` に書き出す（`godot --headless --path . -s tools/build_audio.gd`）、`tools/print_course.gd` — コースのレシピと道しるべを表示
- `tools/build_body.gd` — `assets/source/*.glb` から体のメッシュを作り直す（`godot --headless --path . -s tools/build_body.gd`）
- `tools/capture.tscn` — 画面を撮って見た目を確認する（`xvfb-run -a godot --path . res://tools/capture.tscn -- --scene=<tscn> --out=<path> --at=1.0,3.0 --forward`）

## 作業ルール
- 変更のたびに Godot MCP（`.mcp.json`）で実行し、出力のエラーを読んで自分で直す。
- コミット前にテストを3つ通す（どれも終了コード0で合格）:
  - スモークテスト `godot --headless --path . --fixed-fps 60 res://tests/smoke_test.tscn` — 白箱コースを自動で走り、全技が仕様どおり出るか
  - コーステスト `godot --headless --path . --fixed-fps 60 res://tests/course_test.tscn` — 全16コースを自動走行（`tests/autopilot.gd`）で走りきれるか。コースを変えたら出てきたメダルの目安を `course_catalog.gd` に写す
  - 画面の流れ `godot --headless --path . --fixed-fps 60 res://tests/flow_test.tscn` — タイトル→コース→結果→リプレイ→一時停止→コース選択→フリーラン
- Godot MCP が動かない環境（ディスプレイなし）では `xvfb-run -a godot --path . --audio-driver Dummy --quit-after 240` で描画ありの実行をして出力を読む
- 手触りの数値（ジャンプの高さ、カメラ演出の強さなど `MovementParams` と演出の値）は勝手に変えない。持ち主が走りながら決める。
- 入力は InputMap のアクション名で扱う（キー・ボタンを直接読まない）。player.gd では `_just()` / `_held()` / `_move_input()` を通す（`input_enabled` で止められるように）。
- リトライ・落下で戻ったことは `Player.respawned(to_start)` で受け取る。入力を別の場所で読み直さない。
- テストは記録を `smoke_test` / `test_<id>` / `flow_test` のIDで取る（持ち主の自己ベストとゴーストを上書きしない）。設定を変えるテストは最後に全部戻す。
- コースの見た目・材質を足す時は1つのメッシュにまとめる仕組み（LevelGeometry）を通す。ノードを1つずつ置かない（描画の呼び出しが増える）。

## GDScriptの落とし穴（このプロジェクトで踏んだもの）
- ラムダはローカル変数を値でコピーする。シグナルで数を数える時は Dictionary/Array に入れる
- CharacterBody3D の段差判定は法線で見ない。カプセルの丸い底が角に当たると法線が斜め上を向く。接触位置の高さで見る
- 階段は段だけにしない。段の角を結ぶ見えない坂（greybox.gd の `_stairs`）を重ねる。段差の自動乗り越えは単発の段差用
- 上向きに動いている間は Godot の床吸着が効かない。坂の頂上では `apply_floor_snap()` を自分で呼ぶ
- 空のシェーダーで `TIME` を使うと、空の放射輝度マップが毎フレーム作り直される（重い）。動くものは空とは別のメッシュで描く
- `RenderingServer.global_shader_parameter_get()` はエディタ専用。実行中に読む値はスクリプト側に持つ（`LevelStyle.night_amount`）
- `Input.action_press()` は押しっぱなしのアクションを押し直しても「押した瞬間」にならない。一度離して次のフレームで押す。GUI を動かすテストは `Input.parse_input_event(InputEventAction)` を使う
- ヘッドレス実行では音が合成されず、鳴らした音が解放されないまま終了時に「使用中のリソース」が出る。`Audio.enabled` で鳴らさない。終了は `Audio.quit_game()`
- `_set` / `_get` などは Object の仮想関数と名前がぶつかる（static でも）。補助関数に使わない
