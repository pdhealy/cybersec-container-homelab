# Cyber Homelab Project

## Directory Overview
This directory is currently in the planning and design phase for building a secure, containerized cybersecurity homelab. The homelab will be a 3-tier network architecture implemented entirely within Docker, designed to develop practical security skills safely. It emphasizes enterprise-grade production-level quality, focusing heavily on container security, least privilege, resource tuning, and strict network isolation.

Currently, the directory primarily holds planning documentation. In the future, it will house Infrastructure as Code (IaC) scripts, Docker Compose files, custom Dockerfiles, and orchestration scripts.

## Key Files
*   `.planning/plan.md`: The original conceptual baseline and architectural blueprint. It details the shift from an Nginx-based firewall to an Alpine Linux `iptables` container, outlines the non-root/privilege constraints for attacker/target nodes, and proposes the initial directory structure and `lab_manager.py` orchestration script.
*   `.planning/plan_phased.md`: An advanced, phased execution plan that critiques the original plan. It introduces strict production-grade security standards such as explicit capability dropping (`cap_drop: [ALL]`), `no-new-privileges:true`, read-only filesystems, strict non-root execution, cryptographic SHA256 pinning for images, host kernel tuning (for Wazuh/OpenSearch), disabled Inter-Container Communication (ICC), and programmatic validation via the Gemini CLI.

## Usage
The contents of this directory are intended to be used as a roadmap for systematically building out the cybersecurity homelab. 
Future interactions should focus on executing the phases outlined in `.planning/plan_phased.md`:

1.  **Phase 1 (Foundation):** Set up the workspace directory structure, secure environment variables (`.env`), and host kernel tuning (`setup_host.sh`).
2.  **Phase 2 (Core Network):** Configure isolated Docker networks (`external_net`, `dmz_net`, `internal_net`), build the Alpine Firewall container with hardened rules, and deploy Pi-Hole for DNS.
3.  **Phase 3 (Telemetry & Targets):** Deploy the Wazuh SIEM with production tuning and the vulnerable target (`vulnerables/metasploit-vulnerability-emulator`).
4.  **Phase 4 (Attacker Enclave):** Build the Kali Linux attacker node with DevContainer integration for VS Code.
5.  **Phase 5 (Orchestration):** Refine the Python orchestrator (`lab_manager.py`) for managing the lab lifecycle via Docker Compose profiles.
6.  **Phase 6 (Validation):** Validate the entire setup using Gemini CLI to ensure enterprise-grade security standards are met.
