# IPv6 to IPv4 NAT Forwarding Setup Script
This script configures port forwarding rules from IPv6 to IPv4 on OpenWrt/ImmortalWrt systems.

## Usage
### Method 1: Direct Execution via curl | bash
curl -sSL https://raw.githubusercontent.com/你的用户名/你的仓库名/main/setup_nat_forward.sh | bash

### Method 2: Download and Execute Locally
wget -O setup_nat_forward.sh https://raw.githubusercontent.com/你的用户名/你的仓库名/main/setup_nat_forward.sh
chmod +x setup_nat_forward.sh
./setup_nat_forward.sh

## Notes
- The script will prompt for network interface selection and port forwarding details.
- It supports hotplug events (Scheme 3) and cron jobs (Scheme 2) to apply rules dynamically.
- Cron jobs have minimal impact on system performance.
