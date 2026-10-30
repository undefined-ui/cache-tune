# cache-tune

A Claude Code skill that makes an agent's prompt cache-friendly, so repeated `claude -p` runs cost less
and the agent does the same work.

## Results

One test: Claude Code with `--model sonnet` reviewed 5 merged fastapi PRs, 2 rounds per setup.

| Metric | Before | After | Change |
|---|---|---|---|
| Cost per review | $0.1441 | $0.0732 | -49.2%, cheaper on all 5 PRs |
| Cache writes per run | 24.1k tokens | 11.1k tokens | 73% of the saving |
| Output tokens | | | -32% overall, partly from the fixed findings format; dropping the final summary alone saved 16% |
| Duration | | | -42.8%, but noisy (ranges overlap), so unproven |
| Quality | | | both setups found the same core issues on every PR |

What changed:

1. Review rules and project notes moved from a dated CLAUDE.md into a byte-stable system prompt.
2. Branch and date moved after the diff.
3. Tools cut from 16 to Read/Grep/Glob/Bash, with no MCP connectors, skills or subagents. About 11k
   tokens of skill listings, agent listings and connector tools had been sitting after the diff and were
   written to cache again on every run.
4. No final summary; findings use a fixed format (severity, file:line, fix).

Moving date and branch alone saved little. The changes were not tested one by one.

## What the skill does

1. **Audits** CLAUDE.md, AGENTS.md, `.claude/settings.json`, MCP servers, skills, subagents and the
   scripts that run headless `claude -p` jobs. It flags values that change per run (dates, branch names,
   run IDs, timestamps) inside the stable part of the prompt, and bulky text placed after the per-run part.
2. **Proposes a plan** and applies it only after you confirm:
   - stable rules in one byte-identical block at the top (`--append-system-prompt-file`)
   - per-run data (task, diff, branch, date) at the very end
   - only the tools the job uses, with MCP servers, skills and subagents off where the job doesn't need them
   - a fixed output format with no closing summary
3. **Shows the diff** of every changed file.
4. **Benchmarks** before against after: the same tasks N times through both setups with
   `claude -p --output-format json`, printing cost, duration, cache reads, cache writes and averages.

It changes only how the prompt is assembled, never what the agent is told to do. Model, effort,
permissions and rule text stay as they are.

## Install

```bash
npx skills add undefined-ui/cache-tune -g
```

This uses the [skills](https://github.com/vercel-labs/skills) CLI (needs Node.js) and installs the skill for
your user. Leave out `-g` to install it into the current project only. Restart Claude Code.

Without Node.js, copy the skill folder into your user skills:

```bash
git clone https://github.com/undefined-ui/cache-tune
cp -r cache-tune/skills/cache-tune ~/.claude/skills/
```

Or into one project:

```bash
cp -r cache-tune/skills/cache-tune <your-project>/.claude/skills/
```

## Use

In the project that runs the agent, type:

```text
/cache-tune
```

or ask in your own words, for example "make our PR review job cheaper". The skill audits, shows the plan
and waits for your yes. Before each probe or benchmark it says how many `claude` calls it will make and
asks.

The benchmark also runs on its own:

```bash
scripts/bench.sh -n 2 bench/before.sh bench/after.sh main~2..main~1 main~1..main
```

```bash
scripts/bench.sh --probe bench/before.sh bench/after.sh
```

A setup file is a short bash file with `CLAUDE_ARGS`, a `build_prompt` function and an optional `WORKDIR`.
See [the benchmark reference](skills/cache-tune/reference/benchmark.md) and
[the template](skills/cache-tune/templates/setup.example.sh). `--probe` makes one short haiku call per
setup and lists the tools, MCP servers and skills it loads, with the size of its fixed prefix.

Needs bash, the Claude Code CLI, and python3 or node. Works on macOS, Linux and Windows Git Bash.

## Credit

The idea comes from [Cloudflare's blog post](https://blog.cloudflare.com/obsessive-inference-optimization/)
of Oct 19, 2026. 77% of their AI code review bill was cache writes and reads, and only 14-26% of first
requests hit the cache. Their fix was to split the prompt so the static part gets its own cache
breakpoint. The cache fix alone took them from $2.47 to $2.02 per review; most of their total savings
($2.43 to $0.77) came from switching models and effort levels.

## License

MIT
