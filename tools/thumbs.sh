#!/usr/bin/env bash
# コース選択のカードの絵（assets/ui/thumbs/<id>.jpg、480×270）を撮り直す。見た目を変えたら実行して、できた画像をコミットする。
#   tools/thumbs.sh            全コース
#   tools/thumbs.sh 1-3 4-2    指定したコースだけ
# 自動走行で決めた時刻（下の表の秒）まで走り、その瞬間の1人称の画面から UI を消して縮める（tools/gallery.gd の --thumb）。
# 本番と同じ Mobile レンダラーで撮るため、ソフトウェアの Vulkan（lavapipe）と仮想ディスプレイ（xvfb）を使う。1本10〜40秒。
# 撮る時刻（秒）は「そのコースの景色が一番よく見える所」：見て選んだ。コースを作り直したらここを見直す。
set -u
cd "$(dirname "$0")/.."
export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/lvp_icd.json}"
declare -A AT=(
	[1-1]=10 [1-2]=14 [1-3]=10 [1-4]=10
	[2-1]=10 [2-2]=7 [2-3]=10 [2-4]=10
	[3-1]=10 [3-2]=10 [3-3]=6 [3-4]=10
	[4-1]=10 [4-2]=10 [4-3]=10 [4-4]=10
	[free_run]=2.5
)
ORDER=(1-1 1-2 1-3 1-4 2-1 2-2 2-3 2-4 3-1 3-2 3-3 3-4 4-1 4-2 4-3 4-4 free_run)
IDS=("$@")
[ ${#IDS[@]} -eq 0 ] && IDS=("${ORDER[@]}")
mkdir -p assets/ui/thumbs
for id in "${IDS[@]}"; do
	timeout 600 xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --audio-driver Dummy --fixed-fps 60 res://tools/gallery.tscn -- \
		--course="$id" --at="${AT[$id]}" --thumb="assets/ui/thumbs/$id.jpg" --out="/tmp/thumb_$id" > "/tmp/thumb_$id.log" 2>&1
	grep -E "SCRIPT ERROR|WARNING autopilot|thumb " "/tmp/thumb_$id.log" | head -3
done
echo "thumbs: done (godot --headless --path . --import で取り込む)"
