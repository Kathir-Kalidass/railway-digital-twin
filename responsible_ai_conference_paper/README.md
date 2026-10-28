# Responsible AI Conference Paper

IEEE-format conference paper: **AI-Based Railway Track Defect Detection in
India — False Negatives, Safety Assurance and Human Accountability**.

By Jivetesh, Kathir Kalidass B, Dhinesh Babu C M, Paril T (Anna University).

## Contents

- `Conference.tex` — paper source (IEEE conference class)
- `IEEE.cls` — class file
- `Conference.pdf` — compiled paper
- `TEAM_4_RESPONSIBLE_AI_Railway_Track_defect.pptx` — presentation deck
- `fig_*.png`, `Arch *.png`, `Den.png`, `Eff.png` — figures
- `generate_figures.py` — regenerates result figures
- `generate_ppt.py` — regenerates the slide deck

## Build

```bash
pdflatex Conference.tex
pdflatex Conference.tex   # resolve references
```

LaTeX build artifacts (`aux`, `log`, `out`, `blg`, `bbl`) are ignored.
