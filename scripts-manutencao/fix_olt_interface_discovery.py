#!/usr/bin/env python3
# fix_olt_interface_discovery.py
#
# Problema: Templates de OLT (Fiberhome, e possivelmente outros) têm uma discovery
# rule "Network Interfaces" que descobre sub-interfaces de ONU (padrão PON slot/porta/onu).
# Isso gera dezenas de milhares de itens inúteis (tráfego por ONU individual).
#
# O que este script faz:
#   1. Busca os hosts OLT com muitos itens (suspeitos de ter o problema)
#   2. Identifica as discovery rules que criaram itens ifHCInOctets[PON X/X/X]
#   3. Adiciona filtro NOT_MATCHES_REGEX para excluir sub-interfaces de ONU
#   4. Deleta os itens já criados com o padrão indesejado
#
# Uso:
#   DRY_RUN=true python3 fix_olt_interface_discovery.py    # só lista, não altera
#   python3 fix_olt_interface_discovery.py                  # aplica correção

import json
import os
import re
import sys
import time
from datetime import datetime

try:
    from urllib.request import urlopen, Request
    from urllib.error import URLError
except ImportError:
    from urllib2 import urlopen, Request, URLError

ZABBIX_API_URL = os.getenv("ZABBIX_API_URL", "http://localhost/zabbix/api_jsonrpc.php")
ZABBIX_USER    = os.getenv("ZABBIX_USER", "Admin")
ZABBIX_PASSWORD= os.getenv("ZABBIX_PASSWORD", "zabbix")
DRY_RUN        = os.getenv("DRY_RUN", "false").lower() == "true"

# Padrão de interface de ONU a EXCLUIR: "PON slot/porta/onu" (três níveis)
# Exemplos: PON 15/3/6, PON 1/9/7, pon_1/2/3
ONU_IFACE_PATTERN = r"(?i)^[A-Za-z_-]*[Pp][Oo][Nn][ _]?\d+/\d+/\d+"

# Prefixo das chaves dos itens criados pela discovery indesejada
# Exemplos: ifHCInOctets[PON 15/3/6], ifHCOutOctets[pon_1/2/3]
ONU_KEY_PREFIXES = [
    "ifHCInOctets[",
    "ifHCOutOctets[",
    "ifInErrors[",
    "ifOutErrors[",
    "ifOperStatus[",
    "ifAdminStatus[",
    "ifHighSpeed[",
    "ifAlias[",
    "ifInDiscards[",
    "ifOutDiscards[",
]

# IDs de formulaid para as condições do filtro a adicionar
FILTER_FORMULAID_START = "Z"  # será calculado dinamicamente


def log(msg):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] {msg}")


def api_call(url, method, params, auth=None):
    payload = {
        "jsonrpc": "2.0",
        "method": method,
        "params": params,
        "id": 1,
    }
    if auth:
        payload["auth"] = auth

    data = json.dumps(payload).encode("utf-8")
    req = Request(url, data=data, headers={"Content-Type": "application/json-rpc"})

    try:
        resp = urlopen(req, timeout=60)
        result = json.loads(resp.read().decode("utf-8"))
    except (URLError, Exception) as e:
        log(f"ERRO na API: {e}")
        sys.exit(1)

    if "error" in result:
        raise RuntimeError(result["error"])

    return result["result"]


def login(url, user, password):
    return api_call(url, "user.login", {"user": user, "password": password})


def logout(url, auth):
    try:
        api_call(url, "user.logout", [], auth)
    except Exception:
        pass


def get_onu_items(url, auth):
    """Busca todos os itens com chave que indica sub-interface de ONU."""
    log("Buscando itens de sub-interface de ONU (ifHCInOctets[PON X/X/X]...)...")

    onu_items = []
    pattern = re.compile(ONU_IFACE_PATTERN)

    for prefix in ONU_KEY_PREFIXES:
        # Uma única chamada com limite alto — Zabbix item.get não tem paginação por offset
        items = api_call(url, "item.get", {
            "output": ["itemid", "name", "key_", "hostid"],
            "search": {"key_": prefix},
            "startSearch": True,
            "selectHosts": ["host", "name"],
            "limit": 50000,
            "limitselect": 1,
        }, auth)

        matched = 0
        for item in items:
            key = item["key_"]
            m = re.match(r"[^[]+\[(.+)\]", key)
            if m and pattern.match(m.group(1)):
                onu_items.append(item)
                matched += 1

        log(f"  {prefix}: {matched} itens de ONU (de {len(items)} total com esse prefixo)")

    # Deduplicar por itemid
    seen = set()
    unique = []
    for item in onu_items:
        if item["itemid"] not in seen:
            seen.add(item["itemid"])
            unique.append(item)

    return unique


