# Baseline: typical setup. CLAUDE.md with date + branch at the top, default tools,
# diff piped on stdin, generic review prompt.
sed -e "s|__DATE__|$DATE|" -e "s|__BRANCH__|$BRANCH|" "$ROOT/baseline/CLAUDE.md.tmpl" > "$REPO/CLAUDE.md"
PROMPT="Review this diff, find bugs and risks, then write a summary."
STDIN_FILE="$DIFF"
CLAUDE_ARGS=()
