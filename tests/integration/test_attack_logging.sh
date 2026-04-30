#!/bin/bash
# Integration test to validate attack logging from both the firewall and the target, and DNS logs via Pi-hole.
set -euo pipefail

SPLUNK_PASSWORD=""
if [ -f "configs/.env" ]; then
    SPLUNK_PASSWORD=$(grep '^SPLUNK_PASSWORD=' configs/.env 2>/dev/null | cut -d'=' -f2- | tr -d '"' || true)
fi

if [ -f "configs/.active_lab.env" ]; then
    source configs/.active_lab.env
else
    echo "WARNING: configs/.active_lab.env not found. Assuming all components are active."
fi

echo "=== Running Attack Logging Integration Test ==="

HAS_Wazuh=false
if [ "${ACTIVE_WAZUH:-false}" = "true" ] || [ "${ACTIVE_SPLUNK:-false}" = "true" ]; then
    HAS_Wazuh=true
fi

if [ "$HAS_Wazuh" != "true" ]; then
    echo "No Wazuh is active. Skipping attack logging integration tests."
    exit 0
fi

HAS_TARGET=false
if [ "${ACTIVE_METASPLOITABLE2:-false}" = "true" ] || [ "${ACTIVE_UBUNTU:-false}" = "true" ]; then
    HAS_TARGET=true
fi

if [ "$HAS_TARGET" != "true" ]; then
    echo "No target is active. Skipping attack logging integration tests."
    exit 0
fi

TARGET_IP=""
TARGET_NAME=""
if [ "${ACTIVE_METASPLOITABLE2:-false}" = "true" ]; then
    TARGET_IP="10.10.20.10"
    TARGET_NAME="metasploitable2"
elif [ "${ACTIVE_UBUNTU:-false}" = "true" ]; then
    TARGET_IP="10.10.20.15" # We assume it's roughly here or the name resolves
    TARGET_NAME="ubuntu-target"
fi

# 1. Execute the attacks
if [ "${ACTIVE_ATOMICRED:-false}" = "true" ] && [ -n "$TARGET_IP" ]; then
    echo "Initiating Nmap port scan from atomic-red (10.10.10.20) to ${TARGET_NAME}..."
    docker exec atomic-red pwsh -c "Invoke-AtomicTest T1046 -TestNumbers 12 -InputArgs @{'host'='${TARGET_IP}'; 'port_range'='1-100'}" >/dev/null || true
fi

if [ "${ACTIVE_KALI:-false}" = "true" ] && [ -n "$TARGET_IP" ]; then
    echo "Initiating malformed SSH connection from kali (10.10.10.10) to ${TARGET_NAME}..."
    docker exec kali bash -c "</dev/tcp/${TARGET_IP}/22; sleep 1; echo 'kali_test_probe' > /dev/tcp/${TARGET_IP}/22" 2>/dev/null || true
fi

# 2. Execute DNS Test via Pi-hole
TEST_DOMAIN="pihole-test-domain-${RANDOM}.com"
echo "Initiating DNS query for $TEST_DOMAIN from ${TARGET_NAME} via Pi-hole (10.10.30.5)..."
docker exec ${TARGET_NAME} bash -c "nslookup ${TEST_DOMAIN} 10.10.30.5 || ping -c 1 ${TEST_DOMAIN} || getent hosts ${TEST_DOMAIN}" >/dev/null 2>&1 || true

echo "Waiting 45 seconds for logs to be ingested by Wazuh(s)..."
sleep 45

ALL_PASSED=true

function check_wazuh_log {
    local file=$1
    local pattern=$2
    for i in $(seq 1 5); do
        if docker exec wazuh-manager grep -E "$pattern" "$file" >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    return 1
}

function check_splunk_log {
    local query=$1
    echo "  [DEBUG] Running Splunk query: search index=* earliest=-10m $query"
    for i in $(seq 1 20); do
        if docker exec --user splunk splunk /opt/splunk/bin/splunk search "index=* earliest=-10m $query" -auth "admin:${SPLUNK_PASSWORD}" 2>/dev/null | grep -vE "^WARNING:|^INFO:" | grep . >/dev/null; then
            return 0
        fi
        sleep 3
    done
    return 1
}

