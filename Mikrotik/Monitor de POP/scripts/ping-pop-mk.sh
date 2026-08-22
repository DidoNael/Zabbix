#!/bin/bash

# Defina o IP do MikroTik e o site como variáveis
mikrotik_ip="$1"
site="$2"

# Executa o comando ping no MikroTik e captura a saída
output=$(ssh zabbix@"$mikrotik_ip" "ping $site count=5; quit")

# Extrai todas as linhas que contêm os valores desejados
summary_lines=$(echo "$output" | grep -E 'sent=.*received=.*packet-loss=.*|min-rtt=.*|avg-rtt=.*|max-rtt=.*')

# Extrai os valores das linhas de resumo
sent=$(echo "$summary_lines" | grep -oP 'sent=\K[0-9]+' | head -n 1)
received=$(echo "$summary_lines" | grep -oP 'received=\K[0-9]+' | head -n 1)
packet_loss=$(echo "$summary_lines" | grep -oP 'packet-loss=\K[0-9]+%' | head -n 1)
min_rtt=$(echo "$summary_lines" | grep -oP 'min-rtt=\K[0-9]+ms' | head -n 1)
avg_rtt=$(echo "$summary_lines" | grep -oP 'avg-rtt=\K[0-9]+ms' | head -n 1)
max_rtt=$(echo "$summary_lines" | grep -oP 'max-rtt=\K[0-9]+ms' | head -n 1)

# Remove "ms" e o símbolo "%" dos resultados
min_rtt=$(echo "$min_rtt" | sed 's/ms//g')
avg_rtt=$(echo "$avg_rtt" | sed 's/ms//g')
max_rtt=$(echo "$max_rtt" | sed 's/ms//g')
packet_loss=$(echo "$packet_loss" | sed 's/%//g')

# Cria um objeto JSON com os valores extraídos
json_output=$(cat <<EOF
{
    "site": "$site",
    "sent": "$sent",
    "received": "$received",
    "packet_loss": "$packet_loss",
    "min_rtt": "$min_rtt",
    "avg_rtt": "$avg_rtt",
    "max_rtt": "$max_rtt"
}
EOF
)

# Exibe o JSON resultante
echo "$json_output"
