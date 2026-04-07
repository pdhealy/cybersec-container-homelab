# Cyber Homelab Implementation Status

## Overview
The phased execution plan (`plan_phased.md`) for the secure Cyber Homelab has been largely implemented, focusing on enterprise-grade security standards, least privilege, and container isolation. The foundational infrastructure, core networking, telemetry targets, attacker enclave, and orchestration scripts have been created according to the architectural blueprint.

## Implemented Phases

### Phase 1: Foundation & Infrastructure as Code (IaC) Setup
*   **Directory Structure:** Created the required directories (`attacker-node/`, `vulnerable-target/`, `firewall/`, `siem/`, `pi-hole/`, `.devcontainer/`).
*   **Host Kernel Tuning:** Developed `setup_host.sh` to apply necessary `sysctl` settings (e.g., `vm.max_map_count=262144`), disable swap, and disable IPv6.
*   **Secret Management:** Generated a `.env` file for sensitive credentials (`PIHOLE_PASSWORD`, `WAZUH_ADMIN_PASSWORD`, `ATTACKER_PASSWORD`) and added it to `.gitignore`.

### Phase 2: Core Network & Perimeter Security
*   **Docker Networks:** Defined `external_net`, `dmz_net`, and `internal_net` in `docker-compose.yml` with IPv6 disabled. Inter-Container Communication (ICC) was initially disabled but temporarily re-enabled due to routing restrictions.
*   **Firewall Container:** Built a custom Alpine-based firewall (`firewall/Dockerfile`) with an `iptables` script (`firewall-rules.sh`) enforcing default `DROP` policies and allowing specific routing. Pinned the Alpine base image with a SHA256 digest. Configured with `cap_drop: [ALL]`, `cap_add: [NET_ADMIN, NET_RAW]`, `read_only: true`, and `security_opt: ["no-new-privileges:true"]`.
*   **Pi-hole:** Configured Pi-hole in `docker-compose.yml` on the `internal_net` with resource limits, `read_only: true`, and explicit `tmpfs` mounts. Pinned the image with a SHA256 digest.

### Phase 3: Telemetry & Vulnerable Infrastructure
*   **Wazuh SIEM:** Configured `wazuh/wazuh-manager` in `docker-compose.yml` with production tuning (resource limits, `ulimits`, memory locking). Pinned the image digest. Configured with strict security options (`read_only: true`, `no-new-privileges:true`) and explicit `tmpfs` mounts.
*   **Vulnerable Target:** Configured `vulnerables/metasploitable2` on `dmz_net` with dropped capabilities and read-only root filesystem. Pinned the image digest. Modified default route via custom command.

### Phase 4: The Attacker Enclave
*   **Kali Dockerfile:** Built a custom Kali Linux container (`attacker-node/Dockerfile`) with a non-root `hacker` user, restricted `sudo` access, and essential network tools (`iproute2`, `iputils-ping`, `curl`). Pinned the base image digest.
*   **DevContainer Integration:** Configured `.devcontainer/devcontainer.json` to attach VS Code to the attacker node with necessary extensions.

### Phase 5: Orchestration
*   **Lab Manager Script:** Developed `lab_manager.py` with pre-flight checks (verifying `.env`, `vm.max_map_count`, and swap status) and integrated with Docker Compose commands. Integrated the `validation.sh` script to run automatically 15 seconds after `lab_manager.py up`.

---

## Phase 6 Execution Results (Automated Validation)

The end-to-end validation was successfully integrated into the orchestration script (`lab_manager.py`) using `validation.sh`. The results of the final Phase 6 run are as follows:

