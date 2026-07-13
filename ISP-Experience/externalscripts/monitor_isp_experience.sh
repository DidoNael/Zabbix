#!/usr/bin/env bash
# ==============================================================================
# monitor_isp_experience.sh - Coleta de Experiência e Detecção de Rota (IX vs Trânsito)
# ==============================================================================
# Autor: Sem Limite Telecom & Nael
# Versão: 1.0.0
# Uso: monitor_isp_experience.sh <ID> <TARGET_URL_OR_IP> <PORT> <EXPECTED_ROUTE>
# Exemplo: monitor_isp_experience.sh "valorant_br" "br.leagueoflegends.com" "443" "IX"
# ==============================================================================

ID="${1:-unknown}"
TARGET="${2:-127.0.0.1}"
PORT="${3:-443}"
EXPECTED_ROUTE="${4:-IX}"

# 1. Resolver IP de destino
RESOLVED_IP=$(getent ahostsv4 "$TARGET" 2>/dev/null | head -n 1 | awk '{print $1}')
if [ -z "$RESOLVED_IP" ]; then
    RESOLVED_IP="$TARGET"
fi

# 2. Medir Latência TCP Handshake e HTTP (curl)
HTTP_OUT=$(curl -o /dev/null -s -w "%{http_code} %{time_connect} %{time_total}" --max-time 3 "https://${TARGET}:${PORT}" 2>/dev/null)
if [ -z "$HTTP_OUT" ] || [ "$HTTP_OUT" = "000 0.000000 0.000000" ]; then
    HTTP_OUT=$(curl -o /dev/null -s -w "%{http_code} %{time_connect} %{time_total}" --max-time 3 "http://${TARGET}" 2>/dev/null)
fi

HTTP_CODE=$(echo "$HTTP_OUT" | awk '{print $1}')
TCP_CONN_SEC=$(echo "$HTTP_OUT" | awk '{print $2}')
HTTP_TOT_SEC=$(echo "$HTTP_OUT" | awk '{print $3}')

HTTP_CODE=${HTTP_CODE:-0}
TCP_HANDSHAKE_MS=$(awk "BEGIN {printf \"%.2f\", ${TCP_CONN_SEC:-0} * 1000}")
HTTP_TIME_MS=$(awk "BEGIN {printf \"%.2f\", ${HTTP_TOT_SEC:-0} * 1000}")

# 3. Medir Latência e Perda ICMP Ping (3 pacotes)
PING_OUT=$(ping -c 3 -W 1 "$RESOLVED_IP" 2>/dev/null)
ICMP_LOSS=$(echo "$PING_OUT" | grep -oP '\d+(?=% packet loss)' | head -n 1)
ICMP_LOSS=${ICMP_LOSS:-100}
ICMP_PING_MS=$(echo "$PING_OUT" | grep -oP 'rtt min/avg/max/mdev = \S+' | awk -F'/' '{printf "%.2f", $5}')
ICMP_PING_MS=${ICMP_PING_MS:-0}

# 4. Detecção Inteligente de Rota de Saída (IX.br / PTT vs Trânsito IP)
# Verifica hops via traceroute rápido (máx 8 saltos, timeout 1s)
CURRENT_ROUTE="TRANSITO"
HOP_COUNT=0
HOP_IX_FOUND=0

TRACE_OUT=$(traceroute -m 8 -n -w 1 "$RESOLVED_IP" 2>/dev/null)
HOP_COUNT=$(echo "$TRACE_OUT" | grep -v 'traceroute to' | grep -c '^[ 0-9]')

# Regra de identificação de IX.br / PTT / CDN Direta:
# - Faixas típicas do IX.br (185.6.6.x, 200.219.x.x) ou rotas curtas de peering direto
if echo "$TRACE_OUT" | grep -E -q '185\.6\.6\.|200\.219\.|ix\.br|ptt\.br'; then
    CURRENT_ROUTE="IX"
    HOP_IX_FOUND=1
elif [ "$EXPECTED_ROUTE" = "IX" ] && [ "$HOP_COUNT" -le 5 ] && [ "$ICMP_LOSS" -lt 100 ]; then
    # CDN local / Peering direto com menos de 5 saltos dentro da rede ISP
    CURRENT_ROUTE="IX"
fi

# 5. Verifica Desvio de Rota (Mudança do IX para Trânsito ou vice-versa)
ROUTE_CHANGED=0
if [ "$CURRENT_ROUTE" != "$EXPECTED_ROUTE" ]; then
    ROUTE_CHANGED=1
    ROUTE_STATUS="ALERTA: Desvio de Rota (${EXPECTED_ROUTE} -> ${CURRENT_ROUTE})"
else
    ROUTE_STATUS="Normal (${CURRENT_ROUTE})"
fi

# 6. Registro de histórico de rota em arquivo local (para auditoria)
HISTORY_FILE="/tmp/isp_route_history_${ID}.log"
NOW=$(date '+%Y-%m-%d %H:%M:%S')
LAST_ROUTE=$(tail -n 1 "$HISTORY_FILE" 2>/dev/null | awk '{print $4}')
if [ "$LAST_ROUTE" != "$CURRENT_ROUTE" ]; then
    echo "[$NOW] $ID | Rota mudou: $LAST_ROUTE -> $CURRENT_ROUTE (IP: $RESOLVED_IP)" >> "$HISTORY_FILE"
fi

# 7. Saída JSON única para Master Item do Zabbix
cat <<EOF
{
  "status": 1,
  "id": "$ID",
  "target": "$TARGET",
  "resolved_ip": "$RESOLVED_IP",
  "http_code": $HTTP_CODE,
  "http_time_ms": $HTTP_TIME_MS,
  "tcp_handshake_ms": $TCP_HANDSHAKE_MS,
  "icmp_ping_ms": $ICMP_PING_MS,
  "icmp_loss_pct": $ICMP_LOSS,
  "expected_route": "$EXPECTED_ROUTE",
  "current_route": "$CURRENT_ROUTE",
  "route_changed": $ROUTE_CHANGED,
  "route_status": "$ROUTE_STATUS",
  "route_summary": "$RESOLVED_IP via $CURRENT_ROUTE ($HOP_COUNT saltos)"
}
EOF
