# 单谱分峰图一键出图（通用驱动）
# 用法：
#   .\Build-Single.ps1 -OutDir "<出图目录>" [-Meta .\data\meta_single.json]
# 前置：先跑 prep_single.py 生成 meta_single.json 与 <id>_single_origin.csv
param(
    [Parameter(Mandatory)][string]$OutDir,
    [string]$Meta = '',
    # 单谱版式：4.5 × 3.7 in（横宽比接近文献里的单谱分峰图）
    [double]$PageW = 4500, [double]$PageH = 3700,
    [double]$LayerLeft = 15, [double]$LayerTop = 8, [double]$LayerWidth = 82, [double]$LayerHeight = 74,
    [double]$TickPt = 12, [double]$TextScale = 100, [int]$ExportWidthPx = 2700,   # 4.5 in × 600 dpi
    [string]$FontName = 'Arial', [string]$TickFont = 'Arial',
    [double]$AxisThickness = 3, [double]$TickLen = 10,
    [double]$SymSize = 5, [double]$SymEdge = 0.75,
    [double]$PeakLineW = 1.2, [double]$SumLineW = 1.2, [double]$BgLineW = 0.8,
    [double]$BottomGapFrac = 0.05, [double]$TopGapFrac = 0.10,
    [double]$TitleGapY = 12, [double]$TitleGapX = 8,
    [double]$FillTransparency = 30, [double]$RawTransparency = 50,
    [string]$SumColor = 'color(64,64,64)', [string]$BgColor = 'color(179,179,179)',
    [string[]]$PeakColors = @('color(11,83,148)', 'color(111,168,220)',
                              'color(224,102,102)', 'color(153,0,0)')
)

$ErrorActionPreference = 'Stop'
. "$env:DSH_HOME\custom-tools\origin\OriginToolkit.ps1"
$app = Get-OriginApp -Visible:$false
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Meta) {
    # 默认读当前目录（或 $env:XPS_OUT）下的 data\meta_single.json
    $outRoot = if ($env:XPS_OUT) { $env:XPS_OUT } else { 'data' }
    if (-not [System.IO.Path]::IsPathRooted($outRoot)) {
        $outRoot = Join-Path (Get-Location) $outRoot
    }
    $Meta = Join-Path $outRoot 'meta_single.json'
}
if (-not (Test-Path $Meta)) { throw "找不到 $Meta（先运行 prep_single.py）" }

$info = Get-Content $Meta -Raw -Encoding UTF8 | ConvertFrom-Json
$ids = $info.PSObject.Properties.Name
Write-Host ("要出的单谱图：" + ($ids -join ', '))

foreach ($id in $ids) {
    $entry = $info.$id
    $lo = [double]$entry.window[0]; $hi = [double]$entry.window[1]
    $mid = [math]::Round(($lo + $hi) / 2.0)
    # 只取窗口内、且为整数的刻度值（ticksbydata 超出范围会被忽略）
    $tickLabels = @([math]::Floor($hi), $mid, [math]::Ceiling($lo)) |
        Sort-Object -Descending -Unique |
        Where-Object { $_ -ge [math]::Ceiling($lo) -and $_ -le [math]::Floor($hi) }

    Write-Host ("`n=== 生成 {0} ===" -f $id)
    $json = & (Join-Path $here 'Make-XpsStacked.ps1') -Meta $Meta -Id $id -OutDir $OutDir `
        -PageW $PageW -PageH $PageH -LayerLeft $LayerLeft -LayerTop $LayerTop `
        -LayerWidth $LayerWidth -LayerHeight $LayerHeight `
        -TickPt $TickPt -TextScale $TextScale -FontName $FontName -TickFont $TickFont `
        -AxisThickness $AxisThickness -TickLen $TickLen `
        -SymSize $SymSize -SymEdge $SymEdge -PeakLineW $PeakLineW -SumLineW $SumLineW -BgLineW $BgLineW `
        -BottomGapFrac $BottomGapFrac -TopGapFrac $TopGapFrac -TitleGapY $TitleGapY -TitleGapX $TitleGapX `
        -NoCycleLabels -NoKey -HideYLabels -NoMinorTicks -XInc 2 `
        -XTickLabels $tickLabels -XTickLabelPt 12 `
        -PeakColors $PeakColors -SumColor $SumColor -BgColor $BgColor -BgDash 0 `
        -FillComponents -ApplyTransparency -FillTransparency $FillTransparency -RawTransparency $RawTransparency `
        -ExportWidthPx $ExportWidthPx
    Write-Host $json
    # 单谱图的文件名改成 XPS_<元素>_fit.png（Make-XpsStacked 默认总叫 *_stacked）
    $r = $json | ConvertFrom-Json
    $elemTag = ($entry.elem -replace '[^A-Za-z0-9]', '')
    $target = Join-Path $OutDir ("XPS_{0}_fit.png" -f $elemTag)
    if ($r.Png -and ($r.Png -ne $target) -and (Test-Path $r.Png)) {
        Move-Item -LiteralPath $r.Png -Destination $target -Force
        Write-Host ("  → {0}" -f (Split-Path $target -Leaf))
    }
}
[void]$app.Execute('doc -uw;')
Write-Host "`n完成：单谱图已导出到 $OutDir"
