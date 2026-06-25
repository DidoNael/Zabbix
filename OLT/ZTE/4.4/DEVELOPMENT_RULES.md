# Regras de Desenvolvimento - Template ZTE

Este arquivo define regras estritas para a modificação do template Zabbix OLT ZTE (`Template.xml`).

> [!IMPORTANT]
> **REGRA CRÍTICA: Sem Pré-processamento na Regra de Descoberta Principal**
> 
> A regra de descoberta **`Discovery pon state | pon name | pondesc`** (chave: `interfaces.discovery`) **NÃO** deve conter nenhuma etapa de pré-processamento (tags `<preprocessing>` ou scripts JavaScript).
> 
> Esta regra de descoberta deve ler e repassar os dados brutos obtidos via SNMP diretamente para os protótipos de itens sem qualquer modificação ou filtragem baseada em JavaScript prévio.

## Motivação e Comportamento Esperado
- A regra de descoberta `interfaces.discovery` utiliza SNMP OIDs nativos para buscar informações sobre as portas PON e interfaces associadas.
- Qualquer etapa de pré-processamento JavaScript inserida nessa regra quebra a lógica de vinculação e a descoberta de itens legítimos (por exemplo, portas PON vazias ou sem clientes que precisam ser monitoradas).
- As alterações de cálculo de slots, mesclagem e preenchimento de macros devem ser tratadas de outras formas (por exemplo, na regra `gpon.port.discovery` ou diretamente nos protótipos se necessário, mas **nunca** adicionando pré-processamento JavaScript na regra `interfaces.discovery`).

## Verificação antes de Commits
Antes de realizar commits de alterações no arquivo `Template.xml`:
1. Verifique se o elemento `<discovery_rule>` com o `<key>interfaces.discovery</key>` **não** contém nenhuma tag `<preprocessing>`.
2. Valide o XML carregando-o em um parser de XML válido (como `[xml](Get-Content ...)` no PowerShell).
