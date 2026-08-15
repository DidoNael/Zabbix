#!/usr/bin/env python3
"""
LLD Discovery para Template DNS Monitor - Netstream.
Uso: netstream_dns_discover.py "<servidores>" "<domínios>" "<tipos>"
     Parâmetros separados por vírgula.
Instalar em: /usr/lib/zabbix/externalscripts/netstream_dns_discover.py
Permissão:   chmod +x netstream_dns_discover.py
"""

import sys
import json


def main():
    servers = [s.strip() for s in sys.argv[1].split(",")] if len(sys.argv) > 1 else ["8.8.8.8"]
    domains = [d.strip() for d in sys.argv[2].split(",")] if len(sys.argv) > 2 else ["google.com"]
    types   = [t.strip().upper() for t in sys.argv[3].split(",")] if len(sys.argv) > 3 else ["A"]

    data = []
    for server in servers:
        for domain in domains:
            for dns_type in types:
                if server and domain and dns_type:
                    data.append({
                        "{#DNS_SERVER}": server,
                        "{#DNS_DOMAIN}": domain,
                        "{#DNS_TYPE}":   dns_type,
                    })

    print(json.dumps({"data": data}))


if __name__ == "__main__":
    main()
