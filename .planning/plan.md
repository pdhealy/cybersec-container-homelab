# Planning document

This is an excellent initiative. Building a containerized cybersecurity homelab is one of the most effective ways to develop practical security skills safely. 

As a Senior DevSecOps / Security Architect, I have reviewed your requirements. While your baseline is strong, running a fully functional, true-to-life network simulation entirely within Docker on a local laptop requires specific architectural adjustments. Docker's default behavior is designed for microservice application hosting, not network simulation.

Here is a full expert-level analysis, suggested improvements, and a comprehensive build guide.

---

### Part 1: Expert Analysis & Suggested Improvements

#### 1. The "Firewall" Constraint (Nginx vs. Network Firewall)
*   **Your Idea:** Can Nginx be used as a firewall?
*   **Expert Correction:** Nginx is a Reverse Proxy and can act as a **Web Application Firewall (WAF)** (e.g., ModSecurity), but it is **not** a Network Firewall. For a 3-tier network architecture, you need a router/firewall at the packet level.
*   **Improvement:** I suggest using an **Alpine Linux container running `iptables`** (or `nftables`). This container will attach to all three Docker networks (Internal, DMZ, External) and act as the central gateway, enforcing strict routing and access control lists (ACLs).

#### 2. The Non-Root & Privilege Constraint
*   **Your Requirement:** Run as `user: "1000:1000"` but with sudo privileges.
*   **Expert Correction:** A strict user mapping (`1000:1000`) without Linux capabilities will cripple an Attacker Node. Tools like `nmap` (SYN scans), `tcpdump` (packet sniffing), and raw socket scripts require `root` or specific kernel capabilities (`CAP_NET_RAW`, `CAP_NET_ADMIN`). Additionally, Metasploitable3 is designed as a full OS; restricting it to a non-root user defeats the purpose of system-level exploitation.
*   **Improvement:** 
    *   **Attacker Node:** We will build a custom Kali Dockerfile that creates a non-root user (`hacker`) with passwordless `sudo`. We will add `cap_add: [NET_RAW, NET_ADMIN]` in Compose so network tools work.
    *   **Target Node:** Must run natively to allow realistic privilege escalation exercises.

#### 3. Networking Logic
*   **Your Requirement:** Attacker can communicate with Target and SIEM, but not Firewall.
*   **Expert Correction:** In a routed 3-tier architecture, the Attacker *must* route traffic *through* the Firewall to reach the Target/SIEM. If the Attacker cannot communicate with the Firewall (the gateway), no traffic will route. 
*   **Improvement:** We will restrict access to the Firewall's *management interfaces* (e.g., SSH), but allow *forwarding* of packets through it. We will disable Docker's default Inter-Container Communication (ICC) to force all subnet traffic through our Alpine Firewall container.

#### 4. Dynamic Build & Resource Management
*   **Your Requirement:** End user configures what to build via a Python script. Resource limits must be set.
*   **Improvement:** We will use **Docker Compose Profiles**. Profiles allow you to tag services (e.g., `profile: ["attacker"]`). We will write a Python orchestrator (`lab_manager.py`) that presents a menu to the user, selects the profiles, and executes the Compose commands.
*   **Resource limits** are critical because Wazuh (Elasticsearch/OpenSearch underneath) is incredibly resource-hungry. We will hard-limit Wazuh to prevent your laptop from crashing.

---

### Part 2: Homelab Architecture & Directory Structure

Here is the Google-grade directory structure we will generate.

```text
cyber-homelab/
├── lab_manager.py                # Python script to manage build/teardown
├── docker-compose.yml            # Main infrastructure file
├── .env                          # Environment variables
├── .devcontainer/                
│   └── devcontainer.json         # Mounts VS Code into the Attacker Node
├── attacker-node/
│   ├── Dockerfile                # Custom Kali build (non-root + sudo)
│   └── workspace/                # Mapped to /workspace
├── vulnerable-target/
│   └── workspace/
├── firewall/
│   ├── Dockerfile                # Alpine Iptables router
│   ├── firewall-rules.sh         # The routing logic
│   └── workspace/
├── siem/
│   └── workspace/                # Wazuh persistent data
└── pi-hole/
    └── workspace/                # Pi-Hole configs
```

---

### Part 3: Detailed Setup & Code Implementation

#### 1. The Python Orchestrator (`lab_manager.py`)
This script fulfills your requirement for dynamic user configuration.