def get_onu_discovery_rules(url, auth, onu_items):
    """Identifica as discovery rules de template responsáveis pelos itens de ONU."""
    log("Identificando discovery rules responsáveis...")

    # Pega um item de cada host para identificar o parent_itemid (LLD)
    sample_itemids = [item["itemid"] for item in onu_items[:200]]
    if not sample_itemids:
        return []

    # item.get retorna parent_itemid para itens descobertos via LLD
    items_with_parent = api_call(url, "item.get", {
        "output": ["itemid", "key_", "hostid"],
        "itemids": sample_itemids,
        "selectDiscoveryRule": ["itemid", "name", "templateid"],
    }, auth)

    # Coleta IDs únicos de discovery rules (do template, não do host)
    dr_template_ids = set()
    dr_host_info = {}  # drule_hostid → info
    for item in items_with_parent:
        dr = item.get("discoveryRule")
        if dr and dr.get("itemid"):
            dr_host_id = dr["itemid"]
            dr_host_info[dr_host_id] = dr["name"]
            if dr.get("templateid") and dr["templateid"] != "0":
                dr_template_ids.add(dr["templateid"])

    log(f"  Discovery rules encontradas no host (IDs): {list(dr_host_info.keys())[:10]}")
    log(f"  Discovery rules de template: {list(dr_template_ids)[:10]}")

    if not dr_template_ids:
        log("  AVISO: Não foi possível identificar templates. Usando IDs do host diretamente.")
        return list(dr_host_info.keys())

    return list(dr_template_ids)


def get_current_filter(url, auth, drule_id):
    """Retorna o filtro atual de uma discovery rule."""
    rules = api_call(url, "discoveryrule.get", {
        "output": ["itemid", "name", "filter"],
        "itemids": drule_id,
        "selectFilter": "extend",
    }, auth)
    if rules:
        return rules[0]
    return None


def next_formulaid(existing_ids):
    """Gera próximo formulaid alfabético (A, B, ..., Z, AA, AB, ...)."""
    existing = set(existing_ids)
    # Tenta letras simples primeiro
    for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
        if c not in existing:
            return c
    # Depois combinações
    for c1 in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
        for c2 in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
            comb = c1 + c2
            if comb not in existing:
                return comb
    return "ZZ"


def add_onu_filter(url, auth, drule_id, drule_name):
    """Adiciona condição NOT_MATCHES_REGEX para excluir ONUs na discovery rule."""
    rule = get_current_filter(url, auth, drule_id)
    if not rule:
        log(f"  ERRO: discovery rule {drule_id} não encontrada")
        return False

    current_filter = rule.get("filter", {})
    conditions = current_filter.get("conditions", [])

    # Verifica se já tem o filtro de ONU
    for cond in conditions:
        if ONU_IFACE_PATTERN in cond.get("value", "") or "\\d+/\\d+/\\d+" in cond.get("value", ""):
            log(f"  Filtro de ONU já existe em '{drule_name}' — pulando")
            return False

    # Identifica o macro usado para nome de interface nesta discovery rule
    # Tenta descobrir pelo primeiro item da discovery
    iface_macro = detect_iface_macro(url, auth, drule_id)
    log(f"  Macro de interface detectado: {iface_macro}")

    # Gera novo formulaid
    existing_ids = [c.get("formulaid", "") for c in conditions]
    new_id = next_formulaid(existing_ids)

    # Nova condição: excluir interfaces ONU (PON slot/porta/onu)
    new_condition = {
        "macro": iface_macro,
        "value": r"(?i)^\S*pon[ _]?\d+/\d+/\d+",
        "operator": "NOT_MATCHES_REGEX",
        "formulaid": new_id,
    }
    conditions.append(new_condition)

    new_filter = dict(current_filter)
    new_filter["conditions"] = conditions
    if not new_filter.get("evaltype"):
        new_filter["evaltype"] = "AND"

    prefix = "[DRY-RUN] " if DRY_RUN else ""
    log(f"  {prefix}Adicionando filtro NOT_MATCHES_REGEX '{new_condition['value']}' "
        f"em macro {iface_macro} na rule '{drule_name}' (ID={drule_id})")

    if not DRY_RUN:
        api_call(url, "discoveryrule.update", {
            "itemid": drule_id,
            "filter": new_filter,
        }, auth)
        log(f"  OK — filtro adicionado")

    return True


