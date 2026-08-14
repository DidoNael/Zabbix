# Regras para Templates OLT — NETSTREAM

Regras obrigatórias aplicáveis a **todos** os templates de OLT (ZTE, Fiberhome, Huawei).
Referência canônica: `OLT/ZTE/4.4/Template.xml` e `OLT/ZTE/6.0/Template.xml`.

---

## 1. Discovery de PONs (LOS/DG via script externo)

### Obrigatório em todos os templates

**Master item** (EXTERNAL CHECK, delay=5m, tipo TEXT):
- ZTE: `netstream.gpon.pon.status[{HOST.IP},{$SNMP_COMMUNITY}]`
- Fiberhome: `netstream.gpon.pon.status.fiberhome[{HOST.IP},{$SNMP_COMMUNITY}]`
- Huawei: `netstream.gpon.pon.status.huawei[{HOST.IP},{$SNMP_COMMUNITY}]`

**Discovery rule** (EXTERNAL CHECK, delay=1h):
- ZTE: `netstream.gpon.pon.discovery[{HOST.IP},{$SNMP_COMMUNITY}]` — filtro `gpon`
- Fiberhome/Huawei: equivalente com sufixo por marca

**7 item prototypes dependentes** do master item (DEPENDENT, delay=0):
- `netstream.gpon.pon.online[{#NETSTREAM.PON_INDEX}]`
- `netstream.gpon.pon.offline[{#NETSTREAM.PON_INDEX}]`
- `netstream.gpon.pon.dg[{#NETSTREAM.PON_INDEX}]`
- `netstream.gpon.pon.los[{#NETSTREAM.PON_INDEX}]`
- `netstream.gpon.pon.lof[{#NETSTREAM.PON_INDEX}]`
- `netstream.gpon.pon.losi[{#NETSTREAM.PON_INDEX}]`
- `netstream.gpon.pon.auth[{#NETSTREAM.PON_INDEX}]`

**4 item prototypes calculados** (CALCULATED, delay=1m, espelho dos dependentes):
- `netstream.gpon.pon.calc.online[{#NETSTREAM.PON_INDEX}]`
- `netstream.gpon.pon.calc.offline[{#NETSTREAM.PON_INDEX}]`
- `netstream.gpon.pon.calc.dg[{#NETSTREAM.PON_INDEX}]`
- `netstream.gpon.pon.calc.los[{#NETSTREAM.PON_INDEX}]`

### 4 trigger prototypes obrigatórios

Todos os 4 triggers exigem warmup `count(180)>1` para evitar falso positivo na discovery.

| Trigger | Severidade | Expressão | Recuperação | Manual Close | notificar |
|---|---|---|---|---|---|
| Queda Total | DISASTER | `last()=0 and count(180)>1` | `last()>0` | NÃO | nao |
| DyingGasp | DISASTER | `delta(900)>=3 and count(180)>1` | — | SIM | nao |
| LOS | HIGH | `delta(900)>=3 and count(180)>1` | — | SIM | **telegram** |
| Queda Parcial | HIGH | `change()<-{$GPON_DROP_MIN} and last()>0 and count(180)>1` | — | SIM | nao |

- `delta(900)` = max - min nos últimos 900 segundos — detecta **incremento recente**
- **Nunca usar `last()>N`** para DG/LOS — dispara baseado em valor absoluto histórico (falso positivo)
- **LOS é o único trigger que notifica Telegram** — todos os outros ficam só no Zabbix

### Tags obrigatórias nos triggers de PON

```
scope   = OLT
servico = GPON
pon     = {#NETSTREAM.PON_NAME}
tipo    = Queda_Total | DyingGasp | LOS | Queda_Parcial
notificar = nao | telegram
```

---

## 2. Tráfego TX/RX por PON (IF-MIB)

### Discovery dedicada

- Key: `netstream.gpon.pon.traffic.discovery`
- OID discovery: `discovery[{#SNMPVALUE},IF-MIB::ifDescr,{#IFNAME},IF-MIB::ifName]` ou equivalente
- Filtro em `{#IFNAME}` ou `{#OLTPORT}`: MATCHES `(?i)^\S*pon[ _]?\d+/\d+/\d+`

### Items de tráfego

- RX (download): OID `1.3.6.1.2.1.31.1.1.1.6.{#SNMPINDEX}` (ifHCInOctets)
- TX (upload): OID `1.3.6.1.2.1.31.1.1.1.10.{#SNMPINDEX}` (ifHCOutOctets)
- Keys: `netstream.gpon.pon.traffic.in[{#SNMPINDEX}]` e `.out[{#SNMPINDEX}]`

