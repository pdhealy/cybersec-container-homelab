FROM pihole/pihole@sha256:300cc8f9e966b00440358aafef21f91b32dfe8887e8bd9a6193ed1c4328655d4

# Install rsyslog
RUN apt-get update && apt-get install -y --no-install-recommends rsyslog || apk add --no-cache rsyslog

# Make Pi-hole startup compatible with read-only rootfs and offline bootstrap.
RUN sed -i 's#chown pihole:pihole /macvendor.db#chown pihole:pihole /macvendor.db || true#g' /usr/bin/bash_functions.sh && \
    sed -i '/ftl_config/a\    if [ ! -f /etc/pihole/gravity.db ]; then pihole-FTL sqlite3 -ni /etc/pihole/gravity.db < /etc/.pihole/advanced/Templates/gravity.db.sql; fi' /usr/bin/start.sh

# Add custom rsyslog configuration
COPY rsyslog.conf /etc/rsyslog.conf
COPY 99-logging.conf /etc/dnsmasq.d/99-logging.conf
