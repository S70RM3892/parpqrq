#!/usr/bin/env python3
"""ギャラリーの画面の白飛び（画面下半分で RGB とも250以上の画素の割合）と明るさを出す。試験官の基準は3%未満。
    python3 tools/clip_metric.py /tmp/gallery/*.png
"""
import sys
from PIL import Image
import numpy as np

for path in sys.argv[1:]:
    a = np.asarray(Image.open(path).convert("RGB")).astype(np.int32)
    h = a.shape[0]
    low = a[h // 2:]
    clip = np.all(low >= 250, axis=-1).mean() * 100.0
    lum = (a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722).mean()
    print(f"{path.split('/')[-1]:28s} clip(bottom) {clip:5.1f}%  mean luma {lum:5.1f}")
