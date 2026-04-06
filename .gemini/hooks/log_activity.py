#!/usr/bin/env python3
import sys
import json
import os
import traceback
from datetime import datetime, timezone

LOG_FILE = os.path.join(os.getcwd(), '.gemini', 'logs', 'actions.log')
DEBUG_FILE = os.path.join(os.getcwd(), '.gemini', 'logs', 'hook_debug.log')

def main():
    try:
        input_data = sys.stdin.read()
        if not input_data.strip():
            print("{}")
            return
            
        data = json.loads(input_data)
        
        # Get cwd from payload if available, else use os.getcwd()
        cwd = data.get("cwd", os.getcwd())
        actual_log_file = os.path.join(cwd, '.gemini', 'logs', 'actions.log')
        
        timestamp = data.get("timestamp", datetime.now(timezone.utc).isoformat())
        action = data.get("hook_event_name", "UnknownAction")
        
        # Action details
        details = {}
        for k in ["tool_name", "tool_input", "tool_response", "session_id", "source", "reason", "trigger", "notification_type"]:
            if k in data:
                details[k] = data[k]
                
        if not details:
            details["raw_data_keys"] = list(data.keys())
            
        # Ensure log directory exists
        os.makedirs(os.path.dirname(actual_log_file), exist_ok=True)
        
        with open(actual_log_file, "a") as f:
            f.write(f"[{timestamp}] ACTION: {action} | DETAILS: {json.dumps(details)}\n")
            
    except Exception as e:
        # log errors to a debug file
        try:
            os.makedirs(os.path.dirname(DEBUG_FILE), exist_ok=True)
            with open(DEBUG_FILE, "a") as f:
                f.write(f"Error: {str(e)}\n{traceback.format_exc()}\n")
        except:
            pass
        
    # Always output empty JSON object required by Gemini CLI
    print("{}")

if __name__ == "__main__":
    main()
