#!/usr/bin/env python3
"""
Netstream Topology Auto-Discovery
Consulta API Zabbix, descobre adjacências OSPF/BGP e gera JSON para o plugin Netstream Topology.
"""

import argparse
import json
import re
import sys
import uuid
from typing import Optional

import networkx as nx
import requests
import yaml


# ---------------------------------------------------------------------------
# Zabbix API
# ---------------------------------------------------------------------------

class ZabbixAPI:
    def __init__(self, url: str, token: str = "", user: str = "", password: str = ""):
        self.url = url.rstrip("/") + "/api_jsonrpc.php"
        self._auth = None   # sessão (4.4) ou token (6.0+)
        self._use_bearer = False
        self._id = 0

        if token:
            # Zabbix 6.0+ com API token
            self._auth = token
            self._use_bearer = True
        else:
            self._auth = self._login(user, password)

    def _call(self, method: str, params: dict) -> dict:
        self._id += 1
        headers = {"Content-Type": "application/json"}

        payload = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": self._id,
        }

        if self._use_bearer:
            # Zabbix 6.0+ — token no header
            headers["Authorization"] = f"Bearer {self._auth}"
        elif self._auth and method != "user.login":
            # Zabbix 4.4 / 5.x — auth no body
            payload["auth"] = self._auth

        resp = requests.post(self.url, json=payload, headers=headers, timeout=30)
        resp.raise_for_status()
        data = resp.json()

        if "error" in data:
            raise RuntimeError(f"Zabbix API error: {data['error']}")
        return data.get("result", {})

    def _login(self, user: str, password: str) -> str:
        self._id += 1
        payload = {
            "jsonrpc": "2.0",
            "method": "user.login",
            "params": {"user": user, "password": password},  # 4.4 usa "user", 6.0 usa "username"
            "id": self._id,
        }
        resp = requests.post(self.url, json=payload, timeout=30)
        resp.raise_for_status()
        data = resp.json()
        if "error" in data:
            raise RuntimeError(f"Login failed: {data['error']}")
        return data["result"]

    def get_hosts_with_template(self, template_pattern: str) -> list[dict]:
        templates = self._call("template.get", {
            "output": ["templateid", "name"],
            "search": {"name": template_pattern},
            "searchWildcardsEnabled": True,
        })
        if not templates:
            return []

        template_ids = [t["templateid"] for t in templates]
        return self._call("host.get", {
            "output": ["hostid", "name"],
            "templateids": template_ids,
            "selectInterfaces": ["ip"],
        })

    def get_items_by_pattern(self, hostids: list[str], key_pattern: str) -> list[dict]:
        return self._call("item.get", {
            "output": ["itemid", "hostid", "key_", "lastvalue", "name"],
            "hostids": hostids,
            "search": {"key_": key_pattern.replace("*", "")},
            "searchWildcardsEnabled": True,
        })


# ---------------------------------------------------------------------------
# Discovery logic
# ---------------------------------------------------------------------------

def extract_ip_from_key(key: str) -> Optional[str]:
    """Extrai IP do neighbor a partir do nome do item (ex: ospf.state[GE0/0/1.10.0.0.2])."""
    ip_pattern = r"(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})"
    matches = re.findall(ip_pattern, key)
    if not matches:
        return None
    # O último IP no key costuma ser o neighbor
    return matches[-1]


def build_ip_to_host(hosts: list[dict]) -> dict[str, dict]:
    """Monta mapa de IP → host para cruzamento de neighbors."""
    ip_map: dict[str, dict] = {}
    for host in hosts:
        for iface in host.get("interfaces", []):
            ip = iface.get("ip", "")
            if ip and ip != "0.0.0.0":
                ip_map[ip] = host
    return ip_map


