# Instalação padrão — Zabbix 7.0 + Nginx + PostgreSQL (Debian 13)

Modelo **replicável** para subir um servidor Zabbix novo, com senhas fortes e boas práticas de
segurança. Serve de padrão para todos os próximos servidores.

- **SO:** Debian 13 (Trixie) · **Zabbix:** 7.0 LTS · **Web:** Nginx + PHP-FPM · **Banco:** PostgreSQL (local)
- **Senhas:** geradas por script, **únicas por servidor**, nunca versionadas (repositório é público)

> Três formas de instalar: **(A) automatizada** com `install.sh`, **(B) manual** passo a passo, ou
> **(C) cloud-init** (VM provisionada no 1º boot). Todas usam os mesmos scripts.

---

## Sumário

- [Arquitetura](#arquitetura)
- [Pré-requisitos](#pré-requisitos)
- [Estrutura dos arquivos](#estrutura-dos-arquivos)
- [Caminho A — Instalação automatizada](#caminho-a--instalação-automatizada-recomendado)
- [Caminho B — Passo a passo manual](#caminho-b--passo-a-passo-manual)
- [Caminho C — cloud-init (VM)](#caminho-c--cloud-init-vm)
- [Segurança (obrigatório)](#segurança-obrigatório)
- [Backup](#backup)
- [Validação](#validação)
- [Troubleshooting](#troubleshooting)

---

## Arquitetura

```
                 ┌──────────────────────── servidor Debian 13 ────────────────────────┐
   navegador ───▶│  Nginx  ─(fastcgi)─▶  PHP-FPM (frontend Zabbix)  ──┐                │
                 │                                                     ├──▶ PostgreSQL │
   agents/proxy ─▶│  zabbix-server (10051) ─────────────────────────────┘  (127.0.0.1) │
                 │  zabbix-agent2 (monitora o próprio host)                            │
                 └─────────────────────────────────────────────────────────────────────┘
```

Tudo em um único host: banco local em `127.0.0.1`, frontend PHP servido pelo Nginx e o
`zabbix-server` conversando com o PostgreSQL.

---

## Pré-requisitos

- Debian 13 (Trixie) recém-instalado, com acesso `root`/`sudo`.
- Mínimo sugerido: **2 vCPU / 4 GB RAM / 20 GB disco** (ajuste ao volume de monitoramento).
- Definir hostname/FQDN e ter saída para a internet (repositórios `apt` e `repo.zabbix.com`).
- `openssl`, `git` e `wget` (o `install.sh` instala o que faltar).

---

## Estrutura dos arquivos

```
setup-zabbix-nginx-pgsql/
├── README.md                 ← este guia
├── install.sh                ← instalação automatizada, idempotente
├── gerar-senhas.sh           ← gera .env com senhas fortes
├── .env.example              ← referência das variáveis
├── .gitignore                ← protege .env, chaves e dumps
├── config/
│   ├── nginx-zabbix.conf      ← server block de referência (com TLS comentado)
│   ├── php-fpm-zabbix.conf    ← pool PHP-FPM (requisitos mínimos)
│   └── postgresql-tuning.md   ← tuning + pg_hba
├── seguranca/
│   ├── README.md              ← hardening: firewall, TLS, PSK, atualizações
│   └── firewall.sh            ← regras nftables
├── backup/
│   └── backup-zabbix-db.sh    ← pg_dump com retenção
├── cloud-init/
│   ├── user-data / meta-data  ← provisionamento de VM no 1º boot
│   └── README.md              ← uso em Proxmox/nuvem/NoCloud
└── CHECKLIST.md               ← validação pós-instalação
```

---

## Caminho A — Instalação automatizada (recomendado)

```bash
# 1) Obtenha os arquivos no servidor
sudo apt-get update && sudo apt-get install -y git
git clone --depth 1 https://github.com/DidoNael/Zabbix.git
cd Zabbix/zabbix-server/setup-zabbix-nginx-pgsql

# 2) Gere as senhas fortes (cria o .env). Anote as senhas exibidas!
chmod +x *.sh seguranca/*.sh backup/*.sh
export ZABBIX_SERVER_NAME="zabbix.suaempresa.com.br"   # opcional; ajuste o FQDN
./gerar-senhas.sh

# 3) (Opcional) revise o .env
nano .env

# 4) Instale tudo
sudo ./install.sh
```

Ao final, acesse `http://<IP>/`, faça login com **`Admin` / `zabbix`** e siga direto para a
[seção de Segurança](#segurança-obrigatório). O `install.sh` já cria a config web do frontend —
**não é preciso rodar o assistente**.

> O `install.sh` é **idempotente**: se algo falhar no meio, corrija e rode de novo sem quebrar o que já foi feito.

---

## Caminho B — Passo a passo manual

Para entender cada etapa (ou instalar sem os scripts). Rode como `root`.

### 1. Sistema base

```bash
apt update && apt full-upgrade -y
timedatectl set-timezone America/Sao_Paulo
hostnamectl set-hostname zabbix.suaempresa.com.br
apt install -y wget gnupg2 ca-certificates openssl
```

### 2. PostgreSQL

```bash
apt install -y postgresql postgresql-contrib
systemctl enable --now postgresql

# defina uma senha forte (ex.: openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 24)
DBPASS='COLE_UMA_SENHA_FORTE_AQUI'
runuser -u postgres -- psql -c "CREATE ROLE zabbix LOGIN PASSWORD '${DBPASS}';"
runuser -u postgres -- psql -c "CREATE DATABASE zabbix OWNER zabbix ENCODING 'UTF8' TEMPLATE template0;"
```

### 3. Repositório e pacotes Zabbix 7.0

```bash
wget https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_latest_7.0+debian13_all.deb
dpkg -i zabbix-release_latest_7.0+debian13_all.deb
apt update
apt install -y zabbix-server-pgsql zabbix-frontend-php zabbix-nginx-conf zabbix-sql-scripts zabbix-agent2
```

### 4. Importar o schema inicial

```bash
export PGPASSWORD="${DBPASS}"
zcat /usr/share/zabbix-sql-scripts/postgresql/server.sql.gz | psql -h 127.0.0.1 -U zabbix -d zabbix
unset PGPASSWORD
```

### 5. Configurar o `zabbix-server`

```bash
# /etc/zabbix/zabbix_server.conf
sed -i "s|^# *DBHost=.*|DBHost=127.0.0.1|"        /etc/zabbix/zabbix_server.conf
sed -i "s|^# *DBPassword=.*|DBPassword=${DBPASS}|" /etc/zabbix/zabbix_server.conf
chown root:zabbix /etc/zabbix/zabbix_server.conf && chmod 640 /etc/zabbix/zabbix_server.conf
```

### 6. Configurar o Nginx

Edite `/etc/zabbix/nginx.conf`, descomente e ajuste:

```nginx
listen          80;
server_name     zabbix.suaempresa.com.br;
```

Servidor dedicado ao Zabbix? Remova o site default para evitar conflito na porta 80:

```bash
rm -f /etc/nginx/sites-enabled/default
```

### 7. Configurar o PHP-FPM

Em `/etc/zabbix/php-fpm.conf`, ajuste o fuso:

```ini
php_value[date.timezone] = America/Sao_Paulo
```

### 8. Subir os serviços

```bash
PHP_FPM="php$(ls /etc/php | sort -V | tail -1)-fpm"   # ex.: php8.4-fpm no Debian 13
nginx -t
systemctl restart zabbix-server zabbix-agent2 nginx "${PHP_FPM}"
systemctl enable  zabbix-server zabbix-agent2 nginx "${PHP_FPM}"
```

### 9. Frontend

Acesse `http://<IP>/`. Se você **não** pré-criou `/etc/zabbix/web/zabbix.conf.php`, o assistente web
abre — informe DB `127.0.0.1`, base/usuário `zabbix` e a senha `${DBPASS}`. Login inicial: `Admin` / `zabbix`.

---

## Caminho C — cloud-init (VM)

Provisiona uma VM Debian 13 com tudo pronto no primeiro boot, reutilizando os mesmos scripts.
Passo a passo (Proxmox, NoCloud, nuvem) em [`cloud-init/README.md`](cloud-init/README.md).

---

## Segurança (obrigatório)

Não pare no login. Siga [`seguranca/README.md`](seguranca/README.md):

1. **Firewall** — `sudo MGMT_NET="10.0.0.0/8" ./seguranca/firewall.sh`
2. **HTTPS/TLS** — Let's Encrypt (`certbot`) ou certificado self-signed
3. **Trocar a senha do `Admin`** no frontend (use `ZABBIX_ADMIN_PASSWORD` do `.env`)
4. **PostgreSQL** só em `localhost` + `scram-sha-256`
5. **PSK** entre server e agent2
6. **`unattended-upgrades`** para patches de segurança

---

## Backup

```bash
sudo ./backup/backup-zabbix-db.sh                 # gera .dump comprimido
# Cron diário às 03:15:
echo '15 3 * * * root /caminho/backup/backup-zabbix-db.sh >> /var/log/zabbix-backup.log 2>&1' \
  | sudo tee /etc/cron.d/zabbix-backup
```

---

## Validação

Rode o [`CHECKLIST.md`](CHECKLIST.md). Verificação rápida:

```bash
systemctl is-active zabbix-server zabbix-agent2 nginx postgresql
tail -n 20 /var/log/zabbix/zabbix_server.log
curl -sI http://127.0.0.1/ | head -1
```

---

## Troubleshooting

| Sintoma | Causa provável | Correção |
|---|---|---|
| Rodapé "Zabbix server is not running" | `zabbix-server` parado ou `$ZBX_SERVER` errado no `zabbix.conf.php` | `systemctl status zabbix-server`; conferir `/etc/zabbix/web/zabbix.conf.php` |
| Log: `database is down` / auth falha | senha do `.env` ≠ senha da role no PostgreSQL | rerodar `install.sh` (ajusta a senha) ou `ALTER ROLE zabbix WITH PASSWORD '...'` |
| Frontend abre "Welcome to nginx" | site default ativo na porta 80 | `rm -f /etc/nginx/sites-enabled/default && systemctl reload nginx` |
| Erro de fuso no frontend | `date.timezone` vazio no PHP-FPM | ajustar `/etc/zabbix/php-fpm.conf` e reiniciar o php-fpm |
| `502 Bad Gateway` | socket PHP-FPM ausente | conferir `listen` do pool = `fastcgi_pass` do Nginx (`/run/php/zabbix.sock`) |
| `zcat: not found` no import | `gzip` ausente | `apt install -y gzip` |

Logs úteis: `/var/log/zabbix/zabbix_server.log`, `/var/log/nginx/error.log`,
`journalctl -u zabbix-server -e`.

---

## Convenções deste padrão

- Toda senha vem do `gerar-senhas.sh`; **nada de segredo no Git**.
- Senhas alfanuméricas (sem símbolos) para não quebrar a automação (`sed`/`psql`/PHP).
- Scripts idempotentes: reexecutar é seguro.
- Um servidor = um `.env` = segredos únicos.