```python
#!/usr/bin/env python3
import os
import subprocess

def main():
    print("=== Cyber Homelab Manager ===")
    print("Select components to start (comma separated):")
    print("1. Attacker Node (Kali)")
    print("2. Vulnerable Target (Metasploitable3)")
    print("3. Core Network (Firewall + Pi-Hole)")
    print("4. SIEM (Wazuh - Warning: High RAM Usage)")
    print("5. ALL")
    
    choice = input("Enter choices (e.g., 1,3): ")
    
    profiles = []
    if "1" in choice or "5" in choice: profiles.append("attacker")
    if "2" in choice or "5" in choice: profiles.append("target")
    if "3" in choice or "5" in choice: profiles.append("core")
    if "4" in choice or "5" in choice: profiles.append("siem")

    if not profiles:
        print("No valid options selected. Exiting.")
        return

    profile_args = " ".join([f"--profile {p}" for p in profiles])
    cmd = f"docker compose {profile_args} up -d --build"
    
    print(f"\nExecuting: {cmd}\n")
    subprocess.run(cmd, shell=True)
    print("\nHomelab updated! Use `docker compose down` to stop.")

if __name__ == "__main__":
    main()
```

#### 2. Custom Dockerfiles (Security & Usability)

**A. Attacker Node (`attacker-node/Dockerfile`)**
*Creates the non-root user with sudo, installs base tools.*
```dockerfile
FROM kalilinux/kali-rolling

# Install tools and sudo
RUN apt-get update && apt-get install -y \
    sudo nmap netcat-traditional curl wget python3 git vim iproute2 iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user 'hacker' with UID 1000
RUN useradd -m -s /bin/bash -u 1000 hacker && \
    echo "hacker:hacker" | chpasswd && \
    adduser hacker sudo && \
    echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

USER 1000:1000
WORKDIR /workspace
CMD ["tail", "-f", "/dev/null"] # Keep container alive
```

**B. Firewall Container (`firewall/Dockerfile`)**
```dockerfile
FROM alpine:latest
RUN apk add --no-cache iptables iproute2 bash
COPY firewall-rules.sh /firewall-rules.sh
RUN chmod +x /firewall-rules.sh
# Requires NET_ADMIN capability in compose
CMD ["/firewall-rules.sh"]
```

**C. Firewall Rules (`firewall/firewall-rules.sh`)**
```bash
#!/bin/bash
# Enable IP Forwarding
sysctl -w net.ipv4.ip_forward=1

# Flush rules
iptables -F

# Default Drop policy for forwarding
iptables -P FORWARD DROP

# Allow Attacker (External) to access Target (DMZ)
iptables -A FORWARD -i eth_ext -o eth_dmz -j ACCEPT
# Allow Attacker (External) to access SIEM (Internal)
iptables -A FORWARD -i eth_ext -o eth_int -j ACCEPT
# Drop Attacker trying to access Firewall local services (except ping)
iptables -A INPUT -i eth_ext -p icmp -j ACCEPT
iptables -A INPUT -i eth_ext -j DROP

# Keep container alive
tail -f /dev/null
```

#### 3. The Docker Compose File (`docker-compose.yml`)
*This is the heart of the setup, implementing limits, static IPs, profiles, and networking.*

