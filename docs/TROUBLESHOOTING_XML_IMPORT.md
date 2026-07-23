# Guia de Troubleshooting: Erros Comuns na Importação de Templates XML no Zabbix

Este guia documenta os erros mais frequentes de validação XML ao importar ou modificar
templates nas versões 4.4, 5.x e 6.0+ do Zabbix, e as regras estritas que devem ser
seguidas para evitá-los.

> **Erros 1–6**: específicos do Zabbix 4.4/5.x. **Erros 7–11**: específicos do Zabbix 6.0+
> ou comuns a ambas as versões.

---

## 1. Erro na Tag `<status>` em Triggers e Itens Ativos (`C44XmlValidator`)

### Mensagem de Erro:
```text
Tag inválida "/zabbix_export/templates/template(1)/items/item(X)/status": unexpected constant "0" (ou "1").
```
```text
CXmlValidatorGeneral->validateConstant() in include/classes/import/validators/CXmlValidatorGeneral.php:85
```

### Causa:
No esquema oficial XML de exportação do **Zabbix 4.4**, entidades que estão **ATIVAS (Enabled)** — como `<trigger>`, `<item>` e `<discovery_rule>` — **não devem possuir a tag `<status>0</status>`**. A inclusão de `<status>0</status>` faz com que o validador `C44XmlValidator` rejeite a importação com `unexpected constant "0"`. Apenas itens explicitamente desativados utilizam `<status>1</status>`.

### Como Prevenir / Solucionar:
- Em templates compatíveis com Zabbix 4.4, **omita completamente a tag `<status>`** de qualquer `<item>`, `<trigger>` ou `<discovery_rule>` que esteja ativo por padrão.

---

## 2. Tags SNMP em Itens ou Regras de Descoberta do tipo `EXTERNAL`

### Mensagem de Erro:
```text
Tag inválida "/zabbix_export/templates/template(1)/discovery_rules/discovery_rule(X)/snmp_oid": unexpected tag.
```

### Causa:
Ao modificar uma regra de descoberta (`<discovery_rule>`) ou item (`<item>`) do tipo `SNMPV2` para `EXTERNAL` (script externo), tags exclusivas de SNMP como `<snmp_oid>` e `<snmp_community>` foram mantidas no XML.

### Como Prevenir / Solucionar:
Sempre que definir `<type>EXTERNAL</type>`, remova completamente as tags `<snmp_oid>` e `<snmp_community>` do bloco XML.
Exemplo correto para `EXTERNAL`:
```xml
<discovery_rule>
    <name>Discovery | Network interfaces | Sinal optico single lan</name>
    <type>EXTERNAL</type>
    <key>discovery_huawei_optical.sh["{HOST.CONN}","{$SNMP_COMMUNITY}","single"]</key>
    <delay>1h</delay>
...
```

---

## 3. Tag `<params>` Ausente em Etapas de Pré-processamento

### Mensagem de Erro:
```text
Tag inválida ".../preprocessing/step(1)": a tag "params" está ausente.
```

### Causa:
Etapas de pré-processamento (`<step>`) que utilizam tipos como `REGEX`, `JAVASCRIPT`, `MULTIPLIER` ou `STR_REPLACE` exigem obrigatoriamente a tag `<params>` preenchida.

### Como Prevenir / Solucionar:
Mesmo quando o parâmetro for simples, declare explicitamente a tag `<params>` dentro de cada `<step>` do pré-processamento.

---

## 4. Aplicação Ausente ou ID Inválido (`Aplicação com ID "" não está disponível`)

### Mensagem de Erro:
```text
Aplicação com ID "" não está disponível no "OLT ZTE - NETSTREAM".
```

### Causa:
No Zabbix 4.4/5.0, protótipos de itens (`<item_prototype>`) vinculados a aplicações exigem que a aplicação referenciada na tag `<applications><application><name>NOME</name></application></applications>` esteja devidamente declarada no bloco global `<applications>` do template.

