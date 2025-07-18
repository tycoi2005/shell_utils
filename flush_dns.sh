#!/bin/bash

# This script flushes the DNS cache on macOS and clears the /etc/resolv.conf file.

# --- Flush DNS Cache ---
echo "Flushing DNS cache..."
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
echo "DNS cache flushed successfully."
echo ""

# --- Clear /etc/resolv.conf ---
echo "Backing up /etc/resolv.conf to /etc/resolv.conf.bak..."
sudo cp /etc/resolv.conf /etc/resolv.conf.bak
echo "Clearing /etc/resolv.conf..."
sudo truncate -s 0 /etc/resolv.conf
echo "/etc/resolv.conf cleared."
