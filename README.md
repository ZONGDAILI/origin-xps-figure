# origin-xps-figure

> Publication-quality **XPS figures in Origin** — a [DeepSeek Harness](https://github.com/deepseek-ai) skill
> with **verified** LabTalk/COM settings, so you get the figure in one shot instead of trial and error.

Cover two common scenarios:

- **Multi-cycle stacked (waterfall)** — all cycles of a narrow scan on one axis, offset per cycle.
- **Single-spectrum peak fit** — one representative cycle, components filled down to the background.

The style it produces: 600 dpi, thin uniform frame, Arial integer tick labels only, components coloured by a
blue→red sequence ordered by binding energy, each component filled to its own background curve at 30 %
transparency, raw points as 50 %-transparent open circles, light-grey solid background line, no in-figure text.

## What makes this different

Everything here was established by testing against **OriginPro 2023** (LabTalk `@V = 10.000154`) and the
`Origin.ApplicationSI` COM interface. The skill documents what **actually renders**, including the
non-obvious traps:

| Goal | Works | Don't bother |
|---|---|---|
| exact tick positions *and* labels | `layer.x.ticksbydata$ = "290 286 282"` | `layer.x.inc` (ignored here) / `majorTicks` (only *approximately* N) |
| tick direction | `layer.x.ticks = 1` | — it is a bitmap, **not** a count |
| fill transparency **percentage** | COM `DataPlot.SetNumProp('Transparency', 30)` | `-paaf / -paap` (1/0 toggles only) |
| fill range = component → its background | plot order `peak, bg, peak, bg, …` + `-pfv 8` | `-pfv 1/3/4` (fills to the axis, floods the layer) |
| text font / size | `label.font = font("Arial")` / `\p<percent>(...)` | `label -f`, `.font.size`, `.pt` (no-ops) |
| axis-title distance | `page.ytitle` / `page.xtitle` | dragging objects around |
| uniform frame | `layer.x/y.thickness = 3` | `2` (left axis rounds to 5 px, top/right to 8 px) |

## Style it produces

- 600 dpi PNG, no data tables inside the figure
- thin uniform frame, Arial tick labels, integer tick values only
- components coloured by a **blue→red sequence ordered by binding energy** (not by peak index)
- each component filled down to *its own* background curve, **30 % transparent** (real alpha, blends where components overlap)
- raw data as open circles, **50 % transparent**
- background as a light-grey solid line; envelope as a dark-grey thin line
- no in-figure annotations (cycle order belongs in the caption)

## Install (as a DeepSeek Harness skill)

```powershell
New-Item -ItemType Directory -Force .agents\skills | Out-Null
Copy-Item -Recurse -Force .\origin-xps-figure .agents\skills\
```

Then the skill list shows `origin-xps-figure`. Alternatively, hand the whole zip to the harness and ask it to
read `origin-xps-figure/SKILL.md`.

## Use

```powershell
# multi-cycle stacked
python .\origin-xps-figure\assets\prep.py
.\origin-xps-figure\assets\Build-Stacked.ps1 -OutDir .\out

# single-spectrum peak fit (pick one cycle)
python .\origin-xps-figure\assets\prep_single.py --file YOUR.csv --elem "C 1s" `
    --cycle 2 --window 282 290 --mode bgsub --id s1
.\origin-xps-figure\assets\Build-Single.ps1 -OutDir .\out
```

Input format and `meta.json` fields: [`origin-xps-figure/assets/SAMPLE_FORMAT.md`](origin-xps-figure/assets/SAMPLE_FORMAT.md).
Baseline modes: `raw` (real curved background), `shift` (subtract one constant per cycle — keeps the background
shape while keeping peaks readable), `bgsub` (subtract the whole background), `norm`.

## Requirements

- OriginPro 2023+ on Windows (COM automation)
- PowerShell 7
- Python 3 with numpy + Pillow

## Contents

```
origin-xps-figure/
  SKILL.md                     the skill: verified property list, traps, workflow, checklist
  assets/
    prep.py                    multi-cycle: CasaXPS CSV -> wide table + meta.json
    prep_single.py             single cycle: -> wide table + meta_single.json
    Make-XpsStacked.ps1        the graph builder (fully parameterised)
    Build-Stacked.ps1          stacked-figure driver
    Build-Single.ps1           single-spectrum driver
    Layer-Composite.ps1        fallback when a build cannot do COM transparency
    composite_layers.py        layered render + alpha compositing
    SAMPLE_FORMAT.md           input format / meta fields
dist/                          ready-to-share zip of the skill
```

## License

MIT — see [LICENSE](LICENSE). No experimental data is included; example numbers are synthetic.
