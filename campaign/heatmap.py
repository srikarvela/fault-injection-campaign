#!/usr/bin/env python3
"""Render fault-sensitivity heatmaps (cycle x injection target) as standalone
SVG -- no matplotlib, no dependencies -- from results/<variant>/results.csv.
Each cell is coloured by outcome (exploited/crash/hang/silent). Writes
docs/heatmap_<variant>.svg and prints the exploitability rate. The heatmap is
the artifact that makes the project legible in five seconds.

  python3 campaign/heatmap.py baseline hardened
"""
import csv, os, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
COLOR = {"exploited": "#d1495b", "crash": "#edae49",
         "hang": "#8d99ae", "silent": "#2a9d8f", "": "#eeeeee"}

def load(variant):
    rows = list(csv.DictReader(open(os.path.join(ROOT, "results", variant, "results.csv"))))
    targets, cycles = [], []
    for r in rows:
        if r["target"] not in targets: targets.append(r["target"])
        c = int(r["cycle"])
        if c not in cycles: cycles.append(c)
    grid = {(r["target"], int(r["cycle"])): r["outcome"] for r in rows}
    return targets, sorted(cycles), grid

def svg(variant):
    targets, cycles, grid = load(variant)
    cw, ch, lx, ty = 34, 24, 96, 54
    W = lx + len(cycles) * cw + 20
    H = ty + len(targets) * ch + 70
    expl = sum(1 for v in grid.values() if v == "exploited")
    rate = expl / len(grid) if grid else 0
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" font-family="monospace" font-size="11">']
    s.append(f'<text x="{lx}" y="20" font-size="14" font-weight="bold">Fault sensitivity — {variant} '
             f'(exploitability {rate:.1%})</text>')
    for j, c in enumerate(cycles):
        s.append(f'<text x="{lx + j*cw + cw/2}" y="{ty-6}" text-anchor="middle">{c}</text>')
    s.append(f'<text x="{lx + len(cycles)*cw/2}" y="{H-40}" text-anchor="middle">injection cycle</text>')
    for i, tgt in enumerate(targets):
        y = ty + i*ch
        s.append(f'<text x="{lx-6}" y="{y+ch*0.66}" text-anchor="end">{tgt}</text>')
        for j, c in enumerate(cycles):
            oc = grid.get((tgt, c), "")
            x = lx + j*cw
            s.append(f'<rect x="{x}" y="{y}" width="{cw-2}" height="{ch-2}" '
                     f'fill="{COLOR.get(oc, "#eee")}"><title>{tgt} @cyc{c}: {oc}</title></rect>')
    lx0, ly = lx, H-22
    for k, (name, col) in enumerate(COLOR.items()):
        if name == "": continue
        s.append(f'<rect x="{lx0}" y="{ly}" width="12" height="12" fill="{col}"/>')
        s.append(f'<text x="{lx0+16}" y="{ly+11}">{name}</text>')
        lx0 += 92
    s.append('</svg>')
    out = os.path.join(ROOT, "docs", f"heatmap_{variant}.svg")
    open(out, "w").write("\n".join(s))
    print(f"wrote {os.path.relpath(out, ROOT)}  (exploitability {rate:.1%})")

def main():
    for v in (sys.argv[1:] or ["baseline", "hardened"]):
        svg(v)

if __name__ == "__main__":
    main()
