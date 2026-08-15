# Guia de Performance e Otimização do Zabbix — Semlimite Telecom

Este guia documenta como identificar gargalos de desempenho no Zabbix e as correções aplicadas
neste ambiente. Cobre o servidor Zabbix, banco de dados MySQL/MariaDB e templates SNMP.

---

## 1. Diagnóstico via Log do Zabbix

### 1.1 Localização e análise rápida

```bash
# Tail do log em tempo real
tail -f /var/log/zabbix/zabbix_server.log

# Contar erros de rede por tipo (últimas 5000 linhas)
tail -n 5000 /var/log/zabbix/zabbix_server.log \
  | grep -oP '(failed|error|slow|timeout|cannot)[^"]*' \
  | sort | uniq -c | sort -rn | head -30

# Hosts com mais "first network error"
tail -n 5000 /var/log/zabbix/zabbix_server.log \
  | grep 'first network error' \
  | grep -oP 'on host "[^"]+"' \
  | sort | uniq -c | sort -rn | head -15

# Quais chaves de item geram mais erros
tail -n 5000 /var/log/zabbix/zabbix_server.log \
  | grep 'first network error' \
  | grep -oP 'item "[^"]+"' \
  | sort | uniq -c | sort -rn | head -20

# Queries SQL lentas no log do Zabbix
tail -n 5000 /var/log/zabbix/zabbix_server.log \
  | grep 'slow query'
```

### 1.2 Padrões de alerta no log

| Mensagem | Causa provável | Seção de correção |
|----------|---------------|-------------------|
| `first network error, wait for 30 seconds` | `UnavailableDelay` alto | §2.2 |
| `SNMP agent item "..." failed: first network error` | Timeout alto ou overload de pollers | §2.1, §2.3 |
| `slow query: 28 sec, "delete from history_uint...` | Buffer pool pequeno ou tabela gigante | §3 |
| `slow query: 28 sec, "update hosts set snmp_disable_until..."` | Contenção de I/O no MySQL | §3 |
| `resuming SNMP agent checks on host "X": connection restored` | Host recuperando — normal se esporádico | — |
| `housekeeper [deleted N hist/trends in X sec, idle for 1h]` | Housekeeper OK; avaliar N e X | §3.3 |

---

## 2. Parâmetros do `zabbix_server.conf`

### 2.1 Timeout — tempo máximo de resposta SNMP

**Arquivo:** `/etc/zabbix/zabbix_server.conf`

```ini
# Padrão Zabbix: 3s. Máximo: 30s.
# Se Timeout=30, cada poll que falha bloqueia o poller por 30s,
# impedindo que ele atenda outros hosts.
Timeout=5
```

**Como identificar o problema:**
```bash
grep '^Timeout' /etc/zabbix/zabbix_server.conf
# Se retornar Timeout=30, reduzir imediatamente.
```

**Impacto de Timeout alto:**
- 120 pollers × 30s bloqueados = todos os pollers presos simultaneamente
- Hosts saudáveis ficam sem coleta enquanto pollers aguardam hosts lentos

### 2.2 UnavailableDelay e UnreachableDelay

```ini
# Tempo de espera após o 1º erro (padrão: 30s)
UnavailableDelay=15

# Tempo de espera entre tentativas quando host está inacessível (padrão: 15s)
UnreachableDelay=5
```

**O que significam no log:**
```
"first network error, wait for 15 seconds"   → UnavailableDelay
"another network error, wait for 5 seconds"  → UnreachableDelay
```

**Como identificar:**
```bash
grep -E '^(Unavailable|Unreachable)Delay' /etc/zabbix/zabbix_server.conf
# UnavailableDelay=120 → poller fica 2 minutos parado após 1 erro
```

### 2.3 StartPollers — número de workers SNMP

```ini
# Padrão: varia. Muitos pollers sobrecarregam dispositivos SNMP.
StartPollers=80
StartPollersUnreachable=50
```

**Como identificar o problema:**
```bash
grep '^StartPollers' /etc/zabbix/zabbix_server.conf

# Ver quantos pollers ativos há no momento
ps aux | grep zabbix_server | grep -c poller
```

Muitos pollers simultâneos consultando o mesmo dispositivo via SNMP podem:
- Sobrecarregar o agente SNMP do equipamento (CPU alta)
- Causar respostas lentas → erros em cascata

### 2.4 MaxHousekeeperDelete — velocidade de limpeza do histórico

