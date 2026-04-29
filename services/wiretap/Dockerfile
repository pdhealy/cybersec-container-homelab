FROM alpine:latest

# Install necessary network and cybersecurity utilities for the wiretap sidecar
RUN apk add --no-cache \
    tcpdump \
    tshark \
    nmap \
    curl \
    iproute2 \
    bind-tools \
    netcat-openbsd \
    bash \
    jq \
    ngrep

# Ensure pcaps directory exists
RUN mkdir -p /pcaps

CMD ["tail", "-f", "/dev/null"]
