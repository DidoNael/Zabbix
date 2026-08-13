# Guia de Edição de Templates Zabbix

## Versionamento obrigatório

**Antes de qualquer alteração em template**, criar tag de versão:

```bash
# No diretório do repo local
git tag vX.Y.Z
git push origin vX.Y.Z
```

**Convenção de versão:** `MAJOR.MINOR.PATCH`
- `PATCH`: correção de bug sem mudança funcional
- `MINOR`: novo item, trigger ou discovery adicionado
- `MAJOR`: reestruturação do template ou mudança incompatível

**Workflow obrigatório:**
1. `git tag vX.Y.Z` antes de editar
2. Editar e commitar
3. `git push && git push origin vX.Y.Z`

> Regra: se o template já foi importado em produção, sempre taggear antes — permite rollback via `git checkout vX.Y.Z -- <arquivo>`.

---


## Regras obrigatórias por versão

### Zabbix 4.4 (`Switch/Huawei/4.4/`)

| Campo | Valor correto |
|---|---|
| `<type>` SNMP | `SNMPV2` |
| `<value_type>` texto | `TEXT` (não `4`) |
| `<manual_close>` | `YES` (não `1`) |
| UUIDs | **Não usar** — 4.4 não suporta |
| `<tags>` em itens | **Não usar** — usar `<applications>` |
| `<valuemaps>` | `<value_maps>` com `<value_map>` (sem UUID) |

### Zabbix 6.0 (`Switch/Huawei/6.0/`)

| Campo | Valor correto |
|---|---|
| `<type>` SNMP | `SNMP_AGENT` |
| `<value_type>` texto | `TEXT` |
| `<manual_close>` | `YES` |
| UUIDs | **Obrigatório em todos os elementos** |
| `<tags>` em itens | Usar `<tags>`, não `<applications>` |
| `<valuemaps>` | `<valuemaps>` com `<valuemap>` + `<uuid>` |

---

## UUIDs — regras críticas (6.0)

Todo elemento novo no template 6.0 exige um `<uuid>` **UUIDv4 válido**.

### O que precisa de UUID no 6.0
- `<template>`
- `<discovery_rule>`
- `<item>` e `<item_prototype>`
- `<trigger>` e `<trigger_prototype>`
- `<graph>` e `<graph_prototype>`
- `<valuemap>` (dentro de `<valuemaps>`)
- `<host_prototype>`

### Como gerar UUID válido

```powershell
# PowerShell — gera 1 UUID
[System.Guid]::NewGuid().ToString("N")

# Gerar vários de uma vez
1..10 | ForEach-Object { [System.Guid]::NewGuid().ToString("N") }
```

### Como validar UUIDs existentes

```powershell
$content = Get-Content "Template.xml" -Raw
$uuids = [regex]::Matches($content, '<uuid>([0-9a-f]{32})</uuid>')
$invalid = $uuids | Where-Object { $_.Groups[1].Value[12] -ne '4' }
if ($invalid) { $invalid | ForEach-Object { Write-Output "INVÁLIDO: $($_.Groups[1].Value)" } }
else { Write-Output "OK — todos UUIDv4 válidos" }
```

> **Regra rápida:** o 13º caractere do UUID (sem hífens) deve ser sempre `4`.
> `xxxxxxxx xxxx `**`4`**`xxx xxxx xxxxxxxxxxxx`

---

## Checklist antes de importar

### Template 4.4 → Zabbix 4.4
- [ ] Nenhum `<uuid>` presente
- [ ] `<type>SNMPV2</type>` em todos os itens SNMP
- [ ] `<value_type>TEXT</value_type>` (não número)
- [ ] `<manual_close>YES</manual_close>`
- [ ] Applications declaradas no nível do template em `<applications>`
- [ ] Valuemaps em `<value_maps><value_map>` sem UUID

### Template 6.0 → Zabbix 6.0+
- [ ] UUID presente em **todos** os elementos listados acima
- [ ] 13º char do UUID é `4` (validar com o script acima)
- [ ] `<type>SNMP_AGENT</type>` em todos os itens SNMP
- [ ] Tags em `<tags><tag>` (não `<applications>`)
- [ ] Valuemaps em `<valuemaps><valuemap>` com UUID

---

## Erros comuns de importação e correções