### Como Prevenir / Solucionar:
Sempre verifique se todos os nomes de aplicações listados nos itens e protótipos estão cadastrados na lista `<applications>` no topo do XML do template.

---

## 5. Tipo de Item SNMP (`SNMP_AGENT` vs `SNMPV2`)

### Mensagem de Erro:
```text
Tag inválida "/zabbix_export/templates/template(1)/items/item(X)/type": unexpected constant "SNMP_AGENT".
```

### Causa:
O Zabbix 6.0+ unificou os itens SNMP v1/v2c/v3 sob a constante `<type>SNMP_AGENT</type>`. No entanto, o **Zabbix 4.4 e 5.0** exigem que itens SNMPv2c utilizem a constante `<type>SNMPV2</type>`.

### Como Prevenir / Solucionar:
Em templates exportados para o Zabbix 4.4 (`ZABBIX_EXPORT_VERSION = '4.4'`), todos os itens e regras SNMP devem possuir a tag `<type>SNMPV2</type>`. Nunca utilize `SNMP_AGENT` em templates da versão 4.4.

---

## 6. Comunidade SNMP Ausente em Itens `SNMPV2` (`CItemGeneral->checkInput()`)

### Mensagem de Erro:
```text
Não foi especificada a comunidade SNMP. [... CApiService::exception() in include/classes/api/services/CItemGeneral.php:565]
```

### Causa:
No Zabbix 6.0+ (`SNMP_AGENT`), a comunidade SNMP é herdada diretamente das configurações de interface do Host e é omitida no XML do item. No entanto, no **Zabbix 4.4 e 5.0**, cada item, protótipo de item ou regra de descoberta do tipo `SNMPV2` exige obrigatoriamente a tag `<snmp_community>{$SNMP_COMMUNITY}</snmp_community>`.

### Como Prevenir / Solucionar:
Em todos os elementos com `<type>SNMPV2</type>` no Zabbix 4.4, adicione sempre a tag `<snmp_community>{$SNMP_COMMUNITY}</snmp_community>`.

---

## 7. Tag `<status>` com Valor Numérico no Zabbix 6.0

### Mensagem de Erro:
```text
Invalid tag "/zabbix_export/templates/template(1)/items/item(X)/status": unexpected constant "0".
```

### Causa:
No **Zabbix 6.0+**, a tag `<status>` exige constantes textuais (`ENABLED` ou `DISABLED`),
**nunca** valores numéricos (`0` ou `1`). Isso é diferente do Zabbix 4.4, onde itens ativos
simplesmente omitem a tag `<status>`.

### Como Prevenir / Solucionar:
- **Itens/discovery rules ativos**: omita a tag `<status>` por completo (o padrão é
  `ENABLED`).
- **Itens/discovery rules desativados**: use `<status>DISABLED</status>`.
- **Nunca** use `<status>0</status>` ou `<status>1</status>` em templates 6.0.

> **Atenção:** não remova `<status>DISABLED</status>` de entidades que devem permanecer
> desativadas — remover a tag as **ativaria** indevidamente.

---

## 8. Tag `<uuid>` Ausente em Entidades do Template (Zabbix 6.0)

### Mensagem de Erro:
```text
Invalid tag "/zabbix_export/templates/template(1)/discovery_rules/discovery_rule(1)": the tag "uuid" is missing.
```

### Causa:
O Zabbix 6.0 exige a tag `<uuid>` como **primeiro filho** de toda entidade dentro de um
template: `template`, `item`, `discovery_rule`, `item_prototype`, `trigger`,
`trigger_prototype`, `graph`, `graph_prototype`, `valuemap`, etc. Templates migrados do 4.4
frequentemente não possuem essa tag.

