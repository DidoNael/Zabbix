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
# monitor_isp_experience_netstream.sh - Coleta de Experiência, MTR Trace e Detecção de Rota
# Descrição: Coleta Latência TCP/HTTP, Ping ICMP, MTR Trace Completo e Rota
#            com proteção contra falso positivo de ICMP bloqueado por firewall.

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
HTTP_OUT=$(curl -o /dev/null -s -w "%{http_code} %{time_connect} %{time_total}" --max-time 5 "https://${TARGET}:${PORT}" 2>/dev/null)
if [ -z "$HTTP_OUT" ] || [ "$HTTP_OUT" = "000 0.000000 0.000000" ]; then
    HTTP_OUT=$(curl -o /dev/null -s -w "%{http_code} %{time_connect} %{time_total}" --max-time 5 "http://${TARGET}" 2>/dev/null)
fi

HTTP_CODE=$(echo "$HTTP_OUT" | awk '{print $1}')
TCP_CONN_SEC=$(echo "$HTTP_OUT" | awk '{print $2}')
HTTP_TOT_SEC=$(echo "$HTTP_OUT" | awk '{print $3}')

HTTP_CODE=${HTTP_CODE:-0}
TCP_HANDSHAKE_MS=$(awk "BEGIN {printf \"%.2f\", ${TCP_CONN_SEC:-0} * 1000}")
HTTP_TIME_MS=$(awk "BEGIN {printf \"%.2f\", ${HTTP_TOT_SEC:-0} * 1000}")

# 3. Medir Latência e Perda ICMP Ping (3 pacotes, timeout rápido)
PING_OUT=$(ping -c 3 -W 1 "$RESOLVED_IP" 2>/dev/null)
ICMP_LOSS=$(echo "$PING_OUT" | grep -oP '\d+(?=% packet loss)' | head -n 1)
ICMP_LOSS=${ICMP_LOSS:-100}
ICMP_PING_MS=$(echo "$PING_OUT" | grep -oP 'rtt min/avg/max/mdev = \S+' | awk -F'/' '{printf "%.2f", $5}')
ICMP_PING_MS=${ICMP_PING_MS:-0}

# PROTEÇÃO ANTI-FALSO POSITIVO: se o site bloqueia ICMP mas respondeu TCP/HTTP, não é offline
IS_ONLINE=1
if [ "$HTTP_CODE" -eq 0 ] && [ $(awk "BEGIN {print ($TCP_HANDSHAKE_MS == 0) ? 1 : 0}") -eq 1 ] && [ "$ICMP_LOSS" -eq 100 ]; then
    IS_ONLINE=0
fi

EFFECTIVE_LOSS=$ICMP_LOSS
if [ "$IS_ONLINE" -eq 1 ] && [ "$ICMP_LOSS" -eq 100 ]; then
    EFFECTIVE_LOSS=0
fi

# 4. Executar MTR Trace Completo (ou Traceroute ICMP fallback)
MTR_TEXT=""
if command -v mtr >/dev/null 2>&1; then
    MTR_TEXT=$(mtr -r -c 2 -n "$RESOLVED_IP" 2>/dev/null | tr '\n' ';' | sed 's/"/\\"/g')
else
    MTR_TEXT=$(traceroute -I -m 12 -n -w 1 "$RESOLVED_IP" 2>/dev/null | tr '\n' ';' | sed 's/"/\\"/g')
fi

# 5. Detecção de Rota (IX.br / PTT vs Trânsito IP)
CURRENT_ROUTE="TRANSITO"
HOP_COUNT=$(echo "$MTR_TEXT" | tr ';' '\n' | grep -c '^[ 0-9]')

if echo "$MTR_TEXT" | grep -E -q '185\.6\.6\.|200\.219\.|ix\.br|ptt\.br'; then
    CURRENT_ROUTE="IX"
elif [ "$EXPECTED_ROUTE" = "IX" ] && [ "$HOP_COUNT" -le 7 ] && [ "$IS_ONLINE" -eq 1 ]; then
    CURRENT_ROUTE="IX"
elif [ "$EXPECTED_ROUTE" = "TRANSITO" ]; then
    CURRENT_ROUTE="TRANSITO"
fi

ROUTE_CHANGED=0
if [ "$CURRENT_ROUTE" != "$EXPECTED_ROUTE" ]; then
    ROUTE_CHANGED=1
    ROUTE_STATUS="DESVIO: ${EXPECTED_ROUTE} -> ${CURRENT_ROUTE}"
else
    ROUTE_STATUS="Normal (${CURRENT_ROUTE})"
fi

cat <<EOF
{
  "status": $IS_ONLINE,
  "id": "$ID",
  "target": "$TARGET",
  "resolved_ip": "$RESOLVED_IP",
  "http_code": $HTTP_CODE,
  "http_time_ms": $HTTP_TIME_MS,
  "tcp_handshake_ms": $TCP_HANDSHAKE_MS,
  "icmp_ping_ms": $ICMP_PING_MS,
  "icmp_loss_pct": $EFFECTIVE_LOSS,
  "raw_icmp_loss": $ICMP_LOSS,
  "expected_route": "$EXPECTED_ROUTE",
  "current_route": "$CURRENT_ROUTE",
  "route_changed": $ROUTE_CHANGED,
  "route_status": "$ROUTE_STATUS",
  "route_summary": "$RESOLVED_IP via $CURRENT_ROUTE ($HOP_COUNT saltos)",
  "mtr_trace": "$MTR_TEXT"
}
EOF
