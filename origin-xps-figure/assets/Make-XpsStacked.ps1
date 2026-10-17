# XPS 多循环堆叠对比图（Origin 自动化，本机 OriginPro 2023 实测）
#
# 每个循环 7 条曲线：
#   Background 灰色虚线 / Peak 1..4 彩色实线 / Sum 红色实线 / Raw 黑色空心圆
# 纵向固定偏移 = 全局最大强度 × 1.05，自下而上 Cycle 0 → 最后一个；X 轴反向。
#
# 本机实测要点（踩过的坑）：
#   * set 的线宽单位：-w 是 pt×500，按 pt 设宽度必须用 -wp
#   * layer.plot 不是可靠的曲线条数，用 doc -e DY 计数
#   * plotxy 追加到已有图层必须写窗口名：iy:=[Book]Sheet!(X,Y) ogl:=1
#   * page.width/page.height 单位是 1/1000 英寸（默认页 6432×4923 => 6.43×4.92 in）
#   * 刻度字号 = layer.x.label.pt；轴标题字号 = xb.font.size / yl.font.size
#   * label 定位：-p x y 是按「图层框左上角的百分比」，-a 是轴坐标
#   * PowerShell 方法参数里的 -f 会抢逗号，必须整体加括号
#   * PowerShell 变量名大小写不敏感：[string]$Meta 会把解析出的对象强制转字符串

