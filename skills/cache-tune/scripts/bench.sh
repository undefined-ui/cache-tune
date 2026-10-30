#!/usr/bin/env bash
# Run the same tasks through two Claude Code setups and compare cost, duration
# and cache tokens. The setup file format is in reference/benchmark.md.
set -euo pipefail

# Git Bash on Windows rewrites arguments that start with "/" (slash commands
# such as "/review") into Windows paths. Keep them as written.
export MSYS_NO_PATHCONV=1

usage() {
  cat <<'EOF'
Usage:
  bench.sh [-n RUNS] [-o DIR] [--dry-run] BEFORE.sh AFTER.sh TASK [TASK...]
  bench.sh [-o DIR] --probe SETUP.sh [SETUP.sh...]

Runs every TASK through both setups RUNS times (default 2) with
`claude -p --output-format json`, alternating which setup goes first each
round, and prints cost, duration, turns and tokens per run, per task and on
average. Raw JSON, prompts and answers are kept in DIR
(default: ./bench-results/<time>).

  --dry-run  write and show the prompts each setup would send; call nothing
  --probe    one short haiku call per setup: the tools, MCP servers, skills
             and subagents it loads, and the size of its fixed prefix

A setup file is bash that defines:
  CLAUDE_ARGS=(...)       flags for claude -p, without --output-format
  build_prompt() { ...; } prints the prompt for task "$1" on stdout
  WORKDIR=dir             optional; where claude runs (default: current dir)
It can use $SETUP_DIR, the absolute directory of the setup file.
EOF
}

die() { printf 'bench.sh: %s\n' "$*" >&2; exit 1; }

# Absolute path of a directory. On Git Bash `pwd -W` gives C:/..., which the
# native Windows programs (claude, python, node) also understand.
abs_dir() { (cd "$1" && { pwd -W 2>/dev/null || pwd; }); }

# --- JSON readers: python3, python or node, all reading stdin ---------------

PY_RESULT='
import json, sys
sys.stdout.reconfigure(encoding="utf-8", newline="\n")
d = json.loads(sys.stdin.buffer.read().decode("utf-8"))
if d.get("type") != "result":
    raise SystemExit(1)
m = list((d.get("modelUsage") or {}).values())
if m:
    t = [sum(x.get(k) or 0 for x in m) for k in
         ("inputTokens", "cacheReadInputTokens", "cacheCreationInputTokens", "outputTokens")]
else:
    u = d.get("usage") or {}
    t = [u.get(k) or 0 for k in
         ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens", "output_tokens")]
f = ["error" if d.get("is_error") else "ok", d.get("total_cost_usd") or 0,
     d.get("duration_ms") or 0, d.get("num_turns") or 0] + t
print("\t".join(str(v) for v in f))
print(d.get("result") or "")
'

NODE_RESULT='
let s = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (c) => (s += c));
process.stdin.on("end", () => {
  const d = JSON.parse(s);
  if (d.type !== "result") process.exit(1);
  const m = Object.values(d.modelUsage || {});
  const u = d.usage || {};
  const t = m.length
    ? ["inputTokens", "cacheReadInputTokens", "cacheCreationInputTokens", "outputTokens"]
        .map((k) => m.reduce((a, x) => a + (x[k] || 0), 0))
    : ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens", "output_tokens"]
        .map((k) => u[k] || 0);
  const f = [d.is_error ? "error" : "ok", d.total_cost_usd || 0,
    d.duration_ms || 0, d.num_turns || 0, ...t];
  process.stdout.write(f.join("\t") + "\n" + (d.result || "") + "\n");
});
'

PY_PROBE='
import json, sys
sys.stdout.reconfigure(encoding="utf-8", newline="\n")
init = res = None
for line in sys.stdin.buffer.read().decode("utf-8").splitlines():
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        e = json.loads(line)
    except ValueError:
        continue
    if e.get("type") == "system" and e.get("subtype") == "init":
        init = e
    elif e.get("type") == "result":
        res = e
if init is None:
    raise SystemExit(1)
tools = init.get("tools") or []
mcp = init.get("mcp_servers") or []
agents = init.get("agents") or []
sent = "Task" in tools or "Agent" in tools
print("tools: %d (%s)" % (len(tools), ", ".join(tools)))
print("mcp servers: %s" % (", ".join("%s [%s]" % (s.get("name"), s.get("status")) for s in mcp) or "none"))
if any(s.get("status") == "pending" for s in mcp):
    print("  (pending servers were still connecting; their tools are missing from the list above)")
