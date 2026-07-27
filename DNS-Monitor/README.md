# Template DNS Monitor - Netstream

Monitora servidores DNS via **DIG** e **NSLOOKUP** com descoberta automática (LLD) de combinações servidor × domínio × tipo de registro.

Compatível com **Zabbix 4.4** e **6.0 LTS**.

---

## Estrutura

```
DNS-Monitor/
├── 4.4/
│   └── Template.xml
├── 6.0/
│   └── Template.xml
└── externalscripts/
    ├── netstream_dns_check.sh       ← coleta de métricas (DIG e NSLOOKUP)
    └── netstream_dns_discover.py    ← discovery LLD (gera JSON de combinações)
```

---

## Pré-requisitos

No **servidor Zabbix** (não no agente):

| Requisito | Verificação |
|---|---|
| `dig` (bind-utils) | `dig -v` |
| `nslookup` (bind-utils) | `nslookup -version` |
| Python 3 | `python3 --version` |
| Zabbix `ExternalScripts` configurado | `grep ExternalScripts /etc/zabbix/zabbix_server.conf` |

---

## Instalação

### 1. Copiar os scripts

```bash
cp DNS-Monitor/externalscripts/netstream_dns_check.sh /usr/lib/zabbix/externalscripts/
cp DNS-Monitor/externalscripts/netstream_dns_discover.py /usr/lib/zabbix/externalscripts/
chmod +x /usr/lib/zabbix/externalscripts/netstream_dns_check.sh
chmod +x /usr/lib/zabbix/externalscripts/netstream_dns_discover.py
chown zabbix:zabbix /usr/lib/zabbix/externalscripts/netstream_dns_check.sh
chown zabbix:zabbix /usr/lib/zabbix/externalscripts/netstream_dns_discover.py
```

> Se o caminho dos `ExternalScripts` for diferente, ajuste o `cp` acima.
> Para verificar: `grep ExternalScripts /etc/zabbix/zabbix_server.conf`

### 2. Testar os scripts manualmente

```bash
# Deve retornar o tempo de resposta em ms (ex: 12)
/usr/lib/zabbix/externalscripts/netstream_dns_check.sh 8.8.8.8 google.com A dig time

# Deve retornar 1 (sucesso)
/usr/lib/zabbix/externalscripts/netstream_dns_check.sh 8.8.8.8 google.com A dig status

# Deve retornar NOERROR
/usr/lib/zabbix/externalscripts/netstream_dns_check.sh 8.8.8.8 google.com A dig rcode

# Deve retornar JSON com as combinações
/usr/lib/zabbix/externalscripts/netstream_dns_discover.py "8.8.8.8,1.1.1.1" "google.com" "A"
```

### 3. Importar o template no Zabbix

- **Zabbix 4.4:** importar `4.4/Template.xml`
- **Zabbix 6.0:** importar `6.0/Template.xml`

Caminho: **Administration → General → Import**

### 4. Associar o template a um host

O template pode ser aplicado ao próprio servidor Zabbix ou a qualquer host que represente o ponto de monitoramento DNS.

**Configuration → Hosts → (selecionar host) → Templates → Add**

Buscar por `Template DNS Monitor - Netstream` e salvar.

### 5. Configurar as macros no host

Após associar o template, ajustar as macros em **Configuration → Hosts → Macros**:

| Macro | Valor padrão | Descrição |
|---|---|---|
| `{$DNS_SERVERS_NETSTREAM}` | `8.8.8.8,8.8.4.4,1.1.1.1` | Servidores DNS a monitorar, separados por vírgula |
| `{$DNS_DOMAINS_NETSTREAM}` | `google.com` | Domínios de teste, separados por vírgula |
| `{$DNS_TYPES_NETSTREAM}` | `A` | Tipos de registro (`A`, `AAAA`, `MX`, `NS`...), separados por vírgula |
| `{$DNS_TIMEOUT_NETSTREAM}` | `5` | Timeout em segundos para cada consulta |
| `{$DNS_WARN_TIME_NETSTREAM}` | `200` | Limiar WARNING de tempo de resposta (ms) |
| `{$DNS_CRIT_TIME_NETSTREAM}` | `500` | Limiar CRITICAL de tempo de resposta (ms) |

**Exemplo para monitorar DNS interno e externo:**

