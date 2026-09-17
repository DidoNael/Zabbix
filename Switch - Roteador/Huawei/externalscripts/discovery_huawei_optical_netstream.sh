#!/bin/bash
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
# discovery_huawei_optical_netstream.sh
# Local de instalação no Zabbix Server: /usr/lib/zabbix/externalscripts/
# Uso no Zabbix LLD: discovery_huawei_optical_netstream.sh["{HOST.CONN}", "{$SNMP_COMMUNITY}", "single"]
#                    discovery_huawei_optical_netstream.sh["{HOST.CONN}", "{$SNMP_COMMUNITY}", "multi"]
# Descrição:
#   Correlaciona a tabela física de Módulos Ópticos (ENT-PHYSICAL-MIB, entPhysicalIndex)
#   com a tabela de Descrição de Interfaces (IF-MIB ifAlias, ifIndex).
#   Filtra automaticamente portas sem descrição ou administratively shutdown (desligadas).
#   Retorna JSON LLD compatível com Zabbix 4.4 e Zabbix 6.0+:
#     {#SNMPINDEX}       -> Índice físico (entPhysicalIndex, ex: 67469390)
#     {#ENTPHYSICALNAME} -> Nome da porta (ex: XGigabitEthernet0/0/3)
#     {#IFALIAS}         -> Descrição da interface (ex: PE1 - Dutra)

IP="$1"
COMMUNITY="$2"
MODE="${3:-single}"
PORT="${4:-161}"
FORCE="$5"
TARGET="${IP}:${PORT}"

if [ -z "$IP" ] || [ -z "$COMMUNITY" ]; then
    echo '{"data":[]}'
    exit 0
fi

CACHE_DIR="/tmp/zabbix_huawei_optical_cache"
CACHE_FILE="${CACHE_DIR}/${IP}_${MODE}.json"
CACHE_TTL=3600 # 1 hora de cache

mkdir -m 0755 -p "$CACHE_DIR" 2>/dev/null
chown zabbix:zabbix "$CACHE_DIR" "$CACHE_FILE" 2>/dev/null

if [ "$FORCE" != "force" ] && [ "$FORCE" != "--no-cache" ] && [ -s "$CACHE_FILE" ] && [ -r "$CACHE_FILE" ]; then
    NOW=$(date +%s)
    FILE_TIME=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
    AGE=$((NOW - FILE_TIME))
    if [ "$AGE" -lt "$CACHE_TTL" ]; then
        cat "$CACHE_FILE" 2>/dev/null && exit 0
    fi
fi

if [ "$MODE" = "multi" ]; then
    OPTICAL_BASE="1.3.6.1.4.1.2011.5.25.31.1.1.3.1.5"
else
    OPTICAL_BASE="1.3.6.1.4.1.2011.5.25.31.1.1.3.1.32"
fi

WALK_OPTICAL=$(snmpwalk -v2c -c "$COMMUNITY" -t 3 -r 0 -On "$TARGET" "$OPTICAL_BASE" 2>/dev/null)
if [ -z "$WALK_OPTICAL" ]; then
    echo '{"data":[]}'
    exit 0
fi

# Executa os 5 walks em paralelo para caber dentro do Timeout do Zabbix
TMPWALK=$(mktemp -d)
trap "rm -rf '$TMPWALK'" EXIT
snmpwalk -v2c -c "$COMMUNITY" -t 3 -r 0 -On "$TARGET" 1.3.6.1.2.1.47.1.1.1.1.7 > "$TMPWALK/entname" 2>/dev/null &
snmpwalk -v2c -c "$COMMUNITY" -t 3 -r 0 -On "$TARGET" 1.3.6.1.2.1.31.1.1.1.1   > "$TMPWALK/ifname"  2>/dev/null &
snmpwalk -v2c -c "$COMMUNITY" -t 3 -r 0 -On "$TARGET" 1.3.6.1.2.1.2.2.1.2      > "$TMPWALK/ifdescr" 2>/dev/null &
snmpwalk -v2c -c "$COMMUNITY" -t 3 -r 0 -On "$TARGET" 1.3.6.1.2.1.31.1.1.1.18  > "$TMPWALK/ifalias" 2>/dev/null &
snmpwalk -v2c -c "$COMMUNITY" -t 3 -r 0 -On "$TARGET" 1.3.6.1.2.1.2.2.1.7      > "$TMPWALK/ifadmin" 2>/dev/null &
wait
WALK_ENTNAME=$(cat "$TMPWALK/entname")
WALK_IFNAME=$(cat "$TMPWALK/ifname")
WALK_IFDESCR=$(cat "$TMPWALK/ifdescr")
WALK_IFALIAS=$(cat "$TMPWALK/ifalias")
WALK_IFADMIN=$(cat "$TMPWALK/ifadmin")

