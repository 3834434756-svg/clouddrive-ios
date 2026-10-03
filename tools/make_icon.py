#!/usr/bin/env python3
"""生成 CloudDrive 的 App 图标（无圆角，iOS 会自动裁切）。"""
import json
import os
from PIL import Image, ImageDraw

SS = 4                     # 超采样倍数，保证边缘平滑
MASTER = 1024
W = MASTER * SS
OUT = "CloudDrive/Assets.xcassets/AppIcon.appiconset"

TOP = (91, 124, 250)       # #5b7cfa
BOT = (56, 84, 224)        # #3854e0


def gradient(size):
    g = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        g.putpixel((0, y), tuple(
            int(TOP[i] + (BOT[i] - TOP[i]) * t) for i in range(3)
        ))
    return g.resize((size, size), Image.BILINEAR)


def cloud_layer(size):
    """白色云朵，画在透明层上。坐标基于 1024 画布，按 size 缩放。"""
    s = size / 1024.0
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    white = (255, 255, 255, 255)

    def sc(*v):
        return tuple(round(x * s) for x in v)

    # 底部圆角矩形
    d.rounded_rectangle(sc(230, 570, 740, 710), radius=round(70 * s), fill=white)
    # 三个圆形堆出云朵轮廓（右圆底边与矩形底边对齐，避免平底下凸出小包）
    for cx, cy, r in ((400, 570, 130), (570, 535, 165), (700, 610, 100)):
        d.ellipse(sc(cx - r, cy - r, cx + r, cy + r), fill=white)

    return layer


def make_master():
    base = gradient(W).convert("RGBA")
    layer = cloud_layer(W)

    # 裁到云朵实际包围盒，再按目标宽度等比缩放，最后居中
    cloud = layer.crop(layer.getbbox())
    target_w = int(W * 0.66)
    cloud = cloud.resize(
        (target_w, round(cloud.height * target_w / cloud.width)), Image.LANCZOS
    )
    x = (W - cloud.width) // 2
    y = (W - cloud.height) // 2 - int(W * 0.015)   # 视觉重心略微上提
    base.alpha_composite(cloud, (x, y))

    return base.resize((MASTER, MASTER), Image.LANCZOS)


# iOS 经典图标尺寸表：(idiom, size_pt, scale)
SPECS = [
    ("iphone", "20x20", 2), ("iphone", "20x20", 3),
    ("iphone", "29x29", 2), ("iphone", "29x29", 3),
    ("iphone", "40x40", 2), ("iphone", "40x40", 3),
    ("iphone", "60x60", 2), ("iphone", "60x60", 3),
    ("ipad", "20x20", 1), ("ipad", "20x20", 2),
    ("ipad", "29x29", 1), ("ipad", "29x29", 2),
    ("ipad", "40x40", 1), ("ipad", "40x40", 2),
    ("ipad", "76x76", 1), ("ipad", "76x76", 2),
    ("ipad", "83.5x83.5", 2),
    ("ios-marketing", "1024x1024", 1),
]


def main():
    # 清掉旧文件，避免上一版残留的图标混进 asset catalog
    if os.path.isdir(OUT):
        for n in os.listdir(OUT):
            os.remove(os.path.join(OUT, n))
    os.makedirs(OUT, exist_ok=True)

    master = make_master()

    images = []
    for idiom, size_pt, scale in SPECS:
        px = int(float(size_pt.split("x")[0]) * scale)
        # 文件名必须唯一：不同 idiom 可能算出同一个像素尺寸，
        # 复用同一文件会让 actool 报重复条目
        name = f"icon-{size_pt.replace('.', '_')}@{scale}x~{idiom}.png"
        master.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name))
        images.append({
            "filename": name,
            "idiom": idiom,
            "scale": f"{scale}x",
            "size": size_pt,
        })

    contents = {
        "images": images,
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(OUT, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(contents, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"✅ 生成 {len(images)} 个尺寸 → {OUT}")
    for n in sorted(os.listdir(OUT)):
        p = os.path.join(OUT, n)
        print(f"   {n}  {os.path.getsize(p)} bytes")


if __name__ == "__main__":
    main()
