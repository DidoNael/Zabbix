#!/usr/bin/env bash
# netstream_dns_check.sh — coleta métricas DNS via DIG e NSLOOKUP para Zabbix External Check
# Uso: netstream_dns_check.sh <server> <domain> <type> <tool> <metric> [timeout]
#   tool:   dig | nslookup
#   metric: time | status | rcode | result
# Instalar em: /usr/lib/zabbix/externalscripts/netstream_dns_check.sh
# Permissão:   chmod +x netstream_dns_check.sh

SERVER="$1"
DOMAIN="$2"
TYPE="${3:-A}"
TOOL="${4:-dig}"
METRIC="${5:-time}"
TIMEOUT="${6:-5}"

if [[ -z "$SERVER" || -z "$DOMAIN" ]]; then
    echo "ERRO: uso: $0 <server> <domain> <type> <tool> <metric> [timeout]" >&2
    exit 1
fi

# ── DIG ─────────────────────────────────────────────────────────────────────

dig_time() {
    local ms
    ms=$(dig @"$SERVER" "$DOMAIN" "$TYPE" \
             +time="$TIMEOUT" +tries=1 +stats +noall +comments 2>/dev/null \
         | grep "Query time:" | awk '{print $4}')
    echo "${ms:-9999}"
}

dig_status() {
    local out
    out=$(dig @"$SERVER" "$DOMAIN" "$TYPE" \
              +time="$TIMEOUT" +tries=1 +short 2>/dev/null)
    [[ -n "$out" ]] && echo 1 || echo 0
}

dig_rcode() {
    local rcode
    rcode=$(dig @"$SERVER" "$DOMAIN" "$TYPE" \
                +time="$TIMEOUT" +tries=1 2>/dev/null \
            | grep -oP 'status:\s*\K[A-Z]+')
    echo "${rcode:-TIMEOUT}"
}

dig_result() {
    dig @"$SERVER" "$DOMAIN" "$TYPE" \
        +time="$TIMEOUT" +tries=1 +short 2>/dev/null \
    | head -5 \
    | paste -sd ',' -
}

# ── NSLOOKUP ─────────────────────────────────────────────────────────────────

nslookup_time() {
    local start end
    start=$(date +%s%3N)
    nslookup -timeout="$TIMEOUT" -type="$TYPE" "$DOMAIN" "$SERVER" >/dev/null 2>&1
    end=$(date +%s%3N)
    echo $(( end - start ))
}

nslookup_status() {
    local out
    out=$(nslookup -timeout="$TIMEOUT" -type="$TYPE" "$DOMAIN" "$SERVER" 2>&1)
    if echo "$out" | grep -qE "NXDOMAIN|can't find|No answer|SERVFAIL|timed out|no servers"; then
        echo 0
    elif echo "$out" | grep -qE "Address:|answer:"; then
        echo 1
    else
        echo 0
    fi
}

nslookup_result() {
    nslookup -timeout="$TIMEOUT" -type="$TYPE" "$DOMAIN" "$SERVER" 2>/dev/null \
    | grep -E "^Address:" | grep -v "#" | awk '{print $2}' \
    | head -5 | paste -sd ',' -
}

# ── Dispatcher ───────────────────────────────────────────────────────────────

case "${TOOL}_${METRIC}" in
    dig_time)          dig_time          ;;
    dig_status)        dig_status        ;;
    dig_rcode)         dig_rcode         ;;
    dig_result)        dig_result        ;;
    nslookup_time)     nslookup_time     ;;
    nslookup_status)   nslookup_status   ;;
    nslookup_result)   nslookup_result   ;;
    *)
        echo "ERRO: combinação inválida tool='$TOOL' metric='$METRIC'" >&2
        exit 1
        ;;
esac
