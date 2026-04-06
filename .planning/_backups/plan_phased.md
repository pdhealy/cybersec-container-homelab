# Phased Execution Plan: Secure Cyber Homelab

## Executive Summary & Critique of Previous Plan

The original `plan.md` provided a strong conceptual baseline for a 3-tier cybersecurity homelab using Docker. However, to meet **Google-grade production-level quality, security, standards, and principles**, several critical architectural adjustments must be made:

1.  **Container Security & Least Privilege:** The previous plan relied on default Docker capabilities and insecure practices. A Google-grade approach requires explicit `cap_drop: [ALL]` with only necessary capabilities added back. We must enforce `security_opt: ["no-new-privileges:true"]`, strict non-root execution (`USER <uid>:<gid>`), and `read_only: true` filesystems with explicit `tmpfs` mounts where possible. Furthermore, all base images must use cryptographic SHA256 pinning to prevent supply chain attacks, and strict secret management via `.env` or Docker Secrets must be used.
2.  **Resource & Kernel Tuning:** The SIEM (Wazuh/OpenSearch) deployment in the original plan would likely fail or cause host instability. Production deployments require explicit host kernel tuning (`vm.max_map_count`), disabling host swap (`swapoff -a`), locking JVM heap into physical RAM (`bootstrap.memory_lock: true`), CPU pinning (`cpuset`) for data nodes to avoid "noisy neighbor" issues, container `ulimits` (file descriptors and memlock), and JVM heap size configurations proportional to container memory limits.
3.  **Network Isolation & Routing:** While using Alpine + `iptables` as a router is effective, it must be hardened. Inter-Container Communication (ICC) must be disabled on the Docker bridge networks (`enable_icc: "false"`) to force all traffic through the firewall container. IPv6 must be explicitly disabled (`enable_ipv6: false`) to reduce attack surface. Endpoints must have their default routing explicitly overridden to point to the firewall IP.
4.  **Healthchecks, Logging, & Orchestration:** Production environments do not rely on "fire and forget" deployments. We must implement Docker `healthcheck` directives for all services to ensure dependencies are respected. Strict log rotation policies (`max-size: "10m"`, `max-file: "3"`) must be enforced globally, and infrastructure services require `restart: unless-stopped` policies.
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
    *   Create an idempotent script (`setup_host.sh`) to configure the Docker host.
    *   Apply `sysctl -w vm.max_map_count=262144` (Required for Wazuh/OpenSearch).
    *   **Security & Performance:** Explicitly disable swap (`swapoff -a` and remove from `/etc/fstab`) to prevent OpenSearch performance degradation.
    *   Ensure IP forwarding is enabled on the host if required for the specific Docker network driver setup.
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
    *   **Security:** Use `cap_drop: [ALL]`, `cap_add: [NET_ADMIN, NET_RAW]`, `security_opt: ["no-new-privileges:true"]`, `read_only: true`, and run as `USER <uid>:<gid>`.
    *   Implement `firewall-rules.sh` to enforce default `DROP` policies, only allowing explicit routing (Attacker -> DMZ, Attacker -> SIEM).
    *   Add a Docker `healthcheck` to ensure the routing table is successfully applied before dependent containers start.
    *   Add `restart: unless-stopped`.
3.  **DNS & Ad-Blocking (Pi-Hole):**
    *   Deploy Pi-Hole on the `internal_net` using image digest pinning.
    *   Configure resource limits (`cpus: 0.5`, `memory: 512M`).
    *   **Security:** Enforce `security_opt: ["no-new-privileges:true"]`, `read_only: true` (with `tmpfs` mounts), and strict non-root `USER` execution. Configure Docker log rotation (`max-size: "10m"`, `max-file: "3"`).
    *   Load passwords dynamically from the `.env` file.
    *   Add explicit default route override pointing to the Firewall IP.
    *   Add `restart: unless-stopped`.

## Phase 3: Telemetry & Vulnerable Infrastructure

**Goal:** Deploy the Wazuh SIEM with production tuning, alongside the vulnerable target.

1.  **Wazuh SIEM Deployment:**
    *   Deploy `wazuh/wazuh-manager` and OpenSearch data nodes using pinned SHA256 digests.
    *   **Production Tuning:**
        *   Set strict `deploy.resources.limits` (e.g., 4G memory).
        *   Configure JVM options: `OPENSEARCH_JAVA_OPTS="-Xms2g -Xmx2g"` (50% of the container limit).
        *   Enable `bootstrap.memory_lock: true` in OpenSearch config.
        *   Apply CPU pinning (`cpuset: "0,1"`) for predictable performance.
        *   Configure `ulimits`: `nofile` (soft/hard: 65536) and `memlock` (soft/hard: -1).
    *   **Security:** Enforce `security_opt: ["no-new-privileges:true"]`, `read_only: true` (with `tmpfs` mounts where required), explicit log rotation, and strict non-root `USER` execution.
    *   Add explicit default route override pointing to the Firewall IP.
    *   Ensure persistent volume mounts for `/var/ossec/data`.
    *   Add `restart: unless-stopped`.
