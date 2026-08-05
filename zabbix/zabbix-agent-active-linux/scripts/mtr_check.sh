#!/bin/bash
# MTR - retorna RTT medio e perda de pacotes ao destino final
# Arg1: host/IP alvo
# Arg2: metrica (avg_rtt | loss)

TARGET="$1"
METRIC="${2:-avg_rtt}"

if [ -z "$TARGET" ]; then
    echo "-1"
    exit 1
fi

# --report: modo nao-interativo, -n: sem DNS, -c 10: 10 ciclos
RAW=$(mtr --report -n -c 10 "$TARGET" 2>/dev/null)

case "$METRIC" in
    avg_rtt)
        # Ultima linha (destino) campo Avg
        echo "$RAW" | awk 'END {print $4+0}'
        ;;
    loss)
        # Ultima linha campo Loss%
        echo "$RAW" | awk 'END {gsub(/%/,"",$3); print $3+0}'
        ;;
    *)
        echo "-1"
        exit 1
        ;;
esac
