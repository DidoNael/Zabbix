#!/usr/bin/env python3
import sys, os, json, time, subprocess
OLT_IP    = sys.argv[1]
COMMUNITY = sys.argv[2]
CACHE     = "/tmp/pon_cache_%s.json" % OLT_IP.replace(".", "_")
if not os.path.exists(CACHE) or (time.time() - os.path.getmtime(CACHE)) > 300:
    subprocess.Popen(["python3","/usr/lib/zabbix/externalscripts/pon_status.py",OLT_IP,COMMUNITY],
                     stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
try:
    data = json.load(open(CACHE))
except:
    data = []
t = {"auth":0,"online":0,"offline":0,"los":0,"losi":0,"lof":0,"dg":0,"unk":0}
for p in data:
    for k in t: t[k] += p.get(k,0)
print(json.dumps(t))
