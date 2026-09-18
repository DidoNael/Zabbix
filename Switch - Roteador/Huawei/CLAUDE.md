# Templates Switch Huawei

## Leitura obrigatória antes de editar

Ler os arquivos em `.claude/memory/` antes de qualquer edição ou diagnóstico de import:

- [`.claude/memory/feedback_zabbix_import_prototype_conflict.md`](.claude/memory/feedback_zabbix_import_prototype_conflict.md) — Erro "No permissions to referred object" no import 6.0: causa e solução

---

## Dashboard dependente do template

A dashboard **"NETSTREAM - Sinal de Portas Ópticas - Huawei"** (`grafana-dashboards/Sinal de Portas Opticas - Huawei/sinal-portas-opticas-unificada.json`) usa filtros regex sobre os **nomes dos itens** criados pelo LLD deste template.

**Ao alterar qualquer um destes elementos, verificar e atualizar a dashboard:**
- Nomes de item prototypes (ex: renomear `{#ENTALIAS}` → `{#IFALIAS}` quebrou o painel RX)
- Adição/remoção de discovery rules ópticas (deletar a rule deleta o histórico dos itens)
- Filtros de tipo single vs multi-lane no script `discovery_huawei_optical_netstream.sh`

Repositório da dashboard: `https://github.com/DidoNael/grafana-dashboards`

---

## Regras de formato

Ver `../../CLAUDE.md` para regras completas por versão (4.4 vs 6.0), UUIDs, checklist de import e erros comuns.
