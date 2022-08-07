#!/bin/bash

# Use common vars from .env
source .env

# Ensure exit is properly trapped
trap "exit $?" TERM


# Set error Handlers
error_exit() {
	echo "$(date) - ERROR - ${ERRMSG}"
	exit 1
}

# Ensure requirements are installed
reqs_check() {
	# Check for dependencies
	ERRMSG="Dependency missing. Recommend 'sudo apt-get --no-install-recommends install apache2-utils wireguard'"
	which htpasswd &>/dev/null || error_exit
	which wg &>/dev/null || error_exit
}

# Generate key pairs
gen_keys() {
	# Generate keys, first run only.

	PRIVKEY_WG_CLIENT="$(wg genkey)"
	echo "PRIVKEY_WG_CLIENT=${PRIVKEY_WG_CLIENT}" >> .env

	PUBKEY_WG_CLIENT="$(echo ${PRIVKEY_WG_CLIENT} | wg pubkey)"
	echo "PUBKEY_WG_CLIENT=${PUBKEY_WG_CLIENT}" >> .env
	
	PRIVKEY_WG_SERVER="$(wg genkey)"
	echo "PRIVKEY_WG_SERVER=${PRIVKEY_WG_SERVER}" >> .env
	
	PUBKEY_WG_SERVER="$(echo ${PRIVKEY_WG_SERVER} | wg pubkey)"
	echo "PUBKEY_WG_SERVER=${PUBKEY_WG_SERVER}" >> .env
}

# Generate server and client config files
gen_wg_conf() {
	# Create wg0.conf for client
	cat > ./wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = ${PRIVKEY_WG_CLIENT}
Address = 10.1.0.2/30

[Peer]
PublicKey = ${PUBKEY_WG_SERVER}
AllowedIPs = 0.0.0.0/0
Endpoint = ${WG_HOSTNAME}:${WG_PORT}
PersistentKeepalive = 20
EOF
	chmod 600 ./wireguard/wg0.conf

	# Create wg0.conf for server
	cat > ./server-wg0.conf <<EOF
[Interface]
Address = 10.1.0.1/30
ListenPort = ${WG_PORT}
PrivateKey = ${PRIVKEY_WG_SERVER}

[Peer]
PublicKey = ${PUBKEY_WG_CLIENT}
AllowedIPs = 10.1.0.2/32
EOF

	# Create iptables for server
	cat > ./rules.v4 <<EOF
# Generated NAT Rules
*nat
:PREROUTING ACCEPT [58399:9586820]
:INPUT ACCEPT [724:63142]
:OUTPUT ACCEPT [43:3206]
:POSTROUTING ACCEPT [794:45242]
-A PREROUTING -i eth0 -p tcp -m multiport --dports 80:9000 -j DNAT --to-destination 10.66.66.2
-A PREROUTING -i eth0 -p udp -m multiport --dports 80:9000 -j DNAT --to-destination 10.66.66.2
-A POSTROUTING -s 10.66.66.2/32 -o eth0 -j MASQUERADE
COMMIT
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [37561:13433091]
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -i wg0 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m multiport --dports 80:9000 -j ACCEPT
-A INPUT -p udp -m multiport --dports 80:9000 -j ACCEPT
-A INPUT -p udp -m udp --dport 41510 -j ACCEPT
-A FORWARD -s 10.66.66.2/32 -i wg0 -o eth0 -j ACCEPT
-A FORWARD -d 10.66.66.2/32 -i eth0 -o wg0 -p tcp -m multiport --dports 80:9000 -j ACCEPT
-A FORWARD -d 10.66.66.2/32 -i eth0 -o wg0 -p udp -m multiport --dports 80:9000 -j ACCEPT
-A FORWARD -d 10.66.66.2/32 -i eth0 -o wg0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
COMMIT
EOF
}

echo "Finished setup."
