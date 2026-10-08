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

## 13. Tag `<value_maps>` Fora do Bloco `<template>` (Zabbix 6.0)

### Mensagem de Erro:
```text
Tag inválida "/zabbix_export": tag inesperada "value_maps".
```

### Causa:
No Zabbix 6.0, `<value_maps>` deve estar **dentro** do bloco `<template>`, antes do
`</template>` de fechamento. O Zabbix 4.4 aceitava `<value_maps>` como filho direto de
`<zabbix_export>`, mas o 6.0 não aceita.

### Estrutura errada:
```xml
        </template>
    </templates>
    <value_maps>          ← fora do template
        ...
    </value_maps>
</zabbix_export>
```

### Estrutura correta:
```xml
            <value_maps>  ← dentro do <template>, antes de </template>
                ...
            </value_maps>
        </template>
    </templates>
</zabbix_export>
```

### Como Prevenir / Solucionar:
Mova o bloco para dentro do `<template>`, como último filho antes de `</template>`, **e use
o nome de tag correto para a versão**:

| Versão | Tag do container | Tag de cada item |
|--------|-----------------|-----------------|
| 4.4 | `<value_maps>` | `<value_map>` |
| 6.0 | `<valuemaps>` | `<valuemap>` |

Ocorre com frequência ao migrar templates do formato 4.4 para 6.0.

---

## 14. `zabbix[host,snmp,available]` Removido no Zabbix 7.0

### Mensagem de Erro:
```text
Incorrect item key "zabbix[host,snmp,available]" provided for trigger expression on "NOME_TEMPLATE".
```

### Causa:
O item interno `zabbix[host,snmp,available]` foi removido no Zabbix 7.0. Templates criados
para versões anteriores que usavam esse item em triggers de inacessibilidade falham ao
importar no 7.0.

### Como Prevenir / Solucionar:
Substituir pelo `nodata()` aplicado ao item de uptime do template:

```xml
<!-- Antes (inválido no 7.0) -->
<expression>max(/TEMPLATE/zabbix[host,snmp,available],1h)=0</expression>

<!-- Depois -->
<expression>nodata(/TEMPLATE/uptime_key,5m)=1</expression>
```

Onde `uptime_key` é a key do item de uptime do template. Keys por template deste projeto:

| Template | Key de uptime |
|---|---|
| OLT ZTE | `netstream.system.uptime` |
| OLT Fiberhome | `uptime` |
| OLT Huawei | `netstream.system.uptime` |
| Switch Cisco | `netstream.sysUpTime.0` |
| Switch Datacom | `netstream.sysUpTime.0` |

---

## 15. Função `diff()` Removida no Zabbix 7.0

### Mensagem de Erro:
```text
Invalid parameter "/X/expression": unknown function "diff".
```

### Causa:
A função `diff()` foi removida no Zabbix 7.0. Ela retornava `1` se o último valor
era diferente do anterior, `0` caso contrário.

### Como Prevenir / Solucionar:
Substituir `diff(/TEMPLATE/key)=1` por `change(/TEMPLATE/key)<>0`:

```xml
<!-- Antes (inválido no 7.0) -->
<expression>diff(/TEMPLATE/item)=1 and last(/TEMPLATE/item)=2</expression>

<!-- Depois -->
<expression>change(/TEMPLATE/item)<>0 and last(/TEMPLATE/item)=2</expression>
```

O mesmo vale para `recovery_expression`. Aplica-se a triggers de link DOWN, mudança
de status, e qualquer outro trigger que detecte transição de valor.

---

## 17. Descrição da Porta PON não Aparece nos Alertas (Nome do Circuito Ausente)

### Sintoma:
Triggers de PON exibem apenas o nome técnico da porta, sem o nome do circuito configurado
no equipamento:

```
# Esperado (DEV — com ifAlias):
PON gpon_1/9/2 (SOBERANA): LOS detectado (Fibra)

# Real (produção — sem ifAlias):
PON gpon_1/9/2: LOS detectado (Fibra)
```

