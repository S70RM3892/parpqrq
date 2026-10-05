#!/usr/bin/env bash
# 試験官（.claude/agents/aaa-examiner.md）に見せる画面一式を撮る。
#   tools/gallery.sh [出力先ディレクトリ]   （既定 /tmp/gallery）
# 4エリアの代表コースを自動走行で走りながら数枚ずつ、足元、結果画面、タイトルの各画面。
# 本番と同じ Mobile レンダラー（Vulkan）で撮るため、ソフトウェアの Vulkan（lavapipe）と仮想ディスプレイを使う。
# 各 PNG の描画の統計（draw calls・primitives）は同じ名前の .txt に、全部まとめて index.txt に出る。
set -u
OUT="${1:-/tmp/gallery}"
cd "$(dirname "$0")/.."
mkdir -p "$OUT"
rm -f "$OUT"/*.png "$OUT"/*.txt
export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/lvp_icd.json}"
RUN=(xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --audio-driver Dummy --fixed-fps 60)

shoot() {  # shoot <name> <args...>
	local name="$1"; shift
	timeout 900 "${RUN[@]}" res://tools/gallery.tscn -- --out="$OUT/$name" "$@" > "$OUT/$name.log" 2>&1
	grep -E "ERROR|SCRIPT ERROR|WARNING autopilot" "$OUT/$name.log" | grep -v "resources still in use" | head -5
}

shoot a1_1-3 --course=1-3 --at=3,11,19,27 --shortcuts
shoot a2_2-3 --course=2-3 --at=4,14,24,34 --shortcuts
shoot a3_3-2 --course=3-2 --at=5,14,24,40 --results
shoot a4_4-2 --course=4-2 --at=6,20,35,55 --shortcuts
shoot a4_4-4_down --course=4-4 --at=12 --pitch=-55
shoot a1_1-1_up --course=1-1 --at=8 --pitch=25
shoot free --course=free_run --at=2.5 --pitch=-10
shoot ui_title --title=main
shoot ui_courses --title=courses
shoot ui_controls --title=controls
shoot ui_settings --title=settings

cat "$OUT"/*.txt > "$OUT/index.txt" 2>/dev/null
ls "$OUT"/*.png | wc -l | xargs echo "gallery: shots ->"
cat "$OUT/index.txt"
