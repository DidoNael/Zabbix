# Guia de Troubleshooting: Erros Comuns na Importação de Templates XML no Zabbix

Este guia documenta os erros mais frequentes de validação XML (`CXmlValidatorGeneral`) ao importar ou modificar templates nas versões 4.4, 5.x e 6.0+ do Zabbix, e as regras estritas que devem ser seguidas para evitá-los.

---

## 1. Erro na Tag `<status>` em Triggers (`C44XmlValidator`)

### Mensagem de Erro:
```text
Tag inválida "/zabbix_export/templates/template(1)/items/item(5)/triggers/trigger(2)/status": unexpected constant "0" (ou "1").
```
```text
CXmlValidatorGeneral->validateConstant() in include/classes/import/validators/CXmlValidatorGeneral.php:85
```

### Causa:
No esquema oficial XML de exportação do **Zabbix 4.4**, a entidade `<trigger>` (dentro de itens ou no bloco global de triggers) **não deve possuir a tag `<status>`**. A inclusão da tag `<status>0</status>` ou `<status>1</status>` em um `<trigger>` faz com que o validador `C44XmlValidator` rejeite a importação.

### Como Prevenir / Solucionar:
- Em templates compatíveis com Zabbix 4.4, **nunca inclua a tag `<status>` dentro de elementos `<trigger>`**.
- *(Nota: Em `<trigger_prototype>` dentro de `<discovery_rule>`, a tag `<status>` aceita strings como `DISABLED` ou `ENABLED`, mas em `<trigger>` simples ela deve ser omitida)*.

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

## Checklist de Validação Antes do Commit

Antes de publicar uma nova versão de template XML:
1. [ ] Nenhum `<trigger>` possui tag `<status>` no Zabbix 4.4.
2. [ ] Regras e itens `<type>EXTERNAL</type>` não possuem tags `<snmp_oid>` ou `<snmp_community>`.
3. [ ] Todos os `<step>` de pré-processamento possuem `<params>`.
4. [ ] O encoding do arquivo XML está em UTF-8 sem BOM e indentado corretamente.