param(
    [Parameter(Mandatory)][string]$Meta,
    [Parameter(Mandatory)][string]$Id,
    [Parameter(Mandatory)][string]$OutDir,
    [int]$PageW = 7000,             # 1/1000 英寸 => 7 英寸
    [int]$PageH = 10000,            # => 10 英寸
    [int]$ExportWidthPx = 2100,
    [string]$SaveProjectTo = '',
    [string]$BookName = '',
    # 版式参数（页面单位是 1/1000 英寸；图层位置/尺寸是页面百分比）
    [int]$LayerLeft = 17,
    [int]$LayerTop = 6,
    [int]$LayerWidth = 60,
    [int]$LayerHeight = 87,
    [int]$TitlePt = 22,
    [int]$TickPt = 15,
    [int]$AnnotPt = 14,
    [int]$KeyPt = 14,
    # 本机实测：文本框的 .font.size / .pt 都是**无效属性**（读回正常但渲染不响应），
    # 只有刻度标签的 layer.x.label.pt 有效。文本对象（轴标题/色标/循环标注）改字号
    # 必须用转义序列 \p<百分比>(...)，TextScale 就是那个百分比（100 = 不变）。
    [int]$TextScale = 100,
    [string]$LabelPrefix = 'Cycle ',      # 循环标注前缀；窄图可传 'C' 之类短前缀
    [double]$LabelXPct = 1.2,              # 循环标注的横向位置（图层宽度百分比，左对齐起点）
    [switch]$LabelRight,                   # 循环标注放到右端（等价于给一个靠右的 LabelXPct）
    [switch]$KeySingleColumn,              # 色标排成单列（窄图用）
    # 参考图风格（Times New Roman 粗体 + 粗边框 + 大空心圆 + 细线）
    [string]$FontName = 'Times New Roman',
    [string]$TickFont = 'Arial',          # 刻度数字字体（轴标题/色标仍用 FontName）
    [int]$AxisThickness = 3,               # 轴框线宽（layer.x.thickness）
    [int]$TickLen = 8,                      # 刻度线长（layer.x.tickLength）
    [double]$SymSize = 4,                  # 空心圆点大小（set -z）
    [double]$SymEdge = 0.5,                # 圆点描边粗细（set -kh）
    [double]$PeakLineW = 1.4,              # 分峰线宽（set -wp，单位 pt）
    [double]$SumLineW = 1.7,               # 包络线宽
    [double]$BgLineW = 1.1,                # 背景线宽
    # 分峰填充（参考图风格）：-pfv 7 = Fill to Base，-lfp 指向该循环自己的背景列，
    # -cf 给浅色（本机 -paap/-paal/-paas 透明度选项只当开关用，所以用浅色代替半透明）
    [switch]$FillComponents,
    # Nature 式顺序配色：分峰按"结合能由低到高"取色，默认蓝→红四段渐变
    [string[]]$PeakColors = @('color(11,83,148)', 'color(111,168,220)',
                              'color(224,102,102)', 'color(153,0,0)'),
    [string]$SumColor = 'color(64,64,64)',      # 包络线：深灰
    [string]$BgColor = 'color(179,179,179)',    # 背景：浅灰实线
    [int]$BgDash = 0,                           # 0 = 实线
    # 真透明度（写进工程本体，不靠外部合成）：
    # LabTalk 的 set 选项 -paaf/-paap 只是开关，数值要通过 COM 的
    # DataPlot.SetNumProp('Transparency', 百分比) 设置（实测有效，导出即带 alpha）。
    [switch]$ApplyTransparency,
    [double]$FillTransparency = 30,             # 分峰填充透明度（%）
    [double]$RawTransparency = 50,              # 实测数据点透明度（%）
    [switch]$NoCycleLabels,                # 单谱图不需要循环标注
    [switch]$NoKey,                        # 单谱图可不要色标（参考图就没有）
    # 叠层图版式（参考 CSDN《Origin 叠层图》与期刊常规）：
    #   底部留白、顶部收紧、隐藏无物理意义的 Y 数值、X 刻度疏一点、图例移到图下方
    [double]$BottomGapFrac = 0.35,         # 最下层谱线基线离 X 轴的距离（× 层间距）
    [double]$TopGapFrac = 0.30,            # 最上层峰顶与顶部框线的距离（× 层间距）
    [switch]$HideYLabels,                  # 隐藏 Y 刻度数值（layer.y.showLabels = 0）
    [switch]$KeyBelow,                     # 色标放到图下方（页面坐标，横向排）
    [int]$KeyColumns = 0,                  # 图下方色标的列数（0 = 用原有的分行规则）
    [double]$KeyBelowYFrac = 0.93,         # 图下方色标的纵向位置（页面高度比例，从顶部算）
    [double]$LabelScale = 0,               # 循环标注缩放（0 = 与 TextScale 相同）
    [double]$TitleScale = 0,               # 轴标题缩放（0 = 与 TextScale 相同）
    [int]$XInc = 2,                        # X 主刻度间隔（eV）——本机 layer.x.inc 不生效，仅作记录
    [int]$XTickCount = 0,                  # X 主刻度数目（>0 时用"按数目"设刻度，端点取整即得整齐刻度）
    [double[]]$XTickLabels = @(),          # 手动指定的 X 轴标签（如 @(290,285,280)）：真实刻度
    [double]$XTickLabelPt = 0,             # 刻度标签字号（0 = 用 TickPt 换算）
    # 轴标题与坐标框的距离（% 图层尺寸）——官方文档：page.ytitle / page.xtitle
    [double]$TitleGapY = 10,               # Y 标题离左边框（默认约 25，越小越近）
    [double]$TitleGapX = 6,                # X 标题离下边框（默认约 12，越小越近）
    [switch]$NoMinorTicks,                 # 去掉次要刻度
    [string[]]$FillTints = @('color(214,232,255)', 'color(214,245,220)',
                             'color(240,220,245)', 'color(215,240,245)'),
    [switch]$KeepWorkbook
)

$ErrorActionPreference = 'Stop'
. "$env:DSH_HOME\custom-tools\origin\OriginToolkit.ps1"
$app = Get-OriginApp -Visible:$false

$info = (Get-Content -LiteralPath $Meta -Raw -Encoding UTF8 | ConvertFrom-Json).$Id
if (-not $info) { throw "meta.json 里没有 $Id" }

