#!/usr/bin/env bash
# ============================================================================
# backup-zabbix-db.sh — Backup do banco PostgreSQL do Zabbix
# ----------------------------------------------------------------------------
# Faz pg_dump no formato custom (-Fc, comprimido) com retenção configurável.
# Lê as credenciais do .env (um nível acima) ou de /etc/zabbix/zabbix_server.conf.
#
# Uso manual:  sudo ./backup-zabbix-db.sh
# Cron diário (03:15):
#   15 3 * * * root /caminho/backup/backup-zabbix-db.sh >> /var/log/zabbix-backup.log 2>&1
# ============================================================================
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${BACKUP_DIR:-${DIR}}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

DB_NAME="zabbix"; DB_USER="zabbix"; DB_HOST="127.0.0.1"; DB_PORT="5432"; DB_PASS=""

# 1) tenta o .env do projeto
if [[ -f "${DIR}/../.env" ]]; then
  # shellcheck disable=SC1091
  source "${DIR}/../.env"
  DB_NAME="${ZABBIX_DB_NAME:-$DB_NAME}"; DB_USER="${ZABBIX_DB_USER:-$DB_USER}"
  DB_HOST="${ZABBIX_DB_HOST:-$DB_HOST}"; DB_PORT="${ZABBIX_DB_PORT:-$DB_PORT}"
  DB_PASS="${ZABBIX_DB_PASSWORD:-}"
fi
# 2) fallback: lê do zabbix_server.conf (requer root)
if [[ -z "${DB_PASS}" && -r /etc/zabbix/zabbix_server.conf ]]; then
  DB_PASS="$(grep -E '^DBPassword=' /etc/zabbix/zabbix_server.conf | cut -d= -f2-)"
fi
[[ -n "${DB_PASS}" ]] || { echo "ERRO: senha do banco não encontrada (.env ou zabbix_server.conf)." >&2; exit 1; }

mkdir -p "${DEST}"
STAMP="$(date +%Y%m%d-%H%M%S)"
FILE="${DEST}/zabbix-${STAMP}.dump"

echo "[$(date '+%F %T')] Iniciando backup de '${DB_NAME}' -> ${FILE}"
export PGPASSWORD="${DB_PASS}"
pg_dump -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -Fc -f "${FILE}" "${DB_NAME}"
unset PGPASSWORD
chmod 600 "${FILE}"

echo "[$(date '+%F %T')] OK ($(du -h "${FILE}" | cut -f1)). Aplicando retenção de ${RETENTION_DAYS} dias."
find "${DEST}" -maxdepth 1 -name 'zabbix-*.dump' -type f -mtime "+${RETENTION_DAYS}" -print -delete

# Restauração (referência):
#   createdb -O zabbix zabbix_restore
#   pg_restore -h 127.0.0.1 -U zabbix -d zabbix_restore /caminho/zabbix-AAAAMMDD-HHMMSS.dump
