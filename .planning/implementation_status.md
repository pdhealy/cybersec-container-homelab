# Cyber Homelab Implementation Status

## Overview
The phased execution plan (`plan_phased.md`) for the secure Cyber Homelab has been largely implemented, focusing on enterprise-grade security standards, least privilege, and container isolation. The foundational infrastructure, core networking, telemetry targets, attacker enclave, and orchestration scripts have been created according to the architectural blueprint.

## Implemented Phases

### Phase 1: Foundation & Infrastructure as Code (IaC) Setup
*   **Directory Structure:** Created the required directories (`attacker-node/`, `vulnerable-target/`, `firewall/`, `siem/`, `pi-hole/`, `.devcontainer/`).
*   **Host Kernel Tuning:** Developed `setup_host.sh` to apply necessary `sysctl` settings (e.g., `vm.max_map_count=262144`), disable swap, and disable IPv6.
*   **Secret Management:** Generated a `.env` file for sensitive credentials (`PIHOLE_PASSWORD`, `WAZUH_ADMIN_PASSWORD`, `ATTACKER_PASSWORD`) and added it to `.gitignore`.

### Phase 2: Core Network & Perimeter Security
*   **Docker Networks:** Defined `external_net`, `dmz_net`, and `internal_net` in `docker-compose.yml` with Inter-Container Communication (ICC) strictly disabled (`com.docker.network.bridge.enable_icc: "false"`) and IPv6 disabled.
*   **Firewall Container:** Built a custom Alpine-based firewall (`firewall/Dockerfile`) with an `iptables` script (`firewall-rules.sh`) enforcing default `DROP` policies and allowing specific routing. Pinned the Alpine base image with a SHA256 digest. Configured with `cap_drop: [ALL]`, `cap_add: [NET_ADMIN, NET_RAW]`, `read_only: true`, and `security_opt: ["no-new-privileges:true"]`.
*   **Pi-hole:** Configured Pi-hole in `docker-compose.yml` on the `internal_net` with resource limits, `read_only: true`, and explicit `tmpfs` mounts. Pinned the image with a SHA256 digest.

### Phase 3: Telemetry & Vulnerable Infrastructure
*   **Wazuh SIEM:** Configured `wazuh/wazuh-manager` in `docker-compose.yml` with production tuning (resource limits, `ulimits`, memory locking). Pinned the image digest. Configured with strict security options (`read_only: true`, `no-new-privileges:true`).
*   **Vulnerable Target:** Configured `vulnerables/metasploitable2` on `dmz_net` with dropped capabilities and read-only root filesystem. Pinned the image digest.

### Phase 4: The Attacker Enclave
*   **Kali Dockerfile:** Built a custom Kali Linux container (`attacker-node/Dockerfile`) with a non-root `hacker` user, restricted `sudo` access, and essential network tools. Pinned the base image digest.
*   **DevContainer Integration:** Configured `.devcontainer/devcontainer.json` to attach VS Code to the attacker node with necessary extensions.

### Phase 5: Orchestration
*   **Lab Manager Script:** Developed `lab_manager.py` with pre-flight checks (verifying `.env`, `vm.max_map_count`, and swap status) and integrated with Docker Compose commands.

### Phase 6: Validation (Attempted)
*   **Build Validation:** Successfully validated that all custom Dockerfiles compile using `docker compose build`. Image digests were automatically resolved to their latest valid SHA256 hashes.
*   **Runtime Validation:** Attempted to bring up the environment with `docker compose up -d`, which revealed several runtime failures due to the strict security constraints imposed by the plan.

---

## Issues Encountered

The strict "Google-grade" security constraints outlined in the plan caused several critical runtime failures when validating the setup:

1.  **Routing vs. Privileges (RTNETLINK Errors):**
    *   *Issue:* The plan mandates explicit default route overrides (`ip route add default via ...`) within the container startup commands, while simultaneously requiring `cap_drop: [ALL]` and strict non-root execution.
    *   *Error:* `RTNETLINK answers: Operation not permitted`
    *   *Cause:* Unprivileged users without the `NET_ADMIN` capability cannot manipulate the container's routing table.

2.  **Firewall Constraints (iptables & Root):**
    *   *Issue:* The plan specified running the firewall container as a non-root user (`USER <uid>:<gid>`).
    *   *Error:* `iptables v1.8.11 (nf_tables): Could not fetch rule set generation id: Permission denied (you must be root)`
    *   *Cause:* `iptables` intrinsically requires root namespace access to manipulate network filters, even with `NET_ADMIN` capabilities added.

