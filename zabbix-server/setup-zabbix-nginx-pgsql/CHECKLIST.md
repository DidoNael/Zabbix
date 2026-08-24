# Checklist de validação — pós-instalação

Marque cada item após instalar. Comandos rodam no próprio servidor.

## Serviços ativos
- [ ] `systemctl is-active zabbix-server zabbix-agent2 nginx postgresql` → tudo `active`
- [ ] PHP-FPM ativo: `systemctl is-active "php$(ls /etc/php | sort -V | tail -1)-fpm"`

## Banco de dados
- [ ] Conecta com a senha do `.env`:
      `PGPASSWORD=... psql -h 127.0.0.1 -U zabbix -d zabbix -c '\dt' | head`
- [ ] Schema importado (existe a tabela `users`).

## Zabbix server
- [ ] `tail -n 30 /var/log/zabbix/zabbix_server.log` sem erros de conexão com o DB
- [ ] Porta do trapper escutando: `ss -lntp | grep 10051`
- [ ] Log mostra `server #0 started` / housekeeper ativo

## Frontend (Nginx + PHP)
- [ ] `nginx -t` → OK
- [ ] `curl -sI http://127.0.0.1/ | head -1` → `HTTP/1.1 200` (ou 302 p/ setup)
- [ ] Login no navegador com `Admin` / `zabbix` funciona
- [ ] Rodapé sem alerta "Zabbix server is not running"

## Segurança
- [ ] **Senha do Admin trocada** (não é mais `zabbix`)
- [ ] Firewall aplicado: `nft list ruleset | grep -E '10051|dport'`
- [ ] SSH ainda acessível após o firewall
- [ ] HTTPS/TLS configurado (produção)
- [ ] PostgreSQL só em `localhost` (`ss -lntp | grep 5432` → apenas 127.0.0.1)
- [ ] `.env` com permissão `600` e fora do Git (`git status` limpo)

## Macros globais obrigatórias

Configurar em **Administration → General → Macros** antes de importar os templates OLT.
Macros globais sobrevivem a reimports de template — nunca são resetadas.

- [ ] `{$ONU_DEDICADO_FILTER.NETSTREAM}` = `^(dedicado-|\d)`
  - Filtra ONUs dedicadas na discovery. Sem essa macro, o template usa o fallback `^dedicado-`
    (seguro, mas não captura clientes com ID numérico na descrição da ONU).
  - **Não configurar** = residenciais com descrição começando por número entram na discovery.
  - Ajuste o regex conforme o padrão de nomes da operadora. Exemplos:
    - Só prefixo dedicado: `^dedicado-`
    - Prefixo dedicado ou ID numérico: `^(dedicado-|\d)`
    - Prefixo dedicado ou CID específico: `^(dedicado-|CID\d)`

## Backup
- [ ] `sudo ./backup/backup-zabbix-db.sh` gera o `.dump` sem erro
- [ ] Entrada no cron criada (backup diário)
- [ ] Restauração testada em base temporária (`pg_restore` para `zabbix_restore`)
