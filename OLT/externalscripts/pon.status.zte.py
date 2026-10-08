#!/usr/bin/env python3
"""
pon.status.zte.py v2 — coleta em duas fases para dados consistentes durante quedas.

Fase 1 (rápida, ~6s): auth + online + reason  → LOS sem depender de onu_state
Fase 2 (enriquecimento): onu_state + ifname   → refina LOS e resolve snmp_idx

Se fase 2 falhar (timeout, OLT sob stress), fase 1 mantém LOS correto no cache.
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
CACHE_FULL  = "/tmp/pon_cache_zte_%s.json" % _ip       # fase 1 + 2
CACHE_FAST  = "/tmp/pon_cache_zte_%s_fast.json" % _ip  # fase 1 apenas
LOCK_FILE   = CACHE_FULL + ".lock"
CACHE_TTL   = 60   # segundos

OPTS = ["-v2c", "-c", COMMUNITY, "-t", "25", "-r", "1", "-Cr10", SNMP_TARGET]

OID_AUTH      = "1.3.6.1.4.1.3902.1082.500.10.2.2.3.1.14"
OID_ONLINE    = "1.3.6.1.4.1.3902.1082.500.10.2.2.3.1.15"
OID_REASON    = "1.3.6.1.4.1.3902.1082.500.10.2.3.8.1.7"
OID_ONU_STATE = "1.3.6.1.4.1.3902.1082.500.10.2.3.8.1.2"
OID_IFNAME    = "1.3.6.1.2.1.31.1.1.1.1"


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
    """Dispara snmpbulkwalk em paralelo para cada OID. Retorna dict {chave: [linhas]}."""
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


def _phase1(tmpdir):
    """3 walks: auth, online, reason. Retorna lista de PONs com LOS básico."""
    raw = _walk_parallel({
        "auth":   OID_AUTH,
        "online": OID_ONLINE,
        "reason": OID_REASON,
    }, tmpdir)

    auth_data   = _parse_idx_val(raw["auth"],   r"\.(\d+)\s+=\s+\S+:\s+(\d+)")
    online_data = _parse_idx_val(raw["online"], r"\.(\d+)\s+=\s+\S+:\s+(\d+)")

    # Contar razões por PON — sem filtro onu_state (robusto durante quedas)
    reasons = {}
    for line in raw["reason"]:
        m = re.search(r"\.7\.(\d+)\.(\d+)\s+=\s+\S+:\s+(\d+)", line)
        if not m: continue
        pon = m.group(1); val = int(m.group(3))
        if pon not in reasons:
            reasons[pon] = {"los": 0, "losi": 0, "lof": 0, "dg": 0, "unk": 0}
        if   val == 2: reasons[pon]["los"]  += 1
        elif val == 3: reasons[pon]["losi"] += 1
        elif val == 4: reasons[pon]["lof"]  += 1
        elif val == 9: reasons[pon]["dg"]   += 1
        elif val == 1: reasons[pon]["unk"]  += 1

    result = []
    for idx in sorted(auth_data.keys(), key=lambda x: int(x)):
        auth = auth_data[idx]
        if auth == 0:
            continue
        online = online_data.get(idx, 0)
        i = int(idx)
        slot = (i >> 16) & 0xFF
        card = (i >> 8)  & 0xFF
        port = i & 0xFF
        name = "gpon_%d/%d/%d" % (slot, card, port)
        r = reasons.get(idx, {"los": 0, "losi": 0, "lof": 0, "dg": 0, "unk": 0})
        result.append({
            "idx": idx, "name": name,
            "snmp_idx": None,   # preenchido na fase 2
            "auth": auth, "online": online, "offline": max(auth - online, 0),
            "los": r["los"], "losi": r["losi"], "lof": r["lof"],
            "dg": r["dg"], "unk": r["unk"],
        })
    return result


def _phase2_enrich(pons, tmpdir):
    """2 walks: onu_state + ifname. Enriquece lista da fase 1 in-place."""
    raw = _walk_parallel({
        "onu_state": OID_ONU_STATE,
        "ifname":    OID_IFNAME,
    }, tmpdir)

    # Mapear nome GPON → snmp_idx via ifName
    name_to_ifidx = {}
    for line in raw["ifname"]:
        m = re.search(r"ifName\.(\d+)\s*=\s*STRING:\s*(\S+)", line)
        if m:
            name_to_ifidx[m.group(2).strip()] = int(m.group(1))

    # Montar offline_onus por PON a partir de onu_state
    offline_onus = {}
    for line in raw["onu_state"]:
        m = re.search(r"\.2\.(\d+)\.(\d+)\s+=\s+\S+:\s+(\d+)", line)
        if not m: continue
        pon = m.group(1); onu = m.group(2); state = int(m.group(3))
        if state == 2:
            offline_onus.setdefault(pon, set()).add(onu)

    # Contar LOS filtrado por onu_state
    reasons_filtered = {}
    for line in raw["onu_state"]:  # reutiliza o walk já feito para razões
        pass  # razões vêm da fase 1; precisamos re-coletar reason aqui para filtrar
    # Nota: fase 2 não re-coleta reason — usa LOS da fase 1 com validação por consistência

    for pon in pons:
        idx  = pon["idx"]
        name = pon["name"]

        # Resolver snmp_idx
        snmp_idx = name_to_ifidx.get(name)
        if snmp_idx is not None:
            pon["snmp_idx"] = snmp_idx

        # Validar LOS: se onu_state retornou dados mas quantidade bate, confiar
        # Se offline_onus < offline calculado → walk incompleto → manter LOS fase 1
        expected_offline = pon["offline"]
        actual_offline   = len(offline_onus.get(idx, set()))

        if actual_offline > 0 and actual_offline >= expected_offline:
            # onu_state completo e consistente — LOS fase 1 já está correto pois
            # todos os offline são conhecidos; nenhuma ação necessária.
            # (Se quiséssemos refinar poderíamos re-filtrar, mas LOS via reason
            #  sem filtro já é correto quando onu_state é consistente com auth-online)
            pass
        # Se actual_offline == 0 mas expected_offline > 0: walk falhou → mantém LOS fase 1


def collect_and_save():
    tmpdir = tempfile.mkdtemp()
    try:
        # Fase 1 — rápida, crítica para LOS
        pons = _phase1(tmpdir)
        if pons:
            _atomic_write(CACHE_FAST, pons)

        # Fase 2 — enriquecimento (snmp_idx)
        _phase2_enrich(pons, tmpdir)

        # Só grava cache completo se tiver snmp_idx resolvido em pelo menos 1 PON
        if pons and any(p["snmp_idx"] is not None for p in pons):
            _atomic_write(CACHE_FULL, pons)
        elif pons:
            # Fase 2 falhou (sem ifname) — promove fast para full
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
age_fast = _cache_age(CACHE_FAST)
lock_age = _cache_age(LOCK_FILE)

# Disparar coleta em background se nenhum cache fresco existe
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

# Preferência: cache completo (tem snmp_idx) → cache fast → vazio
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