### Preprocessing (obrigatório, nesta ordem)

1. **CHANGE_PER_SECOND** — converte bytes acumulados em Bps
2. **MULTIPLIER 8** — converte Bps em bps
3. **IN_RANGE 0 / 12500000000 — DISCARD** — descarta counter wrap (>12,5 Gbps = inválido)

### Parâmetros

- Tipo: SNMP_AGENT (6.0) ou SNMPv2 (4.4)
- Delay: 1m | History: 7d | Trends: 90d | Unidade: bps

### Graph prototype obrigatório

- Nome: `PON {#IFNAME}: Trafego TX/RX` (ou `{#OLTPORT}` dependendo da macro disponível)
- Duas séries: IN (azul) e OUT (verde)

---

## 3. Discovery de Uplinks

### Items obrigatórios por uplink

| Item | OID | Preprocessing |
|---|---|---|
| RX bps (ifHCInOctets) | `1.3.6.1.2.1.31.1.1.1.6.{#SNMPINDEX}` | CHANGE_PER_SECOND + x8 |
| TX bps (ifHCOutOctets) | `1.3.6.1.2.1.31.1.1.1.10.{#SNMPINDEX}` | CHANGE_PER_SECOND + x8 |
| Drops entrada | `1.3.6.1.2.1.2.2.1.13.{#SNMPINDEX}` | CHANGE_PER_SECOND |
| Drops saída | `1.3.6.1.2.1.2.2.1.19.{#SNMPINDEX}` | CHANGE_PER_SECOND |
| Erros entrada | `1.3.6.1.2.1.2.2.1.14.{#SNMPINDEX}` | CHANGE_PER_SECOND |
| Status ifOperStatus | `1.3.6.1.2.1.2.2.1.8.{#SNMPINDEX}` | — |
| RX Power dBm | OID específico por marca | MULTIPLIER (0.001 ou 0.01) |
| TX Power dBm | OID específico por marca | MULTIPLIER (0.001 ou 0.01) |
| Temperatura SFP | OID específico por marca | MULTIPLIER (0.001 ou 0.01) |

**OIDs de SFP por marca:**

| Marca | RX Power | TX Power | Temperatura |
|---|---|---|---|
| ZTE | `1.3.6.1.4.1.3902.1082.30.40.2.4.1.2.{#SNMPINDEX}` × 0.001 | `.3.{#SNMPINDEX}` × 0.001 | `.8.{#SNMPINDEX}` × 0.001 |
| Fiberhome | `1.3.6.1.4.1.5875.91.1.17.2.1.13.{#SNMPINDEX}` × 0.01 | `.12.{#SNMPINDEX}` × 0.01 | `.11.{#SNMPINDEX}` × 0.01 |
| Huawei | `1.3.6.1.4.1.2011.6.149.2.5.1.3.{#SNMPINDEX}` × 0.01 | `.4.{#SNMPINDEX}` × 0.01 | `.2.{#SNMPINDEX}` × 0.01 |

### Triggers obrigatórios de uplink

- **Link DOWN**: `max(#3)=2` — HIGH
- **Drops altos entrada**: `avg(5m)>10` — WARNING
- **Drops altos saída**: `avg(5m)>10` — WARNING

### Graph prototype obrigatório

- Nome: `Uplink {#IFNAME}: Trafego (Download / Upload)`
- Duas séries: RX e TX em bps

---

## 4. Hardware por placa/slot

### Discovery obrigatória

Habilitar por padrão (`status=ENABLED`). Fiberhome tem discovery DISABLED — deve ser ativada.

### Items obrigatórios

| Item | Threshold alarme |
|---|---|
| CPU % por slot | >90% por 10 minutos (AVERAGE) |
| Memória % por slot | >90% por 10 minutos (AVERAGE) |
| Status da placa | value map com mínimo: inService/faulty/offline/powerOff |

### Triggers obrigatórios

| Trigger | Expressão | Severidade |
|---|---|---|
| CPU alta | `min(10m)>90` | AVERAGE |
| Memória alta | `min(10m)>90` | AVERAGE |
| Status Faulty | `last()=<código faulty>` | HIGH |
| Status Offline/Down | `last()=<código offline>` | HIGH |
| Status Sem Energia | `last()=<código power_off>` | HIGH |
| Status Not in Service | `last()=<código not_in_service>` | WARNING |

