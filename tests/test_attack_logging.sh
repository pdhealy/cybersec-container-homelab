#!/bin/bash
# Integration test to validate attack logging from both the firewall and the target.
set -euo pipefail

echo "=== Running Attack Logging Integration Test ==="

# 1. Execute the attacks
echo "[1/6] Initiating Nmap port scan from atomic-red (10.10.10.20) to vulnerable-target..."
docker exec atomic-red pwsh -c "Invoke-AtomicTest T1046 -TestNumbers 12 -InputArgs @{'host'='10.10.20.10'; 'port_range'='1-100'}" >/dev/null

echo "[2/6] Initiating malformed SSH connection from attacker-node (10.10.10.10) to vulnerable-target..."
# We send a specific string "kali_test_probe" to uniquely identify this test's application log
docker exec attacker-node bash -c '</dev/tcp/10.10.20.10/22; sleep 1; echo "kali_test_probe" > /dev/tcp/10.10.20.10/22' 2>/dev/null || true

echo "[3/6] Waiting for logs to be ingested by Wazuh SIEM..."
sleep 5

FIREWALL_ATOMIC_FOUND=false
FIREWALL_KALI_FOUND=false
TARGET_ATOMIC_FOUND=false
TARGET_KALI_FOUND=false

# 2. Check for Firewall Logs
echo "[4/6] Validating Firewall Logs (FW_FORWARD_ATTACK)..."
for i in $(seq 1 10); do
    if [ "$FIREWALL_ATOMIC_FOUND" = "false" ] && docker exec wazuh-manager grep "FW_FORWARD_ATTACK" /var/ossec/logs/alerts/alerts.log | grep -q "SRC=10.10.10.20 DST=10.10.20.10"; then
        FIREWALL_ATOMIC_FOUND=true
        echo "  [PASS] Firewall logged the Atomic Red Team attack traffic (10.10.10.20)."
    fi
    
    if [ "$FIREWALL_KALI_FOUND" = "false" ] && docker exec wazuh-manager grep "FW_FORWARD_ATTACK" /var/ossec/logs/alerts/alerts.log | grep -q "SRC=10.10.10.10 DST=10.10.20.10"; then
        FIREWALL_KALI_FOUND=true
        echo "  [PASS] Firewall logged the Kali attacker-node traffic (10.10.10.10)."
    fi

    if [ "$FIREWALL_ATOMIC_FOUND" = "true" ] && [ "$FIREWALL_KALI_FOUND" = "true" ]; then
        break
    fi
    sleep 2
done

if [ "$FIREWALL_ATOMIC_FOUND" = "false" ]; then
    echo "  [FAIL] Firewall logs for Atomic Red Team (10.10.10.20) not found in alerts.log."
fi
if [ "$FIREWALL_KALI_FOUND" = "false" ]; then
    echo "  [FAIL] Firewall logs for Kali attacker-node (10.10.10.10) not found in alerts.log."
fi

# 3. Check for Target Application Logs
echo "[5/6] Validating Target Application Logs (sshd)..."
for i in $(seq 1 10); do
    if [ "$TARGET_ATOMIC_FOUND" = "false" ] && docker exec wazuh-manager grep "10.10.10.20" /var/ossec/logs/archives/archives.log | grep -v "FW_FORWARD_ATTACK" | grep -q "sshd.*Did not receive identification string from 10.10.10.20"; then
        TARGET_ATOMIC_FOUND=true
        echo "  [PASS] Target logged the Atomic Red Team port scan (10.10.10.20)."
    fi

    if [ "$TARGET_KALI_FOUND" = "false" ] && docker exec wazuh-manager grep "10.10.10.10" /var/ossec/logs/archives/archives.log | grep -v "FW_FORWARD_ATTACK" | grep -q "sshd.*Bad protocol version identification 'kali_test_probe' from 10.10.10.10"; then
        TARGET_KALI_FOUND=true
        echo "  [PASS] Target logged the Kali malformed SSH connection (10.10.10.10) uniquely."
    fi

    if [ "$TARGET_ATOMIC_FOUND" = "true" ] && [ "$TARGET_KALI_FOUND" = "true" ]; then
        break
    fi
    sleep 2
done

if [ "$TARGET_ATOMIC_FOUND" = "false" ]; then
    echo "  [FAIL] Target application logs for Atomic Red Team (10.10.10.20) not found in archives.log."
fi
if [ "$TARGET_KALI_FOUND" = "false" ]; then
    echo "  [FAIL] Target application logs for Kali attacker-node (10.10.10.10) not found in archives.log."
fi

echo "[6/6] === Test Summary ==="
if [ "$FIREWALL_ATOMIC_FOUND" = "true" ] && [ "$FIREWALL_KALI_FOUND" = "true" ] && [ "$TARGET_ATOMIC_FOUND" = "true" ] && [ "$TARGET_KALI_FOUND" = "true" ]; then
    echo "ALL TESTS PASSED."
    exit 0
else
    echo "SOME TESTS FAILED."
    exit 1
fi
