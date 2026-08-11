#!/bin/bash
# nqa_huawei_discovery.sh — Descobre instâncias NQA na HUAWEI-NQA-MIB
# Uso: nqa_huawei_discovery.sh <host> <community>
# Retorno: JSON para LLD Zabbix com {#NQA_OWNER} e {#NQA_INSTANCE}

HOST="$1"
COMMUNITY="$2"

if [ -z "$HOST" ] || [ -z "$COMMUNITY" ]; then
    echo '{"data":[]}'
    exit 1
fi

snmpwalk -v2c -c "$COMMUNITY" -Oqn "$HOST" 1.3.6.1.4.1.2011.5.25.111.2.1.1.3 2>/dev/null | python3 -c '
import sys, re

lines = sys.stdin.read().strip().splitlines()
items = []

for line in lines:
    m = re.search(r"\.2\.1\.1\.3\.([\d.]+)\s", line)
    if not m:
        continue
    parts = list(map(int, m.group(1).split(".")))
    i = 0
    try:
        owner_len = parts[i]; i += 1
        owner = "".join(chr(parts[i+j]) for j in range(owner_len)); i += owner_len
        inst_len = parts[i]; i += 1
        instance = "".join(chr(parts[i+j]) for j in range(inst_len))
    except (IndexError, ValueError):
        continue
    if owner and instance:
        k1 = "{#NQA_OWNER}"
        k2 = "{#NQA_INSTANCE}"
        items.append("{\"" + k1 + "\":\"" + owner + "\",\"" + k2 + "\":\"" + instance + "\"}")

print("{\"data\":[" + ",".join(items) + "]}")
'
