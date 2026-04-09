#!/bin/bash
set -e

echo "Setting up host for Cyber Homelab..."

# Apply sysctl settings
sysctl -w vm.max_map_count=262144

# Disable swap
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1

# Disable IPv6
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1

sysctl -p

# Configure DOCKER-USER iptables chain for cross-bridge routing.
# Docker's DOCKER-ISOLATION-STAGE chains block inter-bridge forwarding by default.
# The DOCKER-USER chain is evaluated BEFORE isolation chains, so inserting an ACCEPT
# rule here allows the firewall container to route packets between networks while
# Docker's own containers on the same bridge remain isolated (ICC=false is enforced
# at the bridge level independently).
#
# NOTE: The DOCKER-USER chain is created by the Docker daemon. This section must
# run after Docker has started. If Docker is not yet running, re-run this script
# or use `lab_manager.py up` which applies this rule automatically post-compose.
configure_docker_user_chain() {
    if iptables -L DOCKER-USER -n > /dev/null 2>&1; then
        if ! iptables -C DOCKER-USER -i br-+ -o br-+ -j ACCEPT 2>/dev/null; then
            iptables -I DOCKER-USER -i br-+ -o br-+ -j ACCEPT
            echo "DOCKER-USER: Added cross-bridge ACCEPT rule for firewall container routing."
        else
            echo "DOCKER-USER: Cross-bridge ACCEPT rule already present (idempotent)."
        fi
    else
        echo "WARNING: DOCKER-USER chain not found. Start the Docker daemon first."
        echo "  Re-run this script or use 'sudo ./lab_manager.py up' to apply the rule."
    fi
}

configure_docker_user_chain

echo "Host setup complete."
