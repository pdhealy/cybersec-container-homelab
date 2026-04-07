FROM kalilinux/kali-rolling@sha256:a3849f99f9f187122de4822341c49e55d250a771f2dbc5cfd56a146017e0e6ae

RUN apt-get update && apt-get install -y --no-install-recommends \
    nmap \
    tcpdump \
    iproute2 \
    sudo \
    iputils-ping \
    curl \
    gosu \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash hacker && \
    echo "hacker:attacker" | chpasswd && \
    usermod -aG sudo hacker

# Restrict sudo so hacker can only run specific network tools.
RUN echo "hacker ALL=(ALL) NOPASSWD: /usr/bin/nmap, /usr/sbin/tcpdump, /usr/sbin/ip, /usr/bin/ping" > /etc/sudoers.d/hacker

# The container must start as root (uid 0) to configure the default route via
# `ip route`, then drop to the unprivileged hacker user using gosu.  The
# docker-compose.yml overrides the USER directive to 0:0 at runtime to permit
# this entrypoint pattern.  gosu is preferred over `su` because it uses exec(3)
# to replace the current process, ensuring the final process has no residual
# root capabilities.
USER 1000:1000
