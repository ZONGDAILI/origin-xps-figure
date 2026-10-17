"""单谱分峰图的数据准备（通用版）。

从 CasaXPS 窄扫 CSV 里挑**一个循环**，生成单循环宽表 + meta_single.json，
供 Make-XpsStacked.ps1 出"参考图格式"的单谱分峰图（分峰填充 30%、数据点 50%）。

用法（在 prep.py 同目录下运行）：
    python prep_single.py --file YOUR.csv --elem "C 1s" --cycle 2 \
        --window 281.5 291.5 --mode bgsub --id sample1
    python prep_single.py --file YOUR.csv --elem "Cu 2p" --cycle 1 \
        --window 928.5 939.5 --mode bgsub --id sample2

模式：
    bgsub  扣背景（推荐做单谱分峰图：基线落在 0，分峰填充紧贴基线，最像文献里的样子）
    raw    原始 CPS（背景曲线是真实弯曲的，填充下沿跟着背景走）
    shift  每循环减一个常数（背景形状保留、峰不被大背景压扁）
    norm   除以自身最大强度

多个谱就重复调用几次；meta_single.json 会自动合并（同 id 覆盖）。
"""
import argparse
import csv
import io
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from prep import parse, YTITLES  # noqa: E402  复用同一套解析逻辑

OUT = Path(os.environ.get("XPS_OUT", "data"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", required=True, help="CasaXPS 窄扫 CSV")
    ap.add_argument("--elem", required=True, help='元素名，如 "C 1s"')
    ap.add_argument("--cycle", type=int, default=0, help="用第几个循环（0 起）")
    ap.add_argument("--window", nargs=2, type=float, required=True,
                    help="显示窗口 低 高 (eV)，需落在该循环拟合区间内")
    ap.add_argument("--mode", default="bgsub", choices=["bgsub", "raw", "shift", "norm"])
    ap.add_argument("--id", default="single", help="输出标识（图与表的文件名前缀）")
    args = ap.parse_args()

    src = Path(args.file)
    if not src.is_absolute():
        src = Path(os.environ.get("XPS_SRC", "data_raw")) / src
    if not src.exists():
        raise SystemExit(f"找不到源文件：{src}")

    OUT.mkdir(parents=True, exist_ok=True)
    blocks = parse(src, args.elem)
    if not (0 <= args.cycle < len(blocks)):
        raise SystemExit(f"循环号 {args.cycle} 超范围（共 {len(blocks)} 个）")
    b = blocks[args.cycle]
    lo, hi = float(args.window[0]), float(args.window[1])
    if not (b["fit_lo"] - 1e-9 <= lo and hi <= b["fit_hi"] + 1e-9):
        raise SystemExit(f"窗口 {lo}-{hi} 超出该循环拟合区间 {b['fit_lo']:.2f}-{b['fit_hi']:.2f}")

    # 基线处理
    if args.mode == "bgsub":
        base = list(b["bg"])
        scale = 1.0
        print(f"[{args.id}] bgsub：减去整条背景（填充下沿会成为直线，单谱分峰图常用）")
    elif args.mode == "shift":
        idx0 = [i for i, be in enumerate(b["be"]) if lo <= be <= hi]
        c = min(b["bg"][i] for i in idx0)
        base = [c] * len(b["be"])
        scale = 1.0
        print(f"[{args.id}] shift：减去背景最低点 {c:.1f} CPS（背景形状保留）")
    elif args.mode == "norm":
        idx0 = [i for i, be in enumerate(b["be"]) if lo <= be <= hi]
        scale = max(b["raw"][i] for i in idx0)
        base = [0.0] * len(b["be"])
        print(f"[{args.id}] norm：除以 {scale:.1f}")
    else:
        base = [0.0] * len(b["be"])
        scale = 1.0
        print(f"[{args.id}] raw：原始 CPS")

    idx = [i for i, be in enumerate(b["be"]) if lo <= be <= hi]
    cols = [("BE_0", [b["be"][i] for i in idx]),
            ("Bg_0", [(b["bg"][i] - base[i]) / scale for i in idx])]
    for pj in range(4):
        if pj < b["npeak"]:
            cols.append((f"P{pj+1}_0", [(b["peaks"][pj][i] - base[i]) / scale for i in idx]))
        else:
            cols.append((f"P{pj+1}_0", [None] * len(idx)))
    cols.append(("Env_0", [(b["env"][i] - base[i]) / scale for i in idx]))
    cols.append(("Raw_0", [(b["raw"][i] - base[i]) / scale for i in idx]))

    nrow = max(len(v) for _, v in cols)
    path = OUT / f"{args.id}_single_origin.csv"
    with io.open(path, "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh)
        w.writerow([nm for nm, _ in cols])
        for r in range(nrow):
            w.writerow(["" if (r >= len(vals) or vals[r] is None) else f"{vals[r]:.6g}"
                        for _, vals in cols])

    top = max(c[1][k] for c in cols if c[0].startswith(("Raw_", "Env_")) for k in range(nrow)
              if c[1][k] is not None)
    meta_path = OUT / "meta_single.json"
    meta_all = {}
    if meta_path.exists():
        meta_all = json.load(io.open(meta_path, encoding="utf-8"))
    step = 10 ** max(0, len(str(int(top))) - 2)
    meta_all[args.id] = {
        "id": args.id, "elem": args.elem, "csv": str(path),
        "n_cycles": 1, "n_plots": 7, "window": [lo, hi],
        "labels": [b["label"]], "samples": [b["sample"]], "npeak": [b["npeak"]],
        "fit_regions": [[b["fit_lo"], b["fit_hi"]]],
        "global_max": top, "offset": 0.0,
        "ymax": float(int(top / step + 1) * step),
        "mode": args.mode, "yscale": [scale], "ytitle": YTITLES.get(args.mode, "Intensity (a.u.)"),
        "peak_be": None, "peak_rank": [0, 1, 2, 3],
    }
    json.dump(meta_all, io.open(meta_path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print(f"[{args.id}] {b['label']}（{b['npeak']} 个分峰）窗口 {lo}-{hi} eV → {path.name}（{nrow} 行）")
    print(f"meta → {meta_path}")


if __name__ == "__main__":
    main()
