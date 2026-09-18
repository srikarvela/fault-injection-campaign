#!/usr/bin/env python3
"""Fault-injection campaign driver.

Sweeps the cross product (fault target x cycle) for a variant, runs one Icarus
simulation per point via vvp, parses the RESULT line, classifies the outcome,
and writes results/<variant>/results.csv plus summary.json (with the headline
exploitability rate = exploited / total). Build the .vvp files first with
`make build` (or this script compiles them if missing).

  python3 campaign/run_campaign.py baseline
  python3 campaign/run_campaign.py hardened
  python3 campaign/run_campaign.py both
"""
import csv, json, os, re, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from classify import classify

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CYCLES = list(range(0, 12))
# y-axis: injection targets. label is what the heatmap row is called.
TARGETS = [
    ("skip",       dict(ftype="skip",     ftarget="ir")),
    ("pc.bit0",    dict(ftype="pcflip",   ftarget="pc", fbit=0)),
    ("pc.bit1",    dict(ftype="pcflip",   ftarget="pc", fbit=1)),
    ("pc.bit2",    dict(ftype="pcflip",   ftarget="pc", fbit=2)),
    ("pc.bit3",    dict(ftype="pcflip",   ftarget="pc", fbit=3)),
    ("rf0.bit0",   dict(ftype="regflip",  ftarget="rf0", fbit=0)),
    ("rf0.bit4",   dict(ftype="regflip",  ftarget="rf0", fbit=4)),
    ("rf0.bit8",   dict(ftype="regflip",  ftarget="rf0", fbit=8)),
    ("rf0.bit12",  dict(ftype="regflip",  ftarget="rf0", fbit=12)),
    ("zero",       dict(ftype="zeroflip", ftarget="zero")),
    ("ctrl_boot",  dict(ftype="ctrlflip", ftarget="ctrl_boot")),
]
VVP = {"baseline": "build/dut_baseline.vvp", "hardened": "build/dut_hardened.vvp"}
HARDEN = {"baseline": 0, "hardened": 1}

def ensure_built(variant):
    vvp = os.path.join(ROOT, VVP[variant])
    if os.path.exists(vvp):
        return vvp
    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
    subprocess.run(["iverilog", "-g2012", "-Wno-timescale",
                    f"-Ptb_fault.HARDEN_P={HARDEN[variant]}", "-o", vvp,
                    "rtl/secure_check.sv", "tb/tb_fault.sv"], cwd=ROOT, check=True)
    return vvp

def run_point(vvp, cycle, cfg):
    args = ["vvp", "-N", vvp, f"+ftype={cfg['ftype']}", f"+fcycle={cycle}",
            f"+ftarget={cfg['ftarget']}", f"+fbit={cfg.get('fbit', 0)}"]
    out = subprocess.run(args, cwd=ROOT, capture_output=True, text=True).stdout
    m = re.search(r"RESULT .*boot_ok=(\d) tamper=(\d) halted=(\d) cyc=(\d+)", out)
    if not m:
        raise RuntimeError(f"no RESULT for cycle={cycle} cfg={cfg}\n{out}")
    b, t, h, cyc = (int(x) for x in m.groups())
    return b, t, h, cyc, classify(b, t, h)

def run_variant(variant):
    vvp = ensure_built(variant)
    outdir = os.path.join(ROOT, "results", variant)
    os.makedirs(outdir, exist_ok=True)
    rows, counts = [], {}
    for label, cfg in TARGETS:
        for cyc in CYCLES:
            b, t, h, ncyc, bucket = run_point(vvp, cyc, cfg)
            rows.append(dict(target=label, ftype=cfg["ftype"], cycle=cyc,
                             bit=cfg.get("fbit", 0), boot_ok=b, tamper=t,
                             halted=h, run_cycles=ncyc, outcome=bucket))
            counts[bucket] = counts.get(bucket, 0) + 1
    with open(os.path.join(outdir, "results.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader(); w.writerows(rows)
    total = len(rows)
    exploited = counts.get("exploited", 0)
    summary = dict(variant=variant, total=total, counts=counts,
                   exploitability_rate=round(exploited / total, 4),
                   exploited=exploited)
    with open(os.path.join(outdir, "summary.json"), "w") as f:
        json.dump(summary, f, indent=2)
    print(f"[{variant}] {total} points  counts={counts}  "
          f"exploitability={summary['exploitability_rate']:.1%}")
    return summary

def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "both"
    variants = ["baseline", "hardened"] if which == "both" else [which]
    res = {v: run_variant(v) for v in variants}
    if len(res) == 2:
        b = res["baseline"]["exploitability_rate"]
        h = res["hardened"]["exploitability_rate"]
        print(f"\nExploitability: baseline {b:.1%} -> hardened {h:.1%} "
              f"(delta {b - h:+.1%}) -- the delta is the result.")

if __name__ == "__main__":
    main()
