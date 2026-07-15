#!/usr/bin/env python3
# zabbix_auto_disable.py
# Desabilita automaticamente itens SNMP que estao com erro repetido (not supported)
# evitando que timeouts SNMP marquem hosts como unreachable e causem gaps nos graficos.
#
# Instalacao:
#   1. Copiar para /usr/local/bin/zabbix_auto_disable.py
#   2. chmod +x /usr/local/bin/zabbix_auto_disable.py
#   3. Adicionar no cron: */5 * * * * /usr/local/bin/zabbix_auto_disable.py >> /var/log/zabbix/auto_disable.log 2>&1
#
# Configuracao: editar as variaveis abaixo ou usar variaveis de ambiente

import json
import os
import sys
import time
from datetime import datetime

try:
    from urllib.request import urlopen, Request
    from urllib.error import URLError
except ImportError:
    from urllib2 import urlopen, Request, URLError

# === CONFIGURACAO ===
ZABBIX_API_URL = os.getenv("ZABBIX_API_URL", "http://localhost/zabbix/api_jsonrpc.php")
ZABBIX_USER = os.getenv("ZABBIX_USER", "Admin")
ZABBIX_PASSWORD = os.getenv("ZABBIX_PASSWORD", "zabbix")

# Tempo minimo (em minutos) que um item deve estar com erro antes de ser desabilitado
MIN_ERROR_MINUTES = int(os.getenv("MIN_ERROR_MINUTES", "10"))

# Tipos de item SNMP (SNMPv1=1, SNMPv2c=4, SNMPv3=6)
SNMP_ITEM_TYPES = [1, 4, 6]

# Erros que indicam timeout/conexao (item.error)
ERROR_PATTERNS = [
    "timeout",
    "network error",
    "cannot connect",
    "no response",
    "unreachable",
]

# Modo dry-run: se True, apenas lista os itens sem desabilitar
DRY_RUN = os.getenv("DRY_RUN", "false").lower() == "true"

# Log file para itens desabilitados (historico)
LOG_FILE = os.getenv("LOG_FILE", "/var/log/zabbix/auto_disable_history.log")


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
        resp = urlopen(req, timeout=30)
        result = json.loads(resp.read().decode("utf-8"))
    except (URLError, Exception) as e:
        log(f"ERRO na API: {e}")
        sys.exit(1)

    if "error" in result:
        log(f"ERRO Zabbix API: {result['error']}")
        sys.exit(1)

    return result["result"]


def login(url, user, password):
    return api_call(url, "user.login", {"user": user, "password": password})


def logout(url, auth):
    try:
        api_call(url, "user.logout", [], auth)
    except Exception:
        pass


def get_unsupported_snmp_items(url, auth):
    """Busca itens SNMP com estado 'not supported' (state=1)"""
    items = api_call(url, "item.get", {
        "output": ["itemid", "name", "key_", "type", "state", "error", "status", "hostid"],
        "filter": {
            "state": 1,       # not supported
            "status": 0,      # habilitado
            "type": SNMP_ITEM_TYPES,
        },
        "selectHosts": ["host", "name"],
        "limit": 500,
    }, auth)
    return items


def get_unsupported_item_prototypes(url, auth):
    """Busca item prototypes SNMP com estado 'not supported'"""
    try:
        items = api_call(url, "itemprototype.get", {
            "output": ["itemid", "name", "key_", "type", "state", "error", "status"],
            "filter": {
                "state": 1,
                "status": 0,
                "type": SNMP_ITEM_TYPES,
            },
            "selectHosts": ["host", "name"],
            "limit": 500,
        }, auth)
        return items
    except Exception:
        return []


def matches_error_pattern(error_text):
    """Verifica se o erro do item bate com os padroes conhecidos"""
    if not error_text:
        return False
    error_lower = error_text.lower()
    return any(p in error_lower for p in ERROR_PATTERNS)


def get_events_for_item(url, auth, itemid):
    """Busca eventos internos recentes do item para ver ha quanto tempo esta com erro"""
    events = api_call(url, "event.get", {
        "output": ["clock", "value"],
        "objectids": itemid,
        "source": 3,        # internal events
        "object": 4,         # item
        "sortfield": "clock",
        "sortorder": "DESC",
        "limit": 5,
    }, auth)
    return events


def disable_item(url, auth, itemid):
    """Desabilita um item (status=1)"""
    return api_call(url, "item.update", {
        "itemid": itemid,
        "status": 1,
    }, auth)


def log_disabled_item(host, item_name, item_key, error):
    """Registra item desabilitado no historico"""
    try:
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        line = f"{ts} | HOST: {host} | ITEM: {item_name} | KEY: {item_key} | ERRO: {error}\n"
        with open(LOG_FILE, "a") as f:
            f.write(line)
    except Exception:
        pass


def main():
    log("=== Inicio da verificacao ===")

    if DRY_RUN:
        log("MODO DRY-RUN: nenhum item sera desabilitado")

    auth = login(ZABBIX_API_URL, ZABBIX_USER, ZABBIX_PASSWORD)
    log("Login OK")

    try:
        items = get_unsupported_snmp_items(ZABBIX_API_URL, auth)
        log(f"Encontrados {len(items)} itens SNMP com erro")

        disabled_count = 0
        skipped_count = 0
        now = int(time.time())
        min_error_seconds = MIN_ERROR_MINUTES * 60

        for item in items:
            error_text = item.get("error", "")
            if not matches_error_pattern(error_text):
                continue

            host_name = item["hosts"][0]["name"] if item.get("hosts") else "desconhecido"
            host_id = item["hosts"][0]["host"] if item.get("hosts") else ""

            events = get_events_for_item(ZABBIX_API_URL, auth, item["itemid"])

            if events:
                last_error_time = int(events[0]["clock"])
                error_age = now - last_error_time
                if error_age < min_error_seconds:
                    skipped_count += 1
                    log(f"  SKIP (erro ha {error_age//60}min < {MIN_ERROR_MINUTES}min): "
                        f"[{host_name}] {item['name']} ({item['key_']})")
                    continue

            log(f"  {'[DRY-RUN] ' if DRY_RUN else ''}DESABILITAR: "
                f"[{host_name}] {item['name']} ({item['key_']}) - {error_text[:80]}")

            if not DRY_RUN:
                try:
                    disable_item(ZABBIX_API_URL, auth, item["itemid"])
                    disabled_count += 1
                    log_disabled_item(host_name, item["name"], item["key_"], error_text)
                except Exception as e:
                    log(f"  ERRO ao desabilitar: {e}")
            else:
                disabled_count += 1

        log(f"=== Resultado: {disabled_count} desabilitados, {skipped_count} ignorados (erro recente) ===")

    finally:
        logout(ZABBIX_API_URL, auth)

    log("=== Fim ===\n")


if __name__ == "__main__":
    main()
