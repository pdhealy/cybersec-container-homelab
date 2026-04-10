#!/bin/bash
echo "Firewall rules script is running!"

# Apply firewall rules
iptables -F
iptables -P FORWARD DROP

# Allow related/established traffic
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Log Attacker to DMZ
iptables -A FORWARD -s 10.10.10.0/24 -d 10.10.20.0/24 -j LOG --log-prefix "FW_FORWARD_ATTACK: "

# Allow Attacker to DMZ
iptables -A FORWARD -s 10.10.10.0/24 -d 10.10.20.0/24 -j ACCEPT

# Allow Attacker to SIEM
iptables -A FORWARD -s 10.10.10.0/24 -d 10.10.30.0/24 -j ACCEPT

# Start syslogd first and wait for it to create /dev/log before other daemons
# connect.  -n: don't daemonize  -R host:port: forward to SIEM  -L: log locally
syslogd -n -R 10.10.30.10:514 -L &
SYSLOGD_PID=$!

# Poll for /dev/log (Unix socket created by syslogd) — timeout 5 s.
for i in $(seq 1 10); do
    [ -S /dev/log ] && break
    sleep 0.5
done

# NOTE: iptables-nft (kernel 6.x) writes LOG target output to the netlink
# subsystem, NOT to /proc/kmsg.  klogd therefore never sees the entries.
# Instead we use tcpdump to observe FORWARDED attack packets in real time and
# emit a properly-formatted FW_FORWARD_ATTACK syslog message for each one.
# This gives the SIEM real SRC/DST data without any kernel-log dependency.
#
# -i eth2  : external/attacker interface (10.10.10.0/24 arrives here)
# -n       : no reverse DNS lookups
# -l       : line-buffered so the pipeline sees output immediately
# awk      : extract source and destination IPs, then call logger once per packet
tcpdump -l -i eth2 -n 'src net 10.10.10.0/24 and dst net 10.10.20.0/24' 2>/dev/null | \
awk '{
    src=""; dst="";
    for(i=1;i<=NF;i++){
        if($i ~ /^10\.10\.10\.[0-9]+$/)            src=$i;
        if($i ~ /^10\.10\.20\.[0-9]+(:|>)/)        dst=substr($i,1,index($i,".")+2);
    }
    # re-extract dst properly (remove trailing : or >)
    n=split($0,a," "); for(j=1;j<=n;j++){ if(a[j]~/^10\.10\.20\.[0-9]/) { gsub(/[^0-9.]/,"",a[j]); dst=a[j]; break }}
    if(src!="" && dst!=""){
        cmd="logger -t kernel \"FW_FORWARD_ATTACK: IN=eth2 OUT=eth1 SRC=" src " DST=" dst " PROTO=IP\"";
        system(cmd);
    }
}' &

# Block here; if syslogd dies, the container restarts via Docker policy.
wait $SYSLOGD_PID