2.  **Vulnerable Target Deployment:**
    *   Deploy `vulnerables/metasploit-vulnerability-emulator` on the `dmz_net` (pinned digest).
    *   **Security Context:** Run it with `cap_drop: [ALL]`, `security_opt: ["no-new-privileges:true"]`, and `read_only: true` to prevent an attacker who gains root *inside* the target from easily escaping to the Docker host. Use non-root `USER` where possible.
    *   Add explicit default route override pointing to the Firewall IP.

## Phase 4: The Attacker Enclave

**Goal:** Build the Kali Linux attacker node with necessary capabilities for network scanning, integrated with VS Code DevContainers.

1.  **Kali Dockerfile Build:**
    *   Create a custom Dockerfile based on `kalilinux/kali-rolling` (pinned digest).
    *   Create a non-root `hacker` user. Instead of passwordless sudo, assign a known password (from `.env`) or restrict `sudo` commands to specific network tools, enforcing standard security hygiene even for the attacker.
2.  **DevContainer Integration:**
    *   Configure `.devcontainer/devcontainer.json` to attach to the running `attacker` service.
    *   Include necessary VS Code extensions (Python, Markdown, C/C++).
3.  **Compose Integration:**
    *   Attach to `external_net`.
    *   **Security:** Use `cap_drop: [ALL]`, `cap_add: [NET_RAW, NET_ADMIN]` (required for `nmap`, `tcpdump`, etc.), `security_opt: ["no-new-privileges:true"]`, and `read_only: true` with `/tmp` mounted as `tmpfs`. Ensure it runs as the non-root `USER`.
    *   Add explicit default route override pointing to the Firewall IP.

## Phase 5: Orchestration

**Goal:** Provide a robust, user-friendly way to manage the lifecycle of the lab without manual `docker compose` commands.

1.  **Lab Manager Script (`lab_manager.py`):**
    *   Refine the orchestrator to utilize Docker Compose Profiles properly.
    *   Add pre-flight checks to the script (e.g., verifying `vm.max_map_count` is set, checking if `.env` exists, ensuring swap is disabled).
    *   Implement robust teardown/cleanup functions to prevent state drift between runs.

## Phase 6: End-to-End Validation & Automated Testing (Gemini CLI Execution)

**Goal:** Leverage the Gemini CLI to systematically test the full implementation and configuration, validating that all components align with Google-grade production standards.

1.  **Build & Structural Validation:**
    *   Gemini CLI will invoke `docker compose build` to verify all custom `Dockerfile`s successfully compile.
    *   For custom built images (Attacker, Firewall), Gemini CLI will use `docker inspect` to programmatically verify that:
        *   The `USER` directive is explicitly set to a non-root UID/GID.
        *   Base image digests strictly adhere to the pinned SHA256 hashes.
2.  **Runtime & Security Context Validation:**
    *   Gemini CLI will execute `docker compose up -d` to instantiate the lab.
    *   It will run `docker inspect` across all running containers to assert:
        *   `HostConfig.ReadonlyRootfs` is `true`.
        *   `HostConfig.SecurityOpt` contains `no-new-privileges:true`.
        *   `HostConfig.CapDrop` contains `ALL`.
        *   No container is mounting the host's `/var/run/docker.sock` (preventing orchestration node compromise).
3.  **Network Isolation & Connectivity Testing:**
    *   **ICC Verification:** Gemini CLI will execute `docker exec` commands inside containers residing on the same subnet (if applicable) to attempt lateral movement (e.g., pinging neighboring IPs). These must successfully time out/fail, proving `enable_icc: "false"` is active.
    *   **Firewall Enforcement Verification:** Gemini CLI will use `docker exec <attacker-node> ping -c 1 <vulnerable-target-ip>`. This must succeed to prove the central Alpine Firewall is routing traffic from the `external_net` to the `dmz_net`.
    *   **Drop Policy Verification:** Gemini CLI will use `docker exec <vulnerable-target> ping -c 1 <attacker-node-ip>`. This must drop to prove the NAT/Firewall state prevents outbound initiation from the DMZ.
4.  **Service & API Health Checks:**
    *   Gemini CLI will poll the Docker daemon for the `Health` status of the SIEM and Firewall containers to ensure they transition from `starting` to `healthy`.
    *   Gemini CLI will run a `curl` command against the SIEM API (e.g., `curl -k -u admin:<password> https://<siem-ip>:55000/`) to programmatically confirm it is accepting connections.

---

**Execution Readiness:** This plan is designed to be fully actionable by the Gemini CLI agent. In the final phase, Gemini CLI will autonomously execute the validation commands defined in Phase 6, asserting that the architecture achieves a Google-grade security posture before presenting the environment to the user.