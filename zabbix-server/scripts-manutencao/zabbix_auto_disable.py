#!/usr/bin/env python3
# zabbix_auto_disable.py
# Desabilita automaticamente itens SNMP/calculados que estao com erro repetido
# (not supported), e itens definidos em FORCE_DISABLE_KEYS que estejam ativos
# no host mas que o template ja marcou como desativados.
#
# Instalacao:
#   1. Copiar para /usr/local/bin/zabbix_auto_disable.py
#   2. chmod +x /usr/local/bin/zabbix_auto_disable.py
#   3. Cron: */5 * * * * /usr/local/bin/zabbix_auto_disable.py >> /var/log/zabbix/auto_disable.log 2>&1
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

# Tipos de item a verificar (state=1)
# SNMP: SNMPv1=1, SNMPv2c=4, SNMPv3=6  |  Calculado=15
ITEM_TYPES = [1, 4, 6, 15]

# Itens a desativar SEMPRE que estiverem habilitados no host, independente do estado.
# Usado para forcar desativacao de itens que o template marcou como DISABLED mas que
# hosts existentes ainda mantem ativos (Zabbix nao propaga status DISABLED do template
# para hosts que ja tinham o item ativo).
# Formato: lista de chaves exatas (key_) ou prefixos terminados em '*'
FORCE_DISABLE_KEYS = os.getenv("FORCE_DISABLE_KEYS", "").split(",") if os.getenv("FORCE_DISABLE_KEYS") else [
    # PPPoE totais (template Huawei marcou como DISABLED — hosts existentes ignoram)
    "netstream.pppoe.total",
    "netstream.pppoe.total.max24h",
    "netstream.pppoe.total.min24h",
    # PPPoE por interface (LLD) — nao suportado em roteadores core
    "netstream.pppoe.interface.users*",
    # ifOperStatus.vlanif — item prototype removido do template, ainda existe nos hosts
    "netstream.ifOperStatus.vlanif*",
]
# Remover entradas vazias
FORCE_DISABLE_KEYS = [k.strip() for k in FORCE_DISABLE_KEYS if k.strip()]

# Erros que indicam falha no item
ERROR_PATTERNS = [
    # SNMP / conectividade
    "timeout",
    "network error",
    "cannot connect",
    "no response",
    "unreachable",
    "no such instance",
    "no such object",
    # Preprocessing / tipo
    "preprocessing failed",
    "not suitable for value type",
    "cannot parse",
    # Itens calculados
    "does not exist",
    "cannot evaluate",
    "cannot find value",           # "Cannot find value for expression"
    "history for item",            # "History for item X is empty"
    "invalid value of type",       # "Cannot evaluate expression: invalid value..."
    "not found",                   # chave referenciada ausente
    # Macro invalida (snmp_community vazio ou macro errada)
    "is not a valid macro",
    "unknown macro",
    "macro is not supported",
]

# Modo dry-run: se True, apenas lista os itens sem desabilitar
DRY_RUN = os.getenv("DRY_RUN", "false").lower() == "true"

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


def get_unsupported_items(url, auth):
    """Busca itens habilitados com state=1 (not supported) nos tipos configurados."""
    return api_call(url, "item.get", {
        "output": ["itemid", "name", "key_", "type", "state", "error", "status",
                   "hostid", "lastclock"],
        "filter": {
            "state": 1,
            "status": 0,
            "type": ITEM_TYPES,
        },
        "selectHosts": ["host", "name"],
        "limit": 1000,
    }, auth)


def get_items_by_keys(url, auth, keys):
    """Busca itens habilitados (status=0) com chaves exatas ou prefixo (key*).

    Retorna itens de QUALQUER estado — usado para FORCE_DISABLE_KEYS.
    """
    if not keys:
        return []

    results = []
    for key in keys:
        search_key = key.rstrip("*")
        items = api_call(url, "item.get", {
            "output": ["itemid", "name", "key_", "type", "state", "error",
                       "status", "hostid", "lastclock"],
            "filter": {"status": 0},
            "search": {"key_": search_key},
            "startSearch": True,
            "selectHosts": ["host", "name"],
            "limit": 500,
        }, auth)
        # Se a chave nao termina em *, exigir match exato
        if not key.endswith("*"):
            items = [i for i in items if i["key_"] == key]
        results.extend(items)

    # Deduplicar por itemid
    seen = set()
    unique = []
    for item in results:
        if item["itemid"] not in seen:
            seen.add(item["itemid"])
            unique.append(item)
    return unique


def matches_error_pattern(error_text):
    if not error_text:
        return False
    error_lower = error_text.lower()
    return any(p in error_lower for p in ERROR_PATTERNS)


