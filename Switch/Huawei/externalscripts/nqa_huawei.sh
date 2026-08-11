#!/bin/bash
# nqa_huawei.sh — Coleta resultados NQA ICMP da HUAWEI-NQA-MIB
# Uso: nqa_huawei.sh <host> <community> <owner> <instance>
# Retorno: JSON com rtt_min, rtt_max, rtt_avg, probes_sent, probes_recv, loss_pct
#
# OID base: 1.3.6.1.4.1.2011.5.25.111.4.1.1
# Índice da instância: {len_owner}.{owner_ascii}.{len_instance}.{instance_ascii}
# Sufixo do resultado: .{col}.{idx_instancia}.{num_teste}.{num_probe}

HOST="$1"
COMMUNITY="$2"
OWNER="${3:-admin}"
INSTANCE="$4"

if [ -z "$HOST" ] || [ -z "$COMMUNITY" ] || [ -z "$INSTANCE" ]; then
    echo '{"error":"missing args: host community [owner] instance"}'
    exit 1
fi

# Converter string para índice SNMP decimal (len + ascii bytes)
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

# Walk na tabela de resultados e filtrar pela instância
RAW=$(snmpwalk -v2c -c "$COMMUNITY" -Oqn "$HOST" "$OID_BASE" 2>/dev/null | grep "\.$FULL_IDX\.")

if [ -z "$RAW" ]; then
    echo '{"error":"no NQA data found for this instance"}'
    exit 1
fi

# Extrair maior número de teste (penúltimo elemento após o FULL_IDX)
LAST_TEST=$(echo "$RAW" | grep -oP "\.$FULL_IDX\.\K[0-9]+" | sort -n | tail -1)

if [ -z "$LAST_TEST" ]; then
    echo '{"error":"cannot determine test number"}'
    exit 1
fi

# Extrair valores do último teste (probe 1)
get_col() {
    local col="$1"
    echo "$RAW" | grep "\.${col}\.${FULL_IDX}\.${LAST_TEST}\." | awk '{print $NF}' | head -1
}

RTT_MIN=$(get_col 11)
RTT_MAX=$(get_col 12)
RTT_AVG=$(get_col 26)
PROBES_SENT=$(get_col 21)
PROBES_RECV=$(get_col 22)

RTT_MIN=${RTT_MIN:-0}; RTT_MAX=${RTT_MAX:-0}; RTT_AVG=${RTT_AVG:-0}
PROBES_SENT=${PROBES_SENT:-0}; PROBES_RECV=${PROBES_RECV:-0}

LOSS_PCT=$(python3 -c "s=$PROBES_SENT; r=$PROBES_RECV; print(round((s-r)*100/s,1) if s>0 else 100)")

echo "{\"rtt_min\":${RTT_MIN},\"rtt_max\":${RTT_MAX},\"rtt_avg\":${RTT_AVG},\"probes_sent\":${PROBES_SENT},\"probes_recv\":${PROBES_RECV},\"loss_pct\":${LOSS_PCT}}"