print("skills: %d" % len(init.get("skills") or []))
print("slash commands: %d" % len(init.get("slash_commands") or []))
print("subagents: %d defined, %s" % (len(agents), "listed to the model" if sent else "not listed (no Task/Agent tool)"))
if res:
    u = res.get("usage") or {}
    i, r, w = (u.get(k) or 0 for k in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
    print("fixed prefix: %d tokens (input %d, cache read %d, cache write %d)" % (i + r + w, i, r, w))
    print("cost: %.4f USD" % (res.get("total_cost_usd") or 0))
'

NODE_PROBE='
let s = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (c) => (s += c));
process.stdin.on("end", () => {
  let init = null, res = null;
  for (const raw of s.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line.startsWith("{")) continue;
    let e;
    try { e = JSON.parse(line); } catch { continue; }
    if (e.type === "system" && e.subtype === "init") init = e;
    else if (e.type === "result") res = e;
  }
  if (!init) process.exit(1);
  const tools = init.tools || [], mcp = init.mcp_servers || [], agents = init.agents || [];
  const sent = tools.includes("Task") || tools.includes("Agent");
  const out = [
    `tools: ${tools.length} (${tools.join(", ")})`,
    `mcp servers: ${mcp.map((x) => `${x.name} [${x.status}]`).join(", ") || "none"}`,
    ...(mcp.some((x) => x.status === "pending")
      ? ["  (pending servers were still connecting; their tools are missing from the list above)"] : []),
    `skills: ${(init.skills || []).length}`,
    `slash commands: ${(init.slash_commands || []).length}`,
    `subagents: ${agents.length} defined, ${sent ? "listed to the model" : "not listed (no Task/Agent tool)"}`,
  ];
  if (res) {
    const u = res.usage || {};
    const i = u.input_tokens || 0, r = u.cache_read_input_tokens || 0, w = u.cache_creation_input_tokens || 0;
    out.push(`fixed prefix: ${i + r + w} tokens (input ${i}, cache read ${r}, cache write ${w})`);
    out.push(`cost: ${(res.total_cost_usd || 0).toFixed(4)} USD`);
  }
  process.stdout.write(out.join("\n") + "\n");
});
'

JSON=""
pick_json() {
  local c
  for c in python3 python; do
    # On Windows, python3 may be a Microsoft Store stub that runs nothing.
    if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import json' >/dev/null 2>&1; then
      JSON=$c
      return
    fi
  done
  if command -v node >/dev/null 2>&1; then JSON=node; return; fi
  die "needs python3, python or node to read claude's JSON output"
}

# Line 1: status cost duration_ms turns input cache_read cache_write output.
# Then the answer text.
json_result() {
  if [ "$JSON" = node ]; then node -e "$NODE_RESULT"; else "$JSON" -c "$PY_RESULT"; fi
}

json_probe() {
  if [ "$JSON" = node ]; then node -e "$NODE_PROBE"; else "$JSON" -c "$PY_PROBE"; fi
}

# --- running a setup ---------------------------------------------------------

# in_setup SETUP CMD [ARGS...]: run CMD in a subshell that has sourced SETUP
# and changed to its WORKDIR, so one setup never sees the other's variables.
in_setup() {
  local setup=$1
  shift
  (
    CLAUDE_ARGS=()
    WORKDIR=.
    SETUP_DIR=$(abs_dir "$(dirname "$setup")")
    # shellcheck source=/dev/null
    . "$setup"
    declare -F build_prompt >/dev/null || die "$setup does not define build_prompt"
    cd "$WORKDIR" || die "$setup: WORKDIR not found: $WORKDIR"
    "$@"
  )
}

# The prompt goes in on stdin: no command-line length limit for big diffs,
# and variadic flags such as --tools cannot swallow it.
do_run() { # TASK BASE
  build_prompt "$1" >"$2.prompt.txt"
  claude -p ${CLAUDE_ARGS[@]+"${CLAUDE_ARGS[@]}"} --output-format json \
    <"$2.prompt.txt" >"$2.json" 2>"$2.err"
}