RESULT=$(awk '
function clean_val(str) {
    sub(/^[^=]*=[ \t]*/, "", str)
    sub(/^(STRING|INTEGER|Hex-STRING|Gauge32|Counter32|Counter64):[ \t]*/, "", str)
    sub(/^"/, "", str)
    sub(/"$/, "", str)
    gsub(/^[ \t]+|[ \t]+$/, "", str)
    return str
}
function clean_oid(str) {
    sub(/^\./, "", str)
    return str
}
$1 ~ /\.?1\.3\.6\.1\.2\.1\.31\.1\.1\.1\.1\.[0-9]+/ {
    oid = clean_oid($1)
    idx = oid; sub(/^1\.3\.6\.1\.2\.1\.31\.1\.1\.1\.1\./, "", idx)
    val = clean_val($0)
    if (val != "") { nameToIfIndex[val] = idx }
    next
}
$1 ~ /\.?1\.3\.6\.1\.2\.1\.2\.2\.1\.2\.[0-9]+/ {
    oid = clean_oid($1)
    idx = oid; sub(/^1\.3\.6\.1\.2\.1\.2\.2\.1\.2\./, "", idx)
    val = clean_val($0)
    if (val != "") { nameToIfIndex[val] = idx }
    next
}
$1 ~ /\.?1\.3\.6\.1\.2\.1\.31\.1\.1\.1\.18\.[0-9]+/ {
    oid = clean_oid($1)
    idx = oid; sub(/^1\.3\.6\.1\.2\.1\.31\.1\.1\.1\.18\./, "", idx)
    val = clean_val($0)
    ifIndexToAlias[idx] = val
    next
}
$1 ~ /\.?1\.3\.6\.1\.2\.1\.2\.2\.1\.7\.[0-9]+/ {
    oid = clean_oid($1)
    idx = oid; sub(/^1\.3\.6\.1\.2\.1\.2\.2\.1\.7\./, "", idx)
    val = clean_val($0)
    ifIndexToAdmin[idx] = val
    next
}
$1 ~ /\.?1\.3\.6\.1\.2\.1\.47\.1\.1\.1\.1\.7\.[0-9]+/ {
    oid = clean_oid($1)
    idx = oid; sub(/^1\.3\.6\.1\.2\.1\.47\.1\.1\.1\.1\.7\./, "", idx)
    val = clean_val($0)
    entIndexToName[idx] = val
    next
}
{
    oid = clean_oid($1)
    idx = oid; sub(/^1\.3\.6\.1\.4\.1\.2011\.5\.25\.31\.1\.1\.3\.1\.(5|32)\./, "", idx)
    if (idx != "" && !seen[idx]++) { activeOpticals[++count] = idx }
}
END {
    printf "{\"data\":["
    first = 1
    for (i = 1; i <= count; i++) {
        entIdx = activeOpticals[i]
        portName = entIndexToName[entIdx]
        if (portName == "") continue
        ifIdx = nameToIfIndex[portName]
        portAlias = ""
        adminState = "1"
        if (ifIdx != "") {
            portAlias = ifIndexToAlias[ifIdx]
            adminState = ifIndexToAdmin[ifIdx]
        }
        if (adminState == "2") continue
        if (portAlias == "" || portAlias == "NOT_USE") continue
        if (!first) printf ","
        first = 0
        gsub(/"/, "\\\"", portName)
        gsub(/"/, "\\\"", portAlias)
        printf "{\"{#SNMPINDEX}\":\"%s\", \"{#ENTPHYSICALNAME}\":\"%s\", \"{#IFALIAS}\":\"%s\"}", entIdx, portName, portAlias
    }
    printf "]}\n"
}
' <(echo "$WALK_IFNAME"; echo "$WALK_IFDESCR"; echo "$WALK_IFALIAS"; echo "$WALK_IFADMIN"; echo "$WALK_ENTNAME"; echo "$WALK_OPTICAL"))

if [ -n "$RESULT" ]; then
    echo "$RESULT" > "$CACHE_FILE" 2>/dev/null
    echo "$RESULT"
else
    echo '{"data":[]}'
fi
