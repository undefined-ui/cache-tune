# Benchmark

`scripts/bench.sh` runs the same tasks through two setups with `claude -p --output-format json` and prints
cost, duration, turns and token counts per run, per task and on average. It runs in bash on macOS, Linux
and Windows Git Bash, and it needs `python3` (or `python`) or `node` to read the JSON.

```text
bench.sh [-n RUNS] [-o DIR] [--dry-run] BEFORE.sh AFTER.sh TASK [TASK...]
bench.sh --probe SETUP.sh [SETUP.sh...]
```

## Setup files

A setup file is bash. bench.sh sources it in a subshell, changes to `WORKDIR`, writes the output of
`build_prompt "$TASK"` to a file and sends that file to `claude -p "${CLAUDE_ARGS[@]}" --output-format json`
on stdin.

| Name | Required | Meaning |
|------|----------|---------|
| `CLAUDE_ARGS` | yes | bash array of flags for `claude -p`; do not put `--output-format` in it |
| `build_prompt` | yes | function that prints the prompt for the task in `$1` |
| `WORKDIR` | no | where claude runs, default `.`; relative to where you start bench.sh |
| `SETUP_DIR` | set by bench.sh | absolute directory of the setup file, for paths next to it |

Relative paths inside `CLAUDE_ARGS` and `build_prompt` resolve against `WORKDIR`. A task is any string:
a git range, a PR number, a file path. Only `build_prompt` reads it. See
[../templates/setup.example.sh](../templates/setup.example.sh).

## Rebuilding the old setup

`before.sh` must send what the job sent before the change, with the same model, flags and prompt order.

- If only the job script changed, copy its old flags and prompt code into `before.sh`.
- If files changed that Claude Code loads (CLAUDE.md, settings, `.mcp.json`, skills), run the old setup
  in a worktree of the commit before the change: `git worktree add ../<repo>-before <commit>` and
  `WORKDIR=../<repo>-before` in `before.sh`. Remove it when you are done: `git worktree remove ../<repo>-before`.
- Both setups must get the same task input. If a task is a git range, both worktrees share the history,
  so the same range gives the same diff.

Use `--dry-run` to print what each setup sends without calling claude. Read both prompts: the task data
must be the same, and only the assembly may differ.

## Probe

`--probe` sends `Reply with OK.` once per setup with `--model haiku --max-turns 1` added. It prints the
tools, MCP servers, skills and subagents the setup loads, and the fixed prefix: input + cache read + cache
write tokens for a one-line prompt. That is the overhead every run of the job pays before it reads a
single file. It costs a fraction of a cent per setup.

## Reading the results

- Rounds alternate the order (before first, then after first), so neither setup always gets a warm cache.
  The first run of each setup is usually the coldest.
- `cache_write` is the number to watch: a stable prefix shows up as `cache_read` on later runs.
- For each metric, the table shows whether the before and after ranges overlap. If they overlap, the
  change is unproven at this sample size. Say so, or run more rounds.
- Raw JSON, the prompt and the answer of every run stay in the results directory
  (`bench-results/<time>/` by default). Compare `before-*.answer.txt` with `after-*.answer.txt` to check
  that quality held.
- Prices come from `total_cost_usd`, which Claude Code computes at list price. On a subscription it is an
  estimate, not a bill.
