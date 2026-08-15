#!/bin/bash
# Ping ICMP - retorna latencia, perda e jitter
# Arg1: host/IP alvo
# Arg2: metrica (latency | loss | jitter)

TARGET="$1"
METRIC="${2:-latency}"
COUNT=10

if [ -z "$TARGET" ]; then
    echo "-1"
    exit 1
fi

RAW=$(ping -c "$COUNT" -W 1 "$TARGET" 2>/dev/null)

case "$METRIC" in
    latency)
        # RTT medio em ms (campo avg do resumo)
        echo "$RAW" | awk -F'/' '/rtt|round-trip/ {printf "%.2f\n", $5}' | head -1
        ;;
    loss)
        echo "$RAW" | awk '/packet loss/ {gsub(/%/,""); for(i=1;i<=NF;i++) if($i~/loss/) print $(i-1)}' | head -1
        ;;
    jitter)
        # mdev (mean deviation) como proxy de jitter
        echo "$RAW" | awk -F'/' '/rtt|round-trip/ {printf "%.2f\n", $6}' | head -1
        ;;
    *)
        echo "-1"
        exit 1
        ;;
esac
