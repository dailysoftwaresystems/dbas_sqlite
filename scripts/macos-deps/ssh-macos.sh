#!/bin/bash

HostName="${1:-MacBook-Pro-de-Rafael}"
UserName="${2:-rafaelgasperetti}"

ip=$(ping -c 1 "$HostName" 2>/dev/null | grep -oP '\(\K[^\)]+')

if [ -z "$ip" ]; then
  echo "❌ It was not possible to resolve '$HostName' in current network." >&2
  exit 1
fi

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$UserName@$ip"
