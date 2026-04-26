#!/bin/bash
# Integration test to validate attack logging from both the firewall and the target.
set -euo pipefail

if [ -f ".active_lab.env" ]; then
    source .active_lab.env
else
    echo "WARNING: .active_lab.env not found. Assuming all components are active."
fi

echo "=== Running Attack Logging Integration Test ==="

if [ "${ACTIVE_WAZUH:-false}" != "true" ]; then
    echo "Wazuh is not active. Skipping attack logging integration tests."
    exit 0
fi

if [ "${ACTIVE_METASPLOITABLE2:-false}" != "true" ]; then
    echo "Metasploitable2 is not active. Skipping attack logging integration tests."
    exit 0
fi

# 1. Execute the attacks
if [ "${ACTIVE_ATOMICRED:-false}" = "true" ]; then
    echo "Initiating Nmap port scan from atomic-red (10.10.10.20) to vulnerable-target..."
    docker exec atomic-red pwsh -c "Invoke-AtomicTest T1046 -TestNumbers 12 -InputArgs @{'host'='10.10.20.10'; 'port_range'='1-100'}" >/dev/null || true
fi

if [ "${ACTIVE_KALI:-false}" = "true" ]; then
    echo "Initiating malformed SSH connection from attacker-node (10.10.10.10) to vulnerable-target..."
    # We send a specific string "kali_test_probe" to uniquely identify this test's application log
    docker exec attacker-node bash -c '</dev/tcp/10.10.20.10/22; sleep 1; echo "kali_test_probe" > /dev/tcp/10.10.20.10/22' 2>/dev/null || true
fi

if [ "${ACTIVE_ATOMICRED:-false}" != "true" ] && [ "${ACTIVE_KALI:-false}" != "true" ]; then
    echo "No attackers active. Skipping log checks."
    exit 0
fi

echo "Waiting for logs to be ingested by Wazuh SIEM..."
sleep 5

FIREWALL_ATOMIC_FOUND=false
FIREWALL_KALI_FOUND=false
TARGET_ATOMIC_FOUND=false
TARGET_KALI_FOUND=false

echo "Validating Firewall Logs (FW_FORWARD_ATTACK)..."
for i in $(seq 1 10); do
    if [ "${ACTIVE_ATOMICRED:-false}" = "true" ]; then
        if [ "$FIREWALL_ATOMIC_FOUND" = "false" ] && docker exec wazuh-manager grep "FW_FORWARD_ATTACK" /var/ossec/logs/alerts/alerts.log | grep -q "SRC=10.10.10.20 DST=10.10.20.10"; then
            FIREWALL_ATOMIC_FOUND=true
            echo "  [PASS] Firewall logged the Atomic Red Team attack traffic (10.10.10.20)."
        fi
    else
        FIREWALL_ATOMIC_FOUND=true
    fi
    
    if [ "${ACTIVE_KALI:-false}" = "true" ]; then
        if [ "$FIREWALL_KALI_FOUND" = "false" ] && docker exec wazuh-manager grep "FW_FORWARD_ATTACK" /var/ossec/logs/alerts/alerts.log | grep -q "SRC=10.10.10.10 DST=10.10.20.10"; then
            FIREWALL_KALI_FOUND=true
            echo "  [PASS] Firewall logged the Kali attacker-node traffic (10.10.10.10)."
        fi
    else
        FIREWALL_KALI_FOUND=true
    fi

    if [ "$FIREWALL_ATOMIC_FOUND" = "true" ] && [ "$FIREWALL_KALI_FOUND" = "true" ]; then
        break
    fi
    sleep 2
done

if [ "${ACTIVE_ATOMICRED:-false}" = "true" ] && [ "$FIREWALL_ATOMIC_FOUND" = "false" ]; then
    echo "  [FAIL] Firewall logs for Atomic Red Team (10.10.10.20) not found in alerts.log."
fi
if [ "${ACTIVE_KALI:-false}" = "true" ] && [ "$FIREWALL_KALI_FOUND" = "false" ]; then
    echo "  [FAIL] Firewall logs for Kali attacker-node (10.10.10.10) not found in alerts.log."
fi

echo "Validating Target Application Logs (sshd)..."
for i in $(seq 1 10); do
    if [ "${ACTIVE_ATOMICRED:-false}" = "true" ]; then
        if [ "$TARGET_ATOMIC_FOUND" = "false" ] && docker exec wazuh-manager grep "10.10.10.20" /var/ossec/logs/archives/archives.log | grep -v "FW_FORWARD_ATTACK" | grep -q "sshd.*Did not receive identification string from 10.10.10.20"; then
            TARGET_ATOMIC_FOUND=true
            echo "  [PASS] Target logged the Atomic Red Team port scan (10.10.10.20)."
        fi
    else
        TARGET_ATOMIC_FOUND=true
    fi

    if [ "${ACTIVE_KALI:-false}" = "true" ]; then
        if [ "$TARGET_KALI_FOUND" = "false" ] && docker exec wazuh-manager grep "10.10.10.10" /var/ossec/logs/archives/archives.log | grep -v "FW_FORWARD_ATTACK" | grep -q "sshd.*Bad protocol version identification 'kali_test_probe' from 10.10.10.10"; then
            TARGET_KALI_FOUND=true
            echo "  [PASS] Target logged the Kali malformed SSH connection (10.10.10.10) uniquely."
        fi
    else
        TARGET_KALI_FOUND=true
    fi

    if [ "$TARGET_ATOMIC_FOUND" = "true" ] && [ "$TARGET_KALI_FOUND" = "true" ]; then
        break
    fi
    sleep 2
done

if [ "${ACTIVE_ATOMICRED:-false}" = "true" ] && [ "$TARGET_ATOMIC_FOUND" = "false" ]; then
    echo "  [FAIL] Target application logs for Atomic Red Team (10.10.10.20) not found in archives.log."
fi
if [ "${ACTIVE_KALI:-false}" = "true" ] && [ "$TARGET_KALI_FOUND" = "false" ]; then
    echo "  [FAIL] Target application logs for Kali attacker-node (10.10.10.10) not found in archives.log."
fi

echo "=== Test Summary ==="
if [ "$FIREWALL_ATOMIC_FOUND" = "true" ] && [ "$FIREWALL_KALI_FOUND" = "true" ] && [ "$TARGET_ATOMIC_FOUND" = "true" ] && [ "$TARGET_KALI_FOUND" = "true" ]; then
    echo "ALL TESTS PASSED."
    exit 0
else
    echo "SOME TESTS FAILED."
    exit 1
fi
