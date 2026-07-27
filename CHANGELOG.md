# Changelog

Todas as mudanças relevantes deste repositório de templates Zabbix.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e o
versionamento segue [SemVer](https://semver.org/lang/pt-BR/).

**Escopo do repositório:** templates Zabbix (4.4 e 6.0) para OLT ZTE, Switch/Router
Huawei, OSPF genérico, ISP Experience e DNS Monitor, além de scripts de descoberta externa
(`externalscripts`), scripts de manutenção e documentação.

> **Convenção de compatibilidade:** cada template existe em pastas por versão do
> Zabbix (`4.4/` e `6.0/`). As duas versões têm esquemas XML incompatíveis entre si —
> ver [docs/TROUBLESHOOTING_XML_IMPORT.md](docs/TROUBLESHOOTING_XML_IMPORT.md).

---

## [v2.6.0] — 2026-07-27

### Adicionado

- **Template DNS Monitor (4.4 e 6.0)** — monitoramento de servidores DNS via DIG e
  NSLOOKUP com LLD. Discovery automático de combinações servidor × domínio × tipo de
  registro a partir de macros configuráveis no host (`{$DNS_SERVERS}`, `{$DNS_DOMAINS}`,
  `{$DNS_TYPES}`). Itens por combinação: tempo de resposta (ms), status (0/1), RCODE e
  resultado da consulta, para ambas as ferramentas. Triggers de lentidão em dois limiares
  (WARNING/CRITICAL) e de RCODE anormal. Graph prototype sobrepondo DIG e NSLOOKUP.
  Scripts externos: `dns_check.sh` (coleta) e `dns_discover.py` (LLD JSON).
  Pasta: `DNS-Monitor/`.

---

## [v2.5.0] — 2026-07-23

### Corrigido

- **ZTE 6.0 — `<newvalue>` corrompidos nos valuemaps.** Dois valores estavam truncados:
  `hwOnline (Software não carregado)` e `SFi (Falha de sinal ativa)`. (`a3cc871`)
- **ZTE 6.0 — 20 expressões de trigger no formato 4.4.** Convertidas para o formato
  Zabbix 6.0 (`{Host:key.func(params)}` → `func(/Host/key,params)`). (`dcdea0d`)
- **ZTE 6.0 — 11 trigger prototypes com `{last()}` sem host/key.** Cada trigger
  recebeu a chave correta da sua discovery rule (ONU phase state, PON status, card
  status, CPU/RAM). (`dcdea0d`)
- **ZTE 6.0 — `delta()` substituído por `(max()-min())`.** A função `delta()` foi
  removida no Zabbix 6.0; afetava os triggers de DyingGasp e LOS. (`fc174b8`)
- **ZTE 4.4 — sincronização com as correções do 6.0.** Newvalues corrompidos e 10
  trigger prototypes com `{last()}` sem host/key corrigidos na sintaxe 4.4. (`86b9982`)
- **Huawei 4.4 — 5 trigger prototypes com `{last()}` sem host/key** (OSPF, Fan, PSU,
  RAM, temperatura). Corrigidos com XML-escape e sintaxe 4.4. (`86b9982`)
- **Huawei 4.4 — `snmp_community {}` → `{$SNMP_COMMUNITY}`** em 5 itens. O campo vazio
  causava falha silenciosa de SNMP → "first network error, wait 30 seconds" em
  cascata → unreachable pollers >75% busy → lacunas de dados → gráficos picotando.
  Era a raiz dos picos nos gráficos PPPoE dos 13 roteadores core. (`2c4b250`)

### Adicionado

- **Huawei 4.4 e 6.0 — item prototype `netstream.tempthreshold[{#SNMPINDEX}]`.**
  Coleta o threshold de temperatura configurado no dispositivo (OID
  `1.3.6.1.4.1.2011.5.25.31.1.1.1.1.14.{#SNMPINDEX}`, hwEntityTempThreshold).
  Triggers de temperatura agora comparam contra o limite real do hardware em vez de
  valores fixos. (`aea6401`)
- **`docs/REGRAS_MANUTENCAO_TEMPLATES.md`** — documento de 5 regras de processo:
  (1) sempre atualizar 4.4 e 6.0; (2) verificar sintaxe antes de subir;
  (3) revisar guia de problemas; (4) criar tag de versionamento; (5) atualizar
  CHANGELOG a cada mudança. (`6036f2b`)

### Alterado

- **Huawei 4.4 e 6.0 — itens desativados por padrão:** `netstream.pppoe.total`,
  `netstream.pppoe.total.max24h`, `netstream.pppoe.total.min24h`, `Tabela Mac`,
  discovery `CPU NE (NetEngine)`, `netstream.hwEntityCpuUsage[{#SNMPINDEX}]`.
  (`aea6401`)
- **Huawei 4.4 — itens removidos:** `netstream.ifNumber` (item global) e
  `netstream.ifOperStatus.vlanif.[{#IF}.{#SNMPINDEX}]` (item prototype). (`aea6401`)
- **Huawei 4.4 e 6.0 — delay alterado para `1d`** em 5 discovery rules: Physical,
  Sinal single, Multi lane, Domínios PPPoE, Interfaces Acesso. (`aea6401`)

---

## [v2.4.1] — 2026-07-23

### Corrigido

- **Huawei 6.0 — import bloqueado por `<status>0</status>`.** A tag `<status>` exige
  constante (`ENABLED`/`DISABLED`), nunca valor numérico. As 5 entidades afetadas
  declaram "Desativado por padrão" na descrição e estão desativadas em produção, então
  passaram a `<status>DISABLED</status>` — remover a tag as ativaria indevidamente
  (3 coletas SNMP RADIUS/AAA + 2 discovery rules PPPoE). (`5d81a6f`)
- **Huawei 6.0 — `uuid` ausente em 50 entidades.** O Zabbix 6.0 exige `<uuid>` em toda
  entidade de template. Faltava em `discovery_rule` (17), `trigger_prototype` (28) e
  `graph_prototype` (5). UUIDs gerados de forma **determinística** (uuid5 sobre
  namespace fixo + `name`/`key`/`expression`), para que regerações futuras produzam os
  mesmos valores e não gerem ruído no diff. (`c7acc41`)
- **Huawei 6.0 — `{ITEM.LASTVALUE4}` → `{ITEM.LASTVALUE3}` nos triggers BGP.** As
  expressões referenciam apenas 3 itens (`BgpPeerState`, `BgpPeerAdminStatus`,
  `get_asn_owner_v2.sh`); o índice 4 resolvia sempre como `*UNKNOWN*`, impedindo a
  exibição do nome do ASN do peering. Corrigido em 4 lugares (nome + tag `Provider`,
  IPv4 e IPv6). Mesma correção já aplicada no template 4.4. (`b9a20a5`, `33ab202`)
- **ZTE — encoding de nomes e picos falsos de tráfego.** (`daa1fd6`)
- **ZTE — unidade de temperatura corrompida** (Celsius). (`aae7ede`)
- **ZTE — referências de itens calculados** nos templates de OLT. (`ad95b48`)

### Adicionado

- **Huawei — triggers de RX Power alto/baixo + macros ópticas**
  (`{$OPTICAL_RX_HIGH_WARN}` = `0.5` dBm, `{$OPTICAL_RX_LOW_WARN}` = `-12` dBm).
  Detecta **saturação do receptor** — sinal acima da faixa linear do transceiver causa
  erros de bit e perda intermitente de pacotes **sem queda de link**, falha que os
  triggers de status operacional não enxergam. (`9d2400c`)
- **Padrão de tags de trigger** documentado em
  [docs/TAGGING_STANDARD.md](docs/TAGGING_STANDARD.md), com as tags do template de OLT
  ZTE alinhadas ao padrão (`scope`, `tipo`, `interface`). (`e5d59dd`)
- **Script de manutenção `zabbix_auto_disable.py`** — desativa automaticamente itens
  SNMP com erros repetidos, evitando poluição de fila do poller. Inclui suporte a itens
  calculados e novos padrões de erro. (`6ccb60f`, `cc2ea34`, `c9a4179`, `c1d366d`)

### Alterado

- Retenção de histórico reduzida de `30d` para `14d` (trends preservados). (`33ab514`)

---

## [v2.3.x] — 2026-07-13 a 2026-07-14

Descoberta óptica por script externo e conformidade com o esquema XML do Zabbix 4.4.

### Adicionado

- **`discovery_huawei_optical.sh`** — LLD externo que cruza a `entPhysicalTable`
  (módulos ópticos) com `ifAlias` (descrição da interface), expondo
  `{#ENTPHYSICALNAME}`, `{#IFALIAS}` e `{#ENTALIAS}`. Filtra automaticamente portas sem
  descrição ou administrativamente desligadas. Compatível com 4.4 e 6.0+. (`29f1df5`)
- Alias de descrição `{#ENTALIAS}` nas regras de descoberta de módulo óptico, enriquecendo
  os nomes de trigger com o destino da porta. (`e163e9e`)
- **Guia de troubleshooting de importação XML**
  ([docs/TROUBLESHOOTING_XML_IMPORT.md](docs/TROUBLESHOOTING_XML_IMPORT.md)). (`4a83aa0`)

### Corrigido

- Colisão de prefixo de OID entre `ifName` e `ifAlias` no `snmpwalk`. (`8eb6b7e`)
- Erros de sintaxe no `discovery_huawei_optical.sh` (parêntese e bloco `awk END`).
  (`f105af5`, `9a9f982`)
- **Esquema Zabbix 4.4:** remoção de `<status>0</status>` de itens/discovery ativos;
  remoção da tag `<status>` de triggers; conversão de `SNMP_AGENT` para `SNMPV2`;
  `snmp_community` em itens SNMPV2; declaração da application de topo.
  (`1cc0e4b`, `4a83aa0`, `4bcbbf0`, `3543e93`, `4b6b020`)
- Falsos positivos de "equipamento inacessível": `nodata` ampliado de `5m` para `15m` e
  item Uptime com coleta a `1m`, eliminando alarmes durante picos de fila do servidor.
  (`b117c56`, `9944205`)

### Alterado

- Discovery rules com intervalo de `1h`; interfaces sem descrição ou em shutdown
  administrativo passam a ser filtradas. (`7331028`)

---

## [v2.2.0] — 2026-07-08

### Alterado

- Padronização dos triggers de **reboot (Uptime)** e **offline/nodata** entre os
  templates de OLT ZTE e Switch Huawei. (`46c9db3`)

---

## [v2.0.0 – v2.1.6] — 2026-07-08

Refatoração maior do template de OLT ZTE.

### Adicionado

- Descoberta de **ONU dedicada empresarial** enriquecida com sinal óptico RX, distância
  e motivo de desconexão; melhoria no monitoramento de CRC por PON. (`a59e5f7`)
- Suporte a **Zabbix 6.0** e estruturação de trigger tags. (`7b6c89a`)

### Alterado

- **Namespace `netstream.`** aplicado a todas as chaves de item, discovery rules e
  expressões de trigger do template ZTE. (`4fdb609`)

### Corrigido

- **Alarmes falsos eliminados** em portas PON vazias e ONUs em flapping, via tuning
  aplicado a partir da API em produção. (`5f1cb85`)
- **Esquema Zabbix 4.4:** constantes `FLOAT`/`TEXT` em `value_type`; `yaxismin`/`yaxismax`
  em vez de `ymin_item_1`/`ymax_item_1`; remoção de `drawtype`; `AND_OR` como constante de
  `evaltype`; `params` vazio em todo step de preprocessing; declaração completa de
  applications no bloco de topo.
  (`5bf8214`, `5bc2850`, `b7a4411`, `a7a8ff8`, `9d161f5`, `8e56afd`)

---

## [v1.7.0 – v1.7.4] — 2026-07-08

### Adicionado

- **Descoberta BNG/PPPoE** de domínios e interfaces de acesso, com chaves `netstream.`,
  **desativada por padrão** e com triggers anti-falso-alarme. (`4e5d27e`)
- Graph prototypes para domínios e interfaces PPPoE. (`7b162c7`)
- Itens calculados de Mín/Máx 24h e trigger tags estruturadas para Zabbix Actions. (`442482a`)
- Monitoramento de autenticação **RADIUS/AAA**. (`0bc419c`)

---

## [v1.6.0 – v1.6.4] — 2026-07-08

Melhorias nos triggers de BGP.

### Adicionado

- Tag **`Provider`** em todos os triggers de BGP, exibindo o dono do ASN. (`2decd62`)

### Alterado

- Simplificação para **exatamente 1 trigger** de peer down por família (IPv4 e IPv6),
  severidade `HIGH`, eliminando alertas duplicados. (`a89d28d`)
- Sintaxe nativa 4.4 `{Host:item.strlen()}>0` nos triggers de BGP. (`952a47c`)

### Corrigido

- Vazamento de `stderr` no cache do `get_asn_owner_v2.sh` e permissões seguras
  (`0755`, dono `zabbix`) no cache local de ASN. (`2decd62`, `a3e39c7`)

---

## [v1.5.0 – v1.5.9] — 2026-07-08

### Adicionado

- **Arquitetura de event tags únicas** em 100% dos triggers e prototypes. (`07eefec`)
- Descoberta automática (LLD) de **fontes (PSU)** e **consumo de energia do sistema**,
  suportando chassis NetEngine e Switch dinamicamente. (`098f794`)

### Corrigido

- OIDs de PSU atualizados para a HUAWEI-ENTITY-EXT-MIB oficial (Rated Power `.7`,
  Consumed Power `.8`) e consumo total do chassi via `hwSystemPowerUsedPower`.
  (`89807e6`, `31ad9d1`)
- **Mojibake UTF-8** limpo em 100% dos nós de texto, garantindo nomes ≤ 255 caracteres.
  (`ef86f7c`)
- Unicidade da chave de `get_asn_owner_v2.sh` incluindo o IP do peer (`{#IP}`), para
  suportar múltiplas sessões BGP no mesmo ASN. (`9ae18d0`)

---

## [v1.3.3 – v1.4.7] — 2026-07-08

### Adicionado

- Descoberta de **peers BGP4+ IPv6** e de **sessões BFD** (regras, itens e triggers).
  (`5eab337`, `92b20e5`)
- Value maps para BFD Session State, Diagnostic Code e Address Type. (`03f012b`)
- Pasta `externalscripts` com o `get_asn_owner_v2.sh` e documentação. (`64517f7`)

### Corrigido

- OIDs de BFD corrigidos para a HUAWEI-BFD-MIB. (`70356be`)
- Conformidade estrita **RFC 4122 UUIDv4** em discovery rules e item prototypes do
  template 6.0. (`2b7f608`)
- Tag `</trigger_prototypes>` ausente no `4.4/Template.xml`. (`28dcabc`)

---

## [v1.1.0 – v1.3.2] — 2026-06-24 a 2026-07-08

Entrada dos templates Huawei e suporte a Zabbix 6.0.

### Adicionado

- **Template Switch Huawei 6700 Series** (4.4 e 6.0). (`249f5f3`, `b30520a`)
- **Template OSPF genérico** via SNMP (RFC 1850) e métricas OSPF nos templates Huawei.
  (`9b73d9b`, `04a6663`)
- **Script de auto-descoberta de topologia** via OSPF/BGP. (`fa57814`)
- Descoberta de CPU para roteadores **NetEngine (NE20/NE40)**. (`279e7a1`)
- Guia de tuning do Zabbix 6.0 LTS. (`09754a3`)

### Alterado

- Repositório **reorganizado por versão do Zabbix** (`4.4/`, `6.0/`). (`0e39b2b`)
- Prefixo `netstream.` em todas as chaves (4.4 e 6.0). (`33fd72f`)
- "Memória Utilizada" convertida em item calculado (`Size - Free`) para compatibilidade
  entre NE20 e S6700. (`f5b653a`)

### Corrigido

- **Sintaxe Zabbix 6.0:** `params` → `parameters` no preprocessing (mantendo `params` em
  itens `CALCULATED`); `parameters` em formato array; `diff()` substituído por `change()`;
  escape de `<>` como `&lt;&gt;`; remoção de 2º parâmetro inválido em `last()`.
  (`baccec7`, `c0525e4`, `06ad10f`, `e02e944`, `8b805ef`, `d51d8e8`)
- **UUIDs inválidos** (13º caractere ≠ `4`) que impediam a importação no 6.0, e UUIDs
  duplicados. (`8eb2ad0`, `3c0bc12`, `3705082`)
- OIDs OSPF: remoção de itens com OIDs RFC 1850 inválidos na MIB proprietária Huawei.
  (`7e7cbb6`, `f2eea63`)
- `value_type TEXT` e `manual_close YES` no template 4.4. (`f1c2b26`, `0130473`)

---

## [v1.0.0] — 2026-05-22

Versão inicial: template de **OLT GPON ZTE**.

### Adicionado

- Template ZTE GPON OLT com descoberta de portas GPON e ONUs. (`3f2b642`)
- Prototypes de fase de ONU inativa e último motivo de desconexão. (`5f35917`)
- Descrição da PON nos itens e triggers de porta GPON. (`1bbcf56`)
- Triggers de PSU e de placa (offline / not-in-service). (`3e2d7fa`, `1f01c9e`)
- Trigger tags para macros dinâmicas. (`7699d66`)

### Corrigido

- Cálculo de `getProprietaryIndex` (erro de off-by-one no mapeamento de slot) e
  alinhamento dos índices GPON. (`bf079e1`, `3d2ef13`)
- OIDs de temperatura e TX power do SFP das portas GPON (índices DDM e multiplicadores).
  (`9e98472`)
- Encoding de caracteres em nomes e descrições em português. (`a6b42ed`)

### Alterado

- Templates organizados por tipo de equipamento e fabricante
  (`OLT/ZTE/Template.xml`). (`de18317`)

---

[v2.6.0]: https://github.com/DidoNael/zabbix-templates/compare/v2.5.0...v2.6.0
[v2.5.0]: https://github.com/DidoNael/zabbix-templates/compare/v2.4.1...v2.5.0
[v2.4.1]: https://github.com/DidoNael/zabbix-templates/compare/v2.3.5...v2.4.1
[v2.3.x]: https://github.com/DidoNael/zabbix-templates/compare/v2.2.0...v2.3.5
[v2.2.0]: https://github.com/DidoNael/zabbix-templates/compare/v2.1.6...v2.2.0
[v2.0.0 – v2.1.6]: https://github.com/DidoNael/zabbix-templates/compare/v1.7.4...v2.1.6
[v1.7.0 – v1.7.4]: https://github.com/DidoNael/zabbix-templates/compare/v1.6.4...v1.7.4
[v1.6.0 – v1.6.4]: https://github.com/DidoNael/zabbix-templates/compare/v1.5.9...v1.6.4
[v1.5.0 – v1.5.9]: https://github.com/DidoNael/zabbix-templates/compare/v1.4.7...v1.5.9
[v1.3.3 – v1.4.7]: https://github.com/DidoNael/zabbix-templates/compare/v1.3.2...v1.4.7
[v1.1.0 – v1.3.2]: https://github.com/DidoNael/zabbix-templates/compare/v1.0.0...v1.3.2
[v1.0.0]: https://github.com/DidoNael/zabbix-templates/releases/tag/v1.0.0
