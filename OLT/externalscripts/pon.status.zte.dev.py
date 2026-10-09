#!/usr/bin/env python3
"""
pon.status.zte.py v2.1 — coleta em duas fases para dados consistentes.

Fase 1 (rápida, ~6s): auth + online + reason  → LOS/DG sem filtro (fallback)
Fase 2 (enriquecimento): onu_state + ifname   → filtra reasons, resolve snmp_idx

Lógica de filtro por PON:
  - onu_state retornou offline_onus > 0  → usa counts filtrados (preciso)
  - onu_state vazio + offline == 0       → força 0 (ONUs online, reason é histórico)
  - onu_state vazio + offline > 0        → mantém fase 1 (queda total real no GPON)
"""
import sys, os, json, time, subprocess, tempfile, shutil, re

if len(sys.argv) < 3:
    print("[]"); sys.exit(0)

OLT_IP      = sys.argv[1]
COMMUNITY   = sys.argv[2]
SNMP_PORT   = sys.argv[3] if len(sys.argv) > 3 else "161"
SNMP_TARGET = "%s:%s" % (OLT_IP, SNMP_PORT) if SNMP_PORT != "161" else OLT_IP

if not OLT_IP or not COMMUNITY:
    print("[]"); sys.exit(0)

_ip = OLT_IP.replace(".", "_")
CACHE_FULL = "/tmp/pon_cache_zte_dev_%s.json" % _ip
CACHE_FAST = "/tmp/pon_cache_zte_dev_%s_fast.json" % _ip
LOCK_FILE  = CACHE_FULL + ".lock"
CACHE_TTL  = 60

OPTS = ["-v2c", "-c", COMMUNITY, "-t", "25", "-r", "1", "-Cr10", SNMP_TARGET]

OID_AUTH      = "1.3.6.1.4.1.3902.1082.500.10.2.2.3.1.14"
OID_ONLINE    = "1.3.6.1.4.1.3902.1082.500.10.2.2.3.1.15"
OID_REASON    = "1.3.6.1.4.1.3902.1082.500.10.2.3.8.1.7"
OID_ONU_STATE = "1.3.6.1.4.1.3902.1082.500.10.2.3.8.1.2"
OID_IFNAME    = "1.3.6.1.2.1.31.1.1.1.1"
OID_IFALIAS   = "1.3.6.1.2.1.31.1.1.1.18"


