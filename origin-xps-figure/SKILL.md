---
name: origin-xps-figure
description: 用 Origin 为 XPS 窄扫谱做高质量出版级图片（多循环堆叠瀑布图 + 单谱分峰图），包含峰拟合结果着色、分峰填充到背景曲线、真透明度、轴刻度与字体、导出高清图。当需要把 XPS 数据（CasaXPS 导出、BE/强度/分峰/背景/包络等列）画成 Origin 图、或需要避免在 OriginPro 2023 上反复试错时加载本技能。全部命令均在本机 OriginPro 2023 + COM 上实测通过。
---

# Origin XPS 绘图（堆叠图 / 单谱分峰图）

本技能给出一套**已实测通过**的完整流程与属性清单。目标：不做试错，一次生成出版级 XPS 图。

参考成品样式（Nature 系惯例）：细边框、Arial 刻度、按结合能蓝→红顺序渐变的半透明分峰填充、数据点空心圆半透明、浅灰实线背景、框内无文字、600 dpi。

---

## 0. 先读：本机环境

- OriginPro 2023（home），`Origin64.exe`，LabTalk `@V = 10.000154`
- COM 连接：`New-Object -ComObject Origin.ApplicationSI`（连已有实例；**不要**用 `Origin.ApplicationCOMSI`，那个实例不能渲染导出）
- 工具链（可选）：`$env:DSH_HOME\custom-tools\origin\`（`OriginToolkit.ps1` 提供 `Get-OriginApp` / `Execute` / `LTStr` / `LTVar` / `GetWorksheet` / `PutWorksheet` / `Save-OriginProject`）

---

## 1. 一次就对的属性清单（**最重要的一节**）

### 1.1 有效的属性 ✅

| 目的 | LabTalk / COM | 说明 |
|---|---|---|
| X 轴刻度（位置+标签，任意个数与数值） | `layer.x.ticksbydata$ = "290 286 282"` | **正解**。逆序写（高结合能在左）；必须落在坐标范围内 |
| X 刻度朝向 | `layer.x.ticks = 1` | 1=主刻度向内，2=向外，4=次刻度向内…（**位图，不是数目**） |
| X 刻度长度 | `layer.x.ticklength = 8` | |
| 刻度标签字体/字号/粗体 | `layer.x.label.font = font("Arial")` / `.pt = 13` / `.bold = 1` | 真实轴标签属性，本机有效 |
| 隐藏 Y 刻度数字 | `layer.y.showLabels = 0` | |
| 隐藏 Y 刻度线 | `layer.y.tickLength = 0` | |
| 轴框线粗细 | `layer.x.thickness = 3` / `layer.y.thickness = 3` | **用 3**：取 2 时左轴会取整成 5 px 而上/右是 8 px，粗细不一致 |
| 轴标题与坐标框的距离 | `page.ytitle = 10` / `page.xtitle = 6` | 单位 = % 图层尺寸；**只能写不能读**；越小越贴近 |
| 轴标题文字 | `label -f "Arial" -xb \b(\p70(Binding Energy (eV)))` | 标题用 `\p<百分比>` 控字号 |
| 关闭 Y 轴自动标签/刻度后仍要框线 | 只设上面两条，不动 `showAxes` | |
| 分峰填充 | `set r -pf 1` + `set r -pfv 8` + `set r -cf color(r,g,b)` | `-pfv 8` = Fill to Data Plot，基准 = **Next Plot** |
| 填充透明度（百分比） | COM：`$gl.DataPlots($i).SetNumProp('Transparency', 30)` | **唯一可行的百分比入口**，写进图页后导出即带 alpha |
| 悬停信息里的透明度读回 | COM：`$gl.DataPlots($i).GetNumProp('Transparency')` | 属性名大小写不敏感 |
| 导出 PNG | `expG2img igp:=<图页> type:=0 path:="<目录>/" name:="<名>" res:=300 width:=1050` | `width` 像素 = 物理宽度(in) × dpi |
| 保存工程 | `save <路径>;` | 路径**不要加引号** |

### 1.2 无效 / 陷阱 ❌（踩过的坑，别再试）

| 现象 | 原因 | 正确做法 |
|---|---|---|
| `layer.x.inc` 设了、读回也对，但渲染不变 | 本机不参与渲染 | 用 `ticksbydata$` |
| `layer.x.majorTicks = N` 得到小数标签（936.9/934.2/931.5）或标签跑到范围外 | 文档：only "**approximately** that number" | 用 `ticksbydata$` |
| `set %c -paaf 1` / `-paap` / `-paal` / `-paas` 设百分比无效 | 官方 release note：这些只是 **1/0 开关**（"Transparency for Fill Only"） | 用 COM `SetNumProp('Transparency', n)` |
| 文本对象（label）用 `-f "Arial"` 字体不变 | 对文本对象是 no-op，一直用默认字体 | `label.font = font("Arial")`（`.font` 属性有效） |
| 文本对象 `.font.size` / `.pt` 不改字号 | no-op | 在文字里用 `\p<百分比>(...)` 转义；`\p` 参数里**不能跨行**，多行要逐项包 |
| `layer.plot` 当曲线数 | 它不可靠 | `nP=0; doc -e DY { nP=nP+1; };` |
| `newbook name:=X` 名字被忽略/没建出来 | 窗口名上限 13 字符、下划线会被吞 | 建完读 `page.name$` 校验；名字 ≤13 字符 |
| `set 1!5 -s 0` 无效 | 需要 range 绑定 | `range q5 = 1!5; set q5 -s 0;` |
| 轴反向/范围设了又变回去 | 后续属性会触发重算 | **轴范围与反向最后设**，设完读回校验，失败重设 |
| 图例自动更新把每条曲线都列进去 | `legend.auto` 关不掉 | 删图例 `label -r legend;`，用文本对象做色标 |
| 填充变成整块黑/整块实色 | `-pfc` 是网纹图案色；`-pfv 1/3/4` 会填到坐标轴 0 | 用 `-pfv 8` + 让"下一条曲线"是背景 |
| 填充溢出到整层 | 分峰的"下一条曲线"不是背景 | **绘图顺序**必须 `峰,背景,峰,背景,…` |

---

## 2. 数据准备（步骤 1）

输入：CasaXPS 导出的窄扫 CSV（每个循环一个块，列为 `B.E. | raw CPS | peaks×N | Background | Envelope`）。
输出：一张宽表 + `meta.json`：

```
每循环 8 列： BE_i, Bg_i, P1_i, P2_i, P3_i, P4_i, Env_i, Raw_i        (i = 0..n-1)
```

四个要点：

1. **拟合区间检测**：窗口外 CasaXPS 会把分峰/背景/包络列填成与 raw 相同（padding），用"字节相等"识别每个循环真实的拟合区间。
2. **纵向偏移**：`offset = 1.05 × 全局最大`；第 i 层所有列都加 `i × offset`。
3. **ymax**：`(n-1)×offset + maxRaw + 0.25×offset`（顶部收紧）；Y 轴下限 `-0.5×offset`（底部留白，最下层不压轴）。
4. **峰位排序**（配色用）：用**净峰高** `peak_col - bg_col` 取最大处的 BE，求各循环均值排序。
   ⚠️ 不能用 `peak_col` 原始最大值——峰列含背景，背景占优时最大值会跑到窗口端点，排序会错。
   结果写入 `meta.json` 的 `peak_be` / `peak_rank`。
5. **基线模式**（按需选）：
   - `raw`：原始 CPS（适合背景很平的谱，如 C 1s）
   - `shift`：每条谱只减一个常数（该循环背景在窗口内的最低点）。**背景曲线形状完整保留** → 填充下沿是真实弯曲背景；同时峰不被大背景压扁（适合 Cu 2p 这类背景占比大的谱）
   - `bgsub`：减去整条背景 → 基线恒为 0（填充下沿必为直线，一般不建议用于堆叠图）
   - `norm`：除以各自最大强度

---

## 3. 建图（步骤 2）—— 曲线布局是关键

**每个循环画 10 条曲线**，顺序固定：

```
pos:   0     1    2     3    4     5    6     7    8     9
     Peak1  Bg  Peak2  Bg  Peak3  Bg  Peak4  Bg  Env   Raw