$labels = @($info.labels)
$nCycle = [int]$info.n_cycles
$win = @($info.window)
$xLow = [double]$win[0]        # 窗口下限（低结合能）
$xHigh = [double]$win[1]       # 窗口上限（高结合能）
$offset = [double]$info.offset
$ymax = [double]$info.ymax
$maxRaw = [double]$info.global_max
$nPlot = [int]$info.n_plots
$nColPerCycle = 8
# 每个循环画 10 条曲线：峰1,背景,峰2,背景,峰3,背景,峰4,背景,包络,实测
# 背景重复出现是**故意**的：-pfv 8（Fill to Data Plot，基准=Next Plot）会把填充做在
# "当前曲线"与"下一条曲线"之间，所以每条分峰后面紧跟一条背景曲线，填充范围才正确。
$plotY = @(3, 2, 4, 2, 5, 2, 6, 2, 7, 8)
$nPlotPerCycle = $plotY.Count
# 绘图样式按上面 10 个位置给（位置 1/3/5/7 都是背景）
$posStyle = @('peak1', 'bg', 'peak2', 'bg', 'peak3', 'bg', 'peak4', 'bg', 'env', 'raw')
$posTint = @(0, -1, 1, -1, 2, -1, 3, -1, -1, -1)
$elem = $info.elem

Write-Host ("[{0}] {1}: {2} cycles / {3} plots / window {4}-{5} eV" -f $Id, $elem, $nCycle, $nPlot, $xHigh, $xLow)

# ---------------------------------------------------------------- 读数据
$lines = @(Get-Content -LiteralPath $info.csv -Encoding UTF8 | Where-Object { $_.Trim().Length -gt 0 })
$names = $lines[0].Split(',')
$nCols = $names.Count
$rowsRaw = @()
foreach ($ln in $lines[1..($lines.Count - 1)]) { $rowsRaw += , ($ln.Split(',')) }
$nRow = $rowsRaw.Count
Write-Host ("  数据表 {0} 行 x {1} 列" -f $nRow, $nCols)

$grid = New-Object 'object[,]' $nRow, $nCols
for ($r = 0; $r -lt $nRow; $r++) {
    $f = $rowsRaw[$r]
    for ($c = 0; $c -lt $nCols; $c++) {
        $v = if ($c -lt $f.Count) { $f[$c] } else { '' }
        $grid[$r, $c] = if ($v -eq '') { [double]::NaN } else { [double]$v }
    }
}

# ---------------------------------------------------------------- 新建工作簿（必须确认真的建出来了）
# 窗口短名上限 13 字符，所以从 id 里取短前缀（c1s_single -> C1S）
$shortId = (($Id -replace '_single$', '') -replace '[^A-Za-z0-9]', '').ToUpper()
if ($shortId.Length -gt 5) { $shortId = $shortId.Substring(0, 5) }
$bk = ''; $sh = ''
for ($try = 0; $try -lt 6; $try++) {
    $nm = ('X' + $shortId + (Get-Random -Minimum 1000 -Maximum 9999))
    [void]$app.Execute(('newbook name:="{0}" sheet:=1 option:=1;' -f $nm))
    $b = $app.LTStr('page.name$'); $s = $app.LTStr('wks.name$')
    if ($b -eq $nm -and $s) { $bk = $b; $sh = $s; break }
    Start-Sleep -Milliseconds 200
}
if (-not $bk) { throw 'newbook 连续 6 次没有建出新工作簿' }
Write-Host ("  工作簿 [{0}]{1}" -f $bk, $sh)

# 改名必须趁「还没有图引用它」的时候做：作图之后再改，Origin 会弹
# 「窗口关闭选项」对话框并把改名取消（实测踩过 3 次）
if ($BookName -and $BookName -ne $bk) {
    [void]$app.Execute(('win -r {0} {1};' -f $bk, $BookName))
    Start-Sleep -Milliseconds 300
    if ($app.Execute(('win -a {0};' -f $BookName))) { $bk = $BookName }
    Write-Host ("  工作簿改名为 [{0}]（成功={1}）" -f $bk, ($bk -eq $BookName))
}

[void]$app.Execute(('win -a [{0}]{1};' -f $bk, $sh))
[void]$app.Execute(('wks.ncols = {0};' -f $nCols))
if (-not $app.PutWorksheet(('[{0}]{1}' -f $bk, $sh), $grid)) { throw 'PutWorksheet 失败' }
$rename = ''
for ($c = 0; $c -lt $nCols; $c++) {
    $cn = $names[$c]
    $rename += ('col({0})[L]$ = "{1}";' -f ($c + 1), $cn)
}
[void]$app.Execute($rename)

