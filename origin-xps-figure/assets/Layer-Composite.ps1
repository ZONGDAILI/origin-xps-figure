# 把一个已建好的堆叠图拆成三层渲染，再合成出"数据点置底 50%、分峰填充 30%"的成品
# 曲线布局（每循环 10 条）：0=P1 1=Bg 2=P2 3=Bg 4=P3 5=Bg 6=P4 7=Bg 8=Env 9=Raw
param(
    [Parameter(Mandatory)][string]$Graph,
    [Parameter(Mandatory)][string]$OutPng,
    [string]$Meta = '',
    [string]$Id = '',
    [string[]]$PeakColors = @('color(11,83,148)', 'color(111,168,220)',
                              'color(224,102,102)', 'color(153,0,0)'),
    [string]$SumColor = 'color(64,64,64)',
    [string]$BgColor = 'color(179,179,179)',
    [int]$NPlotsPerCycle = 10,
    [double]$RawAlpha = 0.5,
    [double]$FillAlpha = 0.3,
    [string]$TmpDir = '',
    [switch]$KeepLayers
)

$ErrorActionPreference = 'Stop'
. "$env:DSH_HOME\custom-tools\origin\OriginToolkit.ps1"
$app = Get-OriginApp -Visible:$false

function LT([string]$e) { [void]$app.Execute($e) }

# 每层图都要用 range 绑定到具体曲线，直接 set 1!N 不生效
function PlotCmd([int]$p, [string]$opts) {
    return ('range q{0} = 1!{0}; set q{0} {1};' -f $p, $opts) + "`n"
}