```
{$DNS_SERVERS_NETSTREAM}  →  192.168.1.1,8.8.8.8,1.1.1.1
{$DNS_DOMAINS_NETSTREAM}  →  google.com,seudominio.com.br
{$DNS_TYPES_NETSTREAM}    →  A,MX
```

Isso vai gerar **12 combinações** monitoradas automaticamente (3 servidores × 2 domínios × 2 tipos).

---

## Como funciona o LLD

O script `netstream_dns_discover.py` recebe as macros como argumentos e retorna um JSON com todas as combinações:

```json
{"data": [
  {"{#DNS_SERVER}": "8.8.8.8", "{#DNS_DOMAIN}": "google.com", "{#DNS_TYPE}": "A"},
  {"{#DNS_SERVER}": "1.1.1.1", "{#DNS_DOMAIN}": "google.com", "{#DNS_TYPE}": "A"}
]}
```

O Zabbix usa esse JSON para criar automaticamente os itens, triggers e gráficos de cada combinação.

> O discovery roda a **cada 1 hora** por padrão. Para forçar imediatamente:
> **Monitoring → Latest Data** → filtrar pelo host → clicar em **Check now** no item de discovery.

---

## Itens coletados por combinação

Para cada `{#DNS_SERVER}` × `{#DNS_DOMAIN}` × `{#DNS_TYPE}`:

| Item | Tipo de dado | Intervalo |
|---|---|---|
| DIG — Tempo de resposta | Unsigned (ms) | 60s |
| DIG — Status (0=Falha / 1=Sucesso) | Unsigned | 60s |
| DIG — RCODE (NOERROR, NXDOMAIN...) | Character | 60s |
| DIG — Resultado da consulta | Text | 60s |
| NSLOOKUP — Tempo de resposta | Unsigned (ms) | 60s |
| NSLOOKUP — Status (0=Falha / 1=Sucesso) | Unsigned | 60s |

> O tempo do **DIG** é extraído diretamente do campo `Query time` da saída (`+stats`), refletindo apenas o RTT da consulta DNS.
> O tempo do **NSLOOKUP** é medido externamente (`date +%s%3N`), incluindo o overhead de inicialização do processo — valores costumam ser ~10–50ms maiores.

---

## Triggers

| Trigger | Severidade | Condição |
|---|---|---|
| DNS DIG lento CRITICAL | HIGH | Tempo DIG > `{$DNS_CRIT_TIME_NETSTREAM}` ms |
| DNS DIG lento WARNING | WARNING | Tempo DIG > `{$DNS_WARN_TIME_NETSTREAM}` ms e ≤ CRITICAL |
| DNS DIG falhou | AVERAGE | Status DIG = 0 |
| DNS DIG RCODE anormal | WARNING | RCODE ≠ `NOERROR` |
| DNS NSLOOKUP lento | HIGH | Tempo NSLOOKUP > `{$DNS_CRIT_TIME_NETSTREAM}` ms |
| DNS NSLOOKUP falhou | AVERAGE | Status NSLOOKUP = 0 |

---

## Gráficos

Um graph prototype é criado por combinação:

**DNS Tempo de Resposta: {#DNS_SERVER} — {#DNS_DOMAIN} ({#DNS_TYPE})**

Sobrepõe DIG (verde) e NSLOOKUP (azul) para comparação visual de latência.

---

## Troubleshooting

**Discovery não cria itens:**
- Verificar se os scripts estão em `/usr/lib/zabbix/externalscripts/` com permissão de execução
- Testar o script manualmente como usuário `zabbix`: `sudo -u zabbix /usr/lib/zabbix/externalscripts/netstream_dns_discover.py "8.8.8.8" "google.com" "A"`
- Verificar o log do servidor: `tail -f /var/log/zabbix/zabbix_server.log | grep dns`

**Itens retornam `9999` ms:**
- O servidor DNS não respondeu dentro do timeout (`{$DNS_TIMEOUT_NETSTREAM}`)
- Verificar conectividade: `dig @<servidor> <domínio> A +time=5`

**RCODE retorna `TIMEOUT` em vez de `NOERROR`:**
- Firewall bloqueando UDP 53 do servidor Zabbix para o servidor DNS
- Aumentar `{$DNS_TIMEOUT_NETSTREAM}` se a rede tiver alta latência

**Erro `Permission denied` no script:**
```bash
chown zabbix:zabbix /usr/lib/zabbix/externalscripts/netstream_dns_check.sh
chmod +x /usr/lib/zabbix/externalscripts/netstream_dns_check.sh
```
