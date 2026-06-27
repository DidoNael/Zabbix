# Topology Auto-Discovery — Design Document

## Sumário

Script Python que consulta a API do Zabbix, descobre adjacências OSPF e BGP, e gera um JSON de topologia importável pelo plugin Netstream Topology Panel.

---

## Understanding Summary

- **O que**: Script Python `topology_discovery.py` que gera `topology.json` com nós e links
- **Por que**: Eliminar o trabalho manual de adicionar nós e links um a um no plugin
- **Para quem**: Clientes do plugin Netstream Topology (feature pública), redes médias (20-100 nós)
- **Fontes de dados**: OSPF neighbors + BGP peers já coletados pelo Zabbix via SNMP
- **Saída**: JSON `{ nodes: NodeConfig[], links: LinkConfig[] }` compatível com o import do plugin
- **Execução**: Manual sob demanda ou via cron no servidor
- **Linguagem**: Python com requests + networkx + pyyaml

## Premissas

- Zabbix com API HTTP habilitada e acessível do servidor onde o script roda
- Hosts no Zabbix já têm templates OSPF/BGP aplicados e coletando dados
- O plugin aceita `{ nodes, links }` com métricas vinculadas por `field` (nome do item Zabbix)
- O layout inicial é calculado automaticamente — o cliente ajusta manualmente depois (seed inicial)

## Non-Goals

- Atualização automática em tempo real da topologia
- Substituição da topologia manual existente (é seed inicial, não sobrescreve)
- Suporte a LLDP (não coletado pelo Zabbix hoje)

---

## Arquitetura

```
Zabbix API (HTTP)
       │
       ▼
 topology_discovery.py
  ├── 1. Autentica na API Zabbix
  ├── 2. Lista hosts com templates OSPF/BGP
  ├── 3. Lê items de vizinhança de cada host
  ├── 4. Cruza neighbors (A→B e B→A = 1 link)
  ├── 5. Calcula posição x,y dos nós (layout spring)
  ├── 6. Monta NodeConfig[] + LinkConfig[] com métricas
  └── 7. Salva topology.json
       │
       ▼
  topology.json  →  Plugin: Importar → cola o JSON
```

---

## Descoberta de Nós

Cada host no Zabbix com template OSPF ou BGP vira um nó:

```
NodeConfig:
  id         = host.hostid
  label      = host.name
  zabbixHost = host.name
  icon       = "router"
  x, y       = calculado pelo layout spring
```

---

## Descoberta de Links

**OSPF**: lê items `ospf.state[*]` de cada host, extrai IP do neighbor do nome do item, cruza com IPs dos outros hosts.

```
Host-A: ospf.state[GE0/0/1.10.0.0.2]  → neighbor = 10.0.0.2
Host-B: interface com IP 10.0.0.2      → link A↔B (OSPF)
```

**BGP**: mesma lógica com items `bgp.peer.state[*]`.

**Deduplicação**: A→B e B→A geram apenas 1 link. OSPF tem prioridade sobre BGP quando ambos existem entre o mesmo par.

**Métricas no link** (geradas automaticamente):
```json
{
  "metrics": [{
    "id": "ospf_cost",
    "field": "ospf.cost[{interface}.{ip}]",
    "label": "Cost"
  }]
}
```

---

## Layout Automático

Algoritmo Fruchterman-Reingold via `networkx`:

```python
pos = nx.spring_layout(G, k=200, iterations=50, seed=42)
node.x = (pos[id][0] + 1) * canvas_width  / 2
node.y = (pos[id][1] + 1) * canvas_height / 2
```

Nós conectados por OSPF ficam agrupados naturalmente. O cliente arrasta para ajuste fino.

---

## Diferenciação Visual

| Tipo | Cor do link | Label |
|------|-------------|-------|
| OSPF | `#73BF69`   | Interface local |
| BGP  | `#F7A35C`   | "BGP" + IP peer |
| Externo (peer sem host no Zabbix) | `#888888` | IP do peer |

---

## Casos de Borda

| Situação | Comportamento |
|---|---|
| Neighbor IP não casa com nenhum host | Cria nó "externo" com label = IP, ícone cloud |
| Host tem OSPF e BGP com mesmo vizinho | 2 links paralelos (um de cada tipo) |
| Item sem dado no Zabbix | Link criado sem métrica (`metrics: []`) |
| Host sem IP cadastrado no Zabbix | Usa nome do host, avisa no log |
| Link bidirecional A→B e B→A | Deduplica, mantém 1 link |

---

## Configuração (`config.yaml`)

```yaml
zabbix:
  url: https://zabbix.empresa.com
  token: xxxx                    # ou user/password

discovery:
  ospf_item_pattern: "ospf.state[*]"
  bgp_item_pattern: "bgp.peer.state[*]"
  external_node_icon: "cloud"

layout:
  canvas_width: 1200
  canvas_height: 800
  spring_k: 200
  spring_iterations: 50

output:
  file: topology.json
```

**Execução:**
```bash
# Manual
python topology_discovery.py --config config.yaml

# Cron (diário às 6h)
0 6 * * * /opt/netstream/topology_discovery.py --config /opt/netstream/config.yaml
```

**Dependências:**
```
requests
networkx
pyyaml
```

---

## Decision Log

| Decisão | Alternativas consideradas | Motivo |
|---|---|---|
| Script externo Python | Plugin frontend, API própria | Acesso direto à API Zabbix, zero infraestrutura extra no Grafana |
| Saída JSON importável | Dashboard JSON completo | Menos acoplamento — cliente decide quando importar |
| Seed inicial (não substitui) | Auto-substituir topologia | Preserva personalizações manuais pós-import |
| networkx spring_layout | D3 force, circular, manual | Disponível em Python, resultado natural para topologias de rede |
| OSPF + BGP (sem LLDP) | Só OSPF, todos os protocolos | LLDP não coletado pelo Zabbix atualmente |
| Vizinhos externos viram nós "cloud" | Ignorar, logar e pular | Visibilidade de peers externos (ex: upstream BGP) |