# ---------------------------------------------------------------- 建图
$cmds = ''
for ($i = 0; $i -lt $nCycle; $i++) {
    $xc = $i * $nColPerCycle + 1
    for ($k = 0; $k -lt $nPlotPerCycle; $k++) {
        $yc = $i * $nColPerCycle + $plotY[$k]
        $ogl = if (($i -eq 0) -and ($k -eq 0)) { 'ogl:=<new template:=Line>' } else { 'ogl:=1' }
        $cmds += ('plotxy iy:=[{0}]{1}!({2},{3}) plot:=200 {4};' -f $bk, $sh, $xc, $yc, $ogl) + "`n"
    }
}
[void]$app.Execute($cmds)
$g = $app.LTStr('page.name$')
Write-Host ("  图页 {0}" -f $g)

[void]$app.Execute('nP = 0; doc -e DY { nP = nP + 1; };')
$tv = 'tv' + (Get-Random); [void]$app.Execute(('string {0}$ = $(nP);' -f $tv))
$nGot = [int]$app.LTStr($tv + '$'); [void]$app.Execute(('del -v {0}$;' -f $tv))
$nPlot = $nCycle * $nPlotPerCycle
if ($nGot -ne $nPlot) { throw "曲线数不符：得到 $nGot，期望 $nPlot（不继续设样式，避免错位）" }
Write-Host ("  曲线数校验通过：{0}" -f $nGot)

# ---------------------------------------------------------------- 样式
# 每个循环 10 个位置（posStyle）：peak1,bg,peak2,bg,peak3,bg,peak4,bg,env,raw
# 分峰颜色按"结合能由低到高 = 蓝→红"的渐变分配（peak_rank 由 prep.py 算出）
$rank = @($info.peak_rank)
$slotColor = @()
for ($k = 0; $k -lt 4; $k++) {
    $r = if ($rank.Count -gt $k -and $rank[$k] -ge 0) { $rank[$k] } else { $k }
    $slotColor += $PeakColors[$r % $PeakColors.Count]
}
Write-Host ("  分峰配色（BE 由低到高 → 蓝到红）：P1={0} P2={1} P3={2} P4={3}" -f
            $slotColor[0], $slotColor[1], $slotColor[2], $slotColor[3])

$styleByRole = @{
    'bg'    = ('range r{{0}} = 1!{{0}}; set r{{0}} -c {0}; set r{{0}} -d {1}; set r{{0}} -l 1; set r{{0}} -wp {{1}};' -f $BgColor, $BgDash)
    'env'   = ('range r{{0}} = 1!{{0}}; set r{{0}} -c {0}; set r{{0}} -d 0; set r{{0}} -l 1; set r{{0}} -wp {{1}};' -f $SumColor)
    'raw'   = 'range r{0} = 1!{0}; set r{0} -c 1;  set r{0} -l 0; set r{0} -k 2; set r{0} -kf 1; set r{0} -z {2}; set r{0} -kh {3};'
}
$widthByRole = @{ 'bg' = $BgLineW; 'peak' = $PeakLineW; 'env' = $SumLineW; 'raw' = 0 }
for ($i = 0; $i -lt $nCycle; $i++) {
    $chunk = ''
    for ($k = 0; $k -lt $nPlotPerCycle; $k++) {
        $p = $i * $nPlotPerCycle + $k + 1
        $role = $posStyle[$k]
        if ($role -like 'peak*') {
            $si = [int]$role.Substring(4) - 1
            $cmd = ('range r{{0}} = 1!{{0}}; set r{{0}} -c {0}; set r{{0}} -d 0; set r{{0}} -l 1; set r{{0}} -wp {{1}};' -f $slotColor[$si])
            $chunk += ($cmd -f $p, $PeakLineW) + "`n"
        }
        else {
            $chunk += ($styleByRole[$role] -f $p, $widthByRole[$role], $SymSize, $SymEdge) + "`n"
        }
    }
    if ($FillComponents) {
        for ($k = 0; $k -lt $nPlotPerCycle; $k++) {
            if ($posTint[$k] -lt 0) { continue }        # 背景/包络/实测点不填充
            $p = $i * $nPlotPerCycle + $k + 1
            $si = [int]($posStyle[$k].Substring(4)) - 1
            $tint = $slotColor[$si]
            # -pfv 8 = Fill to Data Plot（One Color），基准 = Next Plot；
            # 因为每条分峰后面紧跟一条背景曲线，填充范围就是"分峰↔背景"之间
            $chunk += ('range rp{0} = 1!{0}; set rp{0} -pf 1; set rp{0} -pfv 8; set rp{0} -cf {1}; set rp{0} -paaf 1;' -f
                       $p, $tint) + "`n"
        }
    }
    [void]$app.Execute($chunk)
}

