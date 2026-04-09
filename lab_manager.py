#!/usr/bin/env python3

import os
import sys
import subprocess
import time


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


def apply_docker_user_rules():
    """Ensure the host iptables allows the firewall container to route across bridges.

    Behaviour differs by Docker version:

    • Legacy Docker (uses DOCKER-ISOLATION-STAGE-1/2 chains): those chains DROP
      all inter-bridge forwarding unconditionally.  We must insert an ACCEPT rule
      into DOCKER-USER (evaluated first) to let the firewall container route.

    • Modern Docker 27+ (uses DOCKER-FORWARD chain): when enable_icc=false is set
      on a bridge network Docker automatically adds:
          -A DOCKER-FORWARD -i <br> -o <br>      -j DROP   (ICC block)
          -A DOCKER-FORWARD -i <br> ! -o <br>    -j ACCEPT (cross-bridge OK)
      Cross-bridge routing therefore works natively; a broad DOCKER-USER ACCEPT
      would override the ICC DROP and re-allow intra-network traffic — harmful.

    This function detects which model is active and acts accordingly.
    """
    print("Checking iptables chain model for cross-bridge routing...")

    # Modern Docker uses DOCKER-FORWARD; legacy uses DOCKER-ISOLATION-STAGE-1.
    modern = subprocess.run(
        ["sudo", "iptables", "-L", "DOCKER-FORWARD", "-n"],
        capture_output=True,
    ).returncode == 0
    legacy = subprocess.run(
        ["sudo", "iptables", "-L", "DOCKER-ISOLATION-STAGE-1", "-n"],
        capture_output=True,
    ).returncode == 0

    if modern and not legacy:
        print("Modern Docker detected (DOCKER-FORWARD chain present).")
        print("  enable_icc=false already provides both ICC isolation and cross-bridge")
        print("  routing via DOCKER-FORWARD — no DOCKER-USER rule needed.")
        return

    if not legacy:
        print("Warning: neither DOCKER-FORWARD nor DOCKER-ISOLATION-STAGE-1 found.")
        print("  Is the Docker daemon running?  Skipping iptables configuration.")
        return

    # Legacy path: insert the broad ACCEPT into DOCKER-USER idempotently.
    print("Legacy Docker detected (DOCKER-ISOLATION-STAGE-1 present).")
    check = subprocess.run(
        ["sudo", "iptables", "-C", "DOCKER-USER",
         "-i", "br-+", "-o", "br-+", "-j", "ACCEPT"],
        capture_output=True,
    )
    if check.returncode == 0:
        print("DOCKER-USER: Cross-bridge ACCEPT rule already present (idempotent).")
        return
    subprocess.run(
        ["sudo", "iptables", "-I", "DOCKER-USER",
         "-i", "br-+", "-o", "br-+", "-j", "ACCEPT"],
        check=True,
    )
    print("DOCKER-USER: Cross-bridge ACCEPT rule inserted for legacy Docker.")


def run_compose(action, profile=None):
    cmd = ["docker", "compose"]
    if profile:
        cmd.extend(["--profile", profile])
    cmd.append(action)
    if action == "up":
        cmd.append("-d")

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
        # Apply host-level iptables rules that allow the firewall container to
        # route across Docker bridge networks.  Must run after compose up so that
        # the DOCKER-USER chain (created by the Docker daemon) is available.
        apply_docker_user_rules()
        print("Waiting for containers to initialize (15s)...")
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
