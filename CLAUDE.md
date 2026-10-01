# Regras do projeto zabbix-templates / OLT NETSTREAM

## OBRIGATÓRIO: Consultar guia de erros antes de editar qualquer XML

**Regra**: antes de realizar qualquer edição em template XML (item, trigger, discovery, preprocessing, graph, valuemap), consultar obrigatoriamente:

```
zabbix-server/docs/TROUBLESHOOTING_XML_IMPORT.md
```

**Por quê**: o arquivo documenta 13+ erros já encontrados em imports (status numérico, uuid ausente, snmp_community faltando, valuemaps fora do template, etc.). Consultar antes evita repetir os mesmos erros e retrabalho de commit/push/reimport.

**Checklist mínimo antes de commitar qualquer XML**:
- [ ] Versão 4.4: itens ativos sem `<status>`, tipo `SNMPV2`, `<snmp_community>` presente
- [ ] Versão 6.0: `<status>DISABLED</status>` (não numérico), `<uuid>` em toda entidade, `<valuemaps>` dentro de `<template>`
- [ ] Ambas: `<params>` presente em todo `<step>` de preprocessing, aplicações declaradas no bloco `<applications>`

**Regra**: ao encontrar qualquer erro novo durante import de template, registrar imediatamente no `TROUBLESHOOTING_XML_IMPORT.md` antes de commitar a correção — incluindo mensagem exata do erro, causa e solução. O arquivo deve ser atualizado no mesmo commit que corrige o problema.

---

## OBRIGATÓRIO: Tags em todas as triggers

**Regra global**: toda trigger em qualquer template (OLT, Switch, Retificadora, DNS, etc.) deve ter tags estruturadas para que possam ser filtradas independentemente em actions, dashboards e relatórios. Tags sem valor semântico (ex: `nome=trigger`) são inúteis — cada tag deve permitir filtrar um grupo de triggers por critério.

**Tags obrigatórias em toda trigger**:

| Tag | Obrigatória | Valores de exemplo |
|---|---|---|
| `scope` | Sim | `OLT`, `ELETRICA`, `SWITCH`, `DNS` |
| `tipo` | Sim | `Falta_Energia`, `Bateria`, `LOS`, `DyingGasp`, `Queda_Total`, `Link_Down` |
| `notificar` | Sim | `telegram`, `nao` |

**Tags adicionais quando aplicável** (permitem filtros específicos em actions):

| Tag | Quando usar | Exemplo |
|---|---|---|
| `percentual` | Triggers de bateria por nível | `80`, `50`, `30`, `15`, `5`, `1` |
| `pon` | Triggers de PON (discovery) | `{#NETSTREAM.PON_NAME}` |
| `servico` | Serviço específico | `GPON`, `SNMP` |

**No XML** (dentro de `<trigger>`):
```xml
<tags>
    <tag><tag>scope</tag><value>ELETRICA</value></tag>
    <tag><tag>tipo</tag><value>Falta_Energia</value></tag>
    <tag><tag>notificar</tag><value>telegram</value></tag>
</tags>
```

**No Zabbix UI** (trigger.update via API): campo `tags` como array de objetos `{"tag": "scope", "value": "OLT"}`.

**Por quê**: sem tags, actions precisam filtrar por nome de trigger (frágil, quebra com renomes). Com tags `tipo=LOS` e `notificar=telegram`, uma action única envia Telegram para todos os LOS independente do template ou OLT. Permite filtrar alertas por equipamento (scope), por tipo de evento (tipo) e por canal de notificação (notificar) de forma independente.

**Checklist antes de commitar qualquer trigger**:
- [ ] Tag `scope` presente
- [ ] Tag `tipo` presente  
- [ ] Tag `notificar` presente (`telegram` ou `nao`)
- [ ] Tags adicionais aplicáveis ao contexto

---

## PROIBIDO: Importar template ou modificar Zabbix sem permissão do usuário

**Regra**: **nunca** importar template, alterar configuração, modificar host, criar item ou fazer qualquer mudança em qualquer instância Zabbix (produção ou homologação) sem aprovação **explícita** do usuário naquela conversa.

**Por quê**: mudanças no Zabbix em produção afetam monitoramento ao vivo — falsos positivos, itens não suportados, triggers disparando. O usuário decide quando e qual ambiente recebe a mudança.

**Fluxo obrigatório**:
1. Editar XML localmente e fazer commit + push no GitHub
2. Apresentar ao usuário o que foi alterado e **aguardar autorização** para importar
3. Só importar após OK explícito ("pode importar", "aplica no WOW", "pode subir em produção", etc.)

**Exceção**: correção emergencial de incidente ativo com OK explícito do usuário na hora.

---

## Fluxo obrigatório para novas funcionalidades

**Regra**: qualquer adição de funcionalidade nova (item, trigger, script, discovery) deve ser feita **apenas no repositório GitHub** (edição local + commit + push). Nunca aplicar diretamente no servidor de produção (sem SQL direto, sem import manual em produção, sem editar scripts em produção).

**Por quê**: o usuário decide quando aplicar em produção conforme a necessidade operacional. Aplicações diretas no servidor criam divergência entre repositório e produção e podem gerar problemas no ambiente ao vivo.

**Fluxo correto**:
1. Editar XMLs e scripts localmente no repositório
2. Commit + push para o GitHub
3. Usuário importa/aplica no momento que julgar adequado

**Exceção**: correções emergenciais de incidente ativo (com OK explícito do usuário para mexer em produção na hora).

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

## OBRIGATÓRIO: equalizar itens entre todas as marcas de OLT

**Regra**: todos os templates de OLT (ZTE, Fiberhome, Huawei, Datacom) devem ser mantidos equalizados com os mesmos tipos de item, chaves (`key`) e nomenclatura de nome para itens equivalentes. O template ZTE é a referência canônica.

