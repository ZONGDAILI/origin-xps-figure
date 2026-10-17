"""把 CasaXPS 多循环导出的 CSV 整理成 Origin 用的宽表。

数据模型（已逐位校验）
----------------------
每个循环一块，列序：B.E. | 原始CPS | 分峰×N | Background | Envelope，且

    P_i(列) = Background + 第 i 个分峰
    Envelope = Background + Σ(P_i − Background)

**拟合区间之外，Background/分峰/Envelope 全都被导出程序写成与原始数据逐位相同**
（即填充值），所以：
  * 用「Background 与原始数据逐位相同」精确判定每个循环的拟合区间（逐位比较，不是容差）；
  * 原始数据画整个显示窗口，拟合曲线只画各自拟合区间 ∩ 显示窗口，缺失处留空 → Origin 断线。
这样既不裁掉有效数据，也不会画出假曲线。

其他
----
* 不重采样：每个循环保留自己的结合能轴，用 Origin「每列自带 X」的方式绘图。
* 纵向偏移 = 全局最大强度 × 1.05（用户指定），自下而上 Cycle 0 → 最后一个。
"""
import csv
import io
import json
import math
import os
import sys
from pathlib import Path

# 源数据目录与输出目录：用环境变量或直接改这里
SRC = Path(os.environ.get("XPS_SRC", "data_raw"))
OUT = Path(os.environ.get("XPS_OUT", "data"))

JOBS = [
    # 每个元素一条：file 是 CasaXPS 导出的窄扫 CSV；window 是显示窗口（整数端点更省心）；
    # mode = raw（原始 CPS）| shift（每循环减自身背景最低点，背景形状保留）| bgsub | norm
    {"id": "sample1", "file": "YOUR_SPECTRUM_1.csv", "elem": "C 1s",
     "window": (281.0, 291.0), "mode": "raw"},
    {"id": "sample2", "file": "YOUR_SPECTRUM_2.csv", "elem": "Cu 2p",
     "window": (930.0, 938.0), "mode": "shift"},
]
YTITLES = {"raw": "Intensity (a.u.)", "norm": "Normalized Intensity (a.u.)",
           "bgsub": "Intensity (a.u.)", "shift": "Intensity (a.u.)"}


def fnum(s):
    s = s.strip()
    return float(s) if s else None