do_probe() { # BASE
  printf 'Reply with OK.\n' |
    claude -p ${CLAUDE_ARGS[@]+"${CLAUDE_ARGS[@]}"} --model haiku --max-turns 1 \
      --output-format stream-json --verbose >"$1.jsonl" 2>"$1.err"
}

do_dry() { # TASK BASE
  local a
  build_prompt "$1" >"$2.prompt.txt"
  printf '  workdir: %s\n  command: claude -p' "$(abs_dir .)"
  for a in ${CLAUDE_ARGS[@]+"${CLAUDE_ARGS[@]}"}; do
    case $a in
      '' | *[!A-Za-z0-9_./:=,@+-]*) printf " '%s'" "${a//\'/\'\\\'\'}" ;;
      *) printf ' %s' "$a" ;;
    esac
  done
  printf ' --output-format json < %s\n' "$2.prompt.txt"
  printf '  prompt: %s bytes, first lines:\n' "$(wc -c <"$2.prompt.txt" | tr -d ' ')"
  head -n 12 "$2.prompt.txt" | sed 's/^/    | /'
}

# --- summary -----------------------------------------------------------------

SUMMARY_AWK='
BEGIN { FS = "\t" }
{
  n++; lab[n] = $1; rnd[n] = $2; ti[n] = $3; st[n] = $5
  name[$3] = $4; if ($3 + 0 > nt) nt = $3 + 0
  for (k = 6; k <= 12; k++) val[n, k] = $k + 0
}
function pct(b, a) { return b == 0 ? "n/a" : sprintf("%+.1f%%", (a - b) / b * 100) }
function fmt(k, v) {
  if (k == 6) return sprintf("%.4f", v)
  if (k == 7 || k == 8) return sprintf("%.1f", v)
  return sprintf("%.0f", v)
}
END {
  printf "%-7s %5s  %-24s %9s %7s %5s %7s %10s %11s %7s\n", "setup", "round", "task",
    "cost_usd", "time_s", "turns", "input", "cache_read", "cache_write", "output"
  for (i = 1; i <= n; i++) {
    t = substr(name[ti[i]], 1, 24)
    if (st[i] == "failed") { printf "%-7s %5d  %-24s failed\n", lab[i], rnd[i], t; continue }
    printf "%-7s %5d  %-24s %9.4f %7.1f %5d %7d %10d %11d %7d%s\n", lab[i], rnd[i], t,
      val[i, 6], val[i, 7] / 1000, val[i, 8], val[i, 9], val[i, 10], val[i, 11], val[i, 12],
      (st[i] == "ok" ? "" : "  error")
    if (st[i] != "ok") continue
    L = lab[i]; cnt[L]++
    tc[L, ti[i]] += val[i, 6]; tk[L, ti[i]]++
    for (k = 6; k <= 12; k++) {
      v = val[i, k]; if (k == 7) v = v / 1000
      sum[L, k] += v
      if (!((L, k) in lo) || v < lo[L, k]) lo[L, k] = v
      if (!((L, k) in hi) || v > hi[L, k]) hi[L, k] = v
    }
  }
  if (!cnt["before"] || !cnt["after"]) { print "\nno successful runs for one of the setups"; exit }

  printf "\nmean cost per task\n%-24s %9s %9s %8s\n", "task", "before", "after", "change"
  for (t = 1; t <= nt; t++) {
    if (!tk["before", t] || !tk["after", t]) continue
    b = tc["before", t] / tk["before", t]; a = tc["after", t] / tk["after", t]
    printf "%-24s %9.4f %9.4f %8s\n", substr(name[t], 1, 24), b, a, pct(b, a)
  }

  printf "\nmean per run (before: %d runs, after: %d runs)\n", cnt["before"], cnt["after"]
  printf "%-12s %10s %10s %8s  %s\n", "metric", "before", "after", "change", "ranges overlap"
  split("cost_usd time_s turns input cache_read cache_write output", label, " ")
  for (k = 6; k <= 12; k++) {
    b = sum["before", k] / cnt["before"]; a = sum["after", k] / cnt["after"]
    ov = (cnt["before"] < 2 || cnt["after"] < 2) ? "-" : \
      ((lo["before", k] <= hi["after", k] && lo["after", k] <= hi["before", k]) ? "yes (unproven)" : "no")
    printf "%-12s %10s %10s %8s  %s\n", label[k - 5], fmt(k, b), fmt(k, a), pct(b, a), ov
  }
}
'

