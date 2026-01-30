#!/bin/bash
# Context handoff detection hook for Ralph Loop
# Monitors context usage and injects handoff instructions when approaching limit

# Read hook input from stdin
INPUT=$(cat)

# Configuration (can be overridden via environment)
CONTEXT_THRESHOLD_PERCENT=${CONTEXT_THRESHOLD_PERCENT:-60}
MAX_CONTEXT_TOKENS=${MAX_CONTEXT_TOKENS:-200000}

# Extract transcript path from hook input
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

# If no transcript available, continue without action
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  echo '{"continue": true}'
  exit 0
fi

# Debounce: only warn once per session
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
DEBOUNCE_FILE="/tmp/ralph-context-handoff-warned-${SESSION_ID:-unknown}"

# If we've already warned this session, skip
if [ -f "$DEBOUNCE_FILE" ]; then
  echo '{"continue": true}'
  exit 0
fi

# Estimate tokens from transcript size (rough: ~4 chars per token)
CHARS=$(wc -c < "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")
TOKENS=$((CHARS / 4))
PERCENTAGE=$((TOKENS * 100 / MAX_CONTEXT_TOKENS))

# Check if we've exceeded the threshold
if [ "$PERCENTAGE" -ge "$CONTEXT_THRESHOLD_PERCENT" ]; then
  # Mark that we've warned this session (prevents spam)
  touch "$DEBOUNCE_FILE"

  HANDOFF_MSG="CONTEXT HANDOFF REQUIRED (~${PERCENTAGE}% context used)

Your context window is filling up. Before running out of space, you MUST perform a handoff:

1. **Write handoff file** alongside your PRD file.
   If PRD is \`/path/to/prd-feature.json\`, write to \`/path/to/prd-feature-handoff.json\`:

   {
     \"triggered_at\": \"$(date -Iseconds)\",
     \"context_percent\": ${PERCENTAGE},
     \"current_story\": \"<story ID you're working on>\",
     \"progress_summary\": \"<what you've accomplished so far>\",
     \"discoveries\": [
       \"<important finding about the codebase>\",
       \"<pattern or convention discovered>\"
     ],
     \"next_steps\": [
       \"<what still needs to be done for this story>\",
       \"<any blockers or considerations>\"
     ],
     \"files_modified\": [\"<list of files you changed>\"],
     \"files_to_review\": [\"<key files the next session should read first>\"]
   }

2. **Update progress file** with any completed work

3. **Commit partial work** if you made meaningful changes:
   git add -A && git commit -m \"wip: partial progress on <story ID>\"

4. **Output the handoff signal**:
   <promise>CONTEXT_FULL</promise>

Do this NOW. The next Ralph session will read your handoff file and continue where you left off."

  # Return with system message injection
  echo "{\"continue\": true, \"systemMessage\": $(echo "$HANDOFF_MSG" | jq -Rs .)}"
  exit 0
fi

# Context is fine, continue normally
echo '{"continue": true}'
