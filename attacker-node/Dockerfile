FROM kalilinux/kali-rolling@sha256:a3849f99f9f187122de4822341c49e55d250a771f2dbc5cfd56a146017e0e6ae

RUN apt-get update && apt-get install -y --no-install-recommends \
    nmap \
    tcpdump \
    iproute2 \
    sudo \
    iputils-ping \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash hacker && \
    echo "hacker:attacker" | chpasswd && \
    usermod -aG sudo hacker

# Restrict sudo so hacker can only run nmap and tcpdump
RUN echo "hacker ALL=(ALL) NOPASSWD: /usr/bin/nmap, /usr/sbin/tcpdump, /usr/sbin/ip, /usr/bin/ping" > /etc/sudoers.d/hacker

USER 1000:1000
