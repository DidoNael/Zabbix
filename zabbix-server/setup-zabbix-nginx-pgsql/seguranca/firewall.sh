#!/usr/bin/env bash
# ============================================================================
# firewall.sh — Firewall nftables para o servidor Zabbix (Debian 13)
# ----------------------------------------------------------------------------
# Política padrão: DROP na entrada. Libera apenas o necessário.
#   22    SSH            (gerência)
#   80    HTTP           (frontend; redirecione p/ 443 após TLS)
#   443   HTTPS          (frontend com TLS)
#   10051 zabbix-server  (trapper — proxies/agents ativos enviam dados)
#   10050 zabbix-agent   (passivo) — restrito à rede de gerência (ver MGMT_NET)
#
# ATENÇÃO: rode com acesso ao console/KVM disponível. Se errar a porta do SSH,
# você pode se trancar para fora. Ajuste SSH_PORT/MGMT_NET conforme o ambiente.
#
# Uso: sudo ./firewall.sh
# ============================================================================
set -euo pipefail

SSH_PORT="${SSH_PORT:-22}"
# Rede autorizada a consultar o zabbix-agent (porta 10050). Ajuste!
# Ex.: "10.0.0.0/8" ou "192.168.10.0/24". Vazio = libera de qualquer origem.
MGMT_NET="${MGMT_NET:-}"

[[ $EUID -eq 0 ]] || { echo "Rode como root: sudo ./firewall.sh" >&2; exit 1; }

command -v nft >/dev/null 2>&1 || { echo "Instalando nftables..."; apt-get install -y -qq nftables; }
systemctl enable --now nftables

if [[ -n "${MGMT_NET}" ]]; then
  AGENT_RULE="ip saddr ${MGMT_NET} tcp dport 10050 accept"
else
  AGENT_RULE="tcp dport 10050 accept"
fi

RULES=/etc/nftables.conf
cat > "${RULES}" <<EOF
#!/usr/sbin/nft -f
# Gerado por firewall.sh — Zabbix server (Debian 13)
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        iif "lo" accept
        ct state established,related accept
        ct state invalid drop

        # ICMP (ping/diagnóstico)
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        # SSH (gerência)
        tcp dport ${SSH_PORT} accept

        # Frontend web
        tcp dport { 80, 443 } accept

        # Zabbix server (trapper) — recebe dados de proxies/agents ativos
        tcp dport 10051 accept

        # Zabbix agent (passivo) neste host
        ${AGENT_RULE}
    }
    chain forward { type filter hook forward priority 0; policy drop; }
    chain output  { type filter hook output  priority 0; policy accept; }
}
EOF

echo "Aplicando ruleset..."
nft -f "${RULES}"
systemctl restart nftables

echo "OK: firewall aplicado. Regras ativas:"
nft list ruleset | sed 's/^/  /'
echo
echo ">> Confirme que o SSH continua acessível ANTES de encerrar esta sessão."
