# How a headless Claude Code request is laid out

## Cache rules (Anthropic API)

From the [prompt caching docs](https://platform.claude.com/docs/en/build-with-claude/prompt-caching):

- The cache is a prefix match. A request renders as `tools`, then `system`, then `messages`. One changed
  byte invalidates the cache for everything after it.
- A read can only land where an earlier request wrote a cache breakpoint. There are at most 4 breakpoints
  per request, and each looks back at most 20 blocks for an earlier entry.
- A write costs more than plain input (1.25x for the 5-minute TTL, 2x for the 1-hour TTL). A read costs
  about 0.1x, less on some newer models. Text that is written on every run and never read back is a
  surcharge, not a saving.
- A prefix shorter than the model's minimum (512 to 4096 tokens, by model) does not cache at all.
- Caches are kept per model and per workspace. A model switch starts from zero.

## What `claude -p` sends

Checked with Claude Code 2.1. Check your version with `bench.sh --probe`.

1. **Tools.** The built-in tools, then every MCP tool: project `.mcp.json`, user and local MCP config,
   plugins, and claude.ai connectors when the CLI is signed in with a claude.ai account. With no flags a
   machine with a few plugins and connectors can send more than 50 tools. Tools come first, so two setups
   with different tool sets share no cache at all.
2. **System prompt.** Claude Code's default prompt, then any `--append-system-prompt[-file]` text. Claude
   Code puts a cache breakpoint after the stable part, so appended text is read from cache on the next
   run, also from another branch or checkout. `--system-prompt[-file]` replaces the default prompt; that
   changes how the agent behaves, so do not switch a job to it.
3. **First user message.** The CLAUDE.md files, and AGENTS.md when it is loaded, plus the date Claude Code
   adds; then the prompt text; then Claude Code's listings: skills, subagents, MCP server instructions,
   deferred tools. This message has no breakpoint inside it. When the prompt changes (a new diff, a new
   task), the whole message is written to cache again, and that includes a large CLAUDE.md and every
   listing after the prompt.

Tested: a 10k-token block passed with `--append-system-prompt-file` was read from cache on the next run
from a different branch. The same block as CLAUDE.md was written again on every run with a new prompt.

## What follows from this

- Stable text goes into `--append-system-prompt-file`, not into CLAUDE.md or the prompt.
- Each tool, MCP server, skill and subagent the job does not use costs tokens on every run, and the
  listings that sit after the prompt are written again every time.
- The order inside the prompt (diff before or after date and branch) matters little for `claude -p`: the
  message is new on every run anyway. Put per-run values last regardless, so nothing stable ever sits after
  them. The order matters a lot for jobs that call the API directly and set their own breakpoints.
- `--exclude-dynamic-system-prompt-sections` moves cwd, env and git status out of the system prompt. It is
  meant for cache reuse across machines and users. In a test on one machine it did not raise cache reads,
  so only use it when the benchmark shows a gain.

## Per-run values to look for

Inside stable text (CLAUDE.md, AGENTS.md, system prompt files, skill and agent files, the fixed part of a
prompt template):

- dates and times: `2026-10-30`, `Last updated`, `As of`, `Today is`, `$(date ...)`, `new Date()`,
  `datetime.now()`
- git state: branch names, SHAs, `git rev-parse`, `git branch --show-current`, `git status` output
- CI values: `${{ github.* }}`, `GITHUB_RUN_ID`, `GITHUB_SHA`, `GITHUB_HEAD_REF`, `CI_COMMIT_*`,
  `BUILD_ID`, PR numbers
- random or unique values: UUIDs, `$RANDOM`, `mktemp` paths, session IDs, absolute paths of a temp checkout
- generated text: a "recent changes" section, file trees, test output, dependency lists that a script
  rewrites before each run
- unsorted output: JSON dumped without sorted keys, file lists without `sort`

Bulky text placed after per-run data: anything in the prompt template after the diff, and Claude Code's
own listings (skills, subagents, MCP tools) when the job does not need them.
