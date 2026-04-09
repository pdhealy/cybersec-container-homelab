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

# Configure iptables for cross-bridge routing (version-aware).
#
# Legacy Docker (DOCKER-ISOLATION-STAGE-1/2 chains): those chains unconditionally
# DROP inter-bridge forwarding.  An ACCEPT rule in DOCKER-USER (evaluated first)
# is required to let the firewall container route packets between networks.
#
# Modern Docker 27+ (DOCKER-FORWARD chain): when enable_icc=false is set, Docker
# automatically adds per-bridge rules that DROP same-bridge traffic (ICC block)
# AND ACCEPT cross-bridge traffic (routing OK).  No DOCKER-USER override is
# needed — inserting one would break ICC isolation by matching before the DROP.
#
# NOTE: Docker chains only exist after the daemon starts.  If not yet running,
# re-run this script or use `lab_manager.py up` (which calls this logic too).
configure_docker_user_chain() {
    if ! iptables -L DOCKER-USER -n > /dev/null 2>&1; then
        echo "WARNING: DOCKER-USER chain not found. Start the Docker daemon first."
        echo "  Re-run this script or use 'sudo ./lab_manager.py up'."
        return
    fi

    # Detect Docker version model.
    if iptables -L DOCKER-FORWARD -n > /dev/null 2>&1; then
        echo "Modern Docker detected (DOCKER-FORWARD chain): cross-bridge routing"
        echo "  is handled natively by enable_icc=false — no DOCKER-USER rule needed."
        return
    fi

    # Legacy Docker: insert ACCEPT into DOCKER-USER idempotently.
    echo "Legacy Docker detected (DOCKER-ISOLATION-STAGE chains): inserting DOCKER-USER rule."
    if ! iptables -C DOCKER-USER -i br-+ -o br-+ -j ACCEPT 2>/dev/null; then
        iptables -I DOCKER-USER -i br-+ -o br-+ -j ACCEPT
        echo "DOCKER-USER: Cross-bridge ACCEPT rule added."
    else
        echo "DOCKER-USER: Cross-bridge ACCEPT rule already present (idempotent)."
    fi
}

configure_docker_user_chain

echo "Host setup complete."