if (-not $TmpDir) { $TmpDir = Join-Path $PSScriptRoot 'test' }
if (-not (Test-Path $TmpDir)) { New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null }
$dirFwd = (Resolve-Path $TmpDir).Path.Replace('\', '/') + '/'

if (-not $app.Execute(('win -a {0};' -f $Graph))) { throw "找不到图页 $Graph" }
LT 'nP = 0; doc -e DY { nP = nP + 1; };'
$tv = 'np' + (Get-Random); LT ('string {0}$ = $(nP);' -f $tv)
$nPlot = [int]$app.LTStr($tv + '$'); LT ('del -v {0}$;' -f $tv)
$nCycle = [int][math]::Floor($nPlot / $NPlotsPerCycle)
Write-Host ("{0}: {1} 条曲线（{2} 循环 × {3}）" -f $Graph, $nPlot, $nCycle, $NPlotsPerCycle)

$peaks = @(); $raws = @(); $envs = @(); $bgs = @()
for ($i = 0; $i -lt $nCycle; $i++) {
    $b = $i * $NPlotsPerCycle
    foreach ($k in @(0, 2, 4, 6)) { $peaks += ($b + $k + 1) }
    $raws += ($b + 10)
    $envs += ($b + 9)
    foreach ($k in @(1, 3, 5, 7)) { $bgs += ($b + $k + 1) }
}

# 分峰颜色按"结合能由低到高 = 蓝→红"分配，与建图脚本同一规则
$rank = @(0, 1, 2, 3)
if ($Meta -and $Id -and (Test-Path $Meta)) {
    $info = Get-Content $Meta -Raw -Encoding UTF8 | ConvertFrom-Json
    $entry = $info.$Id
    if ($entry -and $entry.peak_rank) { $rank = @($entry.peak_rank) }
}
$slotColor = @()
for ($k = 0; $k -lt 4; $k++) {
    $r = if ($rank.Count -gt $k -and $rank[$k] -ge 0) { $rank[$k] } else { $k }
    $slotColor += $PeakColors[$r % $PeakColors.Count]
}
$satColors = $slotColor
$lineColors = $slotColor
Write-Host ("  分峰配色（BE 低→高 蓝→红）：" + ($slotColor -join ' '))

function Export([string]$name) {
    LT ('expG2img igp:={0} type:=0 path:="{1}" name:="{2}" res:=300 width:=525;' -f $Graph, $dirFwd, $name)
    Start-Sleep -Milliseconds 600
    $p = Join-Path (Resolve-Path $TmpDir).Path ($name + '.png')
    if (-not (Test-Path $p)) { throw "导出失败 $name" }
    return $p
}

$base = (Split-Path $OutPng -Leaf) -replace '\.png$', ''

# ------------------------------------------------ 1) 每个分峰单独一层填充（饱和色）
# 背景曲线（每条分峰的"下一条曲线"= 填充基准）必须保持可见，否则退化成填到坐标轴。
$fillPngs = @()
for ($j = 0; $j -lt 4; $j++) {
    $cmds = ''
    for ($i = 0; $i -lt $nCycle; $i++) {
        $p = $i * $NPlotsPerCycle + $j * 2 + 1
        $cmds += PlotCmd $p ('-s 1; set q{0} -pf 1; set q{0} -pfv 8; set q{0} -cf {1}' -f $p, $satColors[$j])
    }
    # 其它分峰隐藏，背景与包络等也隐藏（背景作为基准保留）
    for ($i = 0; $i -lt $nCycle; $i++) {
        for ($k = 0; $k -lt 4; $k++) {
            if ($k -eq $j) { continue }
            $cmds += PlotCmd ($i * $NPlotsPerCycle + $k * 2 + 1) '-s 0'
        }
    }
    foreach ($p in $bgs) { $cmds += PlotCmd $p '-s 1' }
    foreach ($p in ($raws + $envs)) { $cmds += PlotCmd $p '-s 0' }
    LT $cmds
    LT 'doc -uw;'; Start-Sleep -Milliseconds 800
    $png = Export ($base + ('_L_fill{0}' -f ($j + 1)))
    $fillPngs += $png
    Write-Host ("  填充层 {0}  {1} bytes" -f (Split-Path $png -Leaf), (Get-Item $png).Length)
}

# ------------------------------------------------ 2) 其余内容（分峰线/包络/背景/坐标轴/文字/色标）
$cmds = ''
foreach ($p in $peaks) { $cmds += PlotCmd $p ('-pf 0; set q{0} -s 1' -f $p) }
foreach ($p in $envs) { $cmds += PlotCmd $p '-s 1' }
foreach ($p in $bgs) { $cmds += PlotCmd $p '-s 1' }
foreach ($p in $raws) { $cmds += PlotCmd $p '-s 0' }
LT $cmds
LT 'doc -uw;'; Start-Sleep -Milliseconds 900
$pRest = Export ($base + '_L_rest')
Write-Host ("  线条层 {0}  {1} bytes" -f (Split-Path $pRest -Leaf), (Get-Item $pRest).Length)

# ------------------------------------------------ 3) 只有实测点
$cmds = ''
foreach ($p in ($peaks + $envs + $bgs)) { $cmds += PlotCmd $p '-s 0' }
foreach ($p in $raws) { $cmds += PlotCmd $p '-s 1' }
LT $cmds
LT 'doc -uw;'; Start-Sleep -Milliseconds 900
$pRaw = Export ($base + '_L_raw')
Write-Host ("  数据点层 {0}  {1} bytes" -f (Split-Path $pRaw -Leaf), (Get-Item $pRaw).Length)

# ------------------------------------------------ 4) 恢复整图
$cmds = ''
for ($i = 0; $i -lt $nCycle; $i++) {
    $b = $i * $NPlotsPerCycle
    for ($j = 0; $j -lt 4; $j++) {
        $p = $b + $j * 2 + 1
        $cmds += PlotCmd $p ('-s 1; set q{0} -pf 1; set q{0} -pfv 8; set q{0} -cf {1}; set q{0} -c {2}' -f $p, $slotColor[$j], $lineColors[$j])
    }
    foreach ($p in @(($b + 2), ($b + 4), ($b + 6), ($b + 8), ($b + 9), ($b + 10))) {
        $cmds += PlotCmd $p '-s 1'
    }
}
LT $cmds
LT 'doc -uw;'
Write-Host '  已恢复整图样式'

# ------------------------------------------------ 5) 合成
$py = Join-Path $env:DSH_HOME 'dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe'
$script = Join-Path $PSScriptRoot 'composite_layers.py'
# 把 slotColor 里的 "color(r,g,b)" 解析成 "r,g,b" 传给 Python
$rgbArgs = @()
foreach ($c in $slotColor) {
    if ($c -match 'color\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)') { $rgbArgs += ($matches[1] + ',' + $matches[2] + ',' + $matches[3]) }
    else { $rgbArgs += '0,0,0' }
}
& $py $script $pRaw $pRest $OutPng $fillPngs[0] $fillPngs[1] $fillPngs[2] $fillPngs[3] $RawAlpha $FillAlpha ($rgbArgs -join ';')
if (-not (Test-Path $OutPng)) { throw '合成失败' }
Write-Host ("  成品 {0}  {1} bytes" -f (Split-Path $OutPng -Leaf), (Get-Item $OutPng).Length)
if (-not $KeepLayers) {
    Remove-Item $pRaw, $pRest -Force -ErrorAction SilentlyContinue
    Remove-Item $fillPngs -Force -ErrorAction SilentlyContinue
}
