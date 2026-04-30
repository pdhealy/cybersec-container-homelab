#!/usr/bin/env bash
set -u

INPUT_DATA="$(cat)"

if [[ -z "${INPUT_DATA//[[:space:]]/}" ]]; then
  echo "{}"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "{}"
  exit 0
fi

CURRENT_DATE="$(date -u +%Y-%m-%d)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/../logs/$CURRENT_DATE"
LOG_FILE="$LOG_DIR/tool-activity.jsonl"
mkdir -p "$LOG_DIR" 2>/dev/null || true

HOOK_EVENT="preToolUse"
if echo "$INPUT_DATA" | jq -e 'has("toolResult")' >/dev/null 2>&1; then
  HOOK_EVENT="postToolUse"
fi

TOOL_ARGS_PARSED="$(echo "$INPUT_DATA" | jq -c '
  (.toolArgs // "{}") as $raw
  | (
      try ($raw | fromjson)
      catch {"_rawToolArgs": $raw}
    )
')"

LOG_ENTRY="$(echo "$INPUT_DATA" | jq -c --arg event "$HOOK_EVENT" --argjson args "$TOOL_ARGS_PARSED" '
  {
    loggedAt: (now | todateiso8601),
    sourceTimestamp: (.timestamp // null),
    hookEvent: $event,
    cwd: (.cwd // null),
    toolName: (.toolName // null),
    toolArgs: $args,
    bashCommand: (if .toolName == "bash" then ($args.command // null) else null end),
    toolResultType: (.toolResult.resultType // null),
    toolResultPreview: (
      if (.toolResult.textResultForLlm // null) == null
      then null
      else ((.toolResult.textResultForLlm | tostring)[:500])
      end
    )
  }
  | with_entries(select(.value != null))
')"

echo "$LOG_ENTRY" >> "$LOG_FILE" 2>/dev/null || true

echo "{}"
