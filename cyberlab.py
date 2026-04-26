#!/usr/bin/env python3

import os
import sys
import subprocess
import time
import argparse
import glob
import yaml
import questionary

def check_preflight():
    print("Running pre-flight checks...")

    if not os.path.exists(".env"):
        print("Error: .env file missing. Please run setup_host.sh or create .env")
        sys.exit(1)

    try:
        with open("/proc/sys/vm/max_map_count", "r") as f:
            max_map_count = int(f.read().strip())
            if max_map_count < 262144:
                print(f"Error: vm.max_map_count is too low ({max_map_count}). Must be at least 262144.")
                sys.exit(1)
    except FileNotFoundError:
        print("Warning: Could not read /proc/sys/vm/max_map_count.")

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
    print("Configuring iptables for cross-bridge routing while maintaining icc=false...")

    rules = [
        ["-t", "raw", "-I", "PREROUTING", "-s", "10.10.10.0/24", "!", "-d", "10.10.10.0/24", "-j", "ACCEPT"],
        ["-t", "raw", "-I", "PREROUTING", "-s", "10.10.20.0/24", "!", "-d", "10.10.20.0/24", "-j", "ACCEPT"],
        ["-t", "raw", "-I", "PREROUTING", "-s", "10.10.30.0/24", "!", "-d", "10.10.30.0/24", "-j", "ACCEPT"],
        ["-t", "raw", "-I", "PREROUTING", "-d", "10.10.10.254", "-j", "ACCEPT"],
        ["-t", "raw", "-I", "PREROUTING", "-d", "10.10.20.254", "-j", "ACCEPT"],
        ["-t", "raw", "-I", "PREROUTING", "-d", "10.10.30.254", "-j", "ACCEPT"],
        ["-t", "filter", "-I", "DOCKER-USER", "-s", "10.10.10.0/24", "!", "-d", "10.10.10.0/24", "-j", "ACCEPT"],
        ["-t", "filter", "-I", "DOCKER-USER", "-s", "10.10.20.0/24", "!", "-d", "10.10.20.0/24", "-j", "ACCEPT"],
        ["-t", "filter", "-I", "DOCKER-USER", "-s", "10.10.30.0/24", "!", "-d", "10.10.30.0/24", "-j", "ACCEPT"],
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

    subprocess.run(["sudo", "iptables", "-D", "DOCKER-USER", "-i", "br-+", "-o", "br-+", "-j", "ACCEPT"], capture_output=True)
    print("DOCKER-USER/raw PREROUTING: Cross-bridge ACCEPT rules applied.")

def get_presets():
    presets = []
    for f in sorted(glob.glob("presets/*.yml")):
        with open(f, 'r') as file:
            preset = yaml.safe_load(file)
            presets.append((f, preset))
    return presets

def write_active_lab_env(profiles):
    with open(".active_lab.env", "w") as f:
        for p in profiles:
            f.write(f"ACTIVE_{p.upper()}=true\n")
    print("Generated .active_lab.env")

def interactive_mode():
    mode = questionary.select(
        "Choose a deployment mode:",
        choices=["Preset (Recommended)", "Manual Configuration"]
    ).ask()

    if not mode:
        sys.exit(0)

    profiles = []
    if mode.startswith("Preset"):
        presets = get_presets()
        choices = [f"{p[1]['name']} - {p[1]['description']}" for p in presets]
        selection = questionary.select("Select a preset:", choices=choices).ask()
        if not selection:
            sys.exit(0)
        idx = choices.index(selection)
        profiles = presets[idx][1].get("profiles", [])
    else:
        attackers = questionary.checkbox(
            "Select Attacker Node(s):",
            choices=["kali", "atomicred"]
        ).ask()
        
        targets = questionary.checkbox(
            "Select Vulnerable Target(s):",
            choices=["metasploitable2", "ubuntu"]
        ).ask()
        
        siems = questionary.checkbox(
            "Select SIEM(s):",
            choices=["wazuh", "splunk"]
        ).ask()

        if attackers is None or targets is None or siems is None:
            sys.exit(0)

        profiles = attackers + targets + siems

    return profiles

def run_compose(action, profiles=None):
    cmd = ["docker", "compose"]
    if action == "down":
        cmd.extend(["--profile", "*"])
    elif profiles:
        for p in profiles:
            cmd.extend(["--profile", p])
    cmd.append(action)
    if action == "up":
        cmd.append("-d")

    print(f"Executing: {' '.join(cmd)}")
    subprocess.run(cmd, check=True)

def main():
    parser = argparse.ArgumentParser(description="Cyber Homelab Management CLI")
    parser.add_argument("action", nargs="?", choices=["up", "down", "build", "status"], default=None, help="Action to perform")
    parser.add_argument("--preset", type=str, help="Path to a preset YAML file to use directly")
    parser.add_argument("--profiles", type=str, help="Comma-separated list of profiles for manual deployment")
    
    args = parser.parse_args()

    action = args.action

    if not action:
        action = questionary.select(
            "What would you like to do?",
            choices=["up", "down", "build", "status"]
        ).ask()
        if not action:
            sys.exit(0)

    if action == "up":
        check_preflight()
        
        profiles = []
        if args.preset:
            with open(args.preset, 'r') as f:
                preset = yaml.safe_load(f)
                profiles = preset.get("profiles", [])
        elif args.profiles:
            profiles = args.profiles.split(",")
        else:
            profiles = interactive_mode()
            if not profiles:
                print("No profiles selected. Exiting.")
                sys.exit(0)

        write_active_lab_env(profiles)
        run_compose("up", profiles)
        apply_docker_user_rules()
        print("Waiting for containers to initialize (15s)...")
        time.sleep(15)
        print("Running validation script...")
        subprocess.run(["bash", "-x", "./validation.sh"], check=True)
        print("Running attack logging integration test...")
        subprocess.run(["bash", "-x", "./tests/test_attack_logging.sh"], check=True)
    elif action == "down":
        run_compose("down")
        if os.path.exists(".active_lab.env"):
            os.remove(".active_lab.env")
    elif action == "build":
        run_compose("build")
    elif action == "status":
        subprocess.run(["docker", "compose", "ps"])

if __name__ == "__main__":
    main()
