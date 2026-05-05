#!/bin/bash

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <host> <user>" >&2
  exit 2
fi

HostName="$1"
UserName="$2"

ip=$(ping -c 1 "$HostName" 2>/dev/null | grep -oP '\(\K[^\)]+')

if [ -z "$ip" ]; then
  echo "❌ It was not possible to resolve '$HostName' in current network." >&2
  exit 1
fi

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$UserName@$ip"