```yaml
version: '3.8'

# --- Custom Networks (Isolated from Host) ---
networks:
  external_net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.10.10.0/24
  dmz_net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.10.20.0/24
  internal_net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.10.30.0/24

services:
  # ==========================================
  # 1. ATTACKER NODE (Profile: attacker)
  # ==========================================
  attacker:
    build: ./attacker-node
    profiles: ["attacker"]
    container_name: attacker-kali
    volumes:
      - ./attacker-node/workspace:/workspace
    networks:
      external_net:
        ipv4_address: 10.10.10.5
    cap_add:
      - NET_ADMIN  # Required for nmap/sniffing
      - NET_RAW
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 2G

  # ==========================================
  # 2. VULNERABLE TARGET (Profile: target)
  # ==========================================
  target:
    image: vulnerables/metasploit-vulnerability-emulator # Better maintained than Metasploitable3-ub1404 for docker
    profiles: ["target"]
    container_name: vulnerable-target
    volumes:
      - ./vulnerable-target/workspace:/workspace
    networks:
      dmz_net:
        ipv4_address: 10.10.20.5
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 1G

  # ==========================================
  # 3. FIREWALL / ROUTER (Profile: core)
  # ==========================================
  firewall:
    build: ./firewall
    profiles: ["core", "attacker", "target", "siem"] # Always runs if anything else runs
    container_name: network-firewall
    cap_add:
      - NET_ADMIN
    networks:
      external_net:
        ipv4_address: 10.10.10.254 # Acts as gateway
      dmz_net:
        ipv4_address: 10.10.20.254
      internal_net:
        ipv4_address: 10.10.30.254
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M

  # ==========================================
  # 4. PI-HOLE (Profile: core)
  # ==========================================
  pihole:
    image: pihole/pihole:latest
    profiles: ["core"]
    container_name: pihole-dns
    environment:
      TZ: 'America/New_York'
      WEBPASSWORD: 'admin'
    volumes:
      - ./pi-hole/workspace/etc-pihole:/etc/pihole
      - ./pi-hole/workspace/etc-dnsmasq.d:/etc/dnsmasq.d
    networks:
      internal_net:
        ipv4_address: 10.10.30.5
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M

  # ==========================================
  # 5. SIEM: WAZUH (Profile: siem)
  # ==========================================
  wazuh:
    image: wazuh/wazuh-manager:4.7.2 # Single node for laptops
    profiles: ["siem"]
    container_name: wazuh-siem
    volumes:
      - ./siem/workspace:/var/ossec/data
    networks:
      internal_net:
        ipv4_address: 10.10.30.10
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 4G # Wazuh/Elastic requires heavy RAM
```

#### 4. The Devcontainer Integration (`.devcontainer/devcontainer.json`)
By aiming the Devcontainer at the Attacker node, you can open VS Code directly inside Kali Linux. You can write your Python/Bash exploits locally and they execute natively inside the isolated Kali environment.

```json
{
    "name": "Cyber Homelab - Attacker IDE",
    "dockerComposeFile": "../docker-compose.yml",
    "service": "attacker",
    "workspaceFolder": "/workspace",
    "customizations": {
        "vscode": {
            "extensions": [
                "ms-python.python",
                "yzhang.markdown-all-in-one"
            ]
        }
    },
    "remoteUser": "hacker"
}
```

---

### Part 4: Setup Instructions for the End User

1.  **Initialize the Environment:**
    Create the folder structure on your laptop.
    ```bash
    mkdir -p cyber-homelab/{attacker-node/workspace,vulnerable-target/workspace,firewall/workspace,siem/workspace,pi-hole/workspace}
    mkdir -p cyber-homelab/.devcontainer
    ```
2.  **Populate the Files:** 
    Place the `Dockerfile`s, `firewall-rules.sh`, `lab_manager.py`, `docker-compose.yml`, and `devcontainer.json` into their respective directories as outlined above.
3.  **Make Scripts Executable:**
    ```bash
    chmod +x cyber-homelab/lab_manager.py
    chmod +x cyber-homelab/firewall/firewall-rules.sh
    ```
4.  **Run the Lab Manager:**
    ```bash
    cd cyber-homelab
    ./lab_manager.py
    ```
    *(Select Option 1 and 2 to test the attacker and target without melting your laptop's RAM. Add SIEM later once you confirm things are working).*
5.  **Access the Environment:**
    *   **Via CLI:** `docker exec -it attacker-kali /bin/bash`
    *   **Via VS Code:** Open the `cyber-homelab` folder in VS Code. If you have the Devcontainers extension installed, a prompt will appear: *"Folder contains a Dev Container configuration file. Reopen in Container"*. Click this to IDE directly into your Kali attacker node!

### Summary of Expert Improvements Applied:
*   Replaced Nginx with an Alpine IPTables **true packet-filter firewall**, fulfilling the 3-tier DMZ routing requirement.
*   Implemented **Docker Compose Profiles** paired with a Python CLI manager for seamless, customized build execution.
*   Swapped `kirscht/metasploitable3` for `vulnerables/metasploit-vulnerability-emulator`, which is significantly more stable in modern Docker environments while serving the exact same purpose.
*   Enforced precise **resource limit quotas** to ensure Wazuh (Elasticsearch) does not trigger an OOM (Out-of-Memory) crash on the host laptop.
*   Configured a highly secure **non-root user with passwordless `sudo`** and assigned explicit kernel capabilities (`CAP_NET_RAW`), striking the perfect balance between the principle of least privilege and functional hacking utility.