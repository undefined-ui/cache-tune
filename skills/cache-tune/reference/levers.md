# Levers and how to apply them safely

Each lever changes how the prompt is assembled, not what the agent is told to do. Before you apply a
lever, check the condition in its section. If you are not sure the condition holds, ask the user.

## Stable block

- Move the job's rules and project notes, word for word and in the same order, into one file, for example
  `.claude/prompts/review.md`.
- Pass it with `--append-system-prompt-file <file>`. This keeps Claude Code's default system prompt. Do
  not use `--system-prompt[-file]` unless the job already uses it: replacing the default prompt changes
  behavior.
- Take every per-run value out of it (see [prompt-layout.md](prompt-layout.md#per-run-values-to-look-for))
  and put the values in the prompt tail. If a rule depends on a value ("PRs after 2026-01-01 must ..."),
  that is a fixed rule, not a per-run value: leave it.
- Keep it byte-identical: commit the file, do not generate it per run, use LF endings
  (`*.md text eol=lf` in `.gitattributes`).

## Prompt tail

Build the prompt in this order: the task line, then the inputs (diff, files, issue text), then per-run
values (branch, date, PR number, run ID) last. Nothing stable comes after the per-run part.

## Tool list

| Flag | Effect |
|------|--------|
| `--tools "Read,Grep,Glob,Bash"` | only these built-in tools exist; `""` means none |
| `--strict-mcp-config` | ignore all MCP config except `--mcp-config` files; this also drops claude.ai connectors |
| `--mcp-config <file>` | the MCP servers the job needs, one JSON file for the job |
| `--disable-slash-commands` | no skills and no slash commands, so no skill listing |
| leave `Task`/`Agent` out of `--tools` | no subagents, so no subagent listing |

Do not change `--allowedTools`, `--disallowedTools`, `--permission-mode` or the permissions in settings.
`--tools` decides which tools exist; permissions decide which calls may run. They are different things.

If the job's prompt is a slash command (`claude -p "/review"`), `--disable-slash-commands` breaks it.
Either keep skills on, or move the command's text word for word into the stable block and the prompt
first. That is a pure move, and it goes in the plan as its own item.

### Decide what the job uses

1. Read the job's prompt and rules. A review job reads, searches and runs git: `Read,Grep,Glob,Bash`. A
   job that fixes code also needs `Edit,Write`. A job that posts comments needs the tool or MCP server it
   posts with.
2. Read `--allowedTools` and the permission rules. A tool the job may call is a tool it uses.
3. Look at past runs. Transcripts are in `~/.claude/projects/<project>/*.jsonl` locally, and in the logs
   of CI runs that use `--output-format stream-json`. Count the tool calls:
   `grep -o '"name":"[A-Za-z_]*"' run.jsonl | sort | uniq -c`.
4. If a tool shows up in none of these, it is a candidate to remove. Put it in the plan with that
   evidence. If the evidence is thin, keep the tool and say so.

## CLAUDE.md loaded twice

When the stable block holds text from CLAUDE.md, Claude Code still loads CLAUDE.md into the first user
message. Choose one fix:

1. **Split.** Move only the job's own rules into the stable block and leave the general notes in
   CLAUDE.md for interactive use. If what stays is small, let the job load it.
2. **Append CLAUDE.md itself.** Pass `--append-system-prompt-file CLAUDE.md` and add
   `--setting-sources user`, so the project CLAUDE.md is not loaded again. This flag also skips
   `.claude/settings.json` and `.claude/settings.local.json` (permissions, hooks, env). If the job needs
   them, add `--settings .claude/settings.json`. An appended file is sent as is: `@path` imports in it are
   not expanded, so inline the imported files or keep them loading the normal way.
3. **`--bare`.** It skips CLAUDE.md discovery, hooks, plugins and auto-memory, and it accepts only
   `ANTHROPIC_API_KEY` or an `apiKeyHelper` passed with `--settings` (no OAuth sign-in). Use it only when
   the job has no hooks or plugins it depends on.

Check the result with `bench.sh --probe`: the fixed prefix drops by about the size of CLAUDE.md.

## Fixed output format

Put the format in the stable block, for example for a review job:

```text
Output only the findings, one per line:
<severity> <file>:<line> <problem>. Fix: <fix>
<severity> is high, medium or low. If there are no findings, output: No findings.
Do not write a preamble or a closing summary.
```

Keep the job's rules about what counts as a finding. Before you change the format, find every consumer of
the output: `> file`, `| gh pr comment`, `jq .result`, a parser in the CI step. If something parses the
old format, keep that format or change the parser in the same plan.

## claude-code-action

Flags go in the `claude_args` input and the prompt in `prompt`. The action starts its own MCP servers (for
example the ones that post comments). The job uses them, so they must stay. After you add
`--strict-mcp-config`, check the init line in the run log: the action's servers must still be listed.

## Direct API and Agent SDK

The same rules apply. Put the stable system block first with a `cache_control` breakpoint at its end, keep
the tool list fixed and sorted, and put every per-run value after the last breakpoint. In the Agent SDK,
the matching options are the system prompt append, the tool lists, the MCP servers and the setting
sources. Check its docs for the option names of your SDK version.

## Plan template

```markdown
## Plan: <job name>

Job: <command and file>. Runs: <how often, if known>.

| # | Change | Files | Why it saves | Risk |
|---|--------|-------|--------------|------|
| 1 | Move the review rules (CLAUDE.md:12-80) word for word to .claude/prompts/review.md, pass it with --append-system-prompt-file | CLAUDE.md, .claude/prompts/review.md, scripts/review.sh | the rules are read from cache instead of written on every run | none: same text, same order |
| 2 | Drop "Last updated: <date>" from the moved text | .claude/prompts/review.md | keeps the block byte-identical | no rule uses the date |
| 3 | Move branch and date after the diff | scripts/review.sh | nothing stable after per-run data | none |
| 4 | --tools "Read,Grep,Glob,Bash" --strict-mcp-config --disable-slash-commands | scripts/review.sh | no unused tools, MCP tools or listings | 30 past runs used only these tools |
| 5 | Fixed findings format, no closing summary | .claude/prompts/review.md | fewer output tokens | output goes to gh pr comment as plain text |

Stays the same: model, effort, max turns, permissions, rule text, hooks, where the output goes.

Benchmark: before = <commit> in a git worktree, after = the working tree. Tasks: <list>. 2 runs each, so
<N> claude calls.

Apply this plan?
```