# --- main --------------------------------------------------------------------

RUNS=2
OUT=""
DRY=0
PROBE=0
while [ $# -gt 0 ]; do
  case $1 in
    -n) [ $# -ge 2 ] || die "-n needs a number"; RUNS=$2; shift 2 ;;
    -o) [ $# -ge 2 ] || die "-o needs a directory"; OUT=$2; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --probe) PROBE=1; shift ;;
    -h | --help) usage; exit 0 ;;
    --) shift; break ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done
case $RUNS in '' | *[!0-9]* | 0) die "-n needs a positive whole number" ;; esac

if [ "$PROBE" = 1 ]; then
  [ $# -ge 1 ] || die "--probe needs at least one setup file"
  for f in "$@"; do [ -f "$f" ] || die "setup file not found: $f"; done
else
  [ $# -ge 3 ] || { usage >&2; exit 2; }
  for f in "$1" "$2"; do [ -f "$f" ] || die "setup file not found: $f"; done
fi
command -v claude >/dev/null 2>&1 || die "claude not found in PATH"
pick_json

[ -n "$OUT" ] || OUT=bench-results/$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
OUT=$(abs_dir "$OUT")

if [ "$PROBE" = 1 ]; then
  for setup in "$@"; do
    base="$OUT/probe-$(basename "$setup" .sh)"
    printf '== %s\n' "$setup"
    in_setup "$setup" do_probe "$base" || true
    json_probe <"$base.jsonl" 2>/dev/null || printf 'probe failed, see %s.err\n' "$base"
  done
  exit 0
fi

BEFORE=$1
AFTER=$2
shift 2
TASKS=("$@")

if [ "$DRY" = 1 ]; then
  for label in before after; do
    if [ "$label" = before ]; then setup=$BEFORE; else setup=$AFTER; fi
    printf '== %s (%s)\n' "$label" "$setup"
    for ((i = 0; i < ${#TASKS[@]}; i++)); do
      printf 'task %d: %s\n' "$((i + 1))" "${TASKS[i]}"
      in_setup "$setup" do_dry "${TASKS[i]}" "$OUT/$label-t$((i + 1))" || true
    done
  done
  printf '\nPrompts are in %s. Diff them: the task data must match.\n' "$OUT"
  exit 0
fi

total=$((RUNS * ${#TASKS[@]} * 2))
printf '%d rounds x %d tasks x 2 setups = %d claude calls. Results: %s\n\n' \
  "$RUNS" "${#TASKS[@]}" "$total" "$OUT" >&2

ROWS="$OUT/runs.tsv"
: >"$ROWS"
count=0
for ((r = 1; r <= RUNS; r++)); do
  # Alternate the order so neither setup always runs on a warmer cache.
  if ((r % 2)); then order="before after"; else order="after before"; fi
  for ((i = 0; i < ${#TASKS[@]}; i++)); do
    task=${TASKS[i]}
    for label in $order; do
      count=$((count + 1))
      if [ "$label" = before ]; then setup=$BEFORE; else setup=$AFTER; fi
      base="$OUT/$label-r$r-t$((i + 1))"
      printf '[%d/%d] %-6s round %d, task %d (%s): ' "$count" "$total" "$label" "$r" "$((i + 1))" "$task" >&2
      in_setup "$setup" do_run "$task" "$base" || true
      if out=$(json_result <"$base.json" 2>/dev/null); then
        line=$(printf '%s\n' "$out" | head -n 1)
        printf '%s\n' "$out" | tail -n +2 >"$base.answer.txt"
      else
        line=$(printf 'failed\t0\t0\t0\t0\t0\t0\t0')
      fi
      printf '%s\t%d\t%d\t%s\t%s\n' "$label" "$r" "$((i + 1))" "${task//$'\t'/ }" "$line" >>"$ROWS"
      printf '%s\n' "$line" | awk -F'\t' -v b="$base" '
        $1 == "failed" { printf "failed, see %s.err\n", b; next }
        { printf "%s%.4f USD, %.1f s\n", ($1 == "ok" ? "" : "error, "), $2, $3 / 1000 }' >&2
    done
  done
done

printf '\n' >&2
awk "$SUMMARY_AWK" "$ROWS" | tee "$OUT/summary.txt"
printf '\nAnswers: %s/*.answer.txt. Compare before and after to check quality.\n' "$OUT"
