"""Split the cost saving by token type. Usage: shares.py <dir> <round> [<round> ...]

For every published run, total_cost_usd equals the usage priced at these rates (USD per million
tokens, Sonnet 5.5 through Claude Code, which writes the cache with the 1-hour TTL)."""
import json, glob, sys, statistics as st

RATES = {"input": 2.0, "cache write 1h": 4.0, "cache write 5m": 2.5, "cache read": 0.10, "output": 10.0}

def tokens(d):
    u = d["usage"]; cc = u.get("cache_creation", {})
    return {"input": u["input_tokens"], "cache write 1h": cc.get("ephemeral_1h_input_tokens", 0),
            "cache write 5m": cc.get("ephemeral_5m_input_tokens", 0),
            "cache read": u["cache_read_input_tokens"], "output": u["output_tokens"]}

base = sys.argv[1] if len(sys.argv) > 1 else "results"
rounds = sys.argv[2:] or ["1"]
mean = {}
for ver in ("baseline", "optimized"):
    runs = [json.load(open(p, encoding="utf-8")) for r in rounds
            for p in sorted(glob.glob(f"{base}/{ver}-r{r}/pr*/result.json"))]
    for d in runs:
        priced = sum(n * RATES[k] for k, n in tokens(d).items()) / 1e6
        assert abs(priced - d["total_cost_usd"]) < 1e-9, "a run is priced at other rates"
    mean[ver] = {k: st.mean(tokens(d)[k] for d in runs) for k in RATES} | {"runs": len(runs)}

b, o = mean["baseline"], mean["optimized"]
saved = {k: (b[k] - o[k]) * RATES[k] / 1e6 for k in RATES}
total = sum(saved.values())
print(f"runs: baseline {b['runs']}, optimized {o['runs']}; saving per review ${total:.4f}")
print(f"{'tokens':<16}{'baseline':>12}{'optimized':>12}{'saved $':>10}{'share':>8}")
for k in RATES:
    if b[k] or o[k]:
        print(f"{k:<16}{b[k]:>12,.0f}{o[k]:>12,.0f}{saved[k]:>10.4f}{saved[k] / total:>8.0%}")
