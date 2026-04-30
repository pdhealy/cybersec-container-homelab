# Cybersecurity Container Homelab

A containerized, production-hardened cybersecurity testing laboratory for adversarial simulation, threat detection validation, and security operations training. Deploy isolated attacker, vulnerable target, and SIEM infrastructure with automated orchestration, network segmentation, and end-to-end attack logging.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Python Version](https://img.shields.io/badge/Python-3.9+-blue)
![Docker Version](https://img.shields.io/badge/Docker-24.0+-critical)
![Platform](https://img.shields.io/badge/Platform-Linux-informational)

---

## 🎯 Purpose

This homelab provides a **zero-trust network architecture** for security practitioners to:

- **Simulate real-world attacks** using Kali Linux and Atomic Red Team
- **Observe defensive responses** via Wazuh or Splunk SIEM platforms
- **Validate detection rules** with comprehensive firewall and application logging
- **Train security teams** on incident response workflows
- **Research network isolation** using Docker's network policies and custom iptables rules

**Key guarantee:** All container-to-container communication is mediated by an explicit firewall service. No direct inter-host routes exist without explicit allow rules.

---

## ✨ Features

| Capability | Components | Status |
|---|---|---|
| **Isolated Network Zones** | External (attacker), DMZ (target), Internal (SIEM) | ✅ |
| **Layer 3 Routing & Firewalling** | Custom iptables firewall container | ✅ |
| **Intra-Network Isolation** | Docker `enable_icc: "false"` on all bridge networks | ✅ |
| **Read-Only Filesystems** | All services except volumes | ✅ |
| **Capability Dropping** | Minimal privileges per service | ✅ |
| **Attacker Nodes** | Kali Linux, Atomic Red Team | ✅ |
| **Vulnerable Targets** | Metasploitable2, Ubuntu (hardened) | ✅ |
| **SIEM Integration** | Wazuh + Splunk with syslog ingestion | ✅ |
| **DNS Monitoring** | Pi-hole with query logging | ✅ |
| **Packet Capture** | tcpdump with rotation and retention | ✅ |
| **Validation Suite** | Pre-flight checks, security assertions, integration tests | ✅ |

---

## 📋 Prerequisites

### Host Requirements

| Component | Minimum | Recommended |
|---|---|---|
| **OS** | Ubuntu 20.04+ / Debian 11+ / RHEL 8+ | Ubuntu 22.04 LTS |
| **CPU Cores** | 4 | 8+ |
| **RAM** | 12 GB | 16+ GB |
| **Disk** | 50 GB | 100+ GB (for Splunk logs) |
| **Docker** | 24.0+ | Latest |
| **Swap** | Disabled | Disabled (required) |

### Software Dependencies

```bash
# Core
- Docker Engine 24.0+ (with Compose plugin)
- Python 3.9+
- Bash 4.0+

# Optional runtime tools
- tcpdump (for packet capture verification)
- curl (for SIEM API validation)
```

### Security Prerequisites

⚠️ **This lab modifies host kernel parameters and firewall rules.** Run only on isolated test systems.

Before deployment:

```bash
# Check swap status (must be disabled)
free -h
swapon --show

# Check current vm.max_map_count (needs to be 262144 for Wazuh/Splunk)
cat /proc/sys/vm/max_map_count
```

If swap is enabled, disable it:

```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

---

## 🚀 Quick Start

### 1. Clone & Install

```bash
git clone https://github.com/pdhealy/cybersec-container-homelab.git
cd cybersec-container-homelab

# Install Python dependencies
pip install -r requirements.txt
```

### 2. Deploy with Preset (Recommended)

```bash
# Start all components (attacker nodes, vulnerable targets, both SIEMs, wiretap)
python3 src/cyberlab/cli.py up --preset configs/presets/09_all.yml
```

**What happens automatically:**
1. ✅ Pre-flight checks (host configuration, swap status, kernel parameters)
2. ✅ Auto-generates secure `.env` credentials (or uses existing)
3. ✅ Prompts for confirmation if passwords are auto-generated
4. ✅ Applies host kernel tuning (`vm.max_map_count`, IPv4 forwarding, iptables rules)
5. ✅ Builds and starts all container images
6. ✅ Applies dynamic routing rules between networks
7. ✅ Runs structural validation suite (network isolation, security primitives)
8. ✅ Executes end-to-end attack logging integration tests
9. ✅ Reports readiness

---

## 📦 Available Presets

Located in `configs/presets/`:

| Preset | Composition | Use Case |
|---|---|---|
| `09_all.yml` | Kali + AtomicRed + Metasploitable2 + Ubuntu + Wazuh + Splunk | Full capability testing |
| `01_kali_msf2_wazuh.yml` | Kali + Metasploitable2 + Wazuh | Minimal + Wazuh SIEM |
| `02_kali_msf2_splunk.yml` | Kali + Metasploitable2 + Splunk | Minimal + Splunk SIEM |
| `03_kali_ubuntu_wazuh.yml` | Kali + Ubuntu + Wazuh | Hardened target + Wazuh |
| `04_kali_ubuntu_splunk.yml` | Kali + Ubuntu + Splunk | Hardened target + Splunk |
| `05_atomicred_msf2_wazuh.yml` | AtomicRed + Metasploitable2 + Wazuh | Adversary emulation + Wazuh |
| `06_atomicred_msf2_splunk.yml` | AtomicRed + Metasploitable2 + Splunk | Adversary emulation + Splunk |
| `07_atomicred_ubuntu_wazuh.yml` | AtomicRed + Ubuntu + Wazuh | Hardened + Adversary emulation |
| `08_atomicred_ubuntu_splunk.yml` | AtomicRed + Ubuntu + Splunk | Hardened + Adversary emulation |

### Manual Configuration

To choose components interactively:

```bash
python3 src/cyberlab/cli.py up
# Follow prompts to select attacker, target, and SIEM
```

---

## 🔌 Usage & Operations

### Start Lab

```bash
# Using preset (non-interactive, recommended for automation)
python3 src/cyberlab/cli.py up --preset configs/presets/09_all.yml

# Interactive mode (choose components)
python3 src/cyberlab/cli.py up

# Explicit profile list
python3 src/cyberlab/cli.py up --profiles kali,metasploitable2,wazuh
```

### Check Status

```bash
python3 src/cyberlab/cli.py status
# Shows all running containers and their states
```

### Stop Lab

```bash
python3 src/cyberlab/cli.py down
# Gracefully stops and removes all containers
```

### Build Images Only

```bash
python3 src/cyberlab/cli.py build --preset configs/presets/09_all.yml
```

---

## 🏗️ Architecture

### Network Topology

```
┌─────────────────────────────────────────────────────────┐
│                    Host (Linux)                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │              Docker Daemon                        │   │
│  │  ┌─────────────────────────────────────────────┐ │   │
│  │  │   EXTERNAL (10.10.10.0/24)                 │ │   │
│  │  │   [Kali] [AtomicRed] ──────────┐           │ │   │
│  │  └───────────────────────────────┬────────────┘ │   │
│  │                                  │             │   │
│  │  ┌─────────────────────────────┴──────────────┐ │   │
│  │  │   FIREWALL (10.10.*.254)                  │ │   │
│  │  │   - Explicit routing rules                │ │   │
│  │  │   - Drop policy (reverse)                 │ │   │
│  │  │   - iptables + rsyslog + ulogd            │ │   │
│  │  │   - Packet mirror → Wiretap               │ │   │
│  │  └─────────────────────────────┬──────────────┘ │   │
│  │                                  │             │   │
│  │  ┌─────────────────────────────┴──────────────┐ │   │
│  │  │   DMZ (10.10.20.0/24)                      │ │   │
│  │  │   [Metasploitable2] [Ubuntu]               │ │   │
│  │  └─────────────────────────────┬──────────────┘ │   │
│  │                                  │             │   │
│  │  ┌─────────────────────────────┴──────────────┐ │   │
│  │  │   INTERNAL (10.10.30.0/24)                 │ │   │
│  │  │   [Pi-hole] [Wazuh] [Splunk] [Wiretap]     │ │   │
│  │  └──────────────────────────────────────────┘ │   │
│  │                                               │   │
│  └──────────────────────────────────────────────┘   │
│                                                     │
│  Host Ports (localhost):                           │
│    - 8000  → Splunk Web                           │
│    - 8080  → Pi-hole Admin                        │
│   - 55000  → Wazuh API                            │
└─────────────────────────────────────────────────────┘
```

### Security Model

**Zero-Trust Principle:** All inter-network traffic is explicitly allowed or denied.

1. **Network Isolation:** Each zone is a Docker bridge network with `enable_icc: "false"` (no direct host-to-host communication on same network).

2. **Firewall as Single Point of Access:** The firewall container sits at the intersection of all three networks and enforces routing rules via iptables.

3. **Host Kernel Rules:** The iptables `raw` (prerouting) and `filter` (DOCKER-USER) tables are configured during `setup_host.sh` to allow cross-bridge traffic only via the firewall.

4. **Capability Dropping:** All services run with `cap_drop: ALL` and only essential capabilities added back (e.g., `NET_ADMIN` for routing, `NET_BIND_SERVICE` for DNS).

5. **Read-Only Filesystems:** Most services have `read_only: true` with tmpfs mounts for runtime state.

---

## 🔍 SIEM Access

### Wazuh

**Web Console:** N/A (Wazuh API only in this configuration)

**API Access:**
```bash
# Inside wazuh-manager container
curl -k -u "admin:${WAZUH_ADMIN_PASSWORD}" https://localhost:55000/

# Check logs on host
docker exec wazuh-manager tail -f /var/ossec/logs/alerts/alerts.log
```

**Credentials:** Admin password is in `configs/.env` (auto-generated on first run)

### Splunk

**Web Console:** `http://localhost:8000`

**Credentials:** `admin` / password from `configs/.env`

**First-Run:**
- Splunk provisioning takes 5–10 minutes on initial deployment
- Ansible playbooks auto-configure logging and data inputs
- ⚠️ Do NOT mount `/opt/splunk/etc` or `/opt/splunk/var` as empty volumes—this wipes defaults and breaks startup

**Verify UDP Listener Ready:**
```bash
docker exec splunk grep "05EA" /proc/net/udp
# Output: 05EA is the hex port for 1514 (syslog)
```

**Search CLI:**
```bash
docker exec --user splunk splunk \
  /opt/splunk/bin/splunk search "index=main earliest=-10m" \
  -auth "admin:${SPLUNK_PASSWORD}"
```

---

## ✅ Validation & Testing

### Structural Validation

Runs automatically after `up` completes. Verifies:
- Read-only root filesystems and capability dropping
- Intra-network isolation (no direct cross-host communication)
- Firewall routing between zones
- Service health (firewall, Wazuh API, Splunk listener)

**Manual run:**
```bash
bash scripts/validation.sh
```

### Integration Tests

Simulates attack scenarios and verifies SIEM capture:

1. **Nmap port scan** from atomic-red (10.10.10.20) to target
2. **Malformed SSH probe** from kali (10.10.10.10) to target
3. **DNS query** via Pi-hole
4. **Log verification** in Wazuh and Splunk

**Manual run:**
```bash
bash tests/integration/test_attack_logging.sh
```

**Expected output:**
```
[PASS] Wazuh: Firewall logged Atomic Red Team traffic.
[PASS] Wazuh: Target logged Atomic Red Team port scan.
[PASS] Wazuh: Pi-hole logged the DNS query.
[PASS] Splunk: Firewall logged Kali traffic.
...
```

---

## 🛠️ Development & Customization

### Project Structure

```
.
├── src/cyberlab/
│   └── cli.py                 # Lab orchestrator (up, down, build, status)
├── services/
│   ├── attacker-node/         # Kali, Atomic Red Team
│   ├── vulnerable-target/     # Metasploitable2, Ubuntu
│   ├── siem/                  # Wazuh, Splunk
│   ├── firewall/              # Layer 3 routing + iptables
│   ├── pi-hole/               # DNS + query logging
│   └── wiretap/               # tcpdump + PCAP rotation
├── configs/
│   ├── .env.example           # Environment template
│   └── presets/               # Deployment profiles (YAML)
├── scripts/
│   ├── setup_host.sh          # Host kernel tuning + iptables config
│   └── validation.sh          # Security and health checks
├── tests/
│   ├── unit/                  # CLI unit tests
│   └── integration/           # Attack logging end-to-end tests
└── docker-compose.yml         # Complete service definition
```

### Adding a Custom Service

1. Create Dockerfile under `services/my-service/`
2. Add service definition to `docker-compose.yml` with appropriate profile, networks, and security context
3. Update preset YAML if needed
4. Update `src/cyberlab/cli.py` interactive choices if exposing as a profile
5. Run validation: `python3 src/cyberlab/cli.py build --profiles my-service`

---

## 🔧 Troubleshooting

### Pre-Flight Check Failures

**Error: `vm.max_map_count is too low`**
```bash
# Solution: Script auto-runs host setup, or manually:
sudo bash scripts/setup_host.sh
```

**Error: `Swap is enabled`**
```bash
# Solution: Disable swap (required for Wazuh/Splunk)
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

**Error: Missing `configs/.env`**
```bash
# Solution: Script auto-generates; confirm when prompted, or:
cp configs/.env.example configs/.env
# Then edit with unique passwords
```

### Container Issues

**Firewall not routing traffic**
```bash
# Check rules
docker exec firewall iptables -t filter -L FORWARD -v -n

# Check rsyslog + ulogd
docker exec firewall pgrep -a rsyslog
docker exec firewall pgrep -a ulogd

# View recent logs
docker exec firewall tail -50 /var/log/firewall-rules.log
```

**Splunk not ready after 10 minutes**
```bash
# Check provisioning status
docker exec splunk ps aux | grep ansible-playbook

# View logs
docker logs splunk 2>&1 | tail -100

# Verify UDP listener
docker exec splunk grep "05EA" /proc/net/udp
```

**Wazuh API unreachable**
```bash
# Check container health
docker ps --filter "name=wazuh" --format "table {{.ID}}\t{{.Status}}"

# Verify API port
docker exec wazuh-manager netstat -tlnp | grep 55000

# Try API call
docker exec wazuh-manager curl -k -u "admin:PASSWORD" https://127.0.0.1:55000/
```

### Network Issues

**Targets cannot reach external network**
```bash
# Confirm firewall has routes
docker exec firewall ip route show

# Check firewall health
docker inspect firewall --format '{{.State.Health.Status}}'

# Verify iptables on host
sudo iptables -t filter -L DOCKER-USER -v -n | head -20
```

**Packet capture missing traffic**
```bash
# Check wiretap container
docker logs wiretap

# Verify /pcaps volume
ls -lh logs/pcaps/

# Check disk space
df -h logs/
```

---

## 📖 Documentation

- **[Architecture Deep Dive](docs/reference/)** — Network topology, security model, threat scenarios
- **[Packet Capture Analysis](docs/reference/packet-capture/host_capture.md)** — tcpdump inspection workflow
- **[Custom Fieldbook & Rules](configs/)** — Wazuh decoder/rule customization, Splunk sourcetype examples

---

## ⚠️ Security & Compliance Notes

### Operational Constraints

1. **This lab is for isolated test environments only.** Do not deploy on production systems or networks.
2. **Auto-generated credentials** (if missing `.env`) are stored in plaintext. Rotate them and restrict `.env` file permissions: `chmod 600 configs/.env`
3. **Management interfaces** (Wazuh API, Splunk web) are bound to `127.0.0.1` by default. Restrict access via firewall rules if exposing to other interfaces.
4. **Firewall is not yet production-hardened.** See [review.md](review.md) for known issues and roadmap.

### Known Limitations (See `review.md`)

| Issue | Severity | Workaround |
|---|---|---|
| Unbounded packet capture can exhaust disk | High | Monitor `logs/pcaps/` size; implement `logrotate` |
| Default credentials in `.env.example` | High | Generate unique credentials; never commit `.env` to VCS |
| Unit tests outdated | Medium | Run integration tests only; unit tests in progress |
| Mutable base images (`:latest`) | Medium | Pin image tags and use image scanning in CI |

---

## 🤝 Contributing

Contributions welcome! Please:

1. **Create a feature branch:** `git checkout -b feature/your-feature`
2. **Test locally:**
   ```bash
   python3 src/cyberlab/cli.py build --preset configs/presets/09_all.yml
   python3 src/cyberlab/cli.py up --preset configs/presets/09_all.yml
   bash scripts/validation.sh
   bash tests/integration/test_attack_logging.sh
   ```
3. **Validate compose manifest:** `docker compose config > /dev/null`
4. **Submit pull request** with description of changes and test results

---

## 📜 License

This project is licensed under the [MIT License](LICENSE).

---

## 📞 Support & Issues

For bugs, feature requests, or questions:

- **GitHub Issues:** [pdhealy/cybersec-container-homelab/issues](https://github.com/pdhealy/cybersec-container-homelab/issues)
- **Documentation:** See `docs/` and `review.md` for known issues and roadmap

---

## 🙏 Acknowledgments

Built with Docker, Wazuh, Splunk, Kali Linux, and Atomic Red Team. Security architecture inspired by zero-trust networking principles and NIST Cybersecurity Framework.

---

**Last Updated:** 2026-04-30  
**Status:** Homelab / Early Adopter (not production-ready by default—see review.md)