# ---------------------------------------------------------------- 真透明度（COM 对象模型）
# 关键：LabTalk 的 -paaf/-paap 只能开关，透明度数值在 COM 的 DataPlot 对象上
# （SetNumProp('Transparency', n)）。写进图页后，工程本体与导出图都带 alpha，
# 不再需要"分层渲染 + 合成"。
if ($ApplyTransparency) {
    $gl = $app.FindGraphLayer($g)
    if (-not $gl) { throw "找不到图页 $g 的图层对象" }
    $nSet = 0
    for ($i = 0; $i -lt $nCycle; $i++) {
        $b = $i * $nPlotPerCycle
        foreach ($k in @(0, 2, 4, 6)) {
            [void]$gl.DataPlots($b + $k).SetNumProp('Transparency', $FillTransparency)
            $nSet++
        }
        [void]$gl.DataPlots($b + 9).SetNumProp('Transparency', $RawTransparency)
        $nSet++
    }
    Write-Host ("  已写入透明度：分峰填充 {0}%（{1} 条）、实测数据点 {2}%（{3} 条）" -f
                $FillTransparency, ($nCycle * 4), $RawTransparency, $nCycle)
}

# ---------------------------------------------------------------- 轴 / 页面 / 字号
# 轴标题用 \p<百分比>(...) 控制字号、\b(...) 加粗；字体用 label 的 -f 选项
$ytitle = if ($info.ytitle) { $info.ytitle } else { 'Intensity (CPS)' }
$titleScale = if ($TitleScale -gt 0) { $TitleScale } else { $TextScale }
[void]$app.Execute(('label -f "{0}" -xb \b(\p{1}(Binding Energy (eV)))' -f $FontName, $titleScale))
[void]$app.Execute(('label -f "{0}" -yl \b(\p{1}({2}))' -f $FontName, $titleScale, $ytitle))
[void]$app.Execute('layer -a;')
[void]$app.Execute(('page.width = {0}; page.height = {1};' -f $PageW, $PageH))
[void]$app.Execute(('layer.left = {0}; layer.top = {1}; layer.width = {2}; layer.height = {3};' -f
                   $LayerLeft, $LayerTop, $LayerWidth, $LayerHeight))
# 刻度标签：字号用 .pt，字体用 font() 索引，加粗用 .bold
[void]$app.Execute(('layer.x.label.pt = {0}; layer.y.label.pt = {0};' -f $TickPt))
# 刻度数字用 Arial（轴标题仍由 label -f 指定为 FontName）
[void]$app.Execute(('int tf = font("{0}"); layer.x.label.font = tf; layer.y.label.font = tf;' -f $TickFont))
[void]$app.Execute('layer.x.label.bold = 1; layer.y.label.bold = 1;')
# ---------------------------------------------------------------- Y 轴范围（底部留白 + 顶部收紧）
# 叠层图常规：最下层谱线要离 X 轴有距离、最上层峰顶离顶部框线只要一点余量，
# 而不是把大量空白堆在顶部（图例已移到图下方）。两个留白都以"层间距"为单位。
$yFrom = -$BottomGapFrac * $offset
$ymax = ($nCycle - 1) * $offset + $maxRaw + $TopGapFrac * $offset
Write-Host ("  Y 轴范围 {0:0} .. {1:0}" -f $yFrom, $ymax)

