#!/usr/bin/env bash
# Read-only audit: what a project's Claude Code jobs load on every run, and
# which lines hold per-run values. Prints facts and candidate lines; the skill
# turns them into findings. Usage: audit.sh [PROJECT_DIR]
set -uo pipefail

ROOT=${1:-.}
[ -d "$ROOT" ] || { echo "audit.sh: not a directory: $ROOT" >&2; exit 1; }
SELF=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1
HERE=$(pwd)

# Skip this skill's own files when it is installed inside the project.
case $SELF in "$HERE"/*) SELF_REL=${SELF#"$HERE"/}/ ;; *) SELF_REL="" ;; esac
skip_self() { awk -v p="$SELF_REL" 'p == "" || index($0, p) != 1'; }

PRUNE_DIRS=".git node_modules bench-results .venv venv dist build vendor target"
GREP_EXCLUDE=()
for d in $PRUNE_DIRS; do GREP_EXCLUDE+=(--exclude-dir="$d"); done

JOB_TYPES=(--include='*.sh' --include='*.bash' --include='*.zsh' --include='*.ps1' --include='*.py'
  --include='*.js' --include='*.mjs' --include='*.cjs' --include='*.ts' --include='*.yml'
  --include='*.yaml' --include='*.json' --include='*.toml' --include='Makefile' --include='*.mk'
  --include='Dockerfile' --include='justfile' --include='crontab')

# Values that change from run to run. Matched in text that should be stable.
DYN='[12][0-9]{3}-[01][0-9]-[0-3][0-9]|[0-2][0-9]:[0-5][0-9]:[0-5][0-9]|[Ll]ast updated|[Uu]pdated:|[Aa]s of |[Tt]oday is|[Cc]urrent date|[Gg]enerated (at|on)|\$\(date|`date|datetime\.now|Date\.now|new Date\(|[Bb]ranch:|GITHUB_(RUN_ID|RUN_NUMBER|SHA|REF|HEAD_REF|BASE_REF)|CI_COMMIT|BUILD_ID|\$\{\{ *github\.|[0-9a-f]{40}|uuid|\$RANDOM|mktemp|git rev-parse|git branch --show-current'

# Lines that start a headless Claude run.
JOB='claude[[:space:]](.*[[:space:]])?(-p|--print)([^a-zA-Z0-9_-]|$)|claude-code-action|claude_args|claude-agent-sdk|claude_agent_sdk|ClaudeSDKClient'

# files NAME... : project files with these names, minus vendored and generated dirs.
files() {
  local expr=() prune=() n
  for n in "$@"; do expr+=(-o -name "$n"); done
  for n in $PRUNE_DIRS; do prune+=(-o -name "$n"); done
  find . \( "${prune[@]:1}" \) -prune -o -type f \( "${expr[@]:1}" \) -print 2>/dev/null |
    sed 's|^\./||' | skip_self | sort
}

size_line() { # FILE
  local b l
  b=$(wc -c <"$1" | tr -d ' ')
  l=$(wc -l <"$1" | tr -d ' ')
  printf '  %-50s %7s bytes  ~%6s tokens  %5s lines\n' "$1" "$b" "$((b / 4))" "$l"
}

show() { cut -c1-180 | sed 's/^/  /'; }

echo "Project: $HERE"
echo

echo "== Context files (sent with every run that loads them)"
CONTEXT=$(files CLAUDE.md CLAUDE.local.md AGENTS.md)
if [ -n "$CONTEXT" ]; then
  while IFS= read -r f; do size_line "$f"; done <<<"$CONTEXT"
else
  echo "  none in the project"
fi
[ -f "$HOME/.claude/CLAUDE.md" ] && echo "  user level (this machine only, usually not in CI):" && size_line "$HOME/.claude/CLAUDE.md"
if [ -n "$CONTEXT" ]; then
  IMPORTS=$(while IFS= read -r f; do grep -nHE '(^|[[:space:]])@[~./A-Za-z0-9_-]+' "$f"; done <<<"$CONTEXT")
  [ -n "$IMPORTS" ] && echo "  @imports (expanded into the context too):" && printf '%s\n' "$IMPORTS" | show
fi
echo

echo "== Settings and MCP config"
SETTINGS_KEYS='"(enabledPlugins|enableAllProjectMcpServers|enabledMcpjsonServers|mcpServers|hooks|outputStyle|env|permissions|model|apiKeyHelper)"'
found=0
for f in .claude/settings.json .claude/settings.local.json .mcp.json "$HOME/.claude/settings.json"; do
  [ -f "$f" ] || continue
  found=1
  size_line "$f"
  grep -nE "$SETTINGS_KEYS" "$f" | show
done
[ -f "$HOME/.claude.json" ] && grep -q '"mcpServers"' "$HOME/.claude.json" &&
  echo "  ~/.claude.json has mcpServers entries (user or local scope); they load on this machine"
[ "$found" = 1 ] || echo "  none found"
echo "  claude.ai connectors also load when the CLI is signed in with a claude.ai account."
echo "  To see the real list: bench.sh --probe <setup.sh>"
echo

echo "== Skills, subagents, commands"
for spec in ".claude/skills:SKILL.md" ".claude/agents:*.md" ".claude/commands:*.md"; do
  dir=${spec%%:*}
  pat=${spec#*:}
  for base in . "$HOME"; do
    [ -d "$base/$dir" ] || continue
    list=$(find "$base/$dir" -name "$pat" -type f 2>/dev/null | sed 's|^\./||' | skip_self | sort)
    n=$(printf '%s' "$list" | grep -c . || true)
    label=$dir
    [ "$base" = "$HOME" ] && label="~/$dir (user level)"
    printf '  %-34s %3s files\n' "$label" "$n"
  done
done
echo "  Enabled plugins can add more skills, subagents and MCP servers (see enabledPlugins above)."
echo

echo "== Headless jobs"
JOBS=$(grep -rnE "${GREP_EXCLUDE[@]}" "${JOB_TYPES[@]}" "$JOB" . 2>/dev/null | sed 's|^\./||' | skip_self)
if [ -n "$JOBS" ]; then
  printf '%s\n' "$JOBS" | show
else
  echo "  none found (searched shell, Python, JS/TS, YAML, JSON, TOML, Makefiles)"
fi
API=$(grep -rlE "${GREP_EXCLUDE[@]}" "${JOB_TYPES[@]}" 'from anthropic import|import anthropic|@anthropic-ai/sdk' . 2>/dev/null |
  sed 's|^\./||' | skip_self)
[ -n "$API" ] && echo "  direct Anthropic API callers (same rules, own breakpoints):" && printf '%s\n' "$API" | show
echo

JOB_FILES=$(printf '%s\n' "$JOBS" | cut -d: -f1 | grep . | sort -u)
PROMPT_FILES=$(printf '%s\n' "$JOBS" | grep -oE -- '--(append-)?system-prompt-file[= ]+[^ "'\'']+' |
  sed -E 's/^--(append-)?system-prompt-file[= ]+//' | sort -u)

echo "== System prompt files used by jobs"
if [ -n "$PROMPT_FILES" ]; then
  while IFS= read -r f; do
    if [ -f "$f" ]; then size_line "$f"; else echo "  $f (not found from the project root; may be relative to the job's cwd)"; fi
  done <<<"$PROMPT_FILES"
else
  echo "  none"
fi
echo

echo "== Per-run values inside stable text"
STABLE=$( {
  printf '%s\n' "$CONTEXT"
  printf '%s\n' "$PROMPT_FILES"
  files SKILL.md | grep '^\.claude/skills/'
  find .claude/agents .claude/commands -name '*.md' -type f 2>/dev/null | sed 's|^\./||' | skip_self
} | grep . | sort -u)
hits=""
if [ -n "$STABLE" ]; then
  hits=$(while IFS= read -r f; do [ -f "$f" ] && grep -nHE "$DYN" "$f"; done <<<"$STABLE")
fi
if [ -n "$hits" ]; then printf '%s\n' "$hits" | show; else echo "  none found"; fi
echo

echo "== Per-run values in job files (check they come last in the prompt)"
if [ -n "$JOB_FILES" ]; then
  hits=$(while IFS= read -r f; do [ -f "$f" ] && grep -nHE "$DYN|git (diff|log|status|show)" "$f"; done <<<"$JOB_FILES")
  if [ -n "$hits" ]; then printf '%s\n' "$hits" | show; else echo "  none found"; fi
else
  echo "  no job files"
fi
echo
echo "Token counts are bytes/4, a rough estimate."