def parse(path, elem):
    rows = list(csv.reader(io.open(path, encoding="utf-8-sig")))
    header = rows[6]
    starts = [j for j, v in enumerate(header) if v.strip() == "B.E."] + [len(header)]
    data = [r for r in rows[7:] if any(v.strip() for v in r)]
    out = []
    for k in range(len(starts) - 1):
        s, e = starts[k], starts[k + 1]
        hdr = header[s:e]
        npeak = sum(1 for v in hdr if v.strip() == elem + ":" + elem)
        cur = {"label": hdr[1].split(":")[0], "sample": hdr[1], "npeak": npeak,
               "be": [], "raw": [], "peaks": [[] for _ in range(npeak)],
               "bg": [], "env": [], "valid": [], "fit_lo": None, "fit_hi": None}
        for r in data:
            if not r[s].strip() or not r[s + 1].strip():
                continue
            be = fnum(r[s])
            raw = fnum(r[s + 1])
            bg = fnum(r[s + 2 + npeak])
            env = fnum(r[s + 3 + npeak])
            comp = [fnum(r[s + 2 + j]) for j in range(npeak)]
            cur["be"].append(be)
            cur["raw"].append(raw)
            for j in range(npeak):
                cur["peaks"][j].append(comp[j])
            cur["bg"].append(bg)
            cur["env"].append(env)
            # 逐位相同 → 填充值，不在拟合区间内
            in_fit = r[s + 2 + npeak].strip() != r[s + 1].strip()
            cur["valid"].append(in_fit)
            if in_fit:
                cur["fit_lo"] = be if cur["fit_lo"] is None else min(cur["fit_lo"], be)
                cur["fit_hi"] = be if cur["fit_hi"] is None else max(cur["fit_hi"], be)
        out.append(cur)
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    meta_all = {}
    for job in JOBS:
        mode = job.get("mode", "raw")
        blocks = parse(SRC / job["file"], job["elem"])
        lo, hi = job["window"]

        if mode == "bgsub":
            # 扣背景要求整段都在拟合区间内，否则没有背景可减：取所有循环拟合区间的
            # 交集并向内取整到 1 eV（整数端点 → Origin 按数目设刻度时标签才是整数 eV）
            i_lo = max(b["fit_lo"] for b in blocks)
            i_hi = min(b["fit_hi"] for b in blocks)
            lo = math.ceil(i_lo)
            hi = math.floor(i_hi)
            print(f"[{job['id']}] bgsub：拟合区间交集 {i_lo:.2f}-{i_hi:.2f} → 显示窗口 {lo}-{hi} eV")

        for b in blocks:
            if b["fit_lo"] is None:
                raise SystemExit(f"{job['id']} {b['label']}: 没有拟合区间")
            if not (min(b["be"]) <= lo and hi <= max(b["be"])):
                raise SystemExit(f"{job['id']} {b['label']}: 显示窗口超出原始数据范围")
            if mode == "bgsub" and not (lo >= b["fit_lo"] - 1e-9 and hi <= b["fit_hi"] + 1e-9):
                raise SystemExit(f"{job['id']} {b['label']}: 扣背景窗口超出该循环拟合区间")

        # 每个循环：显示窗口内的行；拟合列只在该循环自己的拟合区间内给值
        rows_per_cycle = []
        for b in blocks:
            idx = [i for i, be in enumerate(b["be"]) if lo <= be <= hi]
            rows_per_cycle.append(idx)

        # 基线处理：
        #   norm  = 除以自身窗口内最大强度
        #   bgsub = 减去各自拟合背景（背景列恒为 0，分峰填充下沿必然是直线）
        #   shift = 只减一个常数（各自背景在窗口内的最低点）：背景曲线形状完整保留，
        #           于是分峰填充的下沿是真实的 background 曲线，同时峰形不被大背景压扁
        scales = [1.0] * len(blocks)
        baselines = [[0.0] * len(b["be"]) for b in blocks]
        if mode == "norm":
            scales = [max(b["raw"][i] for i in idx) for b, idx in zip(blocks, rows_per_cycle)]
        elif mode == "bgsub":
            baselines = [list(b["bg"]) for b in blocks]
        elif mode == "shift":
            consts = [min(b["bg"][i] for i in idx) for b, idx in zip(blocks, rows_per_cycle)]
            baselines = [[c] * len(b["be"]) for c in consts]
            print(f"[{job['id']}] shift：各循环减去自身背景最低点 "
                  f"{min(consts):.0f}–{max(consts):.0f} CPS")

        def val(ci, i, arr):
            return (arr[i] - baselines[ci][i]) / scales[ci]

        global_max = max(max(val(ci, i, b["raw"]) for i in idx)
                         for ci, (b, idx) in enumerate(zip(blocks, rows_per_cycle)))
        global_max = max(global_max, 1e-9)
        offset = 1.05 * global_max
        n = len(blocks)
        ymax = ((n - 1) * offset + global_max) / 0.82
        step = 10 ** math.floor(math.log10(max(ymax / 6, 1e-9)))
        ymax = float(math.ceil(ymax / step) * step)

        cols = []
        for ci, (b, idx) in enumerate(zip(blocks, rows_per_cycle)):
            off = ci * offset
            fit_mask = [b["valid"][i] for i in idx]
            cols.append((f"BE_{ci}", [b["be"][i] for i in idx]))
            cols.append((f"Bg_{ci}", [val(ci, i, b["bg"]) + off if m else None for i, m in zip(idx, fit_mask)]))
            for pj in range(4):
                if pj < b["npeak"]:
                    cols.append((f"P{pj+1}_{ci}",
                                 [val(ci, i, b["peaks"][pj]) + off if m else None for i, m in zip(idx, fit_mask)]))
                else:
                    cols.append((f"P{pj+1}_{ci}", [None] * len(idx)))
            cols.append((f"Env_{ci}", [val(ci, i, b["env"]) + off if m else None for i, m in zip(idx, fit_mask)]))
            cols.append((f"Raw_{ci}", [val(ci, i, b["raw"]) + off for i in idx]))

        nrow = max(len(v) for _, v in cols)
        csv_path = OUT / f"{job['id']}_origin.csv"
        with io.open(csv_path, "w", encoding="utf-8", newline="") as fh:
            w = csv.writer(fh)
            w.writerow([nm for nm, _ in cols])
            for r in range(nrow):
                w.writerow(["" if (r >= len(vals) or vals[r] is None) else f"{vals[r]:.6g}"
                            for _, vals in cols])

        # 各分峰的峰位：用「净峰高 = peak 列 - background 列」的最大值处，
        # 不能用峰列原始最大值（峰列含背景，背景占主导时最大值会跑到窗口端点）
        peak_be = []
        for pj in range(4):
            bs = []
            for b, idx in zip(blocks, rows_per_cycle):
                if pj >= b["npeak"]:
                    continue
                col = b["peaks"][pj]
                vals = [(col[i] - b["bg"][i], b["be"][i]) for i in idx if b["valid"][i]]
                if vals:
                    bs.append(max(vals)[1])
            peak_be.append(round(sum(bs) / len(bs), 3) if bs else None)
        order = sorted([p for p in range(4) if peak_be[p] is not None], key=lambda p: peak_be[p])
        rank = [-1] * 4
        for r, p in enumerate(order):
            rank[p] = r
        print(f"   峰位（BE 升序排序）: " +
              ", ".join(f"Peak{p+1}={peak_be[p]:.2f}" for p in order))

        meta = {
            "id": job["id"], "elem": job["elem"], "csv": str(csv_path),
            "n_cycles": n, "n_plots": n * 7, "window": [lo, hi],
            "labels": [b["label"] for b in blocks],
            "samples": [b["sample"] for b in blocks],
            "npeak": [b["npeak"] for b in blocks],
            "fit_regions": [[b["fit_lo"], b["fit_hi"]] for b in blocks],
            "global_max": global_max, "offset": offset, "ymax": ymax,
            "mode": mode, "yscale": scales, "ytitle": YTITLES.get(mode, "Intensity (a.u.)"),
            "peak_be": peak_be, "peak_rank": rank,
        }
        meta_all[job["id"]] = meta
        print(f"[{job['id']}] {job['elem']}: {n} cycles | 模式 {mode} | 显示窗口 {lo}-{hi} eV | "
              f"全局最大 {global_max:.6g} | 偏移 {offset:.6g} | Y 上限 {ymax:.6g}")
        for b, s in zip(blocks, scales):
            extra = f"  缩放 {s:.0f} CPS" if mode == "norm" else ""
            print(f"    {b['label']:9s} npeak={b['npeak']}  拟合区间 {b['fit_lo']:.2f} - {b['fit_hi']:.2f}" + extra)

    with io.open(OUT / "meta.json", "w", encoding="utf-8") as fh:
        json.dump(meta_all, fh, ensure_ascii=False, indent=2)
    print("meta ->", OUT / "meta.json")


if __name__ == "__main__":
    main()
