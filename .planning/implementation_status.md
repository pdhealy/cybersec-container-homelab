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

## Pending Issues & Comprehensive Next Steps

While container-level isolation and least privilege are successfully achieved, the **Docker host network isolation** directly conflicts with our design of using a container as a central L3 Router/Firewall. 

1.  **Resolve L3 Routing Limitations (Host iptables bypass):**
    *   *Problem:* The Docker daemon automatically injects strict `iptables` rules into the host's `FORWARD` and `DOCKER-ISOLATION-STAGE-X` chains to prevent traffic from crossing between separate Docker bridge networks, even if an explicit container is configured to route them.
    *   *Action Plan:* We need to explicitly allow traffic to be routed by the `firewall` container through the host's `FORWARD` chain. This requires executing a script on the host (e.g., in `setup_host.sh`) to insert `ACCEPT` rules into the `DOCKER-USER` iptables chain. 
    *   *Implementation:* Add `sudo iptables -I DOCKER-USER -i br-+ -o br-+ -j ACCEPT` (or specifically target the explicit bridge interfaces for `external_net`, `dmz_net`, and `internal_net`) to bypass the default drop.

2.  **Re-enable Strict ICC (Inter-Container Communication):**
    *   *Problem:* ICC was disabled to allow testing, which violates the strict intra-network isolation requirement. 
    *   *Action Plan:* Revert networks to use `com.docker.network.bridge.enable_icc: "false"`. Test if bypassing the `DOCKER-USER` isolation (Step 1) also resolves the ICC L3 gateway block, or if Docker's bridge driver completely ignores the gateway when ICC is false. If standard Docker bridges cannot support this, we may need to transition to `macvlan` or a custom Docker network driver that inherently supports a central router container.

3.  **Implement Robust SIEM API Health Check:**
    *   *Problem:* The validation script queries the Wazuh API too early. 
    *   *Action Plan:* Update `validation.sh` to implement a wait-for-it loop (e.g., polling the API endpoint every 5 seconds for up to 2 minutes) rather than executing a single `curl` check immediately after `lab_manager.py up`.

4.  **Refine Privilege Dropping:**
    *   *Problem:* The firewall and attacker nodes are currently running as `USER 0:0` (root) because of permissions required for `iptables` and `ip route`.
    *   *Action Plan:* Explore configuring the network namespace routing from the host *before* container initialization, or fully transition to `macvlan`/`ipvlan` architectures to decouple routing from container privileges, allowing a true return to `USER 1000:1000`. 
