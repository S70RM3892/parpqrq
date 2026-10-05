#!/usr/bin/env bash
# クラウドのセッション（毎回まっさらな環境）で、テストと画面の撮影に要る物を入れる。SessionStart フックから呼ばれる。
# - Godot 4.7.2（Linux エディタ版。ヘッドレスのテストと書き出しに使う）
# - ソフトウェアの Vulkan（lavapipe）と仮想ディスプレイ（tools/gallery.sh・tools/capture.tscn が本番と同じ Mobile レンダラーで撮れる）
# - 画像の確認用の Pillow
# 手元の PC（godot が既にある）では何もしない。
set -e
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ] && command -v godot > /dev/null; then
	exit 0
fi
GODOT_VER=4.7.2
if ! command -v godot > /dev/null; then
	mkdir -p /opt/godot
	curl -sSL -o /opt/godot/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VER}-stable/Godot_v${GODOT_VER}-stable_linux.x86_64.zip"
	unzip -o -q /opt/godot/godot.zip -d /opt/godot
	chmod +x "/opt/godot/Godot_v${GODOT_VER}-stable_linux.x86_64"
	ln -sf "/opt/godot/Godot_v${GODOT_VER}-stable_linux.x86_64" /usr/local/bin/godot
fi
if [ ! -f /usr/share/vulkan/icd.d/lvp_icd.json ] || ! command -v xvfb-run > /dev/null; then
	(apt-get install -y -q mesa-vulkan-drivers xvfb > /dev/null 2>&1) || (apt-get update -q > /dev/null 2>&1 && apt-get install -y -q mesa-vulkan-drivers xvfb > /dev/null 2>&1) || true
fi
python3 -c "import PIL" 2> /dev/null || pip install -q pillow numpy > /dev/null 2>&1 || true
cd "$(dirname "$0")/.."
# クラスの一覧と取り込み（無いと「型が見つからない」）
timeout 600 godot --headless --path . --import > /dev/null 2>&1 || true
echo "setup_cloud: godot $(godot --version 2>/dev/null), lavapipe $( [ -f /usr/share/vulkan/icd.d/lvp_icd.json ] && echo yes || echo no )"
