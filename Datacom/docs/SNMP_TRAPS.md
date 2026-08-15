# Configuração de SNMP Traps — OLT Datacom DmOS

## Visão geral

O monitoramento de **DyingGasp** (queda de energia na ONU) e **LOS** (rompimento de fibra) na Datacom DM4618 é feito via **SNMP Traps**, pois esses eventos não estão disponíveis como OIDs polláveis.

Fluxo:
```
OLT DM4618 → trap UDP 162 → Zabbix Server (snmptrapd) → item "SNMP trap" → trigger
```

---

## 1. Configurar a OLT para enviar traps

Acesse a OLT via SSH ou console e execute:

```
configure terminal

! Destino dos traps (IP do servidor Zabbix)
snmp-server host 177.91.165.47 version 2c S3ML1M1T3

! Habilitar traps de ONU
snmp-server enable traps onu dying-gasp
snmp-server enable traps onu los
snmp-server enable traps onu register
snmp-server enable traps onu deregister

! Confirmar configuração
show snmp trap host
show snmp trap status

end
write
```

> **Nota**: Substitua `177.91.165.47` pelo IP do servidor Zabbix e `S3ML1M1T3` pela community correta.

### Verificar traps sendo enviados

Na OLT, force um evento de teste:
```
! Ver log de eventos de trap
show snmp trap statistics
```

No servidor Zabbix, capture os traps:
```bash
tcpdump -i any -n udp port 162 -A 2>/dev/null | grep -i "datacom\|dying\|los\|3709"
```

---

## 2. Configurar o Zabbix Server para receber traps

### 2.1 Instalar snmptrapd

```bash
yum install net-snmp net-snmp-utils -y
# ou
apt install snmptrapd snmp -y
```

### 2.2 Configurar /etc/snmp/snmptrapd.conf

```bash
cat > /etc/snmp/snmptrapd.conf << 'EOF'
# Aceitar traps de qualquer host com a community configurada
authCommunity log,execute,net S3ML1M1T3
authCommunity log,execute,net 4LF4N3T3

# Encaminhar para o Zabbix via script
traphandle default /usr/lib/zabbix/externalscripts/zabbix_trap_receiver.pl
EOF
```

### 2.3 Instalar o script receptor do Zabbix

```bash
# Verificar se já existe (muitas instalações Zabbix já têm)
ls -la /usr/lib/zabbix/externalscripts/zabbix_trap_receiver.pl

# Se não existir, baixar do pacote zabbix-server
# Geralmente em: /usr/share/doc/zabbix-server-mysql/zabbix_trap_receiver.pl.gz
gunzip -c /usr/share/doc/zabbix-server-mysql*/zabbix_trap_receiver.pl.gz \
  > /usr/lib/zabbix/externalscripts/zabbix_trap_receiver.pl
chmod +x /usr/lib/zabbix/externalscripts/zabbix_trap_receiver.pl
```

### 2.4 Configurar o script receptor

Editar `/usr/lib/zabbix/externalscripts/zabbix_trap_receiver.pl`:

```perl
# Linha que define o arquivo de log de traps
my $SNMPTrapperFile = '/tmp/zabbix_traps.tmp';
```

### 2.5 Configurar o Zabbix Server para ler traps

Em `/etc/zabbix/zabbix_server.conf`:

```ini
# Habilitar SNMPTrapper
SNMPTrapperFile=/tmp/zabbix_traps.tmp
StartSNMPTrapper=1
```

### 2.6 Iniciar snmptrapd

```bash
systemctl enable snmptrapd
systemctl start snmptrapd
systemctl restart zabbix-server

# Verificar se está ouvindo na porta 162
ss -ulnp | grep 162
```

---

## 3. OIDs de Trap da Datacom DmOS

Os traps da Datacom usam a enterprise OID `1.3.6.1.4.1.3709`.

| Evento | OID do Trap (provável) | Descrição |
|--------|----------------------|-----------|
| DyingGasp | `1.3.6.1.4.1.3709.3.6.x.x` | ONU perdeu energia |
| LOS | `1.3.6.1.4.1.3709.3.6.x.x` | Perda de sinal óptico |
| ONU Register | `1.3.6.1.4.1.3709.3.6.x.x` | ONU registrou na PON |
| ONU Deregister | `1.3.6.1.4.1.3709.3.6.x.x` | ONU saiu da PON |

> **Para confirmar os OIDs exatos**: solicitar o arquivo MIB `DATACOM-GPON-MIB.mib` ao suporte Datacom, ou capturar um trap real com `tcpdump` e analisar com `snmptranslate`.

### Como capturar trap real para identificar o OID

```bash
# No servidor Zabbix, iniciar captura
snmptrapd -f -Lo -c /etc/snmp/snmptrapd.conf

# Na OLT, desligar e religar uma ONU de teste
# O trap aparecerá no terminal com o OID completo
```

---

## 4. Itens de Trap no Template Zabbix

Após confirmar os OIDs, adicionar no template os itens de trap por porta GPON:

| Item | Tipo | Key |
|------|------|-----|
| Trap DyingGasp | SNMP trap | `snmptrap["1.3.6.1.4.1.3709.3.6.X.X"]` |
| Trap LOS | SNMP trap | `snmptrap["1.3.6.1.4.1.3709.3.6.X.X"]` |
| Qualquer trap ONU | SNMP trap | `snmptrap.fallback` |

O item `snmptrap.fallback` captura **qualquer trap** recebido que não casou com outro item — útil para diagnóstico inicial enquanto os OIDs não estão confirmados.

---

## 5. Testar a recepção

```bash
# Simular um trap manualmente do servidor Zabbix para ele mesmo
snmptrap -v 2c -c S3ML1M1T3 127.0.0.1 '' \
  1.3.6.1.4.1.3709.3.6.1 \
  1.3.6.1.2.1.2.2.1.1 i 101744641

# Verificar se o arquivo de traps recebeu
tail -f /tmp/zabbix_traps.tmp
```

---

## Referências

- Datacom DmOS CLI Reference — comandos `snmp-server`
- Zabbix SNMP Trap documentation: https://www.zabbix.com/documentation/4.4/manual/config/items/itemtypes/snmptrap
- MIB Datacom: solicitar via suporte (suporte@datacom.com.br)
