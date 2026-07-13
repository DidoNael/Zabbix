#!/bin/bash
# ==============================================================================
# Script: discovery_huawei_optical.sh
# Local de instalação no Zabbix Server: /usr/lib/zabbix/externalscripts/discovery_huawei_optical.sh
# Uso no Zabbix LLD: discovery_huawei_optical.sh["{HOST.CONN}", "{$SNMP_COMMUNITY}", "single"]
#                    discovery_huawei_optical.sh["{HOST.CONN}", "{$SNMP_COMMUNITY}", "multi"]
# Descrição:
#   Correlaciona a tabela física de Módulos Ópticos (ENT-PHYSICAL-MIB, entPhysicalIndex)
#   com a tabela de Descrição de Interfaces (IF-MIB ifAlias, ifIndex).
#   Retorna JSON LLD compatível com Zabbix 4.4 e Zabbix 6.0+:
#     {#SNMPINDEX}       -> Índice físico (entPhysicalIndex, ex: 67469390)
#     {#ENTPHYSICALNAME} -> Nome da porta (ex: 100GE0/0/3)
#     {#IFALIAS}         -> Descrição da interface (ex: PE1 - Dutra)
# ==============================================================================

IP="$1"
COMMUNITY="$2"
MODE="${3:-single}"

if [ -z "$IP" ] || [ -z "$COMMUNITY" ]; then
    echo '{"data":[]}'
    exit 0
fi

# Diretório de cache em disco para evitar walks repetidos em curtos intervalos
CACHE_DIR="/tmp/zabbix_huawei_optical_cache"
CACHE_FILE="${CACHE_DIR}/${IP}_${MODE}.json"
CACHE_TTL=300 # 5 minutos de cache

mkdir -m 0755 -p "$CACHE_DIR" 2>/dev/null
chown zabbix:zabbix "$CACHE_DIR" "$CACHE_FILE" 2>/dev/null

if [ -s "$CACHE_FILE" ] && [ -r "$CACHE_FILE" ]; then
    NOW=$(date +%s)
    FILE_TIME=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
    AGE=$((NOW - FILE_TIME))
    if [ "$AGE" -lt "$CACHE_TTL" ]; then
        cat "$CACHE_FILE" 2>/dev/null && exit 0
    fi
fi

# OID de verificação de portas ópticas (Single Lane vs Multi Lane)
if [ "$MODE" = "multi" ]; then
    OPTICAL_BASE=".1.3.6.1.4.1.2011.5.25.31.1.1.3.1.5" # hwEntityOpticalTemperatureML
else
    OPTICAL_BASE=".1.3.6.1.4.1.2011.5.25.31.1.1.3.1.32" # hwEntityOpticalLaneRxPower
fi

# Executa coleta SNMP
WALK_OPTICAL=$(snmpwalk -v2c -c "$COMMUNITY" -Oqn "$IP" "$OPTICAL_BASE" 2>/dev/null)
if [ -z "$WALK_OPTICAL" ]; then
    echo '{"data":[]}'
    exit 0
fi

WALK_ENTNAME=$(snmpwalk -v2c -c "$COMMUNITY" -Oqn "$IP" .1.3.6.1.2.1.47.1.1.1.1.7 2>/dev/null)
WALK_IFNAME=$(snmpwalk -v2c -c "$COMMUNITY" -Oqn "$IP" .1.3.6.1.2.1.31.1.1.1.1 2>/dev/null)
[ -z "$WALK_IFNAME" ] && WALK_IFNAME=$(snmpwalk -v2c -c "$COMMUNITY" -Oqn "$IP" .1.3.6.1.2.1.2.2.1.2 2>/dev/null)
WALK_IFALIAS=$(snmpwalk -v2c -c "$COMMUNITY" -Oqn "$IP" .1.3.6.1.2.1.31.1.1.1.18 2>/dev/null)

# Processa correlação via AWK
RESULT=$(awk '
BEGIN {
    FS = " "
}
# 1. Carrega IFNAME: .1.3.6.1.2.1.31.1.1.1.1.<ifIndex> "100GE0/0/3"
$1 ~ /^\.1\.3\.6\.1\.2\.1\.(31\.1\.1\.1\.1|2\.2\.1\.2)\./ {
    idx = $1
    sub(/^.*\.1\.3\.6\.1\.2\.1\.(31\.1\.1\.1\.1|2\.2\.1\.2)\./, "", idx)
    val = $0
    sub(/^[^"]*"/, "", val)
    sub(/".*$/, "", val)
    ifIndexToName[idx] = val
    nameToIfIndex[val] = idx
    next
}
# 2. Carrega IFALIAS: .1.3.6.1.2.1.31.1.1.1.18.<ifIndex> "PE1 - Dutra"
$1 ~ /^\.1\.3\.6\.1\.2\.1\.31\.1\.1\.1\.18\./ {
    idx = $1
    sub(/^.*\.1\.3\.6\.1\.2\.1\.31\.1\.1\.1\.18\./, "", idx)
    val = $0
    sub(/^[^"]*"/, "", val)
    sub(/".*$/, "", val)
    ifIndexToAlias[idx] = val
    next
}
# 3. Carrega ENTNAME: .1.3.6.1.2.1.47.1.1.1.1.7.<entIndex> "100GE0/0/3"
$1 ~ /^\.1\.3\.6\.1\.2\.1\.47\.1\.1\.1\.1\.7\./ {
    idx = $1
    sub(/^.*\.1\.3\.6\.1\.2\.1\.47\.1\.1\.1\.1\.7\./, "", idx)
    val = $0
    sub(/^[^"]*"/, "", val)
    sub(/".*$/, "", val)
    entIndexToName[idx] = val
    next
}
# 4. Processa portas ópticas ativas
{
    idx = $1
    sub(/^.*\.1\.3\.6\.1\.4\.1\.2011\.5\.25\.31\.1\.1\.3\.1\.(5|32)\./, "", idx)
    if (idx != "" && !seen[idx]++) {
        activeOpticals[++count] = idx
    }
}
END {
    printf "{\"data\":["
    first = 1
    for (i = 1; i <= count; i++) {
        entIdx = activeOpticals[i]
        portName = entIndexToName[entIdx]
        if (portName == "") continue
        
        # Procura o ifIndex correspondente a essa porta
        ifIdx = nameToIfIndex[portName]
        portAlias = ""
        if (ifIdx != "") {
            portAlias = ifIndexToAlias[ifIdx]
        }
        
        if (!first) printf ","
        first = 0
        
        # Escapa aspas duplas no alias e nome
        gsub(/"/, "\\\"", portName)
        gsub(/"/, "\\\"", portAlias)
        
        printf "{\"{#SNMPINDEX}\":\"%s\", \"{#ENTPHYSICALNAME}\":\"%s\", \"{#IFALIAS}\":\"%s\", \"{#ENTALIAS}\":\"%s\"}", entIdx, portName, portAlias, portAlias
    }
    printf "]}\n"
}
' <(echo "$WALK_IFNAME"; echo "$WALK_IFALIAS"; echo "$WALK_ENTNAME"; echo "$WALK_OPTICAL"))

if [ -n "$RESULT" ]; then
    echo "$RESULT" > "$CACHE_FILE" 2>/dev/null
    echo "$RESULT"
else
    echo '{"data":[]}'
fi