3.  **Wazuh Initialization (s6-overlay & Read-Only FS):**
    *   *Issue:* The `wazuh-manager` container is configured with `read_only: true` and `security_opt: ["no-new-privileges:true"]`.
    *   *Error:* Numerous `s6-chown: fatal: unable to chown /var/run/s6/etc/...: Read-only file system` and `Permission denied` errors.
    *   *Cause:* The `s6-overlay` initialization system used by Wazuh extensively manipulates file permissions and ownership in directories like `/var/run/s6/etc/` and `/var/ossec/` upon startup, which fails on a strict read-only filesystem.

4.  **Pi-hole and Target Routing Initialization:**
    *   *Issue:* Similar to the attacker node, `pihole` and `vulnerable-target` failed to set their default routes due to missing `NET_ADMIN` capabilities and missing `ip` commands in some base images (e.g., Metasploitable2 may lack `iproute2` out of the box).

---

## Detailed Fixes & Recommendations

To achieve a functional environment while maintaining the highest possible security posture, the following adjustments are recommended:

1.  **Fixing Routing Restrictions (RTNETLINK Errors):**
    *   *Recommendation:* Since we must override the default routes to enforce traffic through the firewall, the containers that perform routing setup (`attacker-node`, `pihole`, `wazuh-manager`, `vulnerable-target`) must either:
        *   **Option A:** Add the `NET_ADMIN` capability (`cap_add: [NET_ADMIN]`). This slightly reduces isolation but is necessary for manual routing inside the container.
        *   **Option B:** Configure routing at the Docker daemon network level (often complex and unsupported directly in standard Compose bridge networks without custom plugins).
    *   *Action Plan:* Proceed with Option A. Add `cap_add: [NET_ADMIN]` to all containers that require a custom default route.

2.  **Fixing Firewall Root Requirement:**
    *   *Fix Applied:* Removed the `USER 1000:1000` directive from `firewall/Dockerfile`. The container now runs as root but retains `cap_drop: [ALL]`, `cap_add: [NET_ADMIN, NET_RAW]`, `read_only: true`, and `no-new-privileges:true`. This minimizes the attack surface while allowing `iptables` to function.

3.  **Fixing Wazuh Read-Only Initialization:**
    *   *Recommendation:* The `read_only: true` constraint is too strict for `wazuh-manager`'s `s6-overlay`.
    *   *Action Plan:* We must explicitly define `tmpfs` mounts for every directory the initialization scripts attempt to modify. This requires mapping `/var/run/s6/`, `/etc/services.d/`, and ensuring `/var/ossec` has proper writable volumes. Alternatively, we may need to remove `read_only: true` from the `wazuh.manager` service and rely on `no-new-privileges` and `cap_drop` for isolation, as enterprise SIEM deployments often write to numerous unpredictable paths during startup.

4.  **Fixing Metasploitable2 Routing:**
    *   *Recommendation:* The `vulnerable-target` (Metasploitable2) image does not have the `ip` command installed by default, causing the routing command to fail with `sh: line 1: ip: command not found`.
    *   *Action Plan:* We must either build a custom image based on Metasploitable2 to install `iproute2` (using `apt-get install iproute2`), or use the legacy `route add default gw` command if the `net-tools` package is present.

---

## Next Steps

1.  **Apply Capability Fixes:** Update `docker-compose.yml` to grant `NET_ADMIN` to `attacker-node`, `vulnerable-target`, `pihole`, and `wazuh-manager` to allow default route overrides.
2.  **Resolve Metasploitable2 Routing:** Modify the `command` for `vulnerable-target` to use `route add default gw 10.10.20.254` instead of the `ip` command, or create a custom Dockerfile to install `iproute2`.
3.  **Tune Wazuh Read-Only Mounts:** Systematically map the required `s6-overlay` directories to `tmpfs` mounts in `docker-compose.yml`, or temporarily disable `read_only: true` for the `wazuh.manager` to observe a successful startup, then harden iteratively.
4.  **Re-run Validation:** Execute `lab_manager.py up` and verify that all containers start healthily without crashing loops.
5.  **Conduct End-to-End Network Tests:** Execute the network isolation and firewall enforcement tests defined in Phase 6.