**Padrão obrigatório de chaves para ONU Dedicada**:
```
netstream.dedicado.lan.status[{#SNMPINDEX}]
netstream.dedicado.lan.speed[{#SNMPINDEX}]
netstream.dedicado.lan.duplex[{#SNMPINDEX}]
netstream.dedicado.rxpower[{#SNMPINDEX}]
netstream.dedicado.distance[{#SNMPINDEX}]
netstream.onu.status.[{#SNMPINDEX}]
```

**Padrão obrigatório de nomes de item**:
```
ONU Dedicada {#NETSTREAM.ONU_DESC}: LAN 1 Status
ONU Dedicada {#NETSTREAM.ONU_DESC}: LAN 1 Velocidade Negociada
ONU Dedicada {#NETSTREAM.ONU_DESC}: LAN 1 Modo Duplex
ONU Dedicada {#NETSTREAM.ONU_DESC}: Potencia RX (dBm)
ONU Dedicada {#NETSTREAM.ONU_DESC}: Distancia (m)
ONU Dedicada {#NETSTREAM.ONU_DESC}: Status atual
```

**Tags obrigatórias nos itens de ONU Dedicada**:
- Item prototype: `Application = Clientes Dedicados - LAN` (LAN), `Application = Clientes Dedicados` (demais)
- Trigger prototype:
  ```
  scope    = OLT
  servico  = GPON
  tipo     = ONU_Dedicada
  notificar = nao
  ```

**Por quê**: dashboards e filtros de alerta no Zabbix e Grafana dependem de chaves e nomes consistentes. Se uma marca usa `onu.status.state.onu.lan` e outra usa `netstream.dedicado.lan.status`, não é possível criar um dashboard unificado nem um filtro de alerta por tag.

**O que fazer quando a MIB de uma marca não suporta um item**: adicionar o item como `status=DISABLED` com o OID correto para aquela marca (ou `0` se desconhecido), manter a chave e o nome padronizados, e registrar no backlog de `OLT/CLAUDE.md` como pendente de OID.

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

---

## 14. Monitoramento obrigatório pós-import

**Regra**: toda vez que um template for importado no Zabbix (produção ou homologação), é obrigatório monitorar o resultado por 24 horas.

**Fluxo**:
1. Aguardar ~10 minutos após o import
2. Verificar no Zabbix: items "not supported", triggers em estado "Unknown" ou disparando incorretamente
3. Repetir a verificação a cada 1 hora pelas primeiras 24 horas
4. Se encontrar problema: apresentar diagnóstico de causa raiz + proposta de correção ao usuário antes de aplicar qualquer fix

**O que verificar em cada ciclo de validação**:
- Items CALCULATED com "not supported": a fórmula pode referenciar item ausente (LLD não rodou ainda, ou host com modelo diferente do esperado)
- Triggers em estado "Desconhecido" (Unknown): item base com erro — ver coluna "Informação" no Zabbix
- Discovery rules com delay alto (ex: 1 dia): verificar se os protótipos foram criados; se não, forçar execução manual via "Executar agora"
- Triggers disparando (falso positivo) logo após import: avaliar se são legítimas ou artefato do import

**Causa frequente pós-import**: item CALCULATED que depende de itens criados por LLD. O LLD tem delay, então nos primeiros minutos/horas os itens não existem e o CALCULATED fica "not supported". Solução: forçar execução do LLD manualmente logo após o import.

---

## 15. Changelog e Versionamento

**Regra**: toda mudança no projeto (novo item, trigger, script, correção) deve:

1. **Atualizar `CHANGELOG.md`** na raiz do repositório com entrada no formato:
   ```
   ## [vX.Y.Z] - YYYY-MM-DD
   ### Added / Changed / Fixed
   - Descrição objetiva da mudança, template afetado e motivo
   ```
2. **Criar uma nova tag git** após o commit, seguindo semver:
   - `vX.Y.Z` — `X` = breaking change, `Y` = nova funcionalidade, `Z` = correção/ajuste
   - Comando: `git tag -a vX.Y.Z -m "Resumo da mudança"` + `git push origin vX.Y.Z`
3. **Publicar no GitHub** — o `CHANGELOG.md` commitado já documenta o histórico; usar a tag como release point.

**Por quê**: permite rastrear o que mudou, quando e por qual motivo, tanto no repositório quanto no histórico de releases do GitHub. Facilita rollback e auditoria de incidentes.

**Checklist de versionamento** (obrigatório a cada mudança):
- [ ] `CHANGELOG.md` atualizado com versão, data e descrição
- [ ] Commit criado com mensagem clara referenciando o template/script alterado
- [ ] Tag `vX.Y.Z` criada e pushed para o GitHub

---

## 15. Testes com Sub-agente

**Regra**: ao implementar qualquer nova funcionalidade (novo item, script externo, discovery rule, trigger), acionar um sub-agente para executar os testes antes de considerar a tarefa concluída.

**O que o sub-agente deve testar**:
- Script externo: executar manualmente no servidor Zabbix com parâmetros reais e validar saída JSON
- Item SNMP/SSH: verificar se o item coleta dados (`item not supported` = falha)
- Trigger: confirmar que dispara e recupera corretamente com dados simulados ou reais
- LLD: confirmar que a discovery cria os protótipos esperados

**Como acionar**: usar o Agent tool com `subagent_type="claude"` passando: servidor SSH, chave, host de teste, item key e critério de sucesso esperado.

**Por quê**: evita que funcionalidades cheguem a produção sem validação — o histórico do projeto tem casos de scripts deployados que silenciosamente retornavam vazio ou triggers que nunca disparavam por erro de expressão.
