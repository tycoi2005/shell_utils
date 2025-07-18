#!/bin/bash

# This script adds DNS servers from a list to /etc/resolv.conf without adding duplicates.

DNS_LIST_FILE="dns_list.txt"
RESOLV_CONF="/etc/resolv.conf"

# Check if the dns_list.txt file exists
if [ ! -f "$DNS_LIST_FILE" ]; then
    echo "Error: $DNS_LIST_FILE not found."
    exit 1
fi

echo "Reading DNS servers from $DNS_LIST_FILE..."

# Read each line from the dns_list.txt file
while IFS= read -r line || [[ -n "$line" ]]; do
    # Trim leading/trailing whitespace
    ip=$(echo "$line" | awk '{$1=$1};1')

    # Ignore comments and empty lines
    if [[ -z "$ip" || "$ip" == "#"* ]]; then
        continue
    fi

    # Check if the nameserver entry already exists
    if sudo grep -q "^nameserver $ip" "$RESOLV_CONF"; then
        echo "Nameserver $ip already exists in $RESOLV_CONF. Skipping."
    else
        echo "Adding nameserver $ip to $RESOLV_CONF..."
        # Append the nameserver entry to the file
        echo "nameserver $ip" | sudo tee -a "$RESOLV_CONF" > /dev/null
    fi
done < "$DNS_LIST_FILE"

echo "DNS update complete."
