# Regras do projeto zabbix-templates / OLT NETSTREAM

## Trigger de status de interface (uplink / link down)

**Regra**: Trigger de link DOWN em uplinks OLT deve usar `max(#3)=2 and diff()=1` — nunca apenas `last()=2` ou `max(#3)=2` sozinho.

**Por quê**: `max(#3)=2` sozinho gera alerta imediato em interfaces que já estavam DOWN antes do monitoramento começar (falso positivo). O `diff()=1` garante que o status mudou — ou seja, só alerta quando a interface estava UP e ficou DOWN.

**Aplica a**: todos os templates OLT (ZTE, Fiberhome, Huawei) e qualquer discovery que monitore status de interface. Valido para qualquer item de status `ifOperStatus`, `netstream.uplink.status`, etc.

**Expressão correta** (trigger prototype de discovery):
```
{TEMPLATE:item.status.max(#3)}=2 and {TEMPLATE:item.status.diff()}=1 and {TEMPLATE:item.status.count(10m)}>1
```

**Por que o `count(10m)>1`**: quando um item passa de "not supported" para coleta ativa (ex: após correção de SNMP), a primeira amostra é tratada como mudança — `diff()=1` dispara mesmo que a interface já estivesse DOWN. O `count(10m)>1` garante que o item tem pelo menos 2 amostras coletadas (≥3min com delay=3m) antes de alertar, eliminando falsos positivos na ativação.

---

## Trigger de saturação de porta (90%)

- Guarda `ifHighSpeed` como item `netstream.uplink.ifspeed[{#SNMPINDEX}]` com preprocessing MULTIPLIER 125000 (Mbps → Bps)
- Trigger: `last(ifspeed)>0 and min(in.bps, 5m)/last(ifspeed)>0.9 or min(out.bps, 5m)/last(ifspeed)>0.9`
- Prioridade HIGH, manual_close=YES

**Limitação Zabbix 4.4**: templates com múltiplas discovery rules usando `{#SNMPINDEX}` não aceitam trigger prototype via XML import ("multiple discovery rules"). Nesses casos, criar via MySQL diretamente (inserir em `triggers`, `functions`, `trigger_tag`).

---

## Trigger de nodata

- Sempre criar com `status=1` (DISABLED) por padrão — evita falso positivo após import
- Ativar manualmente após confirmar que o item está coletando dados

---

## Warmup obrigatório em triggers de discovery PON

- Todo trigger que usa dados de discovery PON deve ter `count(180)>1` antes da condição principal
- Evita alertas nas primeiras coletas após import ou restart do Zabbix

---

## Conflito prototype vs standalone no import

- Erro "No permissions to referred object" = item mudou de prototype para standalone (ou vice-versa)
- Solução: deletar o item conflitante antes de importar
- Ver: feedback_zabbix_import_prototype_conflict.md

---

## Padrão de nomenclatura de scripts externos OLT

**Regra**: ponto como separador em todos os scripts — nunca underscore.

**Shell scripts** (external check Zabbix — chamados pela chave do item):
```
netstream.gpon.pon.FUNCAO.OLT
```
Exemplos: `netstream.gpon.pon.discovery.zte`, `netstream.gpon.pon.status.fiberhome`, `netstream.gpon.pon.total.huawei`

**Scripts Python** (chamados internamente pelos shell scripts):
```
pon.FUNCAO.OLT.py
```
Exemplos: `pon.discovery.zte.py`, `pon.status.fiberhome.py`, `pon.total.huawei.py`

**Chaves dos itens Zabbix** (devem bater com o nome do shell script):
```
netstream.gpon.pon.FUNCAO.OLT[{HOST.IP},{$SNMP_COMMUNITY}]
```

**OLTs válidas**: `zte`, `fiberhome`, `huawei`

**Fluxo**: Template → chave → shell script → Python script

**Aplica a**: qualquer novo script adicionado em `OLT/externalscripts/`