def _atomic_write(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    try:
        os.rename(tmp, path)
    except OSError:
        try: os.remove(path)
        except: pass
        os.rename(tmp, path)


def _walk_parallel(oids_dict, tmpdir):
    procs = {}
    for key, oid in oids_dict.items():
        procs[key] = subprocess.Popen(
            ["snmpbulkwalk"] + OPTS + [oid],
            stdout=open(tmpdir + "/" + key, "w"),
            stderr=subprocess.PIPE
        )
    for p in procs.values():
        p.wait()
    result = {}
    for key in oids_dict:
        try:
            result[key] = open(tmpdir + "/" + key).read().strip().splitlines()
        except:
            result[key] = []
    return result


def _parse_idx_val(lines, pattern):
    data = {}
    for line in lines:
        m = re.search(pattern, line)
        if m:
            data[m.group(1)] = int(m.group(2))
    return data


def _count_reasons(reason_lines, pon_idx, allowed_onus=None):
    """Conta reason codes para um PON. Se allowed_onus fornecido, filtra por ele."""
    r = {"los": 0, "losi": 0, "lof": 0, "dg": 0, "unk": 0}
    for line in reason_lines:
        m = re.search(r"\.7\.%s\.(\d+)\s+=\s+\S+:\s+(\d+)" % pon_idx, line)
        if not m:
            continue
        onu = m.group(1)
        val = int(m.group(2))
        if allowed_onus is not None and onu not in allowed_onus:
            continue
        if   val == 2: r["los"]  += 1
        elif val == 3: r["losi"] += 1
        elif val == 4: r["lof"]  += 1
        elif val == 9: r["dg"]   += 1
        elif val == 1: r["unk"]  += 1
    return r


def _phase1(tmpdir):
    """3 walks: auth, online, reason. Retorna (lista_pons, reason_lines_raw)."""
    raw = _walk_parallel({
        "auth":   OID_AUTH,
        "online": OID_ONLINE,
        "reason": OID_REASON,
    }, tmpdir)

    auth_data   = _parse_idx_val(raw["auth"],   r"\.(\d+)\s+=\s+\S+:\s+(\d+)")
    online_data = _parse_idx_val(raw["online"], r"\.(\d+)\s+=\s+\S+:\s+(\d+)")

    result = []
    for idx in sorted(auth_data.keys(), key=lambda x: int(x)):
        auth = auth_data[idx]
        if auth == 0:
            continue
        online = online_data.get(idx, 0)
        offline = max(auth - online, 0)
        i = int(idx)
        slot = (i >> 16) & 0xFF
        card = (i >> 8)  & 0xFF
        port = i & 0xFF
        name = "gpon_%d/%d/%d" % (slot, card, port)
        # Fase 1: conta sem filtro (fallback para queda total de PON)
        r = _count_reasons(raw["reason"], idx, allowed_onus=None)
        result.append({
            "idx": idx, "name": name,
            "snmp_idx": None,
            "auth": auth, "online": online, "offline": offline,
            "los": r["los"], "losi": r["losi"], "lof": r["lof"],
            "dg": r["dg"], "unk": r["unk"],
        })
    return result, raw["reason"]


def _phase2_enrich(pons, reason_lines, tmpdir):
    """3 walks: onu_state + ifname + ifalias. Refina counts, resolve snmp_idx e desc."""
    raw = _walk_parallel({
        "onu_state": OID_ONU_STATE,
        "ifname":    OID_IFNAME,
        "ifalias":   OID_IFALIAS,
    }, tmpdir)

    # Mapear nome GPON → snmp_idx via ifName
    name_to_ifidx = {}
    for line in raw["ifname"]:
        m = re.search(r"ifName\.(\d+)\s*=\s*STRING:\s*(\S+)", line)
        if m:
            name_to_ifidx[m.group(2).strip()] = int(m.group(1))

    # Mapear snmp_idx → alias (ifAlias) — descrição configurada na OLT
    ifidx_to_alias = {}
    for line in raw["ifalias"]:
        m = re.search(r"ifAlias\.(\d+)\s*=\s*STRING:\s*(.*)", line)
        if m:
            alias = m.group(2).strip()
            if alias:
                ifidx_to_alias[int(m.group(1))] = alias

    # Montar offline_onus por PON
    offline_onus = {}
    for line in raw["onu_state"]:
        m = re.search(r"\.2\.(\d+)\.(\d+)\s+=\s+\S+:\s+(\d+)", line)
        if not m:
            continue
        pon = m.group(1); onu = m.group(2); state = int(m.group(3))
        if state == 2:
            offline_onus.setdefault(pon, set()).add(onu)

    for pon in pons:
        idx  = pon["idx"]
        name = pon["name"]

        # Resolver snmp_idx via ifName e alias via ifAlias
        snmp_idx = name_to_ifidx.get(name)
        if snmp_idx is not None:
            pon["snmp_idx"] = snmp_idx
            alias = ifidx_to_alias.get(snmp_idx, "")
            if alias:
                pon["desc"] = alias

        offline_expected = pon["offline"]
        actual_offline   = len(offline_onus.get(idx, set()))

        if actual_offline > 0:
            # onu_state retornou dados — usa counts filtrados (elimina histórico)
            r = _count_reasons(reason_lines, idx, allowed_onus=offline_onus[idx])
            pon.update({"los": r["los"], "losi": r["losi"], "lof": r["lof"],
                        "dg": r["dg"], "unk": r["unk"]})
        elif offline_expected == 0:
            # Todas as ONUs online + onu_state sem offline = estado normal
            # Zera reasons (evita contar histórico de ONUs que já voltaram)
            pon.update({"los": 0, "losi": 0, "lof": 0, "dg": 0, "unk": 0})
        # else: offline_expected > 0 e onu_state vazio → queda total no GPON
        #       mantém counts da fase 1 (são os únicos dados disponíveis)


def collect_and_save():
    tmpdir = tempfile.mkdtemp()
    try:
        # Fase 1 — rápida, LOS sem filtro como fallback
        pons, reason_lines = _phase1(tmpdir)
        if pons:
            _atomic_write(CACHE_FAST, pons)

        # Fase 2 — refina com onu_state + ifname
        _phase2_enrich(pons, reason_lines, tmpdir)

        if pons:
            _atomic_write(CACHE_FULL, pons)

    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
        try: os.unlink(LOCK_FILE)
        except: pass


# ── Main ──────────────────────────────────────────────────────────────────────

def _cache_age(path):
    if os.path.exists(path):
        return time.time() - os.path.getmtime(path)
    return 9999

age_full = _cache_age(CACHE_FULL)
lock_age = _cache_age(LOCK_FILE)

if age_full > CACHE_TTL and (not os.path.exists(LOCK_FILE) or lock_age > 180):
    try:
        open(LOCK_FILE, "w").close()
        pid = os.fork()
        if pid == 0:
            os.setsid()
            collect_and_save()
            sys.exit(0)
    except Exception:
        try: os.unlink(LOCK_FILE)
        except: pass

# Preferência: cache completo fresco → cache fast fresco → qualquer existente
age_fast = _cache_age(CACHE_FAST)

if age_full <= CACHE_TTL:
    source = CACHE_FULL
elif age_fast <= CACHE_TTL:
    source = CACHE_FAST
elif os.path.exists(CACHE_FULL):
    source = CACHE_FULL
elif os.path.exists(CACHE_FAST):
    source = CACHE_FAST
else:
    print("[]"); sys.exit(0)

try:
    print(open(source).read())
except:
    print("[]")
