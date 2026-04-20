FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    iptables \
    ulogd2 \
    rsyslog \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

# The Debian package for ulogd2 might create a 'ulog' user. 
# We'll create our 'firewall' user just in case, though the service
# override in docker-compose.yml uses user: "0:0".
RUN groupadd -g 1000 firewall && \
    useradd -u 1000 -g firewall -s /bin/bash -m firewall

COPY firewall-rules.sh /firewall-rules.sh
COPY ulogd.conf /etc/ulogd.conf
COPY rsyslog.conf /etc/rsyslog.conf

RUN chmod +x /firewall-rules.sh

# Run as root because iptables and ulogd (netlink) require it.
USER root

CMD ["/firewall-rules.sh"]
