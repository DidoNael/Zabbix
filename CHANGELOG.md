# Changelog

Todas as mudanÃ§as relevantes deste repositÃ³rio de templates Zabbix.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e o
versionamento segue [SemVer](https://semver.org/lang/pt-BR/).

**Escopo do repositÃ³rio:** templates Zabbix (4.4 e 6.0) para OLT ZTE, Switch/Router
Huawei, OSPF genÃ©rico, ISP Experience e DNS Monitor, alÃ©m de scripts de descoberta externa
(`externalscripts`), scripts de manutenÃ§Ã£o e documentaÃ§Ã£o.

> **ConvenÃ§Ã£o de compatibilidade:** cada template existe em pastas por versÃ£o do
> Zabbix (`4.4/` e `6.0/`). As duas versÃµes tÃªm esquemas XML incompatÃ­veis entre si â€”
> ver [docs/TROUBLESHOOTING_XML_IMPORT.md](docs/TROUBLESHOOTING_XML_IMPORT.md).

---




## [v2.13.7] — 2026-10-01

### Alterado — MikroTik

- **Renomeado template**: `Mikrotik CCR-1036 - COM CPU - NETSTREAM` → `MikroTik RouterOS - NETSTREAM`
  - Template agora é genérico para qualquer RouterOS (CCR, CRS, hEX, RB, etc.)
  - Arquivo renomeado: `Mikrotik CCR-1036 - COM CPU - NETSTREAM.xml` → `MikroTik RouterOS - NETSTREAM.xml`
  - Rename feito via API no Zabbix 177.91.165.53 (ID 10892 preservado, histórico intacto)

---

## [v2.13.6] — 2026-10-01

### Corrigido — MikroTik CCR-1036

- **`avg.cpu.util` agora funciona em qualquer modelo MikroTik** (não apenas CCR-1036):
  - Tipo alterado de `CALCULATED` (hardcoded 36 núcleos) para `EXTERNAL` (script SNMP walk)
  - Novo script `Mikrotik/externalscripts/avg.cpu.util`: faz `snmpwalk 1.3.6.1.2.1.25.3.3.1.2` e retorna média de todos os núcleos encontrados
  - Delay alterado de `1s` (absurdo para calculated) para `60s`
  - Chave atualizada: `avg.cpu.util[{HOST.CONN},{$SNMP_COMMUNITY}]`
  - Deploy obrigatório: copiar script para `/usr/lib/zabbix/externalscripts/avg.cpu.util` no servidor Zabbix e dar `chmod +x`
- **Porta hardcoded removida** da discovery rule `CPU discovery` e item prototype `system.cpu.util[hrProcessorLoad.{#SNMPINDEX}]` — porta `161` nunca deve ser definida em item prototypes

---

## [v2.13.5] — 2026-10-01

### Adicionado — MikroTik CCR-1036

- **Triggers de CPU** no item `avg.cpu.util` (média geral de todos os núcleos):
  - > 60% por 10 minutos → WARNING, tags scope=SISTEMA/tipo=CPU/notificar=telegram
  - > 80% por 5 minutos → HIGH (INCIDENTE), mesmas tags
- **Triggers de RAM** no item `percent.memory` (substituiu trigger simples sem tags):
  - > 80% por 10 minutos → WARNING, tags scope=SISTEMA/tipo=Memoria/notificar=telegram
  - > 90% por 5 minutos → HIGH (INCIDENTE), mesmas tags

---

## [v2.13.3] — 2026-09-30

### Corrigido — MikroTik CCR-1036

- **Correção OIDs SFP optical**: mapeamento correto após snmpwalk nos equipamentos reais
  - RxPower: OID `.10` (era `.6`), multiplier 0.01 (era 0.1) → unidade dBm correta
  - TxPower: OID `.9` (era `.5`), multiplier 0.01 (era 0.1)
  - Temperature: OID `.6` (era `.8`), multiplier 1 (era 0.1) → já vem em °C
  - TxBias: OID `.8` (era `.7`), multiplier 1 (era 0.001) → já vem em mA
  - Verificado em Assare (TxPower=-28.83dBm, RxPower=-30.27dBm, Temp=38°C) e Caragua
  - Fortaleza não tem módulos SFP (OID `.19` ausente) → discovery retorna zero itens normalmente

---

## [v2.13.2] — 2026-09-30

### Alterado — MikroTik CCR-1036

- **Padronização de interfaces**: nomenclatura alinhada ao template Huawei 6700 para compatibilidade em dashboards
  - Discovery rule renomeada: `Network Interfaces Discovery` → `Discovery | Network interfaces Physical`
  - Macro `{#IFCOMENT}` renomeada para `{#IFALIAS}` (mesmo OID ifAlias, só nome padronizado)
  - Todos os itens de interface atualizados: `Interface {#IFNAME}: Bytes In` → `Incoming traffic on interface - {#IFNAME}: ({#IFALIAS})` e padrão equivalente para todos os demais
  - Trigger e graph de interface seguem o mesmo padrão
- **Novo LLD de sinal óptico SFP**: `Discovery | Network interfaces | Sinal optico SFP`
  - OID: `1.3.6.1.4.1.14988.1.1.19.1.1.*` (mtxrOpticalTable)
  - Itens por porta SFP: RxPower (dBm), TxPower (dBm), Temperature (°C), TxBias (mA)
  - Trigger: RxPower < -27 dBm → WARNING, tags scope=SISTEMA/tipo=Sinal_Optico/notificar=telegram
  - Graph: Signal Power (Rx + Tx sobrepostos)
- **Tags obrigatórias** adicionadas em todas as triggers: Link Down, Firmware, Fonte desligada

---

## [v2.13.1] — 2026-09-29

### Alterado — Servidor Linux

- **LLD de filesystems**: substituiu item fixo disk.used.percent.root por regra de descoberta automática
  - Chave nativa do agente: fs.fs.discovery + fs.fs.size[{#FSNAME},pused/free/total]
  - Sem necessidade de UserParameter para disco — agente Zabbix nativo já suporta
  - Descobre automaticamente todos os discos montados: /, /mnt/samba, /data, etc.
  - Exclui filesystems virtuais: tmpfs, devtmpfs, proc, sysfs, cgroup, overlay, squashfs
- **Triggers por filesystem** (encadeadas, disparam só após 15 min contínuos):
  - >= 80% → AVERAGE / notificar=telegram
  - >= 90% → HIGH / notificar=telegram (depende da 80%)
  - >= 95% → DISASTER / notificar=telegram (depende da 90%)
- **Tags obrigatórias** adicionadas em todas as triggers (scope/tipo/notificar)
- **userparameters/servidor_linux.conf**: removida entrada disk.used.percent.root

---
## [v2.13.0] — 2026-09-29

### Adicionado

- **Hypervisor/Proxmox/7.0**: Proxmox VE by HTTP.xml — template oficial Zabbix 7.0 para Proxmox VE via API REST. Coleta: nodes, VMs, containers (LXC), storage, CPU, RAM, rede, cluster status. Macros obrigatórias: {.URL}, {.TOKEN.ID}, {.TOKEN.SECRET}.
- **Hypervisor/VMware/7.0**: VMware Templates.xml — templates oficiais Zabbix 7.0 (VMware + VMware Hypervisor + VMware Guest). Coleta: VMs, datastores, ESXi hosts, snapshots, CPU/RAM por guest. Macros obrigatórias: {.URL}, {.USERNAME}, {.PASSWORD}.

### Configuração para testes

- **Proxmox**: criar token de API no Proxmox (Datacenter → Permissions → API Tokens) e configurar as macros no host
- **VMware**: configurar interface do tipo VMware no host com URL do vCenter (https://vcenter-ip/sdk) + macros de credencial

---
## [v2.12.1] — 2026-09-29

### Adicionado

- **DNS/7.0**: exportados dois templates DNS do Zabbix 7.0 para o repositório:
  - DNS UNBOUND - ZABBIX AGENT ACTIVE - NETSTREAM.xml: coleta estatísticas Unbound via agente ativo (queries, cache hits/miss, servfail, refused). Tags scope/tipo adicionadas.
  - DNS UNBOUND - Statistics SSH - NETSTREAM.xml: coleta top domains/IPs/record types via SSH. **Senha removida do XML** — substituída por macro {} do tipo SECRET_TEXT. Configurar a macro por host no Zabbix UI.

### Segurança

- Template DNS unbound statistics tinha senha root hardcoded no XML. Corrigido para macro {} (SECRET_TEXT) antes do commit — senha nunca exposta no repositório.

---
## [v2.12.0] â€” 2026-09-29

### Adicionado

- **Template Retificadora Huawei - Controladora SMU11B_X** (novo): adicionado ao repositÃ³rio em `Retificadora/Huawei/SMU11B_X/` com melhorias sobre a versÃ£o em produÃ§Ã£o:
  - Trigger "Falta de energia AC Status": alterado de `last()` para `min(900)` â€” sÃ³ alerta apÃ³s 15 minutos contÃ­nuos sem energia, eliminando falsos positivos em microdesligamentos
  - Trigger "TensÃ£o no limite": alterado de `last()` para `min/max(900)` â€” ignora picos transitÃ³rios de tensÃ£o
  - Triggers de bateria (80/50/30/15/5/1%): alterados para `min(900)` â€” evita alarmes em leituras instÃ¡veis
  - Triggers de bateria agora tÃªm dependÃªncias encadeadas (80â†’50â†’30â†’15â†’5â†’1%) para suprimir alertas redundantes
  - Novo item calculado `hwBattEstimatedAutonomy`: estima o tempo de autonomia restante em minutos usando `%_bateria * {$BATTERY_FULL_MINUTES} / 100`
  - Nova macro `{$BATTERY_FULL_MINUTES}` (padrÃ£o 240 = 4h): ajustÃ¡vel por host conforme capacidade real do banco de baterias
  - Campo `opdata` na trigger de energia exibe % atual da bateria no momento do alerta

---

## [v2.11.5] â€” 2026-09-29

### Adicionado

- **OLT ZTE/Fiberhome/Huawei (4.4 e 6.0)**: trigger "Queda total de ONUs" agora exibe contagem de LOS e DG no campo `opdata` â€” ex: "LOS: 8, DG: 2" visÃ­vel diretamente no painel de incidentes
- **Script ZTE `pon.status.zte.py`**: adicionada consulta `ifAlias` (nome do circuito configurado na porta, ex: "SOBERANA") para popular o campo `desc` no cache â€” antes usava apenas `ifDescr` que retornava o nome de sistema
- **Script ZTE `pon.discovery.zte.py`**: passa a exportar `{#NETSTREAM.PON_LABEL}` = "gpon_x/y/z (DESC)" quando ifAlias disponÃ­vel, e `{#NETSTREAM.PON_DESC}` separado â€” alinha com Fiberhome e Huawei que jÃ¡ faziam isso

---

## [v2.11.4] â€” 2026-09-29

### Corrigido

- **CLAUDE.md**: adicionada regra proibindo import/alteraÃ§Ã£o em qualquer instÃ¢ncia Zabbix sem aprovaÃ§Ã£o explÃ­cita do usuÃ¡rio

---

## [v2.11.3] â€” 2026-09-29

### Corrigido

- **OLT Fiberhome 6.0**: recovery do trigger "LOS detectado (Fibra)" corrigido para `last()=0` â€” antes `last() <= max(24h)*0.5` causava atraso para fechar incidente
- **OLT Fiberhome 4.4**: adicionada `recovery_expression` `last()=0` que estava ausente â€” trigger nÃ£o tinha auto-recovery
- **OLT Huawei 4.4**: recovery do trigger "LOS detectado (Fibra)" corrigido para `last()=0` â€” antes `last() <= max(86400)*0.5`
- **OLT Huawei 6.0**: recovery do trigger "LOS detectado (Fibra)" corrigido para `last()=0` â€” antes `last() <= max(24h)*0.5`

---

## [v2.11.2] â€” 2026-09-29

### Corrigido

- **OLT ZTE 6.0**: recovery do trigger "LOS detectado (Fibra)" simplificado para `last()=0` â€” antes usava `last() <= max(24h)*0.5` o que causava atraso de 13+ minutos para fechar incidentes mesmo com LOS = 0
- **OLT ZTE 4.4**: adicionada `recovery_expression` `last()=0` que estava ausente â€” trigger nÃ£o tinha auto-recovery antes desta versÃ£o

---

## [v2.11.1] â€” 2026-09-29

### Corrigido

- **Servidor Linux**: units de `disk.iostat.await/r_await/w_await` corrigidas de `s` para `ms` (UserParameter retorna ms, nÃ£o segundos)
- **Servidor Linux**: units de `disk.iostat.read/write` corrigidas de `kB/s` para `r/s` / `w/s` (UserParameter retorna IOPS, nÃ£o throughput)
- **Servidor Linux**: nome `Disco IO  read wait` / `write wait` com espaÃ§o duplo corrigido

### Adicionado

- **Servidor Linux**: trigger "Disco com uso alto" `avg(#3) >= 80%` AVERAGE adicionado â€” aviso antecipado antes dos 90% e 99%

---

## [v2.11.0] â€” 2026-09-29

### Adicionado

- **Servidor Linux**: novo template `SERVIDOR LINUX - ZABBIX AGENT ACTIVE - NETSTREAM` (Zabbix 7.0) adicionado em `Servidor Linux/7.0/`
- **Servidor Linux**: UserParameters documentados em `Servidor Linux/userparameters/servidor_linux.conf` com comentÃ¡rios por item, dependÃªncias e chave Zabbix correspondente
- **Servidor Linux**: `CLAUDE.md` criado com estrutura do template, tabela de itens/triggers e instruÃ§Ãµes de instalaÃ§Ã£o

---

## [v2.10.10] â€” 2026-09-24

### Corrigido

- **Huawei OLT 4.4 e 6.0 â€” trigger "Queda Total"**: corrige erro na expressÃ£o introduzida em v2.10.8. `min(360s)=0` significa "valor mÃ­nimo dos Ãºltimos 6 min = 0" (basta UM zero para disparar), nÃ£o "contÃ­nuo 6 min em zero". SubstituÃ­do por `max(360s)=0` ("valor mÃ¡ximo dos Ãºltimos 6 min = 0"), que sÃ³ Ã© verdadeiro quando TODOS os valores do perÃ­odo foram 0 â€” ou seja, exige 6 minutos contÃ­nuos de queda real.

---

## [v2.10.9] â€” 2026-09-23

### Corrigido

- **`pon.status.huawei.py`**: coleta parcial de snmpbulkwalk (menos de 75% dos PONs do backup) nÃ£o sobrescreve mais o cache. Causa: snmpbulkwalk com `-Cr100` pode ser truncado pela OLT (especialmente MA5600), retornando apenas 2-40 PONs de 73-161. O preprocessing JS retornava 0 para os PONs ausentes, zerando itens dependentes e disparando cascata de "Queda Total". CorreÃ§Ã£o: antes de gravar, compara `len(result)` com `len(backup)` â€” descarta se < 75%.

---

## [v2.10.8] â€” 2026-09-23

### Corrigido

- **Huawei OLT 4.4 e 6.0 â€” trigger "Queda Total"**: expressÃ£o alterada de `last()=0` para `min(360s)=0` (6 minutos) e removida condiÃ§Ã£o `change()<>0`. Motivo: cache miss de um ciclo (~5min) causava `[]` retornando do `pon.status.huawei.py`, zerava todos os dependentes e disparava cascata de falsos "Queda Total" em todas as PONs simultaneamente. Com `min(6m)=0`, o trigger sÃ³ dispara quando o item ficou 6 minutos contÃ­nuos em zero â€” tolerando um ciclo de cache miss sem alertar.

---

## [v2.10.7] â€” 2026-09-21

### Corrigido

- **`pon.status.huawei.py`**: valores de offline/LOS/DyingGasp sempre zerados. Causa raiz: tabela `.43.1.2` (hwGponDeviceOntTable) sÃ³ expÃµe ONUs online â€” contagem de auth era sempre igual a online, resultando em offline=0. LOS/DG/LOFi hardcoded como 0. CorreÃ§Ã£o: usar tabela `.46` (hwGponDeviceOntControlInfoTable) que expÃµe TODAS as ONUs provisionadas. Novos OIDs: `46.1.15` (hwGponDeviceOntControlRunStatus: 1=online, 2=offline) e `46.1.24` (hwGponDeviceOntControlLastDownCause: 1=LOS, 2=LOSi, 3/4=LOFi, 9=SFi, 13=DyingGasp). Script agora reporta offline, dg, los, losi, lof com valores reais.

---

## [v2.10.6] â€” 2026-09-21

### Corrigido

- **Discovery de uplinks Huawei 4.4/6.0**: OID ampliado para incluir `{#IFNAME}` (`ifName`, OID `.31.1.1.1.1`) e `{#IFALIAS}` (`ifAlias`); nomes de items, triggers e graphs alterados de `{#IFDESC}` para `{#IFNAME}` â€” resolve alertas com nome duplicado "ETHERNET" para todas as interfaces.
- **Trigger Link DOWN Huawei 6.0**: expressÃ£o corrigida â€” adicionado `diff()=1` e `count(10m)>1`, alinhado com HW 4.4 e regra obrigatÃ³ria do CLAUDE.md (sÃ³ alerta quando interface muda de UP para DOWN).
- **Trigger nodata OLT InacessÃ­vel**: alterado de 5m para 1h em todos os templates (ZTE 4.4/6.0, Huawei 4.4/6.0, Fiberhome 4.4/6.0); templates 4.4 migrados de mÃ©todo interno `zabbix[host,snmp,available]` para expressÃ£o `nodata(1h)=1` correta; triggers habilitados.

---

## [v2.10.5] â€” 2026-09-21

### Corrigido

- **ImportaÃ§Ã£o versÃ£o 2.10.3 e 2.10.4 no Zabbix** (via API)
- **SQL fix Fiberhome**: itens `netstream.dedicado.status[...]` renomeados para `netstream.onu.status.[...]` em hosts de produÃ§Ã£o que mantinham a chave antiga apÃ³s reimport do template.

---

## [v2.10.4] â€” 2026-09-21

### Corrigido

- **Community SNMP hardcoded removida do ZTE 4.4** â€” discovery `netstream.oltonudedicado` usava `S3ML1M1T3` fixo; substituÃ­do por `{$SNMP_COMMUNITY}`.
- **Key `netstream.dedicado.lastcause` renomeada para `netstream.dedicado.offline_reason`** nos templates Huawei 4.4 e 6.0, equalizado com ZTE e Fiberhome.
- **Key `netstream.dedicado.status` renomeada para `netstream.onu.status.`** no Fiberhome 6.0 (5 ocorrÃªncias: item prototype + trigger expressions + recovery expressions), equalizado com ZTE e Huawei.
- **Itens de trÃ¡fego de uplink corrigidos para bps** em ZTE 4.4, Huawei 4.4/6.0, Fiberhome 4.4/6.0:
  - Keys renomeadas: `netstream.uplink.in.bps` â†’ `netstream.uplink.in` e `netstream.uplink.out.bps` â†’ `netstream.uplink.out`
  - Adicionado preprocessing `MULTIPLIER x8` (bytesâ†’bits)
  - Unidades corrigidas: `Bps` â†’ `bps`
  - Referencias atualizadas em trigger expressions (saturaÃ§Ã£o) e graph prototypes
- **Trigger ONU Dedicada offline ZTE 4.4**: tag `tipo=Conectividade` corrigida para `tipo=ONU_Dedicada`, alinhada com ZTE 6.0, Huawei e Fiberhome.

---

## [v2.10.3] â€” 2026-09-21

### Adicionado

- **`netstream.dedicado.sn[{#SNMPINDEX}]`** â€” item prototype "Serial Number" adicionado Ã  discovery de ONU Dedicada em todos os templates OLT (ZTE 4.4/6.0, Huawei 4.4/6.0, Fiberhome 4.4/6.0).
  - OID ZTE: `1.3.6.1.4.1.3902.1012.3.28.1.1.5.{#SNMPINDEX}` (Hex-STRING)
  - OID Huawei: `1.3.6.1.4.1.2011.6.128.1.1.2.43.1.3.{#SNMPINDEX}` (Hex-STRING)
  - OID Fiberhome: `1.3.6.1.4.1.5875.800.3.10.1.1.10.{#SNMPINDEX}`
  - Preprocessing: JavaScript converte Hex-STRING para texto legÃ­vel â€” 4 bytes ASCII (vendor) + bytes restantes em hex maiÃºsculo (ex: `HWTCD1D13DA8`)
  - value_type TEXT, delay 1h, history 30d, sem trends
  - Application: `Clientes Dedicados`

---

## [v2.10.2] â€” 2026-09-21

### Adicionado

- **`NETSTREAM - Discovery ONU Dedicada Huawei`** adicionada aos templates Huawei 4.4 e 6.0. Espelha a discovery `netstream.gpon.onu.dedicado.huawei[{HOST.IP},{$SNMP_COMMUNITY}]` existente no servidor de produÃ§Ã£o. Itens incluÃ­dos: rxpower, lastcause, onu.status, lan.status, lan.speed, lan.duplex, distance, traffic.down (DISABLED), traffic.up (DISABLED). Filtro: `{#NETSTREAM.ONU_DESC}` MATCHES `{$ONU_DEDICADO_FILTER.NETSTREAM}`.

---

## [v2.10.1] â€” 2026-09-21

### Removido

- **`onudisc`** (discovery rule legacy de ONU Dedicada Huawei) removida dos templates Huawei 4.4 e 6.0. SubstituÃ­da pela `netstream.gpon.onu.dedicado.huawei` (discovery padronizada). A coexistÃªncia das duas causava criaÃ§Ã£o de itens duplicados nos hosts.

---

## [v2.10.0] â€” 2026-09-21

### Adicionado

- **Itens `netstream.dedicado.traffic.down[{#SNMPINDEX}]` e `netstream.dedicado.traffic.up[{#SNMPINDEX}]`** adicionados Ã  discovery de ONU Dedicada em todos os templates OLT (ZTE 4.4/6.0, Huawei 4.4/6.0, Fiberhome 4.4). Fiberhome 6.0 jÃ¡ possuÃ­a esses itens.
  - **ZTE e Huawei**: adicionados como `DISABLED` â€” Ã­ndice composto (`portIndex.onuId` / `ponPortIfIndex.onuId`) nÃ£o mapeia IF-MIB. Habilitar somente apÃ³s confirmar OID vendor-especÃ­fico por modelo.
  - **Fiberhome**: adicionados como `ENABLED` â€” Ã­ndice Ãºnico (`ifIndex`) mapeia diretamente IF-MIB (`ifHCOutOctets` / `ifHCInOctets`). Preprocessing: CHANGE_PER_SECOND + MULTIPLIER 8 (bytesâ†’bps).
- **Regra de processo**: novas funcionalidades devem ser commitadas no GitHub para que o usuÃ¡rio aplique em produÃ§Ã£o no momento adequado. Nunca aplicar diretamente no servidor via SQL ou import manual sem OK explÃ­cito do usuÃ¡rio.

---

## [v2.9.2] â€” 2026-09-18

### Corrigido

- **`OLT/externalscripts/pon.status.huawei.py`**, **`pon.status.fiberhome.py`**: adicionado suporte a porta SNMP nÃ£o-padrÃ£o via `sys.argv[3]` (`SNMP_PORT`, default `161`). SNMP target passa a ser `IP:PORTA` quando diferente de 161, compatÃ­vel com `snmpbulkwalk`/`snmpget`.
- **`OLT/externalscripts/pon.discovery.huawei.py`**, **`pon.discovery.fiberhome.py`**: porta propagada ao chamar o script de status em background.
- **`OLT/externalscripts/pon.total.huawei.py`**, **`pon.total.fiberhome.py`**, **`pon.total.zte.py`**: adicionado suporte a porta e corrigido nome do script de status chamado (era `pon_status_*.py` com underscore â€” nome antigo).
- **Templates Huawei OLT (4.4 e 6.0)**, **Fiberhome OLT (4.4 e 6.0)**, **ZTE OLT (4.4)**: adicionada macro `{$SNMP_PORT}` (default `161`) e atualizada chave dos itens externos para `[{HOST.IP},{$SNMP_COMMUNITY},{$SNMP_PORT}]`. **ATENÃ‡ÃƒO**: mudanÃ§a de chave â€” em ambientes com template jÃ¡ importado, os itens com a chave antiga permanecem atÃ© reimport do template no host.

### Identificado

- OLT NOVA ERA - MA5680T (179.48.239.97): usa porta SNMP **1611** â€” configurar `{$SNMP_PORT}=1611` neste host apÃ³s reimport do template.

---

## [v2.9.1] â€” 2026-09-18

### Corrigido

- **`OLT/externalscripts/pon.status.huawei.py`**: regex de `ifDescr` para PONs Huawei sÃ³ casava com modelos que incluem o nÃºmero de porta no campo (`GPON_UNI 0/1/2`). Modelos como MA5608T retornam apenas `GPON_UNI` sem porta â€” o script retornava `[]` e a LLD nunca criava itens. Fix: adicionada coleta paralela de `ifName` (OID `1.3.6.1.2.1.31.1.1.1.1`); quando `ifDescr` nÃ£o contÃ©m a porta, o nome Ã© extraÃ­do do `ifName` (`GPON 0/0/0` â†’ `gpon_0/0/0`). Fallback: decodificar slot/porta do ifIndex.

---

## [v2.9.0] â€” 2026-09-12

### Adicionado

- **MikroTik CCR-1036 â€” Monitoramento de sessÃµes simultÃ¢neas (conntrack).**
  - Item SNMP `mikrotik.conntrack.total` via OID `1.3.6.1.4.1.14988.1.1.9.1.0`, delay 1 min.
  - Triggers WARNING (`> {$CONNTRACK_WARN}`, padrÃ£o 300 k) e HIGH (`> {$CONNTRACK_HIGH}`, padrÃ£o 500 k).
  - GrÃ¡fico "Firewall - SessÃµes SimultÃ¢neas".

- **MikroTik CCR-1036 â€” Monitoramento por range/cliente (SSH).**
  - 3 itens SSH `mikrotik.conntrack.filter[1/2/3]` desabilitados por padrÃ£o.
  - ConfiguraÃ§Ã£o por host via macros `{$CONNTRACK_FILTER.1/2/3}`, `{$MIKROTIK_SSH_USER}` e `{$MIKROTIK_SSH_PASS}`.
  - Executa `/ip firewall connection print count-only where src-address~"PREFIX"` via SSH.

- **MikroTik CCR-1036 â€” LLD top-N IPs por conexÃµes (script externo).**
  - Script `Mikrotik/externalscripts/conntrack.top.mikrotik.py` â€” SSH ao RouterOS, conta conexÃµes por IP de origem, retorna JSON.
  - Shell wrapper `netstream.mikrotik.conntrack.top` seguindo convenÃ§Ã£o de nomenclatura do projeto.
  - Master item EXTERNAL + discovery DEPENDENT com preprocessamento JavaScript â†’ item prototype por IP descoberto.
  - Trigger prototype WARNING por cliente com `> {$CONNTRACK_CLIENT_HIGH}` (padrÃ£o 5 k).
  - Macros: `{$CONNTRACK_TOP_N}` (padrÃ£o 10), `{$CONNTRACK_CLIENT_HIGH}`.

### Alterado

- **Todos os templates OLT (ZTE, Fiberhome, Huawei) â€” delay do master item de status reduzido de 2 m para 1 m.**
  - Afeta `netstream.gpon.pon.status.zte/fiberhome/huawei[...]` em todos os XMLs 4.4 e 6.0.
  - Aplicado tambÃ©m via SQL em produÃ§Ã£o (21 itens atualizados).
  - MotivaÃ§Ã£o: latÃªncia de detecÃ§Ã£o de LOS/DG era de atÃ© 2 min; agora â‰¤ 1 min.

- **Action Zabbix #10 ("Telegram - Reportar Problema no Telegram geral") â€” filtro por tag `notificar`.**
  - Adicionada condiÃ§Ã£o TAG VALUE `notificar = telegram` (conditionid 81).
  - A action agora sÃ³ envia ao Telegram triggers que tenham explicitamente `notificar=telegram`.
  - Corrige envio indevido de alertas LOS ao Telegram apÃ³s reabilitaÃ§Ã£o dos triggers com `notificar=nao`.

- **Action Zabbix #10 â€” exclusÃ£o de hosts DEV do Telegram.**
  - Criado grupo `NETSTREAM/DEV` (groupid 116).
  - Hosts DEV adicionados: ZTE C320 (10928), ZTE C350 (10929), Fiberhome Fortaleza (10937), Fiberhome Dutra 1 (10938).
  - CondiÃ§Ã£o `host group NOT IN NETSTREAM/DEV` (conditionid 82) adicionada Ã  action.

### Corrigido

- **`pon.status.zte.py` â€” contagem de LOS inflada por ONUs online.**
  - Causa: OID `.8.1.7` mantÃ©m Ãºltima razÃ£o de queda para todas as ONUs autorizadas, incluindo online.
  - Fix: adicionado walk do OID `.8.1.2` (status por ONU) para filtrar razÃµes somente a ONUs offline.
  - Validado: gpon_1/2/14 caiu de los=24 â†’ los=0; zero PONs com `los > offline`.

- **Triggers LOS â€” reabilitados com `notificar=nao`.**
  - 553 triggers reabilitados apÃ³s correÃ§Ã£o do script e da action.
  - VisÃ­veis no Zabbix mas sem notificaÃ§Ã£o Telegram.

### Processo

- **CLAUDE.md raiz** â€” adicionadas regras 14 (Changelog e Versionamento) e 15 (Testes com Sub-agente).

---

## [v2.8.0] â€” 2026-08-17

### Adicionado

- **InstalaÃ§Ã£o padrÃ£o do servidor Zabbix (`zabbix-server/setup-zabbix-nginx-pgsql/`).**
  Modelo replicÃ¡vel para subir um Zabbix 7.0 LTS em Debian 13 (Trixie) com Nginx + PHP-FPM
  e PostgreSQL local. ConteÃºdo:
  - Guia passo a passo (`README.md`) com trÃªs caminhos: **automatizado**, **manual** e **cloud-init**.
  - `install.sh` idempotente e nÃ£o-interativo (repositÃ³rio oficial, import de schema, config web
    do frontend sem assistente).
  - `gerar-senhas.sh` â€” senhas fortes e **Ãºnicas por servidor** via `openssl`; segredos nunca
    versionados (`.env` protegido por `.gitignore`, pois o repositÃ³rio Ã© pÃºblico).
  - Hardening (`seguranca/`): firewall `nftables`, HTTPS/TLS, PSK serverâ†”agent, `pg_hba` scram-sha-256.
  - `cloud-init/` para provisionamento de VM (Proxmox/nuvem/NoCloud) no primeiro boot.
  - Tuning do PostgreSQL, script de backup com retenÃ§Ã£o e checklist de validaÃ§Ã£o.
  - Validado em container `debian:13`: pacotes `+debian13`, import de schema e `nginx -t` OK.

---

## [v2.7.0] â€” 2026-07-29

### Corrigido

- **Switch Huawei 6700 â€” OpticalAlias: thundering herd SNMP (grÃ¡ficos picotando em sÃ©rie S).**
  ApÃ³s host recovery, os ~52 itens SNMP GET individuais de `entPhysicalAlias` disparavam
  simultaneamente, sobrecarregando o agente SNMP do switch â†’ timeouts em cascata â†’ host
  marcado indisponÃ­vel novamente â†’ spike nos grÃ¡ficos de trÃ¡fego. Causa raiz: itens
  individuais do tipo SNMPV2 com `delay=1d` todos com `nextcheck=NOW` apÃ³s recovery.
  CorreÃ§Ã£o: redesign para master item (1 snmpwalk externo, `delay=1d`) + itens dependentes
  (preprocessing JSONPath, `delay=0`). Adicionado script `netstream_optical_aliases.sh`.
  Nota secundÃ¡ria: `entPhysicalAlias` fica vazio nos switches testados (aliases nÃ£o
  configurados no equipamento) â€” comportamento normal; o benefÃ­cio Ã© a reduÃ§Ã£o de carga SNMP.

### Adicionado

- **Script `Switch/Huawei/externalscripts/netstream_optical_aliases.sh`** â€” walk Ãºnico do
  OID `entPhysicalAlias` (`.1.3.6.1.2.1.47.1.1.1.1.14`), retorna JSON `{snmpindex: alias}`.
  Suporta porta customizada via `HOST:PORT`. Timeout interno de 12s (abaixo do
  `Timeout=15` do `zabbix_server.conf`).

---

## [v2.6.0] â€” 2026-07-27

### Adicionado

- **Template DNS Monitor (4.4 e 6.0)** â€” monitoramento de servidores DNS via DIG e
  NSLOOKUP com LLD. Discovery automÃ¡tico de combinaÃ§Ãµes servidor Ã— domÃ­nio Ã— tipo de
  registro a partir de macros configurÃ¡veis no host (`{$DNS_SERVERS}`, `{$DNS_DOMAINS}`,
  `{$DNS_TYPES}`). Itens por combinaÃ§Ã£o: tempo de resposta (ms), status (0/1), RCODE e
  resultado da consulta, para ambas as ferramentas. Triggers de lentidÃ£o em dois limiares
  (WARNING/CRITICAL) e de RCODE anormal. Graph prototype sobrepondo DIG e NSLOOKUP.
  Scripts externos: `dns_check.sh` (coleta) e `dns_discover.py` (LLD JSON).
  Pasta: `DNS-Monitor/`.

---

## [v2.5.0] â€” 2026-07-23

### Corrigido

- **ZTE 6.0 â€” `<newvalue>` corrompidos nos valuemaps.** Dois valores estavam truncados:
  `hwOnline (Software nÃ£o carregado)` e `SFi (Falha de sinal ativa)`. (`a3cc871`)
- **ZTE 6.0 â€” 20 expressÃµes de trigger no formato 4.4.** Convertidas para o formato
  Zabbix 6.0 (`{Host:key.func(params)}` â†’ `func(/Host/key,params)`). (`dcdea0d`)
- **ZTE 6.0 â€” 11 trigger prototypes com `{last()}` sem host/key.** Cada trigger
  recebeu a chave correta da sua discovery rule (ONU phase state, PON status, card
  status, CPU/RAM). (`dcdea0d`)
- **ZTE 6.0 â€” `delta()` substituÃ­do por `(max()-min())`.** A funÃ§Ã£o `delta()` foi
  removida no Zabbix 6.0; afetava os triggers de DyingGasp e LOS. (`fc174b8`)
- **ZTE 4.4 â€” sincronizaÃ§Ã£o com as correÃ§Ãµes do 6.0.** Newvalues corrompidos e 10
  trigger prototypes com `{last()}` sem host/key corrigidos na sintaxe 4.4. (`86b9982`)
- **Huawei 4.4 â€” 5 trigger prototypes com `{last()}` sem host/key** (OSPF, Fan, PSU,
  RAM, temperatura). Corrigidos com XML-escape e sintaxe 4.4. (`86b9982`)
- **Huawei 4.4 â€” `snmp_community {}` â†’ `{$SNMP_COMMUNITY}`** em 5 itens. O campo vazio
  causava falha silenciosa de SNMP â†’ "first network error, wait 30 seconds" em
  cascata â†’ unreachable pollers >75% busy â†’ lacunas de dados â†’ grÃ¡ficos picotando.
  Era a raiz dos picos nos grÃ¡ficos PPPoE dos 13 roteadores core. (`2c4b250`)

### Adicionado

- **Huawei 4.4 e 6.0 â€” item prototype `netstream.tempthreshold[{#SNMPINDEX}]`.**
  Coleta o threshold de temperatura configurado no dispositivo (OID
  `1.3.6.1.4.1.2011.5.25.31.1.1.1.1.14.{#SNMPINDEX}`, hwEntityTempThreshold).
  Triggers de temperatura agora comparam contra o limite real do hardware em vez de
  valores fixos. (`aea6401`)
- **`docs/REGRAS_MANUTENCAO_TEMPLATES.md`** â€” documento de 5 regras de processo:
  (1) sempre atualizar 4.4 e 6.0; (2) verificar sintaxe antes de subir;
  (3) revisar guia de problemas; (4) criar tag de versionamento; (5) atualizar
  CHANGELOG a cada mudanÃ§a. (`6036f2b`)

### Alterado

- **Huawei 4.4 e 6.0 â€” itens desativados por padrÃ£o:** `netstream.pppoe.total`,
  `netstream.pppoe.total.max24h`, `netstream.pppoe.total.min24h`, `Tabela Mac`,
  discovery `CPU NE (NetEngine)`, `netstream.hwEntityCpuUsage[{#SNMPINDEX}]`.
  (`aea6401`)
- **Huawei 4.4 â€” itens removidos:** `netstream.ifNumber` (item global) e
  `netstream.ifOperStatus.vlanif.[{#IF}.{#SNMPINDEX}]` (item prototype). (`aea6401`)
- **Huawei 4.4 e 6.0 â€” delay alterado para `1d`** em 5 discovery rules: Physical,
  Sinal single, Multi lane, DomÃ­nios PPPoE, Interfaces Acesso. (`aea6401`)

---

## [v2.4.1] â€” 2026-07-23

### Corrigido

- **Huawei 6.0 â€” import bloqueado por `<status>0</status>`.** A tag `<status>` exige
  constante (`ENABLED`/`DISABLED`), nunca valor numÃ©rico. As 5 entidades afetadas
  declaram "Desativado por padrÃ£o" na descriÃ§Ã£o e estÃ£o desativadas em produÃ§Ã£o, entÃ£o
  passaram a `<status>DISABLED</status>` â€” remover a tag as ativaria indevidamente
  (3 coletas SNMP RADIUS/AAA + 2 discovery rules PPPoE). (`5d81a6f`)
- **Huawei 6.0 â€” `uuid` ausente em 50 entidades.** O Zabbix 6.0 exige `<uuid>` em toda
  entidade de template. Faltava em `discovery_rule` (17), `trigger_prototype` (28) e
  `graph_prototype` (5). UUIDs gerados de forma **determinÃ­stica** (uuid5 sobre
  namespace fixo + `name`/`key`/`expression`), para que regeraÃ§Ãµes futuras produzam os
  mesmos valores e nÃ£o gerem ruÃ­do no diff. (`c7acc41`)
- **Huawei 6.0 â€” `{ITEM.LASTVALUE4}` â†’ `{ITEM.LASTVALUE3}` nos triggers BGP.** As
  expressÃµes referenciam apenas 3 itens (`BgpPeerState`, `BgpPeerAdminStatus`,
  `get_asn_owner_v2.sh`); o Ã­ndice 4 resolvia sempre como `*UNKNOWN*`, impedindo a
  exibiÃ§Ã£o do nome do ASN do peering. Corrigido em 4 lugares (nome + tag `Provider`,
  IPv4 e IPv6). Mesma correÃ§Ã£o jÃ¡ aplicada no template 4.4. (`b9a20a5`, `33ab202`)
- **ZTE â€” encoding de nomes e picos falsos de trÃ¡fego.** (`daa1fd6`)
- **ZTE â€” unidade de temperatura corrompida** (Celsius). (`aae7ede`)
- **ZTE â€” referÃªncias de itens calculados** nos templates de OLT. (`ad95b48`)

### Adicionado

- **Huawei â€” triggers de RX Power alto/baixo + macros Ã³pticas**
  (`{$OPTICAL_RX_HIGH_WARN}` = `0.5` dBm, `{$OPTICAL_RX_LOW_WARN}` = `-12` dBm).
  Detecta **saturaÃ§Ã£o do receptor** â€” sinal acima da faixa linear do transceiver causa
  erros de bit e perda intermitente de pacotes **sem queda de link**, falha que os
  triggers de status operacional nÃ£o enxergam. (`9d2400c`)
- **PadrÃ£o de tags de trigger** documentado em
  [docs/TAGGING_STANDARD.md](docs/TAGGING_STANDARD.md), com as tags do template de OLT
  ZTE alinhadas ao padrÃ£o (`scope`, `tipo`, `interface`). (`e5d59dd`)
- **Script de manutenÃ§Ã£o `zabbix_auto_disable.py`** â€” desativa automaticamente itens
  SNMP com erros repetidos, evitando poluiÃ§Ã£o de fila do poller. Inclui suporte a itens
  calculados e novos padrÃµes de erro. (`6ccb60f`, `cc2ea34`, `c9a4179`, `c1d366d`)

### Alterado

- RetenÃ§Ã£o de histÃ³rico reduzida de `30d` para `14d` (trends preservados). (`33ab514`)

---

## [v2.3.x] â€” 2026-07-13 a 2026-07-14

Descoberta Ã³ptica por script externo e conformidade com o esquema XML do Zabbix 4.4.

### Adicionado

- **`discovery_huawei_optical.sh`** â€” LLD externo que cruza a `entPhysicalTable`
  (mÃ³dulos Ã³pticos) com `ifAlias` (descriÃ§Ã£o da interface), expondo
  `{#ENTPHYSICALNAME}`, `{#IFALIAS}` e `{#ENTALIAS}`. Filtra automaticamente portas sem
  descriÃ§Ã£o ou administrativamente desligadas. CompatÃ­vel com 4.4 e 6.0+. (`29f1df5`)
- Alias de descriÃ§Ã£o `{#ENTALIAS}` nas regras de descoberta de mÃ³dulo Ã³ptico, enriquecendo
  os nomes de trigger com o destino da porta. (`e163e9e`)
- **Guia de troubleshooting de importaÃ§Ã£o XML**
  ([docs/TROUBLESHOOTING_XML_IMPORT.md](docs/TROUBLESHOOTING_XML_IMPORT.md)). (`4a83aa0`)

### Corrigido

- ColisÃ£o de prefixo de OID entre `ifName` e `ifAlias` no `snmpwalk`. (`8eb6b7e`)
- Erros de sintaxe no `discovery_huawei_optical.sh` (parÃªntese e bloco `awk END`).
  (`f105af5`, `9a9f982`)
- **Esquema Zabbix 4.4:** remoÃ§Ã£o de `<status>0</status>` de itens/discovery ativos;
  remoÃ§Ã£o da tag `<status>` de triggers; conversÃ£o de `SNMP_AGENT` para `SNMPV2`;
  `snmp_community` em itens SNMPV2; declaraÃ§Ã£o da application de topo.
  (`1cc0e4b`, `4a83aa0`, `4bcbbf0`, `3543e93`, `4b6b020`)
- Falsos positivos de "equipamento inacessÃ­vel": `nodata` ampliado de `5m` para `15m` e
  item Uptime com coleta a `1m`, eliminando alarmes durante picos de fila do servidor.
  (`b117c56`, `9944205`)

### Alterado

- Discovery rules com intervalo de `1h`; interfaces sem descriÃ§Ã£o ou em shutdown
  administrativo passam a ser filtradas. (`7331028`)

---

## [v2.2.0] â€” 2026-07-08

### Alterado

- PadronizaÃ§Ã£o dos triggers de **reboot (Uptime)** e **offline/nodata** entre os
  templates de OLT ZTE e Switch Huawei. (`46c9db3`)

---

## [v2.0.0 â€“ v2.1.6] â€” 2026-07-08

RefatoraÃ§Ã£o maior do template de OLT ZTE.

### Adicionado

- Descoberta de **ONU dedicada empresarial** enriquecida com sinal Ã³ptico RX, distÃ¢ncia
  e motivo de desconexÃ£o; melhoria no monitoramento de CRC por PON. (`a59e5f7`)
- Suporte a **Zabbix 6.0** e estruturaÃ§Ã£o de trigger tags. (`7b6c89a`)

### Alterado

- **Namespace `netstream.`** aplicado a todas as chaves de item, discovery rules e
  expressÃµes de trigger do template ZTE. (`4fdb609`)

### Corrigido

- **Alarmes falsos eliminados** em portas PON vazias e ONUs em flapping, via tuning
  aplicado a partir da API em produÃ§Ã£o. (`5f1cb85`)
- **Esquema Zabbix 4.4:** constantes `FLOAT`/`TEXT` em `value_type`; `yaxismin`/`yaxismax`
  em vez de `ymin_item_1`/`ymax_item_1`; remoÃ§Ã£o de `drawtype`; `AND_OR` como constante de
  `evaltype`; `params` vazio em todo step de preprocessing; declaraÃ§Ã£o completa de
  applications no bloco de topo.
  (`5bf8214`, `5bc2850`, `b7a4411`, `a7a8ff8`, `9d161f5`, `8e56afd`)

---

## [v1.7.0 â€“ v1.7.4] â€” 2026-07-08

### Adicionado

- **Descoberta BNG/PPPoE** de domÃ­nios e interfaces de acesso, com chaves `netstream.`,
  **desativada por padrÃ£o** e com triggers anti-falso-alarme. (`4e5d27e`)
- Graph prototypes para domÃ­nios e interfaces PPPoE. (`7b162c7`)
- Itens calculados de MÃ­n/MÃ¡x 24h e trigger tags estruturadas para Zabbix Actions. (`442482a`)
- Monitoramento de autenticaÃ§Ã£o **RADIUS/AAA**. (`0bc419c`)

---

## [v1.6.0 â€“ v1.6.4] â€” 2026-07-08

Melhorias nos triggers de BGP.

### Adicionado

- Tag **`Provider`** em todos os triggers de BGP, exibindo o dono do ASN. (`2decd62`)

### Alterado

- SimplificaÃ§Ã£o para **exatamente 1 trigger** de peer down por famÃ­lia (IPv4 e IPv6),
  severidade `HIGH`, eliminando alertas duplicados. (`a89d28d`)
- Sintaxe nativa 4.4 `{Host:item.strlen()}>0` nos triggers de BGP. (`952a47c`)

### Corrigido

- Vazamento de `stderr` no cache do `get_asn_owner_v2.sh` e permissÃµes seguras
  (`0755`, dono `zabbix`) no cache local de ASN. (`2decd62`, `a3e39c7`)

---

## [v1.5.0 â€“ v1.5.9] â€” 2026-07-08

### Adicionado

- **Arquitetura de event tags Ãºnicas** em 100% dos triggers e prototypes. (`07eefec`)
- Descoberta automÃ¡tica (LLD) de **fontes (PSU)** e **consumo de energia do sistema**,
  suportando chassis NetEngine e Switch dinamicamente. (`098f794`)

### Corrigido

- OIDs de PSU atualizados para a HUAWEI-ENTITY-EXT-MIB oficial (Rated Power `.7`,
  Consumed Power `.8`) e consumo total do chassi via `hwSystemPowerUsedPower`.
  (`89807e6`, `31ad9d1`)
- **Mojibake UTF-8** limpo em 100% dos nÃ³s de texto, garantindo nomes â‰¤ 255 caracteres.
  (`ef86f7c`)
- Unicidade da chave de `get_asn_owner_v2.sh` incluindo o IP do peer (`{#IP}`), para
  suportar mÃºltiplas sessÃµes BGP no mesmo ASN. (`9ae18d0`)

---

## [v1.3.3 â€“ v1.4.7] â€” 2026-07-08

### Adicionado

- Descoberta de **peers BGP4+ IPv6** e de **sessÃµes BFD** (regras, itens e triggers).
  (`5eab337`, `92b20e5`)
- Value maps para BFD Session State, Diagnostic Code e Address Type. (`03f012b`)
- Pasta `externalscripts` com o `get_asn_owner_v2.sh` e documentaÃ§Ã£o. (`64517f7`)

### Corrigido

- OIDs de BFD corrigidos para a HUAWEI-BFD-MIB. (`70356be`)
- Conformidade estrita **RFC 4122 UUIDv4** em discovery rules e item prototypes do
  template 6.0. (`2b7f608`)
- Tag `</trigger_prototypes>` ausente no `4.4/Template.xml`. (`28dcabc`)

---

## [v1.1.0 â€“ v1.3.2] â€” 2026-06-24 a 2026-07-08

Entrada dos templates Huawei e suporte a Zabbix 6.0.

### Adicionado

- **Template Switch Huawei 6700 Series** (4.4 e 6.0). (`249f5f3`, `b30520a`)
- **Template OSPF genÃ©rico** via SNMP (RFC 1850) e mÃ©tricas OSPF nos templates Huawei.
  (`9b73d9b`, `04a6663`)
- **Script de auto-descoberta de topologia** via OSPF/BGP. (`fa57814`)
- Descoberta de CPU para roteadores **NetEngine (NE20/NE40)**. (`279e7a1`)
- Guia de tuning do Zabbix 6.0 LTS. (`09754a3`)

### Alterado

- RepositÃ³rio **reorganizado por versÃ£o do Zabbix** (`4.4/`, `6.0/`). (`0e39b2b`)
- Prefixo `netstream.` em todas as chaves (4.4 e 6.0). (`33fd72f`)
- "MemÃ³ria Utilizada" convertida em item calculado (`Size - Free`) para compatibilidade
  entre NE20 e S6700. (`f5b653a`)

### Corrigido

- **Sintaxe Zabbix 6.0:** `params` â†’ `parameters` no preprocessing (mantendo `params` em
  itens `CALCULATED`); `parameters` em formato array; `diff()` substituÃ­do por `change()`;
  escape de `<>` como `&lt;&gt;`; remoÃ§Ã£o de 2Âº parÃ¢metro invÃ¡lido em `last()`.
  (`baccec7`, `c0525e4`, `06ad10f`, `e02e944`, `8b805ef`, `d51d8e8`)
- **UUIDs invÃ¡lidos** (13Âº caractere â‰  `4`) que impediam a importaÃ§Ã£o no 6.0, e UUIDs
  duplicados. (`8eb2ad0`, `3c0bc12`, `3705082`)
- OIDs OSPF: remoÃ§Ã£o de itens com OIDs RFC 1850 invÃ¡lidos na MIB proprietÃ¡ria Huawei.
  (`7e7cbb6`, `f2eea63`)
- `value_type TEXT` e `manual_close YES` no template 4.4. (`f1c2b26`, `0130473`)

---

## [v1.0.0] â€” 2026-05-22

VersÃ£o inicial: template de **OLT GPON ZTE**.

### Adicionado

- Template ZTE GPON OLT com descoberta de portas GPON e ONUs. (`3f2b642`)
- Prototypes de fase de ONU inativa e Ãºltimo motivo de desconexÃ£o. (`5f35917`)
- DescriÃ§Ã£o da PON nos itens e triggers de porta GPON. (`1bbcf56`)
- Triggers de PSU e de placa (offline / not-in-service). (`3e2d7fa`, `1f01c9e`)
- Trigger tags para macros dinÃ¢micas. (`7699d66`)

### Corrigido

- CÃ¡lculo de `getProprietaryIndex` (erro de off-by-one no mapeamento de slot) e
  alinhamento dos Ã­ndices GPON. (`bf079e1`, `3d2ef13`)
- OIDs de temperatura e TX power do SFP das portas GPON (Ã­ndices DDM e multiplicadores).
  (`9e98472`)
- Encoding de caracteres em nomes e descriÃ§Ãµes em portuguÃªs. (`a6b42ed`)

### Alterado

- Templates organizados por tipo de equipamento e fabricante
  (`OLT/ZTE/Template.xml`). (`de18317`)

---

[v2.6.0]: https://github.com/DidoNael/zabbix-templates/compare/v2.5.0...v2.6.0
[v2.5.0]: https://github.com/DidoNael/zabbix-templates/compare/v2.4.1...v2.5.0
[v2.4.1]: https://github.com/DidoNael/zabbix-templates/compare/v2.3.5...v2.4.1
[v2.3.x]: https://github.com/DidoNael/zabbix-templates/compare/v2.2.0...v2.3.5
[v2.2.0]: https://github.com/DidoNael/zabbix-templates/compare/v2.1.6...v2.2.0
[v2.0.0 â€“ v2.1.6]: https://github.com/DidoNael/zabbix-templates/compare/v1.7.4...v2.1.6
[v1.7.0 â€“ v1.7.4]: https://github.com/DidoNael/zabbix-templates/compare/v1.6.4...v1.7.4
[v1.6.0 â€“ v1.6.4]: https://github.com/DidoNael/zabbix-templates/compare/v1.5.9...v1.6.4
[v1.5.0 â€“ v1.5.9]: https://github.com/DidoNael/zabbix-templates/compare/v1.4.7...v1.5.9
[v1.3.3 â€“ v1.4.7]: https://github.com/DidoNael/zabbix-templates/compare/v1.3.2...v1.4.7
[v1.1.0 â€“ v1.3.2]: https://github.com/DidoNael/zabbix-templates/compare/v1.0.0...v1.3.2
[v1.0.0]: https://github.com/DidoNael/zabbix-templates/releases/tag/v1.0.0
