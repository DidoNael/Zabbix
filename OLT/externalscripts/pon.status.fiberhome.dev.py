#!/usr/bin/env python3
import sys, os, json, time, subprocess, tempfile, shutil, re

if len(sys.argv) < 3:
    print("[]"); sys.exit(0)

OLT_IP    = sys.argv[1]
COMMUNITY = sys.argv[2]
SNMP_PORT = sys.argv[3] if len(sys.argv) > 3 else "161"
SNMP_TARGET = "%s:%s" % (OLT_IP, SNMP_PORT) if SNMP_PORT != "161" else OLT_IP

if not OLT_IP or not COMMUNITY:
    print("[]"); sys.exit(0)

# Cache DEV isolado — nunca compartilha com o script de produção
CACHE_FILE = "/tmp/pon_cache_fh_dev_%s.json" % OLT_IP.replace(".", "_")
LOCK_FILE  = CACHE_FILE + ".lock"
CACHE_TTL  = 60

def collect_and_save():
    # ONU state table: .11 = state (1=online, 2=dyingGasp, 3=LOS/offline, 0=unknown)
    OID_STATE = "1.3.6.1.4.1.5875.800.3.10.1.1.11"
    # PON names via ifDescr (filter "PON ")
    OID_IFDESCR = "1.3.6.1.2.1.2.2.1.2"
    OPTS = ["-v2c", "-c", COMMUNITY, "-t", "25", "-r", "1", "-Cn0", "-Cr100", SNMP_TARGET]
    tmpdir = tempfile.mkdtemp()
    try:
        procs = {
            "state":  subprocess.Popen(["snmpbulkwalk"] + OPTS + [OID_STATE],
                                       stdout=open(tmpdir+"/state","w"), stderr=subprocess.PIPE),
            "ifdescr": subprocess.Popen(["snmpbulkwalk"] + OPTS + [OID_IFDESCR],
                                        stdout=open(tmpdir+"/ifdescr","w"), stderr=subprocess.PIPE),
        }
        for p in procs.values(): p.wait()

        def rl(f):
            try: return open(tmpdir+"/"+f).read().strip().splitlines()
            except: return []

        # Mapear ifIndex -> nome PON (ex: "PON 11/1")
        pon_names = {}
        for line in rl("ifdescr"):
            m = re.search(r'ifDescr\.(\d+)\s*=\s*STRING:\s*(.+)', line)
            if m and "PON " in m.group(2):
                pon_names[m.group(1)] = m.group(2).strip()

        # Contar ONUs por PON e por estado
        pon_counts = {}
        for line in rl("state"):
            m = re.search(r'\.11\.(\d+)\.(\d+)\s*=\s*INTEGER:\s*(\d+)', line)
            if not m:
                continue
            pon_idx, onu_idx, state = m.group(1), m.group(2), int(m.group(3))
            if pon_idx not in pon_counts:
                pon_counts[pon_idx] = {"auth":0,"online":0,"offline":0,"dg":0,"los":0,"lof":0,"losi":0,"unk":0}
            c = pon_counts[pon_idx]
            c["auth"] += 1
            if   state == 1: c["online"] += 1
            elif state == 2: c["offline"] += 1; c["dg"]  += 1
            elif state == 3: c["offline"] += 1; c["los"] += 1
            else:            c["offline"] += 1; c["unk"] += 1

        result = []
        for pon_idx, c in sorted(pon_counts.items(), key=lambda x: int(x[0])):
            name = pon_names.get(pon_idx, "pon_%s" % pon_idx)
            result.append({
                "idx": pon_idx, "name": name, "snmp_idx": int(pon_idx),
                "auth": c["auth"], "online": c["online"], "offline": c["offline"],
                "dg": c["dg"], "los": c["los"], "lof": c["lof"],
                "losi": c["losi"], "unk": c["unk"],
            })

        if result:
            tmp = CACHE_FILE + ".tmp"
            with open(tmp, "w") as f:
                json.dump(result, f)
            try:
                os.rename(tmp, CACHE_FILE)
            except OSError:
                try: os.remove(CACHE_FILE)
                except: pass
                os.rename(tmp, CACHE_FILE)
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
        try: os.unlink(LOCK_FILE)
        except: pass


def _cache_age(path):
    if os.path.exists(path):
        return time.time() - os.path.getmtime(path)
    return 9999

age  = _cache_age(CACHE_FILE)
lock = _cache_age(LOCK_FILE)

if age > CACHE_TTL and (not os.path.exists(LOCK_FILE) or lock > 180):
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

if os.path.exists(CACHE_FILE):
    try:
        print(open(CACHE_FILE).read())
    except:
        print("[]")
else:
    print("[]")
