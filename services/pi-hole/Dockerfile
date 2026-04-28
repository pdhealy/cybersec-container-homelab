FROM pihole/pihole@sha256:300cc8f9e966b00440358aafef21f91b32dfe8887e8bd9a6193ed1c4328655d4

# Install rsyslog
RUN apt-get update && apt-get install -y --no-install-recommends rsyslog || apk add --no-cache rsyslog

# Add custom rsyslog configuration
COPY rsyslog.conf /etc/rsyslog.conf