### Causa:
O script `pon.status.zte.py` consultava apenas `ifDescr` (OID `1.3.6.1.2.1.2.2.1.2`),
que retorna o nome técnico gerado automaticamente pelo equipamento (ex: `gpon-olt_0/1/2`
ou `GPON0/1/2`) — não o nome do circuito configurado pelo operador.

O nome do circuito fica em `ifAlias` (OID `1.3.6.1.2.1.31.1.1.1.18`), que é o campo
editável em `interface description` na OLT (ex: `SOBERANA`, `BAIRRO-NORTE`). O script
não consultava esse OID, então o campo `desc` no cache ficava vazio.

Adicionalmente, o script `pon.discovery.zte.py` não exportava a macro
`{#NETSTREAM.PON_LABEL}`, que é usada nos nomes de itens e triggers do template. Sem
essa macro na saída do discovery, o Zabbix resolvia `{#NETSTREAM.PON_LABEL}` como
vazio ou apenas como `{#NETSTREAM.PON_NAME}` sem o sufixo de descrição.

> **Nota:** os scripts de Fiberhome e Huawei já consultavam `ifAlias` corretamente.
> O problema era exclusivo do ZTE.

### Como Solucionar:
1. Atualizar `pon.status.zte.py` para fazer `snmpget` de `ifAlias` após montar o
   resultado (igual ao padrão Fiberhome/Huawei):
   ```python
   alias_oids = ["1.3.6.1.2.1.31.1.1.1.18." + str(p["snmp_idx"]) for p in result]
   get_proc = subprocess.run(["snmpget", "-v2c", "-c", COMMUNITY, "-OQe", SNMP_TARGET] + alias_oids, ...)
   for line in get_proc.stdout.splitlines():
       m = re.search(r'ifAlias\.(\d+)\s*=\s*(.+)', line)
       if m:
           alias_map[m.group(1)] = m.group(2).strip().strip('"')
   for p in result:
       p["desc"] = alias_map.get(str(p["snmp_idx"]), "")
   ```

2. Atualizar `pon.discovery.zte.py` para exportar `{#NETSTREAM.PON_LABEL}` e
   `{#NETSTREAM.PON_DESC}`:
   ```python
   "{#NETSTREAM.PON_LABEL}": ("%s (%s)" % (p["name"], p["desc"]) if p.get("desc") else str(p["name"])),
   "{#NETSTREAM.PON_DESC}": str(p.get("desc", "")),
   ```

3. Após deploy dos scripts, **deletar o cache antigo** da OLT para forçar nova coleta:
   ```bash
   rm /tmp/pon_cache_IP_DA_OLT.json
   ```
   O próximo ciclo de coleta criará o cache com `desc` populado e o Zabbix atualizará
   as macros no próximo ciclo de LLD (discovery delay = 1h por padrão — forçar via
   "Execute now" na discovery rule se necessário).

### Arquitetura do Fluxo de Descrição

O nome do circuito percorre o seguinte caminho até aparecer no nome do alerta:

```
OLT (ifAlias configurado no equipamento)
  │
  │  snmpget 1.3.6.1.2.1.31.1.1.1.18.{snmp_idx}
  ▼
pon.status.zte.py  ──►  /tmp/pon_cache_{ip}.json
                         [{"name": "gpon_1/9/2", "desc": "SOBERANA", ...}]
  │
  │  lê cache
  ▼
pon.discovery.zte.py
  └── exporta LLD JSON:
      {
        "{#NETSTREAM.PON_NAME}":  "gpon_1/9/2",
        "{#NETSTREAM.PON_DESC}":  "SOBERANA",
        "{#NETSTREAM.PON_LABEL}": "gpon_1/9/2 (SOBERANA)"   ← macro usada nos nomes
      }
  │
  │  Zabbix processa LLD
  ▼
Discovery Rule cria item/trigger prototypes com macros resolvidas:
  Nome do trigger: "PON gpon_1/9/2 (SOBERANA): LOS detectado (Fibra)"
```

**Por que o snmp_idx e não o idx da tabela de autorização?**

