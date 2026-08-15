# Descoberta de Transceivers Ópticos com Descrição (Huawei VRP)

## Por que este script é necessário?

Nos switches Huawei VRP (séries S6700, S6800, NetEngine, etc.), as tabelas SNMP são estruturadas de forma independente:
- **Tabela de Interfaces / Descrição (`IF-MIB`):** Armazena a descrição administrativa configurada (`description PE1 - Dutra`) na OID `.1.3.6.1.2.1.31.1.1.1.18.{ifIndex}`, indexada pelo **`ifIndex`** (ex: `14`).
- **Tabela de Módulos Ópticos (`HUAWEI-ENTITY-EXTENT-MIB`):** Armazena o sinal óptico RX/TX (`hwEntityOpticalLaneRxPower`) na OID `.1.3.6.1.4.1.2011.5.25.31.1.1.3.1.32.{entPhysicalIndex}`, indexada pelo **`entPhysicalIndex`** (ex: `67469390`).
- A coluna nativa `entPhysicalAlias` (`.1.3.6.1.2.1.47.1.1.1.1.14`) da entidade física vem vazia (`""`) de fábrica na Huawei.

O script **`discovery_huawei_optical.sh`** atua no servidor Zabbix cruzando o nome físico da porta (`entPhysicalName`, ex: `100GE0/0/3`) com o nome da interface (`ifName`) para extrair e associar a descrição (`ifAlias`).

---

## Como Instalar no Servidor Zabbix

1. Copie o arquivo `discovery_huawei_optical.sh` para o diretório de scripts externos do seu Zabbix Server ou Zabbix Proxy:
   ```bash
   cp discovery_huawei_optical.sh /usr/lib/zabbix/externalscripts/discovery_huawei_optical.sh
   ```
   *(Nota: Se o seu Zabbix utiliza outro diretório para `ExternalScripts`, verifique o parâmetro `ExternalScripts` no `/etc/zabbix/zabbix_server.conf`)*

2. Conceda permissão de execução e ajuste o proprietário:
   ```bash
   chmod +x /usr/lib/zabbix/externalscripts/discovery_huawei_optical.sh
   chown zabbix:zabbix /usr/lib/zabbix/externalscripts/discovery_huawei_optical.sh
   ```

---

## Como Testar Manualmente

No terminal do seu servidor Zabbix, execute:
```bash
/usr/lib/zabbix/externalscripts/discovery_huawei_optical.sh "10.99.99.1" "S3ML1M1T3" "single"
```

### Saída Esperada (JSON LLD):
```json
{
  "data": [
    {
      "{#SNMPINDEX}": "67469390",
      "{#ENTPHYSICALNAME}": "100GE0/0/3",
      "{#IFALIAS}": "PE1 - Dutra",
      "{#ENTALIAS}": "PE1 - Dutra"
    }
  ]
}
```

---

## Recursos Internos do Script
- **Cache em Disco (`/tmp/zabbix_huawei_optical_cache`):** Os resultados são cacheados por 5 minutos (300 segundos) para garantir que múltiplas regras ou coletas LLD não gerem tráfego SNMP desnecessário no switch Huawei.
- **Compatibilidade Global:** Funciona com Zabbix 4.4, 5.0, 6.0 e 7.0+.