if [ "${ACTIVE_ATOMICRED:-false}" = "true" ]; then
    echo "Validating Atomic Red Team Firewall Logs..."
    if [ "${ACTIVE_WAZUH:-false}" = "true" ]; then
        if check_wazuh_log "/var/ossec/logs/alerts/alerts.log" "FW_FORWARD_ATTACK.*SRC=10.10.10.20 DST=${TARGET_IP}"; then
            echo "  [PASS] Wazuh: Firewall logged Atomic Red Team traffic."
        else
            echo "  [FAIL] Wazuh: Firewall logs for Atomic Red Team not found."
            ALL_PASSED=false
        fi
    fi
    if [ "${ACTIVE_SPLUNK:-false}" = "true" ]; then
        if check_splunk_log "FW_FORWARD_ATTACK SRC=10.10.10.20 DST=${TARGET_IP}"; then
            echo "  [PASS] Splunk: Firewall logged Atomic Red Team traffic."
        else
            echo "  [FAIL] Splunk: Firewall logs for Atomic Red Team not found."
            ALL_PASSED=false
        fi
    fi
    
    echo "Validating Atomic Red Team Target Logs..."
    if [ "${ACTIVE_WAZUH:-false}" = "true" ]; then
        if check_wazuh_log "/var/ossec/logs/archives/archives.log" "sshd.*Did not receive identification string from 10.10.10.20"; then
            echo "  [PASS] Wazuh: Target logged Atomic Red Team port scan."
        else
            echo "  [FAIL] Wazuh: Target application logs for Atomic Red Team not found."
            ALL_PASSED=false
        fi
    fi
    if [ "${ACTIVE_SPLUNK:-false}" = "true" ]; then
        if check_splunk_log "\"Did not receive identification string from 10.10.10.20\""; then
            echo "  [PASS] Splunk: Target logged Atomic Red Team port scan."
        else
            echo "  [FAIL] Splunk: Target application logs for Atomic Red Team not found."
            ALL_PASSED=false
        fi
    fi
fi

if [ "${ACTIVE_KALI:-false}" = "true" ]; then
    echo "Validating Kali Firewall Logs..."
    if [ "${ACTIVE_WAZUH:-false}" = "true" ]; then
        if check_wazuh_log "/var/ossec/logs/alerts/alerts.log" "FW_FORWARD_ATTACK.*SRC=10.10.10.10 DST=${TARGET_IP}"; then
            echo "  [PASS] Wazuh: Firewall logged Kali traffic."
        else
            echo "  [FAIL] Wazuh: Firewall logs for Kali not found."
            ALL_PASSED=false
        fi
    fi
    if [ "${ACTIVE_SPLUNK:-false}" = "true" ]; then
        if check_splunk_log "FW_FORWARD_ATTACK SRC=10.10.10.10 DST=${TARGET_IP}"; then
            echo "  [PASS] Splunk: Firewall logged Kali traffic."
        else
            echo "  [FAIL] Splunk: Firewall logs for Kali not found."
            ALL_PASSED=false
        fi
    fi
    
    echo "Validating Kali Target Logs..."
    if [ "${ACTIVE_WAZUH:-false}" = "true" ]; then
        if check_wazuh_log "/var/ossec/logs/archives/archives.log" "sshd.*Bad protocol version identification 'kali_test_probe' from 10.10.10.10"; then
            echo "  [PASS] Wazuh: Target logged Kali malformed SSH connection."
        else
            echo "  [FAIL] Wazuh: Target application logs for Kali not found."
            ALL_PASSED=false
        fi
    fi
    if [ "${ACTIVE_SPLUNK:-false}" = "true" ]; then
        if check_splunk_log "\"Bad protocol version identification 'kali_test_probe' from 10.10.10.10\""; then
            echo "  [PASS] Splunk: Target logged Kali malformed SSH connection."
        else
            echo "  [FAIL] Splunk: Target application logs for Kali not found."
            ALL_PASSED=false
        fi
    fi
fi

echo "Validating Pi-hole DNS Logs..."
if [ "${ACTIVE_WAZUH:-false}" = "true" ]; then
    if check_wazuh_log "/var/ossec/logs/archives/archives.log" "query.*${TEST_DOMAIN}"; then
        echo "  [PASS] Wazuh: Pi-hole logged the DNS query for ${TEST_DOMAIN}."
    else
        echo "  [FAIL] Wazuh: Pi-hole DNS logs not found for ${TEST_DOMAIN}."
        ALL_PASSED=false
    fi
fi
if [ "${ACTIVE_SPLUNK:-false}" = "true" ]; then
    if check_splunk_log "\"${TEST_DOMAIN}\""; then
        echo "  [PASS] Splunk: Pi-hole logged the DNS query for ${TEST_DOMAIN}."
    else
        echo "  [FAIL] Splunk: Pi-hole DNS logs not found for ${TEST_DOMAIN}."
        ALL_PASSED=false
    fi
fi

echo "Validating Wiretap Packet Capture..."
PCAP_FOUND=false
for pcap in logs/pcaps/homelab-capture.pcap*; do
    if [ -f "$pcap" ]; then
        filename=$(basename "$pcap")
        if docker exec wiretap tcpdump -r "/pcaps/$filename" -n 2>/dev/null | grep "${TEST_DOMAIN}" >/dev/null; then
            echo "  [PASS] Wiretap: Captured DNS traffic for ${TEST_DOMAIN} in $filename."
            PCAP_FOUND=true
            break
        fi
    fi
done

if [ "$PCAP_FOUND" = "false" ]; then
    echo "  [FAIL] Wiretap: Did not capture DNS traffic for ${TEST_DOMAIN}."
    ALL_PASSED=false
fi

echo "=== Test Summary ==="
if [ "$ALL_PASSED" = "true" ]; then
    echo "ALL TESTS PASSED."
    exit 0
else
    echo "SOME TESTS FAILED."
    exit 1
fi