O índice da tabela proprietária ZTE (`1.3.6.1.4.1.3902.1082.500.10.2.2.3.1.14`)
usa formato `(slot<<16)|(card<<8)|port`, enquanto `ifAlias` no IF-MIB usa o
índice `ifIndex` padrão do sistema operacional. A função `auth_idx_to_ifmib(i)`
converte entre os dois:

```python
def auth_idx_to_ifmib(i):
    card = (i >> 8) & 0xFF
    port = i & 0xFF
    return 0x10000000 | (card << 16) | (port << 8)
```

Esse `snmp_idx` é o mesmo índice usado pelo IF-MIB e pelo `ifAlias`, o que
permite o `snmpget` pontual por porta após a coleta bulk.

---

## 18. Parâmetro `templateGroups` inválido na API de Import (Zabbix 6.0)

### Mensagem de Erro:
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32602,
    "message": "Invalid params.",
    "data": "Invalid parameter \"/rules\": unexpected parameter \"templateGroups\"."
  }
}
```

### Causa:
Ao chamar `configuration.import` via API JSON-RPC no Zabbix **6.0**, o parâmetro
`templateGroups` dentro do objeto `rules` não é reconhecido. Esse parâmetro foi
introduzido em versões posteriores (6.4+) do Zabbix e não existe no schema da API 6.0.

### Como Prevenir / Solucionar:
Remover `templateGroups` do objeto `rules` ao importar via API em servidores Zabbix 6.0:

```python
# ERRADO — causa o erro no Zabbix 6.0
rules = {
    "templates": {"createMissing": True, "updateExisting": True},
    "templateGroups": {"createMissing": True},   # <- remover esta linha
    ...
}

