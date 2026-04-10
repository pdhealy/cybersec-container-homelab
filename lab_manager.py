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
    """Insert iptables rules to allow the firewall container to route packets
    across Docker bridge networks while maintaining strict ICC=false isolation.

    Docker's ICC=false drops intra-bridge traffic and also creates PREROUTING
    raw table drop rules for inter-bridge spoofing. We must insert exceptions
    to allow traffic destined for other subnets to be routed through the firewall
    container.

    The rules are inserted idempotently: if they already exist, no change is made.
    """
    print("Configuring iptables for cross-bridge routing while maintaining icc=false...")

    rules = [
        # Bypass raw table drops for routed cross-subnet traffic
        ["-t", "raw", "-I", "PREROUTING", "-s", "10.10.10.0/24", "!", "-d", "10.10.10.0/24", "-j", "ACCEPT"],
        ["-t", "raw", "-I", "PREROUTING", "-s", "10.10.20.0/24", "!", "-d", "10.10.20.0/24", "-j", "ACCEPT"],
        ["-t", "raw", "-I", "PREROUTING", "-s", "10.10.30.0/24", "!", "-d", "10.10.30.0/24", "-j", "ACCEPT"],
        
        # Bypass raw table drops for traffic explicitly to the firewall's IP
        ["-t", "raw", "-I", "PREROUTING", "-d", "10.10.10.254", "-j", "ACCEPT"],
        ["-t", "raw", "-I", "PREROUTING", "-d", "10.10.20.254", "-j", "ACCEPT"],
        ["-t", "raw", "-I", "PREROUTING", "-d", "10.10.30.254", "-j", "ACCEPT"],

        # Allow cross-subnet traffic through DOCKER-USER (bypasses DOCKER-FORWARD drops)
        ["-t", "filter", "-I", "DOCKER-USER", "-s", "10.10.10.0/24", "!", "-d", "10.10.10.0/24", "-j", "ACCEPT"],
        ["-t", "filter", "-I", "DOCKER-USER", "-s", "10.10.20.0/24", "!", "-d", "10.10.20.0/24", "-j", "ACCEPT"],
        ["-t", "filter", "-I", "DOCKER-USER", "-s", "10.10.30.0/24", "!", "-d", "10.10.30.0/24", "-j", "ACCEPT"],

        # Allow containers to talk to the firewall's IP directly in DOCKER-USER
        ["-t", "filter", "-I", "DOCKER-USER", "-d", "10.10.10.254", "-j", "ACCEPT"],
        ["-t", "filter", "-I", "DOCKER-USER", "-d", "10.10.20.254", "-j", "ACCEPT"],
        ["-t", "filter", "-I", "DOCKER-USER", "-d", "10.10.30.254", "-j", "ACCEPT"],
        ["-t", "filter", "-I", "DOCKER-USER", "-s", "10.10.10.254", "-j", "ACCEPT"],
        ["-t", "filter", "-I", "DOCKER-USER", "-s", "10.10.20.254", "-j", "ACCEPT"],
        ["-t", "filter", "-I", "DOCKER-USER", "-s", "10.10.30.254", "-j", "ACCEPT"],
    ]

    for rule in rules:
        check_cmd = ["sudo", "iptables", "-C", rule[1]] + rule[2:]
        if "-t" in rule:
            check_cmd = ["sudo", "iptables", "-t", rule[1], "-C", rule[3]] + rule[4:]
        
        check = subprocess.run(check_cmd, capture_output=True)
        if check.returncode != 0:
            subprocess.run(["sudo", "iptables"] + rule, check=True)

    # Remove the broken old rule if it exists (which broke strict ICC=false)
    subprocess.run(["sudo", "iptables", "-D", "DOCKER-USER", "-i", "br-+", "-o", "br-+", "-j", "ACCEPT"], capture_output=True)
    print("DOCKER-USER/raw PREROUTING: Cross-bridge ACCEPT rules applied.")


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
        subprocess.run(["bash", "-x", "./validation.sh"], check=True)
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
