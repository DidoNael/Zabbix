# Arquitetura Padrão de Templates — NETSTREAM

Referência canônica: **Template Switch Huawei 6700 Series - Netstream** (versão 4.4)

Todo template novo ou atualizado deve seguir esta arquitetura. Cada módulo indica se é **obrigatório** (presente em todos os vendors) ou **condicional** (presente quando o vendor/hardware suporta).

---

## Módulos obrigatórios

### M1 — Disponibilidade SNMP

| Elemento | Detalhe |
|---|---|
| Item | `zabbix[host,snmp,available]` — tipo INTERNAL |
| Trigger standalone | `last()=0` por 5min → DISASTER, `notificar=telegram` |
| Tags | `scope=SISTEMA`, `tipo=SNMP_Indisponivel`, `notificar=telegram` |

Presente em: Huawei 6700 ✓ | MikroTik ✗ | **todo template deve ter**

---

### M2 — Identidade do equipamento

Items standalone, tipo SNMPV2:

| Item | OID padrão | Chave padrão |
|---|---|---|
| Descrição do sistema | `sysDescr.0` (1.3.6.1.2.1.1.1.0) | `netstream.sysDescr.0` |
| Uptime do sistema | `sysUpTime.0` (1.3.6.1.2.1.1.3.0) | `netstream.sysUpTime.0` |
| Serial Number | OID do vendor | `netstream.serialNumber` |
| Versão de firmware | OID do vendor | `netstream.firmwareVersion` |

Trigger: uptime < 600s → WARNING (`tipo=Reinicializacao`)

---

### M3 — CPU

**Implementação mínima** (items standalone ou discovery):

| Item | Periodicidade | Trigger |
|---|---|---|
| Uso de CPU (%) | 1m | > 80% por 5min → HIGH |
| Uso médio CPU (calculated) | 1m | — |

**Implementação completa** (como no Huawei): discovery rule por núcleo/slot com `{$CPU_WARN}=60` e `{$CPU_CRIT}=80`.

Macros obrigatórias: `{$CPU_WARN}`, `{$CPU_CRIT}`

---

### M4 — Memória

Discovery rule ou items standalone:

| Item prototype | OID |
|---|---|
| Memória total | vendor |
| Memória livre (bytes e %) | vendor |
| Memória utilizada (bytes e %) | calculated |

Trigger: uso > 80% → HIGH (`tipo=Memoria`, `notificar=telegram`)

---

### M5 — Temperatura

**Mínimo**: item standalone por sensor físico identificado.  
**Padrão Huawei**: discovery por slot com thresholds dinâmicos via OID (Minor/Major).

Macros obrigatórias: `{$TEMP_WARN}` (default: 50) e `{$TEMP_CRIT}` (default: 60)

Trigger: `last() > {$TEMP_CRIT}` → HIGH; `last() > {$TEMP_WARN}` → AVERAGE (`tipo=Temperatura`)

---

### M6 — Fan

**Mínimo**: item standalone RPM por fan.  
**Padrão Huawei**: discovery por módulo, coleta velocidade (%) + estado.

Trigger: velocidade > 80% → HIGH (`tipo=Fan`); estado anormal → HIGH

---

### M7 — Fontes de Alimentação (PSU)

**Mínimo**: item por fonte (presente/ativo — boolean).  
**Padrão Huawei**: discovery por PSU com: presente, status, tipo (AC/DC), potência nominal, consumo atual.

Trigger standalone: fonte ausente ou em falha → HIGH (`tipo=Fonte`, `notificar=telegram`)

Macro: `{$PSU_WARN_PERCENT}` (consumo > X% da nominal — opcional)

---

### M8 — Interfaces físicas

Discovery rule obrigatória: `Discovery | Network interfaces Physical`

OIDs mínimos por prototype:
- Status operacional (`ifOperStatus`) — trigger Link Down
- Tráfego IN/OUT (`ifHCInOctets`, `ifHCOutOctets`) — bps
- Erros IN/OUT (`ifInErrors`, `ifOutErrors`)
- Descarte IN/OUT (`ifInDiscards`, `ifOutDiscards`)
- Velocidade (`ifHighSpeed`)

Nomenclatura obrigatória (padrão unificado entre todos os templates):
```
{Metric} on interface - {#IFNAME}: ({#IFALIAS})
```

Trigger de Link Down obrigatório:
```
count(10m) > 1 and diff() = 1 and last() = 2
```
Tags: `scope=SISTEMA`, `tipo=Link_Down`, `notificar=telegram`

Filtro: excluir interfaces admin-down, loopback, virtuals (em discovery separada — M9)

Macro: `{$IFSPEED_TRIGGER_THRESHOLD}` = 0.9 (saturação a 90%)

