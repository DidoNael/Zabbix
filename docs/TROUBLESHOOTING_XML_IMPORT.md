# Guia de Troubleshooting: Erros Comuns na Importação de Templates XML no Zabbix

Este guia documenta os erros mais frequentes de validação XML (`CXmlValidatorGeneral`) ao importar ou modificar templates nas versões 4.4, 5.x e 6.0+ do Zabbix, e as regras estritas que devem ser seguidas para evitá-los.

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

## Checklist de Validação Antes do Commit

Antes de publicar uma nova versão de template XML:
1. [ ] Nenhum `<trigger>`, `<item>` ou `<discovery_rule>` ativo possui tag `<status>` no Zabbix 4.4.
2. [ ] Itens SNMP no Zabbix 4.4 utilizam `<type>SNMPV2</type>` (e não `SNMP_AGENT`).
3. [ ] Todos os itens e regras `<type>SNMPV2</type>` possuem `<snmp_community>{$SNMP_COMMUNITY}</snmp_community>`.
4. [ ] Regras e itens `<type>EXTERNAL</type>` não possuem tags `<snmp_oid>` ou `<snmp_community>`.
5. [ ] Todos os `<step>` de pré-processamento possuem `<params>`.
6. [ ] O encoding do arquivo XML está em UTF-8 sem BOM e indentado corretamente.


