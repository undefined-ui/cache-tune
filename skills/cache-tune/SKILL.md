---
name: cache-tune
description: Make a Claude Code agent's prompt cache-friendly so repeated headless runs (claude -p jobs, CI review bots, scheduled agents, claude-code-action workflows) read the prompt cache instead of writing it again, without changing what the agent does. Audits CLAUDE.md, AGENTS.md, .claude/settings.json, MCP servers, skills, subagents and job scripts, proposes a plan, applies it only after the user confirms, shows the diff, and benchmarks before against after. Use when the user wants to cut the cost of a claude -p job, says cache writes dominate their bill, sees a low cache hit rate, or asks to make their agent setup cache-friendly. Do not use to tune an interactive session, to pick a cheaper model or effort level, or to change the agent's rules or task.
---

# cache-tune

Cuts the cost of repeated agent runs by changing how the prompt is assembled.
`<skill-dir>` below is the base directory Claude Code shows when this skill loads.

## Rules

- Change assembly only: where text sits, which tools load, the output format. Do not reword, add or drop
  rules. Do not remove a tool, MCP server, skill or subagent the job uses. Do not touch model, effort,
  max turns or permissions.
- Read-only until the user approves the plan: no edits, no git changes, no installs.
- Apply only what the user approved. If applying needs a change the plan does not list (a `cd`, a path
  fix, an extra flag), stop and ask first.
- Every `claude` call costs money. Before a probe or a benchmark, say how many calls it makes and ask.

## Workflow

### 1. Audit

Run `bash <skill-dir>/scripts/audit.sh <project-dir>`. It lists context files with sizes, settings, MCP
config, skills, subagents, headless invocations, and lines with per-run values. Then read each job it
found (shell script, CI workflow, Makefile target, cron entry) and write down its request in send order,
as in [reference/prompt-layout.md](reference/prompt-layout.md): tools, system prompt, first user message.

No job found: ask which command runs the agent. If there is none, say there is nothing to tune and stop.

Optional, ask first: `bash <skill-dir>/scripts/bench.sh --probe <setup.sh>` makes one short haiku call
and prints the tools, MCP servers and skills the job loads and the size of its fixed prefix.

### 2. Report

One table: finding, `file:line`, why it costs, fix. Flag:

- per-run values (dates, branch, SHA, PR or run IDs, timestamps, temp paths) inside stable text: CLAUDE.md,
  AGENTS.md, system prompt files, skill and agent files, the fixed part of the prompt template
- bulky stable text (rules, notes, checklists) in CLAUDE.md, AGENTS.md or the prompt: it travels in the
  first user message and is written to cache again on every run
- tools, MCP servers, claude.ai connectors, skills and subagents the job does not use
- per-run data placed before stable text in the prompt template
- a closing summary, or free-form output where a fixed format would do

How to tell what the job uses: [reference/levers.md](reference/levers.md#decide-what-the-job-uses).

### 3. Plan, then stop

Write the plan with the template in [reference/levers.md](reference/levers.md#plan-template): each change
with its file, what moves where, why, and the risk; then what stays the same. Ask "Apply this plan?" and
wait. If the user approves only some items, apply only those.

### 4. Apply

- Stable block: move the job's rules and notes word for word into one file, for example
  `.claude/prompts/<job>.md`, and pass it with `--append-system-prompt-file`. Keep per-run values out of
  it. It must be byte-identical on every run: no dates, no generated text, LF line endings.
- Tail: the prompt ends with the per-run data: task, then diff or inputs, then branch, date and IDs last.
- Tools: `--tools` with only what the job uses, `--strict-mcp-config` (plus `--mcp-config` for servers the
  job needs), `--disable-slash-commands` when it needs no skills. Leave out `Task`/`Agent` when it starts
  no subagents.
- Output: a fixed format with no closing summary, only if nothing downstream parses the old output, or
  the parser changes in the same plan.
- If CLAUDE.md content moved into the stable block, stop the job from loading it twice:
  [reference/levers.md](reference/levers.md#claudemd-loaded-twice).

### 5. Show the diff

`git diff` for every changed file and the full text of every new file. Point out any line that is not a
pure move.

### 6. Benchmark

Write `bench/before.sh` (the job as it was) and `bench/after.sh` (as it is now). Format and how to rebuild
the old setup: [reference/benchmark.md](reference/benchmark.md); template:
[templates/setup.example.sh](templates/setup.example.sh). Pick 2-5 real tasks, tell the user the call
count (2 x tasks x runs), ask, then run it in the background:

```bash
bash <skill-dir>/scripts/bench.sh -n 2 bench/before.sh bench/after.sh <task> [<task>...]
```

Report mean cost, duration, cache reads, cache writes and output tokens with the change in percent, and
cost per task. Call a metric unproven when its before and after ranges overlap. Compare the saved answers
(`*.answer.txt`): do both setups find the same issues?

### 7. Close

State what changed and what the benchmark measured. Add one line: model and effort choice are often
bigger levers (most of Cloudflare's savings came from them), but this skill does not change them.
