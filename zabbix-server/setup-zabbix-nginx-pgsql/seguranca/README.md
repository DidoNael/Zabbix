# Segurança / Hardening — Zabbix Server (Debian 13)

Passos **obrigatórios** após a instalação. Ordem recomendada: firewall → TLS → troca de senha do Admin → PostgreSQL → agente.

---

## 1. Firewall (nftables)

O Debian 13 usa `nftables` por padrão. Rode o script fornecido:

```bash
# Ajuste a rede de gerência que pode consultar o agente (porta 10050):
sudo MGMT_NET="10.0.0.0/8" ./firewall.sh
```

Portas liberadas: `22` (SSH), `80/443` (web), `10051` (server/trapper) e `10050` (agente, restrito a `MGMT_NET`).

> **Atenção:** tenha acesso ao console/KVM antes de aplicar. Se o SSH usa porta customizada, exporte `SSH_PORT` antes de rodar.

---

## 2. HTTPS / TLS

Nunca exponha o frontend em HTTP puro na internet. Duas opções:

### Opção A — Let's Encrypt (domínio público válido)

```bash
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d zabbix.exemplo.com.br --redirect --agree-tos -m voce@exemplo.com.br
```

O `certbot` ajusta o Nginx e cria a renovação automática (`systemctl status certbot.timer`).

### Opção B — Certificado self-signed (rede interna)

```bash
sudo install -d -m 750 /etc/ssl/zabbix
sudo openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
  -keyout /etc/ssl/zabbix/privkey.pem \
  -out    /etc/ssl/zabbix/fullchain.pem \
  -subj "/CN=zabbix.exemplo.com.br"
sudo chmod 600 /etc/ssl/zabbix/privkey.pem
```

Depois habilite o bloco `server { listen 443 ssl; ... }` — veja o exemplo comentado em
[`../config/nginx-zabbix.conf`](../config/nginx-zabbix.conf) — e force o redirect `80 → 443`.

---

## 3. Trocar a senha do usuário Admin

O Zabbix cria o usuário padrão **`Admin`** / **`zabbix`**. Troque no primeiro acesso:
`Users → Users → Admin → Change password` (use o valor de `ZABBIX_ADMIN_PASSWORD` do `.env`).

Recomendado ainda: criar um usuário nominal por operador e habilitar MFA (`Users → Authentication → MFA`).

---

## 4. PostgreSQL

- **Escute apenas localmente** (o banco fica no mesmo host):
  ```
  # /etc/postgresql/<versao>/main/postgresql.conf
  listen_addresses = 'localhost'
  ```
- **Autenticação forte** — garanta `scram-sha-256` no `pg_hba.conf`:
  ```
  # /etc/postgresql/<versao>/main/pg_hba.conf
  host    zabbix    zabbix    127.0.0.1/32    scram-sha-256
  ```
- Recarregue: `sudo systemctl reload postgresql`.
- Não abra a porta `5432` no firewall.

Tuning e mais detalhes em [`../config/postgresql-tuning.md`](../config/postgresql-tuning.md).

---

## 5. Comunicação server ↔ agent com PSK

O `gerar-senhas.sh` já criou `ZABBIX_AGENT_PSK` no `.env`. Para cifrar o agente local:

```bash
source .env
echo -n "${ZABBIX_AGENT_PSK}" | sudo tee /etc/zabbix/zabbix_agent2.psk >/dev/null
sudo chown zabbix:zabbix /etc/zabbix/zabbix_agent2.psk
sudo chmod 600 /etc/zabbix/zabbix_agent2.psk
```

No `/etc/zabbix/zabbix_agent2.conf`:
```
TLSConnect=psk
TLSAccept=psk
TLSPSKIdentity=psk-zabbix-server
TLSPSKFile=/etc/zabbix/zabbix_agent2.psk
```
Reinicie: `sudo systemctl restart zabbix-agent2`. No frontend, configure o mesmo PSK no host (`Encryption`).

---

## 6. Atualizações automáticas de segurança

```bash
sudo apt-get install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

---

## 7. Higiene adicional

- Remova as senhas do console/log após o primeiro boot (o `.env` fica com permissão `600`).
- Faça backup do banco — ver [`../backup/backup-zabbix-db.sh`](../backup/backup-zabbix-db.sh).
- Mantenha o SSH com chave (desabilite senha) e, de preferência, atrás de VPN/bastion.
