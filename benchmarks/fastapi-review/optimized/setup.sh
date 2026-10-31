# Optimized: static part (review rules + project notes) moved into the system prompt, byte-stable
# across jobs; per-job details (branch, date, diff) come last in the user message. No CLAUDE.md.
# Only the tools the reviewer used in the baseline; no MCP servers, skills or subagents.
JOB=$ROOT/runs/.job-$VER-$N.txt
{ printf 'Branch: %s\nDate: %s\n\n' "$BRANCH" "$DATE"; cat "$DIFF"; } > "$JOB"
PROMPT="Review this diff."
STDIN_FILE="$JOB"
SYSTEM_FILE="$ROOT/optimized/system-static.md"
# Git Bash: claude is a Windows program and needs a Windows path (MSYS_NO_PATHCONV=1 is set).
command -v cygpath >/dev/null 2>&1 && SYSTEM_FILE=$(cygpath -w "$SYSTEM_FILE")
CLAUDE_ARGS=(--append-system-prompt-file "$SYSTEM_FILE"
             --tools "Read,Grep,Glob,Bash" --strict-mcp-config --disable-slash-commands)
