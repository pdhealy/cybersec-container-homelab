# Host-Level Packet Capture (Hypervisor Level)

Because Docker utilizes the host's Linux kernel to create virtual bridges for each network, all traffic inherently passes through the host. This method allows you to capture packets without modifying any container configurations or bypassing container security constraints.

## 1. Identify Network Interfaces

First, identify the bridge interfaces created for the homelab networks (`external_net`, `dmz_net`, `internal_net`).

Run the following command to list Docker networks and their IDs:
```bash
docker network ls | grep cybersec-container-homelab
```

Look for the corresponding bridge interfaces on the host:
```bash
ip link show type bridge
```
*Note: Docker bridge interfaces typically start with `br-` followed by the first 12 characters of the network ID.*

## 2. Capture Traffic

You can capture traffic across all interfaces or target a specific bridge.

### Option A: Capture All Host Traffic
This will capture everything traversing the host, including all container networks:
```bash
sudo tcpdump -i any -w offline_analysis.pcap
```

### Option B: Capture Specific Network Traffic
If you only want to capture traffic on a specific subnet (e.g., `dmz_net`), use its bridge interface name:
```bash
sudo tcpdump -i br-<network_id> -w dmz_analysis.pcap
```

## 3. Analyze Offline
Transfer the resulting `.pcap` files to your analysis machine and open them in Wireshark or use `tshark` for offline analysis.
