#!/bin/bash
echo "--- Phase 6: End-to-End Validation ---"
echo "1. Build & Structural Validation"
for img in homelab-attacker:latest homelab-firewall:latest; do
  echo "$img USER directive:"
  docker inspect $img --format '{{.Config.User}}'
done

echo -e "\n2. Runtime & Security Context Validation"
for c in attacker-node firewall pihole wazuh-manager vulnerable-target; do
  echo "Container: $c"
  docker inspect $c --format '  ReadonlyRootfs: {{.HostConfig.ReadonlyRootfs}}'
  docker inspect $c --format '  SecurityOpt: {{.HostConfig.SecurityOpt}}'
  docker inspect $c --format '  CapDrop: {{.HostConfig.CapDrop}}'
done

echo -e "\n3. Network Isolation & Connectivity Testing"
echo "ICC Verification (pihole to wazuh-manager)"
docker exec pihole ping -c 1 -W 2 10.10.30.10 && echo "FAIL: ICC allowed ping" || echo "PASS: ICC ping failed as expected"

echo "Firewall Enforcement (attacker to vulnerable-target)"
docker exec attacker-node ping -c 1 -W 2 10.10.20.10 && echo "PASS: Firewall routed successfully" || echo "FAIL: Firewall ping dropped"

echo "Drop Policy (vulnerable-target to attacker)"
docker exec vulnerable-target ping -c 1 -W 2 10.10.10.10 && echo "FAIL: Drop policy not active" || echo "PASS: Drop policy active as expected"

echo -e "\n4. Service & API Health Checks"
docker inspect firewall --format 'Firewall Health: {{.State.Health.Status}}'
docker exec wazuh-manager curl -s -k -u admin:SecretPassword123! https://127.0.0.1:55000/ > /dev/null && echo "SIEM API is reachable" || echo "SIEM API failed"
