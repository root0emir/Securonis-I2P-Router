#!/bin/sh

# Securonis Script for Enhanced Anonymity and Privacy
# Configures Securonis Linux for maximum online anonymity using the I2P network.
# Version: 1.0
# I2P traffic router
# Note: Always review the script and ensure you understand its functionality
# before execution. Use it responsibly and adhere to local laws and regulations.

# The UID under which I2P runs
I2P_UID="i2p"

# I2P ports
TRANS_PORT="4444"
DNS_PORT="5354"
VIRT_ADDR="10.192.0.0/10"

# Non-I2P destinations
NON_I2P="127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16"
RESV_IANA="0.0.0.0/8 100.64.0.0/10 169.254.0.0/16 192.0.0.0/24 192.0.2.0/24 192.88.99.0/24 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/3"

# Processes to kill
TO_KILL="chrome dropbox firefox pidgin skype thunderbird hexchat"

# BleachBit cleaners
BLEACHBIT_CLEANERS="bash.history system.cache system.clipboard system.custom system.recent_documents system.rotated_logs system.tmp system.trash"
OVERWRITE="true"

# Default hostname
REAL_HOSTNAME="securonis"

# Load default options if exists
if [ -f /etc/default/securonis-router ]; then
	. /etc/default/securonis-i2p
fi

# Prompt function
ask() {
	local prompt default REPLY
	while true; do
		case "${2:-}" in
		Y)
			prompt="Y/n"
			default=Y
			;;
		N)
			prompt="y/N"
			default=N
			;;
		*)
			prompt="Ok"
			default=OK
			;;
		esac

		echo
		read -p "$1 [$prompt] > " REPLY
		REPLY=${REPLY:-$default}

		case "$REPLY" in
		Y* | y*) return 0 ;;
		N* | n* | O* | o*) return 1 ;;
		esac
	done
}

# Change the local hostname
change_hostname() {
	echo

	CURRENT_HOSTNAME=$(hostname)
	NEW_HOSTNAME=${1:-$(shuf -n 1 /usr/share/dict/words | sed -r 's/[^a-zA-Z]//g' | awk '{print tolower($0)}')}

	sed -i 's/127.0.1.1.*/127.0.1.1\t'"$NEW_HOSTNAME"'/g' /etc/hosts

	clean_dhcp

	hostnamectl set-hostname "$NEW_HOSTNAME"

	echo " * Hostname changed to $NEW_HOSTNAME"

	if [ -f "$HOME/.Xauthority" ]; then
		su "$SUDO_USER" -c "xauth -n list | grep -v $CURRENT_HOSTNAME | cut -f1 -d\ | xargs -i xauth remove {}"
		su "$SUDO_USER" -c "xauth add $(xauth -n list | tail -1 | sed 's/^.*\//'$NEW_HOSTNAME'\//g')"
		echo " * X authority file updated"
	fi

	avahi-daemon --kill 2>/dev/null

	echo " * Hostname successfully set to $NEW_HOSTNAME"
}

# Check I2P installation and install if not present
check_install_i2p() {
	if ! command -v i2prouter &> /dev/null; then
		echo "I2P is not installed. Installing I2P..."
		sudo apt-add-repository ppa:i2p-maintainers/i2p -y
		sudo apt-get update
		sudo apt-get install i2p -y
	fi
}

# Check I2P configs
check_configs() {
	grep -q -x 'RUN_DAEMON="yes"' /etc/default/i2p
	if [ $? -ne 0 ]; then
		echo "\n[!] Please add the following to your '/etc/default/i2p' and restart the service:\n"
		echo ' RUN_DAEMON="yes"\n'
		exit 1
	fi

	grep -q -x 'VirtualAddrNetwork 10.192.0.0/10' /etc/i2p/i2p.conf
	VAR1=$?

	grep -q -x 'TransPort 4444' /etc/i2p/i2p.conf
	VAR2=$?

	grep -q -x 'DNSPort 5354' /etc/i2p/i2p.conf
	VAR3=$?

	grep -q -x 'AutomapHostsOnResolve 1' /etc/i2p/i2p.conf
	VAR4=$?

	if [ $VAR1 -ne 0 ] || [ $VAR2 -ne 0 ] || [ $VAR3 -ne 0 ] || [ $VAR4 -ne 0 ]; then
		echo "\n[!] Please add the following to your '/etc/i2p/i2p.conf' and restart service:\n"
		echo ' VirtualAddrNetwork 10.192.0.0/10'
		echo ' TransPort 4444'
		echo ' DNSPort 5354'
		echo ' AutomapHostsOnResolve 1\n'
		exit 1
	fi
}

# Check if this environment runs from a LiveCD or USB Stick
check_livecd() {
	grep -q -x 'securonis:x:1000:1000:Live session user,,,:/home/securonis:/bin/bash' /etc/passwd
	if [ $? -eq 0 ]; then
		echo " * Loading system_i2p AppArmor profile into the kernel..."
		apparmor_parser -r /etc/apparmor.d/system_i2p -C
	fi
}

