#!/usr/bin/env bash
# ==============================================================================
# discovery_isp_services.sh - Zabbix Low-Level Discovery (LLD) para Web & Jogos
# ==============================================================================
# Autor: Sem Limite Telecom & Nael
# Versão: 1.0.0
# Descrição: Descobre serviços de Jogos, Streaming, Sociais e Bancos configurados
#            em /etc/zabbix/isp_services.json ou no diretório atual.
# ==============================================================================

CONFIG_FILE="${1:-/etc/zabbix/isp_services.json}"

if [ ! -f "$CONFIG_FILE" ]; then
    DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
    CONFIG_FILE="${DIR}/isp_services.json"
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo '{"data":[]}'
    exit 0
fi

# Converte o array de JSON no formato nativo LLD do Zabbix ({#ID}, {#NAME}, etc.)
if command -v jq >/dev/null 2>&1; then
    jq -c '{
        data: [
            .[] | {
                "{#ID}": .id,
                "{#NAME}": .name,
                "{#CATEGORY}": .category,
                "{#TARGET}": .target,
                "{#PORT}": (.port | tostring),
                "{#EXPECTED_ROUTE}": .expected_route
            }
        ]
    }' "$CONFIG_FILE"
else
    # Fallback em Python caso jq não esteja instalado
    python3 -c "
import json, sys
try:
    with open('$CONFIG_FILE') as f:
        items = json.load(f)
    out = []
    for item in items:
        out.append({
            '{#ID}': str(item.get('id', '')),
            '{#NAME}': str(item.get('name', '')),
            '{#CATEGORY}': str(item.get('category', '')),
            '{#TARGET}': str(item.get('target', '')),
            '{#PORT}': str(item.get('port', 443)),
            '{#EXPECTED_ROUTE}': str(item.get('expected_route', 'IX'))
        })
    print(json.dumps({'data': out}))
except Exception as e:
    print('{\"data\":[]}')
"
fi
