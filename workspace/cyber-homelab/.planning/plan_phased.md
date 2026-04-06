# Phased Execution Plan: Secure Cyber Homelab

## Executive Summary & Critique of Previous Plan

The original `plan.md` provided a strong conceptual baseline for a 3-tier cybersecurity homelab using Docker. However, to meet **Google-grade production-level quality, security, standards, and principles**, several critical architectural adjustments must be made:

1.  **Container Security & Least Privilege:** The previous plan relied on default Docker capabilities and insecure practices. A Google-grade approach requires explicit `cap_drop: [ALL]` with only necessary capabilities added back, `read_only: true` filesystems with explicit `tmpfs` mounts where possible, `security_opt: ["no-new-privileges:true"]` on all containers, strict non-root execution (`USER <uid>:<gid>`), and strict secret management via `.env` or Docker Secrets. Furthermore, all base images must use cryptographic SHA256 pinning to prevent supply chain attacks.
2.  **Resource & Kernel Tuning:** The SIEM (Wazuh/OpenSearch) deployment in the original plan would likely fail or cause host instability. Production deployments require explicit host kernel tuning (`vm.max_map_count`), disabling host swap (`swapoff -a`), locking JVM heap into physical RAM (`bootstrap.memory_lock: true`), CPU pinning (`cpuset`) for data nodes to avoid "noisy neighbor" issues, container `ulimits` (file descriptors and memlock), and JVM heap size configurations proportional to container memory limits (max 31.5GB).
3.  **Network Isolation & Routing:** While using Alpine + `iptables` as a router is effective, it must be hardened. Inter-Container Communication (ICC) must be disabled on the Docker bridge networks (`enable_icc: "false"`) to force all traffic through the firewall container. IPv6 must be explicitly disabled (`enable_ipv6: false`) to reduce attack surface. Endpoints must have their default routing explicitly overridden to point to the firewall IP.
4.  **Healthchecks, Logging, & Orchestration:** Production environments do not rely on "fire and forget" deployments. We must implement Docker `healthcheck` directives for all services to ensure dependencies are respected. Strict log rotation policies (`max-size: "10m"`, `max-file: "3"`) must be enforced, and infrastructure services require `restart: unless-stopped` policies.
5.  **Idempotency and Validation:** Infrastructure as Code (IaC) scripts (`setup_host.sh`, `lab_manager.py`) must be strictly idempotent. The deployment must end with programmatic validation (e.g., querying the SIEM API to confirm log ingestion) before reporting as "Ready."

This phased plan corrects these deficiencies and provides a step-by-step roadmap for execution.

---

## Phase 1: Foundation & Infrastructure as Code (IaC) Setup

**Goal:** Establish the workspace directory structure, secure environment variables, and configure the host machine to support enterprise-grade containers.

1.  **Directory Initialization:**
    *   Create the strict directory structure inside `workspace/cyber-homelab`:
        *   `attacker-node/`
        *   `vulnerable-target/`
        *   `firewall/`
        *   `siem/`
        *   `pi-hole/`
        *   `.devcontainer/`
2.  **Host Kernel Tuning (Idempotent `setup_host.sh`):**
    *   Create a script (`setup_host.sh`) to configure the Docker host. The script must be strictly idempotent.
    *   Apply `sysctl -w vm.max_map_count=262144` (Required for Wazuh/OpenSearch).
    *   **Security & Performance:** Explicitly disable swap (`swapoff -a` and remove from `/etc/fstab`) to prevent OpenSearch performance degradation.
    *   Ensure IP forwarding is enabled on the host.
    *   Disable IPv6 at the host kernel level if not actively monitored.
3.  **Secret Management:**
    *   Generate a `.env` file to store sensitive variables (e.g., `PIHOLE_PASSWORD`, `WAZUH_ADMIN_PASSWORD`).
    *   Add `.env` to `.gitignore` to prevent credential leakage.

## Phase 2: Core Network & Perimeter Security

**Goal:** Build the isolated Docker networks and the central Alpine Firewall router that dictates all traffic flow.

1.  **Docker Network Configuration:**
    *   Define three custom bridge networks in `docker-compose.yml`: `external_net` (10.10.10.0/24), `dmz_net` (10.10.20.0/24), and `internal_net` (10.10.30.0/24).
    *   **Crucial Security Step:** Set `com.docker.network.bridge.enable_icc: "false"` on these networks to prevent containers on the same subnet from bypassing the firewall.
    *   Explicitly disable IPv6 on these networks (`enable_ipv6: false`).
