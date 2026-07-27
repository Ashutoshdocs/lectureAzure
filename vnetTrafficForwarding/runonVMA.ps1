#!/bin/bash

echo "Updating packages..."
sudo apt update

echo "Installing ping..."
sudo apt install -y iputils-ping

echo "Installing tcpdump..."
sudo apt install -y tcpdump

echo "Disabling UFW..."
sudo ufw disable

echo "Flushing iptables..."
sudo iptables -F
sudo iptables -P INPUT ACCEPT
sudo iptables -P OUTPUT ACCEPT
sudo iptables -P FORWARD ACCEPT

echo "Network Information"
hostname
hostname -I
ip route

echo ""
echo "VM-A is ready."
echo ""
echo "Ping Router:"
echo "ping 10.2.0.4"
echo ""
echo "Ping VM-C:"
echo "ping 10.3.0.4"