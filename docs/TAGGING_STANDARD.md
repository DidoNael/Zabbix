# Padrão de Tags — Zabbix Netstream

> Versão 1.0 · 2026-07-19  
> Aplica-se a todos os templates mantidos neste repositório.

Tags são o mecanismo central de roteamento de alertas no Zabbix: actions, correlação de eventos, dashboards e integrações (Telegram, e-mail, ticket) filtram por tag. Um padrão consistente evita alertas perdidos e facilita a manutenção.

---

## 1. Regras Gerais

- Toda trigger **deve ter** pelo menos as tags `scope` e `tipo`.
- Nomes de tags em **minúsculas com underline** (`pon_desc`, `onu_id`). Exceção: macros LLD que herdam o nome da macro (`{#PONNAME}`).
- Valores **estáticos** em português, sem acentos, sem espaços (`Reinicializacao`, `Hardware`).
- Valores **dinâmicos** usam macros do Zabbix (`{#PONNAME}`, `{ITEM.LASTVALUE1}`).
- Nunca usar flags booleanas como tag (`PONDOWN=PONDOWN`) — prefira `tipo=Conectividade`.
- Tags legadas (`PONDOWN`, `PONHW`, `PONZTE`, `ONUDEDICADO`) devem ser substituídas quando o template for atualizado.

---

## 2. Tags Obrigatórias

| Tag     | Tipo     | Descrição                          | Valores possíveis                                              |
|---------|----------|------------------------------------|----------------------------------------------------------------|
| `scope` | Estático | Escopo do equipamento monitorado   | `OLT`, `Switch`, `Router`, `Servidor`, `Link`, `ISP`          |
| `tipo`  | Estático | Categoria do evento                | Ver **Seção 3**                                                |

---

## 3. Valores Padronizados para `tipo`

| Valor              | Quando usar                                                       |
|--------------------|-------------------------------------------------------------------|
| `LOS`              | Fibra rompida, perda de sinal óptico na ONU/PON                  |
| `Dying Gasp`       | ONU sem energia elétrica                                          |
| `Hardware`         | Falha física: PSU, ventilador, placa, temperatura                 |
| `Reinicializacao`  | Equipamento reiniciou (uptime baixo)                              |
| `Conectividade`    | Link down, sem resposta SNMP, OSPF/BGP down, OLT inacessível     |
| `Performance`      | CPU alta, RAM alta, drops, erros de interface, taxa de erros CRC  |
| `Capacidade`       | PON cheia, limite de ONUs atingido                                |
| `Roteamento`       | BGP peer down, OSPF neighbor down, flapping, MTU mismatch        |
| `Optico`           | Sinal RX/TX fora do limiar, temperatura do módulo SFP            |
| `PPPoE`            | Queda brusca de clientes PPPoE, domínio sem sessões              |

---

## 4. Tags de Contexto (quando aplicável)

Incluir sempre que a trigger for criada por descoberta (LLD) ou quando o valor agrega informação útil no evento.

| Tag          | Tipo            | Descrição                              | Exemplos de valor                              |
|--------------|-----------------|----------------------------------------|------------------------------------------------|
| `vendor`     | Estático        | Fabricante do equipamento              | `ZTE`, `FiberHome`, `Huawei`, `Cisco`          |
| `servico`    | Estático        | Serviço ou protocolo monitorado        | `GPON`, `EPON`, `BGP`, `OSPF`, `PPPoE`        |
| `interface`  | Macro LLD       | Nome da interface de rede              | `{#IFNAME}`, `{#IFDESC}`, `{#ENTPHYSICALNAME}`|
| `pon`        | Macro LLD       | Nome da porta PON                      | `{#PONNAME}`, `{#NETSTREAM.PON_NAME}`          |
| `onu_id`     | Macro LLD       | Identificador da ONU/ONT               | `{#ONUID}`, `{#ONTDESC}`, `{#ONUSN}`          |
| `slot`       | Macro LLD       | Slot ou índice da placa                | `{#SNMPINDEX}`                                 |
| `card_type`  | Macro LLD       | Tipo da placa (OLT)                    | `{#CARDTYPE}`                                  |
| `vizinho`    | Macro LLD       | IP do peer de roteamento               | `{#OSPFNBRIP}`, `{#IP}`                        |
| `asn`        | Macro LLD       | ASN do peer BGP                        | `{#ASN}`                                       |
| `dominio`    | Macro LLD       | Domínio PPPoE                          | `{#DOMAIN}`                                    |

