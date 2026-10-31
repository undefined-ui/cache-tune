"""Screenshot table from raw result.json files. Usage: report.py <dir> <round> [<round> ...]

<dir> is results (the published runs) or runs (your own runs from run.sh)."""
import json, glob, os, sys, statistics as st

def load(base, ver, rnd):
    rows = []
    for p in sorted(glob.glob(f"{base}/{ver}-r{rnd}/pr*/result.json")):
        d = json.load(open(p, encoding="utf-8")); u = d["usage"]
        pr = os.path.basename(os.path.dirname(p)).split("-")[1]
        rows.append(dict(pr=pr, ver=ver, rnd=rnd, cost=d["total_cost_usd"], dur=d["duration_ms"] / 1000,
                         turns=d["num_turns"], cr=u["cache_read_input_tokens"], cw=u["cache_creation_input_tokens"],
                         inp=u["input_tokens"], out=u["output_tokens"]))
    return rows

base = sys.argv[1] if len(sys.argv) > 1 else "results"
rounds = sys.argv[2:] or ["1"]
rows = [r for rnd in rounds for v in ("baseline", "optimized") for r in load(base, v, rnd)]
rows.sort(key=lambda r: (r["pr"], r["rnd"], r["ver"] != "baseline"))
hdr = f"{'PR':<7}{'version':<11}{'run':>4}{'cost $':>9}{'duration':>10}{'turns':>7}{'cache read':>12}{'cache write':>13}{'output':>9}"
print(hdr); print("-" * len(hdr))
for r in rows:
    print(f"#{r['pr']:<6}{r['ver']:<11}{r['rnd']:>4}{r['cost']:>9.4f}{r['dur']:>9.1f}s{r['turns']:>7}{r['cr']:>12,}{r['cw']:>13,}{r['out']:>9,}")
print("-" * len(hdr))
avg = {}
for v in ("baseline", "optimized"):
    rs = [r for r in rows if r["ver"] == v]
    if not rs: continue
    a = {k: st.mean(r[k] for r in rs) for k in ("cost", "dur", "turns", "cr", "cw", "out")}; avg[v] = a
    print(f"{'AVG':<7}{v:<11}{len(rs):>4}{a['cost']:>9.4f}{a['dur']:>9.1f}s{a['turns']:>7.1f}{a['cr']:>12,.0f}{a['cw']:>13,.0f}{a['out']:>9,.0f}")
if len(avg) == 2:
    b, o = avg["baseline"], avg["optimized"]
    for k, name in (("cost", "cost"), ("dur", "duration"), ("turns", "turns"), ("cr", "cache read"), ("cw", "cache write"), ("out", "output")):
        print(f"  {name:<12} {100 * (o[k] - b[k]) / b[k]:+.1f}%")