Thresholds: CPU/Mem em **90%** (não 80%). Janela: **10 minutos** (não pontual).

---

## 5. PSU e Ventiladores

### PSU

- PSU1 e PSU2 como itens separados (podem ser DISABLED por padrão)
- Triggers PSU Fail (=2): HIGH
- Triggers PSU Offline (=3): WARNING

### Fan

- Item de status (pode ser DISABLED por padrão)
- Trigger Fan Fail: HIGH

Fiberhome e Huawei não têm esses OIDs padronizados — investigar MIB antes de adicionar.

---

## 6. OLT Global (Uptime / Nodata / Totais)

### Items obrigatórios

- **Uptime**: OID `1.3.6.1.2.1.1.3.0` — MULTIPLIER 0.01 — unidade `uptime`
- **Totais OLT**: auth, online, offline, dg, los, losi, lof (DEPENDENT do master externo)

### Triggers obrigatórios

| Trigger | Expressão | Severidade |
|---|---|---|
| Reboot detectado | `last()<600 or change()<0` | WARNING |
| OLT Inacessível | `nodata(5m)=1` | DISASTER |

- Trigger de Reboot: threshold 600s (10 minutos de uptime). Fiberhome tem `<1m` — corrigir.
- Trigger nodata: **ausente** em Fiberhome e Huawei — **deve ser adicionado**.

---

## 7. ONU Dedicada

### Features obrigatórias (quando MIB suportar)

| Feature | ZTE | Fiberhome | Huawei |
|---|---|---|---|
| Status online/offline | PRESENTE | DISABLED | DISABLED |
| RX Power dBm | PRESENTE | DISABLED | DISABLED |
| Causa última queda | PRESENTE | AUSENTE | DISABLED |
| Distância (m) | PRESENTE | AUSENTE | AUSENTE |
| Status porta LAN | PRESENTE | AUSENTE | AUSENTE |
| Velocidade LAN | PRESENTE | AUSENTE | AUSENTE |
| Duplex LAN | PRESENTE | AUSENTE | AUSENTE |

Prioridade de implementação: habilitar DISABLED antes de buscar OIDs ausentes.

### Triggers ONU Dedicada

- Status offline: `min(#3)=1` (verificar 3 coletas antes de alarmar) — AVERAGE
- RX Power Crítico: `last()<=-28` — HIGH
- RX Power Degradado: `last()<=-25` — WARNING
- LAN DOWN: `last()=2` (ifOperStatus down) — AVERAGE

### Tags ONU Dedicada

```
scope   = OLT
servico = GPON
tipo    = ONU_Dedicada
notificar = nao
```

---

## 8. SFP Óptico por PON

Disponível via MIB proprietária por marca (descoberta de portas GPON, não IF-MIB).

| Feature | ZTE | Fiberhome | Huawei |
|---|---|---|---|
| TX Power dBm por PON | PRESENTE | DISABLED | AUSENTE |
| RX Power dBm por PON | AUSENTE | DISABLED | AUSENTE |
| Temperatura SFP por PON | PRESENTE | PRESENTE | AUSENTE |

- Fiberhome: habilitar TX/RX Power via GEPON-OLT-COMMON-MIB
- Huawei: investigar equivalente na HUAWEI-GPON-MIB

---

## 9. Macros obrigatórias

| Macro | Valor padrão | Obrigatória em |
|---|---|---|
| `{$SNMP_COMMUNITY}` | `public` | Todos (ZTE não declara — adicionar) |
| `{$GPON_DROP_MIN}` | `5` | Todos |

---

## 10. Nomenclatura e Padrões de Keys

| Contexto | Padrão de key |
|---|---|
| Status PON (dependente) | `netstream.gpon.pon.<campo>[{#NETSTREAM.PON_INDEX}]` |
| Status PON calculado | `netstream.gpon.pon.calc.<campo>[{#NETSTREAM.PON_INDEX}]` |
| Tráfego PON | `netstream.gpon.pon.traffic.in[{#SNMPINDEX}]` / `.out[{#SNMPINDEX}]` |
| Tráfego uplink | OID direto com `{#SNMPINDEX}` |
| ONU dedicada | `netstream.dedicado.<campo>[{#SNMPINDEX}]` |
| SFP PON | `netstream.gpon.sfp.<campo>[{#PROPRIETARYINDEX}]` |
| Hardware | `netstream.<marca>.card.<campo>[{#SNMPINDEX}]` |