# Make sure that only root can run this script
check_root() {
	if [ "$(id -u)" -ne 0 ]; then
		echo "\n[!] This script must run as root\n" >&2
		exit 1
	fi
}

# Release DHCP address
clean_dhcp() {
	dhclient -r
	rm -f /var/lib/dhcp/dhclient*
	echo " * DHCP address released"
}

# Flush iptables rules
flush_iptables() {
	iptables -P INPUT ACCEPT
	iptables -P OUTPUT ACCEPT
	iptables -F
	iptables -t nat -F
	echo " * Deleted all iptables rules"
}

# Kill processes at startup
kill_process() {
	if [ "$TO_KILL" != "" ]; then
		killall -q $TO_KILL
		echo "\n * Killed processes to prevent leaks"
	fi
}

# Explicitly disabled IPv6 to reduce potential data leaks
disable_ipv6() {
	echo " * Disabling IPv6 to prevent data leakage..."
	sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
	sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1
}

# Change MAC address
manage_mac_address() {
	# Get the network interface that has a default route
	NETWORK_INTERFACE=$(ip -o -f inet route show to default | awk '{print $5}' | head -n 1)

	# Check if the network interface is found
	if [ -n "$NETWORK_INTERFACE" ]; then
		case "$1" in
		change)
			echo
			macchanger -r "$NETWORK_INTERFACE" >/dev/null 2>&1
			;;
		restore)
			echo
			macchanger -p "$NETWORK_INTERFACE" >/dev/null 2>&1
			;;
		*)
			echo " ! Invalid argument. Use 'change' to change the MAC address or 'restore' to restore it."
			;;
		esac
	else
		echo " ! No network interface with a default route detected. Check your internet connection."
	fi
}

# Securonis implementation of Transparently Routing Traffic Through I2P
# Adapted for I2P
redirect_to_i2p() {
	echo

	if ! [ -f /etc/network/iptables.rules ]; then
		iptables-save >/etc/network/iptables.rules
		echo " * Saved iptables rules"
	fi

	flush_iptables

	# nat .i2p addresses
	iptables -t nat -A OUTPUT -d $VIRT_ADDR -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -j REDIRECT --to-ports $TRANS_PORT

	# nat dns requests to I2P
	iptables -t nat -A OUTPUT -d 127.0.0.1/32 -p udp -m udp --dport 53 -j REDIRECT --to-ports $DNS_PORT

	# don't nat the I2P process, the loopback, or the local network
	iptables -t nat -A OUTPUT -m owner --uid-owner $I2P_UID -j RETURN
	iptables -t nat -A OUTPUT -o lo -j RETURN

	for _lan in $NON_I2P; do
		iptables -t nat -A OUTPUT -d $_lan -j RETURN
	done

	for _iana in $RESV_IANA; do
		iptables -t nat -A OUTPUT -d $_iana -j RETURN
	done

	# redirect whatever fell thru to I2P's TransPort
	iptables -t nat -A OUTPUT -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -j REDIRECT --to-ports $TRANS_PORT

	# *filter INPUT
	iptables -A INPUT -m state --state ESTABLISHED -j ACCEPT
	iptables -A INPUT -i lo -j ACCEPT

	iptables -A INPUT -j DROP

	# *filter FORWARD
	iptables -A FORWARD -j DROP

	# *filter OUTPUT
	iptables -A OUTPUT -m state --state INVALID -j DROP

	iptables -A OUTPUT -m state --state ESTABLISHED -j ACCEPT

	# allow I2P process output
	iptables -A OUTPUT -m owner --uid-owner $I2P_UID -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -m state --state NEW -j ACCEPT

	# allow loopback output
	iptables -A OUTPUT -d 127.0.0.1/32 -o lo -j ACCEPT

	# I2P transproxy magic
	iptables -A OUTPUT -d 127.0.0.1/32 -p tcp -m tcp --dport $TRANS_PORT --tcp-flags FIN,SYN,RST,ACK SYN -j ACCEPT

	# allow access to lan hosts in $NON_I2P
	for _lan in $NON_I2P; do
		iptables -A OUTPUT -d $_lan -j ACCEPT
	done

	# Log & Drop everything else.
	iptables -A OUTPUT -j LOG --log-prefix "Dropped OUTPUT packet: " --log-level 7 --log-uid
	iptables -A OUTPUT -j DROP

	# Set default policies to DROP
	iptables -P INPUT DROP
	iptables -P FORWARD DROP
	iptables -P OUTPUT DROP
}