def get_item_error_age(url, auth, itemid, lastclock):
    """Retorna em segundos ha quanto tempo o item esta com erro.

    Prefere evento interno mais recente; cai para lastclock como fallback.
    """
    events = api_call(url, "event.get", {
        "output": ["clock", "value"],
        "objectids": itemid,
        "source": 3,   # internal
        "object": 4,   # item
        "sortfield": "clock",
        "sortorder": "DESC",
        "limit": 5,
    }, auth)

    now = int(time.time())

    if events:
        return now - int(events[0]["clock"])

    # Fallback: usar lastclock (ultima vez que o item coletou — mesmo que com erro)
    if lastclock and int(lastclock) > 0:
        return now - int(lastclock)

    # Sem referencia: assume erro antigo o suficiente para desativar
    return now


def disable_item(url, auth, itemid):
    return api_call(url, "item.update", {"itemid": itemid, "status": 1}, auth)


def log_disabled_item(host, item_name, item_key, error, reason):
    try:
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        line = (f"{ts} | HOST: {host} | ITEM: {item_name} | KEY: {item_key} | "
                f"RAZAO: {reason} | ERRO: {error}\n")
        with open(LOG_FILE, "a") as f:
            f.write(line)
    except Exception:
        pass


def process_items(url, auth, items, min_error_seconds, reason_label, check_age=True):
    """Processa uma lista de itens, desativando os que satisfazem os criterios.

    Para Fase 1 (check_age=True): o gate e o tempo em state=1, nao o padrao de erro.
    O campo error pode estar vazio mesmo com state=1 — nao use como filtro obrigatorio.
    """
    disabled = 0
    skipped = 0

    for item in items:
        host_name = item["hosts"][0]["name"] if item.get("hosts") else "desconhecido"
        error_text = item.get("error", "")

        if check_age:
            error_age = get_item_error_age(url, auth, item["itemid"],
                                           item.get("lastclock", 0))
            if error_age < min_error_seconds:
                skipped += 1
                log(f"  SKIP (erro ha {error_age // 60}min < {MIN_ERROR_MINUTES}min): "
                    f"[{host_name}] {item['name']} ({item['key_']})")
                continue

        prefix = "[DRY-RUN] " if DRY_RUN else ""
        erro_display = error_text[:80] if error_text else "(sem mensagem de erro)"
        log(f"  {prefix}DESABILITAR ({reason_label}): "
            f"[{host_name}] {item['name']} ({item['key_']}) — {erro_display}")

        if not DRY_RUN:
            try:
                disable_item(url, auth, item["itemid"])
                disabled += 1
                log_disabled_item(host_name, item["name"], item["key_"],
                                  error_text, reason_label)
            except Exception as e:
                log(f"  ERRO ao desabilitar: {e}")
        else:
            disabled += 1

    return disabled, skipped


def main():
    log("=== Inicio da verificacao ===")
    if DRY_RUN:
        log("MODO DRY-RUN: nenhum item sera desabilitado")

    auth = login(ZABBIX_API_URL, ZABBIX_USER, ZABBIX_PASSWORD)
    log("Login OK")

    min_error_seconds = MIN_ERROR_MINUTES * 60
    total_disabled = 0
    total_skipped = 0

    try:
        # --- Fase 1: itens not supported (state=1) com erro conhecido ---
        items_broken = get_unsupported_items(ZABBIX_API_URL, auth)
        log(f"[Fase 1] {len(items_broken)} itens com state=not supported")
        d, s = process_items(ZABBIX_API_URL, auth, items_broken,
                             min_error_seconds, "not-supported", check_age=True)
        total_disabled += d
        total_skipped += s

        # --- Fase 2: itens em FORCE_DISABLE_KEYS (ativo no host, template ja desativou) ---
        if FORCE_DISABLE_KEYS:
            log(f"[Fase 2] Buscando itens de desativacao forcada: {FORCE_DISABLE_KEYS}")
            items_forced = get_items_by_keys(ZABBIX_API_URL, auth, FORCE_DISABLE_KEYS)
            log(f"[Fase 2] {len(items_forced)} itens encontrados habilitados")
            d, _ = process_items(ZABBIX_API_URL, auth, items_forced,
                                 min_error_seconds, "force-disable", check_age=False)
            total_disabled += d
        else:
            log("[Fase 2] FORCE_DISABLE_KEYS vazio — pulando")

        log(f"=== Resultado: {total_disabled} desabilitados, "
            f"{total_skipped} ignorados (erro recente) ===")

    finally:
        logout(ZABBIX_API_URL, auth)

    log("=== Fim ===\n")


if __name__ == "__main__":
    main()
