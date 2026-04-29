#!/bin/bash
# End-to-End Validation Script — Phase 6
# Polls service health and validates network isolation before declaring the lab ready.
set -euo pipefail

# Load credentials from .env so we don't hardcode passwords in this script.
WAZUH_ADMIN_PASSWORD=""
if [ -f ".env" ]; then
    WAZUH_ADMIN_PASSWORD=$(grep '^WAZUH_ADMIN_PASSWORD=' .env 2>/dev/null | cut -d'=' -f2- | tr -d '"' || true)
fi

if [ -f ".active_lab.env" ]; then
    source .active_lab.env
else
    echo "WARNING: .active_lab.env not found. Assuming all components are active."
fi

PASS=0
FAIL=0
result() { [ "$1" = "PASS" ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1)); echo "  [$1] $2"; }

echo "=== Phase 6: End-to-End Validation ==="

# ---------------------------------------------------------------------------
echo ""
echo "1. Build & Structural Validation"
for img in homelab-firewall:latest; do
    USER_DIR=$(docker inspect "$img" --format '{{.Config.User}}' 2>/dev/null || echo "NOT_FOUND")
    echo "  $img  USER directive: $USER_DIR"
done
if [ "${ACTIVE_KALI:-false}" = "true" ]; then
    USER_DIR=$(docker inspect "homelab-attacker:latest" --format '{{.Config.User}}' 2>/dev/null || echo "NOT_FOUND")
    echo "  homelab-attacker:latest  USER directive: $USER_DIR"
fi

# ---------------------------------------------------------------------------
echo ""
echo "2. Runtime & Security Context Validation"
CONTAINERS="firewall pihole wiretap"
[ "${ACTIVE_KALI:-false}" = "true" ] && CONTAINERS="$CONTAINERS attacker-node"
[ "${ACTIVE_ATOMICRED:-false}" = "true" ] && CONTAINERS="$CONTAINERS atomic-red"
[ "${ACTIVE_WAZUH:-false}" = "true" ] && CONTAINERS="$CONTAINERS wazuh-manager"
[ "${ACTIVE_SPLUNK:-false}" = "true" ] && CONTAINERS="$CONTAINERS splunk"
[ "${ACTIVE_METASPLOITABLE2:-false}" = "true" ] && CONTAINERS="$CONTAINERS vulnerable-target"
[ "${ACTIVE_UBUNTU:-false}" = "true" ] && CONTAINERS="$CONTAINERS ubuntu-target"

for c in $CONTAINERS; do
    echo "  Container: $c"
    docker inspect "$c" --format '    ReadonlyRootfs: {{.HostConfig.ReadonlyRootfs}}' 2>/dev/null || echo "    (not running)"
    docker inspect "$c" --format '    SecurityOpt:    {{.HostConfig.SecurityOpt}}'    2>/dev/null || true
    docker inspect "$c" --format '    CapDrop:        {{.HostConfig.CapDrop}}'        2>/dev/null || true
done

# ---------------------------------------------------------------------------
echo ""
echo "3. Network Isolation & Connectivity Testing"

if [ "${ACTIVE_KALI:-false}" = "true" ] && [ "${ACTIVE_METASPLOITABLE2:-false}" = "true" ]; then
    echo "  Firewall Enforcement (attacker -> vulnerable-target, cross-bridge — must PASS)"
    if docker exec attacker-node ping -c 1 -W 4 10.10.20.10 > /dev/null 2>&1; then
        result PASS "Firewall routed attacker -> DMZ successfully"
    else
        result FAIL "Firewall failed to route attacker -> DMZ"
    fi

    echo "  Drop Policy (vulnerable-target -> attacker, no reverse route — must FAIL)"
    if docker exec vulnerable-target ping -c 1 -W 2 10.10.10.10 > /dev/null 2>&1; then
        result FAIL "Drop policy NOT active — DMZ can initiate connections to attacker"
    else
        result PASS "Drop policy active — DMZ cannot initiate connections to attacker"
    fi
fi

if [ "${ACTIVE_ATOMICRED:-false}" = "true" ] && [ "${ACTIVE_METASPLOITABLE2:-false}" = "true" ]; then
    echo "  Firewall Enforcement (atomic-red -> vulnerable-target, cross-bridge — must PASS)"
    if docker exec atomic-red ping -c 1 -W 4 10.10.20.10 > /dev/null 2>&1; then
        result PASS "Firewall routed atomic-red -> DMZ successfully"
    else
        result FAIL "Firewall failed to route atomic-red -> DMZ"
    fi
fi

# ---------------------------------------------------------------------------
echo ""
echo "4. Service & API Health Checks"

FIREWALL_HEALTH=$(docker inspect firewall --format '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
echo "  Firewall health: $FIREWALL_HEALTH"
[ "$FIREWALL_HEALTH" = "healthy" ] && result PASS "Firewall container healthy" || result FAIL "Firewall container not healthy (status: $FIREWALL_HEALTH)"

if [ "${ACTIVE_WAZUH:-false}" = "true" ]; then
    if [ -z "$WAZUH_ADMIN_PASSWORD" ]; then
        echo "WARNING: WAZUH_ADMIN_PASSWORD not found in .env; SIEM API check will likely fail."
    fi
    echo "  Waiting for Wazuh SIEM API (polling every 5s, up to 120s)..."
    SIEM_READY=false
    for attempt in $(seq 1 24); do
        if docker exec wazuh-manager curl -s -k \
            -u "admin:${WAZUH_ADMIN_PASSWORD}" \
            https://127.0.0.1:55000/ > /dev/null 2>&1; then
            result PASS "SIEM API reachable (attempt ${attempt}/24)"
            SIEM_READY=true
            break
        fi
        echo "    Not ready yet (attempt ${attempt}/24) — retrying in 5s..."
        sleep 5
    done
    if [ "$SIEM_READY" = "false" ]; then
        result FAIL "SIEM API did not respond within 120 seconds"
    fi
fi

if [ "${ACTIVE_SPLUNK:-false}" = "true" ]; then
    echo "  Waiting for Splunk to finish provisioning (polling for UDP 1514, up to 600s)..."
    SPLUNK_READY=false
    for attempt in $(seq 1 120); do
        if docker exec splunk grep "05EA" /proc/net/udp > /dev/null 2>&1; then
            result PASS "Splunk is ready and listening on UDP 1514 (attempt ${attempt}/120)"
            SPLUNK_READY=true
            break
        fi
        echo "    Splunk provisioning... (attempt ${attempt}/120) — retrying in 5s..."
        sleep 5
    done
    if [ "$SPLUNK_READY" = "false" ]; then
        result FAIL "Splunk did not finish provisioning within 600 seconds"
    fi
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Validation Summary: ${PASS} PASS / ${FAIL} FAIL ==="
[ "$FAIL" -eq 0 ] && echo "ALL CHECKS PASSED — Lab is ready." || echo "SOME CHECKS FAILED — Review output above."
