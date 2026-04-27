#!/bin/bash
echo "Firewall rules script is running (NFLOG/ulogd2 mode)!"

# Apply firewall rules
iptables -F
iptables -P FORWARD DROP

# Allow related/established traffic
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Log Attacker to DMZ using NFLOG
# group 1 matches the ulogd.conf setting
iptables -A FORWARD -s 10.10.10.0/24 -d 10.10.20.0/24 -j NFLOG --nflog-prefix "FW_FORWARD_ATTACK" --nflog-group 1

# Allow Attacker to DMZ
iptables -A FORWARD -s 10.10.10.0/24 -d 10.10.20.0/24 -j ACCEPT

# Allow Attacker to SIEM
iptables -A FORWARD -s 10.10.10.0/24 -d 10.10.30.0/24 -j ACCEPT

# Allow DMZ to Pi-hole (DNS)
iptables -A FORWARD -s 10.10.20.0/24 -d 10.10.30.5 -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -s 10.10.20.0/24 -d 10.10.30.5 -p tcp --dport 53 -j ACCEPT

# Allow Internal to SIEM (Syslog)
iptables -A FORWARD -s 10.10.30.0/24 -d 10.10.30.0/24 -j ACCEPT

# Allow DMZ to send syslog to SIEM
iptables -A FORWARD -s 10.10.20.0/24 -d 10.10.30.10 -p udp --dport 514 -j ACCEPT

# Ensure required directories for rsyslog and ulogd exist on tmpfs
mkdir -p /var/log /var/spool/rsyslog /var/run /run

# Start rsyslogd to handle local syslog and forward to SIEM
# -n: run in foreground (will handle forwarding based on /etc/rsyslog.conf)
rsyslogd -n &
RSYSLOG_PID=$!

# Wait for rsyslogd to create /dev/log
for i in $(seq 1 10); do
    [ -S /dev/log ] && break
    sleep 0.5
done

# Start ulogd to capture NFLOG and send to syslog
ulogd -d

# Block here; if rsyslogd dies, the container restarts via Docker policy.
wait $RSYSLOG_PID
