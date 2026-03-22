#!/bin/bash
set -e

# List of domains to allow
DOMAINS=(
  "github.com"
  "api.github.com"
  "objects.githubusercontent.com"
  "registry.npmjs.org"
  "rubygems.org"
  "index.rubygems.org"
  "generativelanguage.googleapis.com"
  "deb.debian.org"
  "security.debian.org"
  "index.docker.io"
  "registry-1.docker.io"
  "auth.docker.io"
  "production.cloudflare.docker.com"
  "dl.google.com" # Common for Google tools
)

# Flush existing rules
iptables -F
iptables -X

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Allow established and related connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow DNS (port 53 UDP/TCP)
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Allow HTTP/HTTPS for specific domains
for domain in "${DOMAINS[@]}"; do
  # Get all IP addresses for the domain (IPv4)
  IPS=$(getent ahosts "$domain" | awk '{print $1}' | sort -u | grep -E '^[0-9.]+$')
  for ip in $IPS; do
    iptables -A OUTPUT -p tcp -d "$ip" --dport 80 -j ACCEPT
    iptables -A OUTPUT -p tcp -d "$ip" --dport 443 -j ACCEPT
  done
done

# Default policy: DROP all other output
iptables -P OUTPUT DROP

echo "Firewall rules applied."
