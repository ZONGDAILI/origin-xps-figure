# INSTALL / 安装说明

本仓库是一个 **DeepSeek Harness 技能**：`origin-xps-figure`
（用 Origin 画出版级 XPS 图，覆盖**多循环堆叠瀑布图**与**单谱分峰图**两种场景）。

## 目录结构

```
INSTALL.md                  ← 本文件
README.md                   ← 仓库首页（含示例图）
LICENSE                     ← MIT
origin-xps-figure/          ← 技能本体
  SKILL.md                  ← 核心：属性清单 / 坑 / 流程 / 验证
  assets/                   ← 可直接运行的脚本
    prep.py                 ← 多循环：源 CSV → 宽表 + meta.json
    prep_single.py          ← 单谱：挑一个循环 → 单循环宽表 + meta_single.json
    Make-XpsStacked.ps1     ← 建图主脚本（全参数化）
    Build-Stacked.ps1       ← 堆叠图一键驱动
    Build-Single.ps1        ← 单谱分峰图一键驱动
    Layer-Composite.ps1     ← 透明度备用方案（分层渲染）
    composite_layers.py     ← 透明度备用方案（合成）
    SAMPLE_FORMAT.md        ← 输入格式与 meta 字段说明
dist/                       ← 可直接分发的技能压缩包
```

## 方式 A：安装成仓库级技能（推荐）

在**你自己的项目根目录**执行：

```powershell
New-Item -ItemType Directory -Force .agents\skills | Out-Null
Copy-Item -Recurse -Force .\origin-xps-figure .agents\skills\
```

完成后应为：

```
<你的项目>/.agents/skills/origin-xps-figure/SKILL.md
```

刷新/重开 DeepSeek Harness 会话，技能列表里出现 `origin-xps-figure` 即可。

## 方式 B：直接让 Harness 读

把 `dist/origin-xps-figure-skill.zip`（或任意一份 `SKILL.md`）发给 DeepSeek Harness，说：

> 读这个 SKILL.md，按它的流程和属性清单帮我画 XPS 图。

## 使用流程

### 多循环堆叠图

```powershell
# 1) 数据：CasaXPS 导出的窄扫 CSV 放进 data_raw\
# 2) 改 origin-xps-figure\assets\prep.py 顶部的 JOBS（文件名 / 元素 / 显示窗口 / 基线模式）
$env:PYTHONUTF8 = 1
python .\origin-xps-figure\assets\prep.py
.\origin-xps-figure\assets\Build-Stacked.ps1 -OutDir .\out      # → out\XPS_<元素>_stacked.png
```

### 单谱分峰图

```powershell
python .\origin-xps-figure\assets\prep_single.py --file YOUR.csv --elem "C 1s" `
    --cycle 2 --window 282 290 --mode bgsub --id s1
.\origin-xps-figure\assets\Build-Single.ps1 -OutDir .\out       # → out\XPS_C1s_fit.png
```

## 环境要求

- OriginPro 2023+（Windows），可 COM 连接（`Origin.ApplicationSI`）
- PowerShell 7
- Python 3 + numpy + Pillow

## 数据安全

本仓库**不包含任何实验数据**：`.gitignore` 已排除 `data/`、`data_raw/`、`out/`、`*.csv`、`*.opju`、`*.png`。
