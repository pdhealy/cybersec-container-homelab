#!/usr/bin/env python3

import os
import sys
import subprocess

def check_preflight():
    print("Running pre-flight checks...")
    
    # Check .env
    if not os.path.exists(".env"):
        print("Error: .env file missing. Please run setup_host.sh or create .env")
        sys.exit(1)
        
    # Check max_map_count
    try:
        with open("/proc/sys/vm/max_map_count", "r") as f:
            max_map_count = int(f.read().strip())
            if max_map_count < 262144:
                print(f"Error: vm.max_map_count is too low ({max_map_count}). Must be at least 262144.")
                sys.exit(1)
    except FileNotFoundError:
        print("Warning: Could not read /proc/sys/vm/max_map_count.")
        
    # Check swap
    try:
        with open("/proc/swaps", "r") as f:
            lines = f.readlines()
            if len(lines) > 1:
                print("Error: Swap is enabled. Disable it with 'sudo swapoff -a' for optimal performance.")
                sys.exit(1)
    except FileNotFoundError:
        pass
        
    print("Pre-flight checks passed.")

def run_compose(action, profile=None):
    cmd = ["docker", "compose"]
    if profile:
        cmd.extend(["--profile", profile])
    cmd.append(action)
    if action in ["up", "down"]:
        cmd.append("-d") if action == "up" else None
    
    print(f"Executing: {' '.join(cmd)}")
    subprocess.run(cmd, check=True)

def main():
    if len(sys.argv) < 2:
        print("Usage: ./lab_manager.py [up|down|build|status]")
        sys.exit(1)
        
    action = sys.argv[1]
    
    if action == "up":
        check_preflight()
        run_compose("up")
        print("Waiting for containers to initialize...")
        import time
        time.sleep(15)
        print("Running validation script...")
        subprocess.run(["./validation.sh"])
    elif action == "down":
        run_compose("down")
    elif action == "build":
        run_compose("build")
    elif action == "status":
        subprocess.run(["docker", "compose", "ps"])
    else:
        print(f"Unknown action: {action}")
        sys.exit(1)

if __name__ == "__main__":
    main()
