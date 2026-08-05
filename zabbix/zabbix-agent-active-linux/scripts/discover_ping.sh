#!/bin/bash
# Descoberta LLD de targets de ping
# Arg1: lista de IPs/hosts separados por virgula
# Saida: JSON para Zabbix LLD

TARGETS="$1"
if [ -z "$TARGETS" ]; then
    echo '{"data":[]}'
    exit 0
fi

echo '{"data":['
first=1
IFS=',' read -ra LIST <<< "$TARGETS"
for target in "${LIST[@]}"; do
    target=$(echo "$target" | tr -d ' ')
    [ -z "$target" ] && continue
    [ $first -eq 0 ] && echo ","
    printf '  {"{#TARGET}": "%s"}' "$target"
    first=0
done
echo
echo ']}'
