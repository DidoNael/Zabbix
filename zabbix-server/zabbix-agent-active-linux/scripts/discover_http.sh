#!/bin/bash
# Descoberta LLD de sites HTTP
# Arg1: lista de URLs separadas por virgula
# Saida: JSON para Zabbix LLD (retorna {#URL} e {#HOST} extraido da URL)

TARGETS="$1"
if [ -z "$TARGETS" ]; then
    echo '{"data":[]}'
    exit 0
fi

echo '{"data":['
first=1
IFS=',' read -ra LIST <<< "$TARGETS"
for url in "${LIST[@]}"; do
    url=$(echo "$url" | tr -d ' ')
    [ -z "$url" ] && continue
    # Extrair hostname da URL
    host=$(echo "$url" | sed 's|https\?://||' | cut -d'/' -f1)
    [ $first -eq 0 ] && echo ","
    printf '  {"{#URL}": "%s", "{#HOST}": "%s"}' "$url" "$host"
    first=0
done
echo
echo ']}'
