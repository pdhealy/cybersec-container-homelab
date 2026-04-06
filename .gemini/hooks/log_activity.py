#!/usr/bin/env python3
import sys
import json
import os
from datetime import datetime

LOG_FILE = os.path.join(os.getcwd(), 'logs', 'gemini_activity.log')

def main():
    try:
        input_data = sys.stdin.read()
        if not input_data.strip():
            print("{}")
            return
            
        data = json.loads(input_data)
        
        timestamp = data.get("timestamp", datetime.utcnow().isoformat() + "Z")
        action = data.get("hook_event_name", "UnknownAction")
        
        # Action details
        details = {}
        for k in ["tool_name", "tool_input", "tool_response", "session_id", "source", "reason", "trigger", "notification_type"]:
            if k in data:
                details[k] = data[k]
                
        if not details:
            details["raw_data_keys"] = list(data.keys())
            
        # Ensure log directory exists
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        
        with open(LOG_FILE, "a") as f:
            f.write(f"[{timestamp}] ACTION: {action} | DETAILS: {json.dumps(details)}\n")
            
    except Exception as e:
        # ignore errors to not break the hook
        pass
        
    # Always output empty JSON object required by Gemini CLI
    print("{}")

if __name__ == "__main__":
    main()
