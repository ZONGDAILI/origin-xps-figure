"""把多层渲染合成为带真实透明度的最终图（numpy 向量化）。

输入顺序：
  raw.png                       实测数据点（黑色空心圆）
  fill1..fill4.png              四个分峰的填充，各自用饱和色画（每层单独渲染 → 重叠处会叠加）
  rest.png                      其余全部内容（分峰线、包络、背景、坐标轴、文字、色标）
  out.png  raw_alpha  fill_alpha

合成顺序 = 数据点(底层) → 4 个填充(各 fill_alpha) → 线条(顶层)。
抠白：raw/rest 按"离白色的距离"；fill 按"像素是否落在 白→填充色 连线上"。
"""
import sys
import numpy as np
from PIL import Image

WHITE = 255.0


def load(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)


def key_dark(arr, soft=26.0):
    return np.clip((WHITE - arr.min(axis=2)) / soft, 0.0, 1.0)


def key_fill(arr, color, soft=16.0):
    d = arr - WHITE
    v = np.array(color, dtype=np.float32) - WHITE
    n2 = float((v * v).sum())
    f = np.clip((d * v).sum(axis=2) / n2, 0.0, 1.0)
    res = np.sqrt(((d - f[..., None] * v) ** 2).sum(axis=2))
    return np.where((res <= soft) & (f > 0.01), f, 0.0).astype(np.float32)


def blend(out, arr, alpha_map, global_alpha):
    a = (alpha_map * global_alpha)[..., None]
    return a * arr + (1.0 - a) * out


def main():
    args = sys.argv[1:]
    raw_p, rest_p, out_p = args[0], args[1], args[2]
    fill_ps = args[3:7]
    raw_alpha = float(args[7])
    fill_alpha = float(args[8])
    # 第 9 个参数："r,g,b;r,g,b;..."（4 个分峰的填充色，顺序与填充层一致）
    colors_arg = args[9] if len(args) > 9 else ''
    fills = []
    for part in colors_arg.split(';'):
        if part.strip():
            fills.append(tuple(int(v) for v in part.split(',')))
    if len(fills) != 4:
        fills = [(11, 83, 148), (111, 168, 220), (224, 102, 102), (153, 0, 0)]

    raw = load(raw_p)
    rest = load(rest_p)
    H, W = rest.shape[:2]
    out = np.full((H, W, 3), WHITE, dtype=np.float32)

    out = blend(out, raw, key_dark(raw), raw_alpha)
    for path, color in zip(fill_ps, fills):
        arr = load(path)
        if arr.shape[:2] != (H, W):
            raise SystemExit("尺寸不一致：%s" % path)
        out = blend(out, arr, key_fill(arr, color), fill_alpha)
    out = blend(out, rest, key_dark(rest), 1.0)

    Image.fromarray(out.clip(0, 255).astype(np.uint8)).save(out_p)
    print("saved", out_p, W, "x", H)


if __name__ == "__main__":
    main()
