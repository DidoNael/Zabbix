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

- Guarda `ifHighSpeed` como item `netstream.uplink.ifspeed[{#SNMPINDEX}]` com preprocessing MULTIPLIER 1000000 (Mbps → bps)
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

---

## Grupos de host obrigatórios nos templates

**Regra**: todo template deve definir ao menos dois grupos de host:
1. `NETSTREAM` — grupo padrão para todos os templates
2. `NETSTREAM/MARCA` — subgrupo com o nome da marca em maiúsculo

**Exemplos válidos**:
- `NETSTREAM` + `NETSTREAM/DATACOM`
- `NETSTREAM` + `NETSTREAM/HUAWEI`
- `NETSTREAM` + `NETSTREAM/ZTE`
- `NETSTREAM` + `NETSTREAM/CISCO`
- `NETSTREAM` + `NETSTREAM/FIBERHOME`

**No XML Zabbix 4.4**:
```xml
<groups>
    <group>
        <name>NETSTREAM</name>
    </group>
    <group>
        <name>NETSTREAM/DATACOM</name>
    </group>
</groups>
```

**Aplica a**: todos os templates (OLT, Switch, Roteador, DNS-Monitor, etc.)

---

## Porta SNMP em item prototypes — nunca hardcode

**Regra**: item prototypes SNMP nunca devem ter `<port>` definida no XML. Se definida, ao importar o template, os itens criados pelo LLD herdam essa porta e ignoram a porta configurada na interface do host.

**Sintoma**: itens criados pelo LLD não coletam dados mesmo com SNMP funcionando — o `snmpget` manual responde, mas o Zabbix dá timeout. No DB: `SELECT port FROM items WHERE hostid=X` retorna `161` mesmo com a interface do host em outra porta.

**Correção em produção** (quando itens já foram criados com porta errada):
```bash
DBPASS=$(grep "^DBPassword" /etc/zabbix/zabbix_server.conf | cut -d= -f2)
mysql -uzabbix -p"$DBPASS" zabbix << SQL
UPDATE items SET port="" WHERE hostid=HOSTID AND key_ LIKE "%PREFIXO%" AND key_ NOT LIKE "%{#%";
SQL
```

**No XML**: nunca incluir `<port>` dentro de `<item_prototype>`. A porta deve estar somente na interface do host no Zabbix.

---

## OBRIGATÓRIO: sincronizar 4.4 e 6.0 a cada mudança

**Regra**: qualquer alteração em um template ZTE (ou Fiberhome/Huawei) **deve ser aplicada nas duas versões** — `4.4/` e `6.0/` — no mesmo commit. Nunca commitar uma versão sem equalizar a outra.

**Por quê**: já perdemos tempo corrigindo falsos positivos em produção porque o fix existia no 4.4 mas não no 6.0 (ou vice-versa). Ambas as versões são usadas em produção — clientes novos sobem 6.0, legados rodam 4.4.

**O que muda entre versões** (só sintaxe, lógica idêntica):

| Elemento | Zabbix 4.4 | Zabbix 6.0 |
|---|---|---|
| Expressão de trigger | `{HOST:item.func(param)}` | `func(/HOST/item,param)` |
| `delta(900)` | `{HOST:item.delta(900)}` | `(max(/HOST/item,900)-min(/HOST/item,900))` |
| `diff()` | `{HOST:item.diff()}` | `diff(/HOST/item)` |
| `change()` | `{HOST:item.change()}` | `change(/HOST/item)` |
| `count(10m)` | `{HOST:item.count(10m)}` | `count(/HOST/item,10m)` |
| `nodata(5m)` | `{HOST:item.nodata(5m)}` | `nodata(/HOST/item,5m)` |
| `<recovery_mode>` (XML) | `RECOVERY_EXPRESSION` | `RECOVERY_EXPRESSION` (igual) |
| `<dependencies>` (XML) | `<name>` + `<expression>` no formato 4.4 | `<name>` + `<expression>` no formato 6.0 |

**Checklist ao editar qualquer trigger prototype**:
- [ ] Nome do trigger igual nas duas versões (incluindo macros como `{#NETSTREAM.PON_DESC}`)
- [ ] Lógica idêntica (expressão, recovery, manual_close, priority, tags)
- [ ] Dependências replicadas nas duas versões
- [ ] Ambos os arquivos no mesmo commit e push