---

## 11. Versões 6.0

### Diferenças obrigatórias da sintaxe 6.0

- Tipo SNMP: `SNMP_AGENT` (não `SNMPV2`)
- Expressões de trigger: `func(/TemplateName/item.key,params)` (não `{host:key.func(params)}`)
- Todos os objetos com UUID gerado (`<uuid>`)
- `<version>6.0</version>` no cabeçalho

### Status atual

| Template | 6.0 existe? |
|---|---|
| ZTE | SIM |
| Fiberhome | NÃO (somente .gitkeep) |
| Huawei | NÃO (somente .gitkeep) |

---

## 12. Regras de Processo

- **Nunca criar trigger para o item `ifLastChange`** (uptime do link no Grafana).
- **Nunca usar `last()>N` para DG ou LOS** — sempre `delta(900)>=3`.
- **Warmup obrigatório**: qualquer trigger em discovery de PON deve ter `count(180)>1` (2+ coletas em 3 minutos).
- **Antes de importar template no Zabbix**: verificar se o item mudou de prototype para standalone (ou vice-versa). Se sim, deletar o prototype conflitante antes de importar para evitar erro "No permissions to referred object" (Zabbix 6.0).
- **git push obrigatório** após cada commit no repo `zabbix-templates`.
- **Trigger de Queda Total tem auto-recovery** (`recovery_expression`); DG, LOS e Queda Parcial são `manual_close=YES`.
- Hardware discovery deve estar **ENABLED** por padrão em todos os templates.

---

## 13. Gaps por Marca (backlog)

### Fiberhome — pendente

- [ ] Criar template 6.0
- [ ] Habilitar discovery de hardware (DISABLED → ENABLED)
- [ ] Corrigir threshold CPU/Mem: 80% → 90%, adicionar janela min(10m)
- [ ] Adicionar triggers de status de placa (Faulty, Offline, Power, Not in Service)
- [ ] Adicionar trigger `nodata(5m)=1` DISASTER
- [ ] Corrigir trigger reboot: `<1m INFO` → `<600s WARNING`
- [ ] Adicionar PSU1 e PSU2
- [ ] Adicionar Fan
- [ ] Habilitar ONU Dedicada (discovery DISABLED)
- [ ] Adicionar causa de queda e LAN status/speed/duplex na ONU Dedicada
- [ ] Habilitar TX/RX Power por PON (DISABLED via GEPON-OLT-COMMON-MIB — não habilitar corrente mA)
- [ ] Padronizar tags de triggers legados (PONDOWN/PONFH → scope/tipo/notificar)
- [ ] Adicionar graph prototype de uplink

### Huawei — pendente

- [ ] Criar template 6.0
- [ ] Adicionar item uptime + trigger reboot
- [ ] Adicionar trigger `nodata(5m)=1` DISASTER
- [ ] Adicionar Memória % por slot (só tem CPU e temperatura)
- [ ] Adicionar status da placa com value map detalhado
- [ ] Adicionar triggers CPU>90%/10min, Mem>90%/10min, status Faulty/Offline/Power
- [ ] Adicionar PSU1 e PSU2
- [ ] Adicionar Fan
- [ ] Habilitar ONU Dedicada (DISABLED) — adicionar causa queda, distância, LAN
- [ ] Corrigir item `ifHCInOctets` na discovery `olt_pcb`: adicionar CHANGE_PER_SECOND + x8
- [ ] Investigar OIDs de SFP por PON (ausente)
- [ ] Adicionar erros de entrada nos uplinks (ausente)
- [ ] Adicionar trigger Link DOWN nos uplinks (ausente)
- [ ] Padronizar tags de triggers legados (PONDOWN/PONHW → scope/tipo/notificar)
- [ ] Adicionar graph prototype de uplink

### ZTE — pendente

- [ ] Declarar macro `{$SNMP_COMMUNITY}` no bloco de macros do template (usada mas não declarada)
- [ ] Investigar e corrigir `PROPRIETARYINDEX = (slot+1)*256` → `slot*256` (lê dados da PON errada)
- [ ] Habilitar PSU1 e PSU2 por padrão (atualmente DISABLED)
- [ ] Habilitar Fan por padrão (atualmente DISABLED)
- [ ] Adicionar RX Power dBm por PON (TX e Temperatura existem; RX ausente)
