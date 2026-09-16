#!/usr/bin/env python3
"""
conntrack.top.mikrotik.py
Conecta via SSH ao MikroTik, conta conexoes ativas por IP de origem
e retorna JSON com o top-N para uso como master item + LLD no Zabbix.

Uso: conntrack.top.mikrotik.py <ip> <user> <password> [top_n=10]
Saida: [{"ip":"1.2.3.4","count":150}, ...]
"""

import sys
import json
import subprocess
import re
from collections import Counter


def fetch_connections(host, user, password):
    cmd = [
        "sshpass", "-p", password,
        "ssh",
        "-o", "StrictHostKeyChecking=no",
        "-o", "ConnectTimeout=10",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "LogLevel=ERROR",
        f"{user}@{host}",
        ":foreach c in=[/ip firewall connection find] do={:put [/ip firewall connection get $c src-address]}"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    return result.stdout


def main():
    if len(sys.argv) < 4:
        print("[]")
        sys.exit(0)

    host = sys.argv[1]
    user = sys.argv[2]
    password = sys.argv[3]
    top_n = int(sys.argv[4]) if len(sys.argv) > 4 else 10

    try:
        raw = fetch_connections(host, user, password)
        counter = Counter()

        for line in raw.splitlines():
            line = line.strip()
            # Formato RouterOS: "1.2.3.4:port" ou "1.2.3.4"
            m = re.match(r'^(\d{1,3}(?:\.\d{1,3}){3})(?::\d+)?$', line)
            if m:
                counter[m.group(1)] += 1

        top = [{"ip": ip, "count": count}
               for ip, count in counter.most_common(top_n)]
        print(json.dumps(top))

    except Exception:
        print("[]")


if __name__ == "__main__":
    main()
