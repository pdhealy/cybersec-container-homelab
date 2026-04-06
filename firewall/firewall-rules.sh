#!/bin/bash

# Apply firewall rules
iptables -F
iptables -P FORWARD DROP

# Allow related/established traffic
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Allow Attacker to DMZ
iptables -A FORWARD -s 10.10.10.0/24 -d 10.10.20.0/24 -j ACCEPT

# Allow Attacker to SIEM
iptables -A FORWARD -s 10.10.10.0/24 -d 10.10.30.0/24 -j ACCEPT

# Loop infinitely to keep the container running
tail -f /dev/null
