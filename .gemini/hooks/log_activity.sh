#!/usr/bin/env bash

INPUT_DATA=$(cat)

if [ -z "$(echo "$INPUT_DATA" | tr -d ' \n\r\t')" ]; then
    echo "{}"
    exit 0
fi

CURRENT_DATE=$(date -u +"%Y-%m-%d")
CURRENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S%z")

if command -v jq >/dev/null 2>&1; then
    CWD=$(echo "$INPUT_DATA" | jq -r '.cwd // "."')
    TIMESTAMP=$(echo "$INPUT_DATA" | jq -r '.timestamp // empty')
    [ -z "$TIMESTAMP" ] && TIMESTAMP="$CURRENT_TIMESTAMP"
    ACTION=$(echo "$INPUT_DATA" | jq -r '.hook_event_name // "UnknownAction"')
    
    DETAILS=$(echo "$INPUT_DATA" | jq -c '
        {
            tool_name: .tool_name,
            tool_input: .tool_input,
            tool_response: .tool_response,
            session_id: .session_id,
            source: .source,
            reason: .reason,
            trigger: .trigger,
            notification_type: .notification_type
        } | with_entries(select(.value != null))
    ')
    if [ "$DETAILS" = "{}" ]; then
        DETAILS=$(echo "$INPUT_DATA" | jq -c '{raw_data_keys: keys}')
    fi
else
    # Fallback to python if jq is missing
    CWD=$(echo "$INPUT_DATA" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("cwd", "."))' 2>/dev/null || echo ".")
    TIMESTAMP=$(echo "$INPUT_DATA" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("timestamp", ""))' 2>/dev/null)
    [ -z "$TIMESTAMP" ] && TIMESTAMP="$CURRENT_TIMESTAMP"
    ACTION=$(echo "$INPUT_DATA" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("hook_event_name", "UnknownAction"))' 2>/dev/null)
    DETAILS=$(echo "$INPUT_DATA" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    d = {k: data[k] for k in ["tool_name", "tool_input", "tool_response", "session_id", "source", "reason", "trigger", "notification_type"] if k in data}
    if not d: d["raw_data_keys"] = list(data.keys())
    print(json.dumps(d))
except:
    print("{}")
' 2>/dev/null || echo "{}")
fi

LOG_DIR="${CWD}/.gemini/logs/${CURRENT_DATE}"
mkdir -p "$LOG_DIR" 2>/dev/null || true

ACTUAL_LOG_FILE="$LOG_DIR/actions.log"

echo "[$TIMESTAMP] ACTION: $ACTION | DETAILS: $DETAILS" >> "$ACTUAL_LOG_FILE" 2>/dev/null || true

echo "{}"
