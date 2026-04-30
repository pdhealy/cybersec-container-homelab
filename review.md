# Enterprise Codebase Review (Cybersecurity Homelab)

## 1. Executive summary

**Overall risk:** High  
**Maturity:** Early-to-mid (strong homelab experimentation, not yet enterprise-ready by default)

Primary blockers are deployment reliability breakage in `docker-compose.yml`, insecure default credential behavior, secret exposure risk via debug tracing, and broad privilege/supply-chain controls that are too permissive for production-grade operation.

## 2. Prioritized findings

| Title | Severity | Affected files/components | Why it matters | Evidence | Recommended fix |
|---|---|---|---|---|---|
| Invalid Compose manifest due duplicate key | **Critical** | `docker-compose.yml` (ubuntu-target service) | Deployment and automation can fail immediately; platform unrecoverable without manual correction | `docker compose --env-file configs/.env config` fails with duplicate `command` key. `docker-compose.yml` includes two `command` entries for `ubuntu-target`. | Keep only one `command` key per service; enforce compose validation in CI. |
| Predictable default credentials auto-promoted to active `.env` | **High** | `src/cyberlab/cli.py`, `configs/.env.example` | Missing `.env` causes automatic copy of known defaults, creating insecure-by-default auth | `cli.py` copies `.env.example` on missing `.env`; `.env.example` contains fixed credentials for Pi-hole, Wazuh, and Splunk. | On first run, generate unique random secrets and force confirmation/rotation before startup. |
| Secret leakage via `bash -x` execution | **High** | `src/cyberlab/cli.py`, `scripts/validation.sh`, `tests/integration/test_attack_logging.sh` | `-x` traces expanded commands; passwords can leak to console/CI logs | `cli.py` invokes scripts with `bash -x`; scripts pass `admin:${WAZUH_ADMIN_PASSWORD}` and `admin:${SPLUNK_PASSWORD}` to commands. | Remove `-x` for secret-bearing scripts; use explicit, redaction-safe logging. |
| Over-privileged firewall container | **High** | `docker-compose.yml` (`firewall`) | `privileged: true` materially increases host attack surface and violates least privilege | Firewall service declares `privileged: true` and runs as root. | Replace with minimal `cap_add` set, hardened seccomp/apparmor profile, and documented capability rationale. |
| Unbounded packet capture can exhaust disk | **High** | `docker-compose.yml` (`wiretap`) | Continuous pcap writes can fill host disk and crash multiple services | `tcpdump -i any -U -w /pcaps/homelab-capture.pcap` writes continuously to persistent storage without rotation. | Use rotation (`-G`/`-W` or `-C`) and retention policy with storage alerting. |
| Healthcheck misses logging-path failures | **Medium** | `docker-compose.yml`, `services/firewall/firewall-rules.sh` | Firewall can appear healthy while logging pipeline is dead, creating observability blind spots | Healthcheck checks only `iptables -L`; script backgrounds rsyslog, runs ulogd foreground, then waits on rsyslog. | Healthcheck should validate rsyslog and ulogd liveness and recent log emission. |
| Unit tests currently broken by code drift | **Medium** | `tests/unit/test_cli.py`, `src/cyberlab/cli.py` | Reliability regressions can pass unnoticed without trustworthy tests | Test suite reports failures around missing `apply_docker_user_rules` references in tests. | Update tests to current CLI behavior and gate merges on passing test suite. |
| Mutable upstream base images (`:latest`) | **Medium** | Multiple Dockerfiles | Reproducibility and supply-chain integrity are weakened; builds may change unexpectedly | Several images use `FROM ...:latest`. | Pin immutable tags/digests and establish regular update cadence. |
| Management interfaces exposed broadly | **Medium** | `docker-compose.yml` (`wazuh.manager`, `splunk`, `pihole`) | Host-exposed admin ports increase attack surface and misconfiguration risk | Ports such as `55000`, `8000`, and `8080` are published on host interfaces. | Bind to trusted interfaces/VPN/localhost and enforce strict network ACLs. |
| Automation maturity gap (no CI workflows) | **Low** | `.github/` | Missing policy gates reduce confidence in changes and increase drift risk | No GitHub Actions workflow enforcing compose validity, tests, security scans, or secret scanning. | Add CI for compose validation, unit/integration tests, image scanning, and secret scanning. |

## 3. Quick wins (high impact, low effort)

1. Remove duplicate `command` key in `ubuntu-target` and enforce `docker compose config` checks in CI.
2. Remove `-x` from script invocations in CLI paths that handle credentials.
3. Replace static `.env.example` secrets with generated unique secrets at bootstrap.
4. Add pcap rotation and retention to the wiretap capture pipeline.
5. Pin `:latest` image references to immutable tags or digests.

## 4. Strategic improvements

1. **Security baseline program:** implement least-privilege profiles, reduce exposed management surfaces, and harden runtime policies.
2. **Secrets lifecycle management:** bootstrap-generated secrets, mandatory rotation flow, and encrypted secret handling (e.g., SOPS/Vault pattern).
3. **Supply-chain assurance:** pinned dependencies/images, SBOM generation, vulnerability scanning, and signature verification.
4. **Operational resilience:** healthchecks that reflect data-plane and log-pipeline health, plus alerting on ingestion/forwarding failures.
5. **Delivery maturity:** CI/CD policy gates (compose validity, tests, security checks), release criteria, and rollback procedures.

## 5. Suggested phased remediation roadmap

- **Phase 0 (Immediate):** fix compose duplicate key, remove `bash -x`, rotate/generate secrets, pin highest-risk images.
- **Phase 1 (Short term):** implement CI validation gates, repair failing tests, add pcap rotation and disk guardrails.
- **Phase 2 (Near term):** least-privilege hardening for firewall and related services; restrict management interface exposure.
- **Phase 3 (Mid term):** supply-chain controls (SBOM/signing/scanning), observability enhancements, and incident/recovery runbooks.
- **Phase 4 (Ongoing):** recurring security posture reviews, dependency refresh cadence, and recovery drill automation.
