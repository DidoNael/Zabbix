# Erros Conhecidos — Import Zabbix

Registro de erros encontrados durante import de templates, com causa e solução.

---

## ERR-001 — `Tag inválida "/zabbix_export": tag inesperada "value_maps"`

**Versão afetada**: Zabbix 6.0  
**Template**: Qualquer template 6.0 com value_maps  
**Quando ocorre**: Ao importar XML onde `<value_maps>` está fora do bloco `<template>`

**Causa**: Em Zabbix 6.0, `<value_maps>` deve estar **dentro** do bloco `<template>`, antes de `</template>`. O posicionamento fora de `<template>` (como nível filho direto de `<zabbix_export>`) é inválido.

**Estrutura errada**:
```xml
    </template>
</templates>
<value_maps>          ← ERRADO: fora do template
    ...
</value_maps>
</zabbix_export>
```

**Estrutura correta**:
```xml
            <value_maps>  ← dentro do <template>
                ...
            </value_maps>
        </template>
    </templates>
</zabbix_export>
```

**Solução**: Mover o bloco `<value_maps>...</value_maps>` para dentro de `<template>`, antes do `</template>` de fechamento.

**Templates corrigidos**: `OLT/Huawei/6.0/HUAWEI OLT - NETSTREAM.xml` (corrigido em 2026-09-21)

---

## ERR-002 — `No permissions to referred object`

**Versão afetada**: Zabbix 4.4 e 6.0  
**Quando ocorre**: Ao importar template onde um item mudou de prototype para standalone (ou vice-versa)

**Causa**: O Zabbix não consegue referenciar o objeto porque mudou de tipo (prototype ↔ standalone). O import falha silenciosamente ou com erro de permissão.

**Solução**: Deletar o item conflitante no Zabbix antes de importar o template atualizado.

---

## ERR-003 — `Multiple discovery rules` (trigger prototype)

**Versão afetada**: Zabbix 4.4  
**Quando ocorre**: Template com múltiplas discovery rules usando `{#SNMPINDEX}` e trigger prototype que referencia itens de ambas

**Causa**: Zabbix 4.4 não aceita trigger prototype que referencia item prototypes de discovery rules diferentes via XML import.

**Solução**: Criar o trigger prototype via MySQL diretamente (inserir em `triggers`, `functions`, `trigger_tag`).
