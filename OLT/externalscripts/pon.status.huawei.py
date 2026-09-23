#!/usr/bin/env python3
import sys, os, json, time, subprocess, tempfile, shutil, re
from collections import defaultdict

if len(sys.argv) < 3:
    print("[]"); sys.exit(0)

OLT_IP    = sys.argv[1]
COMMUNITY = sys.argv[2]
SNMP_PORT = sys.argv[3] if len(sys.argv) > 3 else "161"
SNMP_TARGET = "%s:%s" % (OLT_IP, SNMP_PORT) if SNMP_PORT != "161" else OLT_IP

if not OLT_IP or not COMMUNITY:
    print("[]"); sys.exit(0)

CACHE_FILE   = "/tmp/pon_cache_hw_%s.json" % OLT_IP.replace(".", "_")
CACHE_BACKUP = "/var/lib/zabbix/pon_cache_bak/" + os.path.basename(CACHE_FILE) + ".bak"
LOCK_FILE    = CACHE_FILE + ".lock"
CACHE_TTL    = 60

def collect_and_save():
    # hwGponDeviceOntControlRunStatus: 1=online 2=offline — ALL provisioned ONUs
    # (.21.1.16 retorna total provisionado, não online — não usar para online count)
    OID_RUN_STATUS = "1.3.6.1.4.1.2011.6.128.1.1.2.46.1.15"
    # hwGponDeviceOntControlLastDownCause: 1=LOS 2=LOSi 3=LOFi 4=LOFi 9=SFi 13=DyingGasp
    OID_LAST_CAUSE = "1.3.6.1.4.1.2011.6.128.1.1.2.46.1.24"
    OID_IFDESCR    = "1.3.6.1.2.1.2.2.1.2"
    OID_IFNAME     = "1.3.6.1.2.1.31.1.1.1.1"
    OPTS = ["-v2c", "-c", COMMUNITY, "-t", "25", "-r", "1", "-Cn0", "-Cr100", SNMP_TARGET]
    tmpdir = tempfile.mkdtemp()
    try:
        procs = {
            "run_status": subprocess.Popen(["snmpbulkwalk"] + OPTS + [OID_RUN_STATUS],
                                           stdout=open(tmpdir+"/run_status","w"), stderr=subprocess.PIPE),
            "last_cause": subprocess.Popen(["snmpbulkwalk"] + OPTS + [OID_LAST_CAUSE],
                                           stdout=open(tmpdir+"/last_cause","w"), stderr=subprocess.PIPE),
            "ifdescr":    subprocess.Popen(["snmpbulkwalk"] + OPTS + [OID_IFDESCR],
                                           stdout=open(tmpdir+"/ifdescr","w"), stderr=subprocess.PIPE),
            "ifname":     subprocess.Popen(["snmpbulkwalk"] + OPTS + [OID_IFNAME],
                                           stdout=open(tmpdir+"/ifname","w"), stderr=subprocess.PIPE),
        }
        for p in procs.values(): p.wait()

        def rl(f):
            try: return open(tmpdir+"/"+f).read().strip().splitlines()
            except: return []

        ifname_map = {}
        for line in rl("ifname"):
            m = re.search(r"ifName\.(\d+)\s+=\s+STRING:\s+(.+)", line)
            if m:
                ifname_map[m.group(1)] = m.group(2).strip()

        pon_names = {}
        for line in rl("ifdescr"):
            m = re.search(r"ifDescr\.(\d+).*GPON_UNI(?:\s+([\d/]+))?", line)
            if m:
                if m.group(2):
                    pon_names[m.group(1)] = "gpon_" + m.group(2)
                else:
                    idx = m.group(1)
                    ifname = ifname_map.get(idx, "")
                    port_m = re.search(r"([\d]+/[\d]+/[\d]+)$", ifname)
                    if port_m:
                        pon_names[idx] = "gpon_" + port_m.group(1)
                    else:
                        i = int(idx)
                        slot = (i >> 16) & 0xFF
                        port = (i >> 8) & 0xFF
                        pon_names[idx] = "gpon_0/%d/%d" % (slot, port)

        run_status = defaultdict(dict)  # pon_idx -> {onu_id: state}
        for line in rl("run_status"):
            m = re.search(r"\.46\.1\.15\.(\d+)\.(\d+)\s*=\s*(?:INTEGER:\s*)?(\d+)", line)
            if m:
                run_status[m.group(1)][m.group(2)] = int(m.group(3))

        last_cause = defaultdict(dict)  # pon_idx -> {onu_id: cause}
        for line in rl("last_cause"):
            m = re.search(r"\.46\.1\.24\.(\d+)\.(\d+)\s*=\s*(?:INTEGER:\s*)?(\d+)", line)
            if m:
                last_cause[m.group(1)][m.group(2)] = int(m.group(3))

        result = []
        for pon_idx in sorted(pon_names.keys(), key=lambda x: int(x)):
            name     = pon_names[pon_idx]
            statuses = run_status.get(pon_idx, {})
            causes   = last_cause.get(pon_idx, {})
            auth     = len(statuses)

            if auth == 0:
                continue

            online_count  = 0
            offline_count = 0
            dg = los = losi = lof = 0
            for onu_id, state in statuses.items():
                if state == 1:
                    online_count += 1
                else:
                    offline_count += 1
                    cause = causes.get(onu_id, 0)
                    if cause == 13:
                        dg += 1
                    elif cause == 1:
                        los += 1
                    elif cause == 2:
                        losi += 1
                    elif cause in (3, 4):
                        lof += 1

            unk = max(offline_count - dg - los - losi - lof, 0)

            result.append({
                "{#NETSTREAM.PON_INDEX}": pon_idx,
                "{#NETSTREAM.PON_NAME}":  name,
                "{#NETSTREAM.PON_DESC}": "",
                "idx":     pon_idx, "desc": "",
                "name":    name,
                "auth":    auth,
                "online":  online_count,
                "offline": offline_count,
                "los":     los,
                "losi":    losi,
                "lof":     lof,
                "dg":      dg,
                "unk":     unk,
            })

        if result:
            alias_oids = ["1.3.6.1.2.1.31.1.1.1.18." + str(p["idx"]) for p in result]
            get_proc = subprocess.run(
                ["snmpget", "-v2c", "-c", COMMUNITY, "-t", "20", "-r", "1",
                 "-OQe", SNMP_TARGET] + alias_oids,
                capture_output=True, text=True
            )
            alias_map = {}
            for line in get_proc.stdout.splitlines():
                m = re.search(r'ifAlias\.(\d+)\s*=\s*(.+)', line)
                if m:
                    val = m.group(2).strip().strip('"').strip("'")
                    if (val and val != '""' and val != "''"
                            and not val.lower().startswith("no such")
                            and not val.lower().startswith("no response")):
                        alias_map[m.group(1)] = val
            for p in result:
                p["desc"] = alias_map.get(str(p["idx"]), "")

            with open(CACHE_FILE + ".tmp", "w") as f:
                json.dump(result, f)
            try:
                os.rename(CACHE_FILE + ".tmp", CACHE_FILE)
            except OSError:
                try: os.remove(CACHE_FILE)
                except: pass
                os.rename(CACHE_FILE + ".tmp", CACHE_FILE)
            try:
                shutil.copy2(CACHE_FILE, CACHE_BACKUP)
            except Exception:
                pass
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
        try: os.unlink(LOCK_FILE)
        except: pass

cache_age = 9999
if os.path.exists(CACHE_FILE):
    cache_age = time.time() - os.path.getmtime(CACHE_FILE)

lock_age = time.time() - os.path.getmtime(LOCK_FILE) if os.path.exists(LOCK_FILE) else 9999
if cache_age > CACHE_TTL and (not os.path.exists(LOCK_FILE) or lock_age > 180):
    try:
        open(LOCK_FILE, "w").close()
        pid = os.fork()
        if pid == 0:
            os.setsid()
            devnull = os.open('/dev/null', os.O_RDWR)
            for fd in (0, 1, 2):
                try: os.dup2(devnull, fd)
                except: pass
            if devnull > 2: os.close(devnull)
            collect_and_save()
            sys.exit(0)
    except Exception:
        try: os.unlink(LOCK_FILE)
        except: pass

if os.path.exists(CACHE_FILE):
    try: print(open(CACHE_FILE).read())
    except: print("[]")
elif os.path.exists(CACHE_BACKUP):
    try: print(open(CACHE_BACKUP).read())
    except: print("[]")
else:
    print("[]")