# BleachBit cleaners to delete unnecessary files to preserve anonymity
run_bleachbit() {
	if [ "$OVERWRITE" = "true" ]; then
		echo -n "\n * Deleting and overwriting unnecessary files... "
		bleachbit -o -c $BLEACHBIT_CLEANERS >/dev/null 2>/dev/null
	else
		echo -n "\n * Deleting unnecessary files... "
		bleachbit -c $BLEACHBIT_CLEANERS >/dev/null 2>/dev/null
	fi

	echo "Done!"
}

to_sleep() {
	sleep 3
}

warning() {
	echo "\n[!] WARNING! This is a simple script that prevents most common system data"
	echo "    leaks. Your computer behavior is the key to guaranteeing you strong privacy"
	echo "    protection and anonymity."
	echo "\n[i] Please edit /etc/default/securonis-anonymous with your custom values."
}

do_start() {
	check_install_i2p
	check_configs
	check_root

	warning

	echo "\n[i] Starting anonymous mode - I2P"

	if ask "Do you want to kill running processes to prevent leaks?" Y; then
		kill_process
	else
		echo
	fi

	check_livecd

	if ask "Do you want transparent routing through I2P?" Y; then
		redirect_to_i2p
	else
		echo
	fi

	if ask "Do you want to change MAC address?" Y; then
		manage_mac_address change
	else
		echo
	fi

	if ask "Do you want to change the local hostname? It will cause disconnection" Y; then
		read -p "Type it or press Enter for a random one > " CHOICE

		echo -n "\n * Stopping NetworkManager service"
		systemctl stop NetworkManager 2>/dev/null
		to_sleep

		if [ "$CHOICE" = "" ]; then
			change_hostname
		else
			change_hostname "$CHOICE"
		fi

		echo " * Starting NetworkManager service"
		systemctl start NetworkManager 2>/dev/null
		to_sleep
	else
		echo
	fi

	disable_ipv6

	echo " * Restarting i2p service"
	systemctl restart i2p 2>/dev/null
	to_sleep
	echo

	if [ ! -e /var/run/i2p/i2p.pid ]; then
		echo "\n[!] I2P is not running! Quitting...\n"
		exit 1
	fi
}

do_stop() {

	check_root

	echo "\n[i] Stopping anonymous mode"

	if ask "Do you want to kill running processes to prevent leaks?" Y; then
		kill_process
	else
		echo
	fi

	flush_iptables

	if [ -f /etc/network/iptables.rules ]; then
		iptables-restore </etc/network/iptables.rules
		rm /etc/network/iptables.rules
		echo " * Restored iptables rules"
	fi

	if ask "Do you want to change MAC address?" Y; then
		manage_mac_address restore
	else
		echo
	fi

	if ask "Do you want to change the local hostname? It will cause disconnection" Y; then
		read -p "Type it or press Enter to restore default [$REAL_HOSTNAME] > " CHOICE

		echo -n "\n * Stopping NetworkManager service"
		systemctl stop NetworkManager 2>/dev/null
		to_sleep

		if [ "$CHOICE" = "" ]; then
			change_hostname $REAL_HOSTNAME
		else
			change_hostname "$CHOICE"
		fi

		echo " * Starting NetworkManager service"
		systemctl start NetworkManager 2>/dev/null
		to_sleep
	fi

	if [ "$DISPLAY" ]; then
		if ask "Delete unnecessary files to preserve your anonymity?" Y; then
			run_bleachbit
		fi
	fi

	echo
}

do_status() {
	echo "\n[i] Showing anonymous status\n"

	# Check for I2P IP and status
	HTML=$(curl -s http://localhost:7657)
	IP=$(curl -s http://checkip.dyndns.com | sed -e 's/.*Current IP Address: //' -e 's/<.*$//')

	echo "------------------------------------------------------"
	if echo "$HTML" | grep -q "I2P Router Console"; then
		echo "I2P Status        : ON"
		echo "------------------------------------------------------"
	else
		echo "I2P Status        : OFF"
		echo "------------------------------------------------------"
	fi

	# Display hostname
	CURRENT_HOSTNAME=$(hostname)
	echo "Hostname          : $CURRENT_HOSTNAME"
	echo "Public IP         : $IP"
	echo "------------------------------------------------------"

	echo "Network Interfaces:\n"

	# Loop through all interfaces and get the interface name and MAC address (ether)
	ifconfig -a | while read -r line; do
		# Check if line contains an interface name (e.g., "enp0s3:")
		if echo "$line" | grep -q "flags="; then
			interface=$(echo "$line" | cut -d: -f1)
		fi

		# Check if line contains MAC address (with 'ether')
		if echo "$line" | grep -q "ether"; then
			mac_address=$(echo "$line" | awk '{print $2}')
			echo "$mac_address | $interface"
		fi
	done
	echo "------------------------------------------------------\n"

}

case "$1" in
start)
	do_start
	;;
stop)
	do_stop
	;;
status)
	do_status
	;;
*)
	echo "Usage: $0 {start|stop|status}" >&2
	exit 3
	;;
esac

exit 0