```ini
# Padrão: 5000. Máximo por query de DELETE.
# Valor muito baixo → housekeeper não consegue acompanhar a ingestão de dados.
MaxHousekeeperDelete=50000
```

**Como identificar:**
```bash
grep '^MaxHousekeeperDelete' /etc/zabbix/zabbix_server.conf

# Ver quanto o housekeeper deletou e em quanto tempo (última entrada no log)
grep 'housekeeper' /var/log/zabbix/zabbix_server.log | tail -5
# Exemplo: "deleted 1247463 hist/trends in 228 sec, idle for 1h"
# Se "deleted" for << número de itens × dias → o housekeeper está atrasado
```

### 2.5 Aplicando e reiniciando

```bash
# Editar o arquivo
vi /etc/zabbix/zabbix_server.conf

# Verificar as mudanças antes de reiniciar
grep -E '^(Timeout|UnavailableDelay|UnreachableDelay|StartPollers|MaxHousekeeperDelete)' \
  /etc/zabbix/zabbix_server.conf

# Reiniciar
systemctl restart zabbix-server
systemctl status zabbix-server
```

### 2.6 Valores aplicados neste ambiente

| Parâmetro | Antes | Depois | Motivo |
|-----------|-------|--------|--------|
| `Timeout` | 30s | **5s** | Cada poll bloqueava poller por 30s |
| `UnavailableDelay` | 120s | **15s** | Pausa de 2min após 1º erro |
| `UnreachableDelay` | 30s | **5s** | Tempo entre tentativas |
| `StartPollers` | 120 | **80** | Sobrecarga SNMP nos PE routers |
| `MaxHousekeeperDelete` | 10000 | **50000** | Limpeza insuficiente para 369M linhas |

---

## 3. Banco de Dados — MySQL/MariaDB

### 3.1 Diagnosticar tabelas grandes

```sql
-- Tamanho das tabelas de histórico
SELECT table_name,
       ROUND(data_length/1024/1024/1024, 2) AS data_GB,
       ROUND(index_length/1024/1024/1024, 2) AS index_GB,
       table_rows
FROM information_schema.tables
WHERE table_schema = 'zabbix'
  AND table_name IN (
    'history','history_uint','history_str','history_text',
    'history_log','trends','trends_uint','events'
  )
ORDER BY data_length DESC;
```

**Situação encontrada neste ambiente:**

| Tabela | Dados | Índice | Linhas |
|--------|-------|--------|--------|
| history_uint | 76 GB | 28 GB | 369M |
| history | 13 GB | 6 GB | 98M |
| history_text | 6,8 GB | 497 MB | 3,7M |
| trends_uint | 4,1 GB | 0 | 17M |

`history_uint` com 104 GB (dados + índice) e buffer pool de 5,9 GB → 94% das operações
vão ao disco → queries de DELETE e UPDATE levam 28 segundos.

### 3.2 InnoDB Buffer Pool

O buffer pool é o cache principal do InnoDB. Se for menor que as tabelas ativas,
cada operação vai ao disco físico.

```bash
# Ver valor atual
mysql -uzabbix -p zabbix -e 'SHOW VARIABLES LIKE "innodb_buffer_pool_size";'

# Ver RAM disponível
free -h
```

**Regra geral:** Buffer pool = 60–70% da RAM disponível (excluindo uso atual do SO e Zabbix).

```ini
# /etc/my.cnf — servidor com 19GB RAM, ~10GB disponíveis
[mysqld]
innodb_buffer_pool_size = 10240M   # era 5632M
innodb_buffer_pool_instances = 4   # 1 por 2-4GB de buffer pool
innodb_log_file_size = 512M
innodb_flush_log_at_trx_commit = 2  # performance: flush a cada 1s, não por commit
innodb_flush_method = O_DIRECT      # evita double-buffering com OS cache
innodb_file_per_table = ON          # facilita reclaim de espaço após DELETE
```

**Aplicar (requer restart do MariaDB):**
```bash
vi /etc/my.cnf
systemctl restart mariadb
# Verificar
mysql -e 'SHOW VARIABLES LIKE "innodb_buffer_pool_size";'
```

> ⚠️ O restart do MariaDB derruba o Zabbix momentaneamente. Fazer em janela de manutenção.

### 3.3 Housekeeper interno vs particionamento

O housekeeper do Zabbix usa `DELETE ... LIMIT N` para remover histórico antigo.
Em tabelas grandes, cada DELETE pode demorar dezenas de segundos.