| Erro | Causa | Correção |
|---|---|---|
| `UUIDv4 is expected` | UUID ausente ou inválido (13º char ≠ `4`) | Gerar UUID com PowerShell e substituir |
| `unexpected constant '1'` para `manual_close` | Valor `1` no lugar de `YES` | Substituir `<manual_close>1</manual_close>` por `YES` |
| `unexpected constant '4'` para `value_type` | Número no lugar de string | Substituir pelo nome: `TEXT`, `FLOAT`, `UNSIGNED`, etc. |
| `unexpected constant "CHARACTER"` | `CHARACTER` não é válido no 4.4 | Usar `CHAR` (verificado em produção no template Huawei 4.4) |
| `Application ... not available` | Application referenciada mas não declarada no template | Adicionar em `<applications>` na raiz do template |
| `SNMPV2` inválido no 6.0 | Tipo errado | Usar `SNMP_AGENT` |
| `Expressão de trigger inválida` com string após `<>` | No 4.4, `<>` não funciona com valores do tipo `CHAR`/`TEXT` | Usar `.str(valor)=0` para "diferente de" e `.str(valor)=1` para "igual a" |

---

## Mapeamento de value_type (4.4 numérico → nome)

| Número | String correta no XML |
|---|---|
| 0 | `FLOAT` |
| 1 | `CHAR` ← **não** `CHARACTER` (causa erro de importação) |
| 2 | `LOG` |
| 3 | `UNSIGNED` |
| 4 | `TEXT` |

---

## Itens External Check (scripts externos)

Scripts em `/usr/lib/zabbix/externalscripts/`. O Zabbix chama o arquivo diretamente pelo nome da chave.

| Campo | 4.4 | 6.0 |
|---|---|---|
| `<type>` | `EXTERNAL` | `EXTERNAL` |
| Parâmetros na chave | `script.sh["param1","param2"]` | idem |
| Discovery rule | `EXTERNAL` igual | `EXTERNAL` igual |

**Comparação de strings em triggers com itens CHAR/TEXT:**

| Versão | "igual a" | "diferente de" |
|---|---|---|
| 4.4 | `.str(valor)=1` | `.str(valor)=0` |
| 6.0 | `last(...)="valor"` | `last(...)<>"valor"` |

> No 4.4, `<>` com strings causa erro de importação — confirmado no template DNS Monitor.

**Convenção de nomenclatura de scripts no repositório:**
- Sufixo `_netstream` em todos os scripts externos (ex: `nqa_huawei_netstream.sh`, `discovery_huawei_optical_netstream.sh`)
- Sufixo `_netstream` nas **keys de itens e discovery rules** que referenciam scripts externos (ex: `nqa_huawei_netstream.sh[{HOST.IP},...]`, `discovery_isp_services_netstream.sh["{}"]`)
- Prefixo `netstream.` nas **keys de itens internos** sempre que criar um item novo em template próprio (ex: `netstream.gpon.onu.online[{#SNMPINDEX}]`)
- Macros com sufixo `_NETSTREAM` (ex: `{$DNS_SERVERS_NETSTREAM}`)
- Nome do template com sufixo ` - Netstream` (ex: `Template DNS Monitor - Netstream`)

**Description obrigatória em todo template novo ou editado:**
```
Netstream Telecomunicações — netstream.net.br
Contato: (11) 95990-4100 | suporte@netstream.net.br

AVISO DE PROPRIEDADE INTELECTUAL
Este template é propriedade exclusiva da Netstream Telecomunicações.
É proibida a cópia, distribuição, modificação ou qualquer uso sem
autorização prévia e por escrito da Netstream Telecomunicações.
Todos os direitos reservados.
```

**Header obrigatório em todo script novo ou renomeado:**
```bash
# =============================================================================
# Empresa  : Netstream Telecomunicações
# Site     : netstream.net.br
# Contato  : (11) 95990-4100
# Email    : suporte@netstream.net.br
#
# AVISO DE PROPRIEDADE INTELECTUAL
# Este script é propriedade exclusiva da Netstream Telecomunicações.
# É proibida a cópia, distribuição, modificação ou qualquer uso sem
# autorização prévia e por escrito da Netstream Telecomunicações.
# Todos os direitos reservados.
# =============================================================================
```

> Regra: ao criar ou renomear qualquer script, incluir o header acima logo após o `#!/bin/bash`.

---

## Sincronismo entre 4.4 e 6.0

Ao adicionar um item novo, adicionar nos **dois templates** com as adaptações de formato acima.
Nunca copiar XML de um para o outro sem ajustar os campos de versão.
