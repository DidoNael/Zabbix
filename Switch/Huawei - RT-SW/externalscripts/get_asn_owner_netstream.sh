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
# get_asn_owner_netstream.sh
# Local de instalação no Zabbix: /usr/lib/zabbix/externalscripts/
# Descrição: Consulta o nome/organização proprietária de um ASN (BGP Peer)
#            utilizando Cache Local em Disco e 5 Camadas de Fallback.

ASN=$(echo "$1" | tr -dc '0-9')
if [ -z "$ASN" ]; then
    echo "N/A"
    exit 0
fi

CACHE_DIR="/tmp/zabbix_asn_cache"
CACHE_FILE="${CACHE_DIR}/AS${ASN}.txt"
CACHE_TTL=2592000 # 30 dias em segundos (ASNs raramente mudam de proprietário)

mkdir -m 0755 -p "$CACHE_DIR" 2>/dev/null
chown zabbix:zabbix "$CACHE_DIR" "$CACHE_FILE" 2>/dev/null

# CAMADA 0: Cache Local Válido
if [ -s "$CACHE_FILE" ] && [ -r "$CACHE_FILE" ]; then
    NOW=$(date +%s)
    FILE_TIME=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
    AGE=$((NOW - FILE_TIME))
    if [ "$AGE" -lt "$CACHE_TTL" ]; then
        cat "$CACHE_FILE" 2>/dev/null && exit 0
    fi
fi

RESULT=""

# CAMADA 1: RADB WHOIS
if [ -z "$RESULT" ]; then
    RESULT=$(timeout 4s whois -h whois.radb.net -- "AS${ASN}" 2>/dev/null | grep -iE "^(OrgName|owner|descr|as-name):" | head -n 1 | awk -F: '{print $2}' | xargs)
fi

# CAMADA 2: WHOIS Padrão do Sistema
if [ -z "$RESULT" ]; then
    RESULT=$(timeout 4s whois "AS${ASN}" 2>/dev/null | grep -iE "^(OrgName|owner|descr|as-name|owner-c):" | head -n 1 | awk -F: '{print $2}' | xargs)
fi

# CAMADA 3: LACNIC WHOIS Web
if [ -z "$RESULT" ]; then
    RESULT=$(timeout 4s curl -s "https://lacnic.net/cgi-bin/lacnic/whois?query=AS${ASN}" 2>/dev/null | grep -iE "(OrgName|owner|as-name):" | head -n 1 | awk -F: '{print $2}' | sed 's/<[^>]*>//g' | xargs)
fi

# CAMADA 4: RIPE Stat API
if [ -z "$RESULT" ]; then
    RESULT=$(timeout 4s curl -s "https://stat.ripe.net/data/as-names/data.json?resource=AS${ASN}" 2>/dev/null | grep -oP '"'"${ASN}"'":\s*"\K[^"]+' | xargs)
fi

# CAMADA 5: BGPView API
if [ -z "$RESULT" ]; then
    RESULT=$(timeout 4s curl -s "https://api.bgpview.io/asn/${ASN}" 2>/dev/null | grep -oP '"description_short":\s*"\K[^"]+' | xargs)
fi

if [ -n "$RESULT" ]; then
    echo "$RESULT" > "$CACHE_FILE" 2>/dev/null
    echo "$RESULT"
else
    if [ -s "$CACHE_FILE" ] && [ -r "$CACHE_FILE" ]; then
        cat "$CACHE_FILE" 2>/dev/null
    else
        echo "AS${ASN}"
    fi
fi
