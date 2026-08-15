# Regras de Manutenção dos Templates Zabbix

## Regra 1 — Sempre atualizar todas as versões

Cada template existe em duas versões: **4.4** e **6.0**. Toda alteração de **conteúdo** (novo item, novo trigger, mudança de threshold, mudança de delay) deve ser aplicada nas duas versões.

Exceções são apenas mudanças de **sintaxe** exclusivas de cada versão:

| O que muda nas duas versões | Só muda em uma versão |
|---|---|
| Nome de item, OID, delay, status | `<uuid>` (só no 6.0) |
| Thresholds de trigger | `SNMP_AGENT` vs `SNMPV2` (sintaxe de tipo) |
| Novas discovery rules | `<snmp_community>` (só no 4.4) |
| Remoção de itens | `<applications>` (só no 4.4) |
| Delays de coleta | Sintaxe de expressão de trigger |

**Checklist após qualquer mudança:**

```
[ ] Apliquei em 4.4?
[ ] Apliquei em 6.0?
[ ] Rodei validação XML em ambos?
[ ] Fiz git commit E git push?
```

---

## Regra 2 — Verificar sintaxe antes de subir

As duas versões têm sintaxe diferente em vários pontos. Antes de aplicar uma mudança, verifique a tabela abaixo:

### Tipo de item SNMP
| 4.4 | 6.0 |
|---|---|
| `<type>SNMPV2</type>` | `<type>SNMP_AGENT</type>` |
| `<snmp_community>{$SNMP_COMMUNITY}</snmp_community>` | *(não existe — herdado da interface)* |

### Expressão de trigger
| 4.4 | 6.0 |
|---|---|
| `{Host:key.last()}=1` | `last(/Host/key)=1` |
| `{Host:key.min(5m)}>=65` | `min(/Host/key,5m)>=65` |
| `{Host:key.delta(900)}>=3` | `(max(/Host/key,900)-min(/Host/key,900))>=3` |
| `{Host:key.last()}>={Host:threshold.last()}` | `last(/Host/key)>=last(/Host/threshold)` |
| `last("key")` em CALCULATED | `last(//key)` em CALCULATED |

> ⚠️ **`delta()`** não existe no 6.0 — substituir por `(max()-min())`.

### Estrutura obrigatória no 6.0
- `<uuid>` (UUIDv4, 13° dígito = `4`) como **primeiro filho** de todo item, trigger, discovery rule, valuemap, etc.
- **Não** colocar `<uuid>` dentro de `<graph_item><item>` — referência, não definição.
- `<valuemaps>` dentro do `<template>`, não na raiz do export.
- `<parameters><parameter>` em vez de `<params>` no preprocessing (exceto tipo CALCULATED, que mantém `<params>`).

### Operadores em XML
Sempre escapar dentro de tags `<expression>` e `<recovery_expression>`:

| Operador | XML |
|---|---|
| `>` | `&gt;` |
| `<` | `&lt;` |
| `&` | `&amp;` |

---

## Regra 3 — Revisar o guia de problemas antes de subir

Antes de commitar qualquer alteração, abra `docs/TROUBLESHOOTING_XML_IMPORT.md` e verifique:

1. **A mudança que estou fazendo não está na lista de erros conhecidos?**
   - Ex.: remover `<snmp_community>` no 4.4 quebra itens SNMP.
   - Ex.: usar `last("key")` em CALCULATED no 6.0 é inválido.

2. **A mudança não causa um loop de problema?**
   - Exemplo de loop: corrigir expressão de trigger no 6.0 usando `delta()` → erro ao importar → reverter → corrigir de novo.
   - Solução: consultar a tabela de sintaxe acima *antes* de escrever a expressão.

3. **Após importar, verificar no Zabbix:**
   - Todos os itens que devem estar DISABLED aparecem desativados?
   - Hosts existentes: status de itens/discoveries não é sobrescrito automaticamente — verificar manualmente ou via API.
   - Itens calculados que referenciam outros itens: validar que a chave referenciada existe no host.

---

## Regra 4 — Criar tag de versionamento após cada atualização

Após cada conjunto de mudanças commitado, criar uma tag semântica no git para marcar o estado estável:

```bash
# Formato: v<MAJOR>.<MINOR>.<PATCH>-<data>
git tag -a v1.2.0-20260723 -m "Desativa PPPoE, corrige threshold temperatura, delays 1d"
git push origin v1.2.0-20260723
```

### Critério de versão

| Tipo de mudança | Incrementar |
|---|---|
| Novo template, nova discovery rule, novo sistema de alertas | MAJOR |
| Novos itens, novos triggers, mudança de comportamento | MINOR |
| Correção de sintaxe, ajuste de threshold, fix de importação | PATCH |

> A tag permite que qualquer host ou ambiente saiba exatamente qual versão do template está em uso, e facilita rollback via `git checkout <tag>`.

---

## Regra 5 — Atualizar o CHANGELOG a cada mudança

O arquivo `CHANGELOG.md` na raiz do repositório deve ser atualizado **no mesmo commit** (ou imediatamente após) qualquer alteração nos templates ou scripts.

### Formato da entrada

```markdown
## [vX.Y.Z] — AAAA-MM-DD

### Adicionado
- Descrição objetiva da feature. (`hash-do-commit`)

### Corrigido
- Descrição objetiva do fix. (`hash-do-commit`)

### Alterado
- Descrição objetiva da mudança. (`hash-do-commit`)

### Removido
- Descrição do que foi removido. (`hash-do-commit`)
```

### O que registrar

| Registrar | Não registrar |
|---|---|
| Novo item/trigger/discovery rule | Ajuste de indentação |
| Remoção ou desativação de item | Mudança de comentário interno |
| Mudança de threshold ou delay | Correção de typo em nome de variável |
| Correção de erro de importação | Reordenação sem mudança funcional |
| Nova tag de versão | |

> O CHANGELOG é a fonte de verdade para qualquer operador que precise saber "o que mudou desde ontem". Ele deve ser legível sem contexto de código.

---

## Ordem de trabalho recomendada

```
1. Identificar o que precisa mudar (item, trigger, delay...)
2. Consultar tabela de sintaxe (Regra 2) para 4.4 E 6.0
3. Fazer a mudança no 4.4
4. Fazer a mudança equivalente no 6.0 (adaptar sintaxe)
5. Validar XML: [System.Xml.XmlDocument].Load() nos dois arquivos
6. Atualizar CHANGELOG.md (Regra 5)
7. git add + git commit + git push
8. Criar tag de versionamento (Regra 4) + git push origin <tag>
9. Importar no Zabbix e confirmar resultado
10. Se erro → registrar em TROUBLESHOOTING_XML_IMPORT.md
```

---

## Referência rápida — estrutura do repositório

```
zabbix-templates/
├── Switch/Huawei/
│   ├── 4.4/Template.xml   ← Zabbix 4.4 (SNMPV2, sem uuid)
│   └── 6.0/Template.xml   ← Zabbix 6.0 (SNMP_AGENT, com uuid)
├── OLT/ZTE/
│   ├── 4.4/Template.xml
│   └── 6.0/Template.xml
└── docs/
    ├── TROUBLESHOOTING_XML_IMPORT.md  ← erros de importação conhecidos
    └── REGRAS_MANUTENCAO_TEMPLATES.md ← este arquivo
```
