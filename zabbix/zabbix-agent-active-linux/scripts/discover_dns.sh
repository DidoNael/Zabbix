#!/bin/bash
# Descoberta LLD de combinacoes dominio x servidor DNS (produto cartesiano)
# Arg1: lista de dominios separados por virgula
# Arg2: lista de servidores DNS separados por virgula

DOMAINS="$1"
SERVERS="$2"

if [ -z "$DOMAINS" ] || [ -z "$SERVERS" ]; then
    echo '{"data":[]}'
    exit 0
fi

echo '{"data":['
first=1
IFS=',' read -ra DOM_LIST <<< "$DOMAINS"
IFS=',' read -ra SRV_LIST <<< "$SERVERS"
for domain in "${DOM_LIST[@]}"; do
    domain=$(echo "$domain" | tr -d ' ')
    [ -z "$domain" ] && continue
    for server in "${SRV_LIST[@]}"; do
        server=$(echo "$server" | tr -d ' ')
        [ -z "$server" ] && continue
        [ $first -eq 0 ] && echo ","
        printf '  {"{#DNS_DOMAIN}": "%s", "{#DNS_SERVER}": "%s"}' "$domain" "$server"
        first=0
    done
done
echo
echo ']}'
