#!/bin/bash
# Monitoramento HTTP via curl
# Arg1: URL completa
# Arg2: metrica (time | status | ssl_days)

URL="$1"
METRIC="${2:-status}"

if [ -z "$URL" ]; then
    echo "-1"
    exit 1
fi

case "$METRIC" in
    time)
        # Tempo total em ms
        ms=$(curl -o /dev/null -s -w "%{time_total}" --max-time 10 "$URL" 2>/dev/null)
        if [ -z "$ms" ]; then
            echo "0"
        else
            printf "%.0f\n" "$(echo "$ms * 1000" | bc 2>/dev/null || echo "0")"
        fi
        ;;
    status)
        code=$(curl -o /dev/null -s -w "%{http_code}" --max-time 10 "$URL" 2>/dev/null)
        echo "${code:-0}"
        ;;
    ssl_days)
        host=$(echo "$URL" | sed 's|https\?://||' | cut -d'/' -f1)
        expiry=$(echo | openssl s_client -servername "$host" -connect "$host:443" 2>/dev/null \
            | openssl x509 -noout -enddate 2>/dev/null \
            | cut -d= -f2)
        if [ -z "$expiry" ]; then
            echo "-1"
        else
            exp_epoch=$(date -d "$expiry" +%s 2>/dev/null)
            now_epoch=$(date +%s)
            echo $(( (exp_epoch - now_epoch) / 86400 ))
        fi
        ;;
    *)
        echo "-1"
        exit 1
        ;;
esac
