# Zabbix Actions — OLT ZTE (LOS por Fibra)

Criado em: 2026-08-16  
Aplica-se a: **todos os hosts do grupo `OLT-NETSTREAM`** (não apenas ZTE)

---

## Actions criadas via API

| ID | Nome | Status |
|----|------|--------|
| 47 | Telegram - LOS Queda PARCIAL por Fibra | Ativa |
| 48 | Telegram - LOS Queda TOTAL por Fibra | Ativa |

**Destino:** `Telegram Group PON STATUS` (userid=18) via media type `Telegram` (id=4)

---

## Condições (AND)

| Tipo | Operador | Valor |
|------|----------|-------|
| Host group (0) | = | OLT-NETSTREAM (groupid=112) |
| Trigger name (3) | contém | `Queda PARCIAL por LOS` / `Queda TOTAL por LOS` |

---

## Trigger prototypes associados

Criados na discovery rule `netstream.gpon.pon.discovery.zte[{HOST.IP},{$SNMP_COMMUNITY}]` (itemid=511071, template 10902):

| ID | Nome | Expressão resumida | Prioridade |
|----|------|-------------------|------------|
| 132853 | PON {#NETSTREAM.PON_NAME}: Queda PARCIAL por LOS (Fibra) | `online>0 AND delta(los,900)>=3 AND auth>0` | HIGH (4) |
| 132859 | PON {#NETSTREAM.PON_NAME}: Queda TOTAL por LOS (Fibra) | `online=0 AND delta(los,900)>=1 AND auth.max(86400)>0` | DISASTER (5) |

Tags dos trigger prototypes:
```
scope=OLT, servico=GPON, pon={#NETSTREAM.PON_NAME}, tipo=LOS_Parcial|LOS_Total, notificar=telegram
```

---

## Mensagens Telegram

### Problema — LOS Parcial (action 47, operation 125)
```
Assunto: LOS PARCIAL - {HOST.NAME}

QUEDA PARCIAL POR FIBRA (LOS)

[OLT]: {HOST.HOST}
[POP]: {HOST.DESCRIPTION}
[PON]: {EVENT.TAGS.pon}

ONUs online: {ITEM.VALUE1}
LOS detectados: {ITEM.VALUE2}
Autorizadas: {ITEM.VALUE3}

{EVENT.DATE} {EVENT.TIME}
ID: {EVENT.ID}
```

### Recuperação — LOS Parcial (operation 127)
```
Assunto: LOS NORMALIZADO - {HOST.NAME}

LOS NORMALIZADO

[OLT]: {HOST.HOST}
[PON]: {EVENT.TAGS.pon}

Duração: {EVENT.DURATION}
ID: {EVENT.ID}
```

### Problema — LOS Total (action 48, operation 126)
```
Assunto: LOS TOTAL - {HOST.NAME}

QUEDA TOTAL POR FIBRA (LOS)

[OLT]: {HOST.HOST}
[POP]: {HOST.DESCRIPTION}
[PON]: {EVENT.TAGS.pon}

ONUs online: 0 (PON INATIVA)
LOS detectados: {ITEM.VALUE2}
Autorizadas: {ITEM.VALUE3}

{EVENT.DATE} {EVENT.TIME}
ID: {EVENT.ID}
```

### Recuperação — LOS Total (operation 128)
```
Assunto: PON RESTABELECIDA - {HOST.NAME}

PON RESTABELECIDA

[OLT]: {HOST.HOST}
[PON]: {EVENT.TAGS.pon}

Duração da queda: {EVENT.DURATION}
ID: {EVENT.ID}
```

---

## Items usados nas mensagens

`{ITEM.VALUE1}` = `netstream.gpon.pon.calc.online.zte[{#NETSTREAM.PON_INDEX}]`  
`{ITEM.VALUE2}` = `netstream.gpon.pon.calc.los.zte[{#NETSTREAM.PON_INDEX}]`  
`{ITEM.VALUE3}` = `netstream.gpon.pon.auth.zte[{#NETSTREAM.PON_INDEX}]`

---

## Semântica

- **LOS Parcial:** PON ainda tem ONUs online mas houve aumento de ≥3 LOS em 15min → ramo de fibra, splitter ou conector afetado
- **LOS Total:** PON completamente offline + incremento de LOS → fibra principal cortada

- `delta(los, 900)` = max−min dos últimos 15min no item calc.los
- `max(86400)>0` garante que a PON já teve ONUs em 24h (evita alertar em PONs vazias)
- `manual_close=YES` em ambos — operador precisa fechar explicitamente após resolver

---

## Recriar via API (se necessário)

Script de referência em `/tmp/create_los_actions.py` no servidor Zabbix.  
Recriar trigger prototypes: usar `triggerprototype.create` na discovery `511071` com as expressões acima.
