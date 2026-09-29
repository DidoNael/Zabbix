# Regras — Servidor Linux / ZABBIX AGENT ACTIVE - NETSTREAM

## Estrutura do template

```
Servidor Linux/
├── 7.0/
│   └── SERVIDOR LINUX - ZABBIX AGENT ACTIVE - NETSTREAM.xml   ← template Zabbix 7.0
├── userparameters/
│   └── servidor_linux.conf   ← UserParameters para instalar no agente
└── CLAUDE.md
```

## Versões Zabbix

| Versão | Arquivo | Status |
|--------|---------|--------|
| 7.0    | `7.0/SERVIDOR LINUX - ZABBIX AGENT ACTIVE - NETSTREAM.xml` | Produção |

Ao adicionar suporte a versões anteriores (6.0, 4.4), criar subpasta correspondente seguindo o padrão do restante do repo.

---

## Itens do template e suas chaves

| Chave Zabbix           | UserParameter               | Dep. externa |
|------------------------|-----------------------------|--------------|
| `cpu.utilization`      | `cpu.utilization`           | —            |
| `disk.used.percent.root` | `disk.used.percent.root`  | —            |
| `disk.iostat.await`    | `disk.iostat.await`         | sysstat      |
| `disk.iostat.r_await`  | `disk.iostat.r_await`       | sysstat      |
| `disk.iostat.w_await`  | `disk.iostat.w_await`       | sysstat      |
| `disk.iostat.read`     | `disk.iostat.read`          | sysstat      |
| `disk.iostat.write`    | `disk.iostat.write`         | sysstat      |
| `net.if.input.mbps`    | `net.if.input.mbps`         | —            |
| `net.if.output.mbps`   | `net.if.output.mbps`        | —            |
| `ssh.failed.logins`    | `ssh.failed.logins`         | —            |
| `uptime.system`        | `uptime.system`             | —            |
| `dns.check.globo`      | `dns.check.globo`           | dnsutils/dig |
| `dns.check.registrobr` | `dns.check.registrobr`      | dnsutils/dig |
| `dns.check.uol`        | `dns.check.uol`             | dnsutils/dig |
| `dns.check.youtube`    | `dns.check.youtube`         | dnsutils/dig |

---

## Triggers configuradas

| Nome | Expressão | Prioridade |
|------|-----------|------------|
| Consumo de CPU | `avg(#10) >= 90%` | HIGH |
| Consumo de disco elevado | `avg(#3) >= 90%` | HIGH |
| Disco Cheio | `avg(#3) >= 99%` | HIGH |
| DISK IO - Tempo de espera alto > 20ms | `count(#10) >= 20 em read ou write` | AVERAGE |
| Falha de resolução DNS | `todos os 4 checks = 0` | HIGH |
| Host Reiniciado | `uptime < 86400s` | HIGH |
| Tentativa de brute force | `change(ssh.failed.logins) > 100` | AVERAGE |

---

## Instalação do UserParameter no agente

```bash
# Copiar conf
cp servidor_linux.conf /etc/zabbix/zabbix_agentd.d/

# Instalar dependências
# Debian/Ubuntu:
apt install sysstat dnsutils

# CentOS/RHEL (inclui Issabel PBX):
yum install sysstat bind-utils

# Reiniciar agente
systemctl restart zabbix-agent

# Testar cada chave
zabbix_agentd -t disk.used.percent.root
zabbix_agentd -t dns.check.globo
zabbix_agentd -t cpu.utilization
```

---

## Atenção: disco I/O hardcoded em `sda`

Os UserParameters de `disk.iostat.*` usam `awk '/sda/'`. Em servidores com disco diferente (`vda`, `nvme0n1`, `xvda`) as chaves retornam vazio e ficam "Não suportado".

**Antes de instalar**, verificar o nome do disco:
```bash
lsblk -d -o NAME | tail -n +2 | head -1
```

Ajustar os UserParameters conforme o dispositivo real se necessário.

---

## DNS: retorno esperado

Cada `dns.check.*` retorna `1` (OK) ou `0` (falha). O trigger só dispara quando **todos os 4 = 0 simultaneamente** — isso indica falha total de DNS no servidor, não falha de um único site.

---

## Regras gerais (herdadas do CLAUDE.md raiz)

- Nunca aplicar diretamente em produção sem OK do usuário
- Qualquer mudança vai no CHANGELOG.md + tag semver
- Erros novos de import → registrar em `zabbix-server/docs/TROUBLESHOOTING_XML_IMPORT.md`
