# 🌐 Zabbix Agent Active — Windows | Monitoramento de Qualidade de Internet

Monitoramento completo de qualidade de internet via **Zabbix Agent Active** no Windows, usando scripts PowerShell como UserParameters.

> **Versão**: Zabbix 6.0 LTS | Windows 10/11/Server 2019+

---

## 📦 Conteúdo

```
zabbix-agent-active-windows/
├── conf/
│   └── zabbix_agentd.conf.example   ← UserParameters prontos para copiar
└── scripts/
    ├── ping_check.ps1               ← Latência, perda e jitter (por IP)
    ├── speedtest.ps1                ← Download/Upload em Mbps (Ookla CLI)
    ├── dns_check.ps1                ← Tempo de resolução DNS (geral)
    ├── http_check.ps1               ← Tempo de resposta e status HTTP (geral)
    ├── site_http.ps1                ← HTTP + SSL expiry por site
    ├── site_ping.ps1                ← Ping por domínio/site
    ├── tracert_check.ps1            ← Traceroute com hops, RTT e JSON
    ├── mtr_check.ps1                ← MTR simulado (múltiplos pings por hop)
    └── nslookup_check.ps1           ← NSLookup avançado (A, MX, NS, TXT...)
```

---

## ⚡ Instalação Rápida

### 1. Copiar scripts

```powershell
# Criar pasta de scripts
New-Item -ItemType Directory -Force -Path "C:\zabbix\scripts"

# Copiar todos os scripts para o agente
Copy-Item .\scripts\*.ps1 -Destination "C:\zabbix\scripts\"
```

### 2. Configurar o agente

Adicione o conteúdo de `conf/zabbix_agentd.conf.example` ao seu `zabbix_agentd.conf`.

```powershell
# Localização padrão do conf (instalador oficial)
notepad "C:\Program Files\Zabbix Agent\zabbix_agentd.conf"
```

### 3. Definir política de execução

```powershell
Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
```

### 4. Instalar Speedtest CLI (para métricas de velocidade)

```powershell
winget install Ookla.Speedtest
# Aceitar os termos na primeira execução:
& "C:\Program Files\Speedtest CLI\speedtest.exe" --accept-license --accept-gdpr
```

### 5. Reiniciar o agente

```powershell
Restart-Service "Zabbix Agent"
```

---

## 📋 UserParameters — Chaves Disponíveis

Todos os destinos são **customizáveis** via parâmetros na chave do item `[*]`.

| Chave | Descrição | Unidade |
|---|---|---|
| `internet.ping.latency[IP]` | Latência média ICMP | ms |
| `internet.ping.loss[IP]` | Perda de pacotes | % |
| `internet.ping.jitter[IP]` | Jitter (variação de latência) | ms |
| `internet.speed.download` | Velocidade de download | Mbps |
| `internet.speed.upload` | Velocidade de upload | Mbps |
| `internet.dns.time[dominio]` | Tempo de resolução DNS | ms |
| `internet.http.time[URL]` | Tempo de resposta HTTP | ms |
| `internet.http.status[URL]` | Código de status HTTP | |
| `site.http.time[URL]` | Tempo HTTP por site | ms |
| `site.http.status[URL]` | Status HTTP por site | |
| `site.http.ssl_days[URL]` | Dias até expiração do SSL | days |
| `site.ping.latency[host]` | Ping por domínio/site | ms |
| `site.ping.loss[host]` | Perda por domínio/site | % |
| `site.ping.jitter[host]` | Jitter por domínio/site | ms |
| `site.tracert.hops[host]` | Número de hops até destino | hops |
| `site.tracert.last_rtt[host]` | RTT do último hop | ms |
| `site.tracert.max_rtt[host]` | RTT máximo na rota | ms |
| `site.tracert.json[host]` | JSON completo da rota | texto |
| `site.mtr.avg_rtt[host]` | MTR — RTT médio ao destino | ms |
| `site.mtr.max_rtt[host]` | MTR — RTT máximo ao destino | ms |
| `site.mtr.loss[host]` | MTR — Perda no destino | % |
| `site.mtr.json[host]` | MTR — JSON com todos os hops | texto |
| `site.dns.resolve_time[dom,dns]` | Tempo DNS via servidor específico | ms |
| `site.dns.resolved_ip[dom,dns]` | IP resolvido | texto |
| `site.dns.record_count[dom,dns]` | Quantidade de registros DNS | |
| `site.dns.status[dom,dns]` | Status resolução (1=ok, 0=falhou) | |

---

## 🔧 Intervalos Recomendados

| Check | Intervalo |
|---|---|
| Ping / Latência | 1 min |
| HTTP time/status | 2 min |
| DNS resolve | 5 min |
| Tracert | 10 min |
| MTR | 15 min ⚠️ |
| Speedtest | 15 min |
| SSL expiry | 1 hora |

> ⚠️ O MTR pode demorar 2–5 minutos por execução. Use intervalo mínimo de 15 min.

---

## ✅ Validação

```powershell
# Testar cada UserParameter via agente
& "C:\Program Files\Zabbix Agent\zabbix_agentd.exe" -t "site.ping.latency[google.com]"
& "C:\Program Files\Zabbix Agent\zabbix_agentd.exe" -t "site.http.time[https://www.google.com]"
& "C:\Program Files\Zabbix Agent\zabbix_agentd.exe" -t "site.tracert.hops[google.com]"
& "C:\Program Files\Zabbix Agent\zabbix_agentd.exe" -t "site.dns.resolve_time[google.com,8.8.8.8]"
& "C:\Program Files\Zabbix Agent\zabbix_agentd.exe" -t "site.http.ssl_days[https://www.google.com]"
```

---

## 🚨 Triggers Sugeridas

| Trigger | Expressão | Severidade |
|---|---|---|
| Alta latência | `last(internet.ping.latency[8.8.8.8])>150` | Warning |
| Perda de pacotes > 5% | `last(internet.ping.loss[8.8.8.8])>5` | Warning |
| Internet inacessível | `last(internet.ping.loss[8.8.8.8])>=100` | Disaster |
| Site indisponível | `last(site.http.status[URL])=0` | Disaster |
| HTTP erro 4xx/5xx | `last(site.http.status[URL])>=400` | High |
| SSL expirando em 30 dias | `last(site.http.ssl_days[URL])<30` | Warning |
| SSL expirando em 7 dias | `last(site.http.ssl_days[URL])<7` | High |
| DNS falhou | `last(site.dns.status[dom,dns])=0` | High |
| Download baixo | `last(internet.speed.download)<10` | Warning |

---

*Compatível com Zabbix 6.0 LTS | Windows 10 / 11 / Server 2019+*
