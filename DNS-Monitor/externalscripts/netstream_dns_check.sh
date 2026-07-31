#!/usr/bin/env bash
# netstream_dns_check.sh — coleta métricas DNS via DIG para Zabbix External Check
# Suporta servidores DNS IPv4 e IPv6, registros A, AAAA, MX, NS, CNAME, PTR, TXT etc.
#
# Uso: netstream_dns_check.sh <server> <domain> <type> <tool> <metric> [timeout]
#   server:  IP ou hostname do servidor DNS (IPv4 ou IPv6)
#   domain:  domínio a consultar
#   type:    tipo de registro (A, AAAA, MX, NS, CNAME, PTR, TXT ...)
#   tool:    dig
#   metric:  time | status | rcode | result | answers
#   timeout: segundos (padrão: 5)
#
# Instalar em: /usr/lib/zabbix/externalscripts/netstream_dns_check.sh
# Permissão:   chmod +x netstream_dns_check.sh

# Caminho absoluto — garante funcionamento independente do PATH do usuário zabbix
DIG=$(command -v dig || echo /usr/bin/dig)

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

# ── Dispatcher ───────────────────────────────────────────────────────────────

case "${TOOL}_${METRIC}" in
    dig_time)    dig_time    ;;
    dig_status)  dig_status  ;;
    dig_rcode)   dig_rcode   ;;
    dig_result)  dig_result  ;;
    dig_answers) dig_answers ;;
    *)
        echo "ERRO: combinação inválida tool='$TOOL' metric='$METRIC'" >&2
        exit 1
        ;;
esac
