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
- `scripts/levels/greybox.gd` — 白箱テストコース（配列で定義）、`course_timer.gd` — 計測、`checkpoint.gd` — 落下時の戻り先
- `tools/build_body.gd` — `assets/source/*.glb` から体のメッシュを作り直す（`godot --headless --path . -s tools/build_body.gd`）

## 作業ルール
- 変更のたびに Godot MCP（`.mcp.json`）で実行し、出力のエラーを読んで自分で直す。
- コミット前にスモークテストを通す: `godot --headless --path . --fixed-fps 60 res://tests/smoke_test.tscn`（終了コード0で合格）。コースを自動で走り、全技が仕様どおり出るかを見る
- 手触りの数値（ジャンプの高さ、カメラ演出の強さなど `MovementParams` と演出の値）は勝手に変えない。持ち主が走りながら決める。
- 入力は InputMap のアクション名で扱う（キー・ボタンを直接読まない）。

## GDScriptの落とし穴（このプロジェクトで踏んだもの）
- ラムダはローカル変数を値でコピーする。シグナルで数を数える時は Dictionary/Array に入れる
- CharacterBody3D の段差判定は法線で見ない。カプセルの丸い底が角に当たると法線が斜め上を向く。接触位置の高さで見る
- 階段は段だけにしない。段の角を結ぶ見えない坂（greybox.gd の `_stairs`）を重ねる。段差の自動乗り越えは単発の段差用
- 上向きに動いている間は Godot の床吸着が効かない。坂の頂上では `apply_floor_snap()` を自分で呼ぶ
