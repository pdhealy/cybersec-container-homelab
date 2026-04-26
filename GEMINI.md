# Cyber Homelab - Operations & Validation Guide

This document serves as the foundational reference for managing the containerized cybersecurity homelab environment.

## 1. Prerequisites & Host Configuration
Before building or starting the lab, the host kernel must be tuned to support high-performance services (Wazuh/Splunk) and cross-bridge routing.

- **Setup Command:** `sudo bash setup_host.sh`
  - Sets `vm.max_map_count=262144`.
  - Disables host swap (required for OpenSearch).
  - Enables IPv4 forwarding and disables IPv6.
  - Configures `DOCKER-USER` iptables chains to allow the firewall container to route traffic between isolated networks.

## 2. Lab Management Strategy
Use the `lab_manager.py` orchestrator for all lifecycle operations. It ensures idempotent configuration and automatic validation.

- **Build Images:**
  ```bash
  python3 lab_manager.py build
  ```
- **Start Environment:**
  ```bash
  python3 lab_manager.py up
  ```
  *Note: This command automatically runs pre-flight checks, brings up containers, applies dynamic routing rules, and executes the validation/test suites.*
- **Stop Environment:**
  ```bash
  python3 lab_manager.py down
  ```
- **Check Status:**
  ```bash
  python3 lab_manager.py status
  ```

## 3. Validation & Testing
The environment is verified through two distinct layers:

### A. Structural Validation (`validation.sh`)
Verifies the "Zero Trust" architecture and security primitives:
- Confirms **Read-Only Root Filesystems** and **Capability Dropping** for all nodes.
- Validates **Intra-network Isolation** (ICC=false) prevents nodes on the same subnet from communicating directly.
- Validates **Firewall Enforcement** (routing cross-bridge traffic between External, DMZ, and Internal zones).
- Confirms **SIEM API Health**.

### B. Integration Testing (`tests/test_attack_logging.sh`)
Simulates an end-to-end attack lifecycle:
1. **Nmap Port Scan:** Executed from `atomic-red` to `vulnerable-target`.
2. **Malformed SSH Probe:** Executed from `attacker-node` to `vulnerable-target`.
3. **Log Verification:** Polling Wazuh (`/var/ossec/logs/alerts/alerts.log` and `archives.log`) and Splunk to verify the capture of `FW_FORWARD_ATTACK` and `sshd` probe logs.

## 4. SIEM Access
- **Wazuh API:** Accessible via `curl` from the `wazuh-manager` container.
- **Splunk Web:** Accessible on the host at `http://localhost:8000` (provisioning takes 5-10 minutes on first run).

### Splunk Provisioning & Troubleshooting
- **First-run Delay:** On initial deployment, Splunk uses Ansible playbooks to provision the environment. This can take 5-10 minutes. 
- **Stability Fixes:**
  - **No Volumes:** Do NOT mount `/opt/splunk/etc` or `/opt/splunk/var` as empty volumes. This wipes the image's default configuration and prevents startup.
  - **Disabled Healthcheck:** The Splunk healthcheck is disabled in `docker-compose.yml` to prevent Docker from killing the container during its slow first-time provisioning.
- **Verify UDP Listener:** Run the following command to check if Splunk is ready to receive logs on port 1514 (Hex 05EA):
  ```bash
  docker exec splunk grep "05EA" /proc/net/udp
  ```
- **CLI Search:** Search logs via CLI (use `splunk` user and full path):
  ```bash
  docker exec --user splunk splunk /opt/splunk/bin/splunk search "search index=main earliest=0" -auth "admin:cyberhomelab_splunk_secure"
  ```