### Como Prevenir / Solucionar:
Gere UUIDs **determinísticos** (uuid5 com namespace fixo + identificador da entidade —
`key`, `name` ou `expression`) para que re-gerações produzam os mesmos valores e não poluam
o diff. Exemplo em Python:
```python
import uuid
NS = uuid.UUID("6ba7b810-9dad-11d1-80b4-00c04fd430c8")
seed = "template_name|entity_type|key=minha.chave"
u = uuid.uuid5(NS, seed).hex  # 32 hex chars, sem hífens
```
O `<uuid>` deve ser a **primeira** tag filha do elemento, antes de `<name>`, `<key>`, etc.

---

## 9. Tag `<uuid>` Inesperada Dentro de `<graph_item>/<item>` (Zabbix 6.0)

### Mensagem de Erro:
```text
Invalid tag "/zabbix_export/templates/template(1)/graph_prototypes/graph_prototype(1)/graph_items/graph_item(1)/item": unexpected tag "uuid".
```

### Causa:
Dentro de `<graph_items>`, a referência `<item>` é um **ponteiro** para um item existente
(apenas `<host>` + `<key>`), **não** uma definição completa. A tag `<uuid>` não é permitida
nesse contexto — ela só é válida na **definição** do item/prototype, não na referência.

### Como Prevenir / Solucionar:
Remova qualquer `<uuid>` que esteja dentro de `<graph_item>/<item>`. A estrutura correta é:
```xml
<graph_item>
    <drawtype>GRADIENT_LINE</drawtype>
    <color>1A7C11</color>
    <item>
        <host>Template Switch Huawei 6700 Series - Netstream</host>
        <key>netstream.optical.rx[{#ENTPHYSICALNAME}]</key>
    </item>
</graph_item>
```

---

## 10. "No permissions to referred object or it does not exist!" (Zabbix 6.0)

### Mensagem de Erro:
```text
Import failed.
* No permissions to referred object or it does not exist!
```

### Causa:
Erro genérico que indica que o XML referencia algo que **não existe no servidor de destino**
ou que o usuário importador **não tem permissão** para acessar. As causas mais comuns (em
ordem de frequência):

1. **Host group inexistente**: o template referencia `<group><name>Templates</name></group>`,
   mas no servidor de destino o grupo pode ter outro nome (ex.: `Templates/Network devices`).
2. **UUID de host group divergente**: o XML declara um UUID para o grupo na seção
   `<groups>` do topo do export, e esse UUID não corresponde ao do grupo homônimo no
   servidor. O Zabbix tenta localizar pelo UUID primeiro.
3. **Usuário sem permissão ao grupo**: o usuário que importa não tem leitura/escrita no host
   group referenciado (verificar: Administration → User groups → permissões).
4. **Valuemap com UUID conflitante**: um valuemap com o mesmo nome mas UUID diferente já
   existe no servidor (comum após migração 4.4 → 6.0).
5. **Template linkado inexistente**: se o XML possui `<templates>` linkados na seção de
   dependências, e eles não existem no destino.

### Como Diagnosticar:
1. **Validar referências internas** com o script `xref.py` (na raiz do repositório ou em
   `/tmp`). Se retornar zero referências quebradas, o problema é no servidor.
2. **Verificar o grupo** no servidor: Administration → Host groups → procurar o grupo
   exato referenciado no XML.
3. **Comparar UUIDs**: no XML do export, o UUID do grupo está em
   `<zabbix_export><groups><group><uuid>`. Compare com o UUID do grupo no servidor (via API
   ou exportando um template existente do servidor).
4. **Testar com Super Admin**: se funcionar com Super Admin mas não com o usuário normal, é
   permissão.

### Como Prevenir / Solucionar:
- **Grupo inexistente**: crie o grupo no servidor antes de importar, ou altere o `<name>`
  no XML para corresponder ao grupo existente.
- **UUID divergente**: substitua o UUID do grupo no XML pelo UUID real do servidor, ou
  remova a seção `<groups>` do topo do export (mantendo apenas a referência dentro do
  `<template>`).
- **Permissão**: conceda ao usuário acesso Read-write ao host group via
  Administration → User groups.