```

背景重复 4 次是**故意**的：`-pfv 8`（Fill to Data Plot）的基准是"图层里的下一条曲线"，只有这样每条分峰的填充范围才是"分峰 ↔ 它自己的背景"。

- 若希望**数据点在最底层**：把 `Raw` 移到第一位（`Raw, Peak1, Bg, Peak2, Bg, …`）。
- 曲线总校验：`nPlot = nCycle × 10`，用 `doc -e DY` 数出来核对。
- 每条分峰样式：`-c <颜色> -d 0 -l 1 -wp 0.8`；背景 `-c color(179,179,179) -d 0 -l 1 -wp 0.7`（**浅灰实线**）；包络 `-c color(64,64,64) -wp 1.0`；数据点 `-c 1 -l 0 -k 2 -kf 1 -z 2.5 -kh 0.4`（黑色空心圆）。

---

## 4. 配色（步骤 3）

**按结合能由低到高做蓝→红顺序渐变**（Nature 惯例，避免红绿并列）：

| BE 排名 | 颜色 | RGB |
|---|---|---|
| 最低 | 深蓝 | `color(11,83,148)` |
| ↑ | 浅蓝 | `color(111,168,220)` |
| ↑ | 浅红 | `color(224,102,102)` |
| 最高 | 深红 | `color(153,0,0)` |

按 `meta.peak_rank` 分配（**不是**按 Peak 1–4 的编号顺序），峰线与填充用同一个颜色。

---

## 5. 真透明度（步骤 4）

LabTalk 只能开关，**百分比必须走 COM**：

```powershell
$gl = $app.FindGraphLayer('C1SSTACKED')
for ($i = 0; $i -lt $nCycle; $i++) {
    $b = $i * 10
    foreach ($k in @(0,2,4,6)) { [void]$gl.DataPlots($b + $k).SetNumProp('Transparency', 30) }  # 填充 30%
    [void]$gl.DataPlots($b + 9).SetNumProp('Transparency', 50)                                   # 数据点 50%
}
```

写进图页后 **工程本体就是最终图**，导出 PNG 直接带 alpha，不需要外部合成。
验证方法：导出后取填充内部的像素，应为 `0.7×填充色 + 0.3×白`（30% 透明）。

> 备用方案：若某个 Origin 版本 COM 也不可用，可用 `Layer-Composite.ps1` + `composite_layers.py`
> 做"分层渲染 + 白底抠图 + alpha 合成"（数据点 50%、每个分峰单独一层 30%、线条 100%）。

---

## 6. 轴与排版（步骤 5）

| 项目 | 设置 |
|---|---|
| 页面 | 窄条 1.75 × 10 in；单谱 4.5 × 3.7 in |
| 图层 | 窄条 `left 22 / top 4 / width 64 / height 84`（% 页面） |
| X 刻度 | `ticksbydata$` 给 **3 个整数**（如 290/286/282），Arial 13 pt 粗体，朝内，长度 8 |
| Y 轴 | `showLabels=0` + `tickLength=0`，标题 `Intensity (a.u.)`，`page.ytitle=10` |
| X 标题 | `Binding Energy (eV)`，`page.xtitle=6` |
| 边框 | 四边 `thickness=3`（≈8 px @300 dpi，四边一致） |
| 框内文字 | **不放任何文字**（循环编号、图例都去掉；顺序信息写图注） |
| 输出 | `res:=600 width:=1050`（=1.75 in × 600 dpi） |

字体建议：刻度与标题统一 Arial 粗体（数字用轴标签属性，标题用 `label -xb/-yl` + `\p`）。

---

## 7. 验证清单（导出后必做）

1. `doc -e DY` 曲线数 = nCycle × 10
2. 轴范围与反向：读回 `layer.x.from/to`，确认 from > to
3. 边框：取导出图，沿中线量四边暗像素宽度，应相同（8 px @300 dpi）
4. 刻度：X 标签数 = 期望值；Y 无数字
5. 填充：填充内部像素 = `(1-α)×255 + α×填充色`（α = 不透明度）
6. 文字：图内无任何 text 对象（`label -ra <前缀>` 可清）

---

## 8. 脚本

`assets/` 下是一套可直接改参数运行的脚本，**覆盖堆叠图与单谱分峰图两种场景**：

| 文件 | 作用 |
|---|---|
| `prep.py` | 多循环：解析源 CSV → 宽表 + `meta.json`（拟合区间/偏移/峰位排序/基线模式） |
| `Make-XpsStacked.ps1` | 建图主脚本（布局、样式、填充、透明度、轴、刻度、标题、导出），全参数化 |
| `Build-Stacked.ps1` | 堆叠瀑布图一键驱动（读 `meta.json`，逐个元素出图） |
| `prep_single.py` | 单谱：从源 CSV 取**一个循环** → 单循环宽表 + `meta_single.json` |
| `Build-Single.ps1` | 单谱分峰图一键驱动（4.5 × 3.7 in，输出 `XPS_<元素>_fit.png`） |
| `Layer-Composite.ps1` + `composite_layers.py` | 透明度备用方案（分层渲染 + alpha 合成） |
| `SAMPLE_FORMAT.md` | 输入 CSV 格式与 `meta.json` / `meta_single.json` 字段说明 |

**堆叠图：**

```powershell
$env:PYTHONUTF8 = 1
python .\assets\prep.py
.\assets\Build-Stacked.ps1 -OutDir .\out
```

**单谱分峰图**（同一份源 CSV，挑一个循环）：

```powershell
python .\assets\prep_single.py --file YOUR.csv --elem "C 1s" --cycle 2 `
    --window 281.5 291.5 --mode bgsub --id s1
.\assets\Build-Single.ps1 -OutDir .\out
```

- 单谱图默认 `mode=bgsub`：基线落在 0，分峰填充紧贴基线，最接近文献里的单谱分峰图；
- 若希望填充下沿跟着**真实弯曲背景**走，用 `--mode raw`；
- 多次调用 `prep_single.py` 会合并进同一个 `meta_single.json`（同 id 覆盖），`Build-Single.ps1` 一次出多张。

X 轴刻度默认取"窗口上端、中点、下端"取整后的 3 个值（`Floor(hi)` / 中点 / `Ceiling(lo)`）；
要自定义就在 `Build-*.ps1` 里改 `$tickLabels`，或直接调用 `Make-XpsStacked.ps1 -XTickLabels @(290,286,282)`。

---

## 9. 快速自检问题

- 填充溢出整层？→ 检查绘图顺序是否 `峰,背景,峰,背景…`，以及是否用了 `-pfv 8`
- 刻度数目不对？→ 是否误用了 `layer.x.inc` / `majorTicks`；改用 `ticksbydata$`
- 边框粗细不一？→ `thickness` 是否设成 2；改 3
- 数字字体不是 Arial？→ 是文本对象还是轴标签？轴标签用 `.label.font`，文本对象用 `.font`
- 透明不生效？→ 是否只用了 LabTalk 的 `-paaf`；必须用 COM `SetNumProp`
- 配色顺序错？→ `peak_rank` 是否用"净峰高"算的