# CORRETO para Zabbix 6.0
rules = {
    "templates": {"createMissing": True, "updateExisting": True},
    "items": {"createMissing": True, "updateExisting": True, "deleteMissing": False},
    "triggers": {"createMissing": True, "updateExisting": True, "deleteMissing": False},
    "discoveryRules": {"createMissing": True, "updateExisting": True, "deleteMissing": False},
    "graphs": {"createMissing": True, "updateExisting": True, "deleteMissing": False},
    "valueMaps": {"createMissing": True, "updateExisting": True},
    "templateLinkage": {"createMissing": True}
}
```

Os grupos referenciados no template XML precisam existir previamente no servidor ou
devem ser criados manualmente antes do import.

---

## 18. Token de Sessão Expirado na API Zabbix (`Session terminated`)

### Mensagem de Erro:
```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32500,
    "message": "Application error.",
    "data": "Session terminated, re-login, please."
  }
}
```

### Causa:
O token de API extraído do banco de dados (`SELECT token FROM token` ou via
`SELECT sessionid FROM sessions`) pode estar expirado ou ter sido invalidado por
logout ou limpeza de sessões. O Zabbix invalida sessões por inatividade ou após
a expiração configurada em `Administration → General → GUI`.

### Como Prevenir / Solucionar:
1. Fazer novo login via API para obter token fresco:
   ```bash
   curl -s -X POST http://ZABBIX_HOST/api_jsonrpc.php \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"user.login","params":{"username":"Admin","password":"SENHA"},"id":1}'
   ```
2. Se a senha for desconhecida, resetar via banco de dados:
   - **Zabbix 6.0 (PostgreSQL, usa bcrypt):**
     ```bash
     HASH=$(php -r "echo password_hash('NovaSenha', PASSWORD_BCRYPT);")
     psql -h HOST -U zabbix -d zabbix -c "UPDATE users SET passwd='$HASH' WHERE username='Admin';"
     ```
   - **Zabbix 6.0 (alternativa md5 — dependendo da versão):**
     ```bash
     MD5=$(echo -n "NovaSenha" | md5sum | cut -d' ' -f1)
     psql -h HOST -U zabbix -d zabbix -c "UPDATE users SET passwd='$MD5' WHERE username='Admin';"
     ```
   - Testar qual hash funciona tentando o login via API após cada tentativa.
3. Após obter o token novo, usar imediatamente pois sessões do Zabbix expiram.

> **Observado em:** Zabbix 6.0 (WOW) — token no PostgreSQL estava expirado; reset via md5
> funcionou após tentativa com bcrypt falhar.

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
14. [ ] `<valuemaps>`/`<valuemap>` usam nomes sem underscore (não `value_maps`/`value_map`) e estão dentro de `<template>`.
15. [ ] Nenhum trigger usa `zabbix[host,snmp,available]` — substituir por `nodata(/TEMPLATE/uptime_key,5m)=1`.
16. [ ] Nenhum trigger usa `diff()` — substituir por `change(/TEMPLATE/key)<>0` (removido no Zabbix 7.0).

### Ambas as versões
13. [ ] O encoding do arquivo XML está em UTF-8 sem BOM e indentado corretamente.
14. [ ] Rodar `xref.py` confirma zero referências internas quebradas.

---

## 12. Falso Positivo em Massa — DyingGasp / LOS após Deploy de Script Externo

### Sintoma
Após deploy ou rollback de script externo (`pon.status.zte.py`, etc.), dezenas/centenas de alertas DyingGasp ou LOS abrem simultaneamente em hosts que não têm queda real de clientes (PPPoE estável).

### Causa Raiz
**Cenário A — Script com contagem não filtrada:** O script contabiliza `reason codes` de todos os ONUs offline sem filtrar pelo estado atual (`onu_state`). Como o ZTE armazena o último reason permanentemente (mesmo após ONU voltar online), o DG/LOS fica inflacionado. A troca de versão (inflado → correto ou correto → inflado) gera `delta(900)>=3` → trigger dispara.

**Cenário B — Limpeza de cache:** Ao executar `rm /tmp/pon_cache_zte_*.json`, os itens calculam com valor 0 (cache vazio → JSON vazio → JSONPath retorna 0). Na coleta seguinte, os valores voltam ao nível real (ex: DG=39). `delta(900) = 39 - 0 = 39 >= 3` → trigger dispara. Como o trigger DG tem `manual_close=YES`, os eventos NÃO fecham sozinhos e se acumulam a cada ciclo.

### Prevenção
1. **NUNCA limpar cache de produção** (`/tmp/pon_cache_zte_*.json`, `/tmp/pon_cache_fh_*.json`).
2. **Scripts DEV usam cache separado** (`pon_cache_zte_dev_*.json`) — bug no DEV não contamina produção.
3. **Testar em host DEV por pelo menos 1 ciclo completo** antes de promover para produção.
4. **Não fazer deploy de script em produção** sem aprovação explícita do usuário.

### Resolução (quando já ocorreu)
1. Confirmar que é falso positivo (verificar PPPoE, checar `online` vs `offline` nos itens).
2. Fechar todos os alertas DG via API (loop com `event.acknowledge` action=5, lotes de 500):
   ```python
   # Requer múltiplas rodadas — novos eventos abrem enquanto DG oscila
   for rodada in range(10):
       dg = api(tok, "event.get", {"hostids": [...], "value": "1",
                "search": {"name": "DyingGasp"}, "output": ["eventid"], "limit": 500})
       if not dg: break
       api(tok, "event.acknowledge", {"eventids": [e["eventid"] for e in dg],
           "action": 5, "message": "Falso positivo: <causa>."})
   ```
3. **NÃO limpar o cache** durante o processo — piora a oscilação.
4. Aguardar ~15 minutos para `delta(900)` zerar com valores estáveis.
5. Fechar rodada final dos eventos residuais.

### Diagnóstico — script onu_state com community errada
Se `snmpbulkwalk ... 10.x.x.x <OID_ONU_STATE>` retornar vazio, verificar community SNMP:
```bash
# Obter community real do host no Zabbix
python3 -c "import json,urllib.request; ..."  # via API usermacro.get + globalmacro
# Testar:
snmpbulkwalk -v2c -c S3ML1M1T3 -t 15 -r 1 -Cr10 10.x.x.x <OID>
```