- **Valuemap**: exporte um template do servidor 6.0, compare os UUIDs dos valuemaps
  homônimos, e alinhe no XML a ser importado.

---

## 11. `{ITEM.LASTVALUEN}` com Índice Incorreto nos Triggers

### Sintoma:
Triggers exibem `*UNKNOWN*` em vez do valor esperado no nome ou nas tags. Não é um erro de
importação — o template importa normalmente, mas o trigger não resolve a macro.

### Causa:
A macro `{ITEM.LASTVALUEN}` referencia o N-ésimo item **na ordem em que aparecem na
expressão do trigger**. Se a expressão usa 3 itens, o índice máximo válido é `3`. Um índice
`4` retorna `*UNKNOWN*`.

### Como Diagnosticar:
Conte os itens distintos (pares `host:key`) na expressão do trigger. Exemplo:
```
{Template:BgpPeerState.last()}=1
  and {Template:BgpPeerAdminStatus.last()}=2
  and {Template:get_asn_owner_v2.sh[{#IP}].strlen()}>0
```
São 3 itens → índices válidos: `{ITEM.LASTVALUE1}` a `{ITEM.LASTVALUE3}`.

### Como Prevenir / Solucionar:
Ajuste o índice da macro para corresponder à posição real do item na expressão.

---

## 12. Sintaxe de `<params>` em Itens Calculados (Zabbix 6.0)

### Mensagem de Erro:
```text
Parâmetro inválido "/N/params": uso incorreto da função "last".
```

### Causa:
Itens do tipo `CALCULATED` (`<type>CALCULATED</type>`) usam uma fórmula na tag `<params>`.
No **Zabbix 4.4/5.0**, a sintaxe para referenciar um item do mesmo host era:
```
last("key")
```
No **Zabbix 6.0**, a sintaxe mudou para:
```
last(//key)
```
O `//` significa "host atual". Para referenciar um host específico: `last(/hostname/key)`.

### Como Prevenir / Solucionar:
Substitua todas as ocorrências de `last("key")` por `last(//key)` nos `<params>` de itens
calculados em templates 6.0. O mesmo vale para outras funções de série temporal usadas em
`<params>`: `min`, `max`, `avg`, `sum`, `count`, etc.

---

## Checklist de Validação Antes do Commit

### Zabbix 4.4
1. [ ] Nenhum `<trigger>`, `<item>` ou `<discovery_rule>` ativo possui tag `<status>`.
2. [ ] Itens SNMP utilizam `<type>SNMPV2</type>` (e não `SNMP_AGENT`).
3. [ ] Todos os itens `<type>SNMPV2</type>` possuem `<snmp_community>{$SNMP_COMMUNITY}</snmp_community>`.
4. [ ] Regras e itens `<type>EXTERNAL</type>` não possuem tags `<snmp_oid>` ou `<snmp_community>`.
5. [ ] Todos os `<step>` de pré-processamento possuem `<params>`.
6. [ ] Aplicações referenciadas nos itens estão declaradas no bloco `<applications>` do template.

### Zabbix 6.0
7. [ ] `<status>` usa constante textual (`ENABLED`/`DISABLED`), nunca numérica.
8. [ ] Toda entidade do template possui `<uuid>` como primeiro filho e é UUIDv4 (13° hex = `4`).
9. [ ] Referências `<item>` dentro de `<graph_item>` **não** possuem `<uuid>`.
10. [ ] Host group referenciado existe no servidor de destino com mesmo nome.
11. [ ] UUIDs de valuemaps, host groups e templates linkados são compatíveis com o servidor.
12. [ ] Índices `{ITEM.LASTVALUEN}` nos triggers correspondem à contagem real de itens na expressão.
13. [ ] `<params>` de itens `CALCULATED` usam sintaxe 6.0: `last(//key)` e não `last("key")`.

### Ambas as versões
13. [ ] O encoding do arquivo XML está em UTF-8 sem BOM e indentado corretamente.
14. [ ] Rodar `xref.py` confirma zero referências internas quebradas.