---

## 5. Tags de Valor Dinâmico

Usadas para incluir o valor atual do item como contexto no evento. Facilitam triagem sem abrir o Zabbix.

| Tag           | Quando usar                                 | Valor                    |
|---------------|---------------------------------------------|--------------------------|
| `onus_online` | Triggers de queda massiva ou PON inativa    | `{ITEM.LASTVALUE1}`      |
| `sinal_rx`    | Sinal óptico RX baixo (ONU/uplink)          | `{ITEM.LASTVALUE}`       |
| `status`      | Estado atual do item monitorado             | `{ITEM.LASTVALUE}`       |
| `pon_desc`    | Alias/descrição da porta PON                | `{#PONDESC}`             |
| `asn_status`  | Último estado BGP                           | `{ITEM.LASTVALUE4}`      |

---

## 6. Mapeamento por Template

### OLT ZTE / FiberHome / Huawei (GPON)

| Trigger                                              | scope | tipo             | contexto                            |
|------------------------------------------------------|-------|------------------|-------------------------------------|
| ONU LOS                                              | `OLT` | `LOS`            | `pon`, `onu_id`, `slot`, `servico=GPON`, `vendor` |
| ONU Dying Gasp                                       | `OLT` | `Dying Gasp`     | `pon`, `onu_id`, `slot`, `servico=GPON`, `vendor` |
| PON LOS em múltiplas ONUs                            | `OLT` | `LOS`            | `pon`, `servico=GPON`, `vendor`, `onus_online`     |
| Porta GPON Apagada / Inativa                         | `OLT` | `Conectividade`  | `pon`, `pon_desc`, `servico=GPON`, `onus_online`   |
| Porta GPON Cheia                                     | `OLT` | `Capacidade`     | `pon`, `pon_desc`, `servico=GPON`, `onus_online`   |
| Queda massiva de ONUs                                | `OLT` | `LOS`            | `pon`, `pon_desc`, `servico=GPON`, `onus_online`   |
| Taxa de erros CRC / entrada / saída                  | `OLT` | `Performance`    | `pon`, `pon_desc`                                  |
| Placa offline / faulty / sem energia                 | `OLT` | `Hardware`       | `slot`, `card_type`                                |
| Placa CPU / RAM elevado                              | `OLT` | `Performance`    | `slot`, `card_type`                                |
| OLT: Falha PSU / Fan                                 | `OLT` | `Hardware`       | `vendor`                                           |
| OLT: PSU Desconectada / Offline                      | `OLT` | `Hardware`       | `vendor`                                           |
| OLT: Reiniciou                                       | `OLT` | `Reinicializacao`| `vendor`                                           |
| OLT: Inacessível (sem resposta SNMP)                 | `OLT` | `Conectividade`  | `vendor`                                           |
| Uplink Link DOWN                                     | `OLT` | `Conectividade`  | `interface`                                        |
| Uplink drops entrada / saída                         | `OLT` | `Performance`    | `interface`                                        |
| Uplink erros CRC                                     | `OLT` | `Performance`    | `interface`                                        |
| Sinal RX/TX SFP fora do limiar                       | `OLT` | `Optico`         | `pon`, `pon_desc`                                  |

### Switch Huawei 6700

| Trigger                                              | scope    | tipo             | contexto                         |
|------------------------------------------------------|----------|------------------|----------------------------------|
| Equipamento Reiniciou                                | `Switch` | `Reinicializacao`| `vendor=Huawei`                  |
| CPU elevado                                          | `Switch` | `Performance`    | `slot`                           |
| Memória elevada                                      | `Switch` | `Performance`    | —                                |
| Fan status anormal / velocidade alta                 | `Switch` | `Hardware`       | `slot`                           |
| PSU status anormal                                   | `Switch` | `Hardware`       | `slot`                           |
| Interface DOWN                                       | `Switch` | `Conectividade`  | `interface`                      |
| Erros de CRC / interface                             | `Switch` | `Performance`    | `interface`                      |
| Sinal RX/TX módulo óptico fora do limiar             | `Switch` | `Optico`         | `interface`                      |
| BGP peer DOWN                                        | `Switch` | `Roteamento`     | `vizinho`, `asn`, `servico=BGP`  |
| OSPF neighbor DOWN / não Full                        | `Switch` | `Roteamento`     | `vizinho`, `servico=OSPF`        |
| OSPF flapping                                        | `Switch` | `Roteamento`     | `vizinho`, `servico=OSPF`        |
| OSPF MTU mismatch                                    | `Switch` | `Roteamento`     | `vizinho`, `servico=OSPF`        |
| PPPoE queda brusca de clientes                       | `Switch` | `PPPoE`          | `interface`, `dominio`           |

