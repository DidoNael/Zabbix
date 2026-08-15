#!/usr/bin/env bash
# =============================================================================
# Empresa  : Netstream Telecomunicações
# Site     : netstream.net.br
# Contato  : (11) 95990-4100
# Email    : suporte@netstream.net.br
#
# AVISO DE PROPRIEDADE INTELECTUAL
# Este script é propriedade exclusiva da Netstream Telecomunicações.
# É proibida a cópia, distribuição, modificação ou qualquer uso sem
# autorização prévia e por escrito da Netstream Telecomunicações.
# Todos os direitos reservados.
# =============================================================================
# netstream_optical_aliases_netstream.sh — coleta aliases de todos os módulos
# ópticos em um único SNMP walk.
# Retorna JSON: {"<snmpindex>": "<alias>", ...}
# Uso: netstream_optical_aliases_netstream.sh <HOST[:PORT]> <COMMUNITY>
# Instalar em: /usr/lib/zabbix/externalscripts/

HOST="$1"
COMM="$2"

if [[ -z "$HOST" || -z "$COMM" ]]; then
    echo '{}' >&2
    exit 1
fi

if [[ "$HOST" == *:* ]]; then
    SNMP_HOST="${HOST%:*}:${HOST##*:}"
else
    SNMP_HOST="$HOST"
fi

RAW=$(timeout 12 snmpwalk -v2c -c "$COMM" -Oqn "$SNMP_HOST" \
    .1.3.6.1.2.1.47.1.1.1.1.14 2>/dev/null)

if [[ -z "$RAW" ]]; then
    echo '{}'
    exit 0
fi

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