**Verificar frequência e volume:**
```bash
grep 'housekeeper' /var/log/zabbix/zabbix_server.log | tail -10
```

**Opção 1 — Aumentar MaxHousekeeperDelete (rápido, sem manutenção):**
```ini
MaxHousekeeperDelete=50000
```

**Opção 2 — Particionamento MySQL (solução definitiva para ambientes grandes):**

Com particionamento por dia/semana, remover histórico antigo é um `ALTER TABLE DROP PARTITION`
(instantâneo) em vez de milhões de DELETEs.

Referência: [zabbix-partitioning-script](https://github.com/zabbix-tools/zabbix-partitioner)

```sql
-- Verificar se as tabelas já têm particionamento
SELECT table_name, partition_name
FROM information_schema.partitions
WHERE table_schema = 'zabbix' AND partition_name IS NOT NULL
LIMIT 10;
```

### 3.4 Itens gerando mais histórico

```sql
-- Top 15 itens com mais linhas em history_uint (query pesada em tabela grande)
SELECT i.key_, h.hostid, COUNT(*) AS rows,
       i.history, i.delay
FROM history_uint h
JOIN items i ON h.itemid = i.itemid
GROUP BY h.itemid
ORDER BY rows DESC
LIMIT 15;
```

---

## 4. Otimização de Templates SNMP

### 4.1 Itens com coleta desnecessariamente frequente

O impacto de um item com delay inadequado:
- **`hwEntityOpticalAlias`** (descrição do módulo óptico): dado estático que raramente muda.
  Coletado a cada 15m → gera 96 coletas/dia por interface × centenas de interfaces = overload.

**Como identificar:**
```bash
# Ver delay dos itens mais problemáticos no log
mysql -uzabbix -pSENHA zabbix -e "
SELECT key_, delay, history, COUNT(*) as hosts
FROM items
WHERE key_ LIKE '%OpticalAlias%' AND flags = 2
GROUP BY key_, delay, history;
"
```

**Regra de delay por tipo de dado:**

| Tipo de dado | Delay recomendado |
|---|---|
| Tráfego (bytes/s, erros) | 1m |
| Status operacional (up/down) | 1m |
| Sinal óptico RX/TX (dBm) | 1m |
| Temperatura | 1m–5m |
| Alias / descrição de interface | 1d |
| Versão de firmware, número de série | 1d–7d |
| Thresholds (limites configurados) | 1h |

### 4.2 Discovery filtrando sub-interfaces indesejadas (ONU)

**Problema:** Templates de OLT descobrem sub-interfaces de ONU (`PON 1/9/6`) junto com
as portas físicas (`PON 1/9`), gerando dezenas de milhares de itens inúteis.

**Como identificar:**
```bash
# Ver quantos itens ifHCInOctets com padrão ONU existem
mysql -uzabbix -pSENHA zabbix -e "
SELECT COUNT(*) FROM items
WHERE key_ REGEXP 'ifHCInOctets\\\\[.*[Pp][Oo][Nn][ _]?[0-9]+/[0-9]+/[0-9]+';
"
```

**Como corrigir (no XML do template):**

Adicionar condição `NOT_MATCHES_REGEX` no filtro da discovery rule:
```xml
<filter>
    <conditions>
        <condition>
            <macro>{#IFNAME}</macro>
            <value>(?i)^\S*pon[ _]?\d+/\d+/\d+</value>
            <operator>NOT_MATCHES_REGEX</operator>
            <formulaid>A</formulaid>
        </condition>
    </conditions>
</filter>
```

> **Atenção:** Na API Zabbix 4.x, o operador `NOT_MATCHES_REGEX` deve ser enviado como
> valor numérico `"9"`, não como string. Ver script `scripts-manutencao/fix_olt_interface_discovery.py`.

### 4.3 Thresholds de temperatura via OID (em vez de valor fixo)

**Problema:** Threshold fixo (ex.: 55°C) dispara alarme em componentes com limite
hardware muito superior (ex.: PSU com Minor=118°C).

**Como identificar:**
```bash
# Ver threshold configurado no equipamento
# Na CLI Huawei:
display temperature

# Via SNMP (hwEntityTemperatureThreshold = OID .12):
snmpwalk -v2c -c COMMUNITY IP 1.3.6.1.4.1.2011.5.25.31.1.1.1.1.12
```

**Solução — usar OID do threshold como item prototype:**

```xml
<!-- Item: temperatura atual -->
<item_prototype>
    <name>Slot - {#BOARD}</name>
    <snmp_oid>1.3.6.1.4.1.2011.5.25.31.1.1.1.1.11.{#SNMPINDEX}</snmp_oid>
    <key>netstream.tempslot[{#SNMPINDEX}]</key>
    <delay>1m</delay>
    <units>C</units>
</item_prototype>

<!-- Item: threshold Minor (hwEntityTemperatureThreshold) -->
<item_prototype>
    <name>Slot - {#BOARD}: Threshold Minor</name>
    <snmp_oid>1.3.6.1.4.1.2011.5.25.31.1.1.1.1.12.{#SNMPINDEX}</snmp_oid>
    <key>netstream.tempslot.threshold[{#SNMPINDEX}]</key>
    <delay>1h</delay>
    <units>C</units>
</item_prototype>
```

**Trigger dinâmico:**
```
Warning:  tempslot.last() >= tempslot.threshold.last()
Critical: tempslot.last() >= tempslot.threshold.last() + 3
```

**OIDs Huawei relevantes (hwEntityStateEntry):**

| OID (sufixo) | Nome | Descrição |
|---|---|---|
| `.11.{index}` | hwEntityTemperature | Temperatura atual (°C) |
| `.12.{index}` | hwEntityTemperatureThreshold | Threshold Minor — usado para alarme |
| `.7.{index}` | hwEntityMemUsage | Uso de memória (%) |
| `.8.{index}` | hwEntityMemUsageThreshold | Threshold de memória |

> **Nota S-series vs NE-series:** OID `.12` funciona em ambas as linhas (S e NE).
> OID `.14` (testado) retorna 0 em switches S-series — não usar.

### 4.4 Filtro de discovery para slots sem sensor de temperatura

Quando a discovery coleta `{#TEMP}` (temperatura atual) junto com `{#BOARD}` (descrição),
adicionar filtro para excluir índices sem sensor (que retornam 0):

```xml
<filter>
    <conditions>
        <condition>
            <macro>{#TEMP}</macro>
            <value>^(-?[1-9][0-9]*)$</value>
            <formulaid>A</formulaid>
        </condition>
    </conditions>
</filter>
```

A regex `^(-?[1-9][0-9]*)$` aceita inteiros não-nulos (positivos ou negativos),
excluindo `0` e strings vazias.

---

## 5. Checklist de Diagnóstico de Performance

```bash
# 1. Parâmetros críticos do servidor
grep -E '^(Timeout|UnavailableDelay|UnreachableDelay|StartPollers|MaxHousekeeperDelete)' \
  /etc/zabbix/zabbix_server.conf

# 2. Tamanho do buffer pool vs tabelas
mysql -uzabbix -p zabbix -e '
SELECT ROUND(SUM(data_length+index_length)/1024/1024/1024,1) AS total_GB
FROM information_schema.tables WHERE table_schema="zabbix";'

mysql -e 'SHOW VARIABLES LIKE "innodb_buffer_pool_size";'

# 3. Erros dominantes no log
tail -n 5000 /var/log/zabbix/zabbix_server.log \
  | grep -oP '(failed|slow query)[^"]*' | sort | uniq -c | sort -rn | head -20

# 4. Housekeeper - está conseguindo limpar?
grep 'housekeeper' /var/log/zabbix/zabbix_server.log | tail -3

# 5. Itens com delay inadequado (OpticalAlias como exemplo)
mysql -uzabbix -p zabbix -e "
SELECT key_, delay, COUNT(*) FROM items
WHERE key_ LIKE '%Alias%' GROUP BY key_, delay ORDER BY COUNT(*) DESC LIMIT 10;"

# 6. Hosts instáveis (mais erros SNMP)
tail -n 5000 /var/log/zabbix/zabbix_server.log \
  | grep 'first network error' \
  | grep -oP 'on host "[^"]+"' \
  | sort | uniq -c | sort -rn
```

---

## 6. Referências Rápidas

| Componente | Arquivo | Parâmetro chave |
|---|---|---|
| Zabbix Server | `/etc/zabbix/zabbix_server.conf` | Timeout, StartPollers, MaxHousekeeperDelete |
| MariaDB | `/etc/my.cnf` | innodb_buffer_pool_size |
| Log Zabbix | `/var/log/zabbix/zabbix_server.log` | — |
| Log MariaDB | `/var/log/mariadb/mariadb.log` | — |
| SSH Servidor | `ssh -p2299 root@177.91.165.47` | — |

---

*Última atualização: 2026-07-24 — aplicado em ambiente Semlimite Telecom*
