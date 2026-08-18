#!/usr/bin/env bash
# ============================================================================
# gerar-senhas.sh — Gera senhas fortes e cria o arquivo .env
# ----------------------------------------------------------------------------
# Cada servidor recebe segredos ÚNICOS. Nada é versionado no Git.
#
# Uso:
#   ./gerar-senhas.sh            # cria .env (recusa se já existir)
#   ./gerar-senhas.sh --force    # sobrescreve o .env (troca TODAS as senhas)
#
# Variáveis opcionais de ambiente (herdadas se já exportadas):
#   ZABBIX_SERVER_NAME, ZABBIX_TIMEZONE, NGINX_LISTEN
# ============================================================================
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${DIR}/.env"
FORCE="${1:-}"

command -v openssl >/dev/null 2>&1 || {
  echo "ERRO: openssl não encontrado. Instale com: sudo apt-get install -y openssl" >&2
  exit 1
}

if [[ -f "${ENV_FILE}" && "${FORCE}" != "--force" ]]; then
  echo "ERRO: ${ENV_FILE} já existe. Use --force para sobrescrever (troca TODAS as senhas)." >&2
  exit 1
fi

# Senha alfanumérica forte (~24 chars). Sem símbolos, para não quebrar em
# sed/URL/psql/PHP durante a automação do install.sh.
gen_pass() { openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 24; }
# PSK: 256 bits em hexadecimal (formato exigido pelo zabbix-agent2).
gen_psk()  { openssl rand -hex 32; }

DB_PASSWORD="$(gen_pass)"
ADMIN_PASSWORD="$(gen_pass)"
AGENT_PSK="$(gen_psk)"

SERVER_NAME="${ZABBIX_SERVER_NAME:-zabbix.exemplo.com.br}"
TIMEZONE="${ZABBIX_TIMEZONE:-America/Sao_Paulo}"
NGINX_LISTEN="${NGINX_LISTEN:-80}"

umask 077
cat > "${ENV_FILE}" <<EOF
# Gerado por gerar-senhas.sh em $(date -u +%Y-%m-%dT%H:%M:%SZ)
# NUNCA faça commit deste arquivo — ele contém segredos.
ZABBIX_DB_HOST=127.0.0.1
ZABBIX_DB_PORT=5432
ZABBIX_DB_NAME=zabbix
ZABBIX_DB_USER=zabbix
ZABBIX_DB_PASSWORD=${DB_PASSWORD}
ZABBIX_ADMIN_PASSWORD=${ADMIN_PASSWORD}
ZABBIX_SERVER_NAME=${SERVER_NAME}
NGINX_LISTEN=${NGINX_LISTEN}
ZABBIX_TIMEZONE=${TIMEZONE}
ZABBIX_AGENT_PSK=${AGENT_PSK}
ZABBIX_AGENT_PSK_IDENTITY=psk-zabbix-server
EOF
chmod 600 "${ENV_FILE}"

echo "OK: ${ENV_FILE} criado (permissão 600)."
echo
echo "  Senha do banco (usuário zabbix) : ${DB_PASSWORD}"
echo "  Senha sugerida do Admin (web)   : ${ADMIN_PASSWORD}"
echo "  PSK do agente (hex)             : ${AGENT_PSK}"
echo
echo ">> Guarde estas senhas em um cofre (Bitwarden/KeePass/Vault) AGORA."
echo ">> Revise ZABBIX_SERVER_NAME em ${ENV_FILE} antes de rodar ./install.sh."
