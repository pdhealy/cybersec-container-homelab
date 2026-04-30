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

# Configure DOCKER-USER and raw iptables chains for cross-bridge routing.
# Docker's ICC=false drops intra-bridge traffic and creates PREROUTING
# raw table drop rules. We insert exceptions to allow the firewall container
# to route packets between networks.
configure_docker_user_chain() {
    if iptables -L DOCKER-USER -n > /dev/null 2>&1; then
        echo "Configuring iptables for cross-bridge routing while maintaining icc=false..."

        # Rules to apply
        RULES=(
            "-t raw -I PREROUTING -s 10.10.10.0/24 ! -d 10.10.10.0/24 -j ACCEPT"
            "-t raw -I PREROUTING -s 10.10.20.0/24 ! -d 10.10.20.0/24 -j ACCEPT"
            "-t raw -I PREROUTING -s 10.10.30.0/24 ! -d 10.10.30.0/24 -j ACCEPT"
            "-t raw -I PREROUTING -s 10.10.30.5 -d 10.10.30.10 -j ACCEPT"
            "-t raw -I PREROUTING -s 10.10.30.5 -d 10.10.30.15 -j ACCEPT"
            "-t raw -I PREROUTING -d 10.10.10.254 -j ACCEPT"
            "-t raw -I PREROUTING -d 10.10.20.254 -j ACCEPT"
            "-t raw -I PREROUTING -d 10.10.30.254 -j ACCEPT"
            "-t filter -I DOCKER-USER -s 10.10.10.0/24 ! -d 10.10.10.0/24 -j ACCEPT"
            "-t filter -I DOCKER-USER -s 10.10.20.0/24 ! -d 10.10.20.0/24 -j ACCEPT"
            "-t filter -I DOCKER-USER -s 10.10.30.0/24 ! -d 10.10.30.0/24 -j ACCEPT"
            "-t filter -I DOCKER-USER -s 10.10.30.5 -d 10.10.30.10 -p udp --dport 514 -j ACCEPT"
            "-t filter -I DOCKER-USER -s 10.10.30.5 -d 10.10.30.15 -p udp --dport 1514 -j ACCEPT"
            "-t filter -I DOCKER-USER -d 10.10.10.254 -j ACCEPT"
            "-t filter -I DOCKER-USER -d 10.10.20.254 -j ACCEPT"
            "-t filter -I DOCKER-USER -d 10.10.30.254 -j ACCEPT"
            "-t filter -I DOCKER-USER -s 10.10.10.254 -j ACCEPT"
            "-t filter -I DOCKER-USER -s 10.10.20.254 -j ACCEPT"
            "-t filter -I DOCKER-USER -s 10.10.30.254 -j ACCEPT"
        )

        for rule in "${RULES[@]}"; do
            # Replace -I with -C to check if the rule already exists
            check_rule="${rule/-I /-C }"
            if ! iptables $check_rule 2>/dev/null; then
                iptables $rule
            fi
        done

        if iptables -C DOCKER-USER -i br-+ -o br-+ -j ACCEPT 2>/dev/null; then
            iptables -D DOCKER-USER -i br-+ -o br-+ -j ACCEPT
        fi

        echo "DOCKER-USER/raw PREROUTING: Cross-bridge ACCEPT rules applied."
    else
        echo "WARNING: DOCKER-USER chain not found. Start the Docker daemon first."
        echo "  Re-run this script or use 'sudo ./lab_manager.py up' to apply the rule."
    fi
}

configure_docker_user_chain

echo "Host setup complete."
