#!/bin/bash

###############################################################
# RouterVM Configuration
# Purpose:
#   Configure Ubuntu VM as a Router (NVA)
#
# This script DOES NOT:
#   - Enable Azure NIC IP Forwarding
#   - Create Route Tables
#   - Create VNet Peering
#
# These will be configured manually from Azure Portal.
###############################################################

set -e

echo "=========================================="
echo "Azure Router VM Configuration"
echo "=========================================="

###############################################################
# Update Packages
###############################################################

echo ""
echo "Updating packages..."

sudo apt update

###############################################################
# Install Required Packages
###############################################################

echo ""
echo "Installing required packages..."

sudo apt install -y \
    net-tools \
    traceroute \
    tcpdump \
    iptables-persistent

###############################################################
# Enable IPv4 Forwarding
###############################################################

echo ""
echo "Enabling IP Forwarding..."

sudo sysctl -w net.ipv4.ip_forward=1

###############################################################
# Persist After Reboot
###############################################################

if grep -q "^net.ipv4.ip_forward" /etc/sysctl.conf; then
    sudo sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
else
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
fi

sudo sysctl -p

###############################################################
# Allow Packet Forwarding
###############################################################

echo ""
echo "Configuring iptables..."

sudo iptables -P FORWARD ACCEPT
sudo iptables -F FORWARD
sudo iptables -A FORWARD -j ACCEPT

###############################################################
# Save Rules
###############################################################

echo ""
echo "Saving iptables rules..."

sudo netfilter-persistent save

###############################################################
# Verification
###############################################################

echo ""
echo "=========================================="
echo "Configuration Complete"
echo "=========================================="

echo ""
echo "IP Forwarding Status"

cat /proc/sys/net/ipv4/ip_forward

echo ""
echo "Interfaces"

ip addr

echo ""
echo "Routing Table"

ip route

echo ""
echo "FORWARD Chain"

sudo iptables -L FORWARD -v

echo ""
echo "=========================================="
echo "NEXT STEPS IN AZURE"
echo "=========================================="

echo "1. Enable IP Forwarding on RouterVM NIC."
echo "2. Configure VNet Peering."
echo "3. Create Route Table for VNetA."
echo "4. Create Route Table for VNetC."
echo "5. Test with Allow Forwarded Traffic = Disabled."
echo "6. Enable Allow Forwarded Traffic."
echo "7. Test again."

echo ""
echo "To monitor forwarded packets:"
echo ""
echo "sudo tcpdump -i any icmp"
echo ""
echo "=========================================="