---

### M9 — Interfaces virtuais

*(Condicional: vendors com Vlanif/SVI/Eth-Trunk/Bridge)*

Discovery rule separada: `Discovery | Network interfaces Virtual`

Mesmos item prototypes que M8. Filtro: IFTYPE = 131 (tunnel), 135 (mpls), 53 (Vlanif), 161 (Eth-Trunk) ou nome com padrão regex.

Nomenclatura:
```
{Metric} on virtual interface {#IFNAME}: ({#IFALIAS})
```

---

### M10 — Sinal óptico (por interface)

Discovery rule: `Discovery | Network interfaces | Sinal optico SFP`

Item prototypes por porta SFP:

| Item | OID | Multiplier | Unidade |
|---|---|---|---|
| RxPower | vendor | ajustar | dBm |
| TxPower | vendor | ajustar | dBm |
| Temperature | vendor | ajustar | °C |
| TxBias | vendor | ajustar | mA |
| Vendor/Fabricante | vendor | — | string |

Trigger: `RxPower < {$OPTIC_RX_WARN}` → WARNING (`tipo=Sinal_Optico`, `notificar=telegram`)

Macro: `{$OPTIC_RX_WARN}` = -27

Thresholds opcionais (Huawei expõe via SNMP):
- `{$OPTIC_RX_LOW_CRIT}` — limiar crítico de recepção
- `{$TRANSCEIVER_TEMP_WARN}` = 70

---

### M11 — Roteamento BGP

*(Condicional: roteadores com BGP)*

Discovery rule: `Discovery | BGP IPv4 Peers` (+ IPv6 se suportado)

Item prototypes por peer:
- Admin status (up/down)
- Estado FSM (idle/active/established)
- Tempo em estado established
- Prefixos recebidos IPv4/IPv6
- Remote AS

Trigger: peer não-established → DISASTER (`tipo=BGP`, `notificar=telegram`)

Macro: `{$BGP_PEER_WARN_STATE}` = established

> **MikroTik**: implementado via script SSH interno (item mestre `script.json`). Quando migrar para SNMP puro, usar MIB `BGP4-MIB` (1.3.6.1.2.1.15) ou MIB vendor.

---

### M12 — PPPoE/BNG

*(Condicional: equipamentos com função BNG)*

Items standalone:
- Total de sessões ativas
- Máximo 24h (CALCULATED)
- Mínimo 24h (CALCULATED)

Discovery: por domínio PPPoE (sessões ativas + trigger de queda brusca >50%)

Macros: `{$PPPOE_MIN_USERS}` = 10

---

## Tags obrigatórias em toda trigger

| Tag | Valores |
|---|---|
| `scope` | `SISTEMA`, `ELETRICA`, `SWITCH`, `OLT`, `ROTEADOR` |
| `tipo` | `Link_Down`, `Temperatura`, `Fonte`, `Sinal_Optico`, `BGP`, `CPU`, `Memoria`, `Fan`, `SNMP_Indisponivel`, `Reinicializacao`, `PPPoE` |
| `notificar` | `telegram`, `nao` |

---

## Macros padrão de todo template

| Macro | Default | Uso |
|---|---|---|
| `{$SNMP_COMMUNITY}` | `public` | comunidade SNMP |
| `{$CPU_WARN}` | 60 | CPU trigger warning |
| `{$CPU_CRIT}` | 80 | CPU trigger critical |
| `{$TEMP_WARN}` | 50 | temperatura warning |
| `{$TEMP_CRIT}` | 60 | temperatura critical |
| `{$OPTIC_RX_WARN}` | -27 | sinal óptico RxPower mínimo |
| `{$TRANSCEIVER_TEMP_WARN}` | 70 | temperatura do transceiver |

---

## Status atual por template

| Template | M1 | M2 | M3 | M4 | M5 | M6 | M7 | M8 | M9 | M10 | M11 | M12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Huawei 6700 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| MikroTik CCR | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓* | ✓ | ✓ |
| Cisco | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? |
| Datacom | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? | ? |

*MikroTik M10: OIDs corrigidos em v2.13.3, aguarda validação em produção.

---

## Pendências prioritárias — MikroTik CCR

1. **M1** — Adicionar trigger SNMP indisponível
2. **M9** — Interfaces virtuais (Bridge, VLAN, EoIP, GRE) como discovery separada
3. **M11** — Adicionar owner do ASN nos peers BGP (script `get_asn_owner_netstream.sh`)
4. **Macros** — Adicionar `{$CPU_WARN}`, `{$CPU_CRIT}`, `{$TEMP_WARN}`, `{$TEMP_CRIT}`, `{$OPTIC_RX_WARN}`
