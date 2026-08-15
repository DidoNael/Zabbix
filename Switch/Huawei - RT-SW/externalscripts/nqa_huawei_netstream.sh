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
# nqa_huawei_netstream.sh — Coleta resultados NQA ICMP da HUAWEI-NQA-MIB
# Uso: nqa_huawei_netstream.sh <host> <community> <owner> <instance>
# Retorno: JSON com rtt_min, rtt_max, rtt_avg, probes_sent, probes_recv, loss_pct

HOST="$1"
COMMUNITY="$2"
OWNER="${3:-admin}"
INSTANCE="$4"

if [ -z "$HOST" ] || [ -z "$COMMUNITY" ] || [ -z "$INSTANCE" ]; then
    echo '{"error":"missing args: host community [owner] instance"}'
    exit 1
fi

str_to_snmp_idx() {
    local s="$1"
    local len=${#s}
    local result="$len"
    for (( i=0; i<len; i++ )); do
        result="${result}.$(printf '%d' "'${s:$i:1}")"
    done
    echo "$result"
}

OWNER_IDX=$(str_to_snmp_idx "$OWNER")
INSTANCE_IDX=$(str_to_snmp_idx "$INSTANCE")
FULL_IDX="${OWNER_IDX}.${INSTANCE_IDX}"
OID_BASE="1.3.6.1.4.1.2011.5.25.111.4.1.1"

RAW=$(snmpwalk -v2c -c "$COMMUNITY" -Oqn "$HOST" "$OID_BASE" 2>/dev/null | grep "\.$FULL_IDX\.")

if [ -z "$RAW" ]; then
    echo '{"error":"no NQA data found for this instance"}'
    exit 1
fi

# Pega os dois maiores numeros de teste. Se o mais recente ainda nao completou
# (probes_sent=0), usa o anterior para evitar falso 100% de perda.
mapfile -t TESTS < <(echo "$RAW" | grep -oP "\.$FULL_IDX\.\K[0-9]+" | sort -nu | tail -2)
LAST_TEST="${TESTS[-1]}"
PREV_TEST="${TESTS[-2]:-$LAST_TEST}"

get_col() {
    local col="$1" test="$2"
    echo "$RAW" | grep "\.${col}\.${FULL_IDX}\.${test}\." | awk '{print $NF}' | head -1
}

PROBES_SENT=$(get_col 21 "$LAST_TEST"); PROBES_SENT=${PROBES_SENT:-0}
if [ "$PROBES_SENT" -eq 0 ] && [ "$PREV_TEST" != "$LAST_TEST" ]; then
    LAST_TEST="$PREV_TEST"
    PROBES_SENT=$(get_col 21 "$LAST_TEST"); PROBES_SENT=${PROBES_SENT:-0}
fi

RTT_MIN=$(get_col 11 "$LAST_TEST"); RTT_MIN=${RTT_MIN:-0}
RTT_MAX=$(get_col 12 "$LAST_TEST"); RTT_MAX=${RTT_MAX:-0}
RTT_AVG=$(get_col 26 "$LAST_TEST"); RTT_AVG=${RTT_AVG:-0}
PROBES_RECV=$(get_col 22 "$LAST_TEST"); PROBES_RECV=${PROBES_RECV:-0}

# Col 27 = lost packet ratio (%) calculado pelo proprio firmware.
# Mais confiavel que (sent-recv)/sent pois o firmware conta timeouts corretamente
# mesmo quando probes_recv nao decrementa (bug de firmware Huawei).
LOSS_PCT=$(get_col 27 "$LAST_TEST"); LOSS_PCT=${LOSS_PCT:-0}

echo "{\"rtt_min\":${RTT_MIN},\"rtt_max\":${RTT_MAX},\"rtt_avg\":${RTT_AVG},\"probes_sent\":${PROBES_SENT},\"probes_recv\":${PROBES_RECV},\"loss_pct\":${LOSS_PCT}}"
