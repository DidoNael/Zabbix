#!/bin/bash
# ==============================================================================
# Script: get_asn_owner_v2.sh
# Local de instalação no Zabbix: /usr/lib/zabbix/externalscripts/get_asn_owner_v2.sh
# Descrição: Consulta o nome/organização proprietária de um ASN (BGP Peer)
#            utilizando Cache Local em Disco e 5 Camadas de Fallback.
# ==============================================================================

ASN=$(echo "$1" | tr -dc '0-9')
if [ -z "$ASN" ]; then
    echo "N/A"
    exit 0
fi

CACHE_DIR="/tmp/zabbix_asn_cache"
CACHE_FILE="${CACHE_DIR}/AS${ASN}.txt"
CACHE_TTL=2592000 # 30 dias em segundos (ASNs raramente mudam de proprietário)

# Cria o diretório de cache com permissão aberta para qualquer usuário (root/zabbix)
mkdir -m 0755 -p "$CACHE_DIR" 2>/dev/null
# Ajusta proprietário para zabbix caso executado como root
chown zabbix:zabbix "$CACHE_DIR" "$CACHE_FILE" 2>/dev/null

# CAMADA 0: Cache Local Válido (Resposta < 1 milissegundo)
if [ -s "$CACHE_FILE" ] && [ -r "$CACHE_FILE" ]; then
    NOW=$(date +%s)
    FILE_TIME=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
    AGE=$((NOW - FILE_TIME))
    if [ "$AGE" -lt "$CACHE_TTL" ]; then
        cat "$CACHE_FILE" 2>/dev/null && exit 0
    fi
fi

RESULT=""

# CAMADA 1: RADB WHOIS (Porta 43 - Timeout 4s)
if [ -z "$RESULT" ]; then
    RESULT=$(timeout 4s whois -h whois.radb.net -- "AS${ASN}" 2>/dev/null | grep -iE "^(OrgName|owner|descr|as-name):" | head -n 1 | awk -F: '{print $2}' | xargs)
fi

# CAMADA 2: WHOIS Padrão do Sistema (Porta 43 - Timeout 4s)
if [ -z "$RESULT" ]; then
    RESULT=$(timeout 4s whois "AS${ASN}" 2>/dev/null | grep -iE "^(OrgName|owner|descr|as-name|owner-c):" | head -n 1 | awk -F: '{print $2}' | xargs)
fi

# CAMADA 3: LACNIC WHOIS Web (HTTPS - Timeout 4s)
if [ -z "$RESULT" ]; then
    RESULT=$(timeout 4s curl -s "https://lacnic.net/cgi-bin/lacnic/whois?query=AS${ASN}" 2>/dev/null | grep -iE "(OrgName|owner|as-name):" | head -n 1 | awk -F: '{print $2}' | sed 's/<[^>]*>//g' | xargs)
fi

# CAMADA 4 (Fallback Global HTTPS): RIPE Stat API (Cobre todos os continentes/RIRs)
if [ -z "$RESULT" ]; then
    RESULT=$(timeout 4s curl -s "https://stat.ripe.net/data/as-names/data.json?resource=AS${ASN}" 2>/dev/null | grep -oP '"'"${ASN}"'":\s*"\K[^"]+' | xargs)
fi

# CAMADA 5 (Fallback Global HTTPS 2): BGPView API
if [ -z "$RESULT" ]; then
    RESULT=$(timeout 4s curl -s "https://api.bgpview.io/asn/${ASN}" 2>/dev/null | grep -oP '"description_short":\s*"\K[^"]+' | xargs)
fi

# SALVAMENTO EM CACHE OU FALLBACK DE EMERGÊNCIA
if [ -n "$RESULT" ]; then
    # Grava no cache silenciosamente (sem erros no stderr se houver problema de permissão no arquivo antigo)
    echo "$RESULT" > "$CACHE_FILE" 2>/dev/null
    echo "$RESULT"
else
    # Se todas as conexões externas falharem (ex: queda de link ou falha de DNS):
    if [ -s "$CACHE_FILE" ] && [ -r "$CACHE_FILE" ]; then
        # Serve o cache antigo mesmo vencido
        cat "$CACHE_FILE" 2>/dev/null
    else
        # Retorna o ASN formatado para evitar erro no Zabbix
        echo "AS${ASN}"
    fi
fi