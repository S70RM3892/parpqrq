#!/usr/bin/env python3
"""街の材質に使う写真のテクスチャ（Poly Haven、CC0）を落として、シェーダー用に詰め直す。

    python3 tools/fetch_textures.py            # 落として詰める（落とした物は assets/source/textures/、git に入れない）
    python3 tools/fetch_textures.py --pack     # 落とさずに詰め直すだけ

詰めた物（assets/textures/、git に入れる）:
  <名前>_detail.png  R = 明るさのムラ（0.5 = 平均。白い街の色はシェーダーが決め、ここは模様だけ）、G = 粗さ、B = AO（凹み）
  <名前>_normal.png  法線（OpenGL 形式。Godot と同じ）
  CREDITS.md         出典（CC0 は表示不要だが記録として残す）と実寸
.import も書く（ミップマップあり・VRAM 圧縮・法線は法線マップとして）。
"""
import argparse
import json
import os
import sys
import urllib.request

# 名前 → (Poly Haven の素材, 詰めた時の大きさ)。用途は shaders/level.gdshader と level_style.gd
ASSETS = {
    "concrete": ("concrete_floor_01", 2048),       # 屋上の床・白い物（きれいなコンクリ）
    "concrete_dirty": ("concrete_floor_02", 1024),  # 汚れたコンクリ（暗い物・塔屋）
    "plaster": ("white_plaster_02", 1024),          # ビルの外壁
    "metal": ("metal_plate", 1024),                 # 鉄板の床・ダクト（縞鋼板）
    "corrugated": ("factory_wall", 1024),           # 波板
    "gravel": ("gravel_concrete_03", 2048),         # 砂利の屋上
    "tiles": ("large_grey_tiles", 2048),            # 駅・広場の石のタイル
    "asphalt": ("asphalt_02", 1024),                # 谷底の道路
    "shutter": ("painted_metal_shutter", 1024),     # 室外機・設備の塗装した鉄
}
MAPS = {"diff": "Diffuse", "nor_gl": "nor_gl", "rough": "Rough", "ao": "AO"}
UA = {"User-Agent": "parpqrq-texture-fetch/1.0"}

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "..", "assets", "source", "textures")
OUT = os.path.join(HERE, "..", "assets", "textures")

IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/textures/{file}"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map={normal}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def fetch_json(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return json.load(r)


def download(url, dst):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=300) as r, open(dst, "wb") as f:
        f.write(r.read())


def fetch(res):
    os.makedirs(RAW, exist_ok=True)
    meta = {}
    for name, (asset, _size) in ASSETS.items():
        info = fetch_json(f"https://api.polyhaven.com/info/{asset}")
        files = fetch_json(f"https://api.polyhaven.com/files/{asset}")
        for short, key in MAPS.items():
            entry = files.get(key, {}).get(res, {})
            src = entry.get("jpg") or entry.get("png")
            if src is None:
                print(f"  {asset}: no {key} at {res}", file=sys.stderr)
                continue
            dst = os.path.join(RAW, f"{asset}_{short}.jpg" if "jpg" in entry else f"{asset}_{short}.png")
            if not os.path.exists(dst) or os.path.getsize(dst) != src["size"]:
                print(f"  {asset} {key}")
                download(src["url"], dst)
        meta[name] = {"asset": asset, "name": info.get("name", asset), "authors": list(info.get("authors", {}).keys()),
                      "dims": info.get("dimensions", [0, 0])}
    with open(os.path.join(RAW, "meta.json"), "w") as f:
        json.dump(meta, f, indent=1)


def raw_path(asset, short):
    for ext in (".jpg", ".png"):
        p = os.path.join(RAW, f"{asset}_{short}{ext}")
        if os.path.exists(p):
            return p
    return None


def pack():
    from PIL import Image
    import numpy as np
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(RAW, "meta.json")) as f:
        meta = json.load(f)
    credits = ["# 街の材質のテクスチャ", "",
               "すべて [Poly Haven](https://polyhaven.com) の CC0 素材（著作権放棄。表示は不要だが記録として残す）。",
               "`python3 tools/fetch_textures.py` で落として詰め直せる。", "",
               "| ファイル | 素材 | 作者 | 実寸 (mm) |", "| --- | --- | --- | --- |"]
    for name, (asset, size) in ASSETS.items():
        diff = Image.open(raw_path(asset, "diff")).convert("RGB").resize((size, size), Image.LANCZOS)
        d = np.asarray(diff).astype(np.float32) / 255.0
        lin = np.where(d <= 0.04045, d / 12.92, ((d + 0.055) / 1.055) ** 2.4)
        lum = lin[..., 0] * 0.2126 + lin[..., 1] * 0.7152 + lin[..., 2] * 0.0722
        detail = np.clip(lum / max(1e-4, float(lum.mean())) * 0.5, 0.0, 1.0)
        rough_p = raw_path(asset, "rough")
        rough = np.asarray(Image.open(rough_p).convert("L").resize((size, size), Image.LANCZOS)).astype(np.float32) / 255.0 \
            if rough_p else np.full((size, size), 0.8, np.float32)
        ao_p = raw_path(asset, "ao")
        ao = np.asarray(Image.open(ao_p).convert("L").resize((size, size), Image.LANCZOS)).astype(np.float32) / 255.0 \
            if ao_p else np.ones((size, size), np.float32)
        packed = np.stack([detail, rough, ao], axis=-1)
        Image.fromarray((packed * 255.0 + 0.5).astype(np.uint8), "RGB").save(os.path.join(OUT, f"{name}_detail.png"), optimize=True)
        nor = Image.open(raw_path(asset, "nor_gl")).convert("RGB").resize((size, size), Image.LANCZOS)
        nor.save(os.path.join(OUT, f"{name}_normal.png"), optimize=True)
        for file, normal in ((f"{name}_detail.png", 0), (f"{name}_normal.png", 1)):
            with open(os.path.join(OUT, file + ".import"), "w") as f:
                f.write(IMPORT.format(file=file, normal=normal))
        m = meta[name]
        credits.append(f"| `{name}_*` | [{m['name']}](https://polyhaven.com/a/{asset}) | {', '.join(m['authors'])} | "
                       f"{int(m['dims'][0])} × {int(m['dims'][1])} |")
        print(f"  packed {name} ({size}px, mean luminance {float(lum.mean()):.3f})")
    with open(os.path.join(OUT, "CREDITS.md"), "w") as f:
        f.write("\n".join(credits) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--res", default="2k")
    ap.add_argument("--pack", action="store_true", help="落とさずに詰め直すだけ")
    args = ap.parse_args()
    if not args.pack:
        fetch(args.res)
    pack()
    print("fetch_textures: done")


if __name__ == "__main__":
    main()
