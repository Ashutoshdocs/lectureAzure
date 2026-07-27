#!/bin/bash

###################################################
# Azure S2S VPN Demo - Company VM
###################################################

AZUREVPNIP="4.188.96.118"
LOCALNET="172.16.0.0/16"
REMOTENET="10.0.0.0/16"
PSK="ABC123"

echo "Updating packages..."
apt update

echo "Installing StrongSwan..."
DEBIAN_FRONTEND=noninteractive apt install -y strongswan

echo "Enabling IP forwarding..."
cat >/etc/sysctl.d/99-vpn.conf <<EOF
net.ipv4.ip_forward=1
EOF

sysctl --system

echo "Opening firewall ports..."
ufw allow 500/udp
ufw allow 4500/udp

echo "Backing up configuration..."
cp /etc/ipsec.conf /etc/ipsec.conf.bak.$(date +%s) 2>/dev/null
cp /etc/ipsec.secrets /etc/ipsec.secrets.bak.$(date +%s) 2>/dev/null

echo "Writing ipsec.conf..."

cat >/etc/ipsec.conf <<EOF
config setup
    uniqueids=no

conn azure
    auto=start
    type=tunnel
    keyexchange=ikev2
    authby=psk

    left=%defaultroute
    leftsubnet=$LOCALNET

    right=$AZUREVPNIP
    rightsubnet=$REMOTENET

    ike=aes256-sha1-modp1024!
    esp=aes256-sha1!

    ikelifetime=28800s
    lifetime=3600s

    dpddelay=30
    dpdtimeout=120
    dpdaction=restart
EOF

echo "Writing ipsec.secrets..."

cat >/etc/ipsec.secrets <<EOF
: PSK "$PSK"
EOF

echo "Restarting StrongSwan..."

systemctl restart strongswan-starter

sleep 5

echo ""
echo "======================================"
echo "Configuration Complete"
echo "======================================"
echo ""

echo "Checking service..."
systemctl status strongswan-starter --no-pager

echo ""
echo "======================================"
echo "IPSec Status"
echo "======================================"

ipsec statusall

echo ""
echo "======================================"
echo "Trying to establish tunnel"
echo "======================================"

ipsec up azure

echo ""
echo "======================================"
echo "Final Status"
echo "======================================"

ipsec statusall

echo ""
echo "======================================"
echo "Azure VPN Gateway : $AZUREVPNIP"
echo "Local Network     : $LOCALNET"
echo "Remote Network    : $REMOTENET"
echo "PSK               : $PSK"
echo "======================================"

echo ""
echo "Test after tunnel:"
echo ""
echo "ping <WEB_VM_PRIVATE_IP>"
echo "curl http://<WEB_VM_PRIVATE_IP>"