# 轴框线宽 + 刻度线长 + 刻度数值显示
[void]$app.Execute(('layer.x.thickness = {0}; layer.y.thickness = {0};' -f $AxisThickness))
[void]$app.Execute(('layer.x.tickLength = {0}; layer.y.tickLength = {0};' -f $TickLen))
if ($HideYLabels) {
    # 叠层图的 Y 数值是"偏移后的数"，没有物理意义：连同刻度线一起去掉（轴标题保留）
    [void]$app.Execute('layer.y.showLabels = 0; layer.y.tickLength = 0;')
}
if ($NoMinorTicks) { [void]$app.Execute('layer.x.minorTicks = 0; layer.y.minorTicks = 0;') }
# Y 主刻度间隔取「约 5 格」的 1/2/5×10ⁿ 整数
$rawInc = $ymax / 5.0
$mag = [math]::Pow(10, [math]::Floor([math]::Log10([math]::Max($rawInc, 1e-9))))
$yInc = [math]::Round($rawInc / $mag) * $mag
Write-Host ("  Y 轴 {0} .. {1}（层间距 {2}，底部留白 {3}×层距），Y 刻度间隔 {4}，X 刻度间隔 {5} eV" -f
            $yFrom, $ymax, $offset, $BottomGapFrac, $yInc, $XInc)

# ---------------------------------------------------------------- 图例/色标
# 坑：Origin 的图例对象默认「自动更新」（legend.auto=1），会把**每一条曲线**都列进去；
# 即使关掉 auto 再改 legend.text$，重绘时仍会把未引用的曲线追加回来（84 条图例把整图盖住）。
# 所以这里直接删掉图例，用普通文本对象 + \cN(...) 颜色转义做色标（颜色与曲线一致）。
[void]$app.Execute('label -r legend;')
$mode = if ($info.mode) { $info.mode } else { 'raw' }
# 色标条目：(文字, 颜色)。颜色用 RGB 精确给出，所以每个条目单独成一个文本对象
# （\cN 转义只能表达调色板索引，表达不了任意 RGB）
$items = @(
    @{ t = 'Raw data'; c = 'color(0,0,0)' },
    @{ t = 'Sum'; c = $SumColor },
    @{ t = 'Peak 1'; c = $slotColor[0] },
    @{ t = 'Peak 2'; c = $slotColor[1] },
    @{ t = 'Peak 3'; c = $slotColor[2] },
    @{ t = 'Peak 4'; c = $slotColor[3] }
)
if ($mode -ne 'bgsub') { $items += @{ t = 'Background'; c = $BgColor } }

if (-not $NoKey) {
    $kScale = if ($LabelScale -gt 0) { [math]::Max($LabelScale, 60) } else { $TextScale }
    $cols = if ($KeyColumns -gt 0) { $KeyColumns } else { 1 }
    $rows = [int][math]::Ceiling($items.Count / [double]$cols)
    if ($KeyBelow) {
        # 图下方网格：每个条目一个 label（-d = 页面坐标，1/1000 英寸），颜色逐个精确设置
        $x0 = 0.05 * $PageW
        $dx = 0.45 * $PageW
        $y0 = $KeyBelowYFrac * $PageH
        $dy = 150
        $cmds = ''
        for ($r = 0; $r -lt $rows; $r++) {
            for ($c = 0; $c -lt $cols; $c++) {
                $idx = $r * $cols + $c
                if ($idx -ge $items.Count) { continue }
                $nm = 'KEY' + $idx
                $x = [int]($x0 + $c * $dx)
                $y = [int]($y0 + $r * $dy)
                $cmds += ('label -f "{0}" -d {1} {2} -sa -j 0 -n {3} \b(\p{4}({5}));' -f
                          $FontName, $x, $y, $nm, $kScale, $items[$idx].t) + "`n"
                $cmds += ('{0}.color = {1};' -f $nm, $items[$idx].c) + "`n"
            }
        }
        [void]$app.Execute($cmds)
        Write-Host ("  色标：图下方 {0}×{1} 网格，{2} 项，逐项设 RGB 颜色" -f $cols, $rows, $items.Count)
    }
    else {
        # 图内左上角：单列
        $cmds = ''
        $dy = 0.030
        for ($idx = 0; $idx -lt $items.Count; $idx++) {
            $nm = 'KEY' + $idx
            $cmds += ('label -f "{0}" -p 2 {1} -sa -j 0 -n {2} \b(\p{3}({4}));' -f
                      $FontName, (1.5 + $idx * $dy * 100 / 100 * 100 / 100), $nm, $kScale, $items[$idx].t) + "`n"
            $cmds += ('{0}.color = {1};' -f $nm, $items[$idx].c) + "`n"
        }
        [void]$app.Execute($cmds)
        Write-Host ("  色标：图内单列，{0} 项" -f $items.Count)
    }
}
else {
    Write-Host '  按参数要求不画色标'
}

# ---------------------------------------------------------------- 每条谱线左侧的循环标注
# 注意：label -p 的 y 是「从图层框顶部算的百分比」，所以要用 100 - 数据位置
$lbl = ''
if (-not $NoCycleLabels) {
    for ($i = 0; $i -lt $nCycle; $i++) {
        $nm = 'CL' + $i
        # 标签前缀可换（窄图用短前缀，否则 "Cycle 12" 会占掉大半绘图宽度）
        $lbm = $LabelPrefix + ($labels[$i] -replace '^Cycle\s*', '')
        $ypct = 100.0 - 100.0 * ($i * $offset + 0.30 * $maxRaw) / $ymax
        # 文字大小靠 \p 转义（.font.size 无效）；窄图把标注放右侧平缓段，避免压住分峰
        $xPct = $LabelXPct
        if ($LabelRight) { $xPct = 78.0 }
        $just = 0
        $labScale = if ($LabelScale -gt 0) { $LabelScale } else { $TextScale }
        $lbl += ('label -f "{0}" -p {1} {2} -j {3} -n {4} \b(\p{5}({6}));' -f
                 $FontName, $xPct, [math]::Round($ypct, 3), $just, $nm, $labScale, $lbm) + "`n"
        $lbl += ('{0}.color = color(black);' -f $nm) + "`n"
    }
}
else {
    $lbl = 'label -ra CL;'
}
[void]$app.Execute($lbl)

# ---------------------------------------------------------------- 轴范围最后设（前面的属性会触发重算）
[void]$app.Execute('layer.x.reverse = 0;')
[void]$app.Execute(('layer.x.from = {0}; layer.x.to = {1};' -f $xHigh, $xLow))   # 高结合能在左
[void]$app.Execute(('layer.y.from = {0}; layer.y.to = {1};' -f $yFrom, $ymax))
# 主刻度间隔必须放在轴范围之后设，否则会被重算掉（实测：放前面设的 inc 不生效）
[void]$app.Execute(('layer.x.inc = {0}; layer.y.inc = {1};' -f $XInc, $yInc))
if ($XTickCount -gt 0) {
    # 本机 layer.x.inc 设了不渲染，只能按"数目"设；端点取整时标签才会落在整数 eV 上
    [void]$app.Execute(('layer.x.majorTicks = {0};' -f $XTickCount))
}
Start-Sleep -Milliseconds 400
$chkFrom = [double]$app.LTVar('layer.x.from')
$chkTo = [double]$app.LTVar('layer.x.to')
if ($chkFrom -lt $chkTo) {
    Write-Host ("  设 inc 后轴被重算（{0} -> {1}），重新设反向" -f $chkFrom, $chkTo)
    [void]$app.Execute(('layer.x.from = {0}; layer.x.to = {1};' -f $xHigh, $xLow))
    Start-Sleep -Milliseconds 300
    $chkFrom = [double]$app.LTVar('layer.x.from'); $chkTo = [double]$app.LTVar('layer.x.to')
    if ($chkFrom -lt $chkTo) { throw "X 轴没有反向成功：$chkFrom -> $chkTo" }
}
Write-Host ("  X 轴：{0} -> {1}（已反向），x.inc={2} y.inc={3}" -f
            $chkFrom, $chkTo, $app.LTVar('layer.x.inc'), $app.LTVar('layer.y.inc'))

