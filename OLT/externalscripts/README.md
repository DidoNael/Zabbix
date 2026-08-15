# Scripts externos — OLT NETSTREAM

Scripts que devem estar em `/usr/lib/zabbix/externalscripts/` no servidor Zabbix.

## Instalação

```bash
cd /usr/lib/zabbix/externalscripts
cp netstream.gpon.pon.* pon_*.py /usr/lib/zabbix/externalscripts/
chmod +x netstream.gpon.pon.* pon_*.py
chown zabbix:zabbix netstream.gpon.pon.* pon_*.py
```

## Arquivos por marca

### ZTE
| Arquivo | Tipo | Descrição |
|---|---|---|
| `netstream.gpon.pon.status` | wrapper shell | Chamado pelo Zabbix; chama `pon_status.py` |
| `netstream.gpon.pon.discovery` | wrapper shell | Chamado pelo Zabbix; chama `pon_discovery_zte.py` |
| `netstream.gpon.pon.total.zte` | wrapper shell | Totais globais da OLT ZTE |
| `pon_status.py` | Python 3 | Coleta status por PON via snmpbulkwalk (ZTE) |
| `pon_discovery_zte.py` | Python 3 | Discovery de PONs ZTE |
| `pon_total_zte.py` | Python 3 | Totais OLT ZTE |

### Fiberhome
| Arquivo | Tipo | Descrição |
|---|---|---|
| `netstream.gpon.pon.status.fiberhome` | wrapper shell | Chamado pelo Zabbix |
| `netstream.gpon.pon.discovery.fiberhome` | wrapper shell | Chamado pelo Zabbix |
| `netstream.gpon.pon.total.fiberhome` | wrapper shell | Totais globais OLT Fiberhome |
| `pon_status_fiberhome.py` | Python 3 | Coleta status por PON (Fiberhome) |
| `pon_discovery_fiberhome.py` | Python 3 | Discovery de PONs Fiberhome |
| `pon_total_fiberhome.py` | Python 3 | Totais OLT Fiberhome |

### Huawei
| Arquivo | Tipo | Descrição |
|---|---|---|
| `netstream.gpon.pon.status.huawei` | wrapper shell | Chamado pelo Zabbix |
| `netstream.gpon.pon.discovery.huawei` | wrapper shell | Chamado pelo Zabbix |
| `netstream.gpon.pon.total.huawei` | wrapper shell | Totais globais OLT Huawei |
| `pon_status_huawei.py` | Python 3 | Coleta status por PON (Huawei) |
| `pon_discovery_huawei.py` | Python 3 | Discovery de PONs Huawei |
| `pon_total_huawei.py` | Python 3 | Totais OLT Huawei |

## Dependências

```bash
pip3 install pysnmp
```

## Formato de retorno (pon_status*.py)

JSON com array de objetos por PON:
```json
[
  {
    "index": "1/1/1",
    "online": 32,
    "offline": 1,
    "los": 0,
    "lof": 0,
    "losi": 0,
    "dg": 0,
    "auth": 33
  }
]
```
