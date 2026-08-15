#!/usr/bin/env python3
import sys, os, json, time, subprocess, tempfile, shutil, re

if len(sys.argv) < 3:
    print("[]"); sys.exit(0)

OLT_IP    = sys.argv[1]
COMMUNITY = sys.argv[2]

if not OLT_IP or not COMMUNITY:
    print("[]"); sys.exit(0)

CACHE_FILE = "/tmp/pon_cache_hw_%s.json" % OLT_IP.replace(".", "_")
LOCK_FILE  = CACHE_FILE + ".lock"
CACHE_TTL  = 300

def collect_and_save():
    OID_ONLINE  = "1.3.6.1.4.1.2011.6.128.1.1.2.21.1.16"
    OID_AUTH    = "1.3.6.1.4.1.2011.6.128.1.1.2.43.1.2"
    OID_IFDESCR = "1.3.6.1.2.1.2.2.1.2"
    OPTS = ["-v2c", "-c", COMMUNITY, "-t", "25", "-r", "1", "-Cn0", "-Cr100", OLT_IP]
    tmpdir = tempfile.mkdtemp()
    try:
        procs = {
            "online":  subprocess.Popen(["snmpbulkwalk"] + OPTS + [OID_ONLINE],
                                        stdout=open(tmpdir+"/online","w"), stderr=subprocess.PIPE),
            "auth":    subprocess.Popen(["snmpbulkwalk"] + OPTS + [OID_AUTH],
                                        stdout=open(tmpdir+"/auth","w"), stderr=subprocess.PIPE),
            "ifdescr": subprocess.Popen(["snmpbulkwalk"] + OPTS + [OID_IFDESCR],
                                        stdout=open(tmpdir+"/ifdescr","w"), stderr=subprocess.PIPE),
        }
        for p in procs.values(): p.wait()

        def rl(f):
            try: return open(tmpdir+"/"+f).read().strip().splitlines()
            except: return []

        pon_names = {}
        for line in rl("ifdescr"):
            m = re.search(r"ifDescr\.(\d+).*GPON_UNI\s+([\d/]+)", line)
            if m:
                pon_names[m.group(1)] = "gpon_" + m.group(2)

        online_data = {}
        for line in rl("online"):
            m = re.search(r"\.16\.(\d+)\s+=\s+INTEGER:\s+(\d+)", line)
            if m: online_data[m.group(1)] = int(m.group(2))

        from collections import defaultdict
        auth_count = defaultdict(int)
        for line in rl("auth"):
            m = re.search(r"\.43\.1\.2\.(\d+)\.\d+\s+=\s+INTEGER:", line)
            if m: auth_count[m.group(1)] += 1

        result = []
        for pon_idx in sorted(pon_names.keys(), key=lambda x: int(x)):
            name   = pon_names[pon_idx]
            online = online_data.get(pon_idx, 0)
            auth   = auth_count.get(pon_idx, 0)
            if auth == 0:
                auth = online
            if auth == 0 and online == 0:
                continue
            offline = max(auth - online, 0)
            result.append({
                "{#NETSTREAM.PON_INDEX}": pon_idx,
                "{#NETSTREAM.PON_NAME}":  name,
                "idx":     pon_idx,
                "name":    name,
                "auth":    auth,
                "online":  online,
                "offline": offline,
                "los":     0,
                "losi":    0,
                "lof":     0,
                "dg":      0,
                "unk":     offline,
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

cache_age = 9999
if os.path.exists(CACHE_FILE):
    cache_age = time.time() - os.path.getmtime(CACHE_FILE)

if cache_age > CACHE_TTL and not os.path.exists(LOCK_FILE):
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
    try: print(open(CACHE_FILE).read())
    except: print("[]")
else:
    print("[]")
