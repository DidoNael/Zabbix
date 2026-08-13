#!/usr/bin/env bash
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
# discovery_isp_services_netstream.sh - Zabbix Low-Level Discovery (LLD) para Web & Jogos
# Descrição: Descobre serviços de Jogos, Streaming, Sociais e Bancos configurados
#            em /etc/zabbix/isp_services.json ou no diretório atual.

CONFIG_FILE="${1:-/etc/zabbix/isp_services.json}"

if [ ! -f "$CONFIG_FILE" ]; then
    DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
    CONFIG_FILE="${DIR}/isp_services.json"
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo '{"data":[]}'
    exit 0
fi

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
