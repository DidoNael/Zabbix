#!/usr/bin/env python3
import sys, os, json, time, subprocess, tempfile, shutil, re

if len(sys.argv) < 3:
    print("[]"); sys.exit(0)

OLT_IP    = sys.argv[1]
COMMUNITY = sys.argv[2]

if not OLT_IP or not COMMUNITY:
    print("[]"); sys.exit(0)

CACHE_FILE = "/tmp/pon_cache_fh_%s.json" % OLT_IP.replace(".", "_")
LOCK_FILE  = CACHE_FILE + ".lock"
CACHE_TTL  = 300

def collect_and_save():
    # ONU state table: .11 = state (1=online, 2=dyingGasp, 3=LOS/offline, 0=unknown)
    OID_STATE = "1.3.6.1.4.1.5875.800.3.10.1.1.11"
    # PON names via ifDescr (filter "PON ")
    OID_IFDESCR = "1.3.6.1.2.1.2.2.1.2"
    OPTS = ["-v2c", "-c", COMMUNITY, "-t", "25", "-r", "1", "-Cn0", "-Cr100", OLT_IP]
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
            m = re.search(r'\.2\.1\.2\.(\d+)\s+=\s+STRING:\s+"(PON\s+\S+)"', line)
            if m:
                pon_names[int(m.group(1))] = m.group(2).replace(" ", "_").lower()

        # Derivar nome PON a partir do ifIndex do ONU:
        # slot = idx // 33554432, pon_num = (idx % 33554432) // 524288
        # PON ifIndex = (idx // 524288) * 524288
        from collections import defaultdict
        pons = defaultdict(lambda: {"online":0,"dg":0,"los":0,"unk":0,"auth":0,"name":""})

        for line in rl("state"):
            m = re.search(r'\.11\.(\d+)\s+=\s+INTEGER:\s+(\d+)', line)
            if not m: continue
            idx = int(m.group(1))
            state = int(m.group(2))
            pon_idx = (idx // 524288) * 524288
            # Nome do PON
            if not pons[pon_idx]["name"]:
                name = pon_names.get(pon_idx)
                if not name:
                    slot = idx // 33554432
                    pon_num = (idx % 33554432) // 524288
                    name = "pon_%d/%d" % (slot, pon_num)
                pons[pon_idx]["name"] = name
            pons[pon_idx]["auth"] += 1
            if   state == 1: pons[pon_idx]["online"] += 1
            elif state == 2: pons[pon_idx]["dg"]     += 1
            elif state == 3: pons[pon_idx]["los"]    += 1
            else:            pons[pon_idx]["unk"]    += 1

        result = []
        for pon_idx in sorted(pons.keys()):
            p = pons[pon_idx]
            if p["auth"] == 0:
                continue
            offline = p["auth"] - p["online"]
            name = p["name"]
            result.append({
                "{#NETSTREAM.PON_INDEX}": str(pon_idx),
                "{#NETSTREAM.PON_NAME}":  name,
                "idx":     str(pon_idx),
                "name":    name,
                "auth":    p["auth"],
                "online":  p["online"],
                "offline": offline,
                "los":     p["los"],
                "losi":    0,
                "lof":     0,
                "dg":      p["dg"],
                "unk":     p["unk"],
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

# Cache pattern
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