def discover_topology(api: ZabbixAPI, cfg: dict) -> tuple[list[dict], list[dict]]:
    disc = cfg["discovery"]
    layout_cfg = cfg["layout"]

    # 1. Busca hosts com templates OSPF e BGP
    ospf_pattern = disc.get("ospf_template_pattern", "*OSPF*")
    bgp_pattern = disc.get("bgp_template_pattern", "*BGP*")

    print("[1/5] Buscando hosts com templates OSPF e BGP...")
    ospf_hosts = api.get_hosts_with_template(ospf_pattern)
    bgp_hosts = api.get_hosts_with_template(bgp_pattern)

    # Merge sem duplicatas
    all_hosts_map = {h["hostid"]: h for h in ospf_hosts + bgp_hosts}
    all_hosts = list(all_hosts_map.values())
    hostids = list(all_hosts_map.keys())

    print(f"    {len(all_hosts)} hosts encontrados")

    if not all_hosts:
        print("ERRO: Nenhum host encontrado. Verifique os padrões de template no config.yaml.")
        sys.exit(1)

    # 2. Lê items de neighbor
    print("[2/5] Lendo items de vizinhança (OSPF + BGP)...")
    ospf_item_key = disc.get("ospf_item_pattern", "ospf.state[*]")
    bgp_item_key = disc.get("bgp_item_pattern", "bgp.peer.state[*]")

    ospf_items = api.get_items_by_pattern(hostids, ospf_item_key)
    bgp_items = api.get_items_by_pattern(hostids, bgp_item_key)

    print(f"    {len(ospf_items)} items OSPF, {len(bgp_items)} items BGP")

    # 3. Monta mapa IP → host
    ip_to_host = build_ip_to_host(all_hosts)

    # 4. Descobre links
    print("[3/5] Cruzando neighbors...")
    links_seen: set[tuple[str, str]] = set()
    links_raw: list[dict] = []
    external_nodes: dict[str, dict] = {}

    def add_link(src_id: str, tgt_id: str, link_type: str, item: dict):
        key = tuple(sorted([src_id, tgt_id]))
        if key in links_seen:
            return
        links_seen.add(key)
        links_raw.append({
            "source": src_id,
            "target": tgt_id,
            "type": link_type,
            "item_key": item["key_"],
            "hostid": item["hostid"],
        })

    for item in ospf_items:
        neighbor_ip = extract_ip_from_key(item["key_"])
        if not neighbor_ip:
            continue

        src_host = all_hosts_map.get(item["hostid"])
        if not src_host:
            continue

        if neighbor_ip in ip_to_host:
            tgt_host = ip_to_host[neighbor_ip]
            add_link(src_host["hostid"], tgt_host["hostid"], "ospf", item)
        else:
            # Vizinho externo
            ext_id = f"ext_{neighbor_ip}"
            if ext_id not in external_nodes:
                external_nodes[ext_id] = {"hostid": ext_id, "name": neighbor_ip, "external": True}
            add_link(src_host["hostid"], ext_id, "ospf-external", item)

    for item in bgp_items:
        neighbor_ip = extract_ip_from_key(item["key_"])
        if not neighbor_ip:
            continue

        src_host = all_hosts_map.get(item["hostid"])
        if not src_host:
            continue

        if neighbor_ip in ip_to_host:
            tgt_host = ip_to_host[neighbor_ip]
            add_link(src_host["hostid"], tgt_host["hostid"], "bgp", item)
        else:
            ext_id = f"ext_{neighbor_ip}"
            if ext_id not in external_nodes:
                external_nodes[ext_id] = {"hostid": ext_id, "name": neighbor_ip, "external": True}
            add_link(src_host["hostid"], ext_id, "bgp-external", item)

    print(f"    {len(links_raw)} links descobertos, {len(external_nodes)} nós externos")

    # 5. Layout spring
    print("[4/5] Calculando layout...")
    G = nx.Graph()
    for h in all_hosts:
        G.add_node(h["hostid"])
    for ext in external_nodes.values():
        G.add_node(ext["hostid"])
    for link in links_raw:
        G.add_edge(link["source"], link["target"])

    k = layout_cfg.get("spring_k", 200)
    iterations = layout_cfg.get("spring_iterations", 50)
    pos = nx.spring_layout(G, k=k / 100, iterations=iterations, seed=42)

    cw = layout_cfg.get("canvas_width", 1200)
    ch = layout_cfg.get("canvas_height", 800)

    def to_canvas(p):
        x = round((p[0] + 1) * cw / 2)
        y = round((p[1] + 1) * ch / 2)
        return x, y

    # 6. Monta NodeConfig[]
    print("[5/5] Gerando JSON...")
    nodes_json = []

    for h in all_hosts:
        x, y = to_canvas(pos.get(h["hostid"], (0, 0)))
        nodes_json.append({
            "id": h["hostid"],
            "label": h["name"],
            "zabbixHost": h["name"],
            "icon": "router",
            "x": x,
            "y": y,
            "fx": x,
            "fy": y,
        })

    ext_icon = disc.get("external_node_icon", "cloud")
    for ext in external_nodes.values():
        x, y = to_canvas(pos.get(ext["hostid"], (0, 0)))
        nodes_json.append({
            "id": ext["hostid"],
            "label": ext["name"],
            "icon": ext_icon,
            "x": x,
            "y": y,
            "fx": x,
            "fy": y,
        })

    # 7. Monta LinkConfig[]
    link_colors = {
        "ospf": "#73BF69",
        "ospf-external": "#73BF69",
        "bgp": "#F7A35C",
        "bgp-external": "#F7A35C",
    }

    links_json = []
    for link in links_raw:
        link_type = link["type"]
        item_key = link["item_key"]
        host_id = link["hostid"]
        src_host = all_hosts_map.get(host_id, {})

        # Monta métrica vinculada ao item de state
        metrics = []
        if "ospf" in link_type:
            # Tenta encontrar item de cost equivalente substituindo "state" por "cost"
            cost_key = item_key.replace("ospf.state[", "ospf.cost[")
            metrics.append({
                "id": f"ospf_cost_{uuid.uuid4().hex[:6]}",
                "enabled": True,
                "field": cost_key,
                "label": "Cost",
            })
        elif "bgp" in link_type:
            metrics.append({
                "id": f"bgp_state_{uuid.uuid4().hex[:6]}",
                "enabled": True,
                "field": item_key,
                "label": "BGP State",
            })

        # Label do link
        if link_type == "bgp" or link_type == "bgp-external":
            label = "BGP"
        else:
            # Extrai nome da interface do key (ex: ospf.state[GE0/0/1.10.0.0.2] → GE0/0/1)
            m = re.match(r"ospf\.state\[([^\.\]]+)", item_key)
            label = m.group(1) if m else ""

        links_json.append({
            "source": link["source"],
            "target": link["target"],
            "label": label,
            "color": link_colors.get(link_type, "#888888"),
            "metrics": metrics,
        })

    return nodes_json, links_json


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Netstream Topology Auto-Discovery")
    parser.add_argument("--config", default="config.yaml", help="Arquivo de configuração")
    parser.add_argument("--output", help="Arquivo de saída (sobrescreve config)")
    args = parser.parse_args()

    with open(args.config, "r") as f:
        cfg = yaml.safe_load(f)

    zabbix_cfg = cfg["zabbix"]
    api = ZabbixAPI(
        url=zabbix_cfg["url"],
        token=zabbix_cfg.get("token", ""),
        user=zabbix_cfg.get("user", ""),
        password=zabbix_cfg.get("password", ""),
    )

    nodes, links = discover_topology(api, cfg)

    output_file = args.output or cfg.get("output", {}).get("file", "topology.json")
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump({"nodes": nodes, "links": links}, f, ensure_ascii=False, indent=2)

    print(f"\n✅ Topologia gerada: {output_file}")
    print(f"   {len(nodes)} nós | {len(links)} links")
    print(f"\n   → No plugin Grafana: Importar Topologia → cole o conteúdo de {output_file}")


if __name__ == "__main__":
    main()