2.  **Firewall Container Implementation:**
    *   Build the Alpine `iptables` container using cryptographic SHA256 pinning for the base image.
    *   **Security:** Use `cap_drop: [ALL]`, `cap_add: [NET_ADMIN, NET_RAW]`, `security_opt: ["no-new-privileges:true"]`, and `read_only: true`. Run with explicit `USER` definitions where possible.
    *   Implement `firewall-rules.sh` to enforce default `DROP` policies, only allowing explicit routing (Attacker -> DMZ, Attacker -> SIEM).
    *   Add a Docker `healthcheck` to ensure the routing table is successfully applied before dependent containers start.
    *   Add `restart: unless-stopped`.
3.  **DNS & Ad-Blocking (Pi-Hole):**
    *   Deploy Pi-Hole on the `internal_net` using image digest pinning.
    *   Configure resource limits (`cpus: 0.5`, `memory: 512M`).
    *   **Security:** Enforce `security_opt: ["no-new-privileges:true"]` and strict Docker log rotation (`max-size: "10m"`).
    *   Load passwords dynamically from the `.env` file.
    *   Explicit default route override pointing to the Firewall IP.

## Phase 3: Telemetry & Vulnerable Infrastructure

**Goal:** Deploy the Wazuh SIEM with production tuning, alongside the vulnerable target.

1.  **Wazuh SIEM Deployment:**
    *   Deploy `wazuh/wazuh-manager` and OpenSearch data nodes using pinned SHA256 digests.
    *   **Production Tuning & Stability:**
        *   Set strict `deploy.resources.limits` (e.g., 4G memory).
        *   Configure JVM options: `OPENSEARCH_JAVA_OPTS="-Xms2g -Xmx2g"` (50% of the container limit).
        *   Enable `bootstrap.memory_lock: true` in OpenSearch config.
        *   Apply CPU pinning (`cpuset: "0,1"`) for predictable performance.
        *   Configure `ulimits`: `nofile` (soft/hard: 65536) and `memlock` (soft/hard: -1).
    *   **Security:** Enforce `security_opt: ["no-new-privileges:true"]`, `read_only: true` (with `tmpfs` mounts where required), and explicit log rotation.
    *   Explicit default route override pointing to the Firewall IP.
    *   Ensure persistent volume mounts for `/var/ossec/data`.
    *   Add `restart: unless-stopped`.
2.  **Vulnerable Target Deployment:**
    *   Deploy `vulnerables/metasploit-vulnerability-emulator` on the `dmz_net` (pinned digest).
    *   **Security Context:** Run with `cap_drop: [ALL]` and `security_opt: ["no-new-privileges:true"]` to prevent an attacker who gains root *inside* the target from escaping to the Docker host. Ensure `read_only: true` where possible.
    *   Explicit default route override pointing to the Firewall IP.

## Phase 4: The Attacker Enclave

**Goal:** Build the Kali Linux attacker node with necessary capabilities for network scanning, integrated with VS Code DevContainers.

1.  **Kali Dockerfile Build:**
    *   Create a custom Dockerfile based on `kalilinux/kali-rolling` (pinned digest).
    *   Create a non-root `hacker` user. Restrict `sudo` commands to specific network tools, enforcing standard security hygiene.
2.  **DevContainer Integration:**
    *   Configure `.devcontainer/devcontainer.json` to attach to the running `attacker` service.
    *   Include necessary VS Code extensions.
3.  **Compose Integration:**
    *   Attach to `external_net`.
    *   **Security:** Use `cap_drop: [ALL]`, `cap_add: [NET_RAW, NET_ADMIN]` (required for `nmap`, `tcpdump`, etc.), `security_opt: ["no-new-privileges:true"]`, and `read_only: true` with `/tmp` mounted as `tmpfs`.
    *   Explicit default route override pointing to the Firewall IP.

## Phase 5: Orchestration & Validation

**Goal:** Provide a robust, user-friendly way to manage the lifecycle of the lab without manual `docker compose` commands.

1.  **Lab Manager Script (`lab_manager.py`):**
    *   Refine the orchestrator to utilize Docker Compose Profiles properly.
    *   Add pre-flight checks to the script (e.g., verifying `vm.max_map_count` is set, checking if `.env` exists, ensuring swap is disabled).
2.  **Programmatic Validation Testing:**
    *   Start the environment.
    *   Verify routing programmatically: Ping from Attacker to Target (should succeed). Ping from Target to Attacker (should drop, simulating NAT/Firewall state).
    *   Verify resource limits using `docker stats`.
    *   **Google-Grade Validation:** Query the SIEM API to programmatically confirm it is actively receiving logs and ready for use before exiting the script successfully.

---

**Execution Readiness:** This plan is designed to be fully actionable by the Gemini CLI agent in a subsequent execution phase. All components will be built in the `workspace/cyber-homelab` directory upon command.