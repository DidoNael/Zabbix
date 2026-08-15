#!/bin/bash
# DNS - tempo de resolucao e status via dig
# Arg1: dominio
# Arg2: servidor DNS
# Arg3: metrica (resolve_time | status)

DOMAIN="$1"
SERVER="$2"
METRIC="${3:-status}"

if [ -z "$DOMAIN" ] || [ -z "$SERVER" ]; then
    echo "-1"
    exit 1
fi

DIG=$(command -v dig || echo /usr/bin/dig)

case "$METRIC" in
    resolve_time)
        ms=$("$DIG" "@$SERVER" "$DOMAIN" +noall +stats 2>/dev/null \
            | awk '/Query time:/ {print $4}')
        echo "${ms:-9999}"
        ;;
    status)
        rcode=$("$DIG" "@$SERVER" "$DOMAIN" +noall +comments 2>/dev/null \
            | awk '/status:/ {gsub(/,/,"",$6); print $6}')
        if [ "$rcode" = "NOERROR" ]; then
            echo "1"
        else
            echo "0"
        fi
        ;;
    *)
        echo "-1"
        exit 1
        ;;
esac
