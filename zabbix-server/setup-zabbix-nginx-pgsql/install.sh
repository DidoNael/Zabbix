#!/usr/bin/env bash
# ============================================================================
# install.sh — Instalação automatizada Zabbix 7.0 + Nginx + PostgreSQL
# Alvo: Debian 13 (Trixie). Idempotente e não-interativo.
# ----------------------------------------------------------------------------
# Pré-requisito: rodar ./gerar-senhas.sh antes (cria o .env com as senhas).
# Uso: sudo ./install.sh
#
# Pode ser reexecutado com segurança: cada etapa verifica o estado antes de agir.
# ============================================================================
set -euo pipefail

ZBX_MAJOR="7.0"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${DIR}/.env"

log()  { echo -e "\n\033[1;32m[+] $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }
die()  { echo -e "\033[1;31m[x] $*\033[0m" >&2; exit 1; }

# Executa psql como superusuário postgres sem depender de sudo (usa runuser).
psql_admin() { runuser -u postgres -- psql "$@"; }

# set_conf CHAVE VALOR ARQUIVO — define/atualiza "CHAVE=VALOR" (descomenta se preciso).
set_conf() {
  local key="$1" val="$2" file="$3"
  if grep -qE "^[#[:space:]]*${key}=" "${file}"; then
    sed -i -E "s|^[#[:space:]]*${key}=.*|${key}=${val}|" "${file}"
  else
    echo "${key}=${val}" >> "${file}"
  fi
}

# --- 0. Pré-checagens -------------------------------------------------------
[[ $EUID -eq 0 ]] || die "Rode como root:  sudo ./install.sh"
[[ -f "${ENV_FILE}" ]] || die "Arquivo .env não encontrado. Rode ./gerar-senhas.sh primeiro."

# shellcheck disable=SC1090
set -a; source "${ENV_FILE}"; set +a
: "${ZABBIX_DB_PASSWORD:?Defina ZABBIX_DB_PASSWORD no .env (rode ./gerar-senhas.sh)}"
: "${ZABBIX_DB_NAME:=zabbix}"
: "${ZABBIX_DB_USER:=zabbix}"
: "${ZABBIX_SERVER_NAME:=zabbix.exemplo.com.br}"
: "${ZABBIX_TIMEZONE:=America/Sao_Paulo}"
: "${NGINX_LISTEN:=80}"

# shellcheck disable=SC1091
source /etc/os-release
DEB_VER="${VERSION_ID:-13}"
[[ "${ID:-}" == "debian" ]] || warn "Distribuição '${ID:-desconhecida}' não é Debian — os comandos podem divergir."
export DEBIAN_FRONTEND=noninteractive

log "Ajustando timezone do sistema para ${ZABBIX_TIMEZONE}..."
timedatectl set-timezone "${ZABBIX_TIMEZONE}" 2>/dev/null || warn "Não foi possível ajustar o timezone (seguindo)."

log "Instalando utilitários base..."
apt-get update -qq
apt-get install -y -qq wget gnupg2 ca-certificates openssl >/dev/null

# --- 1. PostgreSQL ----------------------------------------------------------
log "Instalando PostgreSQL..."
apt-get install -y -qq postgresql postgresql-contrib >/dev/null
systemctl enable --now postgresql

if ! psql_admin -tAc "SELECT 1 FROM pg_roles WHERE rolname='${ZABBIX_DB_USER}'" | grep -q 1; then
  log "Criando role '${ZABBIX_DB_USER}'..."
  psql_admin -v ON_ERROR_STOP=1 -c "CREATE ROLE ${ZABBIX_DB_USER} LOGIN PASSWORD '${ZABBIX_DB_PASSWORD}';"
else
  warn "Role '${ZABBIX_DB_USER}' já existe — atualizando a senha para o valor do .env."
  psql_admin -v ON_ERROR_STOP=1 -c "ALTER ROLE ${ZABBIX_DB_USER} WITH PASSWORD '${ZABBIX_DB_PASSWORD}';"
fi

if ! psql_admin -tAc "SELECT 1 FROM pg_database WHERE datname='${ZABBIX_DB_NAME}'" | grep -q 1; then
  log "Criando database '${ZABBIX_DB_NAME}'..."
  psql_admin -v ON_ERROR_STOP=1 -c \
    "CREATE DATABASE ${ZABBIX_DB_NAME} OWNER ${ZABBIX_DB_USER} ENCODING 'UTF8' TEMPLATE template0;"
fi

# --- 2. Repositório e pacotes Zabbix ---------------------------------------
if ! dpkg -s zabbix-release >/dev/null 2>&1; then
  log "Adicionando repositório oficial Zabbix ${ZBX_MAJOR} (Debian ${DEB_VER})..."
  TMPDEB="$(mktemp --suffix=.deb)"
  wget -qO "${TMPDEB}" \
    "https://repo.zabbix.com/zabbix/${ZBX_MAJOR}/debian/pool/main/z/zabbix-release/zabbix-release_latest_${ZBX_MAJOR}+debian${DEB_VER}_all.deb"
  dpkg -i "${TMPDEB}" >/dev/null
  rm -f "${TMPDEB}"
  apt-get update -qq
fi

log "Instalando pacotes Zabbix (server, frontend, nginx, sql-scripts, agent2)..."
apt-get install -y -qq \
  zabbix-server-pgsql \
  zabbix-frontend-php \
  zabbix-nginx-conf \
  zabbix-sql-scripts \
  zabbix-agent2 >/dev/null

# --- 3. Importar schema (idempotente) --------------------------------------
export PGPASSWORD="${ZABBIX_DB_PASSWORD}"
SCHEMA_TABLE="$(psql -h 127.0.0.1 -U "${ZABBIX_DB_USER}" -d "${ZABBIX_DB_NAME}" -tAc \
  "SELECT to_regclass('public.users')" 2>/dev/null || true)"
if [[ -z "${SCHEMA_TABLE}" ]]; then
  log "Importando schema inicial do Zabbix (pode levar 1-2 min)..."
  zcat /usr/share/zabbix-sql-scripts/postgresql/server.sql.gz | \
    psql -q -h 127.0.0.1 -U "${ZABBIX_DB_USER}" -d "${ZABBIX_DB_NAME}"
else
  warn "Schema já importado (tabela 'users' existe) — pulando."
fi
unset PGPASSWORD

# --- 4. Configurar zabbix_server.conf --------------------------------------
log "Configurando /etc/zabbix/zabbix_server.conf..."
ZSC=/etc/zabbix/zabbix_server.conf
set_conf DBHost     "127.0.0.1"             "${ZSC}"
set_conf DBName     "${ZABBIX_DB_NAME}"     "${ZSC}"
set_conf DBUser     "${ZABBIX_DB_USER}"     "${ZSC}"
set_conf DBPassword "${ZABBIX_DB_PASSWORD}" "${ZSC}"
chown root:zabbix "${ZSC}" 2>/dev/null || true
chmod 640 "${ZSC}"

# --- 5. Configuração web do frontend (dispensa o wizard) -------------------
WEBCONF=/etc/zabbix/web/zabbix.conf.php
if [[ ! -f "${WEBCONF}" ]]; then
  log "Gerando configuração web do frontend (dispensa o assistente)..."
  install -d -m 755 /etc/zabbix/web
  cat > "${WEBCONF}" <<PHP
<?php
// Zabbix GUI configuration file — gerado pelo install.sh.
\$DB['TYPE']              = 'POSTGRESQL';
\$DB['SERVER']            = '127.0.0.1';
\$DB['PORT']              = '5432';
\$DB['DATABASE']          = '${ZABBIX_DB_NAME}';
\$DB['USER']              = '${ZABBIX_DB_USER}';
\$DB['PASSWORD']          = '${ZABBIX_DB_PASSWORD}';
\$DB['SCHEMA']            = '';
\$DB['ENCRYPTION']        = false;
\$DB['KEY_FILE']          = '';
\$DB['CERT_FILE']         = '';
\$DB['CA_FILE']           = '';
\$DB['VERIFY_HOST']       = false;
\$DB['CIPHER_LIST']       = '';
\$DB['VAULT']             = '';
\$DB['VAULT_URL']         = '';
\$DB['VAULT_DB_PATH']     = '';
\$DB['VAULT_TOKEN']       = '';
\$DB['VAULT_CERT_FILE']   = '';
\$DB['VAULT_KEY_FILE']    = '';
\$DB['DOUBLE_IEEE754']    = true;
\$ZBX_SERVER              = '127.0.0.1';
\$ZBX_SERVER_PORT         = '10051';
\$ZBX_SERVER_NAME         = '${ZABBIX_SERVER_NAME}';
\$IMAGE_FORMAT_DEFAULT    = IMAGE_FORMAT_PNG;
PHP
  chown root:www-data "${WEBCONF}"
  chmod 640 "${WEBCONF}"
else
  warn "Config web já existe (${WEBCONF}) — mantendo. Apague-a para regerar via wizard."
fi

# --- 6. Nginx --------------------------------------------------------------
log "Configurando Nginx (/etc/zabbix/nginx.conf)..."
NGX=/etc/zabbix/nginx.conf
# As diretivas vêm comentadas no pacote (ex.: "#        listen  8080;").
# Descomenta e reaplica com indentação padrão do bloco (8 espaços).
sed -i -E "s|^[[:space:]]*#?[[:space:]]*listen[[:space:]]+[0-9]+;|        listen          ${NGINX_LISTEN};|" "${NGX}"
sed -i -E "s|^[[:space:]]*#?[[:space:]]*server_name[[:space:]]+[^;]*;|        server_name     ${ZABBIX_SERVER_NAME};|" "${NGX}"
# Servidor dedicado ao Zabbix: remove o site default para não conflitar na porta.
rm -f /etc/nginx/sites-enabled/default

# --- 7. PHP-FPM (timezone) -------------------------------------------------
log "Configurando PHP-FPM (timezone)..."
PFC=/etc/zabbix/php-fpm.conf
# O pacote NÃO traz a linha date.timezone — adiciona se ausente, senão substitui.
if grep -qE '^[;#[:space:]]*php_value\[date\.timezone\]' "${PFC}"; then
  sed -i -E "s|^[;#[:space:]]*php_value\[date\.timezone\][[:space:]]*=.*|php_value[date.timezone] = ${ZABBIX_TIMEZONE}|" "${PFC}"
else
  printf 'php_value[date.timezone] = %s\n' "${ZABBIX_TIMEZONE}" >> "${PFC}"
fi

# --- 8. Detectar serviço PHP-FPM e subir tudo ------------------------------
PHP_VER="$(ls /etc/php 2>/dev/null | sort -V | tail -1 || true)"
PHP_FPM_SVC="php${PHP_VER}-fpm"
if [[ -z "${PHP_VER}" ]] || ! systemctl list-unit-files "${PHP_FPM_SVC}.service" >/dev/null 2>&1; then
  PHP_FPM_SVC="$(systemctl list-unit-files --type=service 2>/dev/null \
    | grep -oE 'php[0-9.]+-fpm\.service' | head -1 | sed 's/\.service//')"
fi
[[ -n "${PHP_FPM_SVC}" ]] || die "Não encontrei o serviço php-fpm."

log "Validando a configuração do Nginx..."
nginx -t

log "Habilitando e (re)iniciando serviços (php-fpm: ${PHP_FPM_SVC})..."
systemctl enable zabbix-server zabbix-agent2 nginx "${PHP_FPM_SVC}" >/dev/null 2>&1 || true
systemctl restart zabbix-server zabbix-agent2 nginx "${PHP_FPM_SVC}"

# --- 9. Resumo -------------------------------------------------------------
IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
log "Instalação concluída."
cat <<EOF

  Frontend : http://${IP:-<IP-do-servidor>}/   (server_name: ${ZABBIX_SERVER_NAME})
  Login    : Admin / zabbix   <<< TROQUE a senha no primeiro acesso!
             Senha sugerida (ZABBIX_ADMIN_PASSWORD) está no arquivo .env.

  Próximos passos de segurança (ver seguranca/README.md):
    1) sudo ./seguranca/firewall.sh        # firewall nftables
    2) Configurar HTTPS/TLS                 # Let's Encrypt ou self-signed
    3) Trocar a senha do usuário Admin no frontend
    4) Conferir:  tail -n 30 /var/log/zabbix/zabbix_server.log

  Valide a instalação com o CHECKLIST.md.

EOF