*   **Build & Structural Validation: PASS.** Both `homelab-attacker` and `homelab-firewall` images correctly specify restricted directives, and the runtime limits apply properly.
*   **Runtime & Security Context Validation: PASS.** All containers strictly enforce `read_only: true`, `security_opt: [no-new-privileges:true]`, and `cap_drop: [ALL]`. Required capabilities (`NET_ADMIN`, `NET_RAW`, etc.) are explicitly allowed where needed.
*   **Service & API Health Checks: PARTIAL PASS.** The Firewall container reports as `healthy`. The SIEM API check fails to respond immediately at the 15-second validation mark because Wazuh's initialization cycle takes longer to boot up its services, but the container does not crash.
*   **Network Isolation & Connectivity Testing: PARTIAL PASS / FAIL.**
    *   *Drop Policy:* **PASS.** Pings from the vulnerable target to the attacker node correctly drop as expected.
    *   *ICC Verification:* **FAIL.** Inter-Container Communication (ICC) between containers on the same network (e.g., Pi-hole to Wazuh) was allowed because `com.docker.network.bridge.enable_icc: "false"` had to be temporarily removed. Without ICC enabled, the Docker host kernel physically drops traffic on bridges, fundamentally preventing the firewall container from routing any traffic between networks.
    *   *Firewall Routing (Attacker to Target):* **FAIL.** Packets successfully route through the firewall gateway but are subsequently dropped by the Docker host's `bridge-nf-call-iptables=1` isolation rules (`DOCKER-FORWARD` and `DOCKER-ISOLATION` chains). The host kernel blocks L2 multi-bridge traversal, preventing true container-to-container L3 routing across isolated networks without explicit host-level `iptables` modifications.

---

## Phase 7: Resolved Issues & Implementation Changes

The pending issues from Phase 6 have been addressed as follows:

### 1. L3 Routing — DOCKER-USER iptables Chain (RESOLVED)
*   **Root Cause:** Docker's `DOCKER-ISOLATION-STAGE-1/2` chains drop all inter-bridge forwarding, blocking the firewall container from routing between `external_net`, `dmz_net`, and `internal_net`.
*   **Fix:** Added an idempotent `iptables -I DOCKER-USER -i br-+ -o br-+ -j ACCEPT` rule to both `setup_host.sh` and `lab_manager.py` (applied after `docker compose up`). The `DOCKER-USER` chain is evaluated before the isolation chains, so this rule allows the firewall container to perform L3 routing while leaving per-bridge ICC isolation intact.
*   **Files changed:** `setup_host.sh`, `lab_manager.py` (`apply_docker_user_rules()`)

### 2. ICC Re-enabled (RESOLVED)
*   **Fix:** Re-added `com.docker.network.bridge.enable_icc: "false"` as `driver_opts` on all three networks (`external_net`, `dmz_net`, `internal_net`) in `docker-compose.yml`. The `DOCKER-USER` fix in Step 1 allows cross-bridge routing to work while this option still blocks intra-network direct communication.
*   **Files changed:** `docker-compose.yml` (all three network definitions)

### 3. SIEM API Health Check — Polling Loop (RESOLVED)
*   **Fix:** Rewrote the SIEM validation section of `validation.sh` to poll the Wazuh API every 5 seconds for up to 120 seconds (24 attempts) before reporting failure. Credentials are now loaded dynamically from `.env` via `grep`/`cut` rather than being hardcoded.
*   **Files changed:** `validation.sh`

### 4. Privilege Dropping — gosu for Attacker Node (PARTIALLY RESOLVED)
*   **Firewall:** The firewall container must run as `uid 0` because `iptables` requires root even with `CAP_NET_ADMIN`. Added explicit `user: "0:0"` to the firewall service in `docker-compose.yml` with a comment documenting the constraint. The long-term path to eliminating this is migrating to a `macvlan`/`ipvlan` architecture where L3 routing is handled by the host kernel rather than a privileged container.
*   **Attacker Node:** Installed `gosu` in `attacker-node/Dockerfile` and updated the `command` in `docker-compose.yml` to use `exec gosu hacker tail -f /dev/null` instead of `su hacker -c '...'`. `gosu` uses `exec(3)` to replace the process, ensuring no residual root capabilities remain after the privilege drop.
*   **Files changed:** `attacker-node/Dockerfile`, `docker-compose.yml` (attacker-node command and firewall user)

---

## Remaining Future Work

*   **macvlan/ipvlan migration:** Fully decouple L3 routing from container privileges by moving the routing function to the host kernel (macvlan parent interface). This would allow the firewall container to run as `USER 1000:1000` and remove the `user: "0:0"` override.
*   **Per-bridge DOCKER-USER rules:** Replace the broad `br-+` wildcard in the DOCKER-USER rule with interface-specific rules targeting the exact bridge names for `external_net`, `dmz_net`, and `internal_net` for tighter host-level control.
