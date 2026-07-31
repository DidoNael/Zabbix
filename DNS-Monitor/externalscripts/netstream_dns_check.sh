#!/usr/bin/env bash
# netstream_dns_check.sh — coleta métricas DNS via DIG e NSLOOKUP para Zabbix External Check
# Suporta servidores DNS IPv4 e IPv6, registros A, AAAA, MX, NS, CNAME, PTR, TXT etc.
#
# Uso: netstream_dns_check.sh <server> <domain> <type> <tool> <metric> [timeout]
#   server:  IP ou hostname do servidor DNS (IPv4 ou IPv6)
#   domain:  domínio a consultar
#   type:    tipo de registro (A, AAAA, MX, NS, CNAME, PTR, TXT ...)
#   tool:    dig | nslookup
#   metric:  time | status | rcode | result | answers
#   timeout: segundos (padrão: 5)
#
# Instalar em: /usr/lib/zabbix/externalscripts/netstream_dns_check.sh
# Permissão:   chmod +x netstream_dns_check.sh

# Caminhos absolutos — garante funcionamento independente do PATH do usuário zabbix
DIG=$(command -v dig || echo /usr/bin/dig)
NSLOOKUP=$(command -v nslookup || echo /usr/bin/nslookup)

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

# ── DIG ──────────────────────────────────────────────────────────────────────
# dig suporta servidores IPv6 nativamente: dig @2001:4860:4860::8888 google.com AAAA
# Não é necessário tratamento especial para IPv6.

dig_time() {
    local ms
    ms=$("$DIG" @"$SERVER" "$DOMAIN" "$TYPE" \
             +time="$TIMEOUT" +tries=1 +noall +stats 2>/dev/null \
         | grep "Query time:" | awk '{print $4}')
    echo "${ms:-9999}"
}

dig_status() {
    local out
    out=$("$DIG" @"$SERVER" "$DOMAIN" "$TYPE" \
              +time="$TIMEOUT" +tries=1 +short 2>/dev/null \
          | grep -v '^$')
    [[ -n "$out" ]] && echo 1 || echo 0
}

dig_rcode() {
    local rcode
    rcode=$("$DIG" @"$SERVER" "$DOMAIN" "$TYPE" \
                +time="$TIMEOUT" +tries=1 2>/dev/null \
            | grep -oP 'status:\s*\K[A-Z]+')
    echo "${rcode:-TIMEOUT}"
}

dig_result() {
    # +short: para AAAA retorna endereços IPv6; para MX retorna "10 mail.exemplo.com"
    "$DIG" @"$SERVER" "$DOMAIN" "$TYPE" \
        +time="$TIMEOUT" +tries=1 +short 2>/dev/null \
    | grep -v '^$' \
    | head -5 \
    | paste -sd ',' -
}

dig_answers() {
    # Conta linhas na ANSWER SECTION — 0 com NOERROR indica possível anomalia
    local count
    count=$("$DIG" @"$SERVER" "$DOMAIN" "$TYPE" \
                +time="$TIMEOUT" +tries=1 +noall +answer 2>/dev/null \
            | grep -vc '^$')
    echo "${count:-0}"
}

# ── NSLOOKUP ─────────────────────────────────────────────────────────────────
# nslookup suporta servidores IPv6 nativamente: nslookup domain 2001:4860:4860::8888

nslookup_time() {
    local start end
    start=$(date +%s%3N)
    "$NSLOOKUP" -timeout="$TIMEOUT" -type="$TYPE" "$DOMAIN" "$SERVER" >/dev/null 2>&1
    end=$(date +%s%3N)
    echo $(( end - start ))
}

nslookup_status() {
    local out
    out=$("$NSLOOKUP" -timeout="$TIMEOUT" -type="$TYPE" "$DOMAIN" "$SERVER" 2>&1)

    if echo "$out" | grep -qE "NXDOMAIN|can't find|No answer|SERVFAIL|timed out|no servers|connection refused"; then
        echo 0
    elif echo "$out" | grep -qE "Address:|Name:|mail exchanger|nameserver|canonical name"; then
        echo 1
    else
        echo 0
    fi
}

nslookup_result() {
    local out
    out=$("$NSLOOKUP" -timeout="$TIMEOUT" -type="$TYPE" "$DOMAIN" "$SERVER" 2>/dev/null)

    case "${TYPE^^}" in
        A|AAAA)
            # Linhas "Address: x" excluindo a do próprio servidor DNS (contém "#porta")
            echo "$out" | grep -E "Address:" | grep -v "#" | awk '{print $NF}' \
            | head -5 | paste -sd ',' -
            ;;
        MX)
            echo "$out" | grep -E "mail exchanger" | awk '{print $(NF-1),$NF}' \
            | head -5 | paste -sd ',' -
            ;;
        NS)
            echo "$out" | grep -E "nameserver" | awk '{print $NF}' \
            | head -5 | paste -sd ',' -
            ;;
        CNAME)
            echo "$out" | grep -E "canonical name" | awk '{print $NF}' \
            | head -3 | paste -sd ',' -
            ;;
        TXT)
            echo "$out" | grep -E "text =" | sed 's/.*text = //' \
            | head -3 | paste -sd ',' -
            ;;
        PTR)
            echo "$out" | grep -E "name =" | awk '{print $NF}' \
            | head -3 | paste -sd ',' -
            ;;
        *)
            # Fallback genérico: remove cabeçalho do servidor e linhas vazias
            echo "$out" | grep -v "^Server:\|^Address:.*#\|^$" \
            | tail -n +2 | head -5 | paste -sd ',' -
            ;;
    esac
}

# ── Dispatcher ───────────────────────────────────────────────────────────────

case "${TOOL}_${METRIC}" in
    dig_time)          dig_time          ;;
    dig_status)        dig_status        ;;
    dig_rcode)         dig_rcode         ;;
    dig_result)        dig_result        ;;
    dig_answers)       dig_answers       ;;
    nslookup_time)     nslookup_time     ;;
    nslookup_status)   nslookup_status   ;;
    nslookup_result)   nslookup_result   ;;
    *)
        echo "ERRO: combinação inválida tool='$TOOL' metric='$METRIC'" >&2
        exit 1
        ;;
esac
