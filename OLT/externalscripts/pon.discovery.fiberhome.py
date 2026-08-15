#!/usr/bin/env python3
import sys, os, json, time, subprocess

OLT_IP    = sys.argv[1]
COMMUNITY = sys.argv[2]
CACHE_FILE = "/tmp/pon_cache_fh_%s.json" % OLT_IP.replace(".", "_")
CACHE_TTL  = 300

# Dispara coleta em background se cache ausente/velho
if not os.path.exists(CACHE_FILE) or (time.time() - os.path.getmtime(CACHE_FILE)) > CACHE_TTL:
    subprocess.Popen(
        ["python3", "/usr/lib/zabbix/externalscripts/pon.status.fiberhome.py", OLT_IP, COMMUNITY],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )

try:
    with open(CACHE_FILE) as f:
        data = json.load(f)
except Exception:
    data = []

lld = [
    {"{#NETSTREAM.PON_INDEX}": str(p["idx"]), "{#NETSTREAM.PON_NAME}": str(p["name"])}
    for p in data if p.get("auth", 0) > 0
]
print(json.dumps({"data": lld}))