### OSPF Genérico

| Trigger                                              | scope    | tipo         | contexto                         |
|------------------------------------------------------|----------|--------------|----------------------------------|
| OSPF Neighbor DOWN                                   | `Router` | `Roteamento` | `vizinho`, `servico=OSPF`        |
| OSPF Neighbor não Full                               | `Router` | `Roteamento` | `vizinho`, `servico=OSPF`        |
| OSPF flapping                                        | `Router` | `Roteamento` | `vizinho`, `servico=OSPF`        |
| OSPF Cost alterado                                   | `Router` | `Roteamento` | `interface`, `servico=OSPF`      |
| OSPF MTU mismatch                                    | `Router` | `Roteamento` | `interface`, `servico=OSPF`      |

### ISP Experience

| Trigger                                              | scope | tipo         | contexto              |
|------------------------------------------------------|-------|--------------|-----------------------|
| Serviço offline                                      | `ISP` | `Conectividade` | `servico`          |

---

## 7. Exemplo de Bloco XML (Zabbix 4.4)

```xml
<trigger>
    <name>OLT: Falha no Ventilador (Fan Fail)</name>
    <expression>...</expression>
    <priority>HIGH</priority>
    <tags>
        <tag>
            <tag>scope</tag>
            <value>OLT</value>
        </tag>
        <tag>
            <tag>tipo</tag>
            <value>Hardware</value>
        </tag>
        <tag>
            <tag>vendor</tag>
            <value>ZTE</value>
        </tag>
    </tags>
</trigger>
```

```xml
<trigger>
    <name>ONU {#ONUID} no slot {#SNMPINDEX}: Fibra optica rompida (LOS)</name>
    <expression>...</expression>
    <priority>HIGH</priority>
    <tags>
        <tag>
            <tag>scope</tag>
            <value>OLT</value>
        </tag>
        <tag>
            <tag>tipo</tag>
            <value>LOS</value>
        </tag>
        <tag>
            <tag>servico</tag>
            <value>GPON</value>
        </tag>
        <tag>
            <tag>onu_id</tag>
            <value>{#ONUID}</value>
        </tag>
        <tag>
            <tag>slot</tag>
            <value>{#SNMPINDEX}</value>
        </tag>
    </tags>
</trigger>
```

---

## 8. Tags Legadas — Plano de Migração

As tags abaixo existem em triggers criadas antes deste padrão e devem ser substituídas gradualmente:

| Tag legada      | Substituir por                          |
|-----------------|-----------------------------------------|
| `PONDOWN=PONDOWN` | `tipo=Conectividade`                  |
| `PONZTE=PONZTE`   | `vendor=ZTE`                          |
| `PONHW=PONHW`     | `vendor=Huawei`                       |
| `PONFH=PONFH`     | `vendor=FiberHome`                    |
| `ONUDEDICADO=ONUDEDICADO` | `tipo=Conectividade` (manter cliente específico no nome da trigger) |
| `Application=GPON` | `servico=GPON`                       |
| `Scope=OLT`        | `scope=OLT`                          |
| `Tipo=LOS`         | `tipo=LOS`                           |
| `Vendor=ZTE`       | `vendor=ZTE`                         |
| `PON={#PONNAME}`   | `pon={#PONNAME}`                     |
| `Alias={#PONDESC}` | `pon_desc={#PONDESC}`               |

> **Nota:** As tags com inicial maiúscula (`Vendor`, `Scope`, `Tipo`, `PON`) foram criadas antes deste padrão. Triggers novas devem usar minúsculas. Triggers existentes serão normalizadas na próxima exportação de template.
