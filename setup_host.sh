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

echo "Host setup complete."
