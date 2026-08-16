#!/usr/bin/env python3
"""
pon_status.py - retorna JSON do cache se existir e for recente,
e dispara coleta em background se o cache estiver desatualizado.
"""
import sys, os, json, time, subprocess, tempfile, shutil

if len(sys.argv) < 3:
    print("[]"); sys.exit(0)

OLT_IP    = sys.argv[1]
COMMUNITY = sys.argv[2]
SNMP_PORT = sys.argv[3] if len(sys.argv) > 3 else "161"
SNMP_TARGET = "%s:%s" % (OLT_IP, SNMP_PORT) if SNMP_PORT != "161" else OLT_IP

if not OLT_IP or not COMMUNITY:
    print("[]"); sys.exit(0)

CACHE_FILE = "/tmp/pon_cache_%s.json" % OLT_IP.replace(".", "_")
LOCK_FILE  = CACHE_FILE + ".lock"
CACHE_TTL  = 300  # 5 minutos

def collect_and_save():
    OID_AUTH   = "1.3.6.1.4.1.3902.1082.500.10.2.2.3.1.14"
    OID_ONLINE = "1.3.6.1.4.1.3902.1082.500.10.2.2.3.1.15"
    OID_REASON = "1.3.6.1.4.1.3902.1082.500.10.2.3.8.1.7"
    OID_IFNAME  = "1.3.6.1.2.1.31.1.1.1.1"
    OID_IFALIAS = "1.3.6.1.2.1.31.1.1.1.18"
    OPTS = ["-v2c", "-c", COMMUNITY, "-t", "25", "-r", "1", "-Cr10", SNMP_TARGET]
    import re
    tmpdir = tempfile.mkdtemp()
    try:
        procs = {
            "auth":   subprocess.Popen(["snmpbulkwalk"] + OPTS + [OID_AUTH],
                                       stdout=open(tmpdir+"/auth","w"), stderr=subprocess.PIPE),
            "online": subprocess.Popen(["snmpbulkwalk"] + OPTS + [OID_ONLINE],
                                       stdout=open(tmpdir+"/online","w"), stderr=subprocess.PIPE),
            "reason": subprocess.Popen(["snmpbulkwalk"] + OPTS + [OID_REASON],
                                       stdout=open(tmpdir+"/reason","w"), stderr=subprocess.PIPE),
            "ifname":  subprocess.Popen(["snmpbulkwalk"] + OPTS + [OID_IFNAME],
                                       stdout=open(tmpdir+"/ifname","w"), stderr=subprocess.PIPE),
            "ifalias": subprocess.Popen(["snmpbulkwalk"] + OPTS + [OID_IFALIAS],
                                       stdout=open(tmpdir+"/ifalias","w"), stderr=subprocess.PIPE),
        }
        for p in procs.values(): p.wait()
        def rl(f):
            try: return open(tmpdir+"/"+f).read().strip().splitlines()
            except: return []
        auth_data, online_data = {}, {}
        for line in rl("auth"):
            m = re.search(r'\.(\d+)\s+=\s+\S+:\s+(\d+)', line)
            if m: auth_data[m.group(1)] = int(m.group(2))
        for line in rl("online"):
            m = re.search(r'\.(\d+)\s+=\s+\S+:\s+(\d+)', line)
            if m: online_data[m.group(1)] = int(m.group(2))
        reasons = {}
        for line in rl("reason"):
            m = re.search(r'\.7\.(\d+)\.(\d+)\s+=\s+\S+:\s+(\d+)', line)
            if not m: continue
            pon = m.group(1); val = int(m.group(3))
            if pon not in reasons:
                reasons[pon] = {"los":0,"losi":0,"lof":0,"dg":0,"unk":0}
            if   val == 2: reasons[pon]["los"]  += 1
            elif val == 3: reasons[pon]["losi"] += 1
            elif val == 4: reasons[pon]["lof"]  += 1
            elif val == 9: reasons[pon]["dg"]   += 1
            elif val == 1: reasons[pon]["unk"]  += 1
        ifname_map = {}
        for line in rl("ifname"):
            m = re.search(r'ifName\.(\d+)\s+=\s+STRING:\s+(\S+)', line)
            if m: ifname_map[m.group(1)] = m.group(2)
        ifalias_map = {}
        for line in rl("ifalias"):
            m = re.search(r'ifAlias\.(\d+)\s+=\s+STRING:\s*(.*)', line)
            if m and m.group(2).strip(): ifalias_map[m.group(1)] = m.group(2).strip()
        name_to_alias = {v: ifalias_map.get(k, "") for k, v in ifname_map.items()}

        result = []
        for idx in sorted(auth_data.keys(), key=lambda x: int(x)):
            auth   = auth_data[idx]
            online = online_data.get(idx, 0)
            i = int(idx)
            name = "gpon_%d/%d/%d" % ((i>>16)&0xFF, (i>>8)&0xFF, i&0xFF)
            r = reasons.get(idx, {"los":0,"losi":0,"lof":0,"dg":0,"unk":0})
            if auth == 0: continue
            result.append({
                "{#NETSTREAM.PON_INDEX}": idx, "{#NETSTREAM.PON_NAME}": name,
                "{#NETSTREAM.PON_DESC}": name_to_alias.get(name, ""),
                "idx": idx, "name": name, "desc": name_to_alias.get(name, ""),
                "auth": auth, "online": online, "offline": max(auth-online, 0),
                "los": r["los"], "losi": r["losi"], "lof": r["lof"],
                "dg": r["dg"], "unk": r["unk"]
            })
        if result:
            with open(CACHE_FILE + ".tmp", "w") as f:
                json.dump(result, f)
            try:
                os.rename(CACHE_FILE + ".tmp", CACHE_FILE)
            except OSError:
                try: os.remove(CACHE_FILE)
                except: pass
                os.rename(CACHE_FILE + ".tmp", CACHE_FILE)
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
        try: os.unlink(LOCK_FILE)
        except: pass

# Verificar se cache é recente
cache_age = 9999
if os.path.exists(CACHE_FILE):
    cache_age = time.time() - os.path.getmtime(CACHE_FILE)

# Disparar coleta em background se cache expirado e não há coleta em andamento
if cache_age > CACHE_TTL and not os.path.exists(LOCK_FILE):
    try:
        open(LOCK_FILE, "w").close()
        pid = os.fork()
        if pid == 0:  # processo filho
            os.setsid()
            collect_and_save()
            sys.exit(0)
    except Exception:
        try: os.unlink(LOCK_FILE)
        except: pass

# Retornar cache existente ou array vazio
if os.path.exists(CACHE_FILE):
    try:
        print(open(CACHE_FILE).read())
    except:
        print("[]")
else:
    print("[]")
