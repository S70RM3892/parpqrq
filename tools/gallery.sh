#!/usr/bin/env bash
# 試験官（.claude/agents/aaa-examiner.md）に見せる画面一式を撮る。
#   tools/gallery.sh [出力先ディレクトリ]   （既定 /tmp/gallery）
# 4エリアの代表コースを自動走行で走りながら数枚ずつ、足元、結果画面、タイトルの各画面。
# 本番と同じ Mobile レンダラー（Vulkan）で撮るため、ソフトウェアの Vulkan（lavapipe）と仮想ディスプレイを使う。
# 画面は 16:9（1920×1080）と 20:9（2400×1080、Android のフラッグシップ機。w_ で始まる）の両方で撮る。重なり・はみ出しの確認に使う。
# ui_title / ui_courses は見本の記録（メダル・近道・ゴースト）を入れて撮る（--fake-records。撮り終えたら元の記録に戻る）。
# 各 PNG の描画の統計（draw calls・primitives）は同じ名前の .txt に、全部まとめて index.txt に出る。
set -u
OUT="${1:-/tmp/gallery}"
cd "$(dirname "$0")/.."
mkdir -p "$OUT"
rm -f "$OUT"/*.png "$OUT"/*.txt
export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/lvp_icd.json}"
RUN=(xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --audio-driver Dummy --fixed-fps 60)
RUN_W=(xvfb-run -a -s "-screen 0 2400x1080x24" godot --path . --audio-driver Dummy --fixed-fps 60 --resolution 2400x1080)

shoot() {  # shoot <name> <args...>   （名前が w_ で始まれば 20:9）
	local name="$1"; shift
	local run=("${RUN[@]}")
	[[ "$name" == w_* ]] && run=("${RUN_W[@]}")
	timeout 900 "${run[@]}" res://tools/gallery.tscn -- --out="$OUT/$name" "$@" > "$OUT/$name.log" 2>&1
	grep -E "ERROR|SCRIPT ERROR|WARNING autopilot" "$OUT/$name.log" | grep -v "resources still in use" | head -5
}

shoot a1_1-3 --course=1-3 --at=3,11,19,27 --shortcuts
shoot a2_2-3 --course=2-3 --at=4,14,24,34 --shortcuts
shoot a3_3-2 --course=3-2 --at=5,14,24,40 --results
shoot a4_4-2 --course=4-2 --at=6,20,35,55 --shortcuts
shoot a4_4-4_down --course=4-4 --at=12 --pitch=-55
shoot a1_1-1_up --course=1-1 --at=8 --pitch=25
shoot free --course=free_run --at=2.5 --pitch=-10
# 技の最中の手（状態に入ってから数フレーム後）
shoot hand_vault --course=1-1 --when=VAULT --delay=6
shoot hand_climb --course=2-1 --when=CLIMB --delay=4
shoot hand_swing --course=2-1 --when=SWING --delay=6
shoot hand_zip --course=2-3 --when=ZIPLINE --delay=40
shoot hand_wallrun --course=3-1 --when=WALL_RUN --delay=15
shoot hand_slide --course=4-1 --when=SLIDE --delay=10
# 開発者のゴースト（金を取った記録で走る）
shoot ghost_1-3 --course=1-3 --at=5 --fake-records
shoot ui_title --title=main --fake-records
shoot ui_courses --title=courses --fake-records
shoot ui_controls --title=controls
shoot ui_settings --title=settings
shoot ui_comfort --title=comfort
shoot ui_pause --course=1-1 --at=3 --pause=menu
shoot ui_pause_settings --course=1-1 --at=3 --pause=settings
shoot results_mid --course=1-1 --at=2 --results --rframes=20
shoot results_stamp --course=1-1 --at=2 --results --rframes=38
# 20:9（結果は 1-1 で短く）
shoot w_ui_title --title=main --fake-records
shoot w_ui_courses --title=courses --fake-records
shoot w_ui_controls --title=controls
shoot w_ui_settings --title=settings
shoot w_ui_comfort --title=comfort
shoot w_ui_pause --course=1-1 --at=3 --pause=menu
shoot w_results --course=1-1 --at=14 --results

cat "$OUT"/*.txt > "$OUT/index.txt" 2>/dev/null
ls "$OUT"/*.png | wc -l | xargs echo "gallery: shots ->"
cat "$OUT/index.txt"
