# Example bench.sh setup: a PR review job after cache-tune.
# bench.sh sources this file in a subshell, changes to WORKDIR and runs
#   build_prompt "$TASK" | claude -p "${CLAUDE_ARGS[@]}" --output-format json
# The matching before.sh copies the job's old flags and prompt code exactly.

# Where claude runs, relative to where bench.sh starts. For the old setup this
# can be a git worktree of the commit before the change.
WORKDIR=.

CLAUDE_ARGS=(
  --model sonnet                                          # same as the job
  --append-system-prompt-file .claude/prompts/review.md   # stable rules, byte-identical
  --tools "Read,Grep,Glob,Bash"                           # only what the job uses
  --strict-mcp-config                                     # no MCP servers or connectors
  --disable-slash-commands                                # no skill listing
  --allowedTools "Bash(git diff:*)" "Bash(git log:*)"     # same permissions as the job
)

# $1 is the task, here a git range such as main~1..main.
# Task first, then the diff, then the per-run values last.
build_prompt() {
  printf 'Review this change.\n\n'
  git diff "$1"
  printf '\nRange: %s\nDate: %s\n' "$1" "$(date +%F)"
}
