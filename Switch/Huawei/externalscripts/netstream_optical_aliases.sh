#!/usr/bin/env bash
# netstream_optical_aliases.sh — coleta aliases de todos os módulos ópticos em um único SNMP walk
# Retorna JSON: {"<snmpindex>": "<alias>", ...}
# Uso: netstream_optical_aliases.sh <HOST[:PORT]> <COMMUNITY>
# Instalar em: /usr/lib/zabbix/externalscripts/
# Permissão:   chmod +x netstream_optical_aliases.sh

HOST="$1"
COMM="$2"

if [[ -z "$HOST" || -z "$COMM" ]]; then
    echo '{}' >&2
    exit 1
fi

# Suporte a HOST:PORT
if [[ "$HOST" == *:* ]]; then
    SNMP_HOST="${HOST%:*}:${HOST##*:}"
else
    SNMP_HOST="$HOST"
fi

# Walk único da OID entPhysicalAlias (.47.1.1.1.1.14)
# timeout interno 12s para não exceder o Timeout do Zabbix (15s)
RAW=$(timeout 12 snmpwalk -v2c -c "$COMM" -Oqn "$SNMP_HOST" \
    .1.3.6.1.2.1.47.1.1.1.1.14 2>/dev/null)

if [[ -z "$RAW" ]]; then
    echo '{}'
    exit 0
fi

# Converter output para JSON: {index: alias}
# Formato do snmpwalk -Oqn: .1.3.6.1.2.1.47.1.1.1.1.14.67469390 "LinkToRouter"
PYCODE='
import sys, json, re
result = {}
for line in sys.stdin:
    line = line.strip()
    m = re.match(r".*\.(\d+)\s+(.*)", line)
    if not m:
        continue
    idx = m.group(1)
    val = m.group(2).strip().strip("\"")
    result[idx] = val
print(json.dumps(result, ensure_ascii=False))
'
echo "$RAW" | python3 -c "$PYCODE"
