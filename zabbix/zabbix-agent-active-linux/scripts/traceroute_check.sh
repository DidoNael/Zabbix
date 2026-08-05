#!/bin/bash
# Traceroute - retorna numero de hops, RTT ultimo hop e RTT maximo
# Arg1: host/IP alvo
# Arg2: metrica (hops | last_rtt | max_rtt)

TARGET="$1"
METRIC="${2:-hops}"

if [ -z "$TARGET" ]; then
    echo "-1"
    exit 1
fi

# -n: sem resolucao DNS, -w 1: timeout 1s por probe, -q 1: 1 probe por hop
RAW=$(traceroute -n -w 1 -q 1 -m 30 "$TARGET" 2>/dev/null)

case "$METRIC" in
    hops)
        echo "$RAW" | grep -c '^ *[0-9]'
        ;;
    last_rtt)
        echo "$RAW" | awk '/^ *[0-9]/ {rtt=$(NF-1)} END {printf "%.2f\n", rtt+0}'
        ;;
    max_rtt)
        echo "$RAW" | awk '/^ *[0-9]/ && $NF ~ /ms/ {
            for(i=2;i<=NF;i++) if($i~/^[0-9]/) { if($i+0>max) max=$i+0 }
        } END {printf "%.2f\n", max+0}'
        ;;
    *)
        echo "-1"
        exit 1
        ;;
esac
