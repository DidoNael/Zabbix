# Backup — Delays das Discovery Rules

Data da alteração: 2026-06-30
Motivo: Forçar atualização rápida após limpeza de itens `.bk` duplicados
Alteração feita: todos os delays de discovery rules → `5m`
Valor original: `1d` (todas)

## Para restaurar

Reimporte os templates com `<delay>1d</delay>` nas discovery rules,
ou altere direto na UI do Zabbix em cada discovery rule.

### 4.4 — Template.xml

| Discovery Rule | Delay original |
|---|---|
| Discovery: BGP4 Peer(s) | 1d |
| Discovery: Temperatura | 1d |
| Discovery \| Network interfaces Virtual | 1d |
| Discovery OSPF PEER | 1d |
| Discovery: Uso de CPU | 1d |
| Discovery: Fan | 1d |
| Discovery \| Network interfaces \| Sinal optico single lan | 1d |
| Discovery: Memoria | 1d |
| Discovery \| Network interfaces | 1d |
| Discovery \| Network interfaces \| Sinal Optico modules multi lane | 1d |

### 6.0 — Template.xml

| Discovery Rule | Delay original |
|---|---|
| Discovery: BGP4 Peer(s) | 1d |
| Discovery: Temperatura | 1d |
| Discovery \| Network interfaces Virtual | 1d |
| Discovery OSPF PEER | 1d |
| Discovery: Uso de CPU | 1d |
| Discovery: Fan | 1d |
| Discovery \| Network interfaces optical single lan | 1d |
| Discovery: Memoria | 1d |
| Discovery \| Network interfaces | 1d |
| Discovery \| Network interfaces Modules Multi Lane | 1d |

## Comando para restaurar (PowerShell)

```powershell
# Restaura 5m → 1d apenas nas discovery rules (delay seguido de lifetime)
(Get-Content "Template.xml" -Raw) -replace '(<delay>)5m(</delay>\r?\n\s+<lifetime>)', '${1}1d${2}' | Set-Content "Template.xml" -Encoding utf8
```
