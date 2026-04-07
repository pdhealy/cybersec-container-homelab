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
    """Insert a rule into the DOCKER-USER iptables chain so the firewall container
    can route packets across Docker bridge networks.

    Docker's DOCKER-ISOLATION-STAGE chains block inter-bridge forwarding by
    default.  The DOCKER-USER chain is evaluated *before* those chains, so an
    ACCEPT rule here lets the firewall container perform L3 routing while still
    allowing per-bridge ICC=false isolation to enforce intra-network separation.

    The rule is inserted idempotently: if it already exists no change is made.
    Requires the Docker daemon (and therefore the DOCKER-USER chain) to be
    running before this function is called.
    """
    print("Configuring DOCKER-USER iptables chain for cross-bridge routing...")

    # Verify the DOCKER-USER chain exists (implies Docker daemon is running).
    probe = subprocess.run(
        ["sudo", "iptables", "-L", "DOCKER-USER", "-n"],
        capture_output=True,
    )
    if probe.returncode != 0:
        print("Warning: DOCKER-USER chain not found. Skipping rule insertion.")
        print("  Ensure the Docker daemon is running and re-run 'lab_manager.py up'.")
        return

    # Idempotency check — iptables -C exits 0 if the rule already exists.
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
    print("DOCKER-USER: Cross-bridge ACCEPT rule inserted successfully.")


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
