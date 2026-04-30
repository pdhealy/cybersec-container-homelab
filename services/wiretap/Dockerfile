FROM alpine@sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11

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
