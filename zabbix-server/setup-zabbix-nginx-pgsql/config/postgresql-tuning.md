# PostgreSQL — Tuning para Zabbix

Valores de partida para o PostgreSQL (Debian 13 traz PostgreSQL 17) num servidor
Zabbix dedicado. Ajuste conforme a RAM e a carga (NVPS). Arquivo:
`/etc/postgresql/<versao>/main/postgresql.conf`.

> Ponto de partida por RAM total do host. Reinicie o PostgreSQL após alterar
> `shared_buffers`/`max_connections`: `sudo systemctl restart postgresql`.

| Parâmetro              | 4 GB RAM | 8 GB RAM | 16 GB RAM | Observação                              |
|------------------------|----------|----------|-----------|-----------------------------------------|
| `shared_buffers`       | 1GB      | 2GB      | 4GB       | ~25% da RAM                             |
| `effective_cache_size` | 2GB      | 6GB      | 12GB      | ~50-75% da RAM (estimativa p/ o planner) |
| `work_mem`             | 16MB     | 32MB     | 64MB      | por operação de sort/hash               |
| `maintenance_work_mem` | 256MB    | 512MB    | 1GB       | VACUUM/CREATE INDEX                     |
| `max_connections`      | 100      | 150      | 200       | ≥ StartPollers + frontend + folga        |
| `wal_buffers`          | 16MB     | 16MB     | 32MB      |                                         |
| `checkpoint_completion_target` | 0.9 | 0.9   | 0.9       | suaviza I/O de checkpoint               |
| `random_page_cost`     | 1.1      | 1.1      | 1.1       | use 1.1 em disco SSD/NVMe               |

Exemplo (host de 8 GB):

```conf
# /etc/postgresql/17/main/postgresql.conf
listen_addresses = 'localhost'
shared_buffers = 2GB
effective_cache_size = 6GB
work_mem = 32MB
maintenance_work_mem = 512MB
max_connections = 150
wal_buffers = 16MB
checkpoint_completion_target = 0.9
random_page_cost = 1.1
```

## Segurança de acesso (`pg_hba.conf`)

```conf
# /etc/postgresql/17/main/pg_hba.conf
local   all         postgres                       peer
host    zabbix      zabbix        127.0.0.1/32     scram-sha-256
host    zabbix      zabbix        ::1/128          scram-sha-256
```

Recarregue sem downtime: `sudo systemctl reload postgresql`.

## Housekeeping / particionamento

Para servidores com muitos itens, avalie **TimescaleDB** para as tabelas de histórico/tendências
(reduz drasticamente o tempo de housekeeping). Configure em
`Administration → Housekeeping` no frontend e ajuste os períodos de retenção.

## Referência

Guia de tuning geral do servidor Zabbix (server + cache + pollers) neste repositório:
[`../../docs/PERFORMANCE_TUNING.md`](../../docs/PERFORMANCE_TUNING.md).
