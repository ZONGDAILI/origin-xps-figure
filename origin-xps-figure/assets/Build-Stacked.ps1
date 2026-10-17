# 堆叠图一键出图（通用驱动）
# 用法：
#   .\Build-Stacked.ps1 -OutDir "<出图目录>" [-Meta .\data\meta.json] [-BookPrefix X]
# 前置：先跑 prep.py 生成 .\data\meta.json 与各 <id>_origin.csv
param(
    [Parameter(Mandatory)][string]$OutDir,
    [string]$Meta = '',
    [double]$PageW = 1750, [double]$PageH = 10000,
    [double]$LayerLeft = 22, [double]$LayerTop = 4, [double]$LayerWidth = 64, [double]$LayerHeight = 84,
    [double]$TickPt = 13, [double]$TextScale = 72, [int]$ExportWidthPx = 1050,
    [string]$LabelPrefix = 'C',
    [string]$FontName = 'Times New Roman', [string]$TickFont = 'Arial',
    [double]$AxisThickness = 3, [double]$TickLen = 8,
    [double]$SymSize = 2.5, [double]$SymEdge = 0.4,
    [double]$PeakLineW = 0.8, [double]$SumLineW = 1.0, [double]$BgLineW = 0.7,
    [double]$BottomGapFrac = 0.5, [double]$TopGapFrac = 0.25,
    [double]$TitleGapY = 10, [double]$TitleGapX = 6,
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
    # 默认读当前目录（或 $env:XPS_OUT）下的 data\meta.json
    $outRoot = if ($env:XPS_OUT) { $env:XPS_OUT } else { 'data' }
    if (-not [System.IO.Path]::IsPathRooted($outRoot)) {
        $outRoot = Join-Path (Get-Location) $outRoot
    }
    $Meta = Join-Path $outRoot 'meta.json'
}
if (-not (Test-Path $Meta)) { throw "找不到 $Meta（先运行 prep.py）" }

$info = Get-Content $Meta -Raw -Encoding UTF8 | ConvertFrom-Json
$ids = $info.PSObject.Properties.Name

Write-Host ("要出的图：" + ($ids -join ', '))
foreach ($id in $ids) {
    $entry = $info.$id
    # 4 个刻度的整数标签：默认取窗口两端 + 中间的一半，可按需覆盖
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
        -TickPt $TickPt -TextScale $TextScale -LabelPrefix $LabelPrefix `
        -FontName $FontName -TickFont $TickFont -AxisThickness $AxisThickness -TickLen $TickLen `
        -SymSize $SymSize -SymEdge $SymEdge -PeakLineW $PeakLineW -SumLineW $SumLineW -BgLineW $BgLineW `
        -BottomGapFrac $BottomGapFrac -TopGapFrac $TopGapFrac -TitleGapY $TitleGapY -TitleGapX $TitleGapX `
        -NoCycleLabels -NoKey -HideYLabels -NoMinorTicks -XInc 2 `
        -XTickLabels $tickLabels -XTickLabelPt 13 `
        -PeakColors $PeakColors -SumColor $SumColor -BgColor $BgColor -BgDash 0 `
        -FillComponents -ApplyTransparency -FillTransparency $FillTransparency -RawTransparency $RawTransparency `
        -ExportWidthPx $ExportWidthPx
    Write-Host $json
}
[void]$app.Execute('doc -uw;')
Write-Host "`n完成：图已导出到 $OutDir"
