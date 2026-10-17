# 输入格式说明（SAMPLE_FORMAT）

## 1. 源数据：CasaXPS 窄扫导出 CSV

`prep.py` 按 CasaXPS 窄扫导出的块状结构解析。一个文件里可以有多个"循环块"，
每个块长这样（第 1 行是块头，含样品名/循环编号；随后是一行列名；再往下是数据）：

```
SampleName - Cycle 0
B.E.    raw CPS   P1      P2      P3      Background   Envelope
292.00  1200.0    1200.0  1200.0  1200.0  1200.0       1200.0
290.00  1500.0    1210.0  1230.0  1215.0  1205.0       1450.0
...
```

要求：

- 列名里必须能识别出 `B.E.`、`raw`、`Background`、`Envelope`，其余含 `P` 的列视为分峰
- 循环数可以不同（有的循环分峰少，缺的列按空列处理）
- 窗口外的行，CasaXPS 会把分峰/背景/包络写成与 raw 相同（padding）——
  `prep.py` 用"逐字节相等"来自动识别每个循环真实的拟合区间，不需要手工标注

如果你的数据不是 CasaXPS 格式，只要在 `prep.py` 的 `parse()` 里换成自己的解析即可，
它只需返回每个循环一个 dict：`be / raw / bg / env / peaks[] / npeak / fit_lo / fit_hi / label / sample`。

## 2. 中间产物

```
data/
  <id>_origin.csv     每循环 8 列：BE_i, Bg_i, P1_i, P2_i, P3_i, P4_i, Env_i, Raw_i
  meta.json           绘图参数与统计
```

`meta.json` 每个元素一条，字段：

| 字段 | 含义 |
|---|---|
| `id` / `elem` / `csv` | 标识、元素名、宽表路径 |
| `n_cycles` | 循环数 |
| `window` | 显示窗口 `[lo, hi]`（单位 eV） |
| `labels` / `samples` / `npeak` | 各循环的编号、样品名、分峰数 |
| `fit_regions` | 各循环的真实拟合区间 |
| `global_max` / `offset` / `ymax` | 全局最大强度、层间距、Y 轴上限 |
| `mode` | `raw` / `shift` / `bgsub` / `norm` |
| `ytitle` | Y 轴标题（默认 `Intensity (a.u.)`） |
| `peak_be` / `peak_rank` | 各分峰的峰位（净峰高最大处）与按 BE 升序的排名 → 决定蓝→红配色 |

## 3. 配色规则

`peak_rank` 决定颜色（不是 Peak 编号顺序）：

| rank | 颜色 |
|---|---|
| 0（最低 BE） | `color(11,83,148)` 深蓝 |
| 1 | `color(111,168,220)` 浅蓝 |
| 2 | `color(224,102,102)` 浅红 |
| 3（最高 BE） | `color(153,0,0)` 深红 |

## 4. 出图

### 多循环堆叠图

```powershell
$py = "<python>"          # 建议用 DSH 自带 python（含 numpy/pandas/Pillow）
$env:PYTHONUTF8 = 1
& $py .\prep.py           # 生成 data\meta.json
.\Build-Stacked.ps1 -OutDir .\out
```

### 单谱分峰图

```powershell
& $py .\prep_single.py --file YOUR.csv --elem "C 1s" --cycle 2 `
        --window 281.5 291.5 --mode bgsub --id s1     # → data\meta_single.json
.\Build-Single.ps1 -OutDir .\out                       # → out\XPS_C1s_fit.png
```

`--mode`：`bgsub`（扣背景，基线 0，填充紧贴基线）| `raw`（真实弯曲背景）|
`shift`（减背景最低点）| `norm`（除以最大值）。多次调用会合并进同一个
`meta_single.json`（同 `--id` 覆盖）。

导出的 PNG 不带数据表；工程文件（.opju）由 `Make-XpsStacked.ps1 -SaveProjectTo` 决定是否保存。