def detect_iface_macro(url, auth, drule_id):
    """Tenta identificar qual macro ({#IF}, {#IFNAME}, {#IFDES}) é usado na discovery rule."""
    # Busca os item prototypes da discovery rule e olha a chave
    prototypes = api_call(url, "itemprototype.get", {
        "output": ["key_"],
        "discoveryids": drule_id,
        "limit": 5,
    }, auth)

    for proto in prototypes:
        key = proto.get("key_", "")
        # Extrai macros da chave: ifHCInOctets[{#IFNAME}] → {#IFNAME}
        macros = re.findall(r"\{#[A-Z_]+\}", key)
        for macro in macros:
            if "IF" in macro:
                return macro

    # Fallback: macros comuns em ordem de probabilidade
    return "{#IFNAME}"


def delete_onu_items(url, auth, items):
    """Deleta os itens de sub-interface de ONU em lotes."""
    if not items:
        log("Nenhum item para deletar.")
        return 0

    total = len(items)
    prefix = "[DRY-RUN] " if DRY_RUN else ""
    log(f"{prefix}Deletando {total} itens de sub-interface de ONU...")

    if DRY_RUN:
        # Mostra amostra
        hosts_count = {}
        for item in items:
            host = item["hosts"][0]["name"] if item.get("hosts") else "?"
            hosts_count[host] = hosts_count.get(host, 0) + 1
        log("  Distribuição por host:")
        for host, count in sorted(hosts_count.items(), key=lambda x: -x[1]):
            log(f"    {host}: {count} itens")
        return total

    # Deleta em lotes de 100
    deleted = 0
    itemids = [item["itemid"] for item in items]
    batch_size = 100

    for i in range(0, len(itemids), batch_size):
        batch = itemids[i:i + batch_size]
        try:
            api_call(url, "item.delete", batch, auth)
            deleted += len(batch)
            log(f"  Deletados {deleted}/{total}...")
        except RuntimeError as e:
            log(f"  ERRO no lote {i//batch_size + 1}: {e}")
            # Tenta um por um se o lote falhou
            for iid in batch:
                try:
                    api_call(url, "item.delete", [iid], auth)
                    deleted += 1
                except RuntimeError as e2:
                    log(f"    Falhou item {iid}: {e2}")

    log(f"  Total deletado: {deleted}/{total}")
    return deleted


def main():
    log("=== Fix: OLT Interface Discovery — sub-interfaces de ONU ===")
    if DRY_RUN:
        log("MODO DRY-RUN: nenhuma alteração será feita")

    auth = login(ZABBIX_API_URL, ZABBIX_USER, ZABBIX_PASSWORD)
    log("Login OK")

    try:
        # 1. Encontra itens de ONU
        onu_items = get_onu_items(ZABBIX_API_URL, auth)
        log(f"Total de itens de sub-interface ONU encontrados: {len(onu_items)}")

        if not onu_items:
            log("Nenhum item de ONU encontrado. Saindo.")
            return

        # 2. Identifica discovery rules de template responsáveis
        drule_ids = get_onu_discovery_rules(ZABBIX_API_URL, auth, onu_items)
        log(f"Discovery rules a corrigir: {drule_ids}")

        # 3. Adiciona filtro em cada discovery rule
        fixed = 0
        for drule_id in drule_ids:
            rule_info = get_current_filter(ZABBIX_API_URL, auth, drule_id)
            name = rule_info.get("name", drule_id) if rule_info else drule_id
            log(f"\nProcessando discovery rule: '{name}' (ID={drule_id})")
            if add_onu_filter(ZABBIX_API_URL, auth, drule_id, name):
                fixed += 1

        log(f"\nDiscovery rules corrigidas: {fixed}/{len(drule_ids)}")

        # 4. Deleta itens ONU já existentes
        log(f"\n--- Removendo {len(onu_items)} itens de sub-interface ONU já criados ---")
        delete_onu_items(ZABBIX_API_URL, auth, onu_items)

        log("\n=== Concluído ===")
        log("PRÓXIMO PASSO: Exportar o(s) template(s) corrigido(s) do Zabbix e "
            "commitar em OLT/Fiberhome/ no repositório git.")

    except RuntimeError as e:
        log(f"ERRO: {e}")
        sys.exit(1)
    finally:
        logout(ZABBIX_API_URL, auth)


if __name__ == "__main__":
    main()
