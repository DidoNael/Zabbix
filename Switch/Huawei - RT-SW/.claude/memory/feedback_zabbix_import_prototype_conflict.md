---
name: feedback-zabbix-import-prototype-conflict
description: "Erro \"No permissions to referred object or it does not exist!\" no import de template Zabbix 6.0 causado por chave de item standalone colidindo com item prototype existente no servidor"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 86ffad65-959a-4844-9f89-fd6609b4bd34
  modified: 2026-08-11T15:02:10.737Z
---

Quando um template Zabbix 6.0 é atualizado e uma chave de item muda de **item prototype** (dentro de discovery rule) para **item standalone** (ou vice-versa), a importação falha com erro genérico:

> `No permissions to referred object or it does not exist!`

**Por quê:** Zabbix não permite que a mesma chave exista simultaneamente como item standalone e como item prototype no mesmo template. O erro é enganoso — não é sobre permissões.

**Como aplicar:** Ao ver esse erro em import de template 6.0, verificar:

1. Exportar o template do servidor via API (`configuration.export`)
2. Comparar UUIDs do servidor vs git — diferença grande indica template desatualizado
3. Para cada item standalone no XML novo, verificar se existe como prototype no servidor:
   ```powershell
   # API call: itemprototype.get com filter key_ = chave do item
   ```
4. Se houver colisão: deletar o(s) prototype(s) antigos via `itemprototype.delete` antes de importar
5. Reimportar o XML

**Caso real (2026-08-11):** Template `Template Switch Huawei 6700 Series - Netstream` (WOW FIBER, Zabbix 6.0).
- Chaves `netstream.hwAvgDuty1min[{#SNMPINDEX}]` e `netstream.hwAvgDuty5min[{#SNMPINDEX}]` foram movidas de prototypes (discovery rule `netstream.hwAvgDuty`) para items standalone no XML novo.
- A discovery rule também ganhou novos prototypes com chave renomeada (ponto adicionado: `hwAvgDuty1min.[{#SNMPINDEX}]`).
- Solução: deletar prototypes IDs 128463 e 128464 via API, depois importar.

**Why:** Erro enganoso desperdiça muito tempo de diagnóstico — a causa real nunca aparece na mensagem.

**How to apply:** Sempre que `configuration.import` retornar esse erro em Zabbix 6.0, rodar diagnóstico de colisão standalone vs prototype antes de investigar permissões ou UUIDs.