# ---------------------------------------------------------------- X 轴刻度（真实轴设置）
# 正确做法（官方文档 Layer.Axis 属性）：
#   layer.axis.ticksbydata$ = "290 286 282"   → 直接指定主刻度的"位置 + 标签"
#   layer.axis.ticks        = 1               → 刻度朝向位图（1 = 主刻度向内）
# 说明：layer.axis.majorTicks 只能给"approximately"该数目（会落到 936.9/934.2 这种小数），
#       layer.axis.ticks 也不是数目而是朝向，之前混用才导致刻度怎么调都不对。
if ($XTickLabels.Count -gt 0) {
    # 逆序（高结合能在左）写成分隔空格的值列表
    $vals = ($XTickLabels | Sort-Object -Descending | ForEach-Object { '{0:0.###}' -f $_ }) -join ' '
    [void]$app.Execute(('layer.x.ticksbydata$ = "{0}";' -f $vals))
    [void]$app.Execute('layer.x.ticks = 1;')            # 主刻度向内
    [void]$app.Execute(('layer.x.ticklength = {0};' -f $TickLen))
    [void]$app.Execute('layer.x.minorTicks = 0;')
    [void]$app.Execute('layer.x.showLabels = 1;')
    [void]$app.Execute('layer.x.labelType = 1;')
    # 刻度标签字体/字号/加粗（真实轴标签属性，本机可用）
    [void]$app.Execute(('layer.x.label.font = font("{0}");' -f $TickFont))
    if ($XTickLabelPt -gt 0) { [void]$app.Execute(('layer.x.label.pt = {0};' -f $XTickLabelPt)) }
    [void]$app.Execute('layer.x.label.bold = 1;')
    Write-Host ("  X 轴刻度：ticksbydata = {0}（真实刻度+标签，字体 {1}）" -f $vals, $TickFont)
}
# 轴标题与坐标框的距离（官方属性：page.ytitle / page.xtitle，单位 % 图层尺寸）
if ($TitleGapY -gt 0) { [void]$app.Execute(('page.ytitle = {0};' -f $TitleGapY)) }
if ($TitleGapX -gt 0) { [void]$app.Execute(('page.xtitle = {0};' -f $TitleGapX)) }
Write-Host ("  轴标题距离：Y {0}%、X {1}%（% 图层尺寸）" -f $TitleGapY, $TitleGapX)
[void]$app.Execute('doc -uw;')
Start-Sleep -Milliseconds 1200

# ---------------------------------------------------------------- 导出
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
$dirFwd = (Resolve-Path $OutDir).Path.Replace('\', '/') + '/'
$elName = $elem.Replace(' ', '')
$img = 'XPS_{0}_stacked' -f $elName
[void]$app.Execute(('expG2img igp:={0} type:=0 path:="{1}" name:="{2}" res:=300 width:={3};' -f
                   $g, $dirFwd, $img, $ExportWidthPx))
$png = Join-Path (Resolve-Path $OutDir).Path ($img + '.png')
$bytes = (Get-Item $png -ErrorAction SilentlyContinue).Length
Write-Host ("  导出 {0} ({1} bytes)" -f $png, $bytes)
if (-not $bytes) { throw '导出失败' }

if ($SaveProjectTo) {
    Save-OriginProject -Path $SaveProjectTo | Out-Null
    Write-Host ("  工程已保存 {0} ({1} bytes)" -f $SaveProjectTo, (Get-Item $SaveProjectTo).Length)
}

[pscustomobject]@{
    Id = $Id; Graph = $g; Book = $bk; Sheet = $sh; Plots = $nGot; Png = $png
    XFrom = $app.LTVar('layer.x.from'); XTo = $app.LTVar('layer.x.to')
    YFrom = $app.LTVar('layer.y.from'); YTo = $app.LTVar('layer.y.to')
    PageW = $app.LTVar('page.width'); PageH = $app.LTVar('page.height')
} | ConvertTo-Json -Compress